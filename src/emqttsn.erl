-module(emqttsn).

-include("config.hrl").
-include("packet.hrl").
-include("logger.hrl").

-include_lib("stdlib/include/assert.hrl").

-export([start_link/2, register/3, subscribe/5, unsubscribe/4, publish/6, add_host/4,
         connect/3, sleep/2, get_state/1, get_state_name/1, reset_config/2, stop/1, disconnect/1]).

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
          {ok, Socket, StateM, Config}
      end
  end.

-spec wait_until_state_name(client(), [atom()], boolean()) -> ok.
wait_until_state_name(Client, StateNames, Block) ->
  case {Block, get_state_name(Client)} of
    {false, _} ->
      ok;
    {true, S} ->
      case lists:member(S, StateNames) of
        true ->
          ok;
        false ->
          wait_until_state_name(Client, StateNames, true)
      end
  end.

-spec register(client(), string(), boolean()) -> ok.
register(Client, TopicName, Block) ->
  gen_statem:cast(Client, {reg, TopicName}),
  wait_until_state_name(Client, [connected], Block).

-spec subscribe(client(), topic_id_type(), topic_id_or_name(), qos(), boolean()) -> ok.
subscribe(Client, TopicIdType, TopicIdOrName, MaxQos, Block) ->
  gen_statem:cast(Client, {sub, TopicIdType, TopicIdOrName, MaxQos}),
  wait_until_state_name(Client, [connected], Block).

-spec unsubscribe(client(), topic_id_type(), topic_id_or_name(), boolean()) -> ok.
unsubscribe(Client, TopicIdType, TopicIdOrName, Block) ->
  gen_statem:cast(Client, {unsub, TopicIdType, TopicIdOrName}),
  wait_until_state_name(Client, [connected], Block).

-spec publish(client(),
              boolean(),
              topic_id_type(),
              topic_id_or_name(),
              string(),
              boolean()) ->
               ok.
publish(Client, Retain, TopicIdType, TopicIdOrName, Message, Block) ->
  gen_statem:cast(Client, {pub, Retain, TopicIdType, TopicIdOrName, Message}),
  wait_until_state_name(Client, [connected], Block).

-spec add_host(client(), host(), port(), gw_id()) -> ok.
add_host(Client, Host, Port, GateWayId) ->
  gen_statem:cast(Client, {add_gw, Host, Port, GateWayId}).

-spec connect(client(), gw_id(), boolean()) -> ok.
connect(Client, GateWayId, Block) ->
  gen_statem:cast(Client, {connect, GateWayId}),
  wait_until_state_name(Client, [connected], Block).

-spec sleep(client(), pos_integer()) -> ok.
sleep(Client, Interval) ->
  gen_statem:cast(Client, {sleep, Interval}).

-spec disconnect(client()) -> ok.
disconnect(Client) ->
  gen_statem:cast(Client, disconnect).

-spec get_state(client()) -> state().
get_state(Client) ->
  State = gen_statem:call(Client, get_state),
  State.

-spec get_state_name(client()) -> atom().
get_state_name(Client) ->
  StateName = gen_statem:call(Client, get_state_name),
  StateName.

-spec reset_config(client(), #config{}) -> ok.
reset_config(Client, Config) ->
  gen_statem:cast(Client, {config, Config}).

-spec stop(client()) -> ok.
stop(Client) ->
  StateName = get_state(Client),
  if StateName =/= initialized andalso StateName =/= found ->
       disconnect(Client),
       gen_statem:stop(Client);
     StateName =:= initialized orelse StateName =:= found ->
       gen_statem:stop(Client)
  end,
  ok.
