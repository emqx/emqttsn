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

%% @doc low-level API for send any type of standard
%% MQTT-SN packet, always used with <i>emqttsn_udp</i>
%%
%% Caution: If you want to use this module, please
%% stop the client from emqttsn if there is any!
%%
%% @see emqttsn_udp
%% @see emqttsn_udp:init_port/0
-module(emqttsn_send).

%% @headerfile "emqttsn.hrl"

-include_lib("stdlib/include/assert.hrl").

-include("emqttsn.hrl").

%% API
-export([send_connect/6, send_willtopic/5, send_willmsg/3, send_register/4, send_regack/5,
         send_subscribe/7, send_unsubscribe/5, send_publish/9, send_puback/5, send_pubrel/3,
         send_pubrec/3, send_pubcomp/3, send_pub_any/7, send_gwinfo/7, send_disconnect/2,
         send_asleep/3, send_awake/3, send_pingreq/2, send_pingresp/2, broadcast_searchgw/4]).

%% @doc Send a MQTT-SN Connect packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Will whether need will message for connect
%% @param CleanSession whether clean session for client
%% @param Duration interval of keep alive timer
%% @param ClientId unique name of client
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_connect(config(),
                   inet:socket(),
                   boolean(),
                   boolean(),
                   non_neg_integer(),
                   string()) ->
                    ok | {error, term()}.
