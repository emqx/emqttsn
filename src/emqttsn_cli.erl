-module(emqttsn_cli).

-include("version.hrl").
-include("config.hrl").

-export([main/1]).

-import(proplists, [get_value/2]).

-type sub_cmd() :: pub|sub.

-define(CMD_NAME, "emqtt-sn").

-define(HELP_OPT,
  [{help, undefined, "help", boolean,
    "Help information"}
  ]).

-define(CONN_SHORT_OPTS,
  [{host, $h, "host", {string, "localhost"},
    "mqtt-sn server hostname or IP address"},
   {port, $p, "port", integer,
    "mqtt-sn server port number"},
   {iface, $I, "iface", string,
    "specify the network interface or ip address to use"},
   {protocol_version, $V, "protocol-version", {atom, ?MQTTSN_PROTO_V1_2},
    "mqtt-sn protocol version: v1.2"},
   {clientid, $C, "clientid", string, {atom, ?CLIENT_ID},
    "client identifier"},
   {keepalive, $k, "keepalive", {integer, 300},
    "keep alive in seconds"}
  ]).

-define(CONN_LONG_OPTS,
  [{will_topic, undefined, "will-topic", string,
  "Topic for will message"},
  {will_payload, undefined, "will-payload", string,
  "Payload in will message"},
  {will_qos, undefined, "will-qos", {integer, 0},
  "QoS for will message"}
  {will_retain, undefined, "will-retain", {boolean, false},
  "Retain in will message"}
  ]).

% TODO: 安装getopt
% TODO:命令行对接

-define(PUB_OPTS, ?CONN_SHORT_OPTS ++
                  [{topic_name, $t, "topic", string,
                    "mqtt topic name on which to publish the message(exclusive with topic_id)"},
                   {topic_id, $t, "topic", string,
                    "mqtt topic id on which to publish the message(exclusive with topic_name)"},
                   {qos, $q, "qos", {integer, 0},
                    "qos level of assurance for delivery of an application message"},
                   {retain, $r, "retain", {boolean, false},
                    "retain message or not"}
                  ] ++ ?HELP_OPT ++ ?CONN_LONG_OPTS ++
                                    [{payload, undefined, "payload", string,
                                      "application message that is being published"}
                                    ]).

-define(SUB_OPTS, ?CONN_SHORT_OPTS ++
                  [{topic_name, $t, "topic", string,
                    "mqtt topic name on which to subscribe to(exclusive with topic_id)"},
                   {topic_id, $t, "topic", string,
                    "mqtt topic id on which to subscribe to(exclusive with topic_name)"},
                   {qos, $q, "qos", {integer, 0},
                    "maximum qos level at which the server can send application messages to the client"}
                  ] ++ ?HELP_OPT ++ ?CONN_LONG_OPTS ++ []).

main(["sub" | Argv]) ->
  {ok, {Opts, _Args}} = getopt:parse(?SUB_OPTS, Argv),
  ok = maybe_help(sub, Opts),

  ok = check_exclusive_args(pub, [topic_name, topic_id], Opts),

  main(sub, Opts);

main(["pub" | Argv]) ->
  {ok, {Opts, _Args}} = getopt:parse(?PUB_OPTS, Argv),
  ok = maybe_help(pub, Opts),

  ok = check_required_args(pub, [payload], Opts),
  ok = check_exclusive_args(pub, [topic_name, topic_id], Opts),

  main(pub, Opts);

main(_Argv) ->
  io:format("Usage: ~s pub | sub [--help]~n", [?CMD_NAME]).

main(PubSub, Opts) ->
  application:ensure_all_started(emqttsn),

  NOpts = parse_cmd_opts(Opts),
  {ok, Client} = emqttsn:start_link(NOpts),
  ConnRet = emqtt:connect(Client),
  case ConnRet of
    {ok, Properties} ->
      io:format("Client ~s sent CONNECT~n", [get_value(clientid, NOpts)]),
      case PubSub of
        pub ->
          publish(Client, NOpts),
          disconnect(Client, NOpts);
        sub ->
          subscribe(Client, NOpts),
          receive_loop(Client)
      end;
    {error, Reason} ->
      io:format("Client ~s failed to sent CONNECT due to ~p~n", [get_value(clientid, NOpts), Reason])
  end.

