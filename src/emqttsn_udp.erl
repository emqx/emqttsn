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
-include("config.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([init_port/1, init_port/0, connect/3, send/2, send_anywhere/4, broadcast/3,
         recv/3]).

%%------------------------------------------------------------------------------
%% @doc Start ans store socket for given port
%% @end
%%------------------------------------------------------------------------------
-spec init_port(inet:port_number()) -> {ok, inet:socket()} | {error, term()}.
init_port(LocalPort) ->
  case gen_udp:open(LocalPort, [binary]) of
    {ok, Socket} ->
      {ok, Socket};
    {error, Reason} when LocalPort =:= 0 ->
      ?LOG(error, "Open random port failed", #{reason => Reason}),
      {error, Reason};
    {error, _Reason} when LocalPort =/= 0 ->
      ?LOG(warning, "Open port ~p failed, turn to random port", [LocalPort]),
      init_port()
  end.

-spec init_port() -> inet:socket() | {error, term()}.
init_port() ->
  init_port(0).

-spec connect(inet:socket(), host(), inet:port_number()) ->
               inet:socket() | {error, term()}.
connect(Socket, Address, Port) ->
  case gen_udp:connect(Socket, Address, Port) of
    ok ->
      Socket;
    {error, Reason} ->
      {error, Reason}
  end.

-spec send(inet:socket(), bitstring()) -> ok | {error, term()}.
send(Socket, Bin) ->
  gen_udp:send(Socket, Bin).

-spec send_anywhere(inet:socket(), bitstring(), host(), inet:port_number()) ->
                     ok | {error, term()}.
send_anywhere(Socket, Bin, Address, RemotePort) ->
  gen_udp:send(Socket, {Address, RemotePort}, Bin).

-spec broadcast(inet:socket(), bitstring(), inet:port_number()) -> {ok, inet:socket()} | {error, term()}.
broadcast(Socket, Bin, RemotePort) ->
  case inet:sockname(Socket) of
    {ok, {_Address, LocalPort}} ->
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
      ?LOG_WARNING("boardcast failed:~p", [Reason]),
      {error, Reason}
  end.

% parse and verify the length of packet

-spec recv_packet(inet:socket(), pid()) -> ok.
recv_packet(Socket, StateM) ->
  receive
    {udp, Socket, IP, InPortNo, Bin} -> 
      gen_statem:cast(StateM, {recv, {IP, InPortNo, Bin}}),
      ok;
    _ ->
      ok
  end.

-spec recv(inet:socket(), pid(), config()) -> no_return().
recv(Socket, StateM, Config) ->
  recv_packet(Socket, StateM),
  recv(Socket, StateM, Config).
