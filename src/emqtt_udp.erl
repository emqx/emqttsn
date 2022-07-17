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

-module(emqtt_udp).

-import(emqtt_utils, [store_socket/1, get_socket/0]).

-export([init_con/2, init_con/3, send/1, send_anywhere/3, recv/2,
         broadcast/2, broadcast/3]).

%%------------------------------------------------------------------------------
%% @doc Start ans store socket for given port
%% @end
%%------------------------------------------------------------------------------
-spec init_local(inet:port_number()) -> ok | {error, Reason}.
init_local(LocalPort) ->
  case gen_udp:open(LocalPort) of
    {ok, Socket} ->
      store_socket(Socket),
      ok;
    {error, Reason} ->
      {error, Reason}
  end.

-spec init_con(Address, RemotePort) -> ok | {error, Reason}
                when Address :: inet:socket_address() | inet:hostname(),
                RemotePort :: inet:port_number(),
                Reason :: inet:posix().
init_con(Address, RemotePort) ->
  init_con(Address, RemotePort, 0).

-spec init_con(Address, RemotePort, LocalPort) -> ok | {error, Reason}
                when Address :: inet:socket_address() | inet:hostname(),
                RemotePort :: inet:port_number(),
                LocalPort :: inet:port_number(),
                Reason :: inet:posix().
init_con(Address, RemotePort, LocalPort) ->
  case gen_udp:open(LocalPort) of
    {ok, Socket} ->
      connect(Socket, Address, RemotePort);
    {error, Reason} ->
      {error, Reason}
  end.

connect(Socket, Address, Port) ->
  case gen_udp:connect(Socket, Address, Port) of
    ok ->
      store_socket(Socket),
      ok;
    {error, Reason} ->
      {error, {connect_failed, Reason}}
  end.

send(Bin) ->
  Socket = get_socket(),
  gen_udp:send(Socket, Bin).

send_anywhere(Bin, Address, RemotePort, LocalPort) ->
  Socket = get_socket(),
  if Socket == none
    -> init_local(LocalPort)
  end,
  gen_udp:send(Socket, {Address, RemotePort}, Bin).

send_anywhere(Bin, Address, RemotePort) ->
  send_anywhere(Bin, Address, RemotePort, 0).

broadcast(Bin, RemotePort, LocalPort) ->
  {ok, socket} = gen_udp:open(LocalPort, [broadcast: true]),
  gen_udp:send(socket, '255.255.255.255', RemotePort, Bin).

broadcast(Bin, RemotePort) ->
  broadcast(Bin, RemotePort, 0).

recv(Client, Length) ->
  Socket = get_socket(),
  case gen_udp:recv(Socket, Length) of
    {ok, RecvData} ->
      gen_statem:cast(Client, {recv, RecvData}),
      recv(Client, Length);
    {error, Reason} ->
      {error, {recv_failed, Reason}}
  end.
