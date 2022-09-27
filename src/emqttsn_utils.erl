-module(emqttsn_utils).

-include("config.hrl").
-include("logger.hrl").
-include("version.hrl").

-export([prev_packet_id/1, next_packet_id/1, store_msg/4, get_msg/2, get_msg/1,
         get_topic_id/1, store_gw/2, get_gw/2, get_gw/1, first_gw/1, next_gw/2,
         default_msg_handler/2]).

%%--------------------------------------------------------------------
%% gateway management lower utilities
%%--------------------------------------------------------------------

-spec table_format(string(), gateway) -> atom().
table_format(TableName, SubName) ->
  case SubName of
    gateway ->
      list_to_atom(TableName ++ "_gateway")
  end.

-spec init_global_store(string()) -> ok.
init_global_store(TableName) ->
  Formatter = fun(X) -> table_format(TableName, X) end,
  Exist = ets:whereis(Formatter(gateway)),
  if Exist =:= undefined ->
       _ = ets:new(Formatter(gateway), [{keypos, #gw_info.id}, named_table, private, set])
  end,
  ok.

%%--------------------------------------------------------------------
%% message management lower utilities
%%--------------------------------------------------------------------

-spec default_msg_handler(topic_id(), string()) -> ok.
default_msg_handler(TopicId, Msg) ->
  ?LOG(info, "new message", #{topic_id => TopicId, message => Msg}),
  ok.

-spec msg_handler_recall([msg_handler()], topic_id(), string()) -> ok.
msg_handler_recall(Handlers, TopicId, Msg) ->
  lists:foreach(fun(Handler) -> Handler(TopicId, Msg) end, Handlers),
  ok.

-spec store_msg_async(dict:dict(topic_id(), queue:queue()),
                      dict:dict(topic_id(), pos_integer()),
                      topic_id(),
                      pos_integer(),
                      string()) ->
                       {dict:dict(topic_id(), queue:queue()), dict:dict(topic_id(), pos_integer())}.
store_msg_async(MsgManager, MsgCounter, TopicId, TopicMax, Msg) ->
  case {dict:find(TopicId, MsgCounter), dict:find(TopicId, MsgManager)} of
    {{ok, OldNum}, {ok, TopicManager}} when OldNum < TopicMax ->
      Num = OldNum + 1,
      NewManager = queue:in(Msg, TopicManager);
    {{ok, OldNum}, {ok, TopicManager}} when OldNum >= TopicMax ->
      Num = OldNum,
      {{value, _Item}, TmpManager} = queue:out(TopicManager),
      NewManager = queue:in(Msg, TmpManager);
    {error, error} ->
      Num = 0,
      NewManager = queue:from_list([Msg])
  end,
  NewMsgCounter = dict:append(TopicId, Num, MsgCounter),
  NewMsgManager = dict:append(TopicId, NewManager, MsgManager),
  {NewMsgManager, NewMsgCounter}.

-spec refresh_msg_manager(topic_id(),
                          dict:dict(topic_id(), queue:queue()),
                          dict:dict(topic_id(), pos_integer())) ->
                           {dict:dict(topic_id(), queue:queue()),
                            dict:dict(topic_id(), pos_integer()),
                            [string()]}.
refresh_msg_manager(TopicId, MsgManager, MsgCounter) ->
  case dict:find(TopicId, MsgManager) of
    {ok, Manager} ->
      MsgManager = dict:erase(TopicId, MsgManager),
      MsgCounter = dict:erase(TopicId, MsgCounter),
      {MsgManager, MsgCounter, queue:to_list(Manager)};
    error ->
      {MsgManager, MsgCounter, []}
  end.

%%--------------------------------------------------------------------
%% message management API
%%--------------------------------------------------------------------
-spec store_msg(state(), topic_id(), pos_integer(), string()) -> state().
store_msg(State, TopicId, TopicMax, Msg) ->
  #state{msg_manager = MsgManager,
         msg_counter = MsgCounter,
         config = Config} =
    State,
  #config{msg_handler = Handlers} = Config,
  case Handlers of
    [] ->
      {NewMsgManager, NewMsgCounter} =
        store_msg_async(MsgManager, MsgCounter, TopicId, TopicMax, Msg),
      State#state{msg_manager = NewMsgManager, msg_counter = NewMsgCounter};
    _ ->
      msg_handler_recall(Handlers, TopicId, Msg),
      State#state{msg_manager = MsgManager, msg_counter = MsgCounter}
  end.
  

-spec get_one_msg(emqttsn:client_pid(), topic_id()) ->
               {ok, dict:dict(topic_id(), [string()])} | invalid.
get_one_msg(Client, TopicId) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager,
         msg_counter = MsgCounter,
         config = Config} =
    State,
  #config{msg_handler = Handlers} = Config,
  if Handlers =/= [] ->
       invalid;
     Handlers =:= [] ->
       {NewMsgManager, NewMsgCounter, Messages} = refresh_msg_manager(TopicId, MsgManager, MsgCounter),
       gen_statem:cast(Client, {reset_msg, NewMsgManager, NewMsgCounter}),
       Map = dict:new(),
       {ok, dict:store(TopicId, Messages, Map)}
  end.

-spec get_msg(emqttsn:client_pid(), [topic_id()]) ->
  {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(Client, TopicIds) ->
  NewDict = dict:new(),
  get_msg(Client, TopicIds, NewDict).

-spec get_msg(emqttsn:client_pid(), [topic_id()], dict:dict(topic_id(), [string()])) ->
  {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(_Client, [], Ret) ->
  {ok, Ret};
get_msg(Client, [TopicId | TopicIds], Ret) ->
  case get_one_msg(Client, TopicId) of
    invalid ->
      invalid;
    {ok, MsgOfTopicId} ->
      NewRet = dict:merge(fun(_K, V1, _V2) -> V1 end, MsgOfTopicId, Ret),
      get_msg(Client, TopicIds, NewRet)
  end.

-spec get_msg(emqttsn:client_pid()) -> {ok, dict:dict(topic_id(), [string()])} | invalid.
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
  case ets:lookup_element(NameGW, GWId, 1) of
    {_, #gw_info{from = OldSRC}} when SRC < OldSRC ->
      false;
    _ ->
      ets:insert(NameGW, {GWId, GWInfo}),
      true
  end.

-spec get_gw(string(), bin_1_byte()) -> #gw_info{} | none.
get_gw(TableName, GWId) ->
  NameGW = table_format(TableName, gateway),
  case ets:lookup_element(NameGW, GWId, 1) of
    {GWId, GWInfo = #gw_info{}} ->
      GWInfo;
    _ ->
      none
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
    '$end_of_table' ->
      none;
    Key ->
      {_, GWInfo} = ets:lookup_element(NameGW, Key, 1),
      GWInfo
  end.

-spec next_gw(string(), bitstring()) -> #gw_info{} | none.
next_gw(TableName, GWId) ->
  NameGW = table_format(TableName, gateway),
  NextKey = ets:next(NameGW, GWId),
  FirstKey = ets:first(NameGW),
  case {NextKey, FirstKey} of
    {'$end_of_table', '$end_of_table'} ->
      none;
    {'$end_of_table', Key} ->
      {_, GWInfo} = ets:lookup_element(NameGW, Key, 1),
      GWInfo;
    {Key, _} ->
      {_, GWInfo} = ets:lookup_element(NameGW, Key, 1),
      GWInfo
  end.

%%--------------------------------------------------------------------
%% packet_id generator for state machine
%%--------------------------------------------------------------------

-spec prev_packet_id(packet_id()) -> packet_id().
prev_packet_id(1) ->
  ?MAX_PACKET_ID;
prev_packet_id(Id) ->
  Id - 1.

-spec next_packet_id(packet_id()) -> packet_id().
next_packet_id(?MAX_PACKET_ID) ->
  1;
next_packet_id(Id) ->
  Id + 1.
