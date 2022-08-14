-module(emqttsn_utils).

-include("config.hrl").
-include("logger.hrl").

-export([prev_packet_id/1, next_packet_id/1, store_msg/4, get_msg/2, get_msg/1, get_topic_id/1,
         store_gw/2, get_gw/2, get_gw/1, first_gw/1, next_gw/2, default_msg_handler/2]).

%%--------------------------------------------------------------------
%% gateway management lower utilities
%%--------------------------------------------------------------------

-spec table_format(string(), term) -> string().
table_format(TableName, SubName) ->
  case SubName of
    gateway -> TableName ++ "_gateway"
  end.

init_global_store(TableName) ->
  Formatter = fun(X) -> table_format(TableName, X) end,
  Exist = ets:whereis(Formatter(gateway)),
  if Exist == undefined ->
    ets:new(Formatter(gateway), [{keypos, #gw_info.id}, named_table, private, set])
  end.

%%--------------------------------------------------------------------
%% message management lower utilities
%%--------------------------------------------------------------------

-spec default_msg_handler(topic_id(), string()) -> no_return().
default_msg_handler(TopicId, Msg) ->
  ?LOG(info, "new message", {topic_id = TopicId, message = Msg}).

-spec msg_handler_recall([msg_handler()], topic_id(), string()) -> no_return().
msg_handler_recall(Handlers, TopicId, Msg) ->
  lists:foreach(fun(Handler) -> Handler(TopicId, Msg) end, Handlers).

-spec store_msg_async(dict(topic_id(), queue:queue()),
                      dict(topic_id(), pos_integer()),
                      topic_id(), pos_integer(), string()) ->
                       {dict(topic_id(), queue:queue()), dict(topic_id(), pos_integer())}.
store_msg_async(MsgManager, MsgCounter, TopicId, TopicMax, Msg) ->
  case {dict:find(TopicId, MsgCounter), dict:find(TopicId, MsgManager)} of
    {{ok, OldNum}, {ok, TopicManager}} when OldNum < TopicMax ->
      Num = OldNum + 1,
      NewManager = queue:in(Msg, TopicManager);
    {{ok, OldNum}, {ok, TopicManager}} when OldNum >= TopicMax ->
      Num = OldNum,
      {{value, _Item}, TmpManager} = queue:out(TopicManager),
      NewManager = queue:in(Msg, TmpManager);
    error ->
      Num = 0,
      NewManager = queue:from_list([Msg])
  end,
  MsgCounter = MsgCounter#{TopicId => Num},
  MsgManager = MsgManager#{TopicId => NewManager},
  {MsgManager, MsgCounter}.

-spec get_msg_recur(emqttsn:client_pid(), [topic_id()], [topic_id()])
                   -> {ok, dict(topic_id(), [string()])} | invalid.
get_msg_recur(Client, [TopicId | TopicIds], Ret) ->
  if
    TopicIds =:= [] ->
      Ret;
    TopicIds =/= [] ->
      case get_msg(Client, TopicId) of
        invalid -> invalid;
        {ok, MsgOfTopicId} ->
          Ret = dict:merge(fun(V1, _V2) -> V1 end, MsgOfTopicId, Ret),
          get_msg_recur(Client, TopicIds, Ret)

      end
  end.

-spec refresh_msg_manager(topic_id(),
                          dict(topic_id(), queue:queue()),
                          dict(topic_id(), pos_integer()))
                         -> {dict(topic_id(), queue:queue()),
                             dict(topic_id(), pos_integer()), [string()]}.
refresh_msg_manager(TopicId, MsgManager, MsgCounter) ->
  case dict:find(TopicId, MsgManager) of
    {ok, Manager} ->
      MsgManager = dict:erase(TopicId, MsgManager),
      MsgCounter = dict:erase(TopicId, MsgCounter),
      {MsgManager, MsgCounter, queue:to_list(Manager)};
    error -> {MsgManager, MsgCounter, []}
  end.

%%--------------------------------------------------------------------
%% message management API
%%--------------------------------------------------------------------
-spec store_msg(state(), topic_id(), pos_integer(), string()) -> state().
store_msg(State, TopicId, TopicMax, Msg) ->
  #state{msg_manager = MsgManager, msg_counter = MsgCounter, config = Config} = State,
  #config{msg_handler = Handlers} = Config,
  case Handlers of
    [] ->
      {MsgManager, MsgCounter} = store_msg_async(MsgManager, MsgCounter, TopicId, TopicMax, Msg);
    _ ->
      msg_handler_recall(Handlers, TopicId, Msg)
  end,
  State#{msg_manager = MsgManager, msg_counter = MsgCounter}.

-spec get_msg(emqttsn:client_pid(), topic_id() | [topic_id()]) -> {ok, dict(topic_id(), [string()])} | invalid.
get_msg(Client, TopicId) when is_integer(TopicId) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager, msg_counter = MsgCounter, config = Config} = State,
  #config{msg_handler = Handlers} = Config,
  if
    Handlers =/= [] ->
      invalid;
    Handlers =:= [] ->
      {MsgManager, MsgCounter, Messages} = refresh_msg_manager(TopicId, MsgManager, MsgCounter),
      gen_statem:cast(Client, {reset_msg, MsgManager, MsgCounter}),
      #{TopicId => Messages}
  end;

get_msg(Client, TopicIds) when is_integer(TopicIds) ->
  get_msg_recur(Client, TopicIds, []).

-spec get_msg(emqttsn:client_pid()) -> {ok, dict(topic_id(), [string()])} | invalid.
get_msg(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  get_msg(Client, dict:fetch_keys(MsgManager)).

-spec get_topic_id(emqttsn:client_pid()) -> [topic_id()].
get_topic_id(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  dict:fetch_keys(MsgManager).

%%--------------------------------------------------------------------
%% gateway management API
%%--------------------------------------------------------------------
-spec store_gw(string(), #gw_info{}) -> boolean().
store_gw(TableName, GWInfo = #gw_info{id = GWId, from = SRC}) ->
  init_global_store(TableName),
  NameGW = table_format(TableName, gateway),
  case ets:lookup(NameGW, GWId) of
    #gw_info{from = OldSRC} when SRC < OldSRC -> false;
    _ ->
      ets:insert(NameGW, GWInfo),
      true
  end.

-spec get_gw(string(), bitstring()) -> #gw_info{} | none.
get_gw(TableName, GWId) ->
  NameGW = table_format(TableName, gateway),
  case ets:lookup(NameGW, GWId) of
    GWInfo = #gw_info{} -> GWInfo;
    _ -> none
  end.

-spec get_gw(string()) -> [#gw_info{}].
get_gw(TableName) ->
  NameGW = table_format(TableName, gateway),
  ets:tab2list(NameGW).

-spec first_gw(string()) -> #gw_info{} | none.
first_gw(TableName) ->
  NameGW = table_format(TableName, gateway),
  NextKey = ets:first(NameGW),
  case NextKey of
    '$end_of_table' -> none;
    Key -> ets:lookup(NameGW, Key)
  end.

-spec next_gw(string(), bitstring()) -> #gw_info{} | none.
next_gw(TableName, GWId) ->
  NameGW = table_format(TableName, gateway),
  NextKey = ets:next(NameGW, GWId),
  FirstKey = ets:first(NameGW),
  case {NextKey, FirstKey} of
    {'$end_of_table', '$end_of_table'} -> none;
    {'$end_of_table', Key} -> ets:lookup(NameGW, Key);
    {Key, _} -> ets:lookup(NameGW, Key)
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