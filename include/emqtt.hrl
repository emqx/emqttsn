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

-ifndef(EMQTT_HRL).

-define(EMQTT_HRL, true).

%%--------------------------------------------------------------------
%% MQTT-SN Protocol Version and Names
%%--------------------------------------------------------------------

-define(MQTTSN_PROTO_V1_2, 0).
-define(PROTOCOL_NAMES, [ { '?,MQTTSN_PROTO_V1_2' , << "MQTT-SN" >> } , ] ).

%%--------------------------------------------------------------------
%% MQTT-SN QoS Levels
%%--------------------------------------------------------------------

%% At most once
-define(QOS_0, 0).
%% At least once
-define(QOS_1, 1).
%% Exactly once
-define(QOS_2, 2).

-type qos() :: ?QOS_0 | ?QOS_1 | ?QOS_2.

-define(IS_QOS(I), I >= ?QOS_0 andalso I =< ?QOS_2).
-define(QOS_I(Name),
        begin
                case Name of
                        ?QOS_0 ->
                                ?QOS_0;
                        qos0 ->
                                ?QOS_0;
                        at_most_once ->
                                ?QOS_0;
                        ?QOS_1 ->
                                ?QOS_1;
                        qos1 ->
                                ?QOS_1;
                        at_least_once ->
                                ?QOS_1;
                        ?QOS_2 ->
                                ?QOS_2;
                        qos2 ->
                                ?QOS_2;
                        exactly_once ->
                                ?QOS_2
                end
        end).
-define(IS_QOS_NAME(I),
        I =:= qos0
        orelse I =:= at_most_once
        orelse I =:= qos1
        orelse I =:= at_least_once
        orelse I =:= qos2
        orelse I =:= exactly_once).

%%--------------------------------------------------------------------
%% Maximum ClientId Length.
%%--------------------------------------------------------------------

%% TODO: 1-23 strings? is still 65535?

-define(MAX_CLIENTID_LEN, 65535).
%%--------------------------------------------------------------------
%% MQTT-SN v1.2 Message Source
%%--------------------------------------------------------------------
-define(CLIENT, 0).
-define(SERVER, 1).

-type msg_src() :: ?CLIENT | ?SERVER.

%%--------------------------------------------------------------------
%% MQTT-SN v1.2 Message Types
%%--------------------------------------------------------------------

%% TODO: note add
%% [ADVERTISE, SEARCHGW, GWINFO, WILLTOPICREQ, WILLTOPIC, WILLMSGREQ]
%% [WILLMSG, REGISTER, REGACK, WILLTOPICUPD, WILLTOPICRESP]
%% [WILLMSGUPD, WILLMSGRESP]
%% remove [AUTH]
-type msg_type() :: 16#00..16#FF.

%% Server to Client: Boardcast to info its address
-define(ADVERTISE, 0).
%% Client boardcast to search a server
-define(SEARCHGW, 1).
%% Client to Client: Boardcast answer to server address
-define(GWINFO, 2).
%% Client request to connect to server
-define(CONNECT, 4).
%% Server to Client: Connect acknowledgment
-define(CONNACK, 5).
%% Client send will topic
-define(WILLTOPICREQ, 6).
%% Server to Client: Will topic acknowledgment
-define(WILLTOPIC, 7).
%% Client send will message
-define(WILLMSGREQ, 8).
%% Server to Client: Will message acknowledgment
-define(WILLMSG, 9).
%% Client ask server for requesting a topic id
%% Server to Client: inform the topic id of a topic name
-define(REGISTER, 10).
%% Client inform acknowledgment
%% Server to Client: Register acknowledgment
-define(REGACK, 11).
%% Publish message
-define(PUBLISH, 12).
%% Publish acknowledgment
-define(PUBACK, 13).
%% Publish received (assured delivery part 1)
-define(PUBREC, 15).
%% Publish release (assured delivery part 2)
-define(PUBREL, 16).
%% Publish complete (assured delivery part 3)
-define(PUBCOMP, 14).
%% Client subscribe request
-define(SUBSCRIBE, 18).
%% Server Subscribe acknowledgment
-define(SUBACK, 19).
%% Unsubscribe request
-define(UNSUBSCRIBE, 20).
%% Unsubscribe acknowledgment
-define(UNSUBACK, 21).
%% PING request
-define(PINGREQ, 22).
%% PING response
-define(PINGRESP, 23).
%% Client or Server is disconnecting
-define(DISCONNECT, 24).
%% Update will topic request
-define(WILLTOPICUPD, 26).
%% Update will topic acknowledgment
-define(WILLTOPICRESP, 27).
%% Update will message request
-define(WILLMSGUPD, 28).
%% Update will message acknowledgment
-define(WILLMSGRESP, 29).
-define(TYPE_NAMES,
        ['ADVERTISE', 'SEARCHGW', 'GWINFO', 'CONNECT', 'CONNACK', 'WILLTOPICREQ', 'WILLTOPIC',
         'WILLMSGREQ', 'WILLMSG', 'REGISTER', 'REGACK', 'PUBLISH', 'PUBACK', 'PUBREC', 'PUBREL',
         'PUBCOMP', 'SUBSCRIBE', 'SUBACK', 'UNSUBSCRIBE', 'UNSUBACK', 'PINGREQ', 'PINGRESP',
         'DISCONNECT', 'WILLTOPICUPD', 'WILLTOPICRESP', 'WILLMSGUPD', 'WILLMSGRESP']).

