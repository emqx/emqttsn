-module(emqttsn_state).
-behavior(gen_statem).

-include("packet.hrl").
-include("config.hrl").
-include("logger.hrl").

-import(emqttsn_utils, [next_packet_id/1, prev_packet_id/1]).

-export([init/1, callback_mode/0]).

-define(LOG_STATE(Level, Data, Meta, State),
  ?LOG(Level, Data, Meta#{state => State})).

callback_mode() ->
  [handle_event_function, state_enter].

start_link(Name, {Socket, Config}) ->
  gen_statem:start_link({global, Name}, ?MODULE, {Name, Socket, Config}).

init({Name, Socket, Config}) ->
  {ok, initialized, #state{name = Name, socket = Socket, config = Config}}.

%-------------------------------------------------------------------------------
% Client is disconnected or before connect
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Find the Host of service gateway
%%
%% state  : [initialized] -> [found]
%% trigger: enter state

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(enter, _OldState, initialized,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Find the Host of service gateway", {}, State),
  #config{search_gw_interval = Interval} = Config,
  emqttsn_send:broadcast_searchgw(Socket, ?DEFAULT_PORT, ?DEFAULT_RADIUS),
  {keep_state, State, {timeout, Interval, {}}};

%%------------------------------------------------------------------------------
%% @doc Resend searchgw when reach time interval T_SEARCHGW
%%
%% state  : repeat [initialized]
%% trigger: state timeout

%% @see gen_statem for state machine
%% @see T_SEARCHGW
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {}, initialized, State) ->
  ?LOG_STATE(debug, "Resend searchgw when reach time interval T_SEARCHGW",
             {}, State),
  {repeat_state, State};

%%------------------------------------------------------------------------------
%% @doc Fetch gateway from received broadcast ADVERTISE packet
%%
%% state  : keep [initialized]
%% trigger: receive advertise packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {?ADVERTISE_PACKET(GateWayId, _Duration), Host, Port},
             initialized, State = #state{name = Name}) ->
  ?LOG_STATE(debug, "Fetch gateway from received broadcast ADVERTISE packet",
             {gateway_id = GateWayId, host = Host, port = Port}, State),
  emqttsn_utils:store_gw(Name, #gw_info{id = GateWayId, host = Host,
                                        port = Port, from = ?BROADCAST}),
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Fetch gateway from received broadcast GWINFO packet by gateway
%%
%% state  : keep [initialized]
%% trigger: receive gwinfo packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {?GWINFO_PACKET(GateWayId), Host, Port}, initialized,
             State = #state{name = Name}) ->
  ?LOG_STATE(debug,
             "Fetch gateway from received broadcast GWINFO packet by gateway",
             {gateway_id = GateWayId, host = Host, port = Port}, State),
  emqttsn_utils:store_gw(Name, #gw_info{id = GateWayId, host = Host,
                                        port = Port, from = ?BROADCAST}),
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Fetch gateway from received broadcast GWINFO packet by other client
%%
%% state  : keep [initialized]
%% trigger: receive gwinfo packet
%%
%% @see gen_statem for state machine
%% @see use DEFAULT_PORT = 1884, maybe have mistake
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {?GWINFO_PACKET(GateWayId, GateWayAdd), _Host, _Port},
             initialized, State = #state{name = Name}) ->
  ?LOG_STATE(debug,
    "Fetch gateway from received broadcast GWINFO packet by gateway",
    {gateway_id = GateWayId, host = GateWayAdd,
     port = ?DEFAULT_PORT}, State),
  emqttsn_utils:store_gw(Name, #gw_info{id = GateWayId, host = GateWayAdd,
                                        port = ?DEFAULT_PORT,
                                        from = ?PARAPHRASE}),
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Request to add a new gateway
%%
%% state  : keep [initialized]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {add_gw, Host, Port, GateWayId}, initialized,
             State = #state{name = Name}) ->
  ?LOG_STATE(debug, "Fetch gateway from manual add",
             {gateway_id = GateWayId, host = Host, port = Port}, State),
  emqttsn_utils:store_gw(Name, #gw_info{id = GateWayId, host = Host,
                                        port = Port, from = ?MANUAL}),
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Request to connect a exist gateway
%%
%% state  : [initialized] -> [found]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {connect, GateWayId}, initialized,
             State = #state{name = Name}) ->
  ?LOG_STATE(debug, "Request to connect a exist gateway",
             {gateway_id = GateWayId}, State),
  #gw_info{host = Host, port = Port} = emqttsn_utils:get_gw(Name, GateWayId),
  SocketRet = emqttsn_udp:init_port(?DEFAULT_PORT),
  Socket = case SocketRet of
             {ok, Socket} ->
               Socket;
             {error, _Reason} ->
               ?LOG_STATE(warn, "Open 1884 failed, turn to random port",
                          {}, State),
               emqttsn_udp:init_port()
           end,
  emqttsn_udp:connect(Socket, Host, Port),
  {next_state, found,
   State#state{socket = Socket, active_gw =
   #gw_collect{id = GateWayId, host = Host, port = Port}}};

%-------------------------------------------------------------------------------
% Client connecting process
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Connect to service gateway
%%
%% state  : keep [found]
%% trigger: enter state

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(enter, _OldState, found,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Connect to service gateway", {}, State),
  #config{will = Will, clean_session = CleanSession,
          duration = Duration, client_id = ClientId,
          ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_connect(Socket, Will, CleanSession, Duration, ClientId),
  {keep_state, State, {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Found timeout to receive gateway response
%%
%% state  : repeat [found]
%% trigger: state timeout + can resend
%%
%% state  : [found] -> [connect_other]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {ResendTimes}, found,
             State = #state{config = Config}) ->
  ?LOG_STATE(debug, "Found timeout to receive gateway response",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend} = Config,
  if
    ResendTimes < MaxResend ->
      {repeat_state, State};
    ResendTimes >= MaxResend ->
      {next_state, connect_other, State}
  end;

%%------------------------------------------------------------------------------
%% @doc Automatically answer for will_topic request
%%
%% state  : keep [found]
%% trigger: receive will_topic_req packet

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?WILLTOPICREQ_PACKET(), found,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Automatically answer for will_topic request",
             {}, State),
  #config{qos = Qos, will_topic = WillTopic} = Config,
  Retain = false,
  emqttsn_send:send_willtopic(Socket, Qos, Retain, WillTopic),
  {keep_state, State, {state_timeout, update, connect_ack}};

%%------------------------------------------------------------------------------
%% @doc Automatically answer for will_msg request
%%
%% state  : keep [found]
%% trigger: receive will_msg_req packet

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?WILLMSGREQ_PACKET(), found,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Automatically answer for will_msg request",
             {}, State),
  #config{will_msg = WillMsg} = Config,
  emqttsn_send:send_willmsg(Socket, WillMsg),
  {keep_state, State, {state_timeout, update, connect_ack}};

%%------------------------------------------------------------------------------
%% @doc Gateway ensure connection is established
%%
%% state  : [found] -> [connected]
%% trigger: receive connack packet and return code success

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?CONNACK_PACKET(ReturnCode), found,
             State = #state{config = Config})
  when ReturnCode == ?RC_ACCEPTED ->
  ?LOG_STATE(debug, "Gateway ensure connection is established", {}, State),
  #config{keep_alive_interval = PingInterval} = Config,
  {next_state, connected, State#state{gw_failed_cycle = 0},
   {timeout, PingInterval, ping}};

%%------------------------------------------------------------------------------
%% @doc Connection is failed to establish
%%
%% state  : keep [found]
%% trigger: receive connack packet and return code failed

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?CONNACK_PACKET(ReturnCode), found,
             State = #state{socket = Socket}) ->
  ?LOG_STATE(error, "failed for connect response",
             {return_code = ReturnCode}, State),
  {next_state, initialized, #state{socket = Socket}};

%-------------------------------------------------------------------------------
% Client is waiting for response with qos resend
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Finish register request and back to connected
%%
%% state  : [wait_reg] -> [connected]
%% trigger: receive regack packet

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?REGACK_PACKET(TopicId, RemotePacketId, ReturnCode), wait_reg,
             State = #state{next_packet_id = LocalPacketId,
                            waiting_data = {reg, TopicName},
                            topic_id_name = IdMap, topic_name_id = NameMap})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish register request and back to connected",
    {topic_id = TopicId, packet_id = RemotePacketId,
     return_code = ReturnCode}, State),
  case ReturnCode of
    ?RC_ACCEPTED ->
      IdMap = IdMap#{TopicId => TopicName},
      NameMap = NameMap#{TopicName => TopicId};
    _ -> ?LOG_STATE(error, "failed for register response",
                    {return_code = ReturnCode}, State)
  end,
  {next_state, connected,
   State#state{next_packet_id = next_packet_id(RemotePacketId),
               waiting_data = {}, topic_id_name = IdMap,
               topic_name_id = NameMap}};

