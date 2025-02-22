(** THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS *)
(** [hashmap_main]: function definitions *)
module HashmapMain.Funs
open Primitives
include HashmapMain.Types
include HashmapMain.Opaque
include HashmapMain.Clauses

#set-options "--z3rlimit 50 --fuel 1 --ifuel 1"

(** [hashmap_main::hashmap::hash_key]: forward function *)
let hashmap_hash_key_fwd (k : usize) : result usize =
  Return k

(** [hashmap_main::hashmap::HashMap::{0}::allocate_slots]: loop 0: forward function *)
let rec hashmap_hash_map_allocate_slots_loop_fwd
  (t : Type0) (slots : vec (hashmap_list_t t)) (n : usize) :
  Tot (result (vec (hashmap_list_t t)))
  (decreases (hashmap_hash_map_allocate_slots_loop_decreases t slots n))
  =
  if n > 0
  then
    let* slots0 = vec_push_back (hashmap_list_t t) slots HashmapListNil in
    let* n0 = usize_sub n 1 in
    hashmap_hash_map_allocate_slots_loop_fwd t slots0 n0
  else Return slots

(** [hashmap_main::hashmap::HashMap::{0}::allocate_slots]: forward function *)
let hashmap_hash_map_allocate_slots_fwd
  (t : Type0) (slots : vec (hashmap_list_t t)) (n : usize) :
  result (vec (hashmap_list_t t))
  =
  hashmap_hash_map_allocate_slots_loop_fwd t slots n

(** [hashmap_main::hashmap::HashMap::{0}::new_with_capacity]: forward function *)
let hashmap_hash_map_new_with_capacity_fwd
  (t : Type0) (capacity : usize) (max_load_dividend : usize)
  (max_load_divisor : usize) :
  result (hashmap_hash_map_t t)
  =
  let v = vec_new (hashmap_list_t t) in
  let* slots = hashmap_hash_map_allocate_slots_fwd t v capacity in
  let* i = usize_mul capacity max_load_dividend in
  let* i0 = usize_div i max_load_divisor in
  Return
    {
      hashmap_hash_map_num_entries = 0;
      hashmap_hash_map_max_load_factor = (max_load_dividend, max_load_divisor);
      hashmap_hash_map_max_load = i0;
      hashmap_hash_map_slots = slots
    }

(** [hashmap_main::hashmap::HashMap::{0}::new]: forward function *)
let hashmap_hash_map_new_fwd (t : Type0) : result (hashmap_hash_map_t t) =
  hashmap_hash_map_new_with_capacity_fwd t 32 4 5

