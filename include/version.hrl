%%--------------------------------------------------------------------
%% MQTT-SN Protocol Version and Names
%%--------------------------------------------------------------------

-define(MQTTSN_PROTO_V1_2, 2).
-define(PROTOCOL_NAMES, [{?MQTTSN_PROTO_V1_2, <<"MQTT-SN">>}]).


-type version() :: ?MQTTSN_PROTO_V1_2.