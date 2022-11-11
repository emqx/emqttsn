%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqttsn_udp_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

init_per_testcase(_TestCase, _Cfg) ->
    meck:unload().

end_per_testcase(_TestCase, _Cfg) ->
    meck:unload().

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() ->
    [t_init_port_failed,
     t_connect_failed,
     t_boardcast_succeed,
     t_boardcast_failed_send,
     t_recv_succeed,
     t_recv_failed,
     t_recv_unexpected,
     t_recv_timeout].

t_init_port_failed(_Cfg) ->
    ok = meck:new(gen_udp, [passthrough, no_history, no_link, unstick]),
    meck:expect(gen_udp, open, fun(_, _) -> {error, mocked_error} end),
    ?assertEqual({error, mocked_error}, emqttsn_udp:init_port()),
    ?assertEqual({error, mocked_error}, emqttsn_udp:init_port(0)),
    ?assertEqual({error, mocked_error}, emqttsn_udp:init_port(11451)).

t_connect_failed(_Cfg) ->
    ok = meck:new(gen_udp, [passthrough, no_history, no_link, unstick]),
    meck:expect(gen_udp, connect, fun(_, _, _) -> {error, mocked_error} end),
    {ok, Socket} = emqttsn_udp:init_port(),
    Host = {127, 0, 0, 1},
    Port = 1884,

    ?assertEqual({error, mocked_error}, emqttsn_udp:connect(Socket, Host, Port)).

t_boardcast_succeed(_Cfg) ->
    {ok, Socket} = emqttsn_udp:init_port(),
    Bin = <<>>,
    Port = 1884,

    ?assertEqual(ok, emqttsn_udp:broadcast(Socket, Bin, Port)).

t_boardcast_failed_send(_Cfg) ->
    {ok, Socket} = emqttsn_udp:init_port(),

    ok = meck:new(gen_udp, [passthrough, no_history, no_link, unstick]),
    meck:expect(gen_udp, send, fun(_, _, _, _) -> {error, mocked_error} end),

    Bin = <<>>,
    Port = 1884,

    ?assertEqual({error, mocked_error}, emqttsn_udp:broadcast(Socket, Bin, Port)).

t_recv_succeed(_Cfg) ->
    ok = meck:new(emqttsn_frame, [passthrough, no_history, no_link]),
    meck:expect(emqttsn_frame, parse, fun(_) -> {ok, mocked_ok} end),
    {ok, Socket} = emqttsn_udp:init_port(),
    Host = {127, 0, 0, 1},
    Port = 1884,
    Bin = <<>>,

    spawn(emqttsn_udp_SUITE, sender, [self(), {udp, Socket, Host, Port, Bin}]),
    ?assertEqual({ok, mocked_ok}, emqttsn_udp:recv(Socket)),

    spawn(emqttsn_udp_SUITE, sender, [self(), {udp, Socket, Host, Port, Bin}]),
    ?assertEqual({ok, mocked_ok}, emqttsn_udp:recv(Socket, 1000)).

t_recv_failed(_Cfg) ->
    ok = meck:new(emqttsn_frame, [passthrough, no_history, no_link]),
    meck:expect(emqttsn_frame, parse, fun(_) -> {error, mocked_error} end),

    {ok, Socket} = emqttsn_udp:init_port(),
    Host = {127, 0, 0, 1},
    Port = 1884,
    Bin = <<>>,

    spawn(emqttsn_udp_SUITE, sender, [self(), {udp, Socket, Host, Port, Bin}]),
    ?assertEqual({error, mocked_error}, emqttsn_udp:recv(Socket)),

    spawn(emqttsn_udp_SUITE, sender, [self(), {udp, Socket, Host, Port, Bin}]),
    ?assertEqual({error, mocked_error}, emqttsn_udp:recv(Socket, 1000)).

t_recv_unexpected(_Cfg) ->
    {ok, Socket} = emqttsn_udp:init_port(),

    spawn(emqttsn_udp_SUITE, sender, [self(), {unexpected}]),
    ?assertEqual({error, unexpected_data}, emqttsn_udp:recv(Socket)),

    spawn(emqttsn_udp_SUITE, sender, [self(), {unexpected}]),
    ?assertEqual({error, unexpected_data}, emqttsn_udp:recv(Socket, 1000)).

t_recv_timeout(_Cfg) ->
    {ok, Socket} = emqttsn_udp:init_port(),

    ?assertEqual({error, udp_receive_timeout}, emqttsn_udp:recv(Socket, 10)).

%%--------------------------------------------------------------------
%% utils
%%--------------------------------------------------------------------

-spec sender(pid(), term()) -> ok.
sender(TargetPid, Msg) ->
    TargetPid ! Msg,
    ok.
