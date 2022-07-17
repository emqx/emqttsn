-record(msg_uid, {
  topic_id :: topic_id(),
  index :: pos_integer()
}).

-record(msg_store, {
  uid :: #msg_uid{},
  timestamp :: Timestamp :: timestamp(),
  data :: bitstring()
}).

-record(msg_collect, {
  topic_id :: topic_id(),
  timestamp :: Timestamp :: timestamp(),
  data :: bitstring()
}).

%%--------------------------------------------------------------------
%% gateway address manager
%%--------------------------------------------------------------------
-define(MANUAL, 2).
-define(BROADCAST, 1).
-define(PARAPHRASE, 0).
-type gw_src() :: ?MANUAL | ?BROADCAST | ?PARAPHRASE.

-record(gw_info,
{
  id :: bitstring(),
  host :: host(),
  port :: inet:port_number(),
  from :: gw_src()
}).

-record(gw_collect, {
  id :: bitstring(),
  host :: host(),
  port :: inet:port_number()
}).

%%--------------------------------------------------------------------
%% state machine
%%--------------------------------------------------------------------
-record(state,
{waiting_data :: tuple(),
 next_packet_id = 0 :: integer(),
 topic_id_name = #{} :: dict(topic_id(), bitstring()),
 topic_name_id = #{} :: dict(bitstring(), topic_id()),
 topic_id_use_qos = #{} :: dict(topic_id(), qos()),
 active_gw = #gw_collect{} :: gw_collect(),
 gw_failed_cycle = 0 :: pos_integer()}).