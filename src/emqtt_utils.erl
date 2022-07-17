-module(emqtt_utils).

-include("config.hrl").
-include("logger.hrl").
-include("storage.hrl").

-export([store_socket/1, get_socket/0, store_option/1, get_option/0,
         prev_packet_id/1, next_packet_id/1, store_msg/2, get_msg/0,
         get_msg/1, store_gw/1, get_gw/0, get_gw/1, first_gw/0, next_gw/1]).

init_global_store() ->
  Exist = ets:whereis(status),
  if Exist == undefined ->
    ets:new(status, [named_table, private, set]),
    ets:new(message, [{keypos, #msg_store.uid}, named_table, private, set]),
    ets:new(msg_number_topic, [{keypos, #msg_uid.topic_id}, named_table, private, set]),
    ets:new(msg_oldest, [{keypos, #msg_uid.topic_id}, named_table, private, set]),
    ets:new(gateway, [{keypos, #gw_info.id}, named_table, private, set])
  end.

-spec store_socket(inet:socket()) -> ok.
store_socket(Socket) ->
  init_global_store(),
  ets:insert(status, {socket, Socket}),
  ok.

-spec get_socket() -> inet:socket() | none.
get_socket() ->
  case ets:lookup(status, socket) of
    {socket, Socket} -> Socket;
    _ -> ?EASY_LOG(error, "no socket created or stored"),
      none
  end.


-spec store_option(options()) -> ok.
store_option(Option) ->
  init_global_store(),
  ets:insert(status, {option, Option}),
  ok.

-spec get_option() -> options() | none.
get_option() ->
  case ets:lookup(status, option) of
    {option, Option} -> Option;
    _ -> ?EASY_LOG(error, "no option created or stored"),
      none
  end.



-spec store_msg(topic_id(), bitstring()) -> ok.
store_msg(TopicId, Msg) ->
  init_global_store(),
  #option{max_message_each_topic = TopicMax} = emqtt_utils:get_option(),
  Now = erlang:timestamp(),
  case {ets:lookup(msg_number_topic, TopicId), ets:lookup(msg_oldest, TopicId)} of
    {[], []} ->
      ets:insert(message, #msg_store{uid = #msg_uid{topic_id = TopicId, index = 1},
                                     timestamp = Now, data = Msg}),
      ets:insert(msg_number_topic, #msg_uid{topic_id = TopicId, index = 1}),
      ets:insert(msg_oldest, #msg_uid{topic_id = TopicId, index = 1});
    {{TopicId, Number}, {TopicId, Oldest}} when Number == TopicMax ->
      ets:insert(message, #msg_store{uid = #msg_uid{topic_id = TopicId, index = Oldest},
                                     timestamp = Now, data = Msg}),
      ets:insert(msg_oldest, #msg_uid{topic_id = TopicId, index = next_msg_id(Oldest, TopicMax)});
    {{TopicId, Number}, {TopicId, Oldest}} ->
      ets:insert(message, #msg_store{uid = #msg_uid{topic_id = TopicId, index = next_msg_id(Number, TopicMax)},
                                     timestamp = Now, data = Msg}),
      ets:insert(msg_number_topic, #msg_uid{topic_id = TopicId, index = next_msg_id(Number, TopicMax)})
  end,
  ok.

-spec get_msg(topic_id() | [topic_id()]) -> [#msg_collect{}].
get_msg(TopicId) when is_integer(TopicId) ->
  Result = ets:select(message, [{#msg_store{uid = #msg_uid{topic_id = '$1', _ = '_'}, timestamp = '$2', data = '$3'},
                                 [{'=:=', '$1', TopicId}],
                                 [#msg_collect{topic_id = '$1', timestamp = '$2', data = '$3'}]}]),
  case Result of
    '$end_of_table' -> [];
    Other when is_list(Other) ->
      lists:sort(fun(#msg_collect{timestamp = TA}, #msg_collect{timestamp = TB}) -> TA =< TB end, Other)
  end.

get_msg(TopicIds) when is_list(TopicIds) ->
  SubStatements = [{'=:=', '$1', TopicId} || TopicId <- TopicIds],
  Result = ets:select(message, [{#msg_store{uid = #msg_uid{topic_id = '$1', _ = '_'}, timestamp = '$2', data = '$3'},
                                 [{'orelse', list_to_tuple(SubStatements)}],
                                 [#msg_collect{topic_id = '$1', timestamp = '$2', data = '$3'}]}]),
  case Result of
    '$end_of_table' -> [];
    Other when is_list(Other) ->
      lists:sort(fun(#msg_collect{timestamp = TA}, #msg_collect{timestamp = TB}) -> TA =< TB end, Other)
  end.

-spec get_msg() -> [#msg_collect{}].
get_msg() ->
  Result = ets:select(message, [{#msg_store{uid = #msg_uid{topic_id = '$1', _ = '_'}, timestamp = '$2', data = '$3'},
                                 [], [#msg_collect{topic_id = '$1', timestamp = '$2', data = '$3'}]}]),
  case Result of
    '$end_of_table' -> [];
    Other when is_list(Other) ->
      lists:sort(fun(#msg_collect{timestamp = TA}, #msg_collect{timestamp = TB}) -> TA =< TB end, Other)
  end.

%%--------------------------------------------------------------------
%% gateway information storage manager
%%--------------------------------------------------------------------
-spec store_gw(#gw_info{}) -> boolean().
store_gw(GWInfo = #gw_info{id = GWId, from = SRC}) ->
  case ets:lookup(gateway, GWId) of
    #gw_info{from = OldSRC} when SRC < OldSRC -> false;
    _ ->
      ets:insert(gateway, GWInfo),
      true
  end.

-spec get_gw(bitstring()) -> #gw_info{} | none.
get_gw(GWId) ->
  case ets:lookup(gateway, GWId) of
    GWInfo = #gw_info{} -> GWInfo;
    _ -> none
  end.

-spec get_gw() -> [#gw_info{}].
get_gw() ->
  ets:tab2list(gateway).

-spec first_gw() -> #gw_info{} | none.
first_gw() ->
  NextKey = ets:first(gateway),
  case NextKey of
    '$end_of_table' -> none;
    Key -> ets:lookup(gateway, Key)
  end.

-spec next_gw() -> #gw_info{} | none.
next_gw(GWId) ->
  NextKey = ets:next(gateway, GWId),
  FirstKey = ets:first(gateway),
  case {NextKey, FirstKey} of
    {'$end_of_table', '$end_of_table'} -> none;
    {'$end_of_table', Key} -> ets:lookup(gateway, Key);
    {Key, _} -> ets:lookup(gateway, Key)
  end.
%%--------------------------------------------------------------------
%% packet_id generator for state machine
%%--------------------------------------------------------------------

-spec prev_packet_id(packet_id()) -> packet_id().
prev_packet_id(1)  -> ?MAX_PACKET_ID;
prev_packet_id(Id) -> Id - 1.

-spec next_packet_id(packet_id()) -> packet_id().
next_packet_id(?MAX_PACKET_ID) -> 1;
next_packet_id(Id)             -> Id + 1.

%%--------------------------------------------------------------------
%% message_id generator for storage
%%--------------------------------------------------------------------

-spec next_msg_id(packet_id(), pos_integer()) -> pos_integer().
next_msg_id(Id, TopicMax) ->
  case Id of
    TopicMax -> 1;
    _ -> Id + 1
  end.