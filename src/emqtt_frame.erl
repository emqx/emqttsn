%%-------------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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
%%-------------------------------------------------------------------------

-module(emqtt_frame).

-include("packet.hrl").
-include("config.hrl").

-export_type([parse_fun/0, serialize_fun/0]).

-opaque parse_result() :: {ok, #mqtt_packet{}}.

-type parse_fun() :: fun((binary()) -> parse_result()).
-type serialize_fun() :: fun((emqx_types:packet()) -> iodata()).

%%--------------------------------------------------------------------
%% Init Config State
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Parse MQTT-SN Frame
%%--------------------------------------------------------------------

% parser API for packet
-spec parse(binary()) -> parse_result().
parse(Bin) ->
  parse_leading_len(Bin).

% parse and verify the length of packet
-spec parse_leading_len(binary()) -> parse_result().
parse_leading_len(<<16#01, Length:16/binary, Rest/binary>>) ->
  #option{strict_mode = StrictMode} = emqtt_utils:get_option(),
  %% Validate length if strict mode.
  StrictMode andalso byte_size(Rest) + 3 == Length,
  parse_payload_type(Rest);
parse_leading_len(<<Length:8/binary, Rest/binary>>) ->
  %% Validate length if strict mode.
  #option{strict_mode = StrictMode} = emqtt_utils:get_option(),
  StrictMode andalso byte_size(Rest) + 1 == Length,
  parse_payload_type(Rest).

% parse the message type to a header of packet
-spec parse_payload_type(binary()) -> parse_result().
parse_payload_type(<<Type:8/binary, Rest/binary>>) ->
  Header = #mqtt_packet_header{type = Type},
  Payload = parse_payload(Rest, Header),
  #mqtt_packet{header = Header, payload = Payload}.

% dispatch to the parser of different message type
-spec parse_payload(binary(), #mqtt_packet_header{}) -> parse_result().
parse_payload(<<GwId:8/binary, Duration:16/binary>>,
              #mqtt_packet_header{type = ?ADVERTISE}) ->
  #mqtt_packet_advertise{gateway_id = GwId, duration = Duration};
parse_payload(<<Radius:8/binary>>, #mqtt_packet_header{type = ?SEARCHGW}) ->
  #mqtt_packet_searchgw{radius = Radius};
parse_payload(Bin, #mqtt_packet_header{type = ?GWINFO}) ->
  parse_gwinfo_msg(Bin);
parse_payload(<<ReturnCode:1/binary>>, #mqtt_packet_header{type = ?CONNACK}) ->
  #mqtt_packet_connack{return_code = ReturnCode};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLTOPICREQ}) ->
  #mqtt_packet_willtopicreq{};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLMSGREQ}) ->
  #mqtt_packet_willmsgreq{};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>,
              #mqtt_packet_header{type = ?REGISTER}) ->
  #mqtt_packet_register{source = ?SERVER,
                        topic_id = TopicId,
                        packet_id = MsgId,
                        topic_name = TopicName};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?REGACK}) ->
  #mqtt_packet_regack{topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>,
              #mqtt_packet_header{type = ?PUBLISH}) ->
  #mqtt_packet_publish{flag = parse_flag(Flag),
                       topic_id = TopicId,
                       packet_id = MsgId,
                       data = Data};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?PUBACK}) ->
  #mqtt_packet_puback{topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREC}) ->
  #mqtt_packet_pubrec{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREL}) ->
  #mqtt_packet_pubrel{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBCOMP}) ->
  #mqtt_packet_pubcomp{packet_id = MsgId};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?SUBACK}) ->
  #mqtt_packet_suback{flag = parse_flag(Flag),
                      topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?UNSUBACK}) ->
  #mqtt_packet_unsuback{packet_id = MsgId};
