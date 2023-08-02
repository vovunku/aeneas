-- THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS
-- [betree_main]: function definitions
import Base
import BetreeMain.Types
import BetreeMain.FunsExternal
open Primitives

namespace betree_main

/- [betree_main::betree::load_internal_node]: forward function -/
def betree.load_internal_node
  (id : U64) (st : State) :
  Result (State × (betree.List (U64 × betree.Message)))
  :=
  betree_utils.load_internal_node id st

/- [betree_main::betree::store_internal_node]: forward function -/
def betree.store_internal_node
  (id : U64) (content : betree.List (U64 × betree.Message)) (st : State) :
  Result (State × Unit)
  :=
  do
    let (st0, _) ← betree_utils.store_internal_node id content st
    Result.ret (st0, ())

/- [betree_main::betree::load_leaf_node]: forward function -/
def betree.load_leaf_node
  (id : U64) (st : State) : Result (State × (betree.List (U64 × U64))) :=
  betree_utils.load_leaf_node id st

/- [betree_main::betree::store_leaf_node]: forward function -/
def betree.store_leaf_node
  (id : U64) (content : betree.List (U64 × U64)) (st : State) :
  Result (State × Unit)
  :=
  do
    let (st0, _) ← betree_utils.store_leaf_node id content st
    Result.ret (st0, ())

/- [betree_main::betree::fresh_node_id]: forward function -/
def betree.fresh_node_id (counter : U64) : Result U64 :=
  do
    let _ ← counter + (U64.ofInt 1)
    Result.ret counter

/- [betree_main::betree::fresh_node_id]: backward function 0 -/
def betree.fresh_node_id_back (counter : U64) : Result U64 :=
  counter + (U64.ofInt 1)

/- [betree_main::betree::NodeIdCounter::{0}::new]: forward function -/
def betree.NodeIdCounter.new : Result betree.NodeIdCounter :=
  Result.ret { next_node_id := (U64.ofInt 0) }

/- [betree_main::betree::NodeIdCounter::{0}::fresh_id]: forward function -/
def betree.NodeIdCounter.fresh_id (self : betree.NodeIdCounter) : Result U64 :=
  do
    let _ ← self.next_node_id + (U64.ofInt 1)
    Result.ret self.next_node_id

/- [betree_main::betree::NodeIdCounter::{0}::fresh_id]: backward function 0 -/
def betree.NodeIdCounter.fresh_id_back
  (self : betree.NodeIdCounter) : Result betree.NodeIdCounter :=
  do
    let i ← self.next_node_id + (U64.ofInt 1)
    Result.ret { next_node_id := i }

/- [core::num::u64::{10}::MAX] -/
def core_num_u64_max_body : Result U64 :=
  Result.ret (U64.ofInt 18446744073709551615)
def core_num_u64_max_c : U64 := eval_global core_num_u64_max_body (by simp)

/- [betree_main::betree::upsert_update]: forward function -/
def betree.upsert_update
  (prev : Option U64) (st : betree.UpsertFunState) : Result U64 :=
  match prev with
  | Option.none =>
    match st with
    | betree.UpsertFunState.Add v => Result.ret v
    | betree.UpsertFunState.Sub i => Result.ret (U64.ofInt 0)
  | Option.some prev0 =>
    match st with
    | betree.UpsertFunState.Add v =>
      do
        let margin ← core_num_u64_max_c - prev0
        if margin >= v
        then prev0 + v
        else Result.ret core_num_u64_max_c
    | betree.UpsertFunState.Sub v =>
      if prev0 >= v
      then prev0 - v
      else Result.ret (U64.ofInt 0)

/- [betree_main::betree::List::{1}::len]: forward function -/
divergent def betree.List.len (T : Type) (self : betree.List T) : Result U64 :=
  match self with
  | betree.List.Cons t tl =>
    do
      let i ← betree.List.len T tl
      (U64.ofInt 1) + i
  | betree.List.Nil => Result.ret (U64.ofInt 0)

/- [betree_main::betree::List::{1}::split_at]: forward function -/
divergent def betree.List.split_at
  (T : Type) (self : betree.List T) (n : U64) :
  Result ((betree.List T) × (betree.List T))
  :=
  if n = (U64.ofInt 0)
  then Result.ret (betree.List.Nil, self)
  else
    match self with
    | betree.List.Cons hd tl =>
      do
        let i ← n - (U64.ofInt 1)
        let p ← betree.List.split_at T tl i
        let (ls0, ls1) := p
        let l := ls0
        Result.ret (betree.List.Cons hd l, ls1)
    | betree.List.Nil => Result.fail Error.panic

/- [betree_main::betree::List::{1}::push_front]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
def betree.List.push_front
  (T : Type) (self : betree.List T) (x : T) : Result (betree.List T) :=
  let tl := mem.replace (betree.List T) self betree.List.Nil
  let l := tl
  Result.ret (betree.List.Cons x l)

/- [betree_main::betree::List::{1}::pop_front]: forward function -/
def betree.List.pop_front (T : Type) (self : betree.List T) : Result T :=
  let ls := mem.replace (betree.List T) self betree.List.Nil
  match ls with
  | betree.List.Cons x tl => Result.ret x
  | betree.List.Nil => Result.fail Error.panic

