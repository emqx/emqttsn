-module(emqttsn_send).

-include("Packet.hrl").
-include("config.hrl").
-include("logger.hrl").

%% API
-export([send_connect/6, send_willtopic/5, send_willmsg/3, send_register/4, send_regack/5, send_subscribe/6,
         send_publish/9, send_puback/5, send_pubrel/3, send_pubrec/3, send_pubcomp/3, send_pub_any/7, send_gwinfo/7,
         send_disconnect/2, send_asleep/3, send_awake/3, send_pingreq/2, send_pingresp/2, broadcast_searchgw/4]).

send_connect(Config, Socket, Will, CleanSession, Duration, ClientId) ->
  Packet = ?CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_willtopic(Config, Socket, Qos, Retain, WillTopic) ->
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_willmsg(Config, Socket, WillMsg) ->
  Packet = ?WILLMSG_PACKET(WillMsg),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_register(Config, Socket, PacketId, TopicName) ->
  Packet = ?REGISTER_PACKET(PacketId, TopicName),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_regack(Config, Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_subscribe(Config, Socket, TopicIdType, PacketId, TopicIdOrName, MaxQos) ->
  Packet = case TopicIdType of
             ?PRE_DEF_TOPIC_ID -> ?SUBSCRIBE_PACKET(PacketId, TopicIdOrName, MaxQos);
             _ -> ?SUBSCRIBE_PACKET(TopicIdType, PacketId, TopicIdOrName, MaxQos)
           end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_publish(Config, Socket, Qos, Dup, Retain, TopicIdType, TopicIdOrName, PacketId, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  Packet = case Qos of
             ?QOS_0 -> ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Data);
             _ -> ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Data)
           end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_puback(Config, Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pubrel(Config, Socket, PacketId) ->
  Packet = ?PUBREL_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pubrec(Config, Socket, PacketId) ->
  Packet = ?PUBREC_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pubcomp(Config, Socket, PacketId) ->
  Packet = ?PUBCOMP_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pub_any(Config, Socket, Address, Port, TopicIdType, TopicIdOrName, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Data),
  emqttsn_udp:send_anywhere(Socket, Packet, Address, Port).

send_gwinfo(Config, Socket, Address, Port, _Radius, GateWayId, GateWayAdd) ->
  Packet = ?GWINFO_PACKET(GateWayId, GateWayAdd),
  emqttsn_udp:send_anywhere(Socket, Packet, Address, Port).

send_disconnect(Config, Socket) ->
  Packet = ?DISCONNECT_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_asleep(Config, Socket, Duration) ->
  Packet = ?DISCONNECT_PACKET(Duration),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_awake(Config, Socket, ClientId) ->
  Packet = ?PINGREQ_PACKET(ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pingreq(Config, Socket) ->
  Packet = ?PINGREQ_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

send_pingresp(Config, Socket) ->
  Packet = ?PINGRESP_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

broadcast_searchgw(Config, Socket, RemotePort, Radius) ->
  Packet = ?SEARCHGW_PACKET(Radius),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:broadcast(Socket, Bin, RemotePort).