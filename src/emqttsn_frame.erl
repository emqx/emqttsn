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

%% @doc MQTT-SN frame parser and serializer
%% 
%% @private
-module(emqttsn_frame).

-include_lib("stdlib/include/assert.hrl").

-include("emqttsn.hrl").

-export([parse/1, parse/2, serialize/1, serialize/2, parse_leading_len/2]).

-type parse_result() :: {ok, #mqttsn_packet{}} | {error, term()}.

-spec boolean_to_integer(boolean()) -> 0 | 1.
boolean_to_integer(Bool) ->
  case Bool of
    true ->
      1;
    false ->
      0
  end.

-spec integer_to_boolean(0 | 1) -> boolean().
integer_to_boolean(Value) ->
  case Value of
    1 ->
      true;
    0 ->
      false
  end.

%%--------------------------------------------------------------------
%% Init Config State
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Parse MQTT-SN Frame
%%--------------------------------------------------------------------

% parser API for packet
-spec parse(bitstring()) -> parse_result().
parse(Bin) ->
  parse(Bin, #config{}).

-spec parse(bitstring(), config()) -> parse_result().
parse(Bin, Config) ->
  case parse_leading_len(Bin, Config) of
    {ok, Length, LeadingLength, Rest} ->
      #config{strict_mode = StrictMode} = Config,
      StrictMode andalso ?assertEqual(byte_size(Rest) + LeadingLength, Length),
      {ok, parse_payload_from_type(Rest, Config)};
    {error, Reason} ->
      {error, Reason}
  end.

-spec parse_leading_len(bitstring(), #config{}) ->
                         {ok, pos_integer(), pos_integer(), bitstring()} | {error, term()}.
parse_leading_len(<<16#01:8/integer, Length:16/integer, Rest/binary>>, Config) ->
  SelfLength = 3,
  #config{max_size = MaxSize} = Config,
  case Length =< MaxSize of
    true ->
      {ok, Length, SelfLength, Rest};
    false ->
      {error, frame_too_large}
  end;
parse_leading_len(<<Length:8/integer, Rest/binary>>, Config) ->
  SelfLength = 1,
  #config{max_size = MaxSize} = Config,
  case Length =< MaxSize of
    true ->
      {ok, Length, SelfLength, Rest};
    false ->
      {error, frame_too_large}
  end.

% parse the message type to a header of packet
-spec parse_payload_from_type(binary(), #config{}) -> mqttsn_packet().
parse_payload_from_type(<<Type:8/integer, Rest/binary>>, Config) ->
  Header = #mqttsn_packet_header{type = Type},
  Payload = parse_payload(Rest, Header, Config),
  #mqttsn_packet{header = Header, payload = Payload}.

% dispatch to the parser of different message type
-spec parse_payload(binary(), #mqttsn_packet_header{}, #config{}) -> packet_payload().
parse_payload(<<GwId:8/integer, Duration:16/integer>>,
              #mqttsn_packet_header{type = ?ADVERTISE},
              _Config) ->
  #mqttsn_packet_advertise{gateway_id = GwId, duration = Duration};
parse_payload(<<Radius:8/integer>>, #mqttsn_packet_header{type = ?SEARCHGW}, _Config) ->
  #mqttsn_packet_searchgw{radius = Radius};
parse_payload(Bin, #mqttsn_packet_header{type = ?GWINFO}, Config) ->
  parse_gwinfo_msg(Bin, Config);
parse_payload(<<ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?CONNACK},
              _Config) ->
  #mqttsn_packet_connack{return_code = ReturnCode};
parse_payload(<<>>, #mqttsn_packet_header{type = ?WILLTOPICREQ}, _Config) ->
  #mqttsn_packet_willtopicreq{};
parse_payload(<<>>, #mqttsn_packet_header{type = ?WILLMSGREQ}, _Config) ->
  #mqttsn_packet_willmsgreq{};
parse_payload(<<TopicId:16/integer, MsgId:16/integer, TopicNameBin/binary>>,
              #mqttsn_packet_header{type = ?REGISTER},
              _Config) ->
  TopicName = binary_to_list(TopicNameBin),
  #mqttsn_packet_register{source = ?SERVER,
                          topic_id = TopicId,
                          packet_id = MsgId,
                          topic_name = TopicName};
parse_payload(<<TopicId:16/integer, MsgId:16/integer, ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?REGACK},
              _Config) ->
  #mqttsn_packet_regack{topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<SerFlag:1/binary,
                TopicIdOrNameBin:2/binary,
                MsgId:16/integer,
                MessageBin/bitstring>>,
              #mqttsn_packet_header{type = ?PUBLISH},
              Config) ->
  Message = binary_to_list(MessageBin),
  Flag = parse_flag(SerFlag, Config),
  #mqttsn_packet_flag{topic_id_type = TopicIdType} = Flag,
  case TopicIdType of
    ?SHORT_TOPIC_NAME ->
      #mqttsn_packet_publish{flag = Flag,
                             topic_id_or_name = binary_to_list(TopicIdOrNameBin),
                             packet_id = MsgId,
                             message = Message};
    _ ->
      <<TopicIdOrName:16/integer>> = TopicIdOrNameBin,
      #mqttsn_packet_publish{flag = Flag,
                             topic_id_or_name = TopicIdOrName,
                             packet_id = MsgId,
                             message = Message}
  end;
parse_payload(<<TopicId:16/integer, MsgId:16/integer, ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?PUBACK},
              _Config) ->
  #mqttsn_packet_puback{topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<MsgId:16/integer>>, #mqttsn_packet_header{type = ?PUBREC}, _Config) ->
  #mqttsn_packet_pubrec{packet_id = MsgId};
parse_payload(<<MsgId:16/integer>>, #mqttsn_packet_header{type = ?PUBREL}, _Config) ->
  #mqttsn_packet_pubrel{packet_id = MsgId};
parse_payload(<<MsgId:16/integer>>, #mqttsn_packet_header{type = ?PUBCOMP}, _Config) ->
  #mqttsn_packet_pubcomp{packet_id = MsgId};
parse_payload(<<Flag:1/binary,
                TopicId:16/integer,
                MsgId:16/integer,
                ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?SUBACK},
              Config) ->
  #mqttsn_packet_suback{flag = parse_flag(Flag, Config),
                        topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<MsgId:16/integer>>, #mqttsn_packet_header{type = ?UNSUBACK}, _Config) ->
  #mqttsn_packet_unsuback{packet_id = MsgId};
parse_payload(<<ClienIdBin/binary>>, #mqttsn_packet_header{type = ?PINGREQ}, _Config) ->
  ClienId = binary_to_list(ClienIdBin),
  #mqttsn_packet_pingreq{empty_packet = false, client_id = ClienId};
parse_payload(<<>>, #mqttsn_packet_header{type = ?PINGRESP}, _Config) ->
  #mqttsn_packet_pingresp{};
parse_payload(Bin, #mqttsn_packet_header{type = ?DISCONNECT}, Config) ->
  parse_disconnect_msg(Bin, Config);
parse_payload(<<ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?WILLTOPICRESP},
              _Config) ->
  #mqttsn_packet_willtopicresp{return_code = ReturnCode};
parse_payload(<<ReturnCode:8/integer>>,
              #mqttsn_packet_header{type = ?WILLMSGRESP},
              _Config) ->
  #mqttsn_packet_willmsgresp{return_code = ReturnCode}.

-spec parse_flag(binary(), #config{}) -> flag().
parse_flag(<<DUP:1/integer,
             Qos:2/integer,
             Retain:1/integer,
             Will:1/integer,
             CleanSession:1/integer,
             TopicIdType:2/integer>>,
           _Config) ->
  #mqttsn_packet_flag{dup = integer_to_boolean(DUP),
                      qos = Qos,
                      retain = integer_to_boolean(Retain),
                      will = integer_to_boolean(Will),
                      clean_session = integer_to_boolean(CleanSession),
                      topic_id_type = TopicIdType}.

-spec parse_gwinfo_msg(binary(), #config{}) -> packet_payload().
parse_gwinfo_msg(<<GWId:8/integer>>, _Config) ->
  #mqttsn_packet_gwinfo{source = ?SERVER, gateway_id = GWId};
parse_gwinfo_msg(<<GWId:8/integer,
                   Adr1:8/integer,
                   Adr2:8/integer,
                   Adr3:8/integer,
                   Adr4:8/integer>>,
                 _Config) ->
  #mqttsn_packet_gwinfo{source = ?CLIENT,
                        gateway_id = GWId,
                        gateway_add = {Adr1, Adr2, Adr3, Adr4}}.

-spec parse_disconnect_msg(binary(), #config{}) -> packet_payload().
parse_disconnect_msg(<<>>, _Config) ->
  #mqttsn_packet_disconnect{empty_packet = true};
parse_disconnect_msg(<<Duration:16/integer>>, _Config) ->
  #mqttsn_packet_disconnect{empty_packet = false, duration = Duration}.

%%--------------------------------------------------------------------
%% Serialize MQTT Packet
%%--------------------------------------------------------------------

-spec serialize(#mqttsn_packet{}) -> bitstring().
serialize(Packet) ->
  serialize(Packet, #config{}).

-spec serialize(#mqttsn_packet{}, #config{}) -> bitstring().
serialize(#mqttsn_packet{header = Header, payload = Payload}, Config) ->
  PayloadBin = serialize_payload(Payload, Config),
  Length = iolist_size(PayloadBin),
  WholeLength =
    case Length of
      L when L =< 256 ->
        Length + 2;
      L when 256 < L andalso L < ?MAX_PACKET_SIZE ->
        Length + 4
    end,
  HeaderBin = serialize_header(Header, WholeLength, Config),

  <<HeaderBin/binary, PayloadBin/binary>>.

-spec serialize_header(#mqttsn_packet_header{}, non_neg_integer(), #config{}) -> binary().
serialize_header(#mqttsn_packet_header{type = Type}, Length, _Config) when Length < 256 ->
  <<Length:8/integer, Type:8/integer>>;
serialize_header(#mqttsn_packet_header{type = Type}, Length, _Config)
  when 256 =< Length andalso Length =< ?MAX_PACKET_SIZE ->
  <<1:8/integer, Length:16/integer, Type:8/integer>>.

-spec serialize_flag(#mqttsn_packet_flag{}, #config{}) -> bin_1_byte().
serialize_flag(#mqttsn_packet_flag{dup = Dup,
                                   qos = Qos,
                                   retain = Retain,
                                   will = Will,
                                   clean_session = CleanSession,
                                   topic_id_type = TopicIdType},
               _Config) ->
  DupValue = boolean_to_integer(Dup),
  RetainValue = boolean_to_integer(Retain),
  WillValue = boolean_to_integer(Will),
  CleanSessionValue = boolean_to_integer(CleanSession),
  <<DupValue:1/integer,
    Qos:2/integer,
    RetainValue:1/integer,
    WillValue:1/integer,
    CleanSessionValue:1/integer,
    TopicIdType:2/integer>>.

-spec serialize_payload(packet_payload(), #config{}) -> iodata().
serialize_payload(#mqttsn_packet_advertise{gateway_id = GwId, duration = Duration},
                  _Config) ->
  <<GwId:8/integer, Duration:16/integer>>;
serialize_payload(#mqttsn_packet_searchgw{radius = Radius}, _Config) ->
  <<Radius:8>>;
serialize_payload(#mqttsn_packet_gwinfo{source = ?CLIENT,
                                        gateway_id = GWId,
                                        gateway_add = GateWayAdd},
                  _Config) ->
  {Adr1, Adr2, Adr3, Adr4} = GateWayAdd,
  <<GWId:8/integer, Adr1:8/integer, Adr2:8/integer, Adr3:8/integer, Adr4:8/integer>>;
serialize_payload(#mqttsn_packet_gwinfo{source = ?SERVER, gateway_id = GWId}, _Config) ->
  <<GWId:8/integer>>;
serialize_payload(#mqttsn_packet_connect{flag = Flag,
                                         duration = Duration,
                                         client_id = ClientId},
                  Config) ->
  SerFlag = serialize_flag(Flag, Config),
  ClientIdBin = list_to_binary(ClientId),
  <<SerFlag/bitstring, 1:8/integer, Duration:16/integer, ClientIdBin/binary>>;
serialize_payload(#mqttsn_packet_connack{return_code = ReturnCode}, _Config) ->
  <<ReturnCode:8/integer>>;
serialize_payload(#mqttsn_packet_willtopicreq{}, _Config) ->
  <<>>;
serialize_payload(#mqttsn_packet_willtopic{} = Bin, Config) ->
  serialize_will_topic(Bin, Config);
serialize_payload(#mqttsn_packet_willmsgreq{}, _Config) ->
  <<>>;
serialize_payload(#mqttsn_packet_willmsg{will_msg = WillMsg}, _Config) ->
  WillMsgBin = list_to_binary(WillMsg),
  WillMsgBin;
serialize_payload(#mqttsn_packet_register{source = ?SERVER,
                                          topic_id = TopicId,
                                          packet_id = MsgId,
                                          topic_name = TopicName},
                  _Config) ->
  TopicNameBin = list_to_binary(TopicName),
  <<TopicId:16/integer, MsgId:16/integer, TopicNameBin/binary>>;
serialize_payload(#mqttsn_packet_register{source = ?CLIENT,
                                          topic_id = _TopicId,
                                          packet_id = MsgId,
                                          topic_name = TopicName},
                  _Config) ->
  TopicNameBin = list_to_binary(TopicName),
  <<0:16/integer, MsgId:16/integer, TopicNameBin/binary>>;
serialize_payload(#mqttsn_packet_regack{topic_id = TopicId,
                                        packet_id = MsgId,
                                        return_code = _ReturnCode},
                  _Config) ->
  <<TopicId:16/integer, MsgId:16/integer, 8/integer>>;
serialize_payload(#mqttsn_packet_publish{flag = Flag,
                                         topic_id_or_name = TopicIdOrName,
                                         packet_id = MsgId,
                                         message = Message},
                  Config) ->
  MessageBin = list_to_binary(Message),
  SerFlag = serialize_flag(Flag, Config),
  #mqttsn_packet_flag{topic_id_type = TopicIdType} = Flag,
  case TopicIdType of
    ?SHORT_TOPIC_NAME ->
      TopicNameBin = list_to_binary(TopicIdOrName),
      <<SerFlag:1/binary, TopicNameBin:2/binary, MsgId:16/integer, MessageBin/binary>>;
    _ ->
      TopicId = TopicIdOrName,
      <<SerFlag:1/binary, TopicId:16/integer, MsgId:16/integer, MessageBin/binary>>
  end;
serialize_payload(#mqttsn_packet_puback{topic_id = TopicId,
                                        packet_id = MsgId,
                                        return_code = ReturnCode},
                  _Config) ->
  <<TopicId:16/integer, MsgId:16/integer, ReturnCode:8/integer>>;
serialize_payload(#mqttsn_packet_pubrec{packet_id = MsgId}, _Config) ->
  <<MsgId:16/integer>>;
serialize_payload(#mqttsn_packet_pubrel{packet_id = MsgId}, _Config) ->
  <<MsgId:16/integer>>;
serialize_payload(#mqttsn_packet_pubcomp{packet_id = MsgId}, _Config) ->
  <<MsgId:16/integer>>;
serialize_payload(#mqttsn_packet_suback{flag = Flag,
                                        topic_id = TopicId,
                                        packet_id = MsgId,
                                        return_code = ReturnCode},
                  Config) ->
  SerFlag = serialize_flag(Flag, Config),
  <<SerFlag:1/binary, TopicId:16/integer, MsgId:16/integer, ReturnCode:8/integer>>;
serialize_payload(#mqttsn_packet_subscribe{flag = Flag,
                                           packet_id = MsgId,
                                           topic_name = TopicName,
                                           topic_id = TopicId},
                  Config) ->
  SerFlag = serialize_flag(Flag, Config),
  Bin = serialize_topic_name_or_id(Flag, TopicName, TopicId, Config),
  <<SerFlag:1/binary, MsgId:16/integer, Bin/binary>>;
serialize_payload(#mqttsn_packet_unsubscribe{flag = Flag,
                                             packet_id = MsgId,
                                             topic_name = TopicName,
                                             topic_id = TopicId},
                  Config) ->
  SerFlag = serialize_flag(Flag, Config),
  Bin = serialize_topic_name_or_id(Flag, TopicName, TopicId, Config),
  <<SerFlag:1/binary, MsgId:16/integer, Bin/binary>>;
serialize_payload(#mqttsn_packet_unsuback{packet_id = MsgId}, _Config) ->
  <<MsgId:16/integer>>;
serialize_payload(#mqttsn_packet_pingreq{} = Bin, Config) ->
  serialize_pingreq(Bin, Config);
serialize_payload(#mqttsn_packet_pingresp{}, _Config) ->
  <<>>;
serialize_payload(#mqttsn_packet_disconnect{} = Bin, Config) ->
  serialize_disconnect(Bin, Config);
serialize_payload(#mqttsn_packet_willtopicupd{} = Bin, Config) ->
  serialize_willtopicupd(Bin, Config);
serialize_payload(#mqttsn_packet_willtopicresp{return_code = ReturnCode}, _Config) ->
  <<ReturnCode:8/integer>>;
serialize_payload(#mqttsn_packet_willmsgupd{will_msg = WillMsg}, _Config) ->
  list_to_binary(WillMsg);
serialize_payload(#mqttsn_packet_willmsgresp{return_code = ReturnCode}, _Config) ->
  <<ReturnCode:8/integer>>.

% serialize willTopic packet payload
-spec serialize_will_topic(#mqttsn_packet_willtopic{}, #config{}) -> iodata().
serialize_will_topic(#mqttsn_packet_willtopic{empty_packet = true}, _Config) ->
  <<>>;
serialize_will_topic(#mqttsn_packet_willtopic{empty_packet = false,
                                              flag = Flag,
                                              will_topic = WillTopic},
                     Config) ->
  WillTopicBin = list_to_binary(WillTopic),
  SerFlag = serialize_flag(Flag, Config),
  <<SerFlag/binary, WillTopicBin/binary>>.

% serialize topicName or topicId by Flag argument topicIdType
-spec serialize_topic_name_or_id(#mqttsn_packet_flag{},
                                 string(),
                                 topic_id(),
                                 #config{}) ->
                                  bitstring().
serialize_topic_name_or_id(#mqttsn_packet_flag{topic_id_type = TopicIdType},
                           _TopicName,
                           TopicId,
                           _Config)
  when TopicIdType == ?PRE_DEF_TOPIC_ID orelse TopicIdType == ?TOPIC_ID ->
  <<TopicId:16/integer>>;
serialize_topic_name_or_id(#mqttsn_packet_flag{topic_id_type = TopicIdType},
                           TopicName,
                           _TopicId,
                           _Config)
  when TopicIdType == ?SHORT_TOPIC_NAME ->
  list_to_binary(TopicName).

% serialize pingReq packet payload
-spec serialize_pingreq(#mqttsn_packet_pingreq{}, #config{}) -> iodata().
serialize_pingreq(#mqttsn_packet_pingreq{empty_packet = true}, _Config) ->
  <<>>;
serialize_pingreq(#mqttsn_packet_pingreq{empty_packet = false, client_id = ClienId},
                  _Config) ->
  list_to_binary(ClienId).

-spec serialize_disconnect(#mqttsn_packet_disconnect{}, #config{}) -> iodata().
serialize_disconnect(#mqttsn_packet_disconnect{empty_packet = true}, _Config) ->
  <<>>;
serialize_disconnect(#mqttsn_packet_disconnect{empty_packet = false, duration = Duration},
                     _Config) ->
  <<Duration:16/integer>>.

-spec serialize_willtopicupd(#mqttsn_packet_willtopicupd{}, #config{}) -> iodata().
serialize_willtopicupd(#mqttsn_packet_willtopicupd{empty_packet = true}, _Config) ->
  <<>>;
serialize_willtopicupd(#mqttsn_packet_willtopicupd{empty_packet = false,
                                                   flag = Flag,
                                                   will_topic = WillTopic},
                       Config) ->
  SerFlag = serialize_flag(Flag, Config),
  WillTopicBin = list_to_binary(WillTopic),
  <<SerFlag/binary, WillTopicBin/binary>>.
