-module(emqttsn_state).
-behavior(gen_statem).

-include("packet.hrl").
-include("config.hrl").
-include("logger.hrl").
-include_lib("stdlib/include/assert.hrl").

-import(emqttsn_utils, [next_packet_id/1]).

-export([init/1, callback_mode/0, start_link/2, handle_event/4]).



-spec callback_mode() -> gen_statem:callback_mode_result().
callback_mode() ->
  [handle_event_function, state_enter].

-spec start_link(string(), {inet:socket(), config()}) -> {ok, pid()} | {error, term()}.
start_link(Name, {Socket, Config}) ->
  case gen_statem:start_link({global, Name}, ?MODULE, {Name, Socket, Config}, []) of
    {'ok', Pid} -> {ok, Pid};
    'ignore' -> 
      ?LOG(error, "gen_statem starting process returns ignore", #{reason => ignore}),
      {error, ignore};
    {error, Reason} -> 
      ?LOG(error, "gen_statem starting process failed", #{reason => Reason}),
      {error, Reason}
  end.

-spec init({string(), inet:socket(), config()}) -> {ok, atom(), state()}.
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

-spec handle_event(atom(), term(), atom(), state()) -> gen_statem:event_handler_result(state()).
handle_event(enter, _OldState, initialized,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Find the Host of service gateway", [], State),
  #config{search_gw_interval = Interval} = Config,
  case emqttsn_send:broadcast_searchgw(Config, Socket, ?DEFAULT_PORT, ?DEFAULT_RADIUS) of
    {ok, NewSocket} -> 
      {keep_state, State#state{socket = NewSocket}, {state_timeout, Interval, {}}};
    {error, _Reason} ->
      {keep_state, State, {state_timeout, Interval, {}}}
    end;

%%------------------------------------------------------------------------------
%% @doc Resend searchgw when reach time interval T_SEARCHGW
%%
%% state  : repeat [initialized]
%% trigger: state timeout

%% @see gen_statem for state machine
%% @see T_SEARCHGW
%% @end
%%------------------------------------------------------------------------------

handle_event(state_timeout, {}, initialized, State = #state{config = Config}) ->
  #config{search_gw_interval = Interval} = Config,
  ?LOG_STATE(debug, "Resend searchgw when reach time interval T_SEARCHGW ~p", [Interval], State),
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
             _StateName, State = #state{name = Name}) ->
  ?LOG_STATE(notice, "Fetch gateway id ~p at ~p:~p from received broadcast ADVERTISE packet",
             [GateWayId, Host, Port], State),
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

handle_event(cast, {?GWINFO_PACKET(GateWayId), Host, Port},
             _StateName, State = #state{name = Name}) ->
  ?LOG_STATE(notice, "Fetch gateway id ~p at ~p:~p from received broadcast GWINFO packet by gateway",
              [GateWayId, Host, Port], State),
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
             _StateName, State = #state{name = Name}) ->
  ?LOG_STATE(notice, "Fetch gateway id ~p at ~p:~p from received broadcast GWINFO packet by client",
              [GateWayId, GateWayAdd, ?DEFAULT_PORT], State),
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

handle_event(cast, {add_gw, Host, Port, GateWayId}, _StateName,
             State = #state{name = Name}) ->
  ?LOG_STATE(notice, "Fetch gateway id ~p at ~p:~p from manual add",
              [GateWayId, Host, Port], State),
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
             State = #state{name = Name, socket = Socket}) ->
  ?LOG_STATE(debug, "Request to connect a exist gateway id ~p",
             [GateWayId], State),
  case emqttsn_utils:get_gw(Name, GateWayId) of
    none -> 
      {keep_state, State};
  #gw_info{host = Host, port = Port} ->
    emqttsn_udp:connect(Socket, Host, Port),
    {next_state, found,
    State#state{socket = Socket, active_gw =
    #gw_collect{id = GateWayId, host = Host, port = Port}}}
  end;

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
  ?LOG_STATE(debug, "Connect to service gateway", [], State),
  #config{will = Will, clean_session = CleanSession,
          duration = Duration, client_id = ClientId,
          ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_connect(Config, Socket, Will, CleanSession, Duration, ClientId),
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
  #config{max_resend = MaxResend} = Config,
  ?LOG_STATE(warning, "Found timeout to receive gateway response, retry: ~p/~p",
            [ResendTimes], State),
  
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
             [], State),
  #config{will_qos = Qos, will_topic = WillTopic} = Config,
  Retain = false,
  emqttsn_send:send_willtopic(Config, Socket, Qos, Retain, WillTopic),
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
             [], State),
  #config{will_msg = WillMsg} = Config,
  emqttsn_send:send_willmsg(Config, Socket, WillMsg),
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
  ?LOG_STATE(debug, "Gateway ensure connection is established", [], State),
  #config{keep_alive = PingInterval} = Config,
  {next_state, connected, State#state{gw_failed_cycle = 0},
   {state_timeout, PingInterval, ping}};

%%------------------------------------------------------------------------------
%% @doc Connection is failed to establish
%%
%% state  : keep [found]
%% trigger: receive connack packet and return code failed

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(cast, ?CONNACK_PACKET(ReturnCode), found,
             State = #state{name = Name, socket = Socket, config = Config}) ->
  ?LOG_STATE(error, "failed for connect response, return code: ~p",
             [ReturnCode], State),
  {next_state, initialized, #state{name = Name, socket = Socket, config = Config}};

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
  
  case ReturnCode of
    ?RC_ACCEPTED ->
      ?LOG_STATE(debug, "Finish register topic id ~p and back to connected, packet id ~p",
        [TopicId, RemotePacketId], State),
      NewIdMap = dict:store(TopicId, TopicName, IdMap),
      NewNameMap = dict:store(TopicName, TopicId, NameMap),
      {next_state, connected,
      State#state{next_packet_id = next_packet_id(RemotePacketId),
                  waiting_data = {}, topic_id_name = NewIdMap,
                  topic_name_id = NewNameMap}};
    _ -> 
      ?LOG_STATE(error, "failed for register response, return code: ~p",
                    [ReturnCode], State),
      {next_state, connected,
      State#state{next_packet_id = next_packet_id(RemotePacketId),
                  waiting_data = {}, topic_id_name = IdMap,
                  topic_name_id = NameMap}}
  end;
  

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

handle_event(state_timeout, {ResendTimes}, wait_reg,
             State = #state{next_packet_id = PacketId, config = Config, 
                            waiting_data = {reg, TopicName}, socket = Socket}) ->
  #config{max_resend = MaxResend, resend_no_qos = WhetherResend,
          ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(debug, "Answer for register topic name ~p is timeout 
              and retry register, packet id: ~p, retry: ~p/~p",
              [TopicName, PacketId, ResendTimes, MaxResend], State),
  
  if
    WhetherResend andalso ResendTimes < MaxResend ->
      emqttsn_send:send_register(Config, Socket, PacketId, TopicName),
      {keep_state, State#state{next_packet_id = PacketId,
                               waiting_data = {reg, TopicName}},
       {state_timeout, AckTimeout, {ResendTimes + 1}}};
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
                            waiting_data = {sub, TopicIdType, TopicIdOrName, _MaxQos}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish subscribe request and back to connected, 
            packet: ~p, topic: ~p, return_code: ~p, qos: ~p",
            [RemotePacketId, TopicIdOrName, ReturnCode, GrantQos], State),
  #config{recv_qos = LocalQos} = Config,
  case ReturnCode of
    ?RC_ACCEPTED -> 
      Qos = min(GrantQos, LocalQos),
      NewQosMap = dict:store(RemoteTopicId, Qos, QosMap),
      case TopicIdType of
        ?SHORT_TOPIC_NAME ->
          NewIdMap = dict:store(RemoteTopicId, TopicIdOrName, IdMap),
          NewNameMap = dict:store(TopicIdOrName, RemoteTopicId, NameMap),
          {next_state, connected,
           State#state{next_packet_id = next_packet_id(LocalPacketId),
                  waiting_data = {}, topic_id_name = NewIdMap,
                  topic_name_id = NewNameMap, topic_id_use_qos = NewQosMap}};
        _ ->
          ?assertEqual(RemoteTopicId, TopicIdOrName),
          {next_state, connected,
           State#state{next_packet_id = next_packet_id(LocalPacketId),
                  waiting_data = {}, topic_id_use_qos = NewQosMap}}
      end;
    _ -> 
      ?LOG_STATE(error, "failed for subscribe response, return_code: ~p",
                    [ReturnCode], State),
      {next_state, connected,
       State#state{next_packet_id = next_packet_id(LocalPacketId),
                   waiting_data = {}}}
    end;

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
                    waiting_data = {sub, TopicIdType, TopicIdOrName, MaxQos}}) ->
  #config{max_resend = MaxResend, resend_no_qos = WhetherResend,
          ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for subscribe request is timeout and retry subscribe, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  if
    WhetherResend andalso ResendTimes < MaxResend ->
      emqttsn_send:send_subscribe(Config, Socket, true, TopicIdType,
                                  PacketId, TopicIdOrName, MaxQos),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {sub, TopicIdType, TopicIdOrName, MaxQos}},
       {state_timeout, AckTimeout, {ResendTimes + 1}}};
    not WhetherResend orelse ResendTimes >= MaxResend ->
      {next_state, connected, State}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish unsubscribe request and back to connected
