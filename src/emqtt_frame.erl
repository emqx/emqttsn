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

-include("emqtt.hrl").

-export_type([options/0, parse_state/0, parse_result/0, serialize_fun/0]).

-type version() :: ?MQTTSN_PROTO_V1_2.
-type options() ::
    #{strict_mode => boolean(),
      clean_session => boolean(),
      keep_alive => boolean(),
      max_size => 1..?MAX_PACKET_SIZE,
      version => version()}.

-opaque parse_state() :: options() | cont_fun().
-opaque parse_result() ::
    {more, cont_fun()} | {ok, #mqtt_packet{}, binary(), parse_state()}.

-type cont_fun() :: fun((binary()) -> parse_result()).
-type serialize_fun() :: fun((emqx_types:packet()) -> iodata()).

-define(DEFAULT_OPTIONS,
        #{strict_mode => false,
          clean_session => false,
          keep_alive => false,
          max_size => ?MAX_PACKET_SIZE,
          version => ?MQTTSN_PROTO_V1_2}).
-define(Q(BYTES, ACC), {BYTES, ACC}).

%%--------------------------------------------------------------------
%% Init Parse State
%%--------------------------------------------------------------------

-spec initial_state() -> {none, options()}.
initial_state() ->
    initial_state(#{}).

-spec initial_state(options()) -> {none, options()}.
initial_state(Options) when is_map(Options) ->
    merge_opts(Options).

%% @pivate
merge_opts(Options) ->
    maps:merge(?DEFAULT_OPTIONS, Options).

%%--------------------------------------------------------------------
%% Parse MQTT-SN Frame
%%--------------------------------------------------------------------

% parser API for packet
-spec parse(binary()) -> parse_result().
parse(Bin) ->
    parse(Bin, initial_state()).

-spec parse(binary(), options()) -> parse_result().
parse(Bin, Options) ->
    parse_leading_len(Bin, Options).

% parse and verify the length of packet
-spec parse_leading_len(binary(), options()) -> parse_result().
parse_leading_len(<<16#01, Length:16/binary, Rest/binary>>,
                  Options = #{strict_mode := StrictMode}) ->
    %% Validate length if strict mode.
    StrictMode andalso byte_size(Rest) + 3 == Length,
    parse_payload_type(Rest, Options);
parse_leading_len(<<Length:8/binary, Rest/binary>>,
                  Options = #{strict_mode := StrictMode}) ->
    %% Validate length if strict mode.
    StrictMode andalso byte_size(Rest) + 1 == Length,
    parse_payload_type(Rest, Options).

% parse the message type to a header of packet
-spec parse_payload_type(binary(), options()) -> parse_result().
parse_payload_type(<<Type:8/binary, Rest/binary>>, Options) ->
    Header = #mqtt_packet_header{type = Type},
    Payload = parse_payload(Rest, Header, Options),
    #mqtt_packet{header = Header, payload = Payload}.

% dispatch to the parser of different message type
-spec parse_payload(binary(), #mqtt_packet_header{}, options()) -> parse_result().
parse_payload(<<GwId:8/binary, Duration:16/binary>>,
              #mqtt_packet_header{type = ?ADVERTISE},
              Option) ->
    #mqtt_packet_advertise{gateway_id = GwId, duration = Duration};
parse_payload(<<Radius:8/binary>>, #mqtt_packet_header{type = ?SEARCHGW}, Option) ->
    #mqtt_packet_searchgw{radius = Radius};
parse_payload(Bin, #mqtt_packet_header{type = ?GWINFO}, Option) ->
    parse_gwinfo_msg(Bin, Option);
parse_payload(<<ReturnCode:1/binary>>, #mqtt_packet_header{type = ?CONNACK}, Option) ->
    #mqtt_packet_connack{return_code = ReturnCode};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLTOPICREQ}, Option) ->
    #mqtt_packet_willtopicreq{};
parse_payload(<<>>, #mqtt_packet_header{type = ?WILLMSGREQ}, Option) ->
    #mqtt_packet_willmsgreq{};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>,
              #mqtt_packet_header{type = ?REGISTER},
              Option) ->
    #mqtt_packet_register{source = ?SERVER,
                          topic_id = TopicId,
                          packet_id = MsgId,
                          topic_name = TopicName};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?REGACK},
              Option) ->
    #mqtt_packet_regack{topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>,
              #mqtt_packet_header{type = ?PUBLISH},
              Option) ->
    #mqtt_packet_publish{flag = parse_flag(Flag),
                         topic_id = TopicId,
                         packet_id = MsgId,
                         data = Data};
parse_payload(<<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?PUBACK},
              Option) ->
    #mqtt_packet_puback{topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREC}, Option) ->
    #mqtt_packet_pubrec{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBREL}, Option) ->
    #mqtt_packet_pubrel{packet_id = MsgId};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?PUBCOMP}, Option) ->
    #mqtt_packet_pubcomp{packet_id = MsgId};
parse_payload(<<Flag:8/binary, TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>,
              #mqtt_packet_header{type = ?SUBACK},
              Option) ->
    #mqtt_packet_suback{flag = parse_flag(Flag),
                        topic_id = TopicId,
                        packet_id = MsgId,
                        return_code = ReturnCode};
