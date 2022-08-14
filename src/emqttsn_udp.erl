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

-module(emqttsn_udp).

-include("logger.hrl").
-import(emqtt_utils, [store_socket/1, get_socket/0]).

-export([init_port/1, init_port/0, connect/3, send/2, send_anywhere/4, broadcast/3, recv/2]).

%%------------------------------------------------------------------------------
%% @doc Start ans store socket for given port
%% @end
%%------------------------------------------------------------------------------
-spec init_port(inet:port_number()) -> inet:socket() | {error, Reason}.
init_port(LocalPort) ->
  case gen_udp:open(LocalPort) of
    {ok, Socket} ->
      Socket;
    {error, Reason} ->
      {error, Reason}
  end.

-spec init_port() -> inet:socket() | {error, Reason}.
init_port() ->
  init_port(0).

-spec connect(inet:socket(), host(), inet:port_number()) -> inet:socket() | {error, Reason}.
connect(Socket, Address, Port) ->
  case gen_udp:connect(Socket, Address, Port) of
    ok ->
      Socket;
    {error, Reason} ->
      {error, Reason}
  end.

send(Socket, Bin) ->
  gen_udp:send(Socket, Bin).

send_anywhere(Socket, Bin, Address, RemotePort) ->
  gen_udp:send(Socket, {Address, RemotePort}, Bin).

broadcast(Socket, Bin, RemotePort) ->
  case inet:peername(Socket) of
    {ok, {_Address, LocalPort}} ->
      {ok, TmpSocket} = gen_udp:open(LocalPort, [broadcast: true]),
      gen_udp:send(TmpSocket, '255.255.255.255', RemotePort, Bin),
      gen_udp:close(TmpSocket);
    {error, _Reason} -> _
  end.

% parse and verify the length of packet
-spec parse_leading_len(binary(), inet:socket()) -> pos_integer().
parse_leading_len(<<16#01:8/binary>>, Socket) ->
  {ok, Length} = gen_udp:recv(Socket, 2),
  Length;
parse_leading_len(<<Length:8/binary>>, _Socket) ->
  Length.

recv_length(Socket, Client) ->
  case gen_udp:recv(Socket, 1) of
    {ok, 8#1} ->
      LeadingByte = gen_udp:recv(Socket, 2),
      recv_body(Socket, Client, LeadingByte);
    {ok, LeadingByte} ->
      recv_body(Socket, Client, LeadingByte);
    {error, Reason} ->
      ?LOG(warn, "failed to recv length", {reason = Reason}),
      recv_length(Socket, Client)
  end.

recv_body(Socket, Client, Length) ->
  case gen_udp:recv(Socket, Length) of
    {ok, RecvData} -> gen_statem:cast(Client, {recv, RecvData});
    {error, Reason} ->
      ?LOG(warn, "failed to recv body", {reason = Reason}),
      recv_length(Socket, Client)
  end.

recv(Socket, Client) ->
  recv_length(Socket, Client),
  recv(Socket, Client).