%%--------------------------------------------------------------------
%% MQTT-SN V1.2 Reason Codes
%%--------------------------------------------------------------------

-define(RC_ACCEPTED, 0).
-define(RC_CONGESTION, 1).
-define(RC_INVALID_ID, 2).
-define(RC_UNSUPPORTED, 3).

-type rc_code() :: RC_ACCEPTED | RC_CONGESTION | RC_INVALID_ID | RC_UNSUPPORTED.

%%--------------------------------------------------------------------
%% Maximum MQTT-SN Packet ID and Length
%%--------------------------------------------------------------------

-define(MAX_PACKET_ID, 16#ffff).
-define(MAX_PACKET_SIZE, 16#fffffff).

%%--------------------------------------------------------------------
%% MQTT-SN Frame Mask
%%--------------------------------------------------------------------

-define(HIGHBIT, 2#10000000).
-define(LOWBITS, 2#01111111).

%%--------------------------------------------------------------------
%% MQTT-SN Topic ID Type
%%--------------------------------------------------------------------

-define(TOPIC_NAME, 2#00).
-define(PRE_DEF_TOPIC_ID, 2#01).
-define(SHORT_TOPIC_NAME, 2#01).

-type topic_id_type() :: 2#00..2#11.

%%--------------------------------------------------------------------
%% MQTT Packet Fixed Header
%%--------------------------------------------------------------------

-record(mqtt_packet_header, {type :: msg_type()}).

-type packet_header() :: #mqtt_packet_header{}.

%%--------------------------------------------------------------------
%% MQTT Packets
%%--------------------------------------------------------------------

%% Default address
-define(DEFAULT_ADDRESS, <<"127.0.0.1">>).

%% Retain Handling
% -define(DEFAULT_SUBOPTS, #{
%     rh => 0,
%     %% Retain as Publish
%     rap => 0,
%     %% No Local
%     nl => 0,
%     %% QoS
%     qos => 0
% }).

%% MQTT-SN flag variable
-type packet_id() :: 0..16#FFFF.
-type topic_id() :: 0..16#FFFF.

-record(mqtt_packet_flag,
        {dup = false :: boolean(),
         qos = ?QOS_0 :: qos(),
         retain = false :: boolean(),
         will = false :: boolean(),
         clean_session = false :: boolean(),
         topic_id_type = ?TOPIC_NAME :: topic_id_type()}).

-type flag() :: #mqtt_packet_flag{}.

%% MQTT-SN packets types
-record(mqtt_packet_advertise, {gateway_id :: integer(), duration :: integer()}).
-record(mqtt_packet_searchgw, {radius :: integer()}).
-record(mqtt_packet_gwinfo,
        {source :: msg_src(),
         gateway_id :: integer,
         gateway_add = ?DEFAULT_ADDRESS :: inet:ip_address()}).
-record(mqtt_packet_connect,
        {proto_name = <<"MQTT-SN">> :: bitstring(),
         proto_ver = ?MQTTSN_PROTO_V1_2,
         flag :: #mqtt_packet_flag{},
         duration :: integer(),
         client_id :: bitstring()}).
-record(mqtt_packet_connack, {return_code :: rc_code()}).
-record(mqtt_packet_willtopicreq, {}).
-record(mqtt_packet_willtopic,
        {empty_packet :: boolean(),
         flag :: #mqtt_packet_flag{},
         will_topic = <<>> :: bitstring()}).
-record(mqtt_packet_willmsgreq, {}).
-record(mqtt_packet_willmsg, {will_msg :: bitstring()}).
-record(mqtt_packet_register,
        {source :: msg_src(),
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         topic_name :: bitstring()}).
-record(mqtt_packet_regack,
        {topic_id :: topic_id(), packet_id :: packet_id(), return_code :: rc_code()}).
-record(mqtt_packet_publish,
        {flag :: #mqtt_packet_flag{},
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         data :: bitstring()}).
-record(mqtt_packet_puback,
        {topic_id :: topic_id(), packet_id :: packet_id(), return_code :: rc_code()}).
-record(mqtt_packet_pubrec, {packet_id :: packet_id()}).
-record(mqtt_packet_pubrel, {packet_id :: packet_id()}).
-record(mqtt_packet_pubcomp, {packet_id :: packet_id()}).
-record(mqtt_packet_subscribe,
        {flag :: #mqtt_packet_flag{},
         packet_id :: packet_id(),
         topic_name = <<>> :: bitstring(),
         topic_id = 0 :: bitstring()}).
-record(mqtt_packet_suback,
        {flag :: #mqtt_packet_flag{},
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         return_code :: rc_code()}).
-record(mqtt_packet_unsubscribe,
        {flag :: #mqtt_packet_flag{},
         packet_id :: packet_id(),
         topic_name = <<>> :: bitstring(),
         topic_id = 0 :: bitstring()}).
-record(mqtt_packet_unsuback, {packet_id :: packet_id()}).
-record(mqtt_packet_pingreq, {client_id :: bitstring()}).
-record(mqtt_packet_pingresp, {}).
-record(mqtt_packet_disconnect, {empty_packet :: boolean(), duration = 0 :: integer()}).
-record(mqtt_packet_willtopicupd,
        {empty_packet :: boolean(),
         flag :: #mqtt_packet_flag{},
         will_topic = <<>> :: bitstring()}).
-record(mqtt_packet_willmsgupd, {will_msg :: bitstring()}).
-record(mqtt_packet_willtopicresp, {return_code :: rc_code()}).
-record(mqtt_packet_willmsgresp, {return_code :: rc_code()}).

%%--------------------------------------------------------------------
%% MQTT Control Packet
%%--------------------------------------------------------------------

-record(mqtt_packet,
        {header :: #mqtt_packet_header{},
         payload ::
                 #mqtt_packet_advertise{} |
                 #mqtt_packet_searchgw{} |
                 #mqtt_packet_gwinfo{} |
                 #mqtt_packet_connect{} |
                 #mqtt_packet_connack{} |
                 #mqtt_packet_willtopicreq{} |
                 #mqtt_packet_willtopic{} |
                 #mqtt_packet_willmsgreq{} |
                 #mqtt_packet_willmsg{} |
                 #mqtt_packet_register{} |
                 #mqtt_packet_regack{} |
                 #mqtt_packet_publish{} |
                 #mqtt_packet_puback{} |
                 #mqtt_packet_subscribe{} |
                 #mqtt_packet_suback{} |
                 #mqtt_packet_unsubscribe{} |
                 #mqtt_packet_unsuback{} |
                 #mqtt_packet_pingreq{} |
                 #mqtt_packet_pingresp{} |
                 #mqtt_packet_disconnect{} |
                 #mqtt_packet_willtopicupd{} |
                 #mqtt_packet_willmsgupd{} |
                 #mqtt_packet_willtopicresp{} |
                 #mqtt_packet_willmsgresp{}}).

%%--------------------------------------------------------------------
%% MQTT Packet Match
%%--------------------------------------------------------------------

-define(ADVERTISE_PACKET(GateWayId, Duration),
        #mqtt_packet{header = #mqtt_packet_header{type = ?ADVERTISE},
                     payload =
                             #mqtt_packet_advertise{gateway_id = GateWayId, duration = Duration}}).
-define(SEARCHGW_PACKET(Radius),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SEARCHGW},
                     payload = #mqtt_packet_searchgw{radius = Radius}}).
-define(GWINFO_PACKET(GateWayId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?CONNECT},
                     payload =
                             #mqtt_packet_gwinfo{source = ?SERVER,
                                                 gateway_id = GateWayId,
                                                 gateway_add = <<"">>}}).
-define(GWINFO_PACKET(GateWayId, GateWayAdd),
        #mqtt_packet{header = #mqtt_packet_header{type = ?CONNECT},
                     payload =
                             #mqtt_packet_gwinfo{source = ?CLIENT,
                                                 gateway_id = GateWayId,
                                                 gateway_add = GateWayAdd}}).
-define(CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?CONNECT},
                     payload =
                             #mqtt_packet_connect{flag =
                                                          #mqtt_packet_flag{will = Will,
                                                                            clean_session =
                                                                                    CleanSession},
                                                  duration = Duration,
                                                  client_id = ClientId}}).
-define(CONNACK_PACKET(ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?CONNACK},
                     payload = #mqtt_packet_connack{return_code = ReturnCode}}).
-define(WILLTOPICREQ_PACKET(),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPICREQ},
                     payload = #mqtt_packet_willtopicreq{}}).
-define(WILLTOPIC_PACKET(),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPIC},
                     payload = #mqtt_packet_willtopic{empty_packet = true}}).
-define(WILLTOPIC_PACKET(Qos, Retain, WillTopic),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPIC},
                     payload =
                             #mqtt_packet_willtopic{empty_packet = false,
                                                    flag =
                                                            #mqtt_packet_flag{qos = Qos,
                                                                              retain = Retain},
                                                    will_topic = WillTopic}}).
