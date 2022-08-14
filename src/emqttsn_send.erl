-module(emqttsn_send).

-include("Packet.hrl").
-include("config.hrl").
-include("logger.hrl").

%% API
-export([send_connect/5, send_willtopic/4, send_willmsg/2, send_register/3, send_regack/4, send_subscribe/5,
         send_publish/8, send_puback/4, send_pubrel/2, send_pubrec/2, send_pubcomp/2, send_pub_any/6, send_gwinfo/6,
         send_disconnect/1, send_asleep/2, send_awake/2, send_pingreq/1, send_pingresp/1, broadcast_searchgw/3]).

send_connect(Socket, Will, CleanSession, Duration, ClientId) ->
  Packet = ?CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
  emqttsn_udp:send(Socket, Packet).

send_willtopic(Socket, Qos, Retain, WillTopic) ->
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),
  emqttsn_udp:send(Socket, Packet).

send_willmsg(Socket, WillMsg) ->
  Packet = ?WILLMSG_PACKET(WillMsg),
  emqttsn_udp:send(Socket, Packet).

send_register(Socket, PacketId, TopicName) ->
  Packet = ?REGISTER_PACKET(PacketId, TopicName),
  emqttsn_udp:send(Socket, Packet).

send_regack(Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),
  emqttsn_udp:send(Socket, Packet).

send_subscribe(Socket, TopicIdType, PacketId, TopicIdOrName, MaxQos) ->
  Packet = case TopicIdType of
             ?PRE_DEF_TOPIC_ID -> ?SUBSCRIBE_PACKET(PacketId, TopicIdOrName, MaxQos);
             _ -> ?SUBSCRIBE_PACKET(TopicIdType, PacketId, TopicIdOrName, MaxQos)
           end,
  emqttsn_udp:send(Socket, Packet).

send_publish(Socket, Qos, Dup, Retain, TopicIdType, TopicIdOrName, PacketId, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  Packet = case Qos of
             ?QOS_0 -> ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Data);
             _ -> ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Data)
           end,
  emqttsn_udp:send(Socket, Packet).

send_puback(Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),
  emqttsn_udp:send(Socket, Packet).

send_pubrel(Socket, PacketId) ->
  Packet = ?PUBREL_PACKET(PacketId),
  emqttsn_udp:send(Socket, Packet).

send_pubrec(Socket, PacketId) ->
  Packet = ?PUBREC_PACKET(PacketId),
  emqttsn_udp:send(Socket, Packet).

send_pubcomp(Socket, PacketId) ->
  Packet = ?PUBCOMP_PACKET(PacketId),
  emqttsn_udp:send(Socket, Packet).

send_pub_any(Socket, Address, Port, TopicIdType, TopicIdOrName, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Data),
  emqttsn_udp:send_anywhere(Socket, Packet, Address, Port).

send_gwinfo(Socket, Address, Port, _Radius, GateWayId, GateWayAdd) ->
  Packet = ?GWINFO_PACKET(GateWayId, GateWayAdd),
  emqttsn_udp:send_anywhere(Socket, Packet, Address, Port).

send_disconnect(Socket) ->
  Packet = ?DISCONNECT_PACKET(),
  emqttsn_udp:send(Socket, Packet).

send_asleep(Socket, Duration) ->
  Packet = ?DISCONNECT_PACKET(Duration),
  emqttsn_udp:send(Socket, Packet).

send_awake(Socket, ClientId) ->
  Packet = ?PINGREQ_PACKET(ClientId),
  emqttsn_udp:send(Socket, Packet).

send_pingreq(Socket) ->
  Packet = ?PINGREQ_PACKET(),
  emqttsn_udp:send(Socket, Packet).

send_pingresp(Socket) ->
  Packet = ?PINGRESP_PACKET(),
  emqttsn_udp:send(Socket, Packet).

broadcast_searchgw(Socket, RemotePort, Radius) ->
  Packet = ?SEARCHGW_PACKET(Radius),
  emqttsn_udp:broadcast(Socket, Packet, RemotePort).