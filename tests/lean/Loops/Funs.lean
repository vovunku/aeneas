-- THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS
-- [loops]: function definitions
import Base
import Loops.Types
open Primitives

namespace loops

/- [loops::sum]: loop 0: forward function -/
divergent def sum_loop (max : U32) (i : U32) (s : U32) : Result U32 :=
  if i < max
  then do
         let s0 ← s + i
         let i0 ← i + (U32.ofInt 1)
         sum_loop max i0 s0
  else s * (U32.ofInt 2)

/- [loops::sum]: forward function -/
def sum (max : U32) : Result U32 :=
  sum_loop max (U32.ofInt 0) (U32.ofInt 0)

/- [loops::sum_with_mut_borrows]: loop 0: forward function -/
divergent def sum_with_mut_borrows_loop
  (max : U32) (mi : U32) (ms : U32) : Result U32 :=
  if mi < max
  then
    do
      let ms0 ← ms + mi
      let mi0 ← mi + (U32.ofInt 1)
      sum_with_mut_borrows_loop max mi0 ms0
  else ms * (U32.ofInt 2)

/- [loops::sum_with_mut_borrows]: forward function -/
def sum_with_mut_borrows (max : U32) : Result U32 :=
  sum_with_mut_borrows_loop max (U32.ofInt 0) (U32.ofInt 0)

/- [loops::sum_with_shared_borrows]: loop 0: forward function -/
divergent def sum_with_shared_borrows_loop
  (max : U32) (i : U32) (s : U32) : Result U32 :=
  if i < max
  then
    do
      let i0 ← i + (U32.ofInt 1)
      let s0 ← s + i0
      sum_with_shared_borrows_loop max i0 s0
  else s * (U32.ofInt 2)

/- [loops::sum_with_shared_borrows]: forward function -/
def sum_with_shared_borrows (max : U32) : Result U32 :=
  sum_with_shared_borrows_loop max (U32.ofInt 0) (U32.ofInt 0)

/- [loops::clear]: loop 0: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
divergent def clear_loop (v : Vec U32) (i : Usize) : Result (Vec U32) :=
  let i0 := Vec.len U32 v
  if i < i0
  then
    do
      let i1 ← i + (Usize.ofInt 1)
      let v0 ← Vec.index_mut_back U32 v i (U32.ofInt 0)
      clear_loop v0 i1
  else Result.ret v

/- [loops::clear]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
def clear (v : Vec U32) : Result (Vec U32) :=
  clear_loop v (Usize.ofInt 0)

/- [loops::list_mem]: loop 0: forward function -/
divergent def list_mem_loop (x : U32) (ls : List U32) : Result Bool :=
  match ls with
  | List.Cons y tl => if y = x
                      then Result.ret true
                      else list_mem_loop x tl
  | List.Nil => Result.ret false

/- [loops::list_mem]: forward function -/
def list_mem (x : U32) (ls : List U32) : Result Bool :=
  list_mem_loop x ls

/- [loops::list_nth_mut_loop]: loop 0: forward function -/
divergent def list_nth_mut_loop_loop
  (T : Type) (ls : List T) (i : U32) : Result T :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret x
    else do
           let i0 ← i - (U32.ofInt 1)
           list_nth_mut_loop_loop T tl i0
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop]: forward function -/
def list_nth_mut_loop (T : Type) (ls : List T) (i : U32) : Result T :=
  list_nth_mut_loop_loop T ls i

/- [loops::list_nth_mut_loop]: loop 0: backward function 0 -/
divergent def list_nth_mut_loop_loop_back
  (T : Type) (ls : List T) (i : U32) (ret0 : T) : Result (List T) :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret (List.Cons ret0 tl)
    else
      do
        let i0 ← i - (U32.ofInt 1)
        let tl0 ← list_nth_mut_loop_loop_back T tl i0 ret0
        Result.ret (List.Cons x tl0)
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop]: backward function 0 -/
def list_nth_mut_loop_back
  (T : Type) (ls : List T) (i : U32) (ret0 : T) : Result (List T) :=
  list_nth_mut_loop_loop_back T ls i ret0