(** [hashmap_main::hashmap::HashMap::{0}::clear]: loop 0: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let rec hashmap_hash_map_clear_loop_fwd_back
  (t : Type0) (slots : vec (hashmap_list_t t)) (i : usize) :
  Tot (result (vec (hashmap_list_t t)))
  (decreases (hashmap_hash_map_clear_loop_decreases t slots i))
  =
  let i0 = vec_len (hashmap_list_t t) slots in
  if i < i0
  then
    let* i1 = usize_add i 1 in
    let* slots0 = vec_index_mut_back (hashmap_list_t t) slots i HashmapListNil
      in
    hashmap_hash_map_clear_loop_fwd_back t slots0 i1
  else Return slots

(** [hashmap_main::hashmap::HashMap::{0}::clear]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_clear_fwd_back
  (t : Type0) (self : hashmap_hash_map_t t) : result (hashmap_hash_map_t t) =
  let* v = hashmap_hash_map_clear_loop_fwd_back t self.hashmap_hash_map_slots 0
    in
  Return
    { self with hashmap_hash_map_num_entries = 0; hashmap_hash_map_slots = v }

(** [hashmap_main::hashmap::HashMap::{0}::len]: forward function *)
let hashmap_hash_map_len_fwd
  (t : Type0) (self : hashmap_hash_map_t t) : result usize =
  Return self.hashmap_hash_map_num_entries

(** [hashmap_main::hashmap::HashMap::{0}::insert_in_list]: loop 0: forward function *)
let rec hashmap_hash_map_insert_in_list_loop_fwd
  (t : Type0) (key : usize) (value : t) (ls : hashmap_list_t t) :
  Tot (result bool)
  (decreases (hashmap_hash_map_insert_in_list_loop_decreases t key value ls))
  =
  begin match ls with
  | HashmapListCons ckey cvalue tl ->
    if ckey = key
    then Return false
    else hashmap_hash_map_insert_in_list_loop_fwd t key value tl
  | HashmapListNil -> Return true
  end

(** [hashmap_main::hashmap::HashMap::{0}::insert_in_list]: forward function *)
let hashmap_hash_map_insert_in_list_fwd
  (t : Type0) (key : usize) (value : t) (ls : hashmap_list_t t) : result bool =
  hashmap_hash_map_insert_in_list_loop_fwd t key value ls

(** [hashmap_main::hashmap::HashMap::{0}::insert_in_list]: loop 0: backward function 0 *)
let rec hashmap_hash_map_insert_in_list_loop_back
  (t : Type0) (key : usize) (value : t) (ls : hashmap_list_t t) :
  Tot (result (hashmap_list_t t))
  (decreases (hashmap_hash_map_insert_in_list_loop_decreases t key value ls))
  =
  begin match ls with
  | HashmapListCons ckey cvalue tl ->
    if ckey = key
    then Return (HashmapListCons ckey value tl)
    else
      let* tl0 = hashmap_hash_map_insert_in_list_loop_back t key value tl in
      Return (HashmapListCons ckey cvalue tl0)
  | HashmapListNil ->
    let l = HashmapListNil in Return (HashmapListCons key value l)
  end

(** [hashmap_main::hashmap::HashMap::{0}::insert_in_list]: backward function 0 *)
let hashmap_hash_map_insert_in_list_back
  (t : Type0) (key : usize) (value : t) (ls : hashmap_list_t t) :
  result (hashmap_list_t t)
  =
  hashmap_hash_map_insert_in_list_loop_back t key value ls

(** [hashmap_main::hashmap::HashMap::{0}::insert_no_resize]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_insert_no_resize_fwd_back
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) (value : t) :
  result (hashmap_hash_map_t t)
  =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_mut_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
    in
  let* inserted = hashmap_hash_map_insert_in_list_fwd t key value l in
  if inserted
  then
    let* i0 = usize_add self.hashmap_hash_map_num_entries 1 in
    let* l0 = hashmap_hash_map_insert_in_list_back t key value l in
    let* v =
      vec_index_mut_back (hashmap_list_t t) self.hashmap_hash_map_slots
        hash_mod l0 in
    Return
      { self with hashmap_hash_map_num_entries = i0; hashmap_hash_map_slots = v
      }
  else
    let* l0 = hashmap_hash_map_insert_in_list_back t key value l in
    let* v =
      vec_index_mut_back (hashmap_list_t t) self.hashmap_hash_map_slots
        hash_mod l0 in
    Return { self with hashmap_hash_map_slots = v }

(** [core::num::u32::{8}::MAX] *)
let core_num_u32_max_body : result u32 = Return 4294967295
let core_num_u32_max_c : u32 = eval_global core_num_u32_max_body

(** [hashmap_main::hashmap::HashMap::{0}::move_elements_from_list]: loop 0: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let rec hashmap_hash_map_move_elements_from_list_loop_fwd_back
  (t : Type0) (ntable : hashmap_hash_map_t t) (ls : hashmap_list_t t) :
  Tot (result (hashmap_hash_map_t t))
  (decreases (
    hashmap_hash_map_move_elements_from_list_loop_decreases t ntable ls))
  =
  begin match ls with
  | HashmapListCons k v tl ->
    let* ntable0 = hashmap_hash_map_insert_no_resize_fwd_back t ntable k v in
    hashmap_hash_map_move_elements_from_list_loop_fwd_back t ntable0 tl
  | HashmapListNil -> Return ntable
  end

(** [hashmap_main::hashmap::HashMap::{0}::move_elements_from_list]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_move_elements_from_list_fwd_back
  (t : Type0) (ntable : hashmap_hash_map_t t) (ls : hashmap_list_t t) :
  result (hashmap_hash_map_t t)
  =
  hashmap_hash_map_move_elements_from_list_loop_fwd_back t ntable ls

(** [hashmap_main::hashmap::HashMap::{0}::move_elements]: loop 0: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let rec hashmap_hash_map_move_elements_loop_fwd_back
  (t : Type0) (ntable : hashmap_hash_map_t t) (slots : vec (hashmap_list_t t))
  (i : usize) :
  Tot (result ((hashmap_hash_map_t t) & (vec (hashmap_list_t t))))
  (decreases (hashmap_hash_map_move_elements_loop_decreases t ntable slots i))
  =
  let i0 = vec_len (hashmap_list_t t) slots in
  if i < i0
  then
    let* l = vec_index_mut_fwd (hashmap_list_t t) slots i in
    let ls = mem_replace_fwd (hashmap_list_t t) l HashmapListNil in
    let* ntable0 =
      hashmap_hash_map_move_elements_from_list_fwd_back t ntable ls in
    let* i1 = usize_add i 1 in
    let l0 = mem_replace_back (hashmap_list_t t) l HashmapListNil in
    let* slots0 = vec_index_mut_back (hashmap_list_t t) slots i l0 in
    hashmap_hash_map_move_elements_loop_fwd_back t ntable0 slots0 i1
  else Return (ntable, slots)

(** [hashmap_main::hashmap::HashMap::{0}::move_elements]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_move_elements_fwd_back
  (t : Type0) (ntable : hashmap_hash_map_t t) (slots : vec (hashmap_list_t t))
  (i : usize) :
  result ((hashmap_hash_map_t t) & (vec (hashmap_list_t t)))
  =
  hashmap_hash_map_move_elements_loop_fwd_back t ntable slots i

(** [hashmap_main::hashmap::HashMap::{0}::try_resize]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_try_resize_fwd_back
  (t : Type0) (self : hashmap_hash_map_t t) : result (hashmap_hash_map_t t) =
  let* max_usize = scalar_cast U32 Usize core_num_u32_max_c in
  let capacity = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* n1 = usize_div max_usize 2 in
  let (i, i0) = self.hashmap_hash_map_max_load_factor in
  let* i1 = usize_div n1 i in
  if capacity <= i1
  then
    let* i2 = usize_mul capacity 2 in
    let* ntable = hashmap_hash_map_new_with_capacity_fwd t i2 i i0 in
    let* (ntable0, _) =
      hashmap_hash_map_move_elements_fwd_back t ntable
        self.hashmap_hash_map_slots 0 in
    Return
      {
        ntable0
          with
          hashmap_hash_map_num_entries = self.hashmap_hash_map_num_entries;
          hashmap_hash_map_max_load_factor = (i, i0)
      }
  else Return { self with hashmap_hash_map_max_load_factor = (i, i0) }

(** [hashmap_main::hashmap::HashMap::{0}::insert]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let hashmap_hash_map_insert_fwd_back
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) (value : t) :
  result (hashmap_hash_map_t t)
  =
  let* self0 = hashmap_hash_map_insert_no_resize_fwd_back t self key value in
  let* i = hashmap_hash_map_len_fwd t self0 in
  if i > self0.hashmap_hash_map_max_load
  then hashmap_hash_map_try_resize_fwd_back t self0
  else Return self0

(** [hashmap_main::hashmap::HashMap::{0}::contains_key_in_list]: loop 0: forward function *)
let rec hashmap_hash_map_contains_key_in_list_loop_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) :
  Tot (result bool)
  (decreases (hashmap_hash_map_contains_key_in_list_loop_decreases t key ls))
  =
  begin match ls with
  | HashmapListCons ckey x tl ->
    if ckey = key
    then Return true
    else hashmap_hash_map_contains_key_in_list_loop_fwd t key tl
  | HashmapListNil -> Return false
  end

(** [hashmap_main::hashmap::HashMap::{0}::contains_key_in_list]: forward function *)
let hashmap_hash_map_contains_key_in_list_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) : result bool =
  hashmap_hash_map_contains_key_in_list_loop_fwd t key ls

(** [hashmap_main::hashmap::HashMap::{0}::contains_key]: forward function *)
let hashmap_hash_map_contains_key_fwd
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) : result bool =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod in
  hashmap_hash_map_contains_key_in_list_fwd t key l

(** [hashmap_main::hashmap::HashMap::{0}::get_in_list]: loop 0: forward function *)
let rec hashmap_hash_map_get_in_list_loop_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) :
  Tot (result t)
  (decreases (hashmap_hash_map_get_in_list_loop_decreases t key ls))
  =
  begin match ls with
  | HashmapListCons ckey cvalue tl ->
    if ckey = key
    then Return cvalue
    else hashmap_hash_map_get_in_list_loop_fwd t key tl
  | HashmapListNil -> Fail Failure
  end

(** [hashmap_main::hashmap::HashMap::{0}::get_in_list]: forward function *)
let hashmap_hash_map_get_in_list_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) : result t =
  hashmap_hash_map_get_in_list_loop_fwd t key ls

(** [hashmap_main::hashmap::HashMap::{0}::get]: forward function *)
let hashmap_hash_map_get_fwd
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) : result t =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod in
  hashmap_hash_map_get_in_list_fwd t key l

(** [hashmap_main::hashmap::HashMap::{0}::get_mut_in_list]: loop 0: forward function *)
let rec hashmap_hash_map_get_mut_in_list_loop_fwd
  (t : Type0) (ls : hashmap_list_t t) (key : usize) :
  Tot (result t)
  (decreases (hashmap_hash_map_get_mut_in_list_loop_decreases t ls key))
  =
  begin match ls with
  | HashmapListCons ckey cvalue tl ->
    if ckey = key
    then Return cvalue
    else hashmap_hash_map_get_mut_in_list_loop_fwd t tl key
  | HashmapListNil -> Fail Failure
  end

(** [hashmap_main::hashmap::HashMap::{0}::get_mut_in_list]: forward function *)
let hashmap_hash_map_get_mut_in_list_fwd
  (t : Type0) (ls : hashmap_list_t t) (key : usize) : result t =
  hashmap_hash_map_get_mut_in_list_loop_fwd t ls key

(** [hashmap_main::hashmap::HashMap::{0}::get_mut_in_list]: loop 0: backward function 0 *)
let rec hashmap_hash_map_get_mut_in_list_loop_back
  (t : Type0) (ls : hashmap_list_t t) (key : usize) (ret : t) :
  Tot (result (hashmap_list_t t))
  (decreases (hashmap_hash_map_get_mut_in_list_loop_decreases t ls key))
  =
  begin match ls with
  | HashmapListCons ckey cvalue tl ->
    if ckey = key
    then Return (HashmapListCons ckey ret tl)
    else
      let* tl0 = hashmap_hash_map_get_mut_in_list_loop_back t tl key ret in
      Return (HashmapListCons ckey cvalue tl0)
  | HashmapListNil -> Fail Failure
  end

(** [hashmap_main::hashmap::HashMap::{0}::get_mut_in_list]: backward function 0 *)
let hashmap_hash_map_get_mut_in_list_back
  (t : Type0) (ls : hashmap_list_t t) (key : usize) (ret : t) :
  result (hashmap_list_t t)
  =
  hashmap_hash_map_get_mut_in_list_loop_back t ls key ret

(** [hashmap_main::hashmap::HashMap::{0}::get_mut]: forward function *)
let hashmap_hash_map_get_mut_fwd
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) : result t =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_mut_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
    in
  hashmap_hash_map_get_mut_in_list_fwd t l key

