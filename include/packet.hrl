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
-include("version.hrl").

-ifndef(EMQTT_HRL).

-define(EMQTT_HRL, true).
-define(DUP_TRUE, true).
-define(DUP_FALSE, false).
-define(RESEND_TIME_BEG, 0).

-type bin_1_byte() :: <<_:8>>.
-type bin_2_byte() :: <<_:16>>.

-define(CLIENT_ID, "client").

-record(client, {state_m :: pid(), receiver :: pid()}).

-type client() :: #client{}.

%%%--------------------------------------------------------------------
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

-type return_code() :: ?RC_ACCEPTED | ?RC_CONGESTION | ?RC_INVALID_ID | ?RC_UNSUPPORTED.

%%--------------------------------------------------------------------
%% MQTT-SN Frame Mask
%%--------------------------------------------------------------------

-define(HIGHBIT, 2#10000000).
-define(LOWBITS, 2#01111111).

%%--------------------------------------------------------------------
%% MQTT-SN Topic ID Type
%%--------------------------------------------------------------------

-define(TOPIC_ID, 2#00).
-define(PRE_DEF_TOPIC_ID, 2#01).
-define(SHORT_TOPIC_NAME, 2#10).

-type topic_id_type() :: 2#00..2#11.
-type topic_id_or_name() :: topic_id() | string().

%%--------------------------------------------------------------------
%% MQTT Packet Fixed Header
%%--------------------------------------------------------------------

-record(mqttsn_packet_header, {type :: msg_type()}).

%%--------------------------------------------------------------------
%% MQTT Packets
%%--------------------------------------------------------------------

%% Default address
-define(DEFAULT_ADDRESS, {127, 0, 0, 1}).

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

-record(mqttsn_packet_flag,
        {dup = false :: boolean(),
         qos = ?QOS_0 :: qos(),
         retain = false :: boolean(),
         will = false :: boolean(),
         clean_session = false :: boolean(),
         topic_id_type = ?TOPIC_ID :: topic_id_type()}).

-type flag() :: #mqttsn_packet_flag{}.

%% MQTT-SN packets types
-record(mqttsn_packet_advertise, {gateway_id :: gw_id(), duration :: non_neg_integer()}).
-record(mqttsn_packet_searchgw, {radius :: non_neg_integer()}).
-record(mqttsn_packet_gwinfo,
        {source :: msg_src(), gateway_id :: gw_id(), gateway_add = ?DEFAULT_ADDRESS :: host()}).
-record(mqttsn_packet_connect,
        {proto_name = ?MQTTSN_PROTO_V1_2_NAME :: bitstring(),
         proto_ver = ?MQTTSN_PROTO_V1_2 :: version(),
         flag :: flag(),
         duration :: non_neg_integer(),
         client_id :: string()}).
-record(mqttsn_packet_connack, {return_code :: return_code()}).
-record(mqttsn_packet_willtopicreq, {}).
-record(mqttsn_packet_willtopic,
        {empty_packet :: boolean(), flag :: flag(), will_topic = "" :: string()}).
-record(mqttsn_packet_willmsgreq, {}).
-record(mqttsn_packet_willmsg, {will_msg :: string()}).
-record(mqttsn_packet_register,
        {source :: msg_src(),
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         topic_name :: string()}).
-record(mqttsn_packet_regack,
        {topic_id :: topic_id(), packet_id :: packet_id(), return_code :: return_code()}).
-record(mqttsn_packet_publish,
        {flag :: #mqttsn_packet_flag{},
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         message :: string()}).
-record(mqttsn_packet_puback,
        {topic_id :: topic_id(), packet_id :: packet_id(), return_code :: return_code()}).
-record(mqttsn_packet_pubrec, {packet_id :: packet_id()}).
-record(mqttsn_packet_pubrel, {packet_id :: packet_id()}).
-record(mqttsn_packet_pubcomp, {packet_id :: packet_id()}).
-record(mqttsn_packet_subscribe,
        {flag :: flag(),
         packet_id :: packet_id(),
         topic_name = "" :: string(),
         topic_id = 0 :: topic_id()}).
-record(mqttsn_packet_suback,
        {flag :: flag(),
         topic_id :: topic_id(),
         packet_id :: packet_id(),
         return_code :: return_code()}).
-record(mqttsn_packet_unsubscribe,
        {flag :: flag(),
         packet_id :: packet_id(),
         topic_name = "" :: string(),
         topic_id = 0 :: topic_id()}).
-record(mqttsn_packet_unsuback, {packet_id :: packet_id()}).
-record(mqttsn_packet_pingreq, {empty_packet :: boolean(), client_id :: string()}).
-record(mqttsn_packet_pingresp, {}).
-record(mqttsn_packet_disconnect,
        {empty_packet :: boolean(), duration = 0 :: non_neg_integer()}).
-record(mqttsn_packet_willtopicupd,
        {empty_packet :: boolean(), flag :: flag(), will_topic = "" :: string()}).
-record(mqttsn_packet_willmsgupd, {will_msg = "" :: string()}).
-record(mqttsn_packet_willtopicresp, {return_code :: return_code()}).
-record(mqttsn_packet_willmsgresp, {return_code :: return_code()}).

%%--------------------------------------------------------------------
%% MQTT Control Packet
%%--------------------------------------------------------------------

-type packet_payload() ::
        #mqttsn_packet_advertise{} | #mqttsn_packet_searchgw{} | #mqttsn_packet_gwinfo{} |
        #mqttsn_packet_connect{} | #mqttsn_packet_connack{} | #mqttsn_packet_willtopicreq{} |
        #mqttsn_packet_willtopic{} | #mqttsn_packet_willmsgreq{} | #mqttsn_packet_willmsg{} |
        #mqttsn_packet_register{} | #mqttsn_packet_regack{} | #mqttsn_packet_publish{} |
        #mqttsn_packet_puback{} | #mqttsn_packet_pubrec{} | #mqttsn_packet_pubrel{} |
        #mqttsn_packet_pubcomp{} | #mqttsn_packet_subscribe{} | #mqttsn_packet_suback{} |
        #mqttsn_packet_unsubscribe{} | #mqttsn_packet_unsuback{} | #mqttsn_packet_pingreq{} |
        #mqttsn_packet_pingresp{} | #mqttsn_packet_disconnect{} | #mqttsn_packet_willtopicupd{} |
        #mqttsn_packet_willmsgupd{} | #mqttsn_packet_willtopicresp{} |
        #mqttsn_packet_willmsgresp{}.

-record(mqttsn_packet, {header :: #mqttsn_packet_header{}, payload :: packet_payload()}).

-type mqttsn_packet() :: #mqttsn_packet{}.

%%--------------------------------------------------------------------
%% MQTT Packet Match
%%--------------------------------------------------------------------

-define(ADVERTISE_PACKET(GateWayId, Duration),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?ADVERTISE},
                       payload =
                               #mqttsn_packet_advertise{gateway_id = GateWayId,
                                                        duration = Duration}}).
-define(SEARCHGW_PACKET(Radius),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SEARCHGW},
                       payload = #mqttsn_packet_searchgw{radius = Radius}}).
-define(GWINFO_PACKET(GateWayId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?GWINFO},
                       payload =
                               #mqttsn_packet_gwinfo{source = ?SERVER,
                                                     gateway_id = GateWayId,
                                                     gateway_add = {0, 0, 0, 0}}}).
-define(GWINFO_PACKET(GateWayId, GateWayAdd),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?GWINFO},
                       payload =
                               #mqttsn_packet_gwinfo{source = ?CLIENT,
                                                     gateway_id = GateWayId,
                                                     gateway_add = GateWayAdd}}).
