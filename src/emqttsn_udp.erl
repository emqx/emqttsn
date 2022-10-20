%%-------------------------------------------------------------------------
%% Copyright (c) 2021-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
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

%% @doc low-level API working with socket, can be used
%% standalone or with <i>emqttsn_send</i>
%%
%% @see emqttsn_send
-module(emqttsn_udp).

%% @headerfile "emqttsn.hrl"

-include("logger.hrl").
-include("emqttsn.hrl").

-include_lib("eunit/include/eunit.hrl").

-export([init_port/1, init_port/0, connect/3, send/2, send_anywhere/4, broadcast/3,
         recv/1, recv/2]).

%% @doc Start a udp socket at given port
%%
%% @param Port on which to open the socket
%%
%% @returns ok | {error, system_limit | inet:posix()}
%% @end
-spec init_port(inet:port_number()) -> {ok, inet:socket()} | {error, term()}.
init_port(LocalPort) ->
  case gen_udp:open(LocalPort, [binary]) of
    {ok, Socket} ->
      {ok, Socket};
    {error, Reason} when LocalPort =:= 0 ->
      ?LOGP(error, "Open random port failed, reason : ~p", [Reason]),
      {error, Reason};
    {error, _Reason} when LocalPort =/= 0 ->
      ?LOGP(warning, "Open port ~p failed, turn to random port", [LocalPort]),
      init_port()
  end.

%% @doc Start a udp socket at auto pick port
%%
%% @equiv init_port(0)
%%
%% @returns ok | {error, system_limit | inet:posix()}
%% @end
-spec init_port() -> {ok, inet:socket()} | {error, term()}.
init_port() ->
  init_port(0).

%% @doc Connect to gateway
%%
%% Caution: not really <i>connect</i>,
%% only store infomation for udp!
%%
%% @param Socket the socket object
%% @param Host host of gateway to connect
%% @param Port port of gateway to connect
%%
%% @end
-spec connect(inet:socket(), host(), inet:port_number()) -> ok | {error, term()}.
connect(Socket, Host, Port) ->
  case gen_udp:connect(Socket, Host, Port) of
    ok ->
      ok;
    {error, Reason} ->
      {error, Reason}
  end.

%% @doc send binary packet to connected gateway
%%
%% Caution: need to connect first before call it!
%% 
%% @param Socket the socket object
%% @param Bin Binary packet send to gateway
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send(inet:socket(), bitstring()) -> ok | {error, term()}.
send(Socket, Bin) ->
  gen_udp:send(Socket, Bin).

%% @doc send binary packet to any host
%% 
%% @param Socket the socket object
%% @param Bin Binary packet send to gateway
%% @param Host host of target to send packet
%% @param RemotePort port of target to send packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec send_anywhere(inet:socket(), bitstring(), host(), inet:port_number()) ->
                     ok | {error, term()}.
send_anywhere(Socket, Bin, Host, RemotePort) ->
  gen_udp:send(Socket, {Host, RemotePort}, Bin).

%% @doc broadcast binary packet to local network
%% 
%% @param Socket the socket object
%% @param Bin Binary packet send to gateway
%% @param RemotePort port of target to send packet
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec broadcast(inet:socket(), bitstring(), inet:port_number()) ->
                 {ok, inet:socket()} | {error, term()}.
broadcast(Socket, Bin, RemotePort) ->
  case inet:sockname(Socket) of
    {ok, {_Host, LocalPort}} ->
      gen_udp:close(Socket),
      {ok, TmpSocket} = gen_udp:open(LocalPort, [binary, {broadcast, true}]),
      case gen_udp:send(TmpSocket, '255.255.255.255', RemotePort, Bin) of
        ok ->
          gen_udp:close(TmpSocket),
          {ok, NewSocket} = gen_udp:open(LocalPort, [binary, {broadcast, true}]),
          {ok, NewSocket};
        {error, Reason} ->
          {error, Reason}
      end;
    {error, Reason} ->
      ?LOGP(warning, "boardcast failed:~p", [Reason]),
      {error, Reason}
  end.

%% @doc recv and parse incoming packet
%% 
%% @param Socket the socket object
%% @equiv recv(Socket, 2000)
%%
%% @returns ok | {error, not_owner | inet:posix()}
%% @end
-spec recv(inet:socket()) -> {ok, mqttsn_packet()} | udp_receive_timeout.
recv(Socket) ->
  recv(Socket, 2000).

%% @doc recv and parse incoming packet at given timeout
%% 
%% @param Socket the socket object
%% @param Timeout the timeout of recv packet
%%
%% @returns {ok, mqttsn_packet()} | {error, udp_receive_timeout}
%% @end
-spec recv(inet:socket(), pos_integer()) -> {ok, mqttsn_packet()} | {error, udp_receive_timeout}.
recv(Socket, Timeout) ->
  receive
    {udp, Socket, _, _, Bin} ->
      ?LOGP(debug, "receive_response Bin=~p~n", [Bin]),
      case emqttsn_frame:parse(Bin) of
        {ok, Packet} ->
          {ok, Packet};
        {error, Reason} ->
          ?LOGP(warning, "parse packet ~p failed: ~p", [Bin, Reason]),
          recv(Socket, Timeout)
      end;
    Other ->
      ?LOGP(warning, "receive_response() Other message: ~p", [{unexpected_udp_data, Other}]),
      recv(Socket, Timeout)
  after Timeout ->
    udp_receive_timeout
  end.