publish(Client, Opts) ->
  Payload = get_value(payload, Opts),
  case emqtt:publish(Client, get_value(topic, Opts), Payload, Opts) of
    {error, Reason} ->
      io:format("Client ~s failed to sent PUBLISH due to ~p~n", [get_value(clientid, Opts), Reason]);
    {error, _PacketId, Reason} ->
      io:format("Client ~s failed to sent PUBLISH due to ~p~n", [get_value(clientid, Opts), Reason]);
    _ ->
      io:format("Client ~s sent PUBLISH (Q~p, R~p, D0, Topic=~s, Payload=...(~p bytes))~n",
                [get_value(clientid, Opts),
                 get_value(qos, Opts),
                 i(get_value(retain, Opts)),
                 get_value(topic, Opts),
                 iolist_size(Payload)])
  end.

subscribe(Client, Opts) ->
  case emqtt:subscribe(Client, get_value(topic, Opts), Opts) of
    {ok, _, [ReasonCode]} when 0 =< ReasonCode andalso ReasonCode =< 2 ->
      io:format("Client ~s subscribed to ~s~n", [get_value(clientid, Opts), get_value(topic, Opts)]);
    {ok, _, [ReasonCode]} ->
      io:format("Client ~s failed to subscribe to ~s due to ~s~n", [get_value(clientid, Opts),
                                                                    get_value(topic, Opts),
                                                                    emqtt:reason_code_name(ReasonCode)]);
    {error, Reason} ->
      io:format("Client ~s failed to send SUBSCRIBE due to ~p~n", [get_value(clientid, Opts), Reason])
  end.


disconnect(Client, Opts) ->
  case emqtt:disconnect(Client) of
    ok ->
      io:format("Client ~s sent DISCONNECT~n", [get_value(clientid, Opts)]);
    {error, Reason} ->
      io:format("Client ~s failed to send DISCONNECT due to ~p~n", [get_value(clientid, Opts), Reason])
  end.

-spec maybe_help(sub_cmd(), dict(atom(), any())) -> no_return().
maybe_help(PubSub, Opts) ->
  case proplists:get_value(help, Opts) of
    true ->
      usage(PubSub),
      halt(0);
    _ -> ok
  end.

-spec usage(sub_cmd()) -> no_return().
usage(PubSub) ->
  Opts = case PubSub of
           pub -> ?PUB_OPTS;
           sub -> ?SUB_OPTS
         end,
  getopt:usage(Opts, ?CMD_NAME ++ " " ++ atom_to_list(PubSub)).

-spec check_required_args(sub_cmd(), [atom()], dict(atom(), any())) -> ok.
check_required_args(PubSub, Keys, Opts) ->
  lists:foreach(fun(Key) ->
    case lists:keyfind(Key, 1, Opts) of
      false ->
        io:format("Error: '~s' required~n", [Key]),
        usage(PubSub),
        halt(1);
      _ -> ok
    end
                end, Keys),
  ok.

-spec check_exclusive_args(sub_cmd(), [atom()], dict(atom(), any())) -> ok.
check_exclusive_args(PubSub, Keys, Opts) ->
  ExistValue = lists:filter(fun(Key) -> lists:keyfind(Key, 1, Opts) =/= false end, Keys),
  case ExistValue of
    [_V] ->
      ok;
    _ ->
      io:format("Error: exclusive group dismatch"),
      usage(PubSub),
      halt(1)
  end.


parse_cmd_opts(Opts) ->
  parse_cmd_opts(Opts, []).

parse_cmd_opts([], Acc) ->
  Acc;
parse_cmd_opts([{host, Host} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{host, Host} | Acc]);
parse_cmd_opts([{port, Port} | Opts], Acc) ->
  parse_cmd_opts(Opts, [{port, Port} | Acc]);
parse_cmd_opts([{iface, Interface} | Opts], Acc) ->
  NAcc = case inet:parse_address(Interface) of
           {ok, IPAddress0} ->
             maybe_append(tcp_opts, {ifaddr, IPAddress0}, Acc);
           _ ->
             case inet:getifaddrs() of
               {ok, IfAddrs} ->
                 case lists:filter(fun({addr, {_, _, _, _}}) -> true;
                   (_) -> false
                                   end, proplists:get_value(Interface, IfAddrs, [])) of
                   [{addr, IPAddress0}] -> maybe_append(tcp_opts, {ifaddr, IPAddress0}, Acc);
                   _ -> Acc
                 end;
               _ -> Acc
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

i(true)  -> 1;
i(false) -> 0.