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

-export([init_port/1, init_port/0, connect/3, send/2, send_anywhere/4, broadcast/3,
         recv/3]).

%%------------------------------------------------------------------------------
%% @doc Start ans store socket for given port
%% @end
%%------------------------------------------------------------------------------
-spec init_port(inet:port_number()) -> {ok, inet:socket()} | {error, term()}.
init_port(LocalPort) ->
  case gen_udp:open(LocalPort) of
    {ok, Socket} ->
      {ok, Socket};
    {error, Reason} when LocalPort =:= 0 ->
      ?LOG(error, "Open random port failed", #{reason => Reason}),
      {error, Reason};
    {error, _Reason} when LocalPort =/= 0 ->
      ?EASY_LOG(warning, "Open 1884 failed, turn to random port"),
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

-spec broadcast(inet:socket(), bitstring(), inet:port_number()) -> ok | {error, term()}.
broadcast(Socket, Bin, RemotePort) ->
  case inet:peername(Socket) of
    {ok, {_Address, LocalPort}} ->
      {ok, TmpSocket} = gen_udp:open(LocalPort, [{broadcast, true}]),
      case gen_udp:send(TmpSocket, '255.255.255.255', RemotePort, Bin) of
        ok ->
          gen_udp:close(TmpSocket),
          ok;
        {error, Reason} ->
          {error, Reason}
      end;
    {error, Reason} ->
      ?LOG(warning, "boardcast failed", #{reason => Reason}),
      {error, Reason}
  end.

% parse and verify the length of packet

-spec recv_packet(inet:socket(), emqtsn:client(), config()) -> ok.
recv_packet(Socket, Client, #config{max_size = MaxSize}) ->
  case gen_udp:recv(Socket, MaxSize) of
    {ok, RecvData} ->
      gen_statem:cast(Client, {recv, RecvData});
    {error, Reason} ->
      ?LOG(warning, "failed to recv packet", #{reason => Reason}),
      ok
  end.

-spec recv(inet:socket(), emqtsn:client(), config()) -> no_return().
recv(Socket, Client, Config) ->
  recv_packet(Socket, Client, Config),
  recv(Socket, Client, Config).
