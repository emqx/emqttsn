-module(emqttsn_protocol_SUITE).

-include("packet.hrl").
-include("config.hrl").
-include("logger.hrl").

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).
-compile(nowarn_export_all).

all() ->
    [t_publish_recv_async, t_publish_recv_sync, t_connect_low_level].

init_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:init_per_suite(Cfg).

end_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:end_per_suite(Cfg).

t_publish_recv_sync(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_0,

    Host = {127, 0, 0, 1},
    Port = 1884,

    Block = true,

    {ok, _, ClientSend, _} = emqttsn:start_link("sender", []),
    emqttsn:add_host(ClientSend, Host, Port, GateWayId),
    emqttsn:connect(ClientSend, GateWayId, Block),
    emqttsn:register(ClientSend, TopicName, Block),

    {ok, _, ClientRecv, _} =
        emqttsn:start_link("judgement",
                           [{msg_handler,
                             [fun(_, RecvMsg) -> ?_assertEqual(Message, RecvMsg) end]}]),
    emqttsn:add_host(ClientRecv, Host, Port, GateWayId),
    emqttsn:connect(ClientRecv, GateWayId, Block),
    emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    emqttsn:stop(ClientSend),
    emqttsn:stop(ClientRecv),
    ok.

t_publish_recv_async(_Cfg) ->
    GateWayId = 1,
    Retain = false,
    TopicIdType = ?SHORT_TOPIC_NAME,
    TopicName = "tn",
    Message = "Message",
    Qos = ?QOS_0,

    Host = {127, 0, 0, 1},
    Port = 1884,

    Block = true,

    {ok, _, ClientSend, _} = emqttsn:start_link("sender", []),
    ok = emqttsn:add_host(ClientSend, Host, Port, GateWayId),
    ok = emqttsn:connect(ClientSend, GateWayId, Block),
    ok = emqttsn:register(ClientSend, TopicName, Block),

    {ok, _, ClientRecv, _} = emqttsn:start_link("judgement", [{msg_handler, []}]),
    ok = emqttsn:add_host(ClientRecv, Host, Port, GateWayId),
    ok = emqttsn:connect(ClientRecv, GateWayId, Block),
    ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos, Block),

    ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message, Block),

    {ok, TopicId} = emqttsn_utils:get_topic_id_from_name(ClientRecv, TopicName, Block),
    {ok, RecvMsgs} = emqttsn_utils:get_one_msg(ClientRecv, TopicId, Block),
    ?_assertEqual([Message], RecvMsgs),

    emqttsn:stop(ClientSend),
    emqttsn:stop(ClientRecv).

t_connect_low_level(_Cfg) ->
    Host = {127, 0, 0, 1},
    Port = 1884,

    Config = #config{client_id = "low_level"},
    #config{clean_session = CleanSession,
            duration = Duration,
            will = Will,
            client_id = ClientId} =
        Config,

    {ok, Socket} = emqttsn_udp:init_port(),
    emqttsn_udp:connect(Socket, Host, Port),

    emqttsn_send:send_connect(Config, Socket, Will, CleanSession, Duration, ClientId),
    ConnPacket = emqttsn_udp:recv(Socket),
    ?_assertEqual(#mqttsn_packet{}, ConnPacket),

    emqttsn_send:send_disconnect(Config, Socket),
    DisConnPacket = emqttsn_udp:recv(Socket),
    ?_assertEqual(#mqttsn_packet{}, DisConnPacket).