-define(CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?CONNECT},
                       payload =
                               #mqttsn_packet_connect{flag =
                                                              #mqttsn_packet_flag{will = Will,
                                                                                  clean_session =
                                                                                          CleanSession},
                                                      duration = Duration,
                                                      client_id = ClientId}}).
-define(CONNACK_PACKET(ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?CONNACK},
                       payload = #mqttsn_packet_connack{return_code = ReturnCode}}).
-define(WILLTOPICREQ_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPICREQ},
                       payload = #mqttsn_packet_willtopicreq{}}).
-define(WILLTOPIC_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPIC},
                       payload = #mqttsn_packet_willtopic{empty_packet = true}}).
-define(WILLTOPIC_PACKET(Qos, Retain, WillTopic),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPIC},
                       payload =
                               #mqttsn_packet_willtopic{empty_packet = false,
                                                        flag =
                                                                #mqttsn_packet_flag{qos = Qos,
                                                                                    retain =
                                                                                            Retain},
                                                        will_topic = WillTopic}}).
-define(WILLMSGREQ_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLMSGREQ},
                       payload = #mqttsn_packet_willmsgreq{}}).
-define(WILLMSG_PACKET(WillMsg),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLMSG},
                       payload = #mqttsn_packet_willmsg{will_msg = WillMsg}}).
