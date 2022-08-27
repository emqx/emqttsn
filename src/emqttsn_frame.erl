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

-module(emqttsn_frame).

-include("packet.hrl").
-include("config.hrl").

-export_type([parse_fun/0, serialize_fun/0]).

-export([parse/1, serialize/2]).

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
-spec parse(binary()) -> parse_result().
parse(Bin) ->
  parse(Bin, #config{}).


parse(Bin, Config) ->
  {Length, Rest} = parse_leading_len(Bin, Config),
  #config{strict_mode = StrictMode} = Config,
  StrictMode and byte_size(Rest) == Length,
  parse_payload_from_type(Rest, Config).

-spec parse_leading_len(binary(), #config{}) -> pos_integer().
parse_leading_len(<<16#01:8/binary, Length:16/binary, Rest>>, Config) ->
  #config{max_size = MaxSize} = Config,
  if Length > MaxSize -> error(frame_too_large) end,
  {Length, Rest};
parse_leading_len(<<Length:8/binary, Rest>>, Config) ->
  #config{max_size = MaxSize} = Config,
  if Length > MaxSize -> error(frame_too_large) end,
  {Length, Rest}.

-spec parse_leading_len(binary(), fun((pos_integer())-> bitstring()), #config{}) -> pos_integer().
parse_leading_len(<<16#01:8/binary, Rest>>, Reader, Config) when Rest == <<>> ->
  Length = Reader(2),
  {Length, Rest}.

% parse the message type to a header of packet
-spec parse_payload_from_type(binary(), #config{}) -> parse_result().
parse_payload_from_type(<<Type:8/binary, Rest/binary>>, Config) ->
  Header = #mqtt_packet_header{type = Type},
  Payload = parse_payload(Rest, Header, Config),
  #mqtt_packet{header = Header, payload = Payload}.

% dispatch to the parser of different message type
-spec parse_payload(binary(), #mqtt_packet_header{}, #config{}) -> parse_result().
parse_payload(<<GwId:8/binary, Duration:16/binary>>,
              #mqtt_packet_header{type = ?ADVERTISE}, Config) ->
  #mqtt_packet_advertise{gateway_id = GwId, duration = Duration};
parse_payload(<<Radius:8/binary>>, #mqtt_packet_header{type = ?SEARCHGW}, Config) ->
  #mqtt_packet_searchgw{radius = Radius};
parse_payload(Bin, #mqtt_packet_header{type = ?GWINFO}, Config) ->
  parse_gwinfo_msg(Bin);
parse_payload(<<ReturnCode:1/binary>>, #mqtt_packet_header{type = ?CONNACK}, Config) ->
  #mqtt_packet_connack{return_code = ReturnCode};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLTOPICREQ}, Config) ->
  #mqtt_packet_willtopicreq{};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLMSGREQ}, Config) ->
  #mqtt_packet_willmsgreq{};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>,
              #mqtt_packet_header{type = ?REGISTER}, Config) ->
  #mqtt_packet_register{source = ?SERVER,
                        topic_id = TopicId,
                        packet_id = MsgId,
                        topic_name = TopicName};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?REGACK}, Config) ->
  #mqtt_packet_regack{topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>,
              #mqtt_packet_header{type = ?PUBLISH}, Config) ->
  #mqtt_packet_publish{flag = parse_flag(Flag),
                       topic_id = TopicId,
                       packet_id = MsgId,
                       data = Data};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?PUBACK}, Config) ->
  #mqtt_packet_puback{topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREC}, Config) ->
  #mqtt_packet_pubrec{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREL}, Config) ->
  #mqtt_packet_pubrel{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBCOMP}, Config) ->
  #mqtt_packet_pubcomp{packet_id = MsgId};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?SUBACK}, Config) ->
  #mqtt_packet_suback{flag = parse_flag(Flag),
                      topic_id = TopicId,
                      packet_id = MsgId,
                      return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?UNSUBACK}, Config) ->
  #mqtt_packet_unsuback{packet_id = MsgId};
parse_payload(<<ClienId/binary>>, #mqtt_packet_header{type = ?PINGREQ}, Config) ->
  #mqtt_packet_pingreq{client_id = ClienId};
parse_payload(<<>>, #mqtt_packet_header{type = ?PINGRESP}, Config) ->
  #mqtt_packet_pingresp{};
parse_payload(Bin, #mqtt_packet_header{type = ?DISCONNECT}, Config) ->
  parse_disconnect_msg(Bin);
parse_payload(<<ReturnCode:2/binary>>, #mqtt_packet_header{type = ?WILLTOPICRESP}, Config) ->
  #mqtt_packet_willtopicresp{return_code = ReturnCode};
parse_payload(<<ReturnCode:2/binary>>, #mqtt_packet_header{type = ?WILLMSGRESP}, Config) ->
  #mqtt_packet_willmsgresp{return_code = ReturnCode}.

-spec parse_flag(binary(), #config{}) -> flag().
parse_flag(<<DUP:1/binary,
             Qos:2/binary,
             Retain:1/binary,
             Will:1/binary,
             CleanSession:1/binary,
             TopicIdType:2/binary>>, Config) ->
  #mqtt_packet_flag{dup = DUP,
                    qos = Qos,
                    retain = Retain,
                    will = Will,
                    clean_session = CleanSession,
                    topic_id_type = TopicIdType}.

-spec parse_gwinfo_msg(binary(), #config{}) -> parse_result().
parse_gwinfo_msg(<<GWId:8/binary>>, Config) ->
  #mqtt_packet_gwinfo{source = ?SERVER, gateway_id = GWId};
parse_gwinfo_msg(<<GWId:8/binary, GwAdd/binary>>, Config) ->
  #mqtt_packet_gwinfo{source = ?CLIENT,
                      gateway_id = GWId,
                      gateway_add = GwAdd}.

-spec parse_disconnect_msg(binary(), #config{}) -> parse_result().
parse_disconnect_msg(<<>>, Config) ->
  #mqtt_packet_disconnect{empty_packet = true};
parse_disconnect_msg(<<Duration:16/binary>>, Config) ->
  #mqtt_packet_disconnect{empty_packet = false, duration = Duration}.

% %%--------------------------------------------------------------------
% %% Serialize MQTT Packet
% %%--------------------------------------------------------------------

-spec serialize(#mqtt_packet{}, #config{}) -> iodata().
serialize(#mqtt_packet{header = Header, payload = Payload}, Config) ->
  PayloadBin = serialize_payload(Payload, Config),
  Length = iolist_size(PayloadBin),
  HeaderBin = serialize_header(Header, Length, Config),
  [HeaderBin, PayloadBin].

-spec serialize_header(#mqtt_packet_header{}, integer(), #config{}) -> iodata().
serialize_header(#mqtt_packet_header{type = Type}, Length, Config) when Length < 256 ->
  <<Length:8, Type:8>>;
serialize_header(#mqtt_packet_header{type = Type}, Length, Config)
  when 256 =< Length andalso Length =< ?MAX_PACKET_SIZE ->
  <<16#01:1, Length:16, Type:8>>.

-spec serialize_flag(#mqtt_packet_flag{}, #config{}) -> iodata().
serialize_flag(#mqtt_packet_flag{dup = Dup,
                                 qos = Qos,
                                 retain = Retain,
                                 will = Will,
                                 clean_session = CleanSession,
                                 topic_id_type = TopicIdType}, Config) ->
  <<Dup:1, Qos:2, Retain:1, Will:1, CleanSession:1, TopicIdType:2>>.

-spec serialize_payload(packet_payload(), #config{}) -> iodata().
serialize_payload(#mqtt_packet_searchgw{radius = Radius}, Config) ->
  <<Radius:8>>;
serialize_payload(#mqtt_packet_gwinfo{source = Source,
                                      gateway_id = GateWayId,
                                      gateway_add = GateWayAdd}, Config) ->
  #config{strict_mode = StrictMode} = Config,
  StrictMode andalso Source == ?CLIENT,
  [<<GateWayId:8>>, GateWayAdd];
serialize_payload(#mqtt_packet_connect{flag = Flag,
                                       duration = Duration,
                                       client_id = ClientId}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  [SerFlag, <<16#01:1, Duration:2, ClientId>>];
serialize_payload(#mqtt_packet_willtopic{} = Bin, Config) ->
  serialize_will_topic(Bin, Config);
serialize_payload(#mqtt_packet_willmsg{will_msg = WillMsg}, Config) ->
  <<WillMsg>>;
serialize_payload(#mqtt_packet_register{source = ?SERVER,
                                        topic_id = TopicId,
                                        packet_id = MsgId,
                                        topic_name = TopicName}, Config) ->
  <<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>;
serialize_payload(#mqtt_packet_regack{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode}, Config) ->
  <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_publish{flag = Flag,
                                       topic_id = TopicId,
                                       packet_id = MsgId,
                                       data = Data}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  <<SerFlag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>;
serialize_payload(#mqtt_packet_puback{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode}, Config) ->
  <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_pubrec{packet_id = MsgId}, Config) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubrel{packet_id = MsgId}, Config) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubcomp{packet_id = MsgId}, Config) ->
  <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_subscribe{flag = Flag,
                                         packet_id = MsgId,
                                         topic_name = TopicName,
                                         topic_id = TopicId}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
  <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_unsubscribe{flag = Flag,
                                           packet_id = MsgId,
                                           topic_name = TopicName,
                                           topic_id = TopicId}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
  <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_pingreq{} = Bin, Config) ->
  serialize_pingreq(Bin);
serialize_payload(#mqtt_packet_pingresp{}, Config) ->
  <<>>;
serialize_payload(#mqtt_packet_disconnect{} = Bin, Config) ->
  serialize_disconnect(Bin, Config);
serialize_payload(#mqtt_packet_willtopicupd{} = Bin, Config) ->
  serialize_willtopicupd(Bin, Config);
serialize_payload(#mqtt_packet_willmsgupd{will_msg = WillMsg}, Config) ->
  <<WillMsg>>.

% serialize willTopic packet payload
-spec serialize_will_topic(#mqtt_packet_willtopic{}, #config{}, Config) -> iodata().
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = true}, Config) ->
  <<>>;
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = false,
                                            flag = Flag,
                                            will_topic = WillTopic}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  [SerFlag, <<WillTopic>>].

% serialize topicName or topicId by Flag argument topicIdType
-spec serialize_topic_name_or_id(#mqtt_packet_flag{}, bitstring(), topic_id(), #config{}) ->
  iodata().
serialize_topic_name_or_id(#mqtt_packet_flag{topic_id_type = [?PRE_DEF_TOPIC_ID | ?TOPIC_ID]},
                           _TopicName,
                           TopicId, Config) ->
  <<TopicId:2>>;
serialize_topic_name_or_id(Flag =
                           #mqtt_packet_flag{topic_id_type = [?SHORT_TOPIC_NAME]},
                           TopicName,
                           _TopicId, Config) ->
  <<TopicName>>.

% serialize pingReq packet payload
-spec serialize_pingreq(#mqtt_packet_pingreq{}, #config{}) -> iodata().
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = true}, Config) ->
  <<>>;
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = false, client_id = ClienId}, Config) ->
  <<ClienId>>.

-spec serialize_disconnect(#mqtt_packet_disconnect{}, #config{}) -> iodata().
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = true}, Config) ->
  <<>>;
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = false,
                                             duration = Duration}, Config) ->
  <<Duration:2/binary>>.

-spec serialize_willtopicupd(#mqtt_packet_willtopicupd{}, #config{}) -> iodata().
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true}, Config) ->
  <<>>;
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true,
                                                 flag = Flag,
                                                 will_topic = WillTopic}, Config) ->
  SerFlag = serialize_flag(Flag, Config),
  <<SerFlag:8/binary, WillTopic>>.
