-module(emqttsn_gateway).

-export([start_emqx/0, stop_emqx/1]).

-include("logger.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(HOST, {127, 0, 0, 1}).
-define(PORT, 1884).
-define(PREDEF_TOPIC_ID1, 1).
-define(PREDEF_TOPIC_ID2, 2).
-define(PREDEF_TOPIC_NAME1, <<"/predefined/topic/name/hello">>).
-define(PREDEF_TOPIC_NAME2, <<"/predefined/topic/name/nice">>).
-define(ENABLE_QOS3, true).

set_special_confs() ->
    application:set_env(emqx_sn, port, ?PORT),
    application:set_env(emqx_sn, advertise_duration, 900000),
    application:set_env(emqx_sn, gateway_id, 1),
    application:set_env(emqx_sn, idle_timeout, 30000),
    application:set_env(emqx_sn, enable_qos3, ?ENABLE_QOS3),
    application:set_env(emqx_sn, enable_stats, false),
    application:set_env(emqx_sn, username, <<"user1">>),
    application:set_env(emqx_sn, password, <<"pw123">>),
    application:set_env(emqx_sn,
                        predefined,
                        [{?PREDEF_TOPIC_ID1, ?PREDEF_TOPIC_NAME1},
                         {?PREDEF_TOPIC_ID2, ?PREDEF_TOPIC_NAME2}]).

-spec start_emqx() -> ok.
start_emqx() ->
    set_special_confs(),
    _ = application:ensure_all_started(emqx_sn),
    ok.

-spec stop_emqx(_) -> ok.
stop_emqx(_) ->
    application:stop(emqx_sn),
    ok.

gateway_succeed_start_test_() ->
    {setup,
     fun start_emqx/0,
     fun stop_emqx/1,
     fun() ->
        {ok, Socket} = gen_udp:open(0, [binary]),
        send_connect_msg(Socket, <<"client_id_test1">>),
        ?assertEqual(<<3, 16#055, 0>>, receive_response(Socket)),

        send_disconnect_msg(Socket),
        ?assertEqual(<<2, 16#18>>, receive_response(Socket)),
        gen_udp:close(Socket)
     end}.

send_connect_msg(Socket, ClientId) ->
    Length = 6 + byte_size(ClientId),
    MsgType = 16#04,
    Dup = 0,
    QoS = 0,
    Retain = 0,
    Will = 0,
    TopicIdType = 0,
    ProtocolId = 1,
    Duration = 10,
    Packet =
        <<Length:8,
          MsgType:8,
          Dup:1,
          QoS:2,
          Retain:1,
          Will:1,
          1:1,
          TopicIdType:2,
          ProtocolId:8,
          Duration:16,
          ClientId/binary>>,
    ok = gen_udp:send(Socket, ?HOST, ?PORT, Packet).

send_disconnect_msg(Socket) ->
    Length = 2,
    MsgType = 18,
    DisConnectPacket = <<Length:8, MsgType:8>>,
    ok = gen_udp:send(Socket, ?HOST, ?PORT, DisConnectPacket).

receive_response(Socket) ->
    receive_response(Socket, 2000).

receive_response(Socket, Timeout) ->
    receive
        {udp, Socket, _, _, Bin} ->
            ?LOG_INFO("receive_response Bin=~p~n", [Bin]),
            Bin;
        {mqttc, From, Data2} ->
            ?LOG_INFO("receive_response() ignore mqttc From=~p, Data2=~p~n", [From, Data2]),
            receive_response(Socket);
        Other ->
            ?LOG_INFO("receive_response() Other message: ~p", [{unexpected_udp_data, Other}]),
            receive_response(Socket)
    after Timeout ->
        udp_receive_timeout
    end.
