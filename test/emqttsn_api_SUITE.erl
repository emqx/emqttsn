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

-module(emqttsn_api_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include("emqttsn.hrl").

-include_lib("eunit/include/eunit.hrl").

init_per_testcase(_TestCase, _Cfg) ->
    meck:unload().

end_per_testcase(_TestCase, _Cfg) ->
    meck:unload().

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() ->
    [t_merge_opt_all, t_state_init_failed, t_reset_config, t_stop_unconnected].

t_merge_opt_all(_Cfg) ->
    Options =
        [{strict_mode, true},
         {clean_session, true},
         {max_size, 1024},
         {ack_timeout, 114},
         {keep_alive, 514},
         {resend_no_qos, true},
         {max_resend, 7},
         {search_gw_interval, 1919},
         {reconnect_max_times, 15},
         {max_message_each_topic, 100},
         {msg_handler, []},
         {send_port, 810},
         {proto_ver, ?MQTTSN_PROTO_V1_2},
         {proto_name, ?MQTTSN_PROTO_V1_2_NAME},
         {radius, 1},
         {duration, 1},
         {recv_qos, ?QOS_0},
         {pub_qos, ?QOS_0},
         {will_qos, ?QOS_0},
         {will, true},
         {will_topic, "deep"},
         {will_msg, "dark"}],
    {ok, _, _} = emqttsn:start_link("Merge", Options).

t_state_init_failed(_Cfg) ->
    ok = meck:new(emqttsn_state, [passthrough, no_history, no_link]),
    meck:expect(emqttsn_state, start_link, fun(_, _) -> {error, mocked_error} end),

    {error, mocked_error} = emqttsn:start_link("StateFailed").

t_reset_config(_Cfg) ->
    {ok, Client, #config{strict_mode = false}} = emqttsn:start_link("ResetConfig"),

    emqttsn:reset_config(Client, #config{strict_mode = true}),
    #state{config = #config{strict_mode = true}} = emqttsn:get_state(Client).

t_stop_unconnected(_Cfg) ->
    ok = meck:new(emqttsn, [passthrough, no_history, no_link]),

    meck:expect(emqttsn, get_state_name, fun(_) -> initialized end),
    {ok, ClientA, _} = emqttsn:start_link("StopA"),
    emqttsn:finalize(ClientA),

    meck:expect(emqttsn, get_state_name, fun(_) -> connected end),
    {ok, ClientB, _} = emqttsn:start_link("StopB"),
    emqttsn:finalize(ClientB).
