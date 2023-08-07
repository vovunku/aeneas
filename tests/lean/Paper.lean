-- THIS FILE WAS AUTOMATICALLY GENERATED BY AENEAS
-- [paper]
import Base
open Primitives

namespace paper

/- [paper::ref_incr]: merged forward/backward function
   (there is a single backward function, and the forward function returns ()) -/
def ref_incr (x : I32) : Result I32 :=
  x + (I32.ofInt 1)

/- [paper::test_incr]: forward function -/
def test_incr : Result Unit :=
  do
    let x ← ref_incr (I32.ofInt 0)
    if not (x = (I32.ofInt 1))
    then Result.fail Error.panic
    else Result.ret ()

/- Unit test for [paper::test_incr] -/
#assert (test_incr == .ret ())

/- [paper::choose]: forward function -/
def choose (T : Type) (b : Bool) (x : T) (y : T) : Result T :=
  if b
  then Result.ret x
  else Result.ret y

/- [paper::choose]: backward function 0 -/
def choose_back
  (T : Type) (b : Bool) (x : T) (y : T) (ret0 : T) : Result (T × T) :=
  if b
  then Result.ret (ret0, y)
  else Result.ret (x, ret0)

/- [paper::test_choose]: forward function -/
def test_choose : Result Unit :=
  do
    let z ← choose I32 true (I32.ofInt 0) (I32.ofInt 0)
    let z0 ← z + (I32.ofInt 1)
    if not (z0 = (I32.ofInt 1))
    then Result.fail Error.panic
    else
      do
        let (x, y) ← choose_back I32 true (I32.ofInt 0) (I32.ofInt 0) z0
        if not (x = (I32.ofInt 1))
        then Result.fail Error.panic
        else
          if not (y = (I32.ofInt 0))
          then Result.fail Error.panic
          else Result.ret ()

/- Unit test for [paper::test_choose] -/
#assert (test_choose == .ret ())

/- [paper::List] -/
inductive List (T : Type) :=
| Cons : T → List T → List T
| Nil : List T

/- [paper::list_nth_mut]: forward function -/
divergent def list_nth_mut (T : Type) (l : List T) (i : U32) : Result T :=
  match l with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret x
    else do
           let i0 ← i - (U32.ofInt 1)
           list_nth_mut T tl i0
  | List.Nil => Result.fail Error.panic

/- [paper::list_nth_mut]: backward function 0 -/
divergent def list_nth_mut_back
  (T : Type) (l : List T) (i : U32) (ret0 : T) : Result (List T) :=
  match l with
  | List.Cons x tl =>
    if i = (U32.ofInt 0)
    then Result.ret (List.Cons ret0 tl)
    else
      do
        let i0 ← i - (U32.ofInt 1)
        let tl0 ← list_nth_mut_back T tl i0 ret0
        Result.ret (List.Cons x tl0)
  | List.Nil => Result.fail Error.panic

/- [paper::sum]: forward function -/
divergent def sum (l : List I32) : Result I32 :=
  match l with
  | List.Cons x tl => do
                        let i ← sum tl
                        x + i
  | List.Nil => Result.ret (I32.ofInt 0)

/- [paper::test_nth]: forward function -/
def test_nth : Result Unit :=
  do
    let l := List.Nil
    let l0 := List.Cons (I32.ofInt 3) l
    let l1 := List.Cons (I32.ofInt 2) l0
    let x ← list_nth_mut I32 (List.Cons (I32.ofInt 1) l1) (U32.ofInt 2)
    let x0 ← x + (I32.ofInt 1)
    let l2 ←
      list_nth_mut_back I32 (List.Cons (I32.ofInt 1) l1) (U32.ofInt 2) x0
    let i ← sum l2
    if not (i = (I32.ofInt 7))
    then Result.fail Error.panic
    else Result.ret ()

/- Unit test for [paper::test_nth] -/
#assert (test_nth == .ret ())

/- [paper::call_choose]: forward function -/
def call_choose (p : (U32 × U32)) : Result U32 :=
  do
    let (px, py) := p
    let pz ← choose U32 true px py
    let pz0 ← pz + (U32.ofInt 1)
    let (px0, _) ← choose_back U32 true px py pz0
    Result.ret px0

end paper
