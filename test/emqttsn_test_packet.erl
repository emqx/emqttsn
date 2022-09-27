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

-module(emqttsn_test_packet).

-compile(export_all).
-compile(nowarn_export_all).

-include("packet.hrl").
-include("config.hrl").

-include_lib("eunit/include/eunit.hrl").

all() ->
  [{group, parse},
   {group, discover},
   {group, connect},
   {group, connack},
   {group, publish},
   {group, puback},
   {group, subscribe},
   {group, suback},
   {group, unsubscribe},
   {group, unsuback},
   {group, ping},
   {group, disconnect}].

groups() ->
  [{parse,
    [parallel],
    [t_parse_short_length, t_parse_long_length, t_parse_frame_too_large]},
   {discover,
    [parallel],
    [t_serialize_parse_advertise,
     t_serialize_parse_searchgw,
     t_serialize_parse_gwinfo_from_gateway,
     t_serialize_parse_gwinfo_from_client]},
   {connect, [parallel], [t_serialize_parse_connect]},
   {will,
    [parallel],
    [t_serialize_parse_willtopicreq,
     t_serialize_parse_willtopic,
     t_serialize_parse_willtopic_empty,
     t_serialize_parse_willmsgreq,
     t_serialize_parse_willmsg]},
   {connack, [parallel], [t_serialize_parse_connack]},
   {register,
    [parallel],
    [t_serialize_parse_register_from_gateway, t_serialize_parse_register_from_client]},
   {regack, [parallel], [t_serialize_parse_regack]},
   {publish,
    [parallel],
    [t_serialize_parse_qos_neg_publish,
     t_serialize_parse_qos0_publish,
     t_serialize_parse_qos1_publish]},
   {puback,
    [parallel],
    [t_serialize_parse_puback,
     t_serialize_parse_pubrec,
     t_serialize_parse_pubrel,
     t_serialize_parse_pubcomp]},
   {subscribe,
    [parallel],
    [t_serialize_parse_subscribe_name, t_serialize_parse_subscribe_id]},
   {suback, [parallel], [t_serialize_parse_suback]},
   {unsubscribe,
    [parallel],
    [t_serialize_parse_unsubscribe_name, t_serialize_parse_unsubscribe_id]},
   {unsuback, [parallel], [t_serialize_parse_unsuback]},
   {ping,
    [parallel],
    [t_serialize_parse_pingreq,
     t_serialize_parse_pingreq_with_id,
     t_serialize_parse_pingresp]},
   {disconnect,
    [parallel],
    [t_serialize_parse_disconnect, t_serialize_parse_disconnect_with_duration]},
   {will_update,
    [parallel],
    [t_serialize_parse_willtopicupd_empty,
     t_serialize_parse_willtopicupd,
     t_serialize_parse_willmsgupd,
     t_serialize_parse_willtopicresp,
     t_serialize_parse_willmsgresp]}].

init_per_suite(Config) ->
  Config.

end_per_suite(_Config) ->
  ok.

init_per_group(_Group, Config) ->
  Config.

end_per_group(_Group, _Config) ->
  ok.