/- [betree_main::betree::List::{1}::pop_front]: backward function 0 -/
def betree.List.pop_front_back
  (T : Type) (self : betree.List T) : Result (betree.List T) :=
  let ls := mem.replace (betree.List T) self betree.List.Nil
  match ls with
  | betree.List.Cons x tl => Result.ret tl
  | betree.List.Nil => Result.fail Error.panic

/- [betree_main::betree::List::{1}::hd]: forward function -/
def betree.List.hd (T : Type) (self : betree.List T) : Result T :=
  match self with
  | betree.List.Cons hd l => Result.ret hd
  | betree.List.Nil => Result.fail Error.panic

/- [betree_main::betree::List::{2}::head_has_key]: forward function -/
def betree.List.head_has_key
  (T : Type) (self : betree.List (U64 × T)) (key : U64) : Result Bool :=
  match self with
  | betree.List.Cons hd l => let (i, _) := hd
                             Result.ret (i = key)
  | betree.List.Nil => Result.ret false

/- [betree_main::betree::List::{2}::partition_at_pivot]: forward function -/
divergent def betree.List.partition_at_pivot
  (T : Type) (self : betree.List (U64 × T)) (pivot : U64) :
  Result ((betree.List (U64 × T)) × (betree.List (U64 × T)))
  :=
  match self with
  | betree.List.Cons hd tl =>
    let (i, t) := hd
    if i >= pivot
    then Result.ret (betree.List.Nil, betree.List.Cons (i, t) tl)
    else
      do
        let p ← betree.List.partition_at_pivot T tl pivot
        let (ls0, ls1) := p
        let l := ls0
        Result.ret (betree.List.Cons (i, t) l, ls1)
  | betree.List.Nil => Result.ret (betree.List.Nil, betree.List.Nil)

/- [betree_main::betree::Leaf::{3}::split]: forward function -/
def betree.Leaf.split
  (self : betree.Leaf) (content : betree.List (U64 × U64))
  (params : betree.Params) (node_id_cnt : betree.NodeIdCounter) (st : State) :
  Result (State × betree.Internal)
  :=
  do
    let p ← betree.List.split_at (U64 × U64) content params.split_size
    let (content0, content1) := p
    let p0 ← betree.List.hd (U64 × U64) content1
    let (pivot, _) := p0
    let id0 ← betree.NodeIdCounter.fresh_id node_id_cnt
    let node_id_cnt0 ← betree.NodeIdCounter.fresh_id_back node_id_cnt
    let id1 ← betree.NodeIdCounter.fresh_id node_id_cnt0
    let (st0, _) ← betree.store_leaf_node id0 content0 st
    let (st1, _) ← betree.store_leaf_node id1 content1 st0
    let n := betree.Node.Leaf { id := id0, size := params.split_size }
    let n0 := betree.Node.Leaf { id := id1, size := params.split_size }
    Result.ret (st1, betree.Internal.mk self.id pivot n n0)

/- [betree_main::betree::Leaf::{3}::split]: backward function 2 -/
def betree.Leaf.split_back
  (self : betree.Leaf) (content : betree.List (U64 × U64))
  (params : betree.Params) (node_id_cnt : betree.NodeIdCounter) (st : State) :
  Result betree.NodeIdCounter
  :=
  do
    let p ← betree.List.split_at (U64 × U64) content params.split_size
    let (content0, content1) := p
    let _ ← betree.List.hd (U64 × U64) content1
    let id0 ← betree.NodeIdCounter.fresh_id node_id_cnt
    let node_id_cnt0 ← betree.NodeIdCounter.fresh_id_back node_id_cnt
    let id1 ← betree.NodeIdCounter.fresh_id node_id_cnt0
    let (st0, _) ← betree.store_leaf_node id0 content0 st
    let _ ← betree.store_leaf_node id1 content1 st0
    betree.NodeIdCounter.fresh_id_back node_id_cnt0

/- [betree_main::betree::Node::{5}::lookup_in_bindings]: forward function -/
divergent def betree.Node.lookup_in_bindings
  (key : U64) (bindings : betree.List (U64 × U64)) : Result (Option U64) :=
  match bindings with
  | betree.List.Cons hd tl =>
    let (i, i0) := hd
    if i = key
    then Result.ret (Option.some i0)
    else
      if i > key
      then Result.ret Option.none
      else betree.Node.lookup_in_bindings key tl
  | betree.List.Nil => Result.ret Option.none

