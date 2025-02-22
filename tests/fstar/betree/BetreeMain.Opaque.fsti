(** THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS *)
(** [betree_main]: external function declarations *)
module BetreeMain.Opaque
open Primitives
include BetreeMain.Types

#set-options "--z3rlimit 50 --fuel 1 --ifuel 1"

(** [betree_main::betree_utils::load_internal_node]: forward function *)
val betree_utils_load_internal_node_fwd
  : u64 -> state -> result (state & (betree_list_t (u64 & betree_message_t)))

(** [betree_main::betree_utils::store_internal_node]: forward function *)
val betree_utils_store_internal_node_fwd
  :
  u64 -> betree_list_t (u64 & betree_message_t) -> state -> result (state &
    unit)

(** [betree_main::betree_utils::load_leaf_node]: forward function *)
val betree_utils_load_leaf_node_fwd
  : u64 -> state -> result (state & (betree_list_t (u64 & u64)))

(** [betree_main::betree_utils::store_leaf_node]: forward function *)
val betree_utils_store_leaf_node_fwd
  : u64 -> betree_list_t (u64 & u64) -> state -> result (state & unit)

(** [core::option::Option::{0}::unwrap]: forward function *)
val core_option_option_unwrap_fwd
  (t : Type0) : option t -> state -> result (state & t)