parse_payload(<<ClienId/binary>>, #mqtt_packet_header{type = ?PINGREQ}) ->
  #mqtt_packet_pingreq{client_id = ClienId};
parse_payload(<<>>, #mqtt_packet_header{type = ?PINGRESP}) ->
  #mqtt_packet_pingresp{};
parse_payload(Bin, #mqtt_packet_header{type = ?DISCONNECT}) ->
  parse_disconnect_msg(Bin);
parse_payload(<<ReturnCode:2/binary>>, #mqtt_packet_header{type = ?WILLTOPICRESP}) ->
  #mqtt_packet_willtopicresp{return_code = ReturnCode};
parse_payload(<<ReturnCode:2/binary>>, #mqtt_packet_header{type = ?WILLMSGRESP}) ->
  #mqtt_packet_willmsgresp{return_code = ReturnCode}.

-spec parse_flag(binary()) -> flag().
parse_flag(<<DUP:1/binary,
             Qos:2/binary,
             Retain:1/binary,
             Will:1/binary,
             CleanSession:1/binary,
             TopicIdType:2/binary>>) ->
  #mqtt_packet_flag{dup = DUP,
                    qos = Qos,
                    retain = Retain,
                    will = Will,
                    clean_session = CleanSession,
                    topic_id_type = TopicIdType}.

-spec parse_gwinfo_msg(binary()) -> parse_result().
parse_gwinfo_msg(<<GWId:8/binary>>) ->
  #mqtt_packet_gwinfo{source = ?SERVER, gateway_id = GWId};
parse_gwinfo_msg(<<GWId:8/binary, GwAdd/binary>>) ->
  #mqtt_packet_gwinfo{source = ?CLIENT,
                      gateway_id = GWId,
                      gateway_add = GwAdd}.

-spec parse_disconnect_msg(binary()) -> parse_result().
parse_disconnect_msg(<<>>) ->
  #mqtt_packet_disconnect{empty_packet = true};
parse_disconnect_msg(<<Duration:16/binary>>) ->
  #mqtt_packet_disconnect{empty_packet = false, duration = Duration}.

% %%--------------------------------------------------------------------
% %% Serialize MQTT Packet
% %%--------------------------------------------------------------------

-spec serialize(#mqtt_packet{}) -> iodata().
serialize(#mqtt_packet{header = Header, payload = Payload}) ->
  PayloadBin = serialize_payload(Payload),
  Length = iolist_size(PayloadBin),
  HeaderBin = serialize_header(Header, Length),
  [HeaderBin, PayloadBin].

-spec serialize_header(#mqtt_packet_header{}, integer()) -> iodata().
serialize_header(#mqtt_packet_header{type = Type}, Length) when Length < 256 ->
  <<Length:8, Type:8>>;
serialize_header(#mqtt_packet_header{type = Type}, Length)
  when 256 =< Length andalso Length =< ?MAX_PACKET_SIZE ->
  <<16#01:1, Length:16, Type:8>>.

-spec serialize_flag(#mqtt_packet_flag{}) -> iodata().
serialize_flag(#mqtt_packet_flag{dup = Dup,
                                 qos = Qos,
                                 retain = Retain,
                                 will = Will,
                                 clean_session = CleanSession,
                                 topic_id_type = TopicIdType}) ->
  <<Dup:1, Qos:2, Retain:1, Will:1, CleanSession:1, TopicIdType:2>>.

-spec serialize_payload(packet_payload()) -> iodata().
serialize_payload(#mqtt_packet_searchgw{radius = Radius}) ->
  <<Radius:8>>;
serialize_payload(#mqtt_packet_gwinfo{source = Source,
                                      gateway_id = GateWayId,
                                      gateway_add = GateWayAdd}) ->
  #option{strict_mode = StrictMode} = emqtt_utils:get_option(),
  StrictMode andalso Source == ?CLIENT,
  [<<GateWayId:8>>, GateWayAdd];
serialize_payload(#mqtt_packet_connect{flag = Flag,
                                       duration = Duration,
                                       client_id = ClientId}) ->
  SerFlag = serialize_flag(Flag),
  [SerFlag, <<16#01:1, Duration:2, ClientId>>];
serialize_payload(#mqtt_packet_willtopic{} = Bin) ->
  serialize_will_topic(Bin);
serialize_payload(#mqtt_packet_willmsg{will_msg = WillMsg}) ->
  <<WillMsg>>;
serialize_payload(#mqtt_packet_register{source = ?SERVER,
                                        topic_id = TopicId,
                                        packet_id = MsgId,
                                        topic_name = TopicName}) ->
  <<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>;
serialize_payload(#mqtt_packet_regack{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode}) ->
  <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_publish{flag = Flag,
                                       topic_id = TopicId,
                                       packet_id = MsgId,
                                       data = Data}) ->
  SerFlag = serialize_flag(Flag),
  <<SerFlag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>;
serialize_payload(#mqtt_packet_puback{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode}) ->
  <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_pubrec{packet_id = MsgId}) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubrel{packet_id = MsgId}) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubcomp{packet_id = MsgId}) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_subscribe{flag = Flag,
                                         packet_id = MsgId,
                                         topic_name = TopicName,
                                         topic_id = TopicId}) ->
  SerFlag = serialize_flag(Flag),
  Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
  <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_unsubscribe{flag = Flag,
                                           packet_id = MsgId,
                                           topic_name = TopicName,
                                           topic_id = TopicId}) ->
  SerFlag = serialize_flag(Flag),
  Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
  <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_pingreq{} = Bin) ->
  serialize_pingreq(Bin);
serialize_payload(#mqtt_packet_pingresp{}) ->
  <<>>;
serialize_payload(#mqtt_packet_disconnect{} = Bin) ->
  serialize_disconnect(Bin);
serialize_payload(#mqtt_packet_willtopicupd{} = Bin) ->
  serialize_willtopicupd(Bin);
serialize_payload(#mqtt_packet_willmsgupd{will_msg = WillMsg}) ->
  <<WillMsg>>.

% serialize willTopic packet payload
-spec serialize_will_topic(#mqtt_packet_willtopic{}) -> iodata().
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = true}) ->
  <<>>;
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = false,
                                            flag = Flag,
                                            will_topic = WillTopic}) ->
  SerFlag = serialize_flag(Flag),
  [SerFlag, <<WillTopic>>].

% serialize topicName or topicId by Flag argument topicIdType
-spec serialize_topic_name_or_id(#mqtt_packet_flag{}, bitstring(), topic_id()) ->
  iodata().
serialize_topic_name_or_id(Flag = #mqtt_packet_flag{topic_id_type = ?PRE_DEF_TOPIC_ID},
                           _TopicName,
                           TopicId) ->
  <<TopicId:2>>;
serialize_topic_name_or_id(Flag =
                           #mqtt_packet_flag{topic_id_type = [?SHORT_TOPIC_NAME | ?TOPIC_NAME]},
                           TopicName,
                           _TopicId) ->
  <<TopicName>>.

% serialize pingReq packet payload
-spec serialize_pingreq(#mqtt_packet_pingreq{}) -> iodata().
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = true}) ->
  <<>>;
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = false, client_id = ClienId}) ->
  <<ClienId>>.

-spec serialize_disconnect(#mqtt_packet_disconnect{}) -> iodata().
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = true}) ->
  <<>>;
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = false,
                                             duration = Duration}) ->
  <<Duration:2/binary>>.

-spec serialize_willtopicupd(#mqtt_packet_willtopicupd{}) -> iodata().
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true}) ->
  <<>>;
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true,
                                                 flag = Flag,
                                                 will_topic = WillTopic}) ->
  SerFlag = serialize_flag(Flag),
  <<SerFlag:8/binary, WillTopic>>.