(** [hashmap_main::hashmap::HashMap::{0}::get_mut]: backward function 0 *)
let hashmap_hash_map_get_mut_back
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) (ret : t) :
  result (hashmap_hash_map_t t)
  =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_mut_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
    in
  let* l0 = hashmap_hash_map_get_mut_in_list_back t l key ret in
  let* v =
    vec_index_mut_back (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
      l0 in
  Return { self with hashmap_hash_map_slots = v }

(** [hashmap_main::hashmap::HashMap::{0}::remove_from_list]: loop 0: forward function *)
let rec hashmap_hash_map_remove_from_list_loop_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) :
  Tot (result (option t))
  (decreases (hashmap_hash_map_remove_from_list_loop_decreases t key ls))
  =
  begin match ls with
  | HashmapListCons ckey x tl ->
    if ckey = key
    then
      let mv_ls =
        mem_replace_fwd (hashmap_list_t t) (HashmapListCons ckey x tl)
          HashmapListNil in
      begin match mv_ls with
      | HashmapListCons i cvalue tl0 -> Return (Some cvalue)
      | HashmapListNil -> Fail Failure
      end
    else hashmap_hash_map_remove_from_list_loop_fwd t key tl
  | HashmapListNil -> Return None
  end

(** [hashmap_main::hashmap::HashMap::{0}::remove_from_list]: forward function *)
let hashmap_hash_map_remove_from_list_fwd
  (t : Type0) (key : usize) (ls : hashmap_list_t t) : result (option t) =
  hashmap_hash_map_remove_from_list_loop_fwd t key ls

