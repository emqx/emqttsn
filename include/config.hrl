%%--------------------------------------------------------------------
%% Maximum MQTT-SN Packet ID and Length
%%--------------------------------------------------------------------

-include("version.hrl").
-include("packet.hrl").

%% Default timeout
-define(DEFAULT_RETRY_INTERVAL, 30000).
-define(DEFAULT_ACK_TIMEOUT, 30000).
-define(DEFAULT_CONNECT_TIMEOUT, 60000).
-define(DEFAULT_SEARCH_GW_INTERVAL, 60000).
-define(DEFAULT_PORT, 1884).
-define(DEFAULT_RADIUS, 0).
% TODO: check argument whether is right
-define(DEFAULT_PING_INTERVAL, 30000).
-define(DEFAULT_MAX_RESEND, 3).
-define(DEFAULT_MAX_RECONNECT, 3).
-define(MAX_PACKET_ID, 16#ffff).
-define(MAX_PACKET_SIZE, 16#ffff).

-type msg_handler() :: fun((topic_id(), string()) -> term()).
-type option() ::
        {strict_mode, boolean()} | {clean_session, boolean()} | {max_size, 1..?MAX_PACKET_SIZE} |
        {auto_discover, boolean()} | {ack_timeout, non_neg_integer()} |
        {keep_alive, non_neg_integer()} | {resend_no_qos, boolean()} |
        {max_resend, non_neg_integer()} | {retry_interval, non_neg_integer()} |
        {connect_timeout, non_neg_integer()} | {search_gw_interval, non_neg_integer()} |
        {reconnect_max_times, non_neg_integer()} | {max_message_each_topic, non_neg_integer()} |
        {msg_handler, [msg_handler()]} | {send_port, inet:port_number()} | {host, host()} |
        {port, inet:port_number()} | {client_id, bin_1_byte()} | {proto_ver, version()} |
        {proto_name, iodata()} | {radius, non_neg_integer()} | {duration, non_neg_integer()} |
        {qos, qos()} | {will, boolean()} | {will_topic, bitstring()} | {will_msg, bitstring()}.

-record(config,
        {% system action config
         strict_mode = false :: boolean(),
         clean_session = true :: boolean(), max_size = ?MAX_PACKET_SIZE :: pos_integer(),
         auto_discover = true :: boolean(),
         ack_timeout = ?DEFAULT_ACK_TIMEOUT :: non_neg_integer(),
         keep_alive = ?DEFAULT_PING_INTERVAL :: non_neg_integer(),
         resend_no_qos = true :: boolean(), max_resend = ?DEFAULT_MAX_RESEND :: non_neg_integer(),
         retry_interval = ?DEFAULT_RETRY_INTERVAL :: non_neg_integer(),
         connect_timeout = ?DEFAULT_CONNECT_TIMEOUT :: non_neg_integer(),
         search_gw_interval = ?DEFAULT_SEARCH_GW_INTERVAL :: non_neg_integer(),
         reconnect_max_times = ?DEFAULT_MAX_RECONNECT :: non_neg_integer(),
         max_message_each_topic = 100 :: non_neg_integer(),
         msg_handler = [fun emqttsn_utils:default_msg_handler/2] :: [msg_handler()],
         %local config
         send_port = 0 :: inet:port_number(),
         % protocol config
         client_id = ?CLIENT_ID :: string(),
         proto_ver = ?MQTTSN_PROTO_V1_2 :: version(),
         proto_name = ?MQTTSN_PROTO_V1_2_NAME :: string(), radius = 3 :: non_neg_integer(),
         duration = 50 :: non_neg_integer(), will_qos = ?QOS_0 :: qos(),
         recv_qos = ?QOS_0 :: qos(), pub_qos = ?QOS_0 :: qos(), will = false :: boolean(),
         will_topic = "" :: string(), will_msg = "" :: string()}).

-type config() :: #config{}.

-record(msg_uid, {topic_id :: topic_id(), index :: non_neg_integer()}).

%%--------------------------------------------------------------------
%% gateway address manager
%%--------------------------------------------------------------------
-define(MANUAL, 2).
-define(BROADCAST, 1).
-define(PARAPHRASE, 0).

-type gw_src() :: ?MANUAL | ?BROADCAST | ?PARAPHRASE.

-record(gw_info,
        {id :: gw_id(), host :: host(), port :: inet:port_number(), from :: gw_src()}).
-record(gw_collect,
        {id = 0 :: gw_id(),
         host = ?DEFAULT_ADDRESS :: host(),
         port = ?DEFAULT_PORT :: inet:port_number()}).

-type gw_collect() :: #gw_collect{}.

%%--------------------------------------------------------------------
%% permanent information for state machine
%%--------------------------------------------------------------------

-record(state,
        {name :: string(),
         config :: #config{},
         waiting_data = {} :: tuple(),
         socket :: inet:socket(),
         next_packet_id = 0 :: non_neg_integer(),
         msg_manager = dict:new() :: dict:dict(topic_id(), queue:queue()),
         msg_counter = dict:new() :: dict:dict(topic_id(), non_neg_integer()),
         topic_id_name = dict:new() :: dict:dict(topic_id(), string()),
         topic_name_id = dict:new() :: dict:dict(string(), topic_id()),
         topic_id_use_qos = dict:new() :: dict:dict(topic_id(), qos()),
         active_gw = #gw_collect{} :: gw_collect(),
         gw_failed_cycle = 0 :: non_neg_integer()}).

-type state() :: #state{}.
