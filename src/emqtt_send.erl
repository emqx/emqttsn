-module(emqtt_send).

-include("packet.hrl").
-include("config.hrl").
-include("logger.hrl").

%% API
-export([send_connect/4, send_willtopic/3, send_willmsg/1, send_register/2, send_regack/3, send_subscribe/3,
         send_publish/7, send_puback/3, send_pubrel/1, send_pubrec/1, send_pubcomp/1, send_pub_any/5, send_gwinfo/5,
         send_disconnect/0, send_asleep/1, send_awake/0, send_pingreq/0, send_pingresp/0, broadcast_searchgw/0]).

send_connect(Will, CleanSession, Duration, ClientId) ->
  packet = ?CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
  emqtt_udp:send(packet).

send_willtopic(Qos, Retain, WillTopic) ->
  packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),
  emqtt_udp:send(packet).

send_willmsg(WillMsg) ->
  packet = ?WILLMSG_PACKET(WillMsg),
  emqtt_udp:send(packet).

send_register(PacketId, TopicName) ->
  packet = ?REGISTER_PACKET(PacketId, TopicName),
  emqtt_udp:send(packet).

send_regack(TopicId, PacketId, ReturnCode) ->
  packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),
  emqtt_udp:send(packet).

send_subscribe(TopicIdType, PacketId, TopicIdOrName) ->
  packet = case TopicIdType of
             ?PRE_DEF_TOPIC_ID -> ?SUBSCRIBE_PACKET(PacketId, TopicIdOrName);
             _ -> ?SUBSCRIBE_PACKET(TopicIdType, PacketId, TopicIdOrName)
           end,
  emqtt_udp:send(packet).

send_publish(Qos, Dup, Retain, TopicIdType, TopicIdOrName, PacketId, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  packet = case Qos of
             ?QOS_0 -> ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Data);
             _ -> ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Data)
           end,
  emqtt_udp:send(packet).

send_puback(TopicId, PacketId, ReturnCode) ->
  packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),
  emqtt_udp:send(packet).

send_pubrel(PacketId) ->
  packet = ?PUBREL_PACKET(PacketId),
  emqtt_udp:send(packet).

send_pubrec(PacketId) ->
  packet = ?PUBREC_PACKET(PacketId),
  emqtt_udp:send(packet).

send_pubcomp(PacketId) ->
  packet = ?PUBCOMP_PACKET(PacketId),
  emqtt_udp:send(packet).

send_pub_any(Address, Port, TopicIdType, TopicIdOrName, Data) ->
  TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID,
  packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Data),
  emqtt_udp:send_anywhere(packet, Address, Port).

send_gwinfo(Address, Port, _Radius, GateWayId, GateWayAdd) ->
  packet = ?GWINFO_PACKET(GateWayId, GateWayAdd),
  emqtt_udp:send_anywhere(packet, Address, Port).

send_disconnect() ->
  packet = ?DISCONNECT_PACKET(),
  emqtt_udp:send(packet).

send_asleep(Duration) ->
  packet = ?DISCONNECT_PACKET(Duration),
  emqtt_udp:send(packet).

send_awake() ->
  #option{client_id = ClientId} = emqtt_utils:get_option(),
  packet = ?PINGREQ_PACKET(ClientId),
  emqtt_udp:send(packet).

send_pingreq() ->
  #option{client_id = ClientId} = emqtt_utils:get_option(),
  packet = ?PINGREQ_PACKET(ClientId),
  emqtt_udp:send(packet).

send_pingresp() ->
  #option{client_id = ClientId} = emqtt_utils:get_option(),
  packet = ?PINGRESP_PACKET(ClientId),
  emqtt_udp:send(packet).

broadcast_searchgw() ->
  #option{send_port = LocalPort, port = RemotePort, radius = Radius} = emqtt_utils:get_option(),
  packet = ?SEARCHGW_PACKET(Radius),
  emqtt_udp:broadcast(packet, RemotePort, LocalPort).