-define(REGISTER_PACKET(PacketId, TopicName),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?REGISTER},
                       payload =
                               #mqttsn_packet_register{source = ?CLIENT,
                                                       topic_id = 0,
                                                       packet_id = PacketId,
                                                       topic_name = TopicName}}).
-define(REGISTER_PACKET(TopicId, PacketId, TopicName),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?REGISTER},
                       payload =
                               #mqttsn_packet_register{source = ?SERVER,
                                                       topic_id = TopicId,
                                                       packet_id = PacketId,
                                                       topic_name = TopicName}}).
-define(REGACK_PACKET(TopicId, PacketId, ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?REGACK},
                       payload =
                               #mqttsn_packet_regack{topic_id = TopicId,
                                                     packet_id = PacketId,
                                                     return_code = ReturnCode}}).
-define(PUBLISH_PACKET(TopicIdType, TopicIdOrName, Message),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBLISH},
                       payload =
                               #mqttsn_packet_publish{flag =
                                                              #mqttsn_packet_flag{qos = ?QOS_neg,
                                                                                  topic_id_type =
                                                                                          TopicIdType},
                                                      topic_id = TopicIdOrName,
                                                      packet_id = 0,
                                                      message = Message}}).
-define(PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Message),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBLISH},
                       payload =
                               #mqttsn_packet_publish{flag =
                                                              #mqttsn_packet_flag{dup = Dup,
                                                                                  qos = ?QOS_0,
                                                                                  retain = Retain,
                                                                                  topic_id_type =
                                                                                          TopicIdType},
                                                      topic_id = TopicIdOrName,
                                                      packet_id = 0,
                                                      message = Message}}).
-define(PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Message),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBLISH},
                       payload =
                               #mqttsn_packet_publish{flag =
                                                              #mqttsn_packet_flag{dup = Dup,
                                                                                  qos = Qos,
                                                                                  retain = Retain,
                                                                                  topic_id_type =
                                                                                          TopicIdType},
                                                      topic_id = TopicIdOrName,
                                                      packet_id = PacketId,
                                                      message = Message}}).
-define(PUBACK_PACKET(TopicId, PacketId, ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBACK},
                       payload =
                               #mqttsn_packet_puback{topic_id = TopicId,
                                                     packet_id = PacketId,
                                                     return_code = ReturnCode}}).
-define(PUBREC_PACKET(PacketId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBREC},
                       payload = #mqttsn_packet_pubrec{packet_id = PacketId}}).
-define(PUBREL_PACKET(PacketId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBREL},
                       payload = #mqttsn_packet_pubrel{packet_id = PacketId}}).
-define(PUBCOMP_PACKET(PacketId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PUBCOMP},
                       payload = #mqttsn_packet_pubcomp{packet_id = PacketId}}).
-define(SUBSCRIBE_PACKET(Dup, PacketId, TopicName, MaxQos),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SUBSCRIBE},
                       payload =
                               #mqttsn_packet_subscribe{flag =
                                                                #mqttsn_packet_flag{dup = Dup,
                                                                                    qos = MaxQos,
                                                                                    topic_id_type =
                                                                                            ?SHORT_TOPIC_NAME},
                                                        packet_id = PacketId,
                                                        topic_name = TopicName}}).