-define(WILLMSGREQ_PACKET(ReasonCode, SessPresent, Properties),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLMSGREQ},
                     payload = #mqtt_packet_willmsgreq{}}).
-define(WILLMSG_PACKET(WillMsg),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLMSG},
                     payload = #mqtt_packet_willmsg{will_msg = WillMsg}}).
-define(REGISTER_PACKET(PacketId, TopicName),
        #mqtt_packet{header = #mqtt_packet_header{type = ?REGISTER},
                     payload =
                             #mqtt_packet_register{source = ?CLIENT,
                                                   topic_id = 0,
                                                   packet_id = PacketId,
                                                   will_msg = WillMsg}}).
-define(REGISTER_PACKET(TopicId, PacketId, TopicName),
        #mqtt_packet{header = #mqtt_packet_header{type = ?REGISTER},
                     payload =
                             #mqtt_packet_register{source = ?SERVER,
                                                   topic_id = TopicId,
                                                   packet_id = PacketId,
                                                   will_msg = WillMsg}}).
-define(REGACK_PACKET(TopicId, PacketId, ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?REGACK},
                     payload =
                             #mqtt_packet_regack{topic_id = TopicId,
                                                 packet_id = PacketId,
                                                 return_code = ReturnCode}}).
-define(PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicId, Data),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBLISH},
                     payload =
                             #mqtt_packet_publish{flag =
                                                          #mqtt_packet_flag{dup = Dup,
                                                                            qos = ?QOS_0,
                                                                            retain = Retain,
                                                                            topic_id_type =
                                                                                    TopicIdType},
                                                  topic_id = TopicId,
                                                  packet_id = 0,
                                                  data = Data}}).
