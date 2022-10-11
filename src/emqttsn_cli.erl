-module(emqttsn_cli).

-include("version.hrl").
-include("packet.hrl").
-include("config.hrl").

-export([main/1]).

-import(proplists, [get_value/2]).

-type sub_cmd() :: pub | sub.

-define(CMD_NAME, "emqttsn").
-define(HELP_OPT, [{help, undefined, "help", boolean, "Help information"}]).
-define(CONN_SHORT_OPTS,
        [{name, $n, "name", {string, ?CLIENT_ID}, "client name(equal to client_id, unique for each client)"},
         {host, $h, "host", {string, "127.0.0.1"}, "mqtt-sn server hostname or IP address"},
         {port, $p, "port", {integer, 1884}, "mqtt-sn server port number"},
         {iface, $I, "iface", string, "specify the network interface or ip address to use"},
         {will, $w, "will", {bool, false}, "whether the client need a will message"},
         {protocol_version,
          $V,
          "protocol-version",
          {atom, ?MQTTSN_PROTO_V1_2},
          "mqtt-sn protocol version: v1.2"},
         {keepalive, $k, "keepalive", {integer, 300}, "keep alive in seconds"}]).
-define(CONN_LONG_OPTS,
        [{will_topic, undefined, "will-topic", string, "Topic for will message"},
         {will_msg, undefined, "will-message", string, "Payload in will message"},
         {will_qos, undefined, "will-qos", {integer, 0}, "QoS for will message"},
         {will_retain, undefined, "will-retain", {boolean, false}, "Retain in will message"}]).
-define(PUB_OPTS,
        ?CONN_SHORT_OPTS
        ++ [{topic_id_type,
             $t,
             "topic_id_type",
             {integer, ?PRE_DEF_TOPIC_ID},
             "mqtt topic id type(0 - topic id, 1 - predefined topic id, 2 - short topic name)"},
            {topic_id,
             $i,
             "topic_id",
             integer,
             "mqtt topic id on which to publish the message(exclusive "
             "with topic_name)"},
             {topic_name,
             $m,
             "topic_name",
             string,
             "mqtt topic name on which to publish the message(exclusive "
             "with topic_id)"},
            {qos,
             $q,
             "qos",
             {integer, 0},
             "qos level of assurance for delivery of an application message"},
            {retain, $r, "retain", {boolean, false}, "retain message or not"}]
        ++ ?HELP_OPT
        ++ ?CONN_LONG_OPTS
        ++ [{message,
             undefined,
             "message",
             string,
             "application message that is being published"}]).
-define(SUB_OPTS,
        ?CONN_SHORT_OPTS
        ++ [{topic_id_type,
             $t,
             "topic_id_type",
             {integer, ?PRE_DEF_TOPIC_ID},
             "mqtt topic id type(0 - topic id, 1 - predefined topic id, 2 - short topic name)"},
             {topic_id,
             $i,
             "topic_id",
             integer,
             "mqtt topic id on which to subscribe to(exclusive "
             "with topic_name)"},
             {topic_name,
             $m,
             "topic_name",
             string,
             "mqtt topic name on which to subscribe to(exclusive "
             "with topic_id)"},
            {qos,
             $q,
             "qos",
             {integer, 0},
             "maximum qos level at which the server can receive application "
             "messages to the client"}]
        ++ ?HELP_OPT
        ++ ?CONN_LONG_OPTS
        ++ []).

-spec main([string()]) -> ok.
main(["sub" | Argv]) ->
  {ok, {Opts, _Args}} = getopt:parse(?SUB_OPTS, Argv),
  ok = maybe_help(sub, Opts),

  main(sub, Opts);
main(["pub" | Argv]) ->
  {ok, {Opts, _Args}} = getopt:parse(?PUB_OPTS, Argv),
  ok = maybe_help(pub, Opts),

  ok = check_required_args(pub, [message], Opts),

  main(pub, Opts);
main(_Argv) ->
  io:format("Usage: ~s pub | sub [--help]~n", [?CMD_NAME]).

-spec main(pub | sub, [term()]) -> ok | no_return().
main(PubSub, Opts) ->
  application:ensure_all_started(emqttsn),

  NOpts = parse_cmd_opts(Opts),
  Name = proplists:get_value(name, NOpts),
  Host = proplists:get_value(host, NOpts),
  Port = proplists:get_value(port, NOpts),

  {ok, Socket, Client, Config} = emqttsn:start_link(Name, NOpts),
  emqttsn:add_host(Client, Host, Port, 1),
  emqttsn:connect(Client, 1, true),
  io:format("Client ~s CONNECT finished", [Name]),
  case PubSub of
    pub ->
      publish(Client, Config, NOpts),
      disconnect(Client, NOpts);
    sub ->
      subscribe(Client, Config, NOpts),
      loop_recv(Socket)
  end,
  ok.

