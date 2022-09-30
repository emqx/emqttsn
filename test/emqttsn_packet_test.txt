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

-module(emqttsn_packet_test).

-include("packet.hrl").
-include("config.hrl").

-include_lib("eunit/include/eunit.hrl").

-define(VALIDATE_SER_PAR(Bin, Packet),
  ?_assertEqual({ok, Packet}, emqttsn_frame:parse(Bin, #config{})),
  ?_assertEqual(Bin, emqttsn_frame:serialize(Packet, #config{}))).

parse_short_length_test_() ->
  Packet = ?PINGRESP_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, #config{}),
  {ok, Length, LeadingLength, Rest} = emqttsn_frame:parse_leading_len(Bin, #config{}),
  ?_assertEqual(Length, 0),
  ?_assertEqual(LeadingLength, 1),
  ?_assertEqual(Rest, <<23>>).

parse_long_length_test_() ->
  Data = payload_string(1000),
  Packet = ?PUBLISH_PACKET(?TOPIC_ID, 1, Data),
  Bin = emqttsn_frame:serialize(Packet, #config{}),

  {ok, Length, LeadingLength, Rest} = emqttsn_frame:parse_leading_len(Bin, #config{}),
  ?_assertEqual(Length, 1000),
  ?_assertEqual(LeadingLength, 1),

  Flag = <<12, 96, 0, 1, 0, 0>>,
  Last = list_to_binary(Data),
  ?_assertEqual(Rest, <<Flag/binary, Last/binary>>).

parse_frame_too_large_test_() ->
  Packet = ?PUBLISH_PACKET(?TOPIC_ID, 1, payload_string(1000)),
  Bin = emqttsn_frame:serialize(Packet, #config{}),

  ?_assertEqual({error, frame_too_large}, emqttsn_frame:parse(Bin, #config{max_size = 1})),
  ?_assertEqual({error, frame_too_large},
                emqttsn_frame:parse(Bin, #config{max_size = 512})),
  ?_assertEqual({ok, Packet}, emqttsn_frame:parse(Bin, #config{max_size = 1024})).

serialize_parse_advertise_test_() ->
  Bin = <<5, 0, 1, 0, 50>>,

  GatewayId = 16#01,
  Duration = 50,
  Packet = ?ADVERTISE_PACKET(GatewayId, Duration),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_searchgw_test_() ->
  Bin = <<3, 1, 50>>,

  Radius = 50,
  Packet = ?SEARCHGW_PACKET(Radius),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_gwinfo_from_gateway_test_() ->
  Bin = <<3, 2, 1>>,

  GatewayId = 16#01,
  Packet = ?GWINFO_PACKET(GatewayId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_gwinfo_from_clien_test_() ->
  Bin = <<7, 2, 1, 114, 5, 1, 4>>,

  GatewayId = 16#01,
  GateWayAdd = {114, 5, 1, 4},
  Packet = ?GWINFO_PACKET(GatewayId, GateWayAdd),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopicreq_test_() ->
  Bin = <<2, 6>>,

  Packet = ?WILLTOPICREQ_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopic_test_() ->
  Bin = <<13, 7, 0, 119, 105, 108, 108, 32, 116, 111, 112, 105, 99>>,

  Qos = ?QOS_0,
  Retain = false,
  WillTopic = "will topic",
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopic_empty_test_() ->
  Bin = <<2, 7>>,

  Packet = ?WILLTOPIC_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willmsgreq_test_() ->
  Bin = <<2, 8>>,

  Packet = ?WILLMSGREQ_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willmsg_test_() ->
  Bin = <<14, 9, 119, 105, 108, 108, 32, 109, 101, 115, 115, 97, 103, 101>>,

  WillMsg = "will message",
  Packet = ?WILLMSG_PACKET(WillMsg),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_connack_test_() ->
  Bin = <<3, 5, 0>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?CONNACK_PACKET(ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_register_from_gateway_test_() ->
  Bin = <<16, 10, 0, 1, 0, 1, 116, 111, 112, 105, 99, 32, 110, 97, 109, 101>>,

  TopicId = 16#01,
  PacketId = 1,
  TopicName = "topic name",
  Packet = ?REGISTER_PACKET(TopicId, PacketId, TopicName),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_register_from_client_test_() ->
  Bin = <<16, 10, 0, 0, 0, 1, 116, 111, 112, 105, 99, 32, 110, 97, 109, 101>>,

  PacketId = 1,
  TopicName = "topic name",
  Packet = ?REGISTER_PACKET(PacketId, TopicName),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_regack_test_() ->
  Bin = <<7, 11, 0, 1, 0, 1, 8>>,

  TopicId = 16#01,
  PacketId = 1,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_qos_neg_publish_test_() ->
  Bin = <<11, 12, 96, 0, 1, 0, 0, 100, 97, 116, 97>>,

  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  Message = "data",
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Message),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_qos0_publish_test_() ->
  Bin = <<11, 12, 0, 0, 1, 0, 0, 100, 97, 116, 97>>,

  Dup = false,
  Retain = false,
  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  Message = "data",
  Packet = ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Message),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_qos1_publish_test_() ->
  Bin = <<11, 12, 32, 0, 1, 0, 1, 100, 97, 116, 97>>,

  Dup = false,
  Qos = ?QOS_1,
  Retain = false,
  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  PacketId = 1,
  Message = "data",
  Packet = ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Message),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_puback_test_() ->
  Bin = <<7, 13, 0, 1, 0, 1, 0>>,

  TopicId = 16#01,
  PacketId = 1,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pubrec_test_() ->
  Bin = <<4, 15, 0, 1>>,

  PacketId = 1,
  Packet = ?PUBREC_PACKET(PacketId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pubrel_test_() ->
  Bin = <<4, 16, 0, 1>>,

  PacketId = 1,
  Packet = ?PUBREL_PACKET(PacketId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pubcomp_test_() ->
  Bin = <<4, 14, 0, 1>>,

  PacketId = 1,
  Packet = ?PUBCOMP_PACKET(PacketId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_subscribe_name_test_() ->
  Bin = <<15, 18, 2, 0, 1, 116, 111, 112, 105, 99, 32, 110, 97, 109, 101>>,

  Dup = false,
  PacketId = 1,
  TopicName = "topic name",
  MaxQos = ?QOS_0,
  Packet = ?SUBSCRIBE_PACKET(Dup, PacketId, TopicName, MaxQos),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_subscribe_id_test_() ->
  Bin = <<7, 18, 128, 0, 1, 0, 1>>,

  Dup = true,
  TopicIdTypeNotName = ?TOPIC_ID,
  PacketId = 1,
  TopicId = 1,
  MaxQos = ?QOS_0,
  Packet = ?SUBSCRIBE_PACKET(Dup, TopicIdTypeNotName, PacketId, TopicId, MaxQos),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_suback_test_() ->
  Bin = <<8, 19, 0, 0, 1, 0, 1, 0>>,

  Qos = ?QOS_0,
  PacketId = 1,
  TopicId = 1,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?SUBACK_PACKET(Qos, TopicId, PacketId, ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_unsubscribe_name_test_() ->
  Bin = <<15, 18, 2, 0, 1, 116, 111, 112, 105, 99, 32, 110, 97, 109, 101>>,

  PacketId = 1,
  TopicName = "topic name",
  Packet = ?UNSUBSCRIBE_PACKET(PacketId, TopicName),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_unsubscribe_id_test_() ->
  Bin = <<7, 18, 0, 0, 1, 7, 127>>,

  TopicIdTypeNotName = ?TOPIC_ID,
  PacketId = 1,
  TopicId = 1919,
  Packet = ?UNSUBSCRIBE_PACKET(TopicIdTypeNotName, PacketId, TopicId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_unsuback_test_() ->
  Bin = <<4, 21, 0, 1>>,

  PacketId = 1,
  Packet = ?UNSUBACK_PACKET(PacketId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pingreq_test_() ->
  Bin = <<2, 22>>,

  Packet = ?PINGREQ_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pingreq_with_id_test_() ->
  Bin = <<8, 22, 99, 108, 105, 101, 110, 116>>,

  ClientId = "client",
  Packet = ?PINGREQ_PACKET(ClientId),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_pingresp_test_() ->
  Bin = <<2, 23>>,

  Packet = ?PINGRESP_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_disconnect_test_() ->
  Bin = <<2, 24>>,

  Packet = ?DISCONNECT_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_disconnect_with_duration_test_() ->
  Bin = <<4, 24, 0, 50>>,

  Duration = 50,
  Packet = ?DISCONNECT_PACKET(Duration),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopicupd_empty_test_() ->
  Bin = <<2, 26>>,

  Packet = ?WILLTOPICUPD_PACKET(),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopicupd_test_() ->
  Bin = <<13, 26, 16, 119, 105, 108, 108, 32, 116, 111, 112, 105, 99>>,

  Qos = ?QOS_0,
  Retain = true,
  WillTopic = "will topic",
  Packet = ?WILLTOPICUPD_PACKET(Qos, Retain, WillTopic),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willmsgupd_test_() ->
  Bin = <<14, 28, 119, 105, 108, 108, 32, 109, 101, 115, 115, 97, 103, 101>>,

  WillMsg = "will message",
  Packet = ?WILLMSGUPD_PACKET(WillMsg),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willtopicresp_test_() ->
  Bin = <<3, 27, 0>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?WILLTOPICRESP_PACKET(ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

serialize_parse_willmsgresp_test_() ->
  Bin = <<3, 29, 0>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?WILLMSGRESP_PACKET(ReturnCode),

  ?VALIDATE_SER_PAR(Bin, Packet).

-spec payload_string(pos_integer()) -> string.
payload_string(Len) ->
  lists:duplicate(Len, $h).