%%
%% state  : [wait_unsub] -> [connected]
%% trigger: receive unsuback packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(cast,
             ?UNSUBACK_PACKET(RemotePacketId),
             wait_unsub,
             State = #state{next_packet_id = LocalPacketId,
                            waiting_data = {unsub, TopicIdType, TopicIdOrName}})
  when RemotePacketId == LocalPacketId ->
    ?LOG_STATE(debug, "Finish unsubscribe request and back to connected, 
            packet: ~p, topic type: ~p, topic: ~p", [RemotePacketId, TopicIdType, TopicIdOrName], State),
    {next_state, connected, State#state{next_packet_id = next_packet_id(LocalPacketId),
                   waiting_data = {}}};

%%------------------------------------------------------------------------------
%% @doc Answer for unsubscribe request is timeout and retry unsubscribe
%%
%% state  : keep [wait_unsub]
%% trigger: state timeout + can resend
%%
%% state  : [wait_unsub] -> [connected]
%% trigger: state timeout + cannot resend
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(state_timeout, {ResendTimes}, wait_sub, State =
                  #state{next_packet_id = PacketId, config = Config, socket = Socket,
                         waiting_data = {unsub, TopicIdType, TopicIdOrName}}) ->
  #config{max_resend = MaxResend, resend_no_qos = WhetherResend,
          ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for unsubscribe request is timeout and retry subscribe, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  if
    WhetherResend andalso ResendTimes < MaxResend ->
      emqttsn_send:send_unsubscribe(Config, Socket, TopicIdType, PacketId, TopicIdOrName),
      {keep_state,
        State#state{next_packet_id = PacketId,
                    waiting_data = {unsub, TopicIdType, TopicIdOrName}},
        {state_timeout, AckTimeout, {ResendTimes + 1}}};
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
                                            LocalTopicIdOrName, Message}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish publish request and back to connected 
             when at QoS 1, packet: ~p, return_code: ~p",
             [RemotePacketId, ReturnCode], State),
  #config{max_message_each_topic = TopicMaxMsg} = Config,
  NewMap = case TopicIdType of
    ?PRE_DEF_TOPIC_ID -> 
      ?assertEqual(RemoteTopicId, LocalTopicIdOrName),
      Map;
    ?TOPIC_ID -> 
      ?assertEqual(RemoteTopicId, LocalTopicIdOrName),
      Map;
    ?SHORT_TOPIC_NAME -> 
      dict:store(RemoteTopicId, LocalTopicIdOrName, Map)
  end,
  if 
    ReturnCode =/= ?RC_ACCEPTED
      ->
        ?LOG_STATE(error, "Failed for publish response, return code: ~p",
                  [ReturnCode], State),
        {next_state, connected,
         State#state{next_packet_id = next_packet_id(LocalPacketId),
                               topic_id_name = NewMap}};
    ReturnCode =:= ?RC_ACCEPTED
      -> 
        NewState = emqttsn_utils:store_msg(State, RemoteTopicId, TopicMaxMsg, Message),
        {next_state, connected,
         NewState#state{next_packet_id = next_packet_id(LocalPacketId),
                        topic_id_name = NewMap}}
  end;
  

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
                                            TopicIdOrName, Message}}) ->
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for publish request is timeout 
             and retry publish at QoS 1, retain: ~p, retry: ~p/~p",
             [Retain, ResendTimes, MaxResend], State),
  
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_publish(Config, Socket, ?QOS_1, ?DUP_TRUE, Retain, TopicIdType,
                                TopicIdOrName, PacketId, Message),
      {keep_state, State#state{next_packet_id = PacketId,
                               waiting_data = {pub, ?QOS_1, TopicIdType,
                                               TopicIdOrName, Message}},
       {state_timeout, AckTimeout, {Retain, ResendTimes + 1}}};
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
                            waiting_data = {pub, ?QOS_2, TopicIdType,
                                            TopicIdOrName, Message}})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Continue publish request part 2, packet id: ~p",
             [RemotePacketId], State),
  TopicId = emqttsn_utils:get_topic_id(TopicIdType, TopicIdOrName, NameMap),
  #config{ack_timeout = AckTimeout,
          max_message_each_topic = TopicMaxMsg} = Config,
  NewState = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Message),
  emqttsn_send:send_pubrel(Config, Socket, RemotePacketId),
  {next_state, wait_pubrel_qos2,
  NewState#state{next_packet_id = next_packet_id(RemotePacketId),
               waiting_data = {pubrel, ?QOS_2}},
   {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};

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
                                            TopicIdOrName, Message}}) ->
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for publish request is timeout 
             at part 2, retain: ~p, retry: ~p/~p",
             [Retain, ResendTimes, MaxResend], State),
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_publish(Config, Socket, ?QOS_2, ?DUP_TRUE, Retain,
                                TopicIdType, TopicIdOrName, PacketId, Message),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {pub, ?QOS_2, TopicIdType,
                                   TopicIdOrName, Message}},
       {state_timeout, AckTimeout, {Retain, ResendTimes + 1}}};
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
  ?LOG_STATE(debug, "Finish publish request part 3, packet id: ~p",
             [RemotePacketId], State),
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
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for publish request is timeout at part 3, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pubrec(Config, Socket, PacketId),
      {keep_state,
       State#state{next_packet_id = PacketId,
                   waiting_data = {pubrel, ?QOS_2}},
       {state_timeout, AckTimeout, {ResendTimes + 1}}};
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
             State = #state{socket = Socket, config = Config,
                            next_packet_id = LocalPacketId})
  when RemotePacketId == LocalPacketId ->
  ?LOG_STATE(debug, "Finish receive publish part 2, packet id: ~p",
             RemotePacketId, State),
  emqttsn_send:send_pubcomp(Config, Socket, RemotePacketId),
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
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for receive publish is timeout at part 2, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pubrec(Config, Socket, PacketId),
      {keep_state, State#state{next_packet_id = PacketId},
       {state_timeout, AckTimeout, {ResendTimes + 1}}};
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
  ?LOG_STATE(debug, "Finish ping request and back to connected", [], State),
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
             State = #state{config = Config, socket = Socket}) ->
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for ping request is timeout and retry pingreq, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_pingreq(Config, Socket),
      {keep_state, State, {state_timeout, AckTimeout, {ResendTimes + 1}}};
    ResendTimes >= MaxResend ->
      {next_state, connect_other, State#state{waiting_data = {}}}
  end;

%%------------------------------------------------------------------------------
%% @doc Finish asleep request and go to asleep
%%
%% state  : [wait_asleep] -> [asleep]
%% trigger: receive pingresp packet
%%
%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(cast, ?DISCONNECT_PACKET(), wait_asleep, State = #state{waiting_data = {sleep, Interval}}) ->
  ?LOG_STATE(debug, "Finish asleep request and go to asleep", [], State),
  {next_state, asleep, State, {state_timeout, Interval, ready_awake}};

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

handle_event(state_timeout, {ResendTimes}, wait_asleep,
             State = #state{config = Config, socket = Socket, waiting_data = {sleep, Interval}}) ->
  #config{max_resend = MaxResend, ack_timeout = AckTimeout} = Config,
  ?LOG_STATE(warning, "Answer for asleep request is timeout and retry asleep, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_asleep(Config, Socket, Interval),
      {keep_state, State, {state_timeout, AckTimeout, {ResendTimes + 1}}};
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
  ?LOG_STATE(debug, "Request Gateway to register and then wait for regack, topic name: ~p",
             [TopicName], State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_register(Config, Socket, PacketId, TopicName),
  {next_state, wait_reg,
   State#state{waiting_data = {reg, TopicName}},
   {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Request Gateway to subscribe and then wait for suback
%%
%% state  : [connected] -> [wait_sub]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(cast, {sub, TopicIdType, TopicIdOrName, MaxQos}, connected,
             State = #state{next_packet_id = PacketId,
                            socket = Socket, config = Config}) ->
  ?LOG_STATE(debug, "Request Gateway to subscribe and then 
             wait for suback, type: ~p, topic: ~p",
             [TopicIdType, TopicIdOrName], State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_subscribe(Config, Socket, false, TopicIdType, PacketId, TopicIdOrName, MaxQos),
  {next_state, wait_sub, State#state{waiting_data = {sub, TopicIdType, TopicIdOrName, MaxQos}}, 
                                     {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};

%%------------------------------------------------------------------------------
%% @doc Request Gateway to unsubscribe and then wait for unsuback
%%
%% state  : [connected] -> [wait_unsub]
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------
                                     
handle_event(cast, {unsub, TopicIdType, TopicIdOrName}, connected,
             State = #state{next_packet_id = PacketId,
                            socket = Socket, config = Config}) ->
  ?LOG_STATE(debug, "Request Gateway to subscribe and then 
                     wait for suback, type: ~p, topic: ~p",
                     [TopicIdType, TopicIdOrName], State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_unsubscribe(Config, Socket, TopicIdType, PacketId, TopicIdOrName),
  {next_state, wait_unsub, State#state{waiting_data = {unsub, TopicIdType, TopicIdOrName}}, 
                                     {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};
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
                            topic_name_id = NameMap, config = Config}) ->
  ?LOG_STATE(debug, "Request Gateway to publish, type: ~p, topic: ~p, return code: ~p",
    [TopicIdType, TopicIdOrName, Retain], State),
  #config{ack_timeout = AckTimeout,
          max_message_each_topic = TopicMaxMsg, pub_qos = Qos} = Config,
  TopicId = emqttsn_utils:get_topic_id(TopicIdType, TopicIdOrName, NameMap),
  emqttsn_send:send_publish(Config, Socket, Qos, ?DUP_FALSE, Retain,
                            TopicIdType, TopicIdOrName, PacketId, Message),

  case Qos of
    ?QOS_0 ->
      NewState = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Message),
      {keep_state, NewState};
    ?QOS_1 -> {next_state, wait_pub_qos1,
               State#state{waiting_data = {pub, ?QOS_1, TopicIdType,
                                           TopicIdOrName, Message}},
               {state_timeout, AckTimeout, {Retain, ?RESEND_TIME_BEG}}};
    ?QOS_2 -> {next_state, wait_pub_qos2,
               State#state{waiting_data = {pub, ?QOS_2, TopicIdType,
                                           TopicIdOrName, Message}},
               {state_timeout, AckTimeout, {Retain, ?RESEND_TIME_BEG}}}
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
                                            _TopicId, _PacketId, _Message),
             connected, State) ->
  ?LOG_STATE(debug, "Receive publish request from other clients", [], State),
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
  ?LOG_STATE(debug, "Receive ping request from gateway", [], State),
  #config{strict_mode = StrictMode} = Config,
  if StrictMode andalso ClientId =/= ?CLIENT_ID
    -> ?LOG_STATE(warning, "remote pingreq has a wrong client id ~p",
                  [ClientId], State)
  end,
  emqttsn_send:send_pingresp(Config, Socket),
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
  ?LOG_STATE(debug, "Send ping request to gateway", [], State),
  #config{ack_timeout = AckTimeout} = Config,
  emqttsn_send:send_pingreq(Config, Socket),
  {next_state, wait_pingreq, State, {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}};

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