/- [betree_main::betree::Node::{5}::lookup_first_message_for_key]: forward function -/
divergent def betree.Node.lookup_first_message_for_key
  (key : U64) (msgs : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match msgs with
  | betree.List.Cons x next_msgs =>
    let (i, m) := x
    if i >= key
    then Result.ret (betree.List.Cons (i, m) next_msgs)
    else betree.Node.lookup_first_message_for_key key next_msgs
  | betree.List.Nil => Result.ret betree.List.Nil

/- [betree_main::betree::Node::{5}::lookup_first_message_for_key]: backward function 0 -/
divergent def betree.Node.lookup_first_message_for_key_back
  (key : U64) (msgs : betree.List (U64 × betree.Message))
  (ret0 : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match msgs with
  | betree.List.Cons x next_msgs =>
    let (i, m) := x
    if i >= key
    then Result.ret ret0
    else
      do
        let next_msgs0 ←
          betree.Node.lookup_first_message_for_key_back key next_msgs ret0
        Result.ret (betree.List.Cons (i, m) next_msgs0)
  | betree.List.Nil => Result.ret ret0

/- [betree_main::betree::Node::{5}::apply_upserts]: forward function -/
divergent def betree.Node.apply_upserts
  (msgs : betree.List (U64 × betree.Message)) (prev : Option U64) (key : U64)
  (st : State) :
  Result (State × U64)
  :=
  do
    let b ← betree.List.head_has_key betree.Message msgs key
    if b
    then
      do
        let msg ← betree.List.pop_front (U64 × betree.Message) msgs
        let (_, m) := msg
        match m with
        | betree.Message.Insert i => Result.fail Error.panic
        | betree.Message.Delete => Result.fail Error.panic
        | betree.Message.Upsert s =>
          do
            let v ← betree.upsert_update prev s
            let msgs0 ←
              betree.List.pop_front_back (U64 × betree.Message) msgs
            betree.Node.apply_upserts msgs0 (Option.some v) key st
    else
      do
        let (st0, v) ← core.option.Option.unwrap U64 prev st
        let _ ←
          betree.List.push_front (U64 × betree.Message) msgs (key,
            betree.Message.Insert v)
        Result.ret (st0, v)

/- [betree_main::betree::Node::{5}::apply_upserts]: backward function 0 -/
divergent def betree.Node.apply_upserts_back
  (msgs : betree.List (U64 × betree.Message)) (prev : Option U64) (key : U64)
  (st : State) :
  Result (betree.List (U64 × betree.Message))
  :=
  do
    let b ← betree.List.head_has_key betree.Message msgs key
    if b
    then
      do
        let msg ← betree.List.pop_front (U64 × betree.Message) msgs
        let (_, m) := msg
        match m with
        | betree.Message.Insert i => Result.fail Error.panic
        | betree.Message.Delete => Result.fail Error.panic
        | betree.Message.Upsert s =>
          do
            let v ← betree.upsert_update prev s
            let msgs0 ←
              betree.List.pop_front_back (U64 × betree.Message) msgs
            betree.Node.apply_upserts_back msgs0 (Option.some v) key st
    else
      do
        let (_, v) ← core.option.Option.unwrap U64 prev st
        betree.List.push_front (U64 × betree.Message) msgs (key,
          betree.Message.Insert v)

/- [betree_main::betree::Node::{5}::lookup]: forward function -/
mutual divergent def betree.Node.lookup
  (self : betree.Node) (key : U64) (st : State) :
  Result (State × (Option U64))
  :=
  match self with
  | betree.Node.Internal node =>
    do
      let ⟨ i, i0, n, n0 ⟩ := node
      let (st0, msgs) ← betree.load_internal_node i st
      let pending ← betree.Node.lookup_first_message_for_key key msgs
      match pending with
      | betree.List.Cons p l =>
        let (k, msg) := p
        if k != key
        then
          do
            let (st1, opt) ←
              betree.Internal.lookup_in_children (betree.Internal.mk i i0 n n0)
                key st0
            let _ ←
              betree.Node.lookup_first_message_for_key_back key msgs
                (betree.List.Cons (k, msg) l)
            Result.ret (st1, opt)
        else
          match msg with
          | betree.Message.Insert v =>
            do
              let _ ←
                betree.Node.lookup_first_message_for_key_back key msgs
                  (betree.List.Cons (k, betree.Message.Insert v) l)
              Result.ret (st0, Option.some v)
          | betree.Message.Delete =>
            do
              let _ ←
                betree.Node.lookup_first_message_for_key_back key msgs
                  (betree.List.Cons (k, betree.Message.Delete) l)
              Result.ret (st0, Option.none)
          | betree.Message.Upsert ufs =>
            do
              let (st1, v) ←
                betree.Internal.lookup_in_children (betree.Internal.mk i i0 n
                  n0) key st0
              let (st2, v0) ←
                betree.Node.apply_upserts (betree.List.Cons (k,
                  betree.Message.Upsert ufs) l) v key st1
              let node0 ←
                betree.Internal.lookup_in_children_back (betree.Internal.mk i
                  i0 n n0) key st0
              let ⟨ i1, _, _, _ ⟩ := node0
              let pending0 ←
                betree.Node.apply_upserts_back (betree.List.Cons (k,
                  betree.Message.Upsert ufs) l) v key st1
              let msgs0 ←
                betree.Node.lookup_first_message_for_key_back key msgs pending0
              let (st3, _) ← betree.store_internal_node i1 msgs0 st2
              Result.ret (st3, Option.some v0)
      | betree.List.Nil =>
        do
          let (st1, opt) ←
            betree.Internal.lookup_in_children (betree.Internal.mk i i0 n n0)
              key st0
          let _ ←
            betree.Node.lookup_first_message_for_key_back key msgs
              betree.List.Nil
          Result.ret (st1, opt)
  | betree.Node.Leaf node =>
    do
      let (st0, bindings) ← betree.load_leaf_node node.id st
      let opt ← betree.Node.lookup_in_bindings key bindings
      Result.ret (st0, opt)

/- [betree_main::betree::Node::{5}::lookup]: backward function 0 -/
divergent def betree.Node.lookup_back
  (self : betree.Node) (key : U64) (st : State) : Result betree.Node :=
  match self with
  | betree.Node.Internal node =>
    do
      let ⟨ i, i0, n, n0 ⟩ := node
      let (st0, msgs) ← betree.load_internal_node i st
      let pending ← betree.Node.lookup_first_message_for_key key msgs
      match pending with
      | betree.List.Cons p l =>
        let (k, msg) := p
        if k != key
        then
          do
            let _ ←
              betree.Node.lookup_first_message_for_key_back key msgs
                (betree.List.Cons (k, msg) l)
            let node0 ←
              betree.Internal.lookup_in_children_back (betree.Internal.mk i i0
                n n0) key st0
            Result.ret (betree.Node.Internal node0)
        else
          match msg with
          | betree.Message.Insert v =>
            do
              let _ ←
                betree.Node.lookup_first_message_for_key_back key msgs
                  (betree.List.Cons (k, betree.Message.Insert v) l)
              Result.ret (betree.Node.Internal (betree.Internal.mk i i0 n n0))
          | betree.Message.Delete =>
            do
              let _ ←
                betree.Node.lookup_first_message_for_key_back key msgs
                  (betree.List.Cons (k, betree.Message.Delete) l)
              Result.ret (betree.Node.Internal (betree.Internal.mk i i0 n n0))
          | betree.Message.Upsert ufs =>
            do
              let (st1, v) ←
                betree.Internal.lookup_in_children (betree.Internal.mk i i0 n
                  n0) key st0
              let (st2, _) ←
                betree.Node.apply_upserts (betree.List.Cons (k,
                  betree.Message.Upsert ufs) l) v key st1
              let node0 ←
                betree.Internal.lookup_in_children_back (betree.Internal.mk i
                  i0 n n0) key st0
              let ⟨ i1, i2, n1, n2 ⟩ := node0
              let pending0 ←
                betree.Node.apply_upserts_back (betree.List.Cons (k,
                  betree.Message.Upsert ufs) l) v key st1
              let msgs0 ←
                betree.Node.lookup_first_message_for_key_back key msgs pending0
              let _ ← betree.store_internal_node i1 msgs0 st2
              Result.ret (betree.Node.Internal (betree.Internal.mk i1 i2 n1
                n2))
      | betree.List.Nil =>
        do
          let _ ←
            betree.Node.lookup_first_message_for_key_back key msgs
              betree.List.Nil
          let node0 ←
            betree.Internal.lookup_in_children_back (betree.Internal.mk i i0 n
              n0) key st0
          Result.ret (betree.Node.Internal node0)
  | betree.Node.Leaf node =>
    do
      let (_, bindings) ← betree.load_leaf_node node.id st
      let _ ← betree.Node.lookup_in_bindings key bindings
      Result.ret (betree.Node.Leaf node)

/- [betree_main::betree::Internal::{4}::lookup_in_children]: forward function -/
divergent def betree.Internal.lookup_in_children
  (self : betree.Internal) (key : U64) (st : State) :
  Result (State × (Option U64))
  :=
  let ⟨ _, i, n, n0 ⟩ := self
  if key < i
  then betree.Node.lookup n key st
  else betree.Node.lookup n0 key st

/- [betree_main::betree::Internal::{4}::lookup_in_children]: backward function 0 -/
divergent def betree.Internal.lookup_in_children_back
  (self : betree.Internal) (key : U64) (st : State) : Result betree.Internal :=
  let ⟨ i, i0, n, n0 ⟩ := self
  if key < i0
  then
    do
      let n1 ← betree.Node.lookup_back n key st
      Result.ret (betree.Internal.mk i i0 n1 n0)
  else
    do
      let n1 ← betree.Node.lookup_back n0 key st
      Result.ret (betree.Internal.mk i i0 n n1)

end

/- [betree_main::betree::Node::{5}::lookup_mut_in_bindings]: forward function -/
divergent def betree.Node.lookup_mut_in_bindings
  (key : U64) (bindings : betree.List (U64 × U64)) :
  Result (betree.List (U64 × U64))
  :=
  match bindings with
  | betree.List.Cons hd tl =>
    let (i, i0) := hd
    if i >= key
    then Result.ret (betree.List.Cons (i, i0) tl)
    else betree.Node.lookup_mut_in_bindings key tl
  | betree.List.Nil => Result.ret betree.List.Nil

/- [betree_main::betree::Node::{5}::lookup_mut_in_bindings]: backward function 0 -/
divergent def betree.Node.lookup_mut_in_bindings_back
  (key : U64) (bindings : betree.List (U64 × U64))
  (ret0 : betree.List (U64 × U64)) :
  Result (betree.List (U64 × U64))
  :=
  match bindings with
  | betree.List.Cons hd tl =>
    let (i, i0) := hd
    if i >= key
    then Result.ret ret0
    else
      do
        let tl0 ← betree.Node.lookup_mut_in_bindings_back key tl ret0
        Result.ret (betree.List.Cons (i, i0) tl0)
  | betree.List.Nil => Result.ret ret0

/- [betree_main::betree::Node::{5}::apply_to_leaf]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
def betree.Node.apply_to_leaf
  (bindings : betree.List (U64 × U64)) (key : U64) (new_msg : betree.Message)
  :
  Result (betree.List (U64 × U64))
  :=
  do
    let bindings0 ← betree.Node.lookup_mut_in_bindings key bindings
    let b ← betree.List.head_has_key U64 bindings0 key
    if b
    then
      do
        let hd ← betree.List.pop_front (U64 × U64) bindings0
        match new_msg with
        | betree.Message.Insert v =>
          do
            let bindings1 ← betree.List.pop_front_back (U64 × U64) bindings0
            let bindings2 ←
              betree.List.push_front (U64 × U64) bindings1 (key, v)
            betree.Node.lookup_mut_in_bindings_back key bindings bindings2
        | betree.Message.Delete =>
          do
            let bindings1 ← betree.List.pop_front_back (U64 × U64) bindings0
            betree.Node.lookup_mut_in_bindings_back key bindings bindings1
        | betree.Message.Upsert s =>
          do
            let (_, i) := hd
            let v ← betree.upsert_update (Option.some i) s
            let bindings1 ← betree.List.pop_front_back (U64 × U64) bindings0
            let bindings2 ←
              betree.List.push_front (U64 × U64) bindings1 (key, v)
            betree.Node.lookup_mut_in_bindings_back key bindings bindings2
    else
      match new_msg with
      | betree.Message.Insert v =>
        do
          let bindings1 ←
            betree.List.push_front (U64 × U64) bindings0 (key, v)
          betree.Node.lookup_mut_in_bindings_back key bindings bindings1
      | betree.Message.Delete =>
        betree.Node.lookup_mut_in_bindings_back key bindings bindings0
      | betree.Message.Upsert s =>
        do
          let v ← betree.upsert_update Option.none s
          let bindings1 ←
            betree.List.push_front (U64 × U64) bindings0 (key, v)
          betree.Node.lookup_mut_in_bindings_back key bindings bindings1

/- [betree_main::betree::Node::{5}::apply_messages_to_leaf]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
divergent def betree.Node.apply_messages_to_leaf
  (bindings : betree.List (U64 × U64))
  (new_msgs : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × U64))
  :=
  match new_msgs with
  | betree.List.Cons new_msg new_msgs_tl =>
    do
      let (i, m) := new_msg
      let bindings0 ← betree.Node.apply_to_leaf bindings i m
      betree.Node.apply_messages_to_leaf bindings0 new_msgs_tl
  | betree.List.Nil => Result.ret bindings

/- [betree_main::betree::Node::{5}::filter_messages_for_key]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
divergent def betree.Node.filter_messages_for_key
  (key : U64) (msgs : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match msgs with
  | betree.List.Cons p l =>
    let (k, m) := p
    if k = key
    then
      do
        let msgs0 ←
          betree.List.pop_front_back (U64 × betree.Message) (betree.List.Cons
            (k, m) l)
        betree.Node.filter_messages_for_key key msgs0
    else Result.ret (betree.List.Cons (k, m) l)
  | betree.List.Nil => Result.ret betree.List.Nil

/- [betree_main::betree::Node::{5}::lookup_first_message_after_key]: forward function -/
divergent def betree.Node.lookup_first_message_after_key
  (key : U64) (msgs : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match msgs with
  | betree.List.Cons p next_msgs =>
    let (k, m) := p
    if k = key
    then betree.Node.lookup_first_message_after_key key next_msgs
    else Result.ret (betree.List.Cons (k, m) next_msgs)
  | betree.List.Nil => Result.ret betree.List.Nil

/- [betree_main::betree::Node::{5}::lookup_first_message_after_key]: backward function 0 -/
divergent def betree.Node.lookup_first_message_after_key_back
  (key : U64) (msgs : betree.List (U64 × betree.Message))
  (ret0 : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match msgs with
  | betree.List.Cons p next_msgs =>
    let (k, m) := p
    if k = key
    then
      do
        let next_msgs0 ←
          betree.Node.lookup_first_message_after_key_back key next_msgs ret0
        Result.ret (betree.List.Cons (k, m) next_msgs0)
    else Result.ret ret0
  | betree.List.Nil => Result.ret ret0

/- [betree_main::betree::Node::{5}::apply_to_internal]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
def betree.Node.apply_to_internal
  (msgs : betree.List (U64 × betree.Message)) (key : U64)
  (new_msg : betree.Message) :
  Result (betree.List (U64 × betree.Message))
  :=
  do
    let msgs0 ← betree.Node.lookup_first_message_for_key key msgs
    let b ← betree.List.head_has_key betree.Message msgs0 key
    if b
    then
      match new_msg with
      | betree.Message.Insert i =>
        do
          let msgs1 ← betree.Node.filter_messages_for_key key msgs0
          let msgs2 ←
            betree.List.push_front (U64 × betree.Message) msgs1 (key,
              betree.Message.Insert i)
          betree.Node.lookup_first_message_for_key_back key msgs msgs2
      | betree.Message.Delete =>
        do
          let msgs1 ← betree.Node.filter_messages_for_key key msgs0
          let msgs2 ←
            betree.List.push_front (U64 × betree.Message) msgs1 (key,
              betree.Message.Delete)
          betree.Node.lookup_first_message_for_key_back key msgs msgs2
      | betree.Message.Upsert s =>
        do
          let p ← betree.List.hd (U64 × betree.Message) msgs0
          let (_, m) := p
          match m with
          | betree.Message.Insert prev =>
            do
              let v ← betree.upsert_update (Option.some prev) s
              let msgs1 ←
                betree.List.pop_front_back (U64 × betree.Message) msgs0
              let msgs2 ←
                betree.List.push_front (U64 × betree.Message) msgs1 (key,
                  betree.Message.Insert v)
              betree.Node.lookup_first_message_for_key_back key msgs msgs2
          | betree.Message.Delete =>
            do
              let v ← betree.upsert_update Option.none s
              let msgs1 ←
                betree.List.pop_front_back (U64 × betree.Message) msgs0
              let msgs2 ←
                betree.List.push_front (U64 × betree.Message) msgs1 (key,
                  betree.Message.Insert v)
              betree.Node.lookup_first_message_for_key_back key msgs msgs2
          | betree.Message.Upsert ufs =>
            do
              let msgs1 ←
                betree.Node.lookup_first_message_after_key key msgs0
              let msgs2 ←
                betree.List.push_front (U64 × betree.Message) msgs1 (key,
                  betree.Message.Upsert s)
              let msgs3 ←
                betree.Node.lookup_first_message_after_key_back key msgs0 msgs2
              betree.Node.lookup_first_message_for_key_back key msgs msgs3
    else
      do
        let msgs1 ←
          betree.List.push_front (U64 × betree.Message) msgs0 (key, new_msg)
        betree.Node.lookup_first_message_for_key_back key msgs msgs1

/- [betree_main::betree::Node::{5}::apply_messages_to_internal]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
divergent def betree.Node.apply_messages_to_internal
  (msgs : betree.List (U64 × betree.Message))
  (new_msgs : betree.List (U64 × betree.Message)) :
  Result (betree.List (U64 × betree.Message))
  :=
  match new_msgs with
  | betree.List.Cons new_msg new_msgs_tl =>
    do
      let (i, m) := new_msg
      let msgs0 ← betree.Node.apply_to_internal msgs i m
      betree.Node.apply_messages_to_internal msgs0 new_msgs_tl
  | betree.List.Nil => Result.ret msgs

/- [betree_main::betree::Node::{5}::apply_messages]: forward function -/
mutual divergent def betree.Node.apply_messages
  (self : betree.Node) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter)
  (msgs : betree.List (U64 × betree.Message)) (st : State) :
  Result (State × Unit)
  :=
  match self with
  | betree.Node.Internal node =>
    do
      let ⟨ i, i0, n, n0 ⟩ := node
      let (st0, content) ← betree.load_internal_node i st
      let content0 ← betree.Node.apply_messages_to_internal content msgs
      let num_msgs ← betree.List.len (U64 × betree.Message) content0
      if num_msgs >= params.min_flush_size
      then
        do
          let (st1, content1) ←
            betree.Internal.flush (betree.Internal.mk i i0 n n0) params
              node_id_cnt content0 st0
          let (node0, _) ←
            betree.Internal.flush_back (betree.Internal.mk i i0 n n0) params
              node_id_cnt content0 st0
          let ⟨ i1, _, _, _ ⟩ := node0
          let (st2, _) ← betree.store_internal_node i1 content1 st1
          Result.ret (st2, ())
      else
        do
          let (st1, _) ← betree.store_internal_node i content0 st0
          Result.ret (st1, ())
  | betree.Node.Leaf node =>
    do
      let (st0, content) ← betree.load_leaf_node node.id st
      let content0 ← betree.Node.apply_messages_to_leaf content msgs
      let len ← betree.List.len (U64 × U64) content0
      let i ← (U64.ofInt 2) * params.split_size
      if len >= i
      then
        do
          let (st1, _) ←
            betree.Leaf.split node content0 params node_id_cnt st0
          let (st2, _) ← betree.store_leaf_node node.id betree.List.Nil st1
          Result.ret (st2, ())
      else
        do
          let (st1, _) ← betree.store_leaf_node node.id content0 st0
          Result.ret (st1, ())

/- [betree_main::betree::Node::{5}::apply_messages]: backward function 0 -/
divergent def betree.Node.apply_messages_back
  (self : betree.Node) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter)
  (msgs : betree.List (U64 × betree.Message)) (st : State) :
  Result (betree.Node × betree.NodeIdCounter)
  :=
  match self with
  | betree.Node.Internal node =>
    do
      let ⟨ i, i0, n, n0 ⟩ := node
      let (st0, content) ← betree.load_internal_node i st
      let content0 ← betree.Node.apply_messages_to_internal content msgs
      let num_msgs ← betree.List.len (U64 × betree.Message) content0
      if num_msgs >= params.min_flush_size
      then
        do
          let (st1, content1) ←
            betree.Internal.flush (betree.Internal.mk i i0 n n0) params
              node_id_cnt content0 st0
          let (node0, node_id_cnt0) ←
            betree.Internal.flush_back (betree.Internal.mk i i0 n n0) params
              node_id_cnt content0 st0
          let ⟨ i1, i2, n1, n2 ⟩ := node0
          let _ ← betree.store_internal_node i1 content1 st1
          Result.ret (betree.Node.Internal (betree.Internal.mk i1 i2 n1 n2),
            node_id_cnt0)
      else
        do
          let _ ← betree.store_internal_node i content0 st0
          Result.ret (betree.Node.Internal (betree.Internal.mk i i0 n n0),
            node_id_cnt)
  | betree.Node.Leaf node =>
    do
      let (st0, content) ← betree.load_leaf_node node.id st
      let content0 ← betree.Node.apply_messages_to_leaf content msgs
      let len ← betree.List.len (U64 × U64) content0
      let i ← (U64.ofInt 2) * params.split_size
      if len >= i
      then
        do
          let (st1, new_node) ←
            betree.Leaf.split node content0 params node_id_cnt st0
          let _ ← betree.store_leaf_node node.id betree.List.Nil st1
          let node_id_cnt0 ←
            betree.Leaf.split_back node content0 params node_id_cnt st0
          Result.ret (betree.Node.Internal new_node, node_id_cnt0)
      else
        do
          let _ ← betree.store_leaf_node node.id content0 st0
          Result.ret (betree.Node.Leaf { node with size := len }, node_id_cnt)

/- [betree_main::betree::Internal::{4}::flush]: forward function -/
divergent def betree.Internal.flush
  (self : betree.Internal) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter)
  (content : betree.List (U64 × betree.Message)) (st : State) :
  Result (State × (betree.List (U64 × betree.Message)))
  :=
  do
    let ⟨ _, i, n, n0 ⟩ := self
    let p ← betree.List.partition_at_pivot betree.Message content i
    let (msgs_left, msgs_right) := p
    let len_left ← betree.List.len (U64 × betree.Message) msgs_left
    if len_left >= params.min_flush_size
    then
      do
        let (st0, _) ←
          betree.Node.apply_messages n params node_id_cnt msgs_left st
        let (_, node_id_cnt0) ←
          betree.Node.apply_messages_back n params node_id_cnt msgs_left st
        let len_right ← betree.List.len (U64 × betree.Message) msgs_right
        if len_right >= params.min_flush_size
        then
          do
            let (st1, _) ←
              betree.Node.apply_messages n0 params node_id_cnt0 msgs_right st0
            let _ ←
              betree.Node.apply_messages_back n0 params node_id_cnt0 msgs_right
                st0
            Result.ret (st1, betree.List.Nil)
        else Result.ret (st0, msgs_right)
    else
      do
        let (st0, _) ←
          betree.Node.apply_messages n0 params node_id_cnt msgs_right st
        let _ ←
          betree.Node.apply_messages_back n0 params node_id_cnt msgs_right st
        Result.ret (st0, msgs_left)

/- [betree_main::betree::Internal::{4}::flush]: backward function 0 -/
divergent def betree.Internal.flush_back
  (self : betree.Internal) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter)
  (content : betree.List (U64 × betree.Message)) (st : State) :
  Result (betree.Internal × betree.NodeIdCounter)
  :=
  do
    let ⟨ i, i0, n, n0 ⟩ := self
    let p ← betree.List.partition_at_pivot betree.Message content i0
    let (msgs_left, msgs_right) := p
    let len_left ← betree.List.len (U64 × betree.Message) msgs_left
    if len_left >= params.min_flush_size
    then
      do
        let (st0, _) ←
          betree.Node.apply_messages n params node_id_cnt msgs_left st
        let (n1, node_id_cnt0) ←
          betree.Node.apply_messages_back n params node_id_cnt msgs_left st
        let len_right ← betree.List.len (U64 × betree.Message) msgs_right
        if len_right >= params.min_flush_size
        then
          do
            let (n2, node_id_cnt1) ←
              betree.Node.apply_messages_back n0 params node_id_cnt0 msgs_right
                st0
            Result.ret (betree.Internal.mk i i0 n1 n2, node_id_cnt1)
        else Result.ret (betree.Internal.mk i i0 n1 n0, node_id_cnt0)
    else
      do
        let (n1, node_id_cnt0) ←
          betree.Node.apply_messages_back n0 params node_id_cnt msgs_right st
        Result.ret (betree.Internal.mk i i0 n n1, node_id_cnt0)

