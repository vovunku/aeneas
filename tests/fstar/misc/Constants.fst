(** THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS *)
(** [constants] *)
module Constants
open Primitives

#set-options "--z3rlimit 50 --fuel 1 --ifuel 1"

(** [constants::X0] *)
let x0_body : result u32 = Return 0
let x0_c : u32 = eval_global x0_body

(** [core::num::u32::{8}::MAX] *)
let core_num_u32_max_body : result u32 = Return 4294967295
let core_num_u32_max_c : u32 = eval_global core_num_u32_max_body

(** [constants::X1] *)
let x1_body : result u32 = Return core_num_u32_max_c
let x1_c : u32 = eval_global x1_body

(** [constants::X2] *)
let x2_body : result u32 = Return 3
let x2_c : u32 = eval_global x2_body

(** [constants::incr]: forward function *)
let incr_fwd (n : u32) : result u32 =
  u32_add n 1

(** [constants::X3] *)
let x3_body : result u32 = incr_fwd 32
let x3_c : u32 = eval_global x3_body

(** [constants::mk_pair0]: forward function *)
let mk_pair0_fwd (x : u32) (y : u32) : result (u32 & u32) =
  Return (x, y)

(** [constants::Pair] *)
type pair_t (t1 t2 : Type0) = { pair_x : t1; pair_y : t2; }

(** [constants::mk_pair1]: forward function *)
let mk_pair1_fwd (x : u32) (y : u32) : result (pair_t u32 u32) =
  Return { pair_x = x; pair_y = y }

(** [constants::P0] *)
let p0_body : result (u32 & u32) = mk_pair0_fwd 0 1
let p0_c : (u32 & u32) = eval_global p0_body

(** [constants::P1] *)
let p1_body : result (pair_t u32 u32) = mk_pair1_fwd 0 1
let p1_c : pair_t u32 u32 = eval_global p1_body

(** [constants::P2] *)
let p2_body : result (u32 & u32) = Return (0, 1)
let p2_c : (u32 & u32) = eval_global p2_body

(** [constants::P3] *)
let p3_body : result (pair_t u32 u32) = Return { pair_x = 0; pair_y = 1 }
let p3_c : pair_t u32 u32 = eval_global p3_body

(** [constants::Wrap] *)
type wrap_t (t : Type0) = { wrap_val : t; }

(** [constants::Wrap::{0}::new]: forward function *)
let wrap_new_fwd (t : Type0) (val0 : t) : result (wrap_t t) =
  Return { wrap_val = val0 }

(** [constants::Y] *)
let y_body : result (wrap_t i32) = wrap_new_fwd i32 2
let y_c : wrap_t i32 = eval_global y_body

(** [constants::unwrap_y]: forward function *)
let unwrap_y_fwd : result i32 =
  Return y_c.wrap_val

(** [constants::YVAL] *)
let yval_body : result i32 = unwrap_y_fwd
let yval_c : i32 = eval_global yval_body

(** [constants::get_z1::Z1] *)
let get_z1_z1_body : result i32 = Return 3
let get_z1_z1_c : i32 = eval_global get_z1_z1_body

(** [constants::get_z1]: forward function *)
let get_z1_fwd : result i32 =
  Return get_z1_z1_c

(** [constants::add]: forward function *)
let add_fwd (a : i32) (b : i32) : result i32 =
  i32_add a b

(** [constants::Q1] *)
let q1_body : result i32 = Return 5
let q1_c : i32 = eval_global q1_body

(** [constants::Q2] *)
let q2_body : result i32 = Return q1_c
let q2_c : i32 = eval_global q2_body

(** [constants::Q3] *)
let q3_body : result i32 = add_fwd q2_c 3
let q3_c : i32 = eval_global q3_body

(** [constants::get_z2]: forward function *)
let get_z2_fwd : result i32 =
  let* i = get_z1_fwd in let* i0 = add_fwd i q3_c in add_fwd q1_c i0

(** [constants::S1] *)
let s1_body : result u32 = Return 6
let s1_c : u32 = eval_global s1_body

(** [constants::S2] *)
let s2_body : result u32 = incr_fwd s1_c
let s2_c : u32 = eval_global s2_body

(** [constants::S3] *)
let s3_body : result (pair_t u32 u32) = Return p3_c
let s3_c : pair_t u32 u32 = eval_global s3_body

(** [constants::S4] *)
let s4_body : result (pair_t u32 u32) = mk_pair1_fwd 7 8
let s4_c : pair_t u32 u32 = eval_global s4_body

