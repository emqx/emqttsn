%%--------------------------------------------------------------------
%% Maximum MQTT-SN Packet ID and Length
%%--------------------------------------------------------------------

-include("version.hrl").

-define(CLIENT_ID, 16#01).
%% Default timeout
-define(DEFAULT_RETRY_INTERVAL, 30000).
-define(DEFAULT_ACK_TIMEOUT, 30000).
-define(DEFAULT_CONNECT_TIMEOUT, 60000).
-define(DEFAULT_SEARCH_GW_INTERVAL, 60000).
-define(DEFAULT_SLEEP_INTERVAL, 60000).
-define(DEFAULT_PORT, 1884).
-define(DEFAULT_RADIUS, 0).
% TODO: 检查这几个参数是否正确
-define(DEFAULT_PING_INTERVAL, 30000).
-define(DEFAULT_MAX_RESEND, 3).
-define(DEFAULT_MAX_RECONNECT, 3).
-define(MAX_PACKET_ID, 16#ffff).
-define(MAX_PACKET_SIZE, 16#ffff).

-type host() :: inet:ip_address() | inet:hostname().

-type msg_handler() :: fun((topic_id(), string())-> no_return()).

-type option() ::
{strict_mode, boolean()} |
{clean_session, boolean()} |
{max_size, 1..?MAX_PACKET_SIZE} |
{auto_discover, boolean()} |
{ack_timeout, pos_integer()} |
{ping_interval, pos_integer()} |
{resend_no_qos, boolean()} |
{max_resend, pos_integer()} |
{retry_interval, pos_integer()} |
{connect_timeout, pos_integer()} |
{search_gw_interval, pos_integer()} |
{reconnect_max_times, pos_integer()} |
{max_message_each_topic, pos_integer()} |
{sleep_interval, pos_integer()} |
{msg_handler, [msg_handler()]} |
{send_port, inet:port_number()} |
{host, host()} |
{port, inet:port_number()} |
{client_id, binary()} |
{proto_ver, version()} |
{proto_name, iodata()} |
{radius, pos_integer()} |
{duration, pos_integer()} |
{qos, qos()} |
{clean_session, boolean()} |
{will, boolean()} |
{will_topic, bitstring()} |
{will_msg, bitstring()}.

-record(config,
{% system action config
 strict_mode = false :: boolean(),
 clean_session = true :: boolean(),
 max_size = ?MAX_PACKET_SIZE :: 1..?MAX_PACKET_SIZE,
 auto_discover = true :: boolean(),
 ack_timeout = ?DEFAULT_ACK_TIMEOUT :: pos_integer(),
 keep_alive = ?DEFAULT_PING_INTERVAL :: pos_integer(),
 resend_no_qos = true :: boolean(),
 max_resend = ?DEFAULT_MAX_RESEND :: pos_integer(),
 retry_interval = ?DEFAULT_RETRY_INTERVAL :: pos_integer(),
 connect_timeout = ?DEFAULT_CONNECT_TIMEOUT :: pos_integer(),
 search_gw_interval = ?DEFAULT_SEARCH_GW_INTERVAL :: pos_integer(),
 reconnect_max_times = ?DEFAULT_MAX_RECONNECT :: pos_integer(),
 max_message_each_topic = 100 :: pos_integer(),
 sleep_interval = ?DEFAULT_SLEEP_INTERVAL :: pos_integer(),
 msg_handler = [fun emqttsn_utils:default_msg_handler/2] :: [msg_handler()],
%local config
 send_port = ?DEFAULT_PORT :: inet:port_number(),
% gateway config
 host :: host(),
 port = ?DEFAULT_PORT :: inet:port_number(),
% protocol config
 client_id = ?CLIENT_ID :: binary(),
 proto_ver = ?MQTTSN_PROTO_V1_2 :: version(),
 proto_name = proplists:get_value(?MQTTSN_PROTO_V1_2, ?PROTOCOL_NAMES) :: iodata(),
 radius = 3 :: pos_integer(),
 duration :: pos_integer(),
 qos :: qos(),
 clean_session :: boolean(),
 will :: boolean(),
 will_topic :: bitstring(),
 will_msg :: bitstring()}).

-record(msg_uid, {
  topic_id :: topic_id(),
  index :: pos_integer()
}).

-record(msg_store, {
  uid :: #msg_uid{},
  timestamp :: Timestamp :: timestamp(),
  data :: bitstring()
}).

-record(msg_collect, {
  topic_id :: topic_id(),
  timestamp :: Timestamp :: timestamp(),
  data :: bitstring()
}).

%%--------------------------------------------------------------------
%% gateway address manager
%%--------------------------------------------------------------------
-define(MANUAL, 2).
-define(BROADCAST, 1).
-define(PARAPHRASE, 0).
-type gw_src() :: ?MANUAL | ?BROADCAST | ?PARAPHRASE.

-record(gw_info,
{
  id :: bitstring(),
  host :: host(),
  port :: inet:port_number(),
  from :: gw_src()
}).

-record(gw_collect, {
  id :: bitstring(),
  host :: host(),
  port :: inet:port_number()
}).

%%--------------------------------------------------------------------
%% permanent information for state machine
%%--------------------------------------------------------------------
-type state() :: #state{}.

-record(state,
{name :: string(),
 config :: #config{},
 waiting_data :: tuple(),
 socket :: inet:socket(),
 next_packet_id = 0 :: integer(),
 msg_manager = #{} :: dict(topic_id(), queue:queue()),
 msg_counter = #{} :: dict(topic_id(), pos_integer()),
 topic_id_name = #{} :: dict(topic_id(), bitstring()),
 topic_name_id = #{} :: dict(bitstring(), topic_id()),
 topic_id_use_qos = #{} :: dict(topic_id(), qos()),
 active_gw = #gw_collect{} :: gw_collect(),
 gw_failed_cycle = 0 :: pos_integer()}).