t_parse_short_length(_) ->
  Packet = ?PINGRESP_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, #config{}),
  {Length, Rest} = emqttsn_frame:parse_leading_len(Bin, #config{}),
  ?assertEqual(Length, 10),
  ?assertEqual(Rest, <<>>).

t_parse_long_length(_) ->
  Packet = ?PUBLISH_PACKET(?TOPIC_ID, 1, payload(1000)),
  Bin = emqttsn_frame:serialize(Packet, #config{}),
  {Length, Rest} = emqttsn_frame:parse_leading_len(Bin, #config{}),
  ?assertEqual(Length, 10),
  ?assertEqual(Rest, <<>>).

t_parse_frame_too_large(_) ->
  Packet = ?PUBLISH_PACKET(?TOPIC_ID, 1, payload(1000)),
  Bin = emqttsn_frame:serialize(Packet, #config{}),
  ?catch_error(frame_too_large, emqttsn_frame:parse(Bin, #config{max_size = 256})),
  ?catch_error(frame_too_large, emqttsn_frame:parse(Bin, #config{max_size = 512})),
  ?assertEqual(Packet, emqttsn_frame:parse(Bin, #config{max_size = 1024})).

t_serialize_parse_advertise(_) ->
  Bin = <<1, 2>>,

  GatewayId = 16#01,
  Duration = 50,
  Packet = ?ADVERTISE_PACKET(GatewayId, Duration),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_searchgw(_) ->
  Bin = <<1, 2>>,

  Radius = 50,
  Packet = ?SEARCHGW_PACKET(Radius),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_gwinfo_from_gateway(_) ->
  Bin = <<1, 2>>,

  GatewayId = 16#01,
  Packet = ?GWINFO_PACKET(GatewayId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_gwinfo_from_client(_) ->
  Bin = <<1, 2>>,

  GatewayId = 16#01,
  GateWayAdd = "127.0.0.1",
  Packet = ?GWINFO_PACKET(GatewayId, GateWayAdd),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopicreq(_) ->
  Bin = <<1, 2>>,

  Packet = ?WILLTOPICREQ_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopic(_) ->
  Bin = <<1, 2>>,

  Qos = ?QOS_0,
  Retain = false,
  WillTopic = "will topic",
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopic_empty(_) ->
  Bin = <<1, 2>>,

  Packet = ?WILLTOPIC_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willmsgreq(_) ->
  Bin = <<1, 2>>,

  Packet = ?WILLMSGREQ_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willmsg(_) ->
  Bin = <<1, 2>>,

  WillMsg = "will message",
  Packet = ?WILLMSG_PACKET(WillMsg),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_connack(_) ->
  Bin = <<1, 2>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?CONNACK_PACKET(ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_register_from_gateway(_) ->
  Bin = <<1, 2>>,

  TopicId = 16#01,
  PacketId = 1,
  TopicName = "topic name",
  Packet = ?REGISTER_PACKET(TopicId, PacketId, TopicName),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_register_from_client(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  TopicName = "topic name",
  Packet = ?REGISTER_PACKET(PacketId, TopicName),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_regack(_) ->
  Bin = <<1, 2>>,

  TopicId = 16#01,
  PacketId = 1,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_qos_neg_publish(_) ->
  Bin = <<1, 2>>,

  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  Message = "data",
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Message),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_qos0_publish(_) ->
  Bin = <<1, 2>>,

  Dup = false,
  Retain = false,
  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  Message = "data",
  Packet = ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Message),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_qos1_publish(_) ->
  Bin = <<1, 2>>,

  Dup = false,
  Qos = ?QOS_1,
  Retain = false,
  TopicIdType = ?TOPIC_ID,
  TopicIdOrName = 16#01,
  PacketId = 1,
  Message = "data",
  Packet = ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Message),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_puback(_) ->
  Bin = <<1, 2>>,

  TopicId = 16#01,
  PacketId = 1,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pubrec(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  Packet = ?PUBREC_PACKET(PacketId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pubrel(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  Packet = ?PUBREL_PACKET(PacketId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pubcomp(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  Packet = ?PUBCOMP_PACKET(PacketId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_subscribe_name(_) ->
  Bin = <<1, 2>>,

  Dup = false,
  PacketId = 1,
  TopicName = "tn",
  MaxQos = ?QOS_0,
  Packet = ?SUBSCRIBE_PACKET(Dup, PacketId, TopicName, MaxQos),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_subscribe_id(_) ->
  Bin = <<1, 2>>,

  TopicIdTypeNotName = ?TOPIC_ID,
  PacketId = 1,
  TopicId = 16#01,
  MaxQos = ?QOS_0,
  Packet = ?SUBSCRIBE_PACKET(TopicIdTypeNotName, PacketId, TopicId, MaxQos),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_suback(_) ->
  Bin = <<1, 2>>,

  Qos = ?QOS_0,
  PacketId = 1,
  TopicId = 16#01,
  ReturnCode = ?RC_ACCEPTED,
  Packet = ?SUBACK_PACKET(Qos, TopicId, PacketId, ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_unsubscribe_name(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  TopicId = "tn",
  Packet = ?UNSUBSCRIBE_PACKET(PacketId, TopicId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_unsubscribe_id(_) ->
  Bin = <<1, 2>>,

  TopicIdTypeNotName = ?TOPIC_ID,
  PacketId = 1,
  TopicId = 16#01,
  Packet = ?UNSUBSCRIBE_PACKET(TopicIdTypeNotName, PacketId, TopicId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_unsuback(_) ->
  Bin = <<1, 2>>,

  PacketId = 1,
  Packet = ?UNSUBACK_PACKET(PacketId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pingreq(_) ->
  Bin = <<1, 2>>,

  Packet = ?PINGREQ_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pingreq_with_id(_) ->
  Bin = <<1, 2>>,

  ClientId = 1,
  Packet = ?PINGREQ_PACKET(ClientId),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_pingresp(_) ->
  Bin = <<1, 2>>,

  Packet = ?PINGRESP_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_disconnect(_) ->
  Bin = <<1, 2>>,

  Packet = ?DISCONNECT_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_disconnect_with_duration(_) ->
  Bin = <<1, 2>>,

  Packet = ?DISCONNECT_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopicupd_empty(_) ->
  Bin = <<1, 2>>,

  Packet = ?WILLTOPICUPD_PACKET(),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopicupd(_) ->
  Bin = <<1, 2>>,

  Qos = ?QOS_0,
  Retain = true,
  WillTopic = "will_topic",
  Packet = ?WILLTOPICUPD_PACKET(Qos, Retain, WillTopic),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willmsgupd(_) ->
  Bin = <<1, 2>>,

  WillMsg = "will message",
  Packet = ?WILLMSGUPD_PACKET(WillMsg),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willtopicresp(_) ->
  Bin = <<1, 2>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?WILLTOPICRESP_PACKET(ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

t_serialize_parse_willmsgresp(_) ->
  Bin = <<1, 2>>,

  ReturnCode = ?RC_ACCEPTED,
  Packet = ?WILLMSGRESP_PACKET(ReturnCode),

  ?assertEqual(validate_ser_par(Bin, Packet), true).

payload(Len) ->
  iolist_to_binary(lists:duplicate(Len, 1)).

validate_ser_par(Bin, Packet) ->
  Cond1 =
    case emqttsn_frame:parse(Bin, #config{}) of
      {ok, Packet} ->
        true;
      _ ->
        false
    end,
  Cond2 =
    case emqttsn_frame:serialize(Packet, #config{}) of
      Bin ->
        true;
      _ ->
        false
    end,
  Cond1 and Cond2.
