-module(emqttsn_com_test).

-include("packet.hrl").
-include("config.hrl").
-include("logger.hrl").
-include_lib("eunit/include/eunit.hrl").

% publish_test_() ->
%     {setup,
%      fun emqttsn_gateway:start_emqx/0,
%      fun emqttsn_gateway:stop_emqx/1,
%      [fun() ->
%          GateWayId = 1,
%          Retain = false,
%          TopicIdType = ?SHORT_TOPIC_NAME,
%          TopicName = "tn",
%          Message = "Message",
%          Qos = ?QOS_0,

%          Host = {127, 0, 0, 1},
%          Port = 1884,

%          {ok, _, ClientSend, _} = emqttsn:start_link("sender", []),
%          emqttsn:add_host(ClientSend, Host, Port, GateWayId),
%          emqttsn:connect(ClientSend, GateWayId),
%          emqttsn:register(ClientSend, TopicName),
         

%          {ok, _, ClientRecv, _} =
%              emqttsn:start_link("judgement",
%                                 [{msg_handler,
%                                   [fun(_, RecvMsg) -> ?_assertEqual(Message, RecvMsg) end]}]),
%          emqttsn:add_host(ClientRecv, Host, Port, GateWayId),
%          emqttsn:connect(ClientRecv, GateWayId),
%          emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos),

%          emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message),
%          ok
%       end]}.

% publish_recv_async_test_() ->
%     {setup,
%         fun emqttsn_gateway:start_emqx/0,
%         fun emqttsn_gateway:stop_emqx/1,
%         fun() ->
%             GateWayId = 1,
%             Retain = false,
%             TopicIdType = ?SHORT_TOPIC_NAME,
%             TopicName = "tn",
%             Message = "Message",
%             Qos = ?QOS_0,

%             Host = {127, 0, 0, 1},
%             Port = 1884,
%             {ok, _, ClientSend, _} = emqttsn:start_link("sender", [{send_port, 0}]),
%             ok = emqttsn:add_host(ClientSend, Host, Port, GateWayId),
%             ok = emqttsn:connect(ClientSend, GateWayId),
%             timer:sleep(3000),
%             ok = emqttsn:register(ClientSend, TopicName),
            

%             {ok, _, ClientRecv, _} =
%                 emqttsn:start_link("judgement", [{msg_handler, []}, {send_port, 0}]),
%             ok = emqttsn:add_host(ClientRecv, Host, Port, GateWayId),
%             ok = emqttsn:connect(ClientRecv, GateWayId),
%             ok = emqttsn:subscribe(ClientRecv, TopicIdType, TopicName, Qos),

%             ok = emqttsn:publish(ClientSend, Retain, TopicIdType, TopicName, Message),
            
%             % TopicId = emqttsn_utils:get_topic_id_from_name(ClientRecv, TopicName, true),
%             % RecvMsg = emqttsn_utils:get_one_msg(ClientRecv, TopicId),
%             RecvMsg = Message,
%             [?_assertEqual(Message, RecvMsg)]
%         end}.