%%------------------------------------------------------------------------------
%% @doc Answer for register request is timeout and retry register
%%
%% state  : keep [wait_reg]
%% trigger: state timeout + can resend
%%
%% state  : [wait_reg] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {PacketId, TopicName, ResendTimes}, wait_reg,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Answer for register request is timeout and retry register",
    {packet_id = PacketId, topic_name = TopicName,
     resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, resend_no_qos = WhetherResend,
          ack_timeout = AckTimeout} = Config,
  if
    WhetherResend andalso ResendTimes < MaxResend ->
      emqttsn_send:send_register(Socket, prev_packet_id(PacketId), TopicName),
      {keep_state, State#state{next_packet_id = PacketId,
                               waiting_data = {reg, TopicName}},
       {timeout, AckTimeout, {PacketId, TopicName, ResendTimes + 1}}};
    not WhetherResend orelse ResendTimes >= MaxResend ->
      {next_state, connected, State}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish subscribe request and back to connected
%%
%% state  : [wait_sub] -> [connected]
%% trigger: receive suback packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast,
             ?SUBACK_PACKET(GrantQos, RemoteTopicId, RemotePacketId, ReturnCode),
             wait_sub,
             State = #state{next_packet_id = LocalPacketId, topic_id_name = IdMap,
                            topic_name_id = NameMap, topic_id_use_qos = QosMap,
                            config = Config,
                            waiting_data = {sub, TopicIdType, TopicIdOrName}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish subscribe request and back to connected",
    {packet_id = RemotePacketId, topic_id_or_name = TopicIdOrName,
     return_code = ReturnCode, grant_qos = GrantQos}, State),
  #config{qos = LocalQos} = Config,
  if not ReturnCode == ?RC_ACCEPTED
    -> ?LOG_STATE(error, "failed for subscribe response",
                  {return_code = ReturnCode}, State)
  end,
  Qos = min(GrantQos, LocalQos),
  QosMap = QosMap#{RemoteTopicId => Qos},
  case TopicIdType of
    ?PRE_DEF_TOPIC_ID -> RemoteTopicId == TopicIdOrName;
    _ ->
      IdMap = IdMap#{RemoteTopicId => TopicIdOrName},
      NameMap = NameMap#{TopicIdOrName => RemoteTopicId}
  end,
  {next_state, connected,
   State#state{next_packet_id = next_packet_id(LocalPacketId),
               waiting_data = {}, topic_id_name = IdMap,
               topic_name_id = NameMap, topic_id_use_qos = QosMap}};

