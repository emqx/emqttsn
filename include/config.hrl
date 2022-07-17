%%--------------------------------------------------------------------
%% Maximum MQTT-SN Packet ID and Length
%%--------------------------------------------------------------------

-include("version.hrl").

-define(ClientId, 16#01).
%% Default timeout
-define(DEFAULT_RETRY_INTERVAL, 30000).
-define(DEFAULT_ACK_TIMEOUT, 30000).
-define(DEFAULT_CONNECT_TIMEOUT, 60000).
-define(DEFAULT_SEARCH_GW_INTERVAL, 60000).
-define(DEFAULT_SLEEP_INTERVAL, 60000).
-define(DEFAULT_PORT, 1884).
% TODO: 检查这几个参数是否正确
-define(DEFAULT_PING_INTERVAL, 30000).
-define(DEFAULT_MAX_RESEND, 3).
-define(DEFAULT_MAX_RECONNECT, 3).
-define(MAX_PACKET_ID, 16#ffff).
-define(MAX_PACKET_SIZE, 16#ffff).

-type host() :: inet:ip_address() | inet:hostname().

-record(option,
{% system action config
 strict_mode = false :: boolean(),
 clean_session = true :: boolean(),
 max_size = ?MAX_PACKET_SIZE :: 1..?MAX_PACKET_SIZE,
 auto_discover = true :: boolean(),
 force_ping = true :: boolean(),
 ack_timeout = ?DEFAULT_ACK_TIMEOUT :: pos_integer(),
 ping_interval = ?DEFAULT_PING_INTERVAL :: pos_integer(),
 resend_no_qos = true :: boolean(),
 max_resend = ?DEFAULT_MAX_RESEND :: pos_integer(),
 retry_interval = ?DEFAULT_RETRY_INTERVAL :: pos_integer(),
 connect_timeout = ?DEFAULT_CONNECT_TIMEOUT :: pos_integer(),
 search_gw_interval = ?DEFAULT_SEARCH_GW_INTERVAL :: pos_integer(),
 reconnect_max_times = ?DEFAULT_MAX_RECONNECT :: pos_integer(),
 max_message_each_topic = 100 :: pos_integer(),
 sleep_interval = ?DEFAULT_SLEEP_INTERVAL :: pos_integer(),
%local config
 send_port = ?DEFAULT_PORT :: inet:port_number(),
% gateway config
 host :: host(),
 port = ?DEFAULT_PORT :: inet:port_number(),
% protocol config
 client_id = ?ClientId :: binary(),
 proto_ver = ?MQTTSN_PROTO_V1_2 :: version(),
 proto_name = proplists:get_value(?MQTTSN_PROTO_V1_2, ?PROTOCOL_NAMES) :: iodata(),
 radius = 3 :: pos_integer(),
 duration :: pos_integer(),
 qos :: qos(),
 clean_session :: boolean(),
 will :: boolean(),
 will_topic :: bitstring(),
 will_msg :: bitstring()}).