/- [loops::list_nth_shared_loop]: loop 0: forward function -/
divergent def list_nth_shared_loop_loop
  (T : Type) (ls : List T) (i : U32) : Result T :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret x
    else do
           let i0 ← i - (U32.ofInt 1)
           list_nth_shared_loop_loop T tl i0
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_loop]: forward function -/
def list_nth_shared_loop (T : Type) (ls : List T) (i : U32) : Result T :=
  list_nth_shared_loop_loop T ls i

/- [loops::get_elem_mut]: loop 0: forward function -/
divergent def get_elem_mut_loop (x : Usize) (ls : List Usize) : Result Usize :=
  match ls with
  | List.Cons y tl => if y = x
                      then Result.ret y
                      else get_elem_mut_loop x tl
  | List.Nil => Result.fail Error.panic

/- [loops::get_elem_mut]: forward function -/
def get_elem_mut (slots : Vec (List Usize)) (x : Usize) : Result Usize :=
  do
    let l ← Vec.index_mut (List Usize) slots (Usize.ofInt 0)
    get_elem_mut_loop x l

/- [loops::get_elem_mut]: loop 0: backward function 0 -/
divergent def get_elem_mut_loop_back
  (x : Usize) (ls : List Usize) (ret0 : Usize) : Result (List Usize) :=
  match ls with
  | List.Cons y tl =>
    if y = x
    then Result.ret (List.Cons ret0 tl)
    else
      do
        let tl0 ← get_elem_mut_loop_back x tl ret0
        Result.ret (List.Cons y tl0)
  | List.Nil => Result.fail Error.panic

/- [loops::get_elem_mut]: backward function 0 -/
def get_elem_mut_back
  (slots : Vec (List Usize)) (x : Usize) (ret0 : Usize) :
  Result (Vec (List Usize))
  :=
  do
    let l ← Vec.index_mut (List Usize) slots (Usize.ofInt 0)
    let l0 ← get_elem_mut_loop_back x l ret0
    Vec.index_mut_back (List Usize) slots (Usize.ofInt 0) l0

/- [loops::get_elem_shared]: loop 0: forward function -/
divergent def get_elem_shared_loop
  (x : Usize) (ls : List Usize) : Result Usize :=
  match ls with
  | List.Cons y tl => if y = x
                      then Result.ret y
                      else get_elem_shared_loop x tl
  | List.Nil => Result.fail Error.panic

/- [loops::get_elem_shared]: forward function -/
def get_elem_shared (slots : Vec (List Usize)) (x : Usize) : Result Usize :=
  do
    let l ← Vec.index_shared (List Usize) slots (Usize.ofInt 0)
    get_elem_shared_loop x l

/- [loops::id_mut]: forward function -/
def id_mut (T : Type) (ls : List T) : Result (List T) :=
  Result.ret ls

/- [loops::id_mut]: backward function 0 -/
def id_mut_back (T : Type) (ls : List T) (ret0 : List T) : Result (List T) :=
  Result.ret ret0

/- [loops::id_shared]: forward function -/
def id_shared (T : Type) (ls : List T) : Result (List T) :=
  Result.ret ls

/- [loops::list_nth_mut_loop_with_id]: loop 0: forward function -/
divergent def list_nth_mut_loop_with_id_loop
  (T : Type) (i : U32) (ls : List T) : Result T :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret x
    else do
           let i0 ← i - (U32.ofInt 1)
           list_nth_mut_loop_with_id_loop T i0 tl
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_with_id]: forward function -/
def list_nth_mut_loop_with_id (T : Type) (ls : List T) (i : U32) : Result T :=
  do
    let ls0 ← id_mut T ls
    list_nth_mut_loop_with_id_loop T i ls0

/- [loops::list_nth_mut_loop_with_id]: loop 0: backward function 0 -/
divergent def list_nth_mut_loop_with_id_loop_back
  (T : Type) (i : U32) (ls : List T) (ret0 : T) : Result (List T) :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret (List.Cons ret0 tl)
    else
      do
        let i0 ← i - (U32.ofInt 1)
        let tl0 ← list_nth_mut_loop_with_id_loop_back T i0 tl ret0
        Result.ret (List.Cons x tl0)
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_with_id]: backward function 0 -/
def list_nth_mut_loop_with_id_back
  (T : Type) (ls : List T) (i : U32) (ret0 : T) : Result (List T) :=
  do
    let ls0 ← id_mut T ls
    let l ← list_nth_mut_loop_with_id_loop_back T i ls0 ret0
    id_mut_back T ls l

