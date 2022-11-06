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

-module(emqttsn).

%% @headerfile "emqttsn.hrl"

-include("emqttsn.hrl").
-include("logger.hrl").

-include_lib("stdlib/include/assert.hrl").

-export([start_link/1, start_link/2, register/3, subscribe/5, unsubscribe/4, publish/6,
         add_host/4, connect/3, sleep/3, get_state/1, get_state_name/1, reset_config/2, stop/1,
         finalize/1, disconnect/1, wait_until_state_name/2]).

-export_type([client/0]).

-spec merge_opt(#config{}, [option()]) -> #config{}.
merge_opt(Config, [{strict_mode, Value} | Options]) ->
  merge_opt(Config#config{strict_mode = Value}, Options);
merge_opt(Config, [{clean_session, Value} | Options]) ->
  merge_opt(Config#config{clean_session = Value}, Options);
merge_opt(Config, [{max_size, Value} | Options]) ->
  merge_opt(Config#config{max_size = Value}, Options);
merge_opt(Config, [{ack_timeout, Value} | Options]) ->
  merge_opt(Config#config{ack_timeout = Value}, Options);
merge_opt(Config, [{keep_alive, Value} | Options]) ->
  merge_opt(Config#config{keep_alive = Value}, Options);
merge_opt(Config, [{resend_no_qos, Value} | Options]) ->
  merge_opt(Config#config{resend_no_qos = Value}, Options);
merge_opt(Config, [{max_resend, Value} | Options]) ->
  merge_opt(Config#config{max_resend = Value}, Options);
merge_opt(Config, [{search_gw_interval, Value} | Options]) ->
  merge_opt(Config#config{search_gw_interval = Value}, Options);
merge_opt(Config, [{reconnect_max_times, Value} | Options]) ->
  merge_opt(Config#config{reconnect_max_times = Value}, Options);
merge_opt(Config, [{max_message_each_topic, Value} | Options]) ->
  merge_opt(Config#config{max_message_each_topic = Value}, Options);
merge_opt(Config, [{msg_handler, Value} | Options]) ->
  merge_opt(Config#config{msg_handler = Value}, Options);
merge_opt(Config, [{send_port, Value} | Options]) ->
  merge_opt(Config#config{send_port = Value}, Options);
merge_opt(Config, [{proto_ver, Value} | Options]) ->
  merge_opt(Config#config{proto_ver = Value}, Options);
merge_opt(Config, [{proto_name, Value} | Options]) ->
  merge_opt(Config#config{proto_name = Value}, Options);
merge_opt(Config, [{radius, Value} | Options]) ->
  merge_opt(Config#config{radius = Value}, Options);
merge_opt(Config, [{duration, Value} | Options]) ->
  merge_opt(Config#config{duration = Value}, Options);
merge_opt(Config, [{recv_qos, Value} | Options]) ->
  merge_opt(Config#config{recv_qos = Value}, Options);
merge_opt(Config, [{pub_qos, Value} | Options]) ->
  merge_opt(Config#config{pub_qos = Value}, Options);
merge_opt(Config, [{will_qos, Value} | Options]) ->
  merge_opt(Config#config{will_qos = Value}, Options);
merge_opt(Config, [{will, Value} | Options]) ->
  merge_opt(Config#config{will = Value}, Options);
merge_opt(Config, [{will_topic, Value} | Options]) ->
  merge_opt(Config#config{will_topic = Value}, Options);
merge_opt(Config, [{will_msg, Value} | Options]) ->
  merge_opt(Config#config{will_msg = Value}, Options);
merge_opt(Config, [{_AnyKey, _AnyValue} | Options]) ->
  merge_opt(Config, Options);
merge_opt(Config, []) ->
  Config.

%% @doc Create a MQTT-SN client by default options
%%
%% @param Name unique name of client, used also as client id
%%
%% @equiv start_link(Name, [])
%% @returns A client object
%% @end
-spec start_link(string()) -> {ok, client(), config()} | {error, term()}.
start_link(Name) ->
  start_link(Name, []).

%% @doc Create a MQTT-SN client
%%
%% @param Name unique name of client, used also as client id
%% @param Options array of client construction parameters
%%
%% @returns A client object
%% @end
-spec start_link(string(), [option()]) -> {ok, client(), config()} | {error, term()}.
start_link(Name, Options) ->
  NameLength = string:length(Name),
  ?assert(NameLength >= 1 andalso NameLength =< 23),
  Config = merge_opt(#config{client_id = Name}, Options),

  case emqttsn_state:start_link(Name, Config) of
    {error, Reason} ->
      ?LOGP(error, "gen_statem init failed, reason: ~p", [Reason]),
      {error, Reason};
    {ok, StateM} ->
      {ok, StateM, Config}
  end.

%% @doc Block until client reach target state
%%
%% @param Client the client object
%% @param StateNames target state name to be wait for
%%
%% @end
-spec wait_until_state_name(client(), [atom()]) -> ok.
wait_until_state_name(Client, StateNames) ->
  wait_until_state_name(Client, StateNames, true).

-spec wait_until_state_name(client(), [atom()], boolean()) -> ok.
wait_until_state_name(Client, StateNames, Block) ->
  case {Block, get_state_name(Client)} of
    {false, _} ->
      ok;
    {true, S} ->
      case lists:member(S, StateNames) of
        true ->
          ok;
        false ->
          wait_until_state_name(Client, StateNames, true)
      end
  end.

%% @doc Cast a MQTT-SN register request
%%
%% @param Client the client object
%% @param TopicName topic name to be registered
%% @param Block whether make a block/unblock request(wait until ack response or timeout)
%%
%% @end
-spec register(client(), string(), boolean()) -> ok.
register(Client, TopicName, Block) ->
  gen_statem:cast(Client, {reg, TopicName}),
  wait_until_state_name(Client, [connected], Block).

%% @doc Cast a MQTT-SN subscribe request
%%
%% @param Client the client object
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param MaxQos max Qos level can be handled of subscribed request
%% @param Block whether make a block/unblock request(wait until ack response or timeout)
%%
%% @end
-spec subscribe(client(), topic_id_type(), topic_id_or_name(), qos(), boolean()) -> ok.
subscribe(Client, TopicIdType, TopicIdOrName, MaxQos, Block) ->
  gen_statem:cast(Client, {sub, TopicIdType, TopicIdOrName, MaxQos}),
  wait_until_state_name(Client, [connected], Block).

%% @doc Cast a MQTT-SN unsubscribe request
%%
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param Block whether make a block/unblock request(wait until ack response or timeout)
%%
%% @end
-spec unsubscribe(client(), topic_id_type(), topic_id_or_name(), boolean()) -> ok.
unsubscribe(Client, TopicIdType, TopicIdOrName, Block) ->
  gen_statem:cast(Client, {unsub, TopicIdType, TopicIdOrName}),
  wait_until_state_name(Client, [connected], Block).

%% @doc Cast a MQTT-SN publish request
%%
%% @param Client the client object
%% @param Retain whether the message is retain
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param Message message data of publish request
%% @param Block whether make a block/unblock request(wait until ack response or timeout)
%%
%% @end
-spec publish(client(),
              boolean(),
              topic_id_type(),
              topic_id_or_name(),
              string(),
              boolean()) ->
               ok.
publish(Client, Retain, TopicIdType, TopicIdOrName, Message, Block) ->
  gen_statem:cast(Client, {pub, Retain, TopicIdType, TopicIdOrName, Message}),
  wait_until_state_name(Client, [connected], Block).

%% @doc Manually add a gateway host(non-blocking)
%%
%% @param Client the client object
%% @param Host host of new gateway
%% @param Port port of new gateway
%% @param GatewayId gateway id of new gateway(save locally)
%%
%% @end
-spec add_host(client(), host(), port(), gw_id()) -> ok.
add_host(Client, Host, Port, GateWayId) ->
  gen_statem:cast(Client, {add_gw, Host, Port, GateWayId}).

%% @doc Cast a MQTT-SN connect request
%%
%% @param Client the client object
%% @param GatewayId gateway id to be connected
%% @param Block whether make a block/unblock request(wait until ack response or timeout)
%%
%%
-spec connect(client(), gw_id(), boolean()) -> ok.
connect(Client, GateWayId, Block) ->
  gen_statem:cast(Client, {connect, GateWayId}),
  wait_until_state_name(Client, [connected], Block).

%% @doc Cast a MQTT-SN sleep request
%%
%% @param Client the client object
%% @param Interval sleep interval(ms)
%%
%%
%% @end
-spec sleep(client(), pos_integer(), boolean()) -> ok.
sleep(Client, Interval, Block) ->
  gen_statem:cast(Client, {sleep, Interval}),
  wait_until_state_name(Client, [asleep], Block).

%% @doc Cast a MQTT-SN disconnect request(non-blocking)
%%
%% @param Client the client object
%%
%% @end
-spec disconnect(client()) -> ok.
disconnect(Client) ->
  gen_statem:cast(Client, disconnect).

%% @doc Get state data of the client(force-blocking)
%%
%% @param Client the client object
%%
%% @returns state data
%% @end
-spec get_state(client()) -> state().
get_state(Client) ->
  State = gen_statem:call(Client, get_state),
  State.

%% @doc Get state name of the client(force-blocking)
%%
%% @param Client the client object
%%
%%
%% @end
-spec get_state_name(client()) -> atom().
get_state_name(Client) ->
  StateName = gen_statem:call(Client, get_state_name),
  StateName.

%% @doc Set new config of the client(non-blocking)
%%
%% @param Client the client object
%% @param Config new config to be set
%%
%% @returns state name
%% @end
-spec reset_config(client(), #config{}) -> ok.
reset_config(Client, Config) ->
  gen_statem:cast(Client, {config, Config}).

%% @doc Only Stop the state machine client, but not disconnect(non-blocking)
%%
%% @param Client the client object
%% @param Config new config to be set
%%
%% @returns socket for low-level API, can be closed if not use
%% @end
-spec stop(client()) -> {ok, inet:socket()}.
stop(Client) ->
  #state{socket = Socket} = get_state(Client),
  gen_statem:stop(Client),
  {ok, Socket}.

%% @doc Stop and disconnect the client(non-blocking)
%%
%% @param Client the client object
%% @param Config new config to be set
%%
%% @returns socket for low-level API, can be closed if not use
%% @end
-spec finalize(client()) -> ok.
finalize(Client) ->
  StateName = get_state_name(Client),
  case StateName =/= initialized andalso StateName =/= found of
    true ->
      disconnect(Client),
      stop(Client);
    false ->
      stop(Client)
  end,
  ok.
