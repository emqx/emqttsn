-module(emqttsn).

-include("config.hrl").
-include("packet.hrl").
-include("logger.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([start_link/2, register/2, subscribe/4, publish/5, add_host/4, connect/2,
         get_state/1, reset_config/2, stop/1]).

-export_type([client/0]).


-spec merge_opt(#config{}, [option()]) -> #config{}.
merge_opt(Config, [{strict_mode, Value} | Options]) ->
  merge_opt(Config#config{strict_mode = Value}, Options);
merge_opt(Config, [{clean_session, Value} | Options]) ->
  merge_opt(Config#config{clean_session = Value}, Options);
merge_opt(Config, [{max_size, Value} | Options]) ->
  merge_opt(Config#config{max_size = Value}, Options);
merge_opt(Config, [{auto_discover, Value} | Options]) ->
  merge_opt(Config#config{auto_discover = Value}, Options);
merge_opt(Config, [{ack_timeout, Value} | Options]) ->
  merge_opt(Config#config{ack_timeout = Value}, Options);
merge_opt(Config, [{keep_alive, Value} | Options]) ->
  merge_opt(Config#config{keep_alive = Value}, Options);
merge_opt(Config, [{resend_no_qos, Value} | Options]) ->
  merge_opt(Config#config{resend_no_qos = Value}, Options);
merge_opt(Config, [{max_resend, Value} | Options]) ->
  merge_opt(Config#config{max_resend = Value}, Options);
merge_opt(Config, [{retry_interval, Value} | Options]) ->
  merge_opt(Config#config{retry_interval = Value}, Options);
merge_opt(Config, [{connect_timeout, Value} | Options]) ->
  merge_opt(Config#config{connect_timeout = Value}, Options);
merge_opt(Config, [{search_gw_interval, Value} | Options]) ->
  merge_opt(Config#config{search_gw_interval = Value}, Options);
merge_opt(Config, [{reconnect_max_times, Value} | Options]) ->
  merge_opt(Config#config{reconnect_max_times = Value}, Options);
merge_opt(Config, [{max_message_each_topic, Value} | Options]) ->
  merge_opt(Config#config{max_message_each_topic = Value}, Options);
merge_opt(Config, [{sleep_interval, Value} | Options]) ->
  merge_opt(Config#config{sleep_interval = Value}, Options);
merge_opt(Config, [{msg_handler, Value} | Options]) ->
  merge_opt(Config#config{msg_handler = Value}, Options);
merge_opt(Config, [{send_port, Value} | Options]) ->
  merge_opt(Config#config{send_port = Value}, Options);
merge_opt(Config, [{proto_ver, Value} | Options]) ->
  merge_opt(Config#config{proto_ver = Value}, Options);
merge_opt(Config, [{proto_name, Value} | Options]) ->
  merge_opt(Config#config{proto_name = Value}, Options);
merge_opt(Config, [{radius, Value} | Options]) ->
  merge_opt(Config#config{radius = Value}, Options);
merge_opt(Config, [{duration, Value} | Options]) ->
  merge_opt(Config#config{duration = Value}, Options);
merge_opt(Config, [{recv_qos, Value} | Options]) ->
  merge_opt(Config#config{recv_qos = Value}, Options);
merge_opt(Config, [{pub_qos, Value} | Options]) ->
  merge_opt(Config#config{pub_qos = Value}, Options);
merge_opt(Config, [{will_qos, Value} | Options]) ->
  merge_opt(Config#config{will_qos = Value}, Options);
merge_opt(Config, [{will, Value} | Options]) ->
  merge_opt(Config#config{will = Value}, Options);
merge_opt(Config, [{will_topic, Value} | Options]) ->
  merge_opt(Config#config{will_topic = Value}, Options);
merge_opt(Config, [{will_msg, Value} | Options]) ->
  merge_opt(Config#config{will_msg = Value}, Options);
merge_opt(Config, []) ->
  Config.

-spec start_link(string(), [option()]) ->
                  {ok, inet:socket(), client(), config()} | {error, term()}.
start_link(Name, Option) ->
  NameLength = string:length(Name),
  ?assert(NameLength >= 1 andalso NameLength =< 23),
  Config = merge_opt(#config{client_id = Name}, Option),
  #config{send_port = Port} = Config,

  case emqttsn_udp:init_port(Port) of
    {error, Reason} ->
      ?LOG(error, "port init failed", #{reason => Reason}),
      {error, Reason};
    {ok, Socket} ->
      case emqttsn_state:start_link(Name, {Socket, Config}) of
        {error, Reason} ->
          ?LOG(error, "gen_statem init failed", #{reason => Reason}),
          {error, Reason};
        {ok, StateM} ->
          Receiver = spawn(emqttsn_udp, recv, [Socket, StateM, Config]),
          {ok, Socket, #client{state_m = StateM, receiver = Receiver}, Config}
      end
  end.

-spec register(client(), string()) -> ok.
register(#client{state_m = StateM}, TopicName) ->
  gen_statem:cast(StateM, {reg, TopicName}).

-spec subscribe(client(), topic_id_type(), topic_id_or_name(), qos()) -> ok.
subscribe(#client{state_m = StateM}, TopicIdType, TopicIdOrName, MaxQos) ->
  gen_statem:cast(StateM, {sub, TopicIdType, TopicIdOrName, MaxQos}).

-spec publish(client(), boolean(), topic_id_type(), topic_id_or_name(), string()) -> ok.
publish(#client{state_m = StateM}, Retain, TopicIdType, TopicIdOrName, Message) ->
  gen_statem:cast(StateM, {pub, Retain, TopicIdType, TopicIdOrName, Message}).

-spec add_host(client(), host(), port(), gw_id()) -> ok.
add_host(#client{state_m = StateM}, Host, Port, GateWayId) ->
  gen_statem:cast(StateM, {add_gw, Host, Port, GateWayId}).

-spec connect(client(), gw_id()) -> ok.
connect(#client{state_m = StateM}, GateWayId) ->
  gen_statem:cast(StateM, {connect, GateWayId}).

-spec get_state(client()) -> state().
get_state(#client{state_m = StateM}) ->
  State = gen_statem:call(StateM, get_state),
  State.

-spec reset_config(client(), #config{}) -> ok.
reset_config(#client{state_m = StateM}, Config) ->
  gen_statem:cast(StateM, {config, Config}).

-spec stop(client()) -> ok.
stop(Client) ->
  #client{state_m = StateM, receiver = Receiver} = Client,
  gen_statem:stop(StateM),
  exit(Receiver).
