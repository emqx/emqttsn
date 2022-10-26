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

-module(emqttsn_cli_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

%%--------------------------------------------------------------------
%% setups
%%--------------------------------------------------------------------

all() ->
    [t_cli_basic_communication].

init_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:init_per_suite(Cfg).

end_per_suite(Cfg) ->
    emqttsn_gateway_SUITE:end_per_suite(Cfg).

%%--------------------------------------------------------------------
%% tests
%%--------------------------------------------------------------------

t_cli_basic_communication(_Cfg) ->
    Pid = spawn(fun start_receiver/0),
    send_message(),
    timer:sleep(1000),
    exit(Pid, kill).

%%--------------------------------------------------------------------
%% utils
%%--------------------------------------------------------------------

send_message() ->
    emqttsn_cli:main(["pub",
                      "-n",
                      "sender",
                      "-h",
                      "127.0.0.1",
                      "-p",
                      "1884",
                      "-I",
                      "127.0.0.1:0",
                      "-i",
                      "1",
                      "--message",
                      "Message"]).

start_receiver() ->
    emqttsn_cli:main(["sub",
                      "-n",
                      "receiver",
                      "-h",
                      "127.0.0.1",
                      "-p",
                      "1884",
                      "-I",
                      "127.0.0.1:0",
                      "-i",
                      "1"]).