handle_event(cast, {sleep, Interval}, connected,
             State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Notify Gateway to sleep for a duration", [], State),
  if
    Interval =< 0 ->
      ?LOG_STATE(debug, "non-positive Sleep interval ~p leads to no sleeping mode", 
                 [Interval], State),
      {keep_state, State};
    Interval > 0 ->
      #config{ack_timeout = AckTimeout} = Config,
      emqttsn_send:send_asleep(Config, Socket, Interval),
      {next_state, wait_asleep, State#state{waiting_data = {sleep, Interval}}, 
      {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}}
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
  ?LOG_STATE(debug, "Connect to other available gateway", [], State),
  #config{reconnect_max_times = MaxTry} = Config,
  Desperate = TryTimes > MaxTry,
  AvailableGW = emqttsn_utils:next_gw(Name, FormerId),
  FirstGW = emqttsn_utils:first_gw(Name),
  if FirstGW =:= AvailableGW
    -> NewState = State#state{gw_failed_cycle = TryTimes + 1}
  end,
  case AvailableGW of
    #gw_info{id = GWId, host = Host, port = Port} when Desperate =:= false ->
      {next_state, found,
      NewState#state{active_gw = #gw_collect{id = GWId, host = Host,
                                           port = Port}}};
    _ ->
      {next_state, initialized, #state{name = Name, socket = Socket, config = Config}}
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

handle_event(state_timeout, ready_awake, asleep, State = #state{config = Config, socket = Socket}) ->
  ?LOG_STATE(debug, "Send ping request to gateway to awake", [], State),
  #config{ack_timeout = AckTimeout, client_id = ClintId} = Config,
  emqttsn_send:send_awake(Config, Socket, ClintId),
  {next_state, awake, State, {state_timeout, AckTimeout,
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
                                            _Message), awake, State) ->
  ?LOG_STATE(debug, "Receive publish request from other clients", [], State),
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
             [], State),
  #config{keep_alive = PingInterval} = Config,
  {next_state, asleep, State, {state_timeout, PingInterval, ping}};

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
  #config{max_resend = MaxResend, client_id = ClientId} = Config,
  ?LOG_STATE(warning, "Answer for awake request is timeout and retry awake, retry: ~p/~p",
             [ResendTimes, MaxResend], State),
  
  if
    ResendTimes < MaxResend ->
      emqttsn_send:send_awake(Config, Socket, ClientId),
      {keep_state, State, {state_timeout, update, {ResendTimes + 1}}};
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
             State = #state{name = Name, socket = Socket, config = Config}) ->
  ?LOG_STATE(debug, "Answer for gateway address ~p:~p request from other clients",
             [Host, Port], State),
  FirstGW = emqttsn_utils:first_gw(Name),
  case FirstGW of
    #gw_info{id = GateWayId, host = GWHost} ->
      emqttsn_send:send_gwinfo(Config, Socket, Host, Port, Radius, GateWayId, GWHost);
    none -> none
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
             StateName, State = #state{socket = Socket, topic_id_name = IdMap,
                                       topic_name_id = NameMap, config = Config})
  when StateName =:= connected orelse StateName =:= awake ->
  ?LOG_STATE(debug, "Receive register request for ~p:~p from other clients, packet id: ~p",
    [TopicId, TopicName, PacketId], State),
  NewIdMap = dict:store(TopicId, TopicName, IdMap),
  NewNameMap = dict:store(TopicName, TopicId, NameMap),
  emqttsn_send:send_regack(Config, Socket, TopicId, PacketId, ?RC_ACCEPTED),
  {keep_state, State#state{topic_id_name = NewIdMap, topic_name_id = NewNameMap,
                           next_packet_id = next_packet_id(PacketId)}};