-define(PUBLISH_PACKET(Dup, QosNot0, Retain, TopicIdType, TopicId, PacketId, Data),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBLISH},
                     payload =
                             #mqtt_packet_publish{flag =
                                                          #mqtt_packet_flag{dup = Dup,
                                                                            qos = QosNot0,
                                                                            retain = Retain,
                                                                            topic_id_type =
                                                                                    TopicIdType},
                                                  topic_id = TopicId,
                                                  packet_id = PacketId,
                                                  data = Data}}).
-define(PUBACK_PACKET(TopicId, PacketId, ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBACK},
                     payload =
                             #mqtt_packet_puback{topic_id = TopicId,
                                                 packet_id = PacketId,
                                                 return_code = ReturnCode}}).
-define(PUBREC_PACKET(PacketId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBREC},
                     payload = #mqtt_packet_pubrec{packet_id = PacketId}}).
-define(PUBREL_PACKET(PacketId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBREL},
                     payload = #mqtt_packet_pubrel{packet_id = PacketId}}).
-define(PUBCOMP_PACKET(PacketId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PUBCOMP},
                     payload = #mqtt_packet_pubcomp{packet_id = PacketId}}).
%% todo: here
-define(SUBSCRIBE_PACKET(PacketId, TopicId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE},
                     payload =
                             #mqtt_packet_subscribe{flag =
                                                            #mqtt_packet_flag{dup = Dup,
                                                                              qos = Qos,
                                                                              topic_id_type =
                                                                                      ?PRE_DEF_TOPIC_ID},
                                                    packet_id = PacketId,
                                                    topic_id = TopicId}}).