end

/- [betree_main::betree::Node::{5}::apply]: forward function -/
def betree.Node.apply
  (self : betree.Node) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter) (key : U64) (new_msg : betree.Message)
  (st : State) :
  Result (State × Unit)
  :=
  do
    let l := betree.List.Nil
    let (st0, _) ←
      betree.Node.apply_messages self params node_id_cnt (betree.List.Cons
        (key, new_msg) l) st
    let _ ←
      betree.Node.apply_messages_back self params node_id_cnt (betree.List.Cons
        (key, new_msg) l) st
    Result.ret (st0, ())

/- [betree_main::betree::Node::{5}::apply]: backward function 0 -/
def betree.Node.apply_back
  (self : betree.Node) (params : betree.Params)
  (node_id_cnt : betree.NodeIdCounter) (key : U64) (new_msg : betree.Message)
  (st : State) :
  Result (betree.Node × betree.NodeIdCounter)
  :=
  let l := betree.List.Nil
  betree.Node.apply_messages_back self params node_id_cnt (betree.List.Cons
    (key, new_msg) l) st

/- [betree_main::betree::BeTree::{6}::new]: forward function -/
def betree.BeTree.new
  (min_flush_size : U64) (split_size : U64) (st : State) :
  Result (State × betree.BeTree)
  :=
  do
    let node_id_cnt ← betree.NodeIdCounter.new
    let id ← betree.NodeIdCounter.fresh_id node_id_cnt
    let (st0, _) ← betree.store_leaf_node id betree.List.Nil st
    let node_id_cnt0 ← betree.NodeIdCounter.fresh_id_back node_id_cnt
    Result.ret (st0,
      {
        params :=
          { min_flush_size := min_flush_size, split_size := split_size },
        node_id_cnt := node_id_cnt0,
        root := (betree.Node.Leaf { id := id, size := (U64.ofInt 0) })
      })

