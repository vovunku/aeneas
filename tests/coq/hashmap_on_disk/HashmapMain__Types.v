(** THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS *)
(** [hashmap_main]: type definitions *)
Require Import Primitives.
Import Primitives.
Require Import Coq.ZArith.ZArith.
Local Open Scope Primitives_scope.
Module HashmapMain__Types .

(** [hashmap_main::hashmap::List] *)
Inductive Hashmap_list_t (T : Type) :=
| HashmapListCons : usize -> T -> Hashmap_list_t T -> Hashmap_list_t T
| HashmapListNil : Hashmap_list_t T
.

Arguments HashmapListCons {T} _ _ _  .
Arguments HashmapListNil {T}  .

(** [hashmap_main::hashmap::HashMap] *)
Record Hashmap_hash_map_t (T : Type) :=
mkHashmap_hash_map_t
{
  Hashmap_hash_map_num_entries : usize;
  Hashmap_hash_map_max_load_factor : (usize * usize);
  Hashmap_hash_map_max_load : usize;
  Hashmap_hash_map_slots : vec (Hashmap_list_t T);
}
.

Arguments mkHashmap_hash_map_t {T} _ _ _ _  .
Arguments Hashmap_hash_map_num_entries {T}  .
Arguments Hashmap_hash_map_max_load_factor {T}  .
Arguments Hashmap_hash_map_max_load {T}  .
Arguments Hashmap_hash_map_slots {T}  .

(** [core::num::u32::{9}::MAX] *)
Definition core_num_u32_max_body : result u32 := Return (4294967295 %u32) .
Definition core_num_u32_max_c : u32 := core_num_u32_max_body%global .

(** The state type used in the state-error monad *)
Axiom state : Type.

End HashmapMain__Types .