/- [loops::list_nth_shared_loop_with_id]: loop 0: forward function -/
divergent def list_nth_shared_loop_with_id_loop
  (T : Type) (i : U32) (ls : List T) : Result T :=
  match ls with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret x
    else
      do
        let i0 ← i - (U32.ofInt 1)
        list_nth_shared_loop_with_id_loop T i0 tl
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_loop_with_id]: forward function -/
def list_nth_shared_loop_with_id
  (T : Type) (ls : List T) (i : U32) : Result T :=
  do
    let ls0 ← id_shared T ls
    list_nth_shared_loop_with_id_loop T i ls0

/- [loops::list_nth_mut_loop_pair]: loop 0: forward function -/
divergent def list_nth_mut_loop_pair_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_mut_loop_pair_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_pair]: forward function -/
def list_nth_mut_loop_pair
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_mut_loop_pair_loop T ls0 ls1 i

/- [loops::list_nth_mut_loop_pair]: loop 0: backward function 0 -/
divergent def list_nth_mut_loop_pair_loop_back'a
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl0)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl00 ← list_nth_mut_loop_pair_loop_back'a T tl0 tl1 i0 ret0
          Result.ret (List.Cons x0 tl00)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_pair]: backward function 0 -/
def list_nth_mut_loop_pair_back'a
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_mut_loop_pair_loop_back'a T ls0 ls1 i ret0

/- [loops::list_nth_mut_loop_pair]: loop 0: backward function 1 -/
divergent def list_nth_mut_loop_pair_loop_back'b
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl10 ← list_nth_mut_loop_pair_loop_back'b T tl0 tl1 i0 ret0
          Result.ret (List.Cons x1 tl10)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_pair]: backward function 1 -/
def list_nth_mut_loop_pair_back'b
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_mut_loop_pair_loop_back'b T ls0 ls1 i ret0

/- [loops::list_nth_shared_loop_pair]: loop 0: forward function -/
divergent def list_nth_shared_loop_pair_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_shared_loop_pair_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_loop_pair]: forward function -/
def list_nth_shared_loop_pair
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_shared_loop_pair_loop T ls0 ls1 i

/- [loops::list_nth_mut_loop_pair_merge]: loop 0: forward function -/
divergent def list_nth_mut_loop_pair_merge_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_mut_loop_pair_merge_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_pair_merge]: forward function -/
def list_nth_mut_loop_pair_merge
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_mut_loop_pair_merge_loop T ls0 ls1 i

/- [loops::list_nth_mut_loop_pair_merge]: loop 0: backward function 0 -/
divergent def list_nth_mut_loop_pair_merge_loop_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : (T × T)) :
  Result ((List T) × (List T))
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then let (t, t0) := ret0
           Result.ret (List.Cons t tl0, List.Cons t0 tl1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let (tl00, tl10) ←
            list_nth_mut_loop_pair_merge_loop_back T tl0 tl1 i0 ret0
          Result.ret (List.Cons x0 tl00, List.Cons x1 tl10)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_loop_pair_merge]: backward function 0 -/
def list_nth_mut_loop_pair_merge_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : (T × T)) :
  Result ((List T) × (List T))
  :=
  list_nth_mut_loop_pair_merge_loop_back T ls0 ls1 i ret0

/- [loops::list_nth_shared_loop_pair_merge]: loop 0: forward function -/
divergent def list_nth_shared_loop_pair_merge_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_shared_loop_pair_merge_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_loop_pair_merge]: forward function -/
def list_nth_shared_loop_pair_merge
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_shared_loop_pair_merge_loop T ls0 ls1 i

