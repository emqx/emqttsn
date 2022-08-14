-module(emqttsn).

-include("config.hrl").
-include("packet.hrl").
-export([start_link/2, register/2, subscribe/3, publish/5, add_host/4,
         connect/2, get_state/1, reset_config/2, stop/1]).

-record(client, {
  state_m :: pid(),
  receiver :: pid()
}).
-type client() :: #client{}.

-spec merge_opt(#config{}, [option()]) -> #config{}.
merge_opt(Config, [Option | Options]) ->
  {Key, Value} = Option,
  merge_opt(Options, Config#{Key = Value});

merge_opt(Config, []) ->
  Config.


-spec start_link(string(), [option()]) -> client().
start_link(Name, Option) ->
  Config = merge_opt(#config{}, Option),
  #config{send_port = Port} = Config,

  Socket = emqttsn_udp:init_port(Port),
  StateM = emqttsn_state:start_link(Name, {Socket, Config}),
  Receiver = spawn(emqttsn_udp, recv, [Socket, StateM]),
  #client{state_m = StateM, receiver = Receiver}.


-spec register(client(), string()) -> no_return().
register(#client{state_m = StateM}, TopicName) ->
  gen_statem:cast(StateM, {reg, TopicName}).

-spec subscribe(client(), topic_id_type(), topic_id_or_name()) -> no_return().
subscribe(#client{state_m = StateM}, TopicIdType, TopicIdOrName) ->
  gen_statem:cast(StateM, {sub, TopicIdType, TopicIdOrName}).

-spec publish(client(), bool(), topic_id_type(), topic_id_or_name(), string()) -> no_return().
publish(#client{state_m = StateM}, Retain, TopicIdType, TopicIdOrName, Message) ->
  gen_statem:cast(StateM, {pub, Retain, TopicIdType, TopicIdOrName, Message}).

-spec add_host(client(), host(), port(), bitstring()) -> no_return().
add_host(#client{state_m = StateM}, Host, Port, GateWayId) ->
  gen_statem:cast(StateM, {add_gw, Host, Port, GateWayId}).

-spec add_host(client(), host(), port(), bitstring()) -> no_return().
connect(#client{state_m = StateM}, GateWayId) ->
  gen_statem:cast(StateM, {connect, GateWayId}).

-spec get_state(client()) -> state().
get_state(#client{state_m = StateM}) ->
  State = gen_statem:call(StateM, get_state),
  State.

-spec reset_config(client(), #config{}) -> no_return().
reset_config(#client{state_m = StateM}, Config) ->
  gen_statem:cast(StateM, {config, Config}).

-spec stop(client()) -> no_return().
stop(Client) ->
  #client{state_m = StateM, receiver = Receiver} = Client,
  gen_statem:stop(StateM),
  exit(Receiver).