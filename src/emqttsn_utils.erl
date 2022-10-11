-module(emqttsn_utils).

-include("config.hrl").
-include("packet.hrl").
-include("version.hrl").
-include("logger.hrl").

-export([next_packet_id/1, store_msg/4, get_msg/2, get_msg/1, get_one_topic_msg/3,
         get_topic_id/3, get_all_topic_id/1, get_topic_id_from_name/3, store_gw/2, get_gw/2,
         get_gw/1, first_gw/1, next_gw/2, default_msg_handler/2]).

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
  ?LOGP(notice, "new message: ~p, topic id: ~p", [TopicId, Msg]),
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
    {{ok, OldNum}, {ok, MsgQueue}} when OldNum < TopicMax ->
      Num = OldNum + 1,
      NewQueue = queue:in(Msg, MsgQueue);
    {{ok, OldNum}, {ok, MsgQueue}} when OldNum >= TopicMax ->
      Num = OldNum,
      {{value, _Item}, TmpQueue} = queue:out(MsgQueue),
      NewQueue = queue:in(Msg, TmpQueue);
    {error, error} ->
      Num = 0,
      NewQueue = queue:from_list([Msg])
  end,
  NewMsgCounter = dict:store(TopicId, Num, MsgCounter),
  NewMsgManager = dict:store(TopicId, NewQueue, MsgManager),
  {NewMsgManager, NewMsgCounter}.

-spec refresh_msg_manager(topic_id(),
                          dict:dict(topic_id(), queue:queue()),
                          dict:dict(topic_id(), pos_integer())) ->
                           {dict:dict(topic_id(), queue:queue()),
                            dict:dict(topic_id(), pos_integer()),
                            [string()]}.
refresh_msg_manager(TopicId, MsgManager, MsgCounter) ->
  case dict:find(TopicId, MsgManager) of
    {ok, MsgQueue} ->
      NewMsgManager = dict:erase(TopicId, MsgManager),
      NewMsgCounter = dict:erase(TopicId, MsgCounter),
      {NewMsgManager, NewMsgCounter, queue:to_list(MsgQueue)};
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

-spec get_one_topic_msg(client(), topic_id(), boolean()) -> {ok, [string()]} | invalid.
get_one_topic_msg(Client, TopicId, Block) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager,
         msg_counter = MsgCounter,
         config = Config} =
    State,
  #config{msg_handler = Handlers} = Config,
  if Handlers =/= [] ->
       invalid;
     Handlers =:= [] ->
       {NewMsgManager, NewMsgCounter, Messages} =
         refresh_msg_manager(TopicId, MsgManager, MsgCounter),
       case {Block, Messages} of
         {false, _} ->
           gen_statem:cast(Client, {reset_msg, NewMsgManager, NewMsgCounter}),
           {ok, Messages};
         {true, []} ->
          get_one_topic_msg(Client, TopicId, true);
         {true, _} ->
           gen_statem:cast(Client, {reset_msg, NewMsgManager, NewMsgCounter}),
           {ok, Messages}
       end
  end.

-spec get_msg(client(), [topic_id()]) ->
               {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(Client, TopicIds) ->
  NewDict = dict:new(),
  get_msg(Client, TopicIds, NewDict).

-spec get_msg(client(), [topic_id()], dict:dict(topic_id(), [string()])) ->
               {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(_Client, [], Ret) ->
  {ok, Ret};
get_msg(Client, [TopicId | TopicIds], Ret) ->
  case get_one_topic_msg(Client, TopicId, false) of
    invalid ->
      invalid;
    {ok, MsgOfTopicId} ->
      NewRet = dict:merge(fun(_K, V1, _V2) -> V1 end, MsgOfTopicId, Ret),
      get_msg(Client, TopicIds, NewRet)
  end.

-spec get_msg(client()) -> {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  get_msg(Client, dict:fetch_keys(MsgManager)).

-spec get_all_topic_id(client()) -> [topic_id()].
get_all_topic_id(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  dict:fetch_keys(MsgManager).

-spec get_topic_id_from_name(client(), string(), boolean()) -> {ok, topic_id()} | none.
get_topic_id_from_name(Client, TopicName, Block) ->
  State = gen_statem:call(Client, get_state),
  #state{topic_name_id = Map} = State,
  case {Block, dict:find(TopicName, Map)} of
    {false, Ret} ->
      Ret;
    {true, {ok, TopicId}} ->
      {ok, TopicId};
    {true, error} ->
      get_topic_id_from_name(Client, TopicName, true)
  end.

%%--------------------------------------------------------------------
%% gateway management API
%%--------------------------------------------------------------------
-spec store_gw(string(), #gw_info{}) -> boolean().
store_gw(TableName, GWInfo = #gw_info{id = GWId, from = SRC}) ->
  init_global_store(TableName),
  NameGW = table_format(TableName, gateway),
  case ets:lookup(NameGW, GWId) of
    [{_, #gw_info{from = OldSRC}}] when SRC < OldSRC ->
      ?LOGP(warning, "insert into ~p for gateway id:~p failed", [TableName, GWId]),
      false;
    [] ->
      ets:insert(NameGW, GWInfo),
      ?LOGP(notice, "insert into ~p for gateway id:~p", [TableName, GWId]),
      true
  end.

-spec get_gw(string(), gw_id()) -> #gw_info{} | none.
get_gw(TableName, GWId) ->
  NameGW = table_format(TableName, gateway),
  case ets:lookup(NameGW, GWId) of
    [GWInfo = #gw_info{}] ->
      GWInfo;
    [] ->
      ?LOGP(warning, "not gateway to connect from ~p for selected gateway id:~p",
                   [TableName, GWId]),
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

-spec next_packet_id(packet_id()) -> packet_id().
next_packet_id(?MAX_PACKET_ID) ->
  1;
next_packet_id(Id) ->
  Id + 1.

-spec get_topic_id(topic_id_type(),
                   topic_id() | string(),
                   dict:dict(string(), topic_id())) ->
                    topic_id().
get_topic_id(TopicIdType, TopicIdOrName, NameMap) ->
  case TopicIdType of
    ?PRE_DEF_TOPIC_ID ->
      TopicIdOrName;
    ?TOPIC_ID ->
      TopicIdOrName;
    ?SHORT_TOPIC_NAME ->
      dict:fetch(TopicIdOrName, NameMap)
  end.

