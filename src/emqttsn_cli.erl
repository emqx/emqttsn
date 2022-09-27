-module(emqttsn_cli).

-include("version.hrl").
-include("config.hrl").
-include("packet.hrl").

-export([main/1]).

-import(proplists, [get_value/2]).

-type sub_cmd() :: pub | sub.

-define(CMD_NAME, "emqtt-sn").
-define(HELP_OPT, [{help, undefined, "help", boolean, "Help information"}]).
-define(CONN_SHORT_OPTS,
        [{name, $n, "name", {string, "default"}, "client name(unique for each client)"},
         {host, $h, "host", {string, "localhost"}, "mqtt-sn server hostname or IP address"},
         {port, $p, "port", integer, "mqtt-sn server port number"},
         {iface, $I, "iface", string, "specify the network interface or ip address to use"},
         {protocol_version,
          $V,
          "protocol-version",
          {atom, ?MQTTSN_PROTO_V1_2},
          "mqtt-sn protocol version: v1.2"},
         {clientid, $C, "clientid", string, {atom, ?CLIENT_ID}, "client identifier"},
         {keepalive, $k, "keepalive", {integer, 300}, "keep alive in seconds"}]).
-define(CONN_LONG_OPTS,
        [{will_topic, undefined, "will-topic", string, "Topic for will message"},
         {will_payload, undefined, "will-payload", string, "Payload in will message"},
         {will_qos, undefined, "will-qos", {integer, 0}, "QoS for will message"},
         {will_retain, undefined, "will-retain", {boolean, false}, "Retain in will message"}]).
-define(PUB_OPTS,
        ?CONN_SHORT_OPTS
        ++ [{topic_id_type,
             $t,
             "topic_type",
             {atom, ?TOPIC_ID},
             "mqtt topic name on which to publish the message(exclusive with "
             "topic_id)"},
            {topic_id_or_name,
             $i,
             "topic_id_or_name",
             string,
             "mqtt topic id or name on which to publish the message(exclusive "
             "with topic_name)"},
            {qos,
             $q,
             "qos",
             {integer, 0},
             "qos level of assurance for delivery of an application message"},
            {retain, $r, "retain", {boolean, false}, "retain message or not"}]
        ++ ?HELP_OPT
        ++ ?CONN_LONG_OPTS
        ++ [{payload,
             undefined,
             "payload",
             string,
             "application message that is being published"}]).
-define(SUB_OPTS,
        ?CONN_SHORT_OPTS
        ++ [{topic_id_type,
             $t,
             "topic_type",
             {atom, ?TOPIC_ID},
             "mqtt topic name on which to subscribe to(exclusive with topic_id)"},
            {topic_id_or_name,
             $t,
             "topic_id_or_name",
             string,
             "mqtt topic id on which to subscribe to(exclusive with topic_name)"},
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

  ok = check_required_args(pub, [payload], Opts),

  main(pub, Opts);

main(_Argv) ->
  io:format("Usage: ~s pub | sub [--help]~n", [?CMD_NAME]).

-spec main(pub | sub, [term()]) -> ok.
main(PubSub, Opts) ->
  application:ensure_all_started(emqttsn),

  NOpts = parse_cmd_opts(Opts),

  {Socket, Client, Config} = emqttsn:start_link(get_value(name, NOpts), NOpts),
  io:format("Client ~s sent CONNECT~n", [get_value(clientid, NOpts)]),
  case PubSub of
    pub ->
      publish(Client, NOpts),
      disconnect(Client, NOpts);
    sub ->
      subscribe(Client, NOpts),
      emqttsn_udp:recv(Socket, Client, Config)
  end,
  ok.

-spec publish(emqtsn:client(), [term()]) -> ok.
publish(Client, Opts) ->
  Payload = get_value(payload, Opts),
  Retain = get_value(retain, Opts),
  TopicIdType = get_value(topic_id_type, Opts),
  TopicIdOrName = get_value(topic_id_or_name, Opts),
  emqttsn:publish(Client, Retain, TopicIdType, TopicIdOrName, Payload),
  ok.

-spec subscribe(emqtsn:client(), [term()]) -> ok.
subscribe(Client, Opts) ->
  TopicIdType = get_value(topic_id_type, Opts),
  TopicIdOrName = get_value(topic_id_or_name, Opts),
  MaxQos = get_value(qos, Opts),
  emqttsn:subscribe(Client, TopicIdType, TopicIdOrName, MaxQos),
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

parse_cmd_opts(Opts) ->
  parse_cmd_opts(Opts, []).

parse_cmd_opts([], Acc) ->
  Acc;
parse_cmd_opts([{host, Host} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{host, Host} | Acc]);
parse_cmd_opts([{port, Port} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{port, Port} | Acc]);
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
parse_cmd_opts([{clientid, Clientid} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{clientid, list_to_binary(Clientid)} | Acc]);
parse_cmd_opts([{will_topic, Topic} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{will_topic, list_to_binary(Topic)} | Acc]);
parse_cmd_opts([{will_payload, Payload} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{will_payload, list_to_binary(Payload)} | Acc]);
parse_cmd_opts([{will_qos, Qos} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{will_qos, Qos} | Acc]);
parse_cmd_opts([{will_retain, Retain} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{will_retain, Retain} | Acc]);
parse_cmd_opts([{keepalive, I} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{keepalive, I} | Acc]);
parse_cmd_opts([{qos, QoS} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{qos, QoS} | Acc]);
parse_cmd_opts([{topic_name, TopicName} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{topic_name, TopicName} | Acc]);
parse_cmd_opts([{topic_id, TopicId} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{topic_id, TopicId} | Acc]);
parse_cmd_opts([{retain, Retain} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{retain, Retain} | Acc]);
parse_cmd_opts([{payload, Payload} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{payload, list_to_binary(Payload)} | Acc]);
parse_cmd_opts([_ | Opts], Acc) ->
  parse_cmd_opts(Opts, Acc).

maybe_append(Key, Value, TupleList) ->
  case lists:keytake(Key, 1, TupleList) of
    {value, {Key, OldValue}, NewTupleList} ->
      [{Key, [Value | OldValue]} | NewTupleList];
    false ->
      [{Key, [Value]} | TupleList]
  end.