/- [betree_main::betree::BeTree::{6}::apply]: forward function -/
def betree.BeTree.apply
  (self : betree.BeTree) (key : U64) (msg : betree.Message) (st : State) :
  Result (State × Unit)
  :=
  do
    let (st0, _) ←
      betree.Node.apply self.root self.params self.node_id_cnt key msg st
    let _ ←
      betree.Node.apply_back self.root self.params self.node_id_cnt key msg st
    Result.ret (st0, ())

/- [betree_main::betree::BeTree::{6}::apply]: backward function 0 -/
def betree.BeTree.apply_back
  (self : betree.BeTree) (key : U64) (msg : betree.Message) (st : State) :
  Result betree.BeTree
  :=
  do
    let (n, nic) ←
      betree.Node.apply_back self.root self.params self.node_id_cnt key msg st
    Result.ret { self with node_id_cnt := nic, root := n }

/- [betree_main::betree::BeTree::{6}::insert]: forward function -/
def betree.BeTree.insert
  (self : betree.BeTree) (key : U64) (value : U64) (st : State) :
  Result (State × Unit)
  :=
  do
    let (st0, _) ←
      betree.BeTree.apply self key (betree.Message.Insert value) st
    let _ ←
      betree.BeTree.apply_back self key (betree.Message.Insert value) st
    Result.ret (st0, ())