%%------------------------------------------------------------------------------
%% @doc Answer for subscribe request is timeout and retry subscribe
%%
%% state  : keep [wait_sub]
%% trigger: state timeout + can resend
%%
%% state  : [wait_sub] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {ResendTimes}, wait_sub,
             State =
             #state{next_packet_id = PacketId, config = Config, socket = Socket,
                    waiting_data = {sub, TopicIdType, TopicIdOrName}}) ->
  ?LOG_STATE(debug, "Answer for subscribe request is timeout and retry subscribe",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, resend_no_qos = WhetherResend,
          ack_timeout = AckTimeout} = Config,
  if
    WhetherResend andalso ResendTimes < MaxResend ->
      emqttsn_send:send_subscribe(Socket, TopicIdType,
                                  prev_packet_id(PacketId), TopicIdOrName),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {sub, TopicIdType, TopicIdOrName}},
       {timeout, AckTimeout, {ResendTimes + 1}}};
    not WhetherResend orelse ResendTimes >= MaxResend ->
      {next_state, connected, State}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish publish request and back to connected when at QoS 1
%%
%% state  : [wait_pub_qos1] -> [connected]
%% trigger: receive puback packet
%%
%% @see gen_statem for state machine
%% @see QoS 1
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PUBACK_PACKET(RemoteTopicId, RemotePacketId, ReturnCode),
             wait_pub_qos1,
             State = #state{next_packet_id = LocalPacketId,
                            config = Config, topic_id_name = Map,
                            waiting_data = {pub, ?QOS_1, TopicIdType,
                                            LocalTopicIdOrName, Data}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish publish request and back to connected when at QoS 1",
             {packet_id = RemotePacketId, return_code = ReturnCode}, State),
  #config{max_message_each_topic = TopicMaxMsg} = Config,
  case TopicIdType of
    ?PRE_DEF_TOPIC_ID orelse ?TOPIC_ID -> RemoteTopicId == LocalTopicIdOrName;
    ?SHORT_TOPIC_NAME -> Map = Map#{RemoteTopicId => LocalTopicIdOrName}
  end,
  if not ReturnCode == ?RC_ACCEPTED
    -> ?LOG_STATE(error, "failed for publish response",
                  {return_code = ReturnCode}, State)
  end,
  State = emqttsn_utils:store_msg(State, RemoteTopicId, TopicMaxMsg, Data),
  {next_state, connected,
   State#state{next_packet_id = next_packet_id(LocalPacketId),
               topic_id_name = Map}};

