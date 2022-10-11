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