parse_payload(<<MsgId:16/binary>>, #mqtt_packet_header{type = ?UNSUBACK}, Option) ->
    #mqtt_packet_unsuback{packet_id = MsgId};
parse_payload(<<ClienId/binary>>, #mqtt_packet_header{type = ?PINGREQ}, Option) ->
    #mqtt_packet_pingreq{client_id = ClienId};
parse_payload(<<>>, #mqtt_packet_header{type = ?PINGRESP}, Option) ->
    #mqtt_packet_pingresp{};
parse_payload(Bin, #mqtt_packet_header{type = ?DISCONNECT}, Option) ->
    parse_disconnect_msg(Bin, Option);
parse_payload(<<ReturnCode:2/binary>>,
              #mqtt_packet_header{type = ?WILLTOPICRESP},
              Option) ->
    #mqtt_packet_willtopicresp{return_code = ReturnCode};
parse_payload(<<ReturnCode:2/binary>>,
              #mqtt_packet_header{type = ?WILLMSGRESP},
              Option) ->
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

-spec parse_gwinfo_msg(binary(), options()) -> parse_result().
parse_gwinfo_msg(<<GWId:8/binary>>, Option) ->
    #mqtt_packet_gwinfo{source = ?SERVER, gateway_id = GWId};
parse_gwinfo_msg(<<GWId:8/binary, GwAdd/binary>>, Option) ->
    #mqtt_packet_gwinfo{source = ?CLIENT,
                        gateway_id = GWId,
                        gateway_add = GwAdd}.

-spec parse_disconnect_msg(binary(), options()) -> parse_result().
parse_disconnect_msg(<<>>, Option) ->
    #mqtt_packet_disconnect{empty_packet = true};
parse_disconnect_msg(<<Duration:16/binary>>, Option) ->
    #mqtt_packet_disconnect{empty_packet = false, duration = Duration}.

%%--------------------------------------------------------------------
%% Serialize MQTT Packet
%%--------------------------------------------------------------------

-spec serialize(#mqtt_packet{}, options()) -> iodata().
serialize(#mqtt_packet{header = Header, payload = Payload}, Option) ->
    PayloadBin = serialize_payload(Payload, Option),
    Length = iolist_size(PayloadBin),
    HeaderBin = serialize_header(Header, Length, Option),
    [HeaderBin, PayloadBin].

-spec serialize_header(#mqtt_packet_header{}, integer(), options()) -> iodata().
serialize_header(#mqtt_packet_header{type = Type}, Length, Option) when Length < 256 ->
    <<Length:8, Type:8>>;
serialize_header(#mqtt_packet_header{type = Type}, Length, Option)
    when 256 =< Length andalso Length =< ?MAX_PACKET_SIZE ->
    <<16#01:1, Length:16, Type:8>>.

-spec serialize_flag(#mqtt_packet_flag{}, options()) -> iodata().
serialize_flag(#mqtt_packet_flag{dup = Dup,
                                 qos = Qos,
                                 retain = Retain,
                                 will = Will,
                                 clean_session = CleanSession,
                                 topic_id_type = TopicIdType},
               Option) ->
    <<Dup:1, Qos:2, Retain:1, Will:1, CleanSession:1, TopicIdType:2>>.

-spec serialize_payload(packet_payload(), options()) -> iodata().
serialize_payload(#mqtt_packet_searchgw{radius = Radius}, Option) ->
    <<Radius:8>>;
serialize_payload(#mqtt_packet_gwinfo{source = Source,
                                      gateway_id = GateWayId,
                                      gateway_add = GateWayAdd},
                  Options = #{strict_mode := StrictMode}) ->
    StrictMode andalso Source == ?CLIENT,
    [<<GateWayId:8>>, GateWayAdd];
serialize_payload(#mqtt_packet_connect{flag = Flag,
                                       duration = Duration,
                                       client_id = ClientId},
                  Option) ->
    SerFlag = serialize_flag(Flag, Option),
    [SerFlag, <<16#01:1, Duration:2, ClientId>>];
serialize_payload(#mqtt_packet_willtopic{} = Bin, Option) ->
    serialize_will_topic(Bin, Option);
serialize_payload(#mqtt_packet_willmsg{will_msg = WillMsg}, Option) ->
    <<WillMsg>>;
serialize_payload(#mqtt_packet_register{source = ?SERVER,
                                        topic_id = TopicId,
                                        packet_id = MsgId,
                                        topic_name = TopicName},
                  Option) ->
    <<TopicId:16/binary, MsgId:16/binary, TopicName/binary>>;
serialize_payload(#mqtt_packet_regack{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode},
                  Option) ->
    <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_publish{flag = Flag,
                                       topic_id = TopicId,
                                       packet_id = MsgId,
                                       data = Data},
                  Option) ->
    SerFlag = serialize_flag(Flag, Option),
    <<SerFlag:8/binary, TopicId:16/binary, MsgId:16/binary, Data/binary>>;
serialize_payload(#mqtt_packet_puback{topic_id = TopicId,
                                      packet_id = MsgId,
                                      return_code = ReturnCode},
                  Option) ->
    <<TopicId:16/binary, MsgId:16/binary, ReturnCode:8/binary>>;
serialize_payload(#mqtt_packet_pubrec{packet_id = MsgId}, Option) ->
    <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubrel{packet_id = MsgId}, Option) ->
    <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_pubcomp{packet_id = MsgId}, Option) ->
    <<MsgId:16/binary>>;
serialize_payload(#mqtt_packet_subscribe{flag = Flag,
                                         packet_id = MsgId,
                                         topic_name = TopicName,
                                         topic_id = TopicId},
                  Option) ->
    SerFlag = serialize_flag(Flag, Option),
    Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
    <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_unsubscribe{flag = Flag,
                                           packet_id = MsgId,
                                           topic_name = TopicName,
                                           topic_id = TopicId},
                  Option) ->
    SerFlag = serialize_flag(Flag, Option),
    Data = serialize_topic_name_or_id(Flag, TopicName, TopicId),
    <<SerFlag:8/binary, MsgId:16/binary, Data>>;
serialize_payload(#mqtt_packet_pingreq{} = Bin, Option) ->
    serialize_pingreq(Bin, Option);
serialize_payload(#mqtt_packet_pingresp{}, Option) ->
    <<>>;
serialize_payload(#mqtt_packet_disconnect{} = Bin, Option) ->
    serialize_disconnect(Bin, Option);
serialize_payload(#mqtt_packet_willtopicupd{} = Bin, Option) ->
    serialize_willtopicupd(Bin, Option);
serialize_payload(#mqtt_packet_willmsgupd{will_msg = WillMsg}, Option) ->
    <<WillMsg>>.

% serialize willTopic packet payload
-spec serialize_will_topic(#mqtt_packet_willtopic{}, options()) -> iodata().
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = true}, Option) ->
    <<>>;
serialize_will_topic(#mqtt_packet_willtopic{empty_packet = false,
                                            flag = Flag,
                                            will_topic = WillTopic},
                     Option) ->
    SerFlag = serialize_flag(Flag, Option),
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
-spec serialize_pingreq(#mqtt_packet_pingreq{}, options()) -> iodata().
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = true}, Option) ->
    <<>>;
serialize_pingreq(#mqtt_packet_pingreq{empty_packet = false, client_id = ClienId},
                  Option) ->
    <<ClienId>>.

-spec serialize_disconnect(#mqtt_packet_disconnect{}, options()) -> iodata().
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = true}, Option) ->
    <<>>;
serialize_disconnect(#mqtt_packet_disconnect{empty_packet = false, duration = Duration},
                     Option) ->
    <<Duration:2/binary>>.

-spec serialize_willtopicupd(#mqtt_packet_willtopicupd{}, options()) -> iodata().
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true}, Option) ->
    <<>>;
serialize_willtopicupd(#mqtt_packet_willtopicupd{empty_packet = true,
                                                 flag = Flag,
                                                 will_topic = WillTopic},
                       Option) ->
    SerFlag = serialize_flag(Flag, Option),
    <<SerFlag:8/binary, WillTopic>>.
