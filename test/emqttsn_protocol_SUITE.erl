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

-module(emqttsn_protocol_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include("emqttsn.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(HOST, {127, 0, 0, 1}).
-define(PORT, 1884).

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() ->
    [t_connect_eager,
     t_publish_recv_async,
     t_publish_recv_sync,
     t_low_level_com,
     t_merge_com,
     t_connect_with_will,
     t_publish_qos_neg,
     t_publish_qos_1,
     t_publish_qos_2,
     t_unsubscribe,
     t_sleeping].

init_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:init_per_suite(Cfg).

end_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:end_per_suite(Cfg).

%%--------------------------------------------------------------------
%% tests
%%--------------------------------------------------------------------

t_connect_eager(_Cfg) ->
    GateWayId = 1,

    Block = false,

    {ok, ClientSend, _} = emqttsn:start_link("sender_e", []),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block).

t_publish_recv_sync(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_0,

    Block = true,

    {ok, ClientSend, _} = emqttsn:start_link("sender_0", []),
    emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    emqttsn:connect(ClientSend, GateWayId, Block),
    emqttsn:register(ClientSend, TopicName, Block),

    % register a message consumer which will sync consumes messages
    {ok, ClientRecv, _} =
        emqttsn:start_link("judgement_0",
                           [{msg_handler,
                             [fun(_, RecvMsg) -> ?_assertEqual(Message, RecvMsg) end]}]),
    emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    emqttsn:connect(ClientRecv, GateWayId, Block),
    emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    emqttsn:finalize(ClientSend),
    emqttsn:finalize(ClientRecv),
    ok.

t_publish_recv_async(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_0,

    Block = true,
    {ok, ClientSend, _} = emqttsn:start_link("sender_1", []),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),
    ok = emqttsn:register(ClientSend, TopicName, Block),

    % clear default message consumer
    {ok, ClientRecv, _} = emqttsn:start_link("judgement_1", [{msg_handler, []}]),
    ok = emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    % get message async from state machine
    {ok, TopicId} = emqttsn_utils:get_topic_id_from_name(ClientRecv, TopicName, Block),
    {ok, RecvMsgs} = emqttsn_utils:get_one_topic_msg(ClientRecv, TopicId, Block),
    ?_assertEqual([Message], RecvMsgs),

    emqttsn:finalize(ClientSend),
    emqttsn:finalize(ClientRecv).

t_low_level_com(_Cfg) ->
    Config = #config{client_id = "low_level"},
    #config{clean_session = CleanSession,
            duration = Duration,
            will = Will,
            client_id = ClientId} =
        Config,

    % use low-level communication API, not need state machine any more
    {ok, Socket} = emqttsn_udp:init_port(),
    emqttsn_udp:connect(Socket, ?HOST, ?PORT),

    emqttsn_send:send_connect(Config, Socket, Will, CleanSession, Duration, ClientId),
    ConnPacket = emqttsn_udp:recv(Socket),
    ?_assertEqual(#mqttsn_packet{header = ?CONNACK}, ConnPacket),

    emqttsn_send:send_pingreq(Config, Socket),
    ?_assertEqual(#mqttsn_packet{header = ?PINGRESP}, ConnPacket),

    emqttsn_send:send_disconnect(Config, Socket),
    DisConnPacket = emqttsn_udp:recv(Socket),
    ?_assertEqual(#mqttsn_packet{header = ?DISCONNECT}, DisConnPacket).

t_merge_com(_Cfg) ->
    GateWayId = 1,

    Block = true,

    {ok, ClientSend, Config} = emqttsn:start_link("sender_2", []),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),

    % stop state machine and turn to low-level API
    {ok, Socket} = emqttsn:stop(ClientSend),

    emqttsn_send:send_disconnect(Config, Socket),
    DisConnPacket = emqttsn_udp:recv(Socket),
    ?_assertEqual(#mqttsn_packet{}, DisConnPacket).

t_connect_with_will(_Cfg) ->
    GateWayId = 1,
    WillTopic = "wt",
    WillMsg = "Will Message",

    Host = {127, 0, 0, 1},
    Port = 1884,

    Block = true,

    {ok, ClientSend, _} =
        emqttsn:start_link("sender_3",
                           [{will, true}, {will_topic, WillTopic}, {will_msg, WillMsg}]),
    emqttsn:add_host(ClientSend, Host, Port, GateWayId),
    emqttsn:connect(ClientSend, GateWayId, Block),
    emqttsn:finalize(ClientSend),
    ok.

t_publish_qos_neg(_Cfg) ->
    GateWayId = 1,
    TopicIdType = ?PRE_DEF_TOPIC_ID,
    TopicId = 1,
    Message = "Message",
    Qos = ?QOS_0,

    Block = true,

    % clear default message consumer
    {ok, ClientRecv, _} = emqttsn:start_link("judgement_1", [{msg_handler, []}]),
    ok = emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicId, Qos, Block),

    {ok, Socket} = emqttsn_udp:init_port(),
    emqttsn_udp:connect(Socket, ?HOST, ?PORT),

    emqttsn_send:send_pub_any(#config{}, Socket, ?HOST, ?PORT, TopicIdType, TopicId, Message),

    % get message async from state machine
    {ok, RecvMsgs} = emqttsn_utils:get_one_topic_msg(ClientRecv, TopicId, Block),
    ?_assertEqual([Message], RecvMsgs),

    emqttsn:finalize(ClientRecv).

t_publish_qos_1(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_1,

    Block = true,

    {ok, ClientSend, _} = emqttsn:start_link("sender_5", [{pub_qos, Qos}]),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),
    ok = emqttsn:register(ClientSend, TopicName, Block),

    % clear default message consumer
    {ok, ClientRecv, _} = emqttsn:start_link("judgement_5", [{msg_handler, []}]),
    ok = emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    % get message async from state machine
    {ok, TopicId} = emqttsn_utils:get_topic_id_from_name(ClientRecv, TopicName, Block),
    {ok, RecvMsgs} = emqttsn_utils:get_one_topic_msg(ClientRecv, TopicId, Block),
    ?_assertEqual([Message], RecvMsgs),

    emqttsn:finalize(ClientSend),
    emqttsn:finalize(ClientRecv).

t_publish_qos_2(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_2,

    Block = true,

    {ok, ClientSend, _} = emqttsn:start_link("sender_6", [{pub_qos, Qos}]),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),
    ok = emqttsn:register(ClientSend, TopicName, Block),

    % clear default message consumer
    {ok, ClientRecv, _} = emqttsn:start_link("judgement_6", [{msg_handler, []}]),
    ok = emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    % get message async from state machine
    {ok, TopicId} = emqttsn_utils:get_topic_id_from_name(ClientRecv, TopicName, Block),
    {ok, RecvMsgs} = emqttsn_utils:get_one_topic_msg(ClientRecv, TopicId, Block),
    ?_assertEqual([Message], RecvMsgs),

    emqttsn:finalize(ClientSend),
    emqttsn:finalize(ClientRecv).

t_unsubscribe(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_0,

    Block = true,

    {ok, ClientSend, _} = emqttsn:start_link("sender_7", []),
    ok = emqttsn:add_host(ClientSend, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),
    ok = emqttsn:register(ClientSend, TopicName, Block),

    % will not receive any message
    {ok, ClientRecv, _} =
        emqttsn:start_link("judgement_7",
                           [{msg_handler, [fun(_, _RecvMsg) -> ?_test(false) end]}]),
    ok = emqttsn:add_host(ClientRecv, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    % unsubscribe topic leading to no recv message
    ok = emqttsn:unsubscribe(ClientRecv, TopicIdType, TopicName, Block),

    ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    timer:sleep(1000),

    emqttsn:finalize(ClientSend),
    emqttsn:finalize(ClientRecv).

t_sleeping(_Cfg) ->
    GateWayId = 1,
    SleepInterval = 1000,

    Block = true,

    {ok, Client, _} = emqttsn:start_link("sleeper_1", []),
    ok = emqttsn:add_host(Client, ?HOST, ?PORT, GateWayId),
    ok = emqttsn:connect(Client, GateWayId, Block),

    emqttsn:sleep(Client, SleepInterval, true),

    ?_assertEqual(asleep, emqttsn:get_state_name(Client)),
    timer:sleep(2000),
    ?_assertEqual(awake, emqttsn:get_state_name(Client)),
    emqttsn:finalize(Client).
