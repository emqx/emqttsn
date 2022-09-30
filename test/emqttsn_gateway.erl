-module(emqttsn_gateway).
-export([start_emqx/0, stop_emqx/1]).

-include_lib("eunit/include/eunit.hrl").

-define(CONF_DEFAULT, <<
    "\n"
    "gateway.mqttsn {\n"
    "  gateway_id = 1\n"
    "  broadcast = true\n"
    "  enable_qos3 = true\n"
    "  predefined = [\n"
    "    { id = 1,\n"
    "      topic = \"/predefined/topic/name/hello\"\n"
    "    },\n"
    "    { id = 2,\n"
    "      topic = \"/predefined/topic/name/nice\"\n"
    "    }\n"
    "  ]\n"
    "  clientinfo_override {\n"
    "    username = \"user1\"\n"
    "    password = \"pw123\"\n"
    "  }\n"
    "  listeners.udp.default {\n"
    "    bind = 1884\n"
    "  }\n"
    "}\n"
>>).



-spec start_emqx() -> ok.
start_emqx() ->
    ensure_test_module(emqx_common_test_helpers),
    ensure_test_module(emqx_ratelimiter_SUITE),
    ok = emqx_common_test_helpers:load_config(emqx_gateway_schema, ?CONF_DEFAULT),
    ok = emqx_common_test_helpers:start_apps([emqx_gateway]),
    ok.

-spec stop_emqx(_) -> ok.
stop_emqx(_) ->
    ensure_test_module(emqx_common_test_helpers),
    emqx_common_test_helpers:stop_apps([emqx_gateway]).

-spec ensure_test_module(M::atom()) -> ok.
ensure_test_module(M) ->
    false == code:is_loaded(M) andalso
        compile_emqx_test_module(M).


-spec compile_emqx_test_module(M::atom()) -> ok.
compile_emqx_test_module(M) ->
    EmqxDir = code:lib_dir(emqx),
    EmqttDir = code:lib_dir(emqttsn),
    MFilename= filename:join([EmqxDir, "test", M]),
    OutDir = filename:join([EmqttDir, "test"]),
    {ok, _} = compile:file(MFilename, [{outdir, OutDir}]),
    ok.