-spec publish(emqtsn:client(), config(), [term()]) -> ok.
publish(Client, _Config, Opts) ->
  Message = get_value(message, Opts),
  Retain = get_value(retain, Opts),
  TopicIdType = get_value(topic_id_type, Opts),
  TopicIdOrName = case TopicIdType of
    ?SHORT_TOPIC_NAME -> get_value(topic_name, Opts);
    ?TOPIC_ID -> get_value(topic_id, Opts);
    ?PRE_DEF_TOPIC_ID -> get_value(topic_id, Opts)
  end,
  emqttsn:publish(Client, Retain, TopicIdType, TopicIdOrName, Message, true),
  ok.

-spec loop_recv(inet:socket()) -> no_return().
loop_recv(Socket) ->
  emqttsn_udp:recv(Socket),
  loop_recv(Socket).

-spec subscribe(emqtsn:client(), config(), [term()]) -> ok.
subscribe(Client, Config, Opts) ->
  TopicIdType = get_value(topic_id_type, Opts),
  TopicIdOrName = case TopicIdType of
    ?SHORT_TOPIC_NAME -> get_value(topic_name, Opts);
    ?TOPIC_ID -> get_value(topic_id, Opts);
    ?PRE_DEF_TOPIC_ID -> get_value(topic_id, Opts)
  end,
  MaxQos = get_value(qos, Opts),
  emqttsn:subscribe(Client, TopicIdType, TopicIdOrName, MaxQos, true),
  ok.

-spec disconnect(emqtsn:client(), [term()]) -> ok.
disconnect(Client, _Opts) ->
  emqttsn:stop(Client),
  ok.

-spec maybe_help(sub_cmd(), [term()]) -> ok.
maybe_help(PubSub, Opts) ->
  case proplists:get_value(help, Opts) of
    true ->
      usage(PubSub),
      halt(0);
    _ ->
      ok
  end.

-spec usage(sub_cmd()) -> ok | no_return().
usage(PubSub) ->
  Opts =
    case PubSub of
      pub ->
        ?PUB_OPTS;
      sub ->
        ?SUB_OPTS
    end,
  getopt:usage(Opts, ?CMD_NAME ++ " " ++ atom_to_list(PubSub)).

-spec check_required_args(sub_cmd(), [atom()], [term()]) -> ok | no_return().
check_required_args(PubSub, Keys, Opts) ->
  lists:foreach(fun(Key) ->
                   case lists:keyfind(Key, 1, Opts) of
                     false ->
                       io:format("Error: '~s' required~n", [Key]),
                       usage(PubSub),
                       halt(1);
                     _ -> ok
                   end
                end,
                Keys),
  ok.

-spec parse_cmd_opts([{atom(), term()}]) -> [{atom(), term()}].
parse_cmd_opts(Opts) ->
  parse_cmd_opts(Opts, []).

-spec parse_cmd_opts([{atom(), term()}], [{atom(), term()}]) -> [{atom(), term()}].
parse_cmd_opts([], Acc) ->
  Acc;
parse_cmd_opts([{host, Host} | Opts], Acc) ->
  {ok, StdAddress} = inet:parse_ipv4_address(Host),
  parse_cmd_opts(Opts, [{host, StdAddress} | Acc]);
parse_cmd_opts([{iface, Interface} | Opts], Acc) ->
  NAcc =
    case inet:parse_address(Interface) of
      {ok, IPAddress0} ->
        maybe_append(tcp_opts, {ifaddr, IPAddress0}, Acc);
      _ ->
        case inet:getifaddrs() of
          {ok, IfAddrs} ->
            case lists:filter(fun ({addr, {_, _, _, _}}) ->
                                    true;
                                  (_) ->
                                    false
                              end,
                              proplists:get_value(Interface, IfAddrs, []))
            of
              [{addr, IPAddress0}] ->
                maybe_append(tcp_opts, {ifaddr, IPAddress0}, Acc);
              _ ->
                Acc
            end;
          _ ->
            Acc
        end
    end,
  parse_cmd_opts(Opts, NAcc);
parse_cmd_opts([{protocol_version, 'v1.2'} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{proto_ver, ?MQTTSN_PROTO_V1_2} | Acc]);
parse_cmd_opts([{Key, Value} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{Key, Value} | Acc]).

-spec maybe_append(term(), term(), [{term(), term()}]) -> [{term(), term()}].
maybe_append(Key, Value, TupleList) ->
  case lists:keytake(Key, 1, TupleList) of
    {value, {Key, OldValue}, NewTupleList} ->
      [{Key, [Value | OldValue]} | NewTupleList];
    false ->
      [{Key, [Value]} | TupleList]
  end.