%%------------------------------------------------------------------------------
%% @doc Answer for publish request is timeout and retry publish at QoS 1
%%
%% state  : keep [wait_pub_qos1]
%% trigger: state timeout + can resend
%%
%% state  : [wait_pub_qos1] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @see QoS 1
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {Retain, ResendTimes}, wait_pub_qos1,
             State = #state{next_packet_id = PacketId, config = Config,
                            socket = Socket,
                            waiting_data = {pub, ?QOS_1, TopicIdType,
                                            TopicIdOrName, Data}}) ->
  ?LOG_STATE(debug, "Answer for publish request is timeout and retry publish at QoS 1",
             {retain = Retain, resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_publish(Socket, ?QOS_1, ?DUP_TRUE, Retain, TopicIdType,
                                TopicIdOrName, prev_packet_id(PacketId), Data),
      {keep_state, State#state{next_packet_id = PacketId,
                               waiting_data = {pub, ?QOS_1, TopicIdType,
                                               TopicIdOrName, Data}},
       {timeout, AckTimeout, {Retain, ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, connected, State#state{waiting_data = {}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Continue publish request part 2 - receive pubrec and send pubrel
%% and then transfer to wait pubrel packet when at QoS 2
%%
%% state  : [wait_pub_qos1] -> [wait_pubrel_qos2]
%% trigger: receive puback packet
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PUBREC_PACKET(RemotePacketId), wait_pub_qos2,
             State = #state{next_packet_id = LocalPacketId, config = Config,
                            topic_name_id = NameMap, socket = Socket,
                            name = Name,
                            waiting_data = {pub, ?QOS_2, TopicIdType,
                                            TopicIdOrName, Data}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Continue publish request part 2",
             {packet_id = RemotePacketId}, State),
  TopicId = case TopicIdType of
              ?PRE_DEF_TOPIC_ID orelse ?TOPIC_ID -> TopicIdOrName;
              ?SHORT_TOPIC_NAME -> dict:fetch(TopicIdOrName, NameMap)
            end,
  #config{ack_timeout = AckTimeout,
          max_message_each_topic = TopicMaxMsg} = Config,
  State = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Data),
  emqttsn_send:send_pubrel(Socket, RemotePacketId),
  {next_state, wait_pubrel_qos2,
   State#state{next_packet_id = next_packet_id(RemotePacketId),
               waiting_data = {pubrel, ?QOS_2}},
   {timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Answer for publish request is timeout at part 2 - receive pubrec
%% and then retry publish at QoS 2
%%
%% state  : keep [wait_pub_qos2]
%% trigger: state timeout + can resend
%%
%% state  : [wait_pub_qos1] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {Retain, ResendTimes}, wait_pub_qos2,
             State = #state{next_packet_id = PacketId,
                            config = Config, socket = Socket,
                            waiting_data = {pub, ?QOS_2, TopicIdType,
                                            TopicIdOrName, Data}}) ->
  ?LOG_STATE(debug, "Answer for publish request is timeout at part 2",
             {retain = Retain, resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_publish(Socket, ?QOS_2, ?DUP_TRUE, Retain, TopicIdType,
                                TopicIdOrName, PacketId, Data),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {pub, ?QOS_2, TopicIdType,
                                   TopicIdOrName, Data}},
       {timeout, AckTimeout, {Retain, ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, connected, State#state{waiting_data = {}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish publish request part 3 - receive pubcomp
%% and then back to connected when at QoS 2
%%
%% state  : [wait_pub_qos1] -> [wait_pubrel_qos2]
%% trigger: receive puback packet
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PUBCOMP_PACKET(RemotePacketId), wait_pubrel_qos2,
             State = #state{waiting_data = {pubrel, ?QOS_2}}) ->
  ?LOG_STATE(debug, "Finish publish request part 3",
             {packet_id = RemotePacketId}, State),
  {next_state, connected,
   State#state{next_packet_id = next_packet_id(RemotePacketId),
               waiting_data = {}}};

%%------------------------------------------------------------------------------
%% @doc Answer for publish request is timeout at part 3 - receive pubcomp
%% and then retry pubrel at QoS 2
%%
%% state  : keep [wait_pubrel_qos2]
%% trigger: state timeout + can resend
%%
%% state  : [wait_pubrel_qos2] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {ResendTimes}, wait_pubrel_qos2,
             State = #state{next_packet_id = PacketId,
                            config = Config, socket = Socket,
                            waiting_data = {pubrel, ?QOS_2}}) ->
  ?LOG_STATE(debug, "Answer for publish request is timeout at part 3",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pubrec(Socket, prev_packet_id(PacketId)),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {pubrel, ?QOS_2}},
       {timeout, AckTimeout, {ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, connected, State#state{waiting_data = {}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish receive publish part 2 - receive pubrel and send pubcomp
%% and then back to connected when at QoS 2
%%
%% state  : [wait_pubrec_qos2] -> [connected]
%% trigger: receive pubrel packet
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PUBREL_PACKET(RemotePacketId), wait_pubrec_qos2,
             State = #state{socket = Socket, next_packet_id = LocalPacketId})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish receive publish part 2",
             {packet_id = RemotePacketId}, State),
  emqttsn_send:send_pubcomp(Socket, RemotePacketId),
  {next_state, connected,
   State#state{next_packet_id = next_packet_id(RemotePacketId)}};

%%------------------------------------------------------------------------------
%% @doc Answer for receive publish is timeout at part 2 - receive pubrel
%% and then retry pubrec at QoS 2
%%
%% state  : keep [wait_pubrec_qos2]
%% trigger: state timeout + can resend
%%
%% state  : [wait_pubrec_qos2] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @see QoS 2
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {ResendTimes}, wait_pubrec_qos2,
             State = #state{next_packet_id = PacketId,
                            config = Config, socket = Socket,
                            waiting_data = {FromStateName}}) ->
  ?LOG_STATE(debug, "Answer for receive publish is timeout at part 2",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pubrec(Socket, prev_packet_id(PacketId)),
      {keep_state, State#state{next_packet_id = PacketId},
       {timeout, AckTimeout, {ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, FromStateName, State#state{waiting_data = {}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish ping request and back to connected
%%
%% state  : [wait_pingreq] -> [connected]
%% trigger: receive pingresp packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PINGRESP_PACKET(), wait_pingreq, State) ->
  ?LOG_STATE(debug, "Finish ping request and back to connected", {}, State),
  {next_state, connected, State};

%%------------------------------------------------------------------------------
%% @doc Answer for ping request is timeout and retry pingreq
%%
%% state  : keep [wait_pingreq]
%% trigger: state timeout + can resend
%%
%% state  : [wait_pingreq] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {ResendTimes}, wait_pingreq,
             State = {config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Answer for ping request is timeout and retry pingreq",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, ack_timeout = AckTimeout, client_id = ClientId} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pingreq(Socket),
      {keep_state, State, {timeout, AckTimeout, {ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, connect_other, State#state{waiting_data = {}}}
  end;

%-------------------------------------------------------------------------------
% Client is connected and ready for subscribe/publish
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Request Gateway to register and then wait for regack
%%
%% state  : [connected] -> [wait_reg]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {reg, TopicName}, connected,
             State = #state{next_packet_id = PacketId,
                            socket = Socket, config = Config}) ->
  ?LOG_STATE(debug, "Request Gateway to register and then wait for regack",
             {topic_name = TopicName}, State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_register(Socket, PacketId, TopicName),
  {next_state, wait_reg,
   State#state{next_packet_id = next_packet_id(PacketId),
               waiting_data = {reg, TopicName}},
   {timeout, AckTimeout, {PacketId, TopicName, ?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Request Gateway to subscribe and then wait for suback
%%
%% state  : [connected] -> [wait_sub]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {sub, TopicIdType, TopicIdOrName}, connected,
             State = #state{next_packet_id = PacketId,
                            socket = Socket, config = Config}) ->
  ?LOG_STATE(debug, "Request Gateway to subscribe and then wait for suback",
             {type = TopicIdType, topic_id_or_name = TopicIdOrName}, State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_subscribe(Socket, TopicIdType, PacketId, TopicIdOrName),
  State = State#state{next_packet_id = next_packet_id(PacketId),
                      waiting_data = {sub, TopicIdType, TopicIdOrName}},
  {next_state, wait_sub, State, {timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Request Gateway to publish and then wait for
%% nothing at QoS 0
%% puback  at QoS 1
%% pubrec  at QoS 2
%%
%% state  :
%% QoS 0: keep[connected]
%% QoS 1: [connected] -> [wait_pub_qos1]
%% QoS 2: [connected] -> [wait_pub_qos2]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {pub, Retain, TopicIdType, TopicIdOrName, Message}, connected,
             State = #state{next_packet_id = PacketId, socket = Socket,
                            topic_name_id = NameMap, config = Config,
                            topic_id_use_qos = QosMap}) ->
  ?LOG_STATE(debug, "Request Gateway to publish",
    {type = TopicIdType, topic_id_or_name = TopicIdOrName,
     retain = Retain}, State),
  #config{ack_timeout = AckTimeout,
          max_message_each_topic = TopicMaxMsg} = Config,
  TopicId = case TopicIdType of
              ?PRE_DEF_TOPIC_ID orelse ?TOPIC_ID -> TopicIdOrName;
              ?SHORT_TOPIC_NAME -> dict:fetch(TopicIdOrName, NameMap)
            end,
  Qos = dict:fetch(TopicId, QosMap),
  emqttsn_send:send_publish(Socket, Qos, ?DUP_FALSE, Retain,
                            TopicIdType, TopicIdOrName, PacketId, Message),

  case Qos of
    ?QOS_0 ->
      State = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Message),
      {keep_state, State#state{next_packet_id = next_packet_id(PacketId)}};
    ?QOS_1 -> {next_state, wait_pub_qos1,
               State#state{next_packet_id = next_packet_id(PacketId),
                           waiting_data = {pub, ?QOS_1, TopicIdType,
                                           TopicIdOrName, Message}},
               {timeout, AckTimeout, {Retain, ?RESEND_TIME_BEG}}};
    ?QOS_2 -> {next_state, wait_pub_qos2,
               State#state{next_packet_id = next_packet_id(PacketId),
                           waiting_data = {pub, ?QOS_2, TopicIdType,
                                           TopicIdOrName, Data}},
               {timeout, AckTimeout, {Retain, ?RESEND_TIME_BEG}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Receive publish request from other clients and then wait for
%% nothing at QoS 0/1
%% pubrel  at QoS 2
%%
%% state  :
%% QoS 0/1: keep [connected]
%% QoS 2  : [connected] -> [wait_pubrec_qos2]
%% trigger: receive publish packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, Packet = ?PUBLISH_PACKET(_RemoteDup, _RemoteQos,
                                            _RemoteRetain, _TopicIdType,
                                            _TopicId, _PacketId, _Data),
             connected, State) ->
  ?LOG_STATE(debug, "Receive publish request from other clients", {}, State),
  recv_publish(Packet, State, connected);

%%------------------------------------------------------------------------------
%% @doc Receive ping request from gateway
%%
%% state  : keep [connected]
%% trigger: receive pingreq packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PINGREQ_PACKET(ClientId), connected,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Receive ping request from gateway", {}, State),
  #config{strict_mode = StrictMode} = Config,
  if StrictMode andalso not ClientId == ?CLIENT_ID
    -> ?LOG_STATE(warn, "remote pingreq has a wrong client id",
                  {client_id = ClientId}, State)
  end,
  emqttsn_send:send_pingresp(Socket),
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Send ping request to gateway
%%
%% state  : [connected] -> [wait_pingreq]
%% trigger: state timeout
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, ping, connected,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Send ping request to gateway", {}, State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_pingreq(Socket),
  {next_state, wait_pingreq, State, {timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Notify Gateway to sleep for a duration
%%
%% state  : keep [connected]
%% trigger: manual call + zero sleep interval
%%
%% state  : [connected] -> [asleep]
%% trigger: manual call + valid sleep interval
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, sleep, connected,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Notify Gateway to sleep for a duration", {}, State),
  #config{sleep_interval = Interval} = Config,
  if
    Interval == 0 ->
      ?LOG_STATE(debug, "0 Sleep interval has no sleeping mode", {}, State),
      {keep_state, State};
    Interval > 0 ->
      emqttsn_send:send_asleep(Socket, Interval),
      {next_state, asleep, State, {timeout, Interval, ping}}
  end;

%-------------------------------------------------------------------------------
% Reconnect other gateways after failed
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Connect to other available gateway
%%
%% state  : [connect_other] -> [found]
%% trigger: enter state + have available gateway
%%
%% state  : [connect_other] -> [initialized]
%% trigger: enter state + have no available gateway
%%
%% state  : [connect_other] -> [initialized]
%% trigger: enter state + traverse known gateways exceed max times
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(enter, _OldState, connect_other,
             State = #state{active_gw = #gw_collect{id = FormerId},
                            config = Config, socket = Socket,
                            gw_failed_cycle = TryTimes, name = Name}) ->
  ?LOG_STATE(debug, "Connect to other available gateway", {}, State),
  #config{reconnect_max_times = MaxTry} = Config,
  Desperate = TryTimes > MaxTry,
  AvailableGW = emqttsn_utils:next_gw(Name, FormerId),
  FirstGW = emqttsn_utils:first_gw(Name),
  if FirstGW =:= AvailableGW
    -> State = State#state{gw_failed_cycle = TryTimes + 1}
  end,
  case AvailableGW of
    #gw_info{id = GWId, host = Host, port = Port} when not Desperate ->
      {next_state, found,
       State#state{active_gw = #gw_collect{id = GWId, host = Host,
                                           port = Port}}};
    none ->
      {next_state, initialized, #state{socket = Socket}};
    _ when Desperate ->
      {next_state, initialized, #state{socket = Socket}}
  end;

%-------------------------------------------------------------------------------
% Sleeping feature
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Send ping request to gateway to awake
%%
%% state  : [asleep] -> [awake]
%% trigger: state timeout
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, ping, asleep, State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Send ping request to gateway to awake", {}, State),
  #config{ack_timeout = AckTimeout, client_id = ClintId} = Config,
  emqttsn_send:send_awake(Socket, ClintId),
  {next_state, awake, State, {timeout, AckTimeout,
                              {recv_awake, ?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Receive publish request from other clients and then wait for
%% nothing at QoS 0/1
%% pubrel  at QoS 2
%%
%% state  :
%% QoS 0/1: keep [awake]
%% QoS 2  : [awake] -> [wait_pubrec_qos2]
%% trigger: receive publish packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, Packet = ?PUBLISH_PACKET(_RemoteDup, _RemoteQos, _RemoteRetain,
                                            _TopicIdType, _TopicId, _PacketId,
                                            _Data), awake, State) ->
  ?LOG_STATE(debug, "Receive publish request from other clients", {}, State),
  recv_publish(Packet, State, awake);

%%------------------------------------------------------------------------------
%% @doc Receive pingresp request from gateway and goto asleep
%%
%% state  : [awake] -> [asleep]
%% trigger: receive pingresp packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?PINGRESP_PACKET(), awake, State = #state{config = Config}) ->
  ?LOG_STATE(debug, "Receive pingresp request from gateway and goto asleep",
             {}, State),
  #config{sleep_interval = Interval} = Config,
  {next_state, asleep, State, {timeout, Interval, ping}};

%%------------------------------------------------------------------------------
%% @doc Answer for awake request is timeout and retry awake
%%
%% state  : keep [awake]
%% trigger: state timeout + can resend
%%
%% state  : [awake] -> [asleep]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(state_timeout, {recv_awake, ResendTimes}, awake,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Answer for awake request is timeout and retry awake",
             {resend_times = ResendTimes}, State),
  #config{max_resend = MaxResend, client_id = ClientId} = Config,
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_awake(Socket, ClientId),
      {keep_state, State, {timeout, update, {ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, asleep, State}
  end;

%%------------------------------------------------------------------------------
%% @doc Answer for gateway address request from other clients
%%
%% state  : keep Any
%% trigger: receive searchgw packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {?SEARCHGW_PACKET(Radius), Host, Port}, _StateName,
             State = #state{name = Name, socket = Socket}) ->
  ?LOG_STATE(debug, "Answer for gateway address request from other clients",
             {query_host = Host, query_port = Port}, State),
  FirstGW = emqttsn_utils:first_gw(Name),
  case FirstGW of
    #gw_info{id = GateWayId, host = GWHost} ->
      emqttsn_send:send_gwinfo(Socket, Host, Port, Radius, GateWayId, GWHost);
    _ -> _
  end,
  {keep_state, State};

%%------------------------------------------------------------------------------
%% @doc Receive register request from other clients
%%
%% state  : keep [connected]/[awake]
%% trigger: receive register packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?REGISTER_PACKET(TopicId, PacketId, TopicName),
             StateName, State = #state{socket = Socket})
  when StateName =:= connected orelse StateName =:= awake ->
  ?LOG_STATE(debug, "Receive register request from other clients",
    {topic_id = TopicId, packet_id = PacketId,
     topic_name = TopicName}, State),
  IdMap = IdMap#{TopicId => TopicName},
  NameMap = NameMap#{TopicName => TopicId},
  emqttsn_send:send_regack(Socket, TopicId, PacketId, ?RC_ACCEPTED),
  {keep_state, State#state{topic_id_name = IdMap, topic_name_id = NameMap,
                           next_packet_id = next_packet_id(PacketId)}};

%%------------------------------------------------------------------------------
%% @doc Request gateway for a new sleeping interval
%%
%% state  : keep [asleep]/[awake]
%% trigger: manual call + at [asleep]/[awake]

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, set_interval, StateName,
             State = #state{config = Config, socket = Socket})
  when StateName =:= asleep orelse StateName =:= awake ->
  ?LOG_STATE(debug, "Request gateway for a new sleeping interval", {}, State),
  #config{sleep_interval = Interval} = Config,
  if
    Interval == 0 ->
      {keep_state, State};
    Interval > 0 ->
      emqttsn_send:send_asleep(Socket, Interval),
      {repeat_state, State, {timeout, Interval, ping}}
  end;

%%------------------------------------------------------------------------------
%% @doc Request gateway to disconnect
%%
%% state  : [asleep]/[awake]/[connected] -> [initialized]
%% trigger: manual call + at [asleep]/[awake]/[connected]

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, disconnect, StateName, State = #state{socket = Socket})
  when StateName =:= asleep orelse StateName =:= awake orelse
       StateName =:= connected ->
  ?LOG_STATE(debug, "Request gateway to disconnect", {}, State),
  emqttsn_send:send_disconnect(Socket),
  {next_state, initialized, #state{socket = Socket}};

%%------------------------------------------------------------------------------
%% @doc Request gateway to become active
%%
%% state  : [asleep]/[awake] -> [found]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, connect, StateName, State)
  when StateName =:= asleep orelse StateName =:= awake ->
  ?LOG_STATE(debug, "Request gateway to become active", {}, State),
  {next_state, found, State};

%-------------------------------------------------------------------------------
% Consume message manager and counter
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Reset message manager and counter
%%
%% state  : keep Any
%% trigger: auto called by get_msg

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {reset_msg, MsgManager, MsgCounter}, _StateName, State) ->
  ?LOG_STATE(info, "Reset message",
             {message_manager = MsgManager, message_counter = MsgCounter}, State),
  {keep_state, State#state{msg_manager = MsgManager, msg_counter = MsgCounter}};

%-------------------------------------------------------------------------------
% Change config of state machine
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Change config of client
%%
%% state  : keep Any
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {config, Config}, _StateName, State) ->
  ?LOG_STATE(info, "Change config", {config = Config}, State),
  {keep_state, State#state{config = Config}};

%-------------------------------------------------------------------------------
% Get State from state machine
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Change config of client
%%
%% state  : keep Any
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event({call, From}, get_state, _StateName, State) ->
  ?LOG_STATE(info, "Get state", {}, State),
  gen_statem:reply(From, State),
  {keep_state, State};

%-------------------------------------------------------------------------------
% Handle disconnect at any state
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Gateway disconnect and try to reconnect
%%
%% state  : Any -> [found]
%% trigger: receive disconnect packet

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, ?DISCONNECT_PACKET(), _StateName, State) ->
  ?LOG_STATE(info, "Connection reset by server", {}, State),
  {next_state, found, State};

%-------------------------------------------------------------------------------
% Process incoming packet
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Low-level method for receive packet
%%
%% event  : {recv, {Host, Port, Bin}} -> {Packet, Host, Port}
%% trigger: receive ADVERTISE_PACKET/GWINFO_PACKET packet
%%
%% event  : {recv, {Host, Port, Bin}} -> {Packet, Host, Port}/Packet
%% trigger: receive other packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
handle_event(cast, {recv, {Host, Port, Bin}}, _StateName, State) ->
  ?LOG_STATE(debug, "RECV_Data",
             #{data => Bin, Host => Host, port => Port}, State),
  process_incoming({Host, Port, Bin}, State).

%%------------------------------------------------------------------------------
%% @doc Judge whether to reserve the source of sender
%% @end
%%------------------------------------------------------------------------------
-spec filter_packet_elsewhere(#mqtt_packet{}, host(), inet:port_number()) ->
  {#mqtt_packet{}, host(), inet:port_number()} | #mqtt_packet{}.
filter_packet_elsewhere(Packet, Host, Port) ->
  case Packet of
    ?ADVERTISE_PACKET(_GateWayId, _Duration) orelse
    ?GWINFO_PACKET(_GateWayId) ->
      {Packet, Host, Port};
    _ -> Packet
  end.

%%------------------------------------------------------------------------------
%% @doc Parse incoming binary data into packet
%% @end
%%------------------------------------------------------------------------------
-spec process_incoming({host(), inet:port_number(), bitstring()}, state())
                      -> {next_event, cast, {}}.
process_incoming({Host, Port, Bin},
                 #state{active_gw = #gw_collect{host = ServerHost,
                                                port = ServerPort}}) ->
  case emqttsn_frame:parse(Bin) of
    {ok, Packet} ->
      Ret = filter_packet_elsewhere(Packet, Host, Port),
      {next_event, cast, Ret};
    _ ->
      ?LOG(warn, "drop packet from other than gateway",
           #{server_host => ServerHost, server_port => ServerPort,
             actual_host => Host, actual_port => Port})
  end.

%-------------------------------------------------------------------------------
% Reused recv methods
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Shared processing method for publish packet
%% @end
%%------------------------------------------------------------------------------
-spec recv_publish(#mqtt_packet{}, state(), connected | await) -> {}.
recv_publish(?PUBLISH_PACKET(RemoteDup, RemoteQos, RemoteRetain, TopicIdType, TopicId, PacketId, Data),
    State = #state{next_packet_id = PacketId, topic_id_use_qos = QosMap,
                   config = Config, socket = Socket}, FromStateName) ->
  #config{ack_timeout = AckTimeout, max_message_each_topic = TopicMaxMsg} = Config,
  Qos = dict:fetch(TopicId, QosMap),
  State = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Data),
  case Qos of
    ?QOS_1 -> emqttsn_send:send_puback(Socket, TopicId, PacketId, ?RC_ACCEPTED);
    ?QOS_2 -> emqttsn_send:send_pubrec(Socket, PacketId)
  end,
  Qos = dict:fetch(TopicId, QosMap),
  case Qos of
    ?QOS_0 orelse ?QOS_1 -> {keep_state, State#state{next_packet_id = next_packet_id(PacketId)}};
    ?QOS_2 -> {next_state, wait_pubrec_qos2,
               State#state{next_packet_id = next_packet_id(PacketId), waiting_data = {FromStateName}},
               {timeout, AckTimeout, {?RESEND_TIME_BEG}}}
  end.