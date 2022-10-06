%%--------------------------------------------------------------------
%% Copyright (c) 2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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
%%--------------------------------------------------------------------

-module(emqttsn_gateway_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

-define(HOST, {127, 0, 0, 1}).
-define(PORT, 1884).

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() ->
    [t_gateway_succeed_start].

init_per_suite(Cfg) ->
    emqx_ct_helpers:start_apps([emqx_sn], fun set_special_confs/1),
    Cfg.

end_per_suite(_Cfg) ->
    emqx_ct_helpers:stop_apps([emqx_sn]),
    ok.

set_special_confs(_App) ->
    ok.

%%--------------------------------------------------------------------
%% tests
%%--------------------------------------------------------------------

t_gateway_succeed_start(_Cfg) ->
    {ok, Socket} = gen_udp:open(0, [binary]),
    send_connect_msg(Socket, <<"client_id_test1">>),
    ?assertEqual(<<3, 16#05, 0>>, receive_response(Socket)),
    
    send_disconnect_msg(Socket),
    ?assertEqual(<<2, 16#18>>, receive_response(Socket)),
    gen_udp:close(Socket).

%%--------------------------------------------------------------------
%% utils
%%--------------------------------------------------------------------

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
    MsgType = 16#18,
    DisConnectPacket = <<Length:8, MsgType:8>>,
    ok = gen_udp:send(Socket, ?HOST, ?PORT, DisConnectPacket).

receive_response(Socket) ->
    receive_response(Socket, 2000).

receive_response(Socket, Timeout) ->
    receive
        {udp, Socket, _, _, Bin} ->
            ct:pal("receive_response Bin=~p~n", [Bin]),
            Bin;
        {mqttc, From, Data2} ->
            ct:pal("receive_response() ignore mqttc From=~p, Data2=~p~n", [From, Data2]),
            receive_response(Socket);
        Other ->
            ct:pal("receive_response() Other message: ~p", [{unexpected_udp_data, Other}]),
            receive_response(Socket)
    after Timeout ->
        udp_receive_timeout
    end.
