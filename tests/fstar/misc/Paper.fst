(** THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS *)
(** [paper] *)
module Paper
open Primitives

#set-options "--z3rlimit 50 --fuel 1 --ifuel 1"

(** [paper::ref_incr]: merged forward/backward function
    (there is a single backward function, and the forward function returns ()) *)
let ref_incr_fwd_back (x : i32) : result i32 =
  i32_add x 1

(** [paper::test_incr]: forward function *)
let test_incr_fwd : result unit =
  let* x = ref_incr_fwd_back 0 in
  if not (x = 1) then Fail Failure else Return ()

(** Unit test for [paper::test_incr] *)
let _ = assert_norm (test_incr_fwd = Return ())

(** [paper::choose]: forward function *)
let choose_fwd (t : Type0) (b : bool) (x : t) (y : t) : result t =
  if b then Return x else Return y

(** [paper::choose]: backward function 0 *)
let choose_back
  (t : Type0) (b : bool) (x : t) (y : t) (ret : t) : result (t & t) =
  if b then Return (ret, y) else Return (x, ret)

(** [paper::test_choose]: forward function *)
let test_choose_fwd : result unit =
  let* z = choose_fwd i32 true 0 0 in
  let* z0 = i32_add z 1 in
  if not (z0 = 1)
  then Fail Failure
  else
    let* (x, y) = choose_back i32 true 0 0 z0 in
    if not (x = 1)
    then Fail Failure
    else if not (y = 0) then Fail Failure else Return ()

(** Unit test for [paper::test_choose] *)
let _ = assert_norm (test_choose_fwd = Return ())

(** [paper::List] *)
type list_t (t : Type0) =
| ListCons : t -> list_t t -> list_t t
| ListNil : list_t t

(** [paper::list_nth_mut]: forward function *)
let rec list_nth_mut_fwd (t : Type0) (l : list_t t) (i : u32) : result t =
  begin match l with
  | ListCons x tl ->
    if i = 0
    then Return x
    else let* i0 = u32_sub i 1 in list_nth_mut_fwd t tl i0
  | ListNil -> Fail Failure
  end

(** [paper::list_nth_mut]: backward function 0 *)
let rec list_nth_mut_back
  (t : Type0) (l : list_t t) (i : u32) (ret : t) : result (list_t t) =
  begin match l with
  | ListCons x tl ->
    if i = 0
    then Return (ListCons ret tl)
    else
      let* i0 = u32_sub i 1 in
      let* tl0 = list_nth_mut_back t tl i0 ret in
      Return (ListCons x tl0)
  | ListNil -> Fail Failure
  end

(** [paper::sum]: forward function *)
let rec sum_fwd (l : list_t i32) : result i32 =
  begin match l with
  | ListCons x tl -> let* i = sum_fwd tl in i32_add x i
  | ListNil -> Return 0
  end

(** [paper::test_nth]: forward function *)
let test_nth_fwd : result unit =
  let l = ListNil in
  let l0 = ListCons 3 l in
  let l1 = ListCons 2 l0 in
  let* x = list_nth_mut_fwd i32 (ListCons 1 l1) 2 in
  let* x0 = i32_add x 1 in
  let* l2 = list_nth_mut_back i32 (ListCons 1 l1) 2 x0 in
  let* i = sum_fwd l2 in
  if not (i = 7) then Fail Failure else Return ()

(** Unit test for [paper::test_nth] *)
let _ = assert_norm (test_nth_fwd = Return ())

(** [paper::call_choose]: forward function *)
let call_choose_fwd (p : (u32 & u32)) : result u32 =
  let (px, py) = p in
  let* pz = choose_fwd u32 true px py in
  let* pz0 = u32_add pz 1 in
  let* (px0, _) = choose_back u32 true px py pz0 in
  Return px0