%%------------------------------------------------------------------------------
%% @doc Request gateway to disconnect
%%
%% state  : [asleep]/[awake]/[connected] -> [initialized]
%% trigger: manual call + at [asleep]/[awake]/[connected]

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event(cast, disconnect, StateName,
             State = #state{name = Name,socket = Socket, config = Config})
  when StateName =:= asleep orelse StateName =:= awake orelse
       StateName =:= connected ->
  ?LOG_STATE(debug, "Request gateway to disconnect", [], State),
  emqttsn_send:send_disconnect(Config, Socket),
  {next_state, initialized, #state{name = Name, socket = Socket, config = Config}};

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
  ?LOG_STATE(debug, "Request gateway to become active", [], State),
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
  ?LOG_STATE(debug, "Reset message\nManager: ~p\nCounter:~p",
             [MsgManager, MsgCounter], State),
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
  ?LOG_STATE(debug, "Change config: ~p", [Config], State),
  {keep_state, State#state{config = Config}};

%-------------------------------------------------------------------------------
% Get State from state machine
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Get State data of client
%%
%% state  : keep Any
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event({call, From}, get_state, _StateName, State) ->
  ?LOG_STATE(debug, "Get state", [], State),
  gen_statem:reply(From, State),
  {keep_state, State};

  
%%------------------------------------------------------------------------------
%% @doc Get State name of client
%%
%% state  : keep Any
%% trigger: manual call

%% @see gen_statem for state machine
%% @end
%%------------------------------------------------------------------------------

handle_event({call, From}, get_state_name, StateName, State) ->
  ?LOG_STATE(debug, "Get state name: ~p", [StateName], State),
  gen_statem:reply(From, StateName),
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

handle_event(cast, ?DISCONNECT_PACKET(), StateName, State)
  when StateName =/= wait_asleep ->
  ?LOG_STATE(warning, "Connection reset by server", [], State),
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

handle_event(info, {udp, Socket, Host, Port, Bin}, _StateName, State = #state{socket = SelfSocket})
when Socket =:= SelfSocket ->
  ?LOG_STATE(debug, "recv packet {~p} from host ~p:~p",
    [Bin, Host, Port], State),
  process_incoming({Host, Port, Bin}, State);

handle_event(info,{udp_error, _Socket, Reason}, _StateName, State) ->
  ?LOG_STATE(debug, "recv failed for reason: ~p",
             [Reason], State),
  {keep_state, State};

handle_event(enter, Args, StateName, State) ->
  ?LOG_DEBUG("useless enter with ~p at ~p",
             [Args, StateName]),
  {keep_state, State};

handle_event(Operation, Args, StateName, State) ->
  ?LOG_WARNING("unsupported operation ~p with ~p at ~p",
             [Operation, Args, StateName]),
  {keep_state, State}.
%%------------------------------------------------------------------------------
%% @doc Judge whether to reserve the source of sender
%% @end
%%------------------------------------------------------------------------------

-spec filter_packet_elsewhere(mqttsn_packet(), host(), inet:port_number()) ->
  {mqttsn_packet(), host(), inet:port_number()} | mqttsn_packet().
filter_packet_elsewhere(Packet, Host, Port) ->
  case Packet of
    ?ADVERTISE_PACKET(_GateWayId, _Duration) ->
      {Packet, Host, Port};
    ?GWINFO_PACKET(_GateWayId) ->
      {Packet, Host, Port};
    _ -> Packet
  end.

%%------------------------------------------------------------------------------
%% @doc Parse incoming binary data into packet
%% @end
%%------------------------------------------------------------------------------

-spec process_incoming({host(), inet:port_number(), bitstring()}, state())
                      -> gen_statem:event_handler_result(state()).
process_incoming({Host, Port, Bin},
                  State = #state{active_gw = #gw_collect{host = ServerHost,
                                                port = ServerPort}}) ->
  case emqttsn_frame:parse(Bin) of
    {ok, Packet} ->
      Ret = filter_packet_elsewhere(Packet, Host, Port),
      {keep_state, State, {next_event, cast, Ret}};
    _ ->
      ?LOG(warning, "drop packet from other than gateway",
           #{server_host => ServerHost, server_port => ServerPort,
             actual_host => Host, actual_port => Port}),
      {keep_state, State}
  end.

%-------------------------------------------------------------------------------
% Reused recv methods
%-------------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% @doc Shared processing method for publish packet
%% @end
%%------------------------------------------------------------------------------

-spec recv_publish(mqttsn_packet(), state(), connected | awake) -> gen_statem:event_handler_result(state()).
recv_publish(?PUBLISH_PACKET(_RemoteDup, _RemoteQos, _RemoteRetain, TopicIdType, TopicIdOrName, PacketId, Message),
    State = #state{topic_id_use_qos = QosMap, config = Config, socket = Socket, topic_name_id = NameMap}, FromStateName) ->
  
  #config{ack_timeout = AckTimeout, max_message_each_topic = TopicMaxMsg} = Config,
  TopicId = emqttsn_utils:get_topic_id(TopicIdType, TopicIdOrName, NameMap),
  Qos = dict:fetch(TopicId, QosMap),
  NewState = emqttsn_utils:store_msg(State, TopicId, TopicMaxMsg, Message),
  case Qos of
    ?QOS_0 -> 
      {keep_state, NewState#state{next_packet_id = next_packet_id(PacketId)}};
    ?QOS_1 -> 
      emqttsn_send:send_puback(Config, Socket, TopicId, PacketId, ?RC_ACCEPTED),
      {keep_state, NewState#state{next_packet_id = PacketId}};
    ?QOS_2 -> 
      emqttsn_send:send_pubrec(Config, Socket, PacketId),
      {next_state, wait_pubrec_qos2,
               NewState#state{next_packet_id = PacketId, waiting_data = {FromStateName}},
               {state_timeout, AckTimeout, {?RESEND_TIME_BEG}}}
  end.