/- [betree_main::betree::BeTree::{6}::insert]: backward function 0 -/
def betree.BeTree.insert_back
  (self : betree.BeTree) (key : U64) (value : U64) (st : State) :
  Result betree.BeTree
  :=
  betree.BeTree.apply_back self key (betree.Message.Insert value) st

/- [betree_main::betree::BeTree::{6}::delete]: forward function -/
def betree.BeTree.delete
  (self : betree.BeTree) (key : U64) (st : State) : Result (State × Unit) :=
  do
    let (st0, _) ← betree.BeTree.apply self key betree.Message.Delete st
    let _ ← betree.BeTree.apply_back self key betree.Message.Delete st
    Result.ret (st0, ())

/- [betree_main::betree::BeTree::{6}::delete]: backward function 0 -/
def betree.BeTree.delete_back
  (self : betree.BeTree) (key : U64) (st : State) : Result betree.BeTree :=
  betree.BeTree.apply_back self key betree.Message.Delete st

/- [betree_main::betree::BeTree::{6}::upsert]: forward function -/
def betree.BeTree.upsert
  (self : betree.BeTree) (key : U64) (upd : betree.UpsertFunState) (st : State)
  :
  Result (State × Unit)
  :=
  do
    let (st0, _) ←
      betree.BeTree.apply self key (betree.Message.Upsert upd) st
    let _ ← betree.BeTree.apply_back self key (betree.Message.Upsert upd) st
    Result.ret (st0, ())

/- [betree_main::betree::BeTree::{6}::upsert]: backward function 0 -/
def betree.BeTree.upsert_back
  (self : betree.BeTree) (key : U64) (upd : betree.UpsertFunState) (st : State)
  :
  Result betree.BeTree
  :=
  betree.BeTree.apply_back self key (betree.Message.Upsert upd) st

/- [betree_main::betree::BeTree::{6}::lookup]: forward function -/
def betree.BeTree.lookup
  (self : betree.BeTree) (key : U64) (st : State) :
  Result (State × (Option U64))
  :=
  betree.Node.lookup self.root key st

/- [betree_main::betree::BeTree::{6}::lookup]: backward function 0 -/
def betree.BeTree.lookup_back
  (self : betree.BeTree) (key : U64) (st : State) : Result betree.BeTree :=
  do
    let n ← betree.Node.lookup_back self.root key st
    Result.ret { self with root := n }

/- [betree_main::main]: forward function -/
def main : Result Unit :=
  Result.ret ()

/- Unit test for [betree_main::main] -/
#assert (main == .ret ())

end betree_main