-define(SUBSCRIBE_PACKET(Dup, TopicIdTypeNotName, PacketId, TopicId, MaxQos),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SUBSCRIBE},
                       payload =
                               #mqttsn_packet_subscribe{flag =
                                                                #mqttsn_packet_flag{dup = Dup,
                                                                                    qos = MaxQos,
                                                                                    topic_id_type =
                                                                                            TopicIdTypeNotName},
                                                        packet_id = PacketId,
                                                        topic_id = TopicId}}).
-define(SUBACK_PACKET(Qos, TopicId, PacketId, ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SUBACK},
                       payload =
                               #mqttsn_packet_suback{flag = #mqttsn_packet_flag{qos = Qos},
                                                     topic_id = TopicId,
                                                     packet_id = PacketId,
                                                     return_code = ReturnCode}}).
-define(UNSUBSCRIBE_PACKET(PacketId, TopicName),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SUBSCRIBE},
                       payload =
                               #mqttsn_packet_unsubscribe{flag =
                                                                  #mqttsn_packet_flag{topic_id_type
                                                                                              =
                                                                                              ?SHORT_TOPIC_NAME},
                                                          packet_id = PacketId,
                                                          topic_name = TopicName}}).
-define(UNSUBSCRIBE_PACKET(TopicIdTypeNotName, PacketId, TopicId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?SUBSCRIBE},
                       payload =
                               #mqttsn_packet_unsubscribe{flag =
                                                                  #mqttsn_packet_flag{topic_id_type
                                                                                              =
                                                                                              TopicIdTypeNotName},
                                                          packet_id = PacketId,
                                                          topic_id = TopicId}}).
-define(UNSUBACK_PACKET(PacketId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?UNSUBACK},
                       payload = #mqttsn_packet_unsuback{packet_id = PacketId}}).
-define(PINGREQ_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PINGREQ},
                       payload = #mqttsn_packet_pingreq{empty_packet = true}}).
-define(PINGREQ_PACKET(ClientId),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PINGREQ},
                       payload =
                               #mqttsn_packet_pingreq{empty_packet = false, client_id = ClientId}}).
-define(PINGRESP_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?PINGRESP},
                       payload = #mqttsn_packet_pingresp{}}).
-define(DISCONNECT_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?DISCONNECT},
                       payload = #mqttsn_packet_disconnect{empty_packet = true}}).
-define(DISCONNECT_PACKET(Duration),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?DISCONNECT},
                       payload =
                               #mqttsn_packet_disconnect{empty_packet = false,
                                                         duration = Duration}}).
-define(WILLTOPICUPD_PACKET(),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPICUPD},
                       payload = #mqttsn_packet_willtopicupd{empty_packet = true}}).
-define(WILLTOPICUPD_PACKET(Qos, Retain, WillTopic),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPICUPD},
                       payload =
                               #mqttsn_packet_willtopicupd{empty_packet = false,
                                                           flag =
                                                                   #mqttsn_packet_flag{qos = Qos,
                                                                                       retain =
                                                                                               Retain},
                                                           will_topic = WillTopic}}).
-define(WILLMSGUPD_PACKET(WillMsg),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLMSGUPD},
                       payload = #mqttsn_packet_willmsgupd{will_msg = WillMsg}}).
-define(WILLTOPICRESP_PACKET(ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLTOPICRESP},
                       payload = #mqttsn_packet_willtopicresp{return_code = ReturnCode}}).
-define(WILLMSGRESP_PACKET(ReturnCode),
        #mqttsn_packet{header = #mqttsn_packet_header{type = ?WILLMSGRESP},
                       payload = #mqttsn_packet_willmsgresp{return_code = ReturnCode}}).

-endif.