/- [loops::list_nth_mut_shared_loop_pair]: loop 0: forward function -/
divergent def list_nth_mut_shared_loop_pair_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_mut_shared_loop_pair_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_shared_loop_pair]: forward function -/
def list_nth_mut_shared_loop_pair
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_mut_shared_loop_pair_loop T ls0 ls1 i

/- [loops::list_nth_mut_shared_loop_pair]: loop 0: backward function 0 -/
divergent def list_nth_mut_shared_loop_pair_loop_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl0)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl00 ←
            list_nth_mut_shared_loop_pair_loop_back T tl0 tl1 i0 ret0
          Result.ret (List.Cons x0 tl00)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_shared_loop_pair]: backward function 0 -/
def list_nth_mut_shared_loop_pair_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_mut_shared_loop_pair_loop_back T ls0 ls1 i ret0

/- [loops::list_nth_mut_shared_loop_pair_merge]: loop 0: forward function -/
divergent def list_nth_mut_shared_loop_pair_merge_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_mut_shared_loop_pair_merge_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_shared_loop_pair_merge]: forward function -/
def list_nth_mut_shared_loop_pair_merge
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_mut_shared_loop_pair_merge_loop T ls0 ls1 i

/- [loops::list_nth_mut_shared_loop_pair_merge]: loop 0: backward function 0 -/
divergent def list_nth_mut_shared_loop_pair_merge_loop_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl0)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl00 ←
            list_nth_mut_shared_loop_pair_merge_loop_back T tl0 tl1 i0 ret0
          Result.ret (List.Cons x0 tl00)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_mut_shared_loop_pair_merge]: backward function 0 -/
def list_nth_mut_shared_loop_pair_merge_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_mut_shared_loop_pair_merge_loop_back T ls0 ls1 i ret0

/- [loops::list_nth_shared_mut_loop_pair]: loop 0: forward function -/
divergent def list_nth_shared_mut_loop_pair_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_shared_mut_loop_pair_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_mut_loop_pair]: forward function -/
def list_nth_shared_mut_loop_pair
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_shared_mut_loop_pair_loop T ls0 ls1 i

/- [loops::list_nth_shared_mut_loop_pair]: loop 0: backward function 1 -/
divergent def list_nth_shared_mut_loop_pair_loop_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl10 ←
            list_nth_shared_mut_loop_pair_loop_back T tl0 tl1 i0 ret0
          Result.ret (List.Cons x1 tl10)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_mut_loop_pair]: backward function 1 -/
def list_nth_shared_mut_loop_pair_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_shared_mut_loop_pair_loop_back T ls0 ls1 i ret0

/- [loops::list_nth_shared_mut_loop_pair_merge]: loop 0: forward function -/
divergent def list_nth_shared_mut_loop_pair_merge_loop
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (x0, x1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          list_nth_shared_mut_loop_pair_merge_loop T tl0 tl1 i0
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_mut_loop_pair_merge]: forward function -/
def list_nth_shared_mut_loop_pair_merge
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) : Result (T × T) :=
  list_nth_shared_mut_loop_pair_merge_loop T ls0 ls1 i

/- [loops::list_nth_shared_mut_loop_pair_merge]: loop 0: backward function 0 -/
divergent def list_nth_shared_mut_loop_pair_merge_loop_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  match ls0 with
  | List.Cons x0 tl0 =>
    match ls1 with
    | List.Cons x1 tl1 =>
      if i = (U32.ofInt 0)
      then Result.ret (List.Cons ret0 tl1)
      else
        do
          let i0 ← i - (U32.ofInt 1)
          let tl10 ←
            list_nth_shared_mut_loop_pair_merge_loop_back T tl0 tl1 i0 ret0
          Result.ret (List.Cons x1 tl10)
    | List.Nil => Result.fail Error.panic
  | List.Nil => Result.fail Error.panic

/- [loops::list_nth_shared_mut_loop_pair_merge]: backward function 0 -/
def list_nth_shared_mut_loop_pair_merge_back
  (T : Type) (ls0 : List T) (ls1 : List T) (i : U32) (ret0 : T) :
  Result (List T)
  :=
  list_nth_shared_mut_loop_pair_merge_loop_back T ls0 ls1 i ret0

end loops