send_connect(Config, Socket, Will, CleanSession, Duration, ClientId) ->
  Packet = ?CONNECT_PACKET(Will, CleanSession, Duration, ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN WillTopic packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Qos the qos level of will
%% @param Retain whether the message is retain
%% @param WillTopic the data of will topic
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_willtopic(config(), inet:socket(), qos(), boolean(), string()) ->
                      ok | {error, term()}.
send_willtopic(Config, Socket, Qos, Retain, WillTopic) ->
  Packet = ?WILLTOPIC_PACKET(Qos, Retain, WillTopic),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN WillMsg packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param WillMsg the data of will message
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_willmsg(config(), inet:socket(), string()) -> ok | {error, term()}.
send_willmsg(Config, Socket, WillMsg) ->
  Packet = ?WILLMSG_PACKET(WillMsg),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN WillMsg packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param TopicName topic name to be registered
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_register(config(), inet:socket(), string(), packet_id()) ->
                     ok | {error, term()}.
send_register(Config, Socket, TopicName, PacketId) ->
  Packet = ?REGISTER_PACKET(PacketId, TopicName),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN RegAck packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param TopicId topic id of packet
%% @param ReturnCode return code of request
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_regack(config(), inet:socket(), topic_id(), return_code(), packet_id()) ->
                   ok | {error, term()}.
send_regack(Config, Socket, TopicId, ReturnCode, PacketId) ->
  Packet = ?REGACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN Subscribe packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Dup whether it is a duplicated packet
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param MaxQos max Qos level can be handled of subscribed request
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_subscribe(config(),
                     inet:socket(),
                     boolean(),
                     topic_id_type(),
                     topic_id_or_name(),
                     qos(),
                     packet_id()) ->
                      ok | {error, term()}.
send_subscribe(Config, Socket, Dup, TopicIdType, TopicIdOrName, MaxQos, PacketId) ->
  Packet =
    case TopicIdType of
      ?SHORT_TOPIC_NAME ->
        ?SUBSCRIBE_PACKET(Dup, PacketId, TopicIdOrName, MaxQos);
      _ ->
        ?SUBSCRIBE_PACKET(Dup, TopicIdType, PacketId, TopicIdOrName, MaxQos)
    end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN Unsubscribe packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_unsubscribe(config(),
                       inet:socket(),
                       topic_id_type(),
                       topic_id_or_name(),
                       packet_id()) ->
                        ok | {error, term()}.
send_unsubscribe(Config, Socket, TopicIdType, TopicIdOrName, PacketId) ->
  Packet =
    case TopicIdType of
      ?SHORT_TOPIC_NAME ->
        ?UNSUBSCRIBE_PACKET(PacketId, TopicIdOrName);
      _ ->
        ?UNSUBSCRIBE_PACKET(TopicIdOrName, PacketId, TopicIdOrName)
    end,
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN Publish packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Qos the qos level of publish
%% @param Dup whether it is a duplicated packet
%% @param Retain whether the message is retain
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param Message message data of publish request
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_publish(config(),
                   inet:socket(),
                   qos(),
                   boolean(),
                   boolean(),
                   topic_id_type(),
                   topic_id_or_name(),
                   string(),
                   packet_id()) ->
                    ok | {error, term()}.
send_publish(Config,
             Socket,
             Qos,
             Dup,
             Retain,
             TopicIdType,
             TopicIdOrName,
             Message,
             PacketId) ->
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

%% @doc Send a MQTT-SN PubAck packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param TopicId topic id of packet
%% @param ReturnCode return code of request
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_puback(config(), inet:socket(), topic_id(), return_code(), packet_id()) ->
                   ok | {error, term()}.
send_puback(Config, Socket, TopicId, ReturnCode, PacketId) ->
  Packet = ?PUBACK_PACKET(TopicId, PacketId, ReturnCode),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN PubRel packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pubrel(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubrel(Config, Socket, PacketId) ->
  Packet = ?PUBREL_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN PubRec packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pubrec(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubrec(Config, Socket, PacketId) ->
  Packet = ?PUBREC_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN PubComp packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param PacketId the id of packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pubcomp(config(), inet:socket(), packet_id()) -> ok | {error, term()}.
send_pubcomp(Config, Socket, PacketId) ->
  Packet = ?PUBCOMP_PACKET(PacketId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN publish packet to any gateway(at Qos -1)
%%
%% @param Config the client object
%% @param Socket the socket object(not need to connect)
%% @param Host host of target gateway
%% @param Port port of target gateway
%% @param TopicIdType data type of TopicIdOrName param
%% @param TopicIdOrName topic id or name to be sent(decided by TopicIdType)
%% @param Message message data of publish request
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pub_any(config(),
                   inet:socket(),
                   host(),
                   inet:port_number(),
                   topic_id_type(),
                   topic_id_or_name(),
                   string()) ->
                    ok | {error, term()}.
send_pub_any(Config, Socket, Host, Port, TopicIdType, TopicIdOrName, Message) ->
  ?assert(TopicIdType == ?SHORT_TOPIC_NAME orelse TopicIdType == ?PRE_DEF_TOPIC_ID),
  Packet = ?PUBLISH_PACKET(TopicIdType, TopicIdOrName, Message),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send_anywhere(Socket, Bin, Host, Port).

%% @doc Send a MQTT-SN GwInfo packet to any client
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Host host of target client
%% @param Port port of target client
%% @param _Radius the radius for transmission packet(not implement)
%% @param GateWayId the id of responsed gateway
%% @param GateWayAdd the host of responsed gateway(without port)
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_gwinfo(config(),
                  inet:socket(),
                  host(),
                  inet:port_number(),
                  pos_integer(),
                  gw_id(),
                  host()) ->
                   ok | {error, term()}.
send_gwinfo(Config, Socket, Host, Port, _Radius, GateWayId, GateWayAdd) ->
  Packet = ?GWINFO_PACKET(GateWayId, GateWayAdd),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send_anywhere(Socket, Bin, Host, Port).

%% @doc Send a MQTT-SN Disconnect packet
%%
%% @param Config the client object
%% @param Socket the socket object
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_disconnect(config(), inet:socket()) -> ok | {error, term()}.
send_disconnect(Config, Socket) ->
  Packet = ?DISCONNECT_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN asleep Disconnect packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param Interval sleep interval(ms)
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_asleep(config(), inet:socket(), non_neg_integer()) -> ok | {error, term()}.
send_asleep(Config, Socket, Interval) ->
  Packet = ?DISCONNECT_PACKET(Interval),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN awake PingReq packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param ClientId unique name of client
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_awake(config(), inet:socket(), string()) -> ok | {error, term()}.
send_awake(Config, Socket, ClientId) ->
  Packet = ?PINGREQ_PACKET(ClientId),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN PingReq packet
%%
%% @param Config the client object
%% @param Socket the socket object
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pingreq(config(), inet:socket()) -> ok | {error, term()}.
send_pingreq(Config, Socket) ->
  Packet = ?PINGREQ_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Send a MQTT-SN PingResp packet
%%
%% @param Config the client object
%% @param Socket the socket object
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_pingresp(config(), inet:socket()) -> ok | {error, term()}.
send_pingresp(Config, Socket) ->
  Packet = ?PINGRESP_PACKET(),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:send(Socket, Bin).

%% @doc Boardcast a MQTT-SN SearchGw packet
%%
%% @param Config the client object
%% @param Socket the socket object
%% @param RemotePort the port to broadcast
%% @param Radius the radius for transmission packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec broadcast_searchgw(config(),
                         inet:socket(),
                         inet:port_number(),
                         non_neg_integer()) ->
                          {ok, inet:socket()} | {error, term()}.
broadcast_searchgw(Config, Socket, RemotePort, Radius) ->
  Packet = ?SEARCHGW_PACKET(Radius),
  Bin = emqttsn_frame:serialize(Packet, Config),
  emqttsn_udp:broadcast(Socket, Bin, RemotePort).
