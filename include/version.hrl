-ifndef(MQTTSN_PROTO_V1_2).

%%--------------------------------------------------------------------
%% MQTT-SN Protocol Version and Names
%%--------------------------------------------------------------------

-define(MQTTSN_PROTO_V1_2, 2).
-define(MQTTSN_PROTO_V1_2_NAME, "MQTT-SN").
-define(PROTOCOL_NAMES, [{?MQTTSN_PROTO_V1_2, ?MQTTSN_PROTO_V1_2_NAME}]).

-type version() :: ?MQTTSN_PROTO_V1_2.
-type host() :: inet:ip4_address().

%%--------------------------------------------------------------------
%% MQTT-SN QoS Levels
%%--------------------------------------------------------------------

%% At most once
-define(QOS_0, 0).
%% At least once
-define(QOS_1, 1).
%% Exactly once
-define(QOS_2, 2).
%% Simple publish for Qos Level -1
-define(QOS_neg, 3).

-type qos() :: ?QOS_0 | ?QOS_1 | ?QOS_2 | ?QOS_neg.

-define(IS_QOS(I), I >= ?QOS_0 andalso I =< ?QOS_neg).

%%--------------------------------------------------------------------
%% MQTT-SN Packet Info
%%--------------------------------------------------------------------

-type packet_id() :: 0..16#FFFF.
-type topic_id() :: 0..16#FFFF.
-type gw_id() :: 0..16#FF.

-endif.