(** [hashmap_main::hashmap::HashMap::{0}::remove_from_list]: loop 0: backward function 1 *)
let rec hashmap_hash_map_remove_from_list_loop_back
  (t : Type0) (key : usize) (ls : hashmap_list_t t) :
  Tot (result (hashmap_list_t t))
  (decreases (hashmap_hash_map_remove_from_list_loop_decreases t key ls))
  =
  begin match ls with
  | HashmapListCons ckey x tl ->
    if ckey = key
    then
      let mv_ls =
        mem_replace_fwd (hashmap_list_t t) (HashmapListCons ckey x tl)
          HashmapListNil in
      begin match mv_ls with
      | HashmapListCons i cvalue tl0 -> Return tl0
      | HashmapListNil -> Fail Failure
      end
    else
      let* tl0 = hashmap_hash_map_remove_from_list_loop_back t key tl in
      Return (HashmapListCons ckey x tl0)
  | HashmapListNil -> Return HashmapListNil
  end

(** [hashmap_main::hashmap::HashMap::{0}::remove_from_list]: backward function 1 *)
let hashmap_hash_map_remove_from_list_back
  (t : Type0) (key : usize) (ls : hashmap_list_t t) :
  result (hashmap_list_t t)
  =
  hashmap_hash_map_remove_from_list_loop_back t key ls

