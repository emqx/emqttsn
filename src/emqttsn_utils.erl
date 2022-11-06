%%-------------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%-------------------------------------------------------------------------

%% @doc utility designed for message or gateway, often used with aync
%% message handle.
-module(emqttsn_utils).

%% @headerfile "emqttsn.hrl"

-include("emqttsn.hrl").
-include("logger.hrl").

-export([init_global_store/1, store_msg/4, get_msg/2, get_msg/1, get_one_topic_msg/3,
         get_all_topic_id/1, get_topic_id_from_name/3, store_gw/2, get_gw/3, get_gw/2,
         get_all_gw/2, get_all_gw/1, default_msg_handler/2]).

%%--------------------------------------------------------------------
%% gateway management lower utilities
%%--------------------------------------------------------------------

%% @doc init ets storage for gateway
%%
%% Caution: not need in most cases, if you don't
%% know about mqttsn gateway storage, do not use it.
%%
%% @param Name unique name of client, used also as client id
%%
%% @end
-spec init_global_store(string()) -> ok.
init_global_store(Name) ->
  NameGW = list_to_atom(Name),
  Exist = ets:whereis(NameGW),
  case Exist of
    undefined ->
      _ = ets:new(NameGW, [{keypos, #gw_info.id}, named_table, public, set]),
      ok;
    _ ->
      ok
  end.

%%--------------------------------------------------------------------
%% message management lower utilities
%%--------------------------------------------------------------------

%% @doc default message handler when sync handle
%%
%% Caution: not need in most cases, if you don't
%% know about message handler, do not use it.
%%
%% @param TopicId topic id of incoming message
%% @param Msg data of incoming message
%%
%% @end
-spec default_msg_handler(topic_id(), string()) -> ok.
default_msg_handler(TopicId, Msg) ->
  ?LOGP(notice, "new message: ~p, topic id: ~p", [TopicId, Msg]),
  ok.

-spec msg_handler_recall([msg_handler()], topic_id(), string()) -> ok.
msg_handler_recall(Handlers, TopicId, Msg) ->
  lists:foreach(fun(Handler) -> Handler(TopicId, Msg) end, Handlers),
  ok.

-spec store_msg_async(dict:dict(topic_id(), queue:queue()),
                      dict:dict(topic_id(), non_neg_integer()),
                      topic_id(),
                      non_neg_integer(),
                      string()) ->
                       {dict:dict(topic_id(), queue:queue()),
                        dict:dict(topic_id(), non_neg_integer())}.
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
                          dict:dict(topic_id(), non_neg_integer())) ->
                           {dict:dict(topic_id(), queue:queue()),
                            dict:dict(topic_id(), non_neg_integer()),
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

%% @doc store an message(async handler API)
%%
%% Caution: not need in most cases, if you don't
%% know about message storage, do not use it.
%%
%% @param State state data of state machine
%% @param TopicId topic id of message
%% @param TopicMax maximum number of message to stored by one topic
%% @param Msg data of message
%%
%% @end
-spec store_msg(state(), topic_id(), non_neg_integer(), string()) -> state().
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

%% @doc collect all message of a topic id(async handler API)
%%
%% @param Client the client object
%% @param TopicId topic id to fetch messages
%% @param Block whether make a block/unblock reques(wait until message is exist)
%%
%% @end
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

%% @doc collect all message of some topic id(async handler API, non-blocking)
%%
%% @param Client the client object
%% @param TopicIds array of topic id to fetch messages
%%
%% @end
-spec get_msg(client(), [topic_id()]) ->
               {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(Client, TopicIds) ->
  {ok, KVList} = get_msg(Client, TopicIds, []),
  {ok, dict:from_list(KVList)}.

-spec get_msg(client(), [topic_id()], [{topic_id(), [string()]}]) ->
               {ok, [{topic_id(), [string()]}]} | invalid.
get_msg(_Client, [], Ret) ->
  {ok, Ret};
get_msg(Client, [TopicId | TopicIds], Ret) ->
  case get_one_topic_msg(Client, TopicId, false) of
    invalid ->
      invalid;
    {ok, MsgOfTopicId} ->
      get_msg(Client, TopicIds, Ret ++ [{TopicId, MsgOfTopicId}])
  end.

%% @doc collect all message(async handler API, non-blocking)
%%
%% @param Client the client object
%% @equiv get_msg(Client, AllTopic)
%%
%% @end
-spec get_msg(client()) -> {ok, dict:dict(topic_id(), [string()])} | invalid.
get_msg(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  get_msg(Client, dict:fetch_keys(MsgManager)).

%% @doc collect all topic id(non-blocking)
%%
%% @param Client the client object
%%
%% @end
-spec get_all_topic_id(client()) -> [topic_id()].
get_all_topic_id(Client) ->
  State = gen_statem:call(Client, get_state),
  #state{msg_manager = MsgManager} = State,
  dict:fetch_keys(MsgManager).

%% @doc get topic id from topic name
%%
%% @param Client the client object
%% @param TopicName topic name
%% @param Block whether make a block/unblock request(wait until topic id is exist)
%%
%% @end
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

%% @doc store gateway into ets
%%
%% @param Name unique name of client, used also as client id
%% @param GWInfo gateway information(including gateway id, host, port and come-from source)
%%
%% @end
-spec store_gw(string(), #gw_info{}) -> boolean().
store_gw(Name, GWInfo = #gw_info{id = GWId, from = SRC}) ->
  NameGW = list_to_atom(Name),
  case ets:lookup(NameGW, GWId) of
    [#gw_info{from = OldSRC}] when SRC < OldSRC ->
      ?LOGP(warning, "insert into ~p for gateway id:~p failed", [Name, GWId]),
      false;
    [] ->
      ets:insert(NameGW, GWInfo),
      ?LOGP(notice, "insert into ~p for gateway id:~p", [Name, GWId]),
      true;
    [#gw_info{from = OldSRC}] when SRC >= OldSRC ->
      ets:insert(NameGW, GWInfo),
      ?LOGP(warning, "substitude gateway id:~p", [Name, GWId]),
      true
  end.

%% @doc fetch existing gateway from ets by gateway id unblockly(common used)
%%
%% @param Name unique name of client, used also as client id
%% @param GWId gateway id to identify an gateway
%%
%% @end
-spec get_gw(string(), gw_id()) -> #gw_info{} | none.
get_gw(Name, GWId) ->
  get_gw(Name, GWId, false).

%% @doc fetch existing gateway from ets by gateway id
%%
%% @param Name unique name of client, used also as client id
%% @param GWId gateway id to identify an gateway
%% @param Block whether make a block/unblock request(wait until gateway is exist)
%%
%% @end
-spec get_gw(string(), gw_id(), boolean()) -> #gw_info{} | none.
get_gw(Name, GWId, Block) ->
  NameGW = list_to_atom(Name),
  case {ets:lookup(NameGW, GWId), Block} of
    {[GWInfo = #gw_info{}], _} ->
      GWInfo;
    {[], false} ->
      ?LOGP(warning, "not gateway to fetch from ~p for selected gateway id:~p", [Name, GWId]),
      none;
    {[], true} ->
      ?LOGP(debug,
            "not gateway to fetch from ~p for selected gateway id:~p, try "
            "again",
            [Name, GWId]),
      get_gw(Name, GWId, Block)
  end.

%% @doc fetch all existing gateway from ets unblockly(common used)
%%
%% @param Name unique name of client, used also as client id
%%
%% @end
-spec get_all_gw(string()) -> [#gw_info{}].
get_all_gw(Name) ->
  get_all_gw(Name, false).

%% @doc fetch all existing gateway from ets
%%
%% @param Name unique name of client, used also as client id
%% @param Block whether make a block/unblock request(wait until gateway is exist)
%%
%% @end
-spec get_all_gw(string(), boolean()) -> [#gw_info{}].
get_all_gw(Name, Block) ->
  NameGW = list_to_atom(Name),
  Ret = ets:tab2list(NameGW),
  case {Ret, Block} of
    {[], false} ->
      ?LOGP(warning, "not gateway to fetch from ~p", [Name]),
      [];
    {[], true} ->
      ?LOGP(debug, "not gateway to fetch from ~p, try again", [Name]),
      get_all_gw(Name, Block);
    {_, _} ->
      Ret
  end.
