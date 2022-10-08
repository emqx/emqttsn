-module(emqttsn_send).

-include_lib("stdlib/include/assert.hrl").

-include("packet.hrl").
-include("config.hrl").

%% API
-export([send_connect/6, send_willtopic/5, send_willmsg/3, send_register/4, send_regack/5,
         send_subscribe/7, send_publish/9, send_puback/5, send_pubrel/3, send_pubrec/3,
         send_pubcomp/3, send_pub_any/7, send_gwinfo/7, send_disconnect/2, send_asleep/3,
         send_awake/3, send_pingreq/2, send_pingresp/2, broadcast_searchgw/4]).

-spec send_connect(config(),
                   inet:socket(),
                   boolean(),
                   boolean(),
                   pos_integer(),
                   bin_1_byte()) ->
                    ok | {error, term()}.
send_connect(Config, Socket, Will, CleanSession, Duration, ClientId) ->
  Packet = ?CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_willtopic(config(), inet:socket(), qos(), boolean(), string()) -> ok | {error, term()}.
send_willtopic(Config, Socket, Qos, Retain, WillTopic) ->
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_willmsg(config(), inet:socket(), string()) -> ok | {error, term()}.
send_willmsg(Config, Socket, WillMsg) ->
  Packet = ?WILLMSG_PACKET(WillMsg),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_register(config(), inet:socket(), packet_id(), string()) -> ok | {error, term()}.
send_register(Config, Socket, PacketId, TopicName) ->
  Packet = ?REGISTER_PACKET(PacketId, TopicName),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_regack(config(), inet:socket(), topic_id(), packet_id(), return_code()) ->
                   ok | {error, term()}.
send_regack(Config, Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_subscribe(config(),
                     inet:socket(),
                     boolean(),
                     topic_id_type(),
                     packet_id(),
                     topic_id_or_name(),
                     qos()) ->
                      ok | {error, term()}.
send_subscribe(Config, Socket, Dup, TopicIdType, PacketId, TopicIdOrName, MaxQos) ->
  Packet =
    case TopicIdType of
      ?SHORT_TOPIC_NAME ->
        ?SUBSCRIBE_PACKET(Dup, PacketId, TopicIdOrName, MaxQos);
      _ ->
        ?SUBSCRIBE_PACKET(Dup, TopicIdType, PacketId, TopicIdOrName, MaxQos)
    end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_publish(config(),
                   inet:socket(),
                   qos(),
                   boolean(),
                   boolean(),
                   topic_id_type(),
                   topic_id_or_name(),
                   packet_id(),
                   string()) ->
                    ok | {error, term()}.
send_publish(Config,
             Socket,
             Qos,
             Dup,
             Retain,
             TopicIdType,
             TopicIdOrName,
             PacketId,
             Message) ->
  ?assert(TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID),
  Packet =
    case Qos of
      ?QOS_0 ->
        ?PUBLISH_PACKET(Dup, Retain, TopicIdType, TopicIdOrName, Message);
      _ ->
        ?PUBLISH_PACKET(Dup, Qos, Retain, TopicIdType, TopicIdOrName, PacketId, Message)
    end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_puback(config(), inet:socket(), topic_id(), packet_id(), return_code()) ->
                   ok | {error, term()}.
send_puback(Config, Socket, TopicId, PacketId, ReturnCode) ->
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pubrel(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubrel(Config, Socket, PacketId) ->
  Packet = ?PUBREL_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pubrec(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubrec(Config, Socket, PacketId) ->
  Packet = ?PUBREC_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pubcomp(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubcomp(Config, Socket, PacketId) ->
  Packet = ?PUBCOMP_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pub_any(config(),
                   inet:socket(),
                   host(),
                   inet:port_number(),
                   topic_id_type(),
                   topic_id_or_name(),
                   string()) ->
                    ok | {error, term()}.
send_pub_any(Config, Socket, Address, Port, TopicIdType, TopicIdOrName, Message) ->
  ?assert(TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID),
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Message),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send_anywhere(Socket, Bin, Address, Port).

-spec send_gwinfo(config(),
                  inet:socket(),
                  host(),
                  inet:port_number(),
                  pos_integer(),
                  bin_1_byte(),
                  host()) ->
                   ok | {error, term()}.
send_gwinfo(Config, Socket, Address, Port, _Radius, GateWayId, GateWayAdd) ->
  Packet = ?GWINFO_PACKET(GateWayId, GateWayAdd),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send_anywhere(Socket, Bin, Address, Port).

-spec send_disconnect(config(), inet:socket()) -> ok | {error, term()}.
send_disconnect(Config, Socket) ->
  Packet = ?DISCONNECT_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_asleep(config(), inet:socket(), non_neg_integer()) -> ok | {error, term()}.
send_asleep(Config, Socket, Duration) ->
  Packet = ?DISCONNECT_PACKET(Duration),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_awake(config(), inet:socket(), bin_1_byte()) -> ok | {error, term()}.
send_awake(Config, Socket, ClientId) ->
  Packet = ?PINGREQ_PACKET(ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pingreq(config(), inet:socket()) -> ok | {error, term()}.
send_pingreq(Config, Socket) ->
  Packet = ?PINGREQ_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec send_pingresp(config(), inet:socket()) -> ok | {error, term()}.
send_pingresp(Config, Socket) ->
  Packet = ?PINGRESP_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

-spec broadcast_searchgw(config(),
                         inet:socket(),
                         inet:port_number(),
                         non_neg_integer()) ->
                          {ok, inet:socket()} | {error, term()}.
broadcast_searchgw(Config, Socket, RemotePort, Radius) ->
  Packet = ?SEARCHGW_PACKET(Radius),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:broadcast(Socket, Bin, RemotePort).