-define(SUBSCRIBE_PACKET(TopicIdTypeNotId, PacketId, TopicName),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE},
                     payload =
                             #mqtt_packet_subscribe{flag =
                                                            #mqtt_packet_flag{dup = Dup,
                                                                              qos = Qos,
                                                                              topic_id_type =
                                                                                      TopicIdTypeNotId},
                                                    packet_id = PacketId,
                                                    topic_name = TopicName}}).
-define(SUBACK_PACKET(Qos, TopicId, ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SUBACK},
                     payload =
                             #mqtt_packet_suback{flag = #mqtt_packet_flag{qos = Qos},
                                                 packet_id = PacketId,
                                                 return_code = ReturnCode}}).
-define(UNSUBSCRIBE_PACKET(PacketId, TopicId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE},
                     payload =
                             #mqtt_packet_unsubscribe{flag =
                                                              #mqtt_packet_flag{dup = Dup,
                                                                                qos = Qos,
                                                                                topic_id_type =
                                                                                        ?PRE_DEF_TOPIC_ID},
                                                      packet_id = PacketId,
                                                      topic_id = TopicId}}).
-define(UNSUBSCRIBE_PACKET(TopicIdTypeNotId, PacketId, TopicName),
        #mqtt_packet{header = #mqtt_packet_header{type = ?SUBSCRIBE},
                     payload =
                             #mqtt_packet_unsubscribe{flag =
                                                              #mqtt_packet_flag{dup = Dup,
                                                                                qos = Qos,
                                                                                topic_id_type =
                                                                                        TopicIdTypeNotId},
                                                      packet_id = PacketId,
                                                      topic_name = TopicName}}).
-define(UNSUBACK_PACKET(PacketId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?UNSUBACK},
                     payload = #mqtt_packet_unsuback{packet_id = PacketId}}).
-define(PINGREQ_PACKET(ClientId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PINGREQ},
                     payload = #mqtt_packet_pingreq{client = ClientId}}).
-define(PINGRESP_PACKET(ClientId),
        #mqtt_packet{header = #mqtt_packet_header{type = ?PINGREQ},
                     payload = #mqtt_packet_pingresp{}}).
-define(DISCONNECT_PACKET(),
        #mqtt_packet{header = #mqtt_packet_header{type = ?DISCONNECT},
                     payload = #mqtt_packet_disconnect{empty_packet = true}}).
-define(DISCONNECT_PACKET(Duration),
        #mqtt_packet{header = #mqtt_packet_header{type = ?DISCONNECT},
                     payload = #mqtt_packet_disconnect{empty_packet = false, duration = Duration}}).
-define(WILLTOPICUPD_PACKET(),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPICUPD},
                     payload = #mqtt_packet_willtopicupd{empty_packet = true}}).
-define(WILLTOPICUPD_PACKET(Qos, Retain, WillTopic),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPICUPD},
                     payload =
                             #mqtt_packet_willtopicupd{empty_packet = false,
                                                       flag =
                                                               #mqtt_packet_flag{qos = Qos,
                                                                                 retain = Retain},
                                                       duration = Duration}}).
-define(WILLMSGUPD_PACKET(WillMsg),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLMSGUPD},
                     payload = #mqtt_packet_willmsgupd{will_msg = WillMsg}}).
-define(WILLTOPICRESP_PACKET(ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLTOPICRESP},
                     payload = #mqtt_packet_willtopicresp{return_code = ReturnCode}}).
-define(WILLMSGRESP_PACKET(ReturnCode),
        #mqtt_packet{header = #mqtt_packet_header{type = ?WILLMSGRESP},
                     payload = #mqtt_packet_willmsgresp{return_code = ReturnCode}}).
-define(catch_error(Error, Exp),
        try
                Exp
        catch
                error:Error ->
                        ok
        end).

-endif.