(** [hashmap_main::hashmap::HashMap::{0}::remove]: forward function *)
let hashmap_hash_map_remove_fwd
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) : result (option t) =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_mut_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
    in
  let* x = hashmap_hash_map_remove_from_list_fwd t key l in
  begin match x with
  | None -> Return None
  | Some x0 ->
    let* _ = usize_sub self.hashmap_hash_map_num_entries 1 in Return (Some x0)
  end

(** [hashmap_main::hashmap::HashMap::{0}::remove]: backward function 0 *)
let hashmap_hash_map_remove_back
  (t : Type0) (self : hashmap_hash_map_t t) (key : usize) :
  result (hashmap_hash_map_t t)
  =
  let* hash = hashmap_hash_key_fwd key in
  let i = vec_len (hashmap_list_t t) self.hashmap_hash_map_slots in
  let* hash_mod = usize_rem hash i in
  let* l =
    vec_index_mut_fwd (hashmap_list_t t) self.hashmap_hash_map_slots hash_mod
    in
  let* x = hashmap_hash_map_remove_from_list_fwd t key l in
  begin match x with
  | None ->
    let* l0 = hashmap_hash_map_remove_from_list_back t key l in
    let* v =
      vec_index_mut_back (hashmap_list_t t) self.hashmap_hash_map_slots
        hash_mod l0 in
    Return { self with hashmap_hash_map_slots = v }
  | Some x0 ->
    let* i0 = usize_sub self.hashmap_hash_map_num_entries 1 in
    let* l0 = hashmap_hash_map_remove_from_list_back t key l in
    let* v =
      vec_index_mut_back (hashmap_list_t t) self.hashmap_hash_map_slots
        hash_mod l0 in
    Return
      { self with hashmap_hash_map_num_entries = i0; hashmap_hash_map_slots = v
      }
  end

(** [hashmap_main::hashmap::test1]: forward function *)
let hashmap_test1_fwd : result unit =
  let* hm = hashmap_hash_map_new_fwd u64 in
  let* hm0 = hashmap_hash_map_insert_fwd_back u64 hm 0 42 in
  let* hm1 = hashmap_hash_map_insert_fwd_back u64 hm0 128 18 in
  let* hm2 = hashmap_hash_map_insert_fwd_back u64 hm1 1024 138 in
  let* hm3 = hashmap_hash_map_insert_fwd_back u64 hm2 1056 256 in
  let* i = hashmap_hash_map_get_fwd u64 hm3 128 in
  if not (i = 18)
  then Fail Failure
  else
    let* hm4 = hashmap_hash_map_get_mut_back u64 hm3 1024 56 in
    let* i0 = hashmap_hash_map_get_fwd u64 hm4 1024 in
    if not (i0 = 56)
    then Fail Failure
    else
      let* x = hashmap_hash_map_remove_fwd u64 hm4 1024 in
      begin match x with
      | None -> Fail Failure
      | Some x0 ->
        if not (x0 = 56)
        then Fail Failure
        else
          let* hm5 = hashmap_hash_map_remove_back u64 hm4 1024 in
          let* i1 = hashmap_hash_map_get_fwd u64 hm5 0 in
          if not (i1 = 42)
          then Fail Failure
          else
            let* i2 = hashmap_hash_map_get_fwd u64 hm5 128 in
            if not (i2 = 18)
            then Fail Failure
            else
              let* i3 = hashmap_hash_map_get_fwd u64 hm5 1056 in
              if not (i3 = 256) then Fail Failure else Return ()
      end

(** Unit test for [hashmap_main::hashmap::test1] *)
let _ = assert_norm (hashmap_test1_fwd = Return ())

(** [hashmap_main::insert_on_disk]: forward function *)
let insert_on_disk_fwd
  (key : usize) (value : u64) (st : state) : result (state & unit) =
  let* (st0, hm) = hashmap_utils_deserialize_fwd st in
  let* hm0 = hashmap_hash_map_insert_fwd_back u64 hm key value in
  let* (st1, _) = hashmap_utils_serialize_fwd hm0 st0 in
  Return (st1, ())

(** [hashmap_main::main]: forward function *)
let main_fwd : result unit =
  Return ()

(** Unit test for [hashmap_main::main] *)
let _ = assert_norm (main_fwd = Return ())

