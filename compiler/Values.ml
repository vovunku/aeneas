open Identifiers
open Types
module PrimitiveValues = PrimitiveValues

(* TODO(SH): I often write "abstract" (value, borrow content, etc.) while I should
 * write "abstraction" (because those values are not abstract, they simply are
 * inside abstractions) *)

module BorrowId = IdGen ()
module SymbolicValueId = IdGen ()
module AbstractionId = IdGen ()
module FunCallId = IdGen ()
module LoopId = IdGen ()

type big_int = PrimitiveValues.big_int [@@deriving show, ord]
type scalar_value = PrimitiveValues.scalar_value [@@deriving show, ord]
type literal = PrimitiveValues.literal [@@deriving show, ord]
type symbolic_value_id = SymbolicValueId.id [@@deriving show, ord]
type symbolic_value_id_set = SymbolicValueId.Set.t [@@deriving show, ord]
type loop_id = LoopId.id [@@deriving show, ord]

(** The kind of a symbolic value, which precises how the value was generated.

    TODO: remove? This is not useful anymore.
  *)
type sv_kind =
  | FunCallRet  (** The value is the return value of a function call *)
  | FunCallGivenBack
      (** The value is a borrowed value given back by an abstraction
          (happens when giving a borrow to a function: when the abstraction
          introduced to model the function call ends we reintroduce a symbolic
          value in the context for the value modified by the abstraction through
          the borrow).
       *)
  | SynthInput
      (** The value is an input value of the function whose body we are
          currently synthesizing.
       *)
  | SynthRetGivenBack
      (** The value is a borrowed value that the function whose body we are
          synthesizing returned, and which was given back because we ended
          one of the lifetimes of this function (we do this to synthesize
          the backward functions).
       *)
  | SynthInputGivenBack
      (** The value was given back upon ending one of the input abstractions *)
  | Global  (** The value is a global *)
  | LoopOutput  (** The output of a loop (seen as a forward computation) *)
  | LoopGivenBack
      (** A value given back by a loop (when ending abstractions while going backwards) *)
  | LoopJoin
      (** The result of a loop join (when computing loop fixed points) *)
  | Aggregate
      (** A symbolic value we introduce in place of an aggregate value *)
[@@deriving show, ord]

(** Ancestor for {!symbolic_value} iter visitor *)
class ['self] iter_symbolic_value_base =
  object (_self : 'self)
    inherit [_] VisitorsRuntime.iter
    method visit_sv_kind : 'env -> sv_kind -> unit = fun _ _ -> ()
    method visit_rty : 'env -> rty -> unit = fun _ _ -> ()

    method visit_symbolic_value_id : 'env -> symbolic_value_id -> unit =
      fun _ _ -> ()
  end

(** Ancestor for {!symbolic_value} map visitor for *)
class ['self] map_symbolic_value_base =
  object (_self : 'self)
    inherit [_] VisitorsRuntime.map
    method visit_sv_kind : 'env -> sv_kind -> sv_kind = fun _ x -> x
    method visit_rty : 'env -> rty -> rty = fun _ x -> x

    method visit_symbolic_value_id
        : 'env -> symbolic_value_id -> symbolic_value_id =
      fun _ x -> x
  end

(** A symbolic value *)
type symbolic_value = {
  sv_kind : sv_kind;
  sv_id : symbolic_value_id;
  sv_ty : rty;
}
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_symbolic_value";
        variety = "iter";
        ancestors = [ "iter_symbolic_value_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_symbolic_value";
        variety = "map";
        ancestors = [ "map_symbolic_value_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

type borrow_id = BorrowId.id [@@deriving show, ord]
type borrow_id_set = BorrowId.Set.t [@@deriving show, ord]
type loan_id = BorrowId.id [@@deriving show, ord]
type loan_id_set = BorrowId.Set.t [@@deriving show, ord]

(** Ancestor for {!typed_value} iter visitor *)
class ['self] iter_typed_value_base =
  object (self : 'self)
    inherit [_] iter_symbolic_value
    method visit_literal : 'env -> literal -> unit = fun _ _ -> ()
    method visit_erased_region : 'env -> erased_region -> unit = fun _ _ -> ()
    method visit_variant_id : 'env -> variant_id -> unit = fun _ _ -> ()
    method visit_ety : 'env -> ety -> unit = fun _ _ -> ()
    method visit_borrow_id : 'env -> borrow_id -> unit = fun _ _ -> ()
    method visit_loan_id : 'env -> loan_id -> unit = fun _ _ -> ()

    method visit_borrow_id_set : 'env -> borrow_id_set -> unit =
      fun env ids -> BorrowId.Set.iter (self#visit_borrow_id env) ids

    method visit_loan_id_set : 'env -> loan_id_set -> unit =
      fun env ids -> BorrowId.Set.iter (self#visit_loan_id env) ids
  end

(** Ancestor for {!typed_value} map visitor for *)
class ['self] map_typed_value_base =
  object (self : 'self)
    inherit [_] map_symbolic_value
    method visit_literal : 'env -> literal -> literal = fun _ cv -> cv

    method visit_erased_region : 'env -> erased_region -> erased_region =
      fun _ r -> r

    method visit_ety : 'env -> ety -> ety = fun _ ty -> ty
    method visit_variant_id : 'env -> variant_id -> variant_id = fun _ x -> x
    method visit_borrow_id : 'env -> borrow_id -> borrow_id = fun _ id -> id
    method visit_loan_id : 'env -> loan_id -> loan_id = fun _ id -> id

    method visit_borrow_id_set : 'env -> borrow_id_set -> borrow_id_set =
      fun env ids -> BorrowId.Set.map (self#visit_borrow_id env) ids

    method visit_loan_id_set : 'env -> loan_id_set -> loan_id_set =
      fun env ids -> BorrowId.Set.map (self#visit_loan_id env) ids
  end

(** An untyped value, used in the environments *)
type value =
  | Literal of literal  (** Non-symbolic primitive value *)
  | Adt of adt_value  (** Enumerations and structures *)
  | Bottom  (** No value (uninitialized or moved value) *)
  | Borrow of borrow_content  (** A borrowed value *)
  | Loan of loan_content  (** A loaned value *)
  | Symbolic of symbolic_value
      (** Borrow projector over a symbolic value.
      
          Note that contrary to the abstraction-values case, symbolic values
          appearing in regular values are interpreted as *borrow* projectors,
          they can never be *loan* projectors.
       *)

and adt_value = {
  variant_id : variant_id option;
  field_values : typed_value list;
}

and borrow_content =
  | SharedBorrow of borrow_id  (** A shared borrow. *)
  | MutBorrow of borrow_id * typed_value  (** A mutably borrowed value. *)
  | ReservedMutBorrow of borrow_id
      (** A reserved mut borrow.

          This is used to model {{: https://rustc-dev-guide.rust-lang.org/borrow_check/two_phase_borrows.html} two-phase borrows}.
          When evaluating a two-phase mutable borrow we first introduce a reserved
          borrow which behaves like a shared borrow until the moment we actually *use*
          the borrow: at this point, we end all the other shared borrows (and reserved
          borrows - though there shouldn't be any other reserved borrows in practice)
          of this value and replace the reserved borrow with a mutable borrow (as well as
          the shared loan with a mutable loan).
          
          A simple use case of two-phase borrows:
          {[
            let mut v = Vec::new();
            v.push(v.len());
          ]}
          
          Without two-phase borrows, this gets desugared to (something similar to)
          the following MIR:
          {[
            v = Vec::new();
            v1 = &mut v;
            v2 = &v; // We need this borrow, but v has already been mutably borrowed!
            l = Vec::len(move v2); // We need v2 here, and v1 *below*
            Vec::push(move v1, move l);
          ]}

          With two-phase borrows we get this:
          {[
            v = Vec::new();
            v1 = &two-phase mut v; // v1 is a reserved borrow, and v is *shared*
            v2 = &v; // v is shared, so we can (immutably) borrow through v2
            l = Vec::len(move v2); // We use v2 here
            Vec::push(move v1, move l); // v1 gets promoted to a mutable borrow here
          ]}
       *)

and loan_content =
  | SharedLoan of loan_id_set * typed_value
  | MutLoan of loan_id

(** "Meta"-value: information we store for the synthesis.

     Note that we never automatically visit the meta-values with the
     visitors: they really are meta information, and shouldn't be considered
     as part of the environment during a symbolic execution.
     
     TODO: we may want to create wrappers, to prevent accidently mixing meta
     values and regular values.
 *)
and mvalue = typed_value

(** "Regular" typed value (we map variables to typed values) *)
and typed_value = { value : value; ty : ety }
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_typed_value_visit_mvalue";
        variety = "iter";
        ancestors = [ "iter_typed_value_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_typed_value_visit_mvalue";
        variety = "map";
        ancestors = [ "map_typed_value_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

(** "Meta"-symbolic value.

     See the explanations for {!mvalue}

     TODO: we may want to create wrappers, to prevent mixing meta values
     and regular values.
 *)
type msymbolic_value = symbolic_value [@@deriving show, ord]

class ['self] iter_typed_value =
  object (_self : 'self)
    inherit [_] iter_typed_value_visit_mvalue

    (** We have to override the {!iter_typed_value_visit_mvalue.visit_mvalue} method,
        to ignore meta-values *)
    method! visit_mvalue : 'env -> mvalue -> unit = fun _ _ -> ()

    method visit_msymbolic_value : 'env -> msymbolic_value -> unit =
      fun _ _ -> ()
  end

class ['self] map_typed_value =
  object (_self : 'self)
    inherit [_] map_typed_value_visit_mvalue

    (** We have to override the {!iter_typed_value_visit_mvalue.visit_mvalue} method,
        to ignore meta-values *)
    method! visit_mvalue : 'env -> mvalue -> mvalue = fun _ x -> x

    method visit_msymbolic_value : 'env -> msymbolic_value -> msymbolic_value =
      fun _ m -> m
  end

(** When giving shared borrows to functions (i.e., inserting shared borrows inside
    abstractions) we need to reborrow the shared values. When doing so, we lookup
    the shared values and apply some special projections to the shared value
    (until we can't go further, i.e., we find symbolic values which may get
    expanded upon reading them later), which don't generate avalues but
    sets of borrow ids and symbolic values.
    
    Note that as shared values can't get modified it is ok to forget the
    structure of the values we projected, and only keep the set of borrows
    (and symbolic values).
    
    TODO: we may actually need to remember the structure, in order to know
    which borrows are inside which other borrows...
*)
type abstract_shared_borrow =
  | AsbBorrow of borrow_id
  | AsbProjReborrows of symbolic_value * rty
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_abstract_shared_borrow";
        variety = "iter";
        ancestors = [ "iter_typed_value" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_abstract_shared_borrow";
        variety = "map";
        ancestors = [ "map_typed_value" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

(** A set of abstract shared borrows *)
type abstract_shared_borrows = abstract_shared_borrow list
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_abstract_shared_borrows";
        variety = "iter";
        ancestors = [ "iter_abstract_shared_borrow" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_abstract_shared_borrows";
        variety = "map";
        ancestors = [ "map_abstract_shared_borrow" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

(** Ancestor for {!aproj} iter visitor *)
class ['self] iter_aproj_base =
  object (_self : 'self)
    inherit [_] iter_abstract_shared_borrows
  end

(** Ancestor for {!aproj} map visitor *)
class ['self] map_aproj_base =
  object (_self : 'self)
    inherit [_] map_abstract_shared_borrows
  end

type aproj =
  | AProjLoans of symbolic_value * (msymbolic_value * aproj) list
      (** A projector of loans over a symbolic value.
      
          Whenever we call a function, we introduce a symbolic value for
          the returned value. We insert projectors of loans over this
          symbolic value in the abstractions introduced by this function
          call: those projectors allow to insert the proper loans in the
          various abstractions whenever symbolic borrows get expanded.

          The borrows of a symbolic value may be spread between different
          abstractions, meaning that *one* projector of loans might receive
          *several* (symbolic) given back values.
          
          This is the case in the following example:
          {[
            fn f<'a> (...) -> (&'a mut u32, &'a mut u32);
            fn g<'b, 'c>(p : (&'b mut u32, &'c mut u32));

            let p = f(...);
            g(move p);

            // Symbolic context after the call to g:
            // abs'a {'a} { [s@0 <: (&'a mut u32, &'a mut u32)] }
            //
            // abs'b {'b} { (s@0 <: (&'b mut u32, &'c mut u32)) }
            // abs'c {'c} { (s@0 <: (&'b mut u32, &'c mut u32)) }
          ]}
          
          Upon evaluating the call to [f], we introduce a symbolic value [s@0]
          and a projector of loans (projector loans from the region 'c).
          This projector will later receive two given back values: one for
          'a and one for 'b.
          
          We accumulate those values in the list of projections (note that
          the meta value stores the value which was given back).
          
          We can later end the projector of loans if [s@0] is not referenced
          anywhere in the context below a projector of borrows which intersects
          this projector of loans.
       *)
  | AProjBorrows of symbolic_value * rty
      (** Note that an AProjBorrows only operates on a value which is not below
          a shared loan: under a shared loan, we use {!abstract_shared_borrow}.
          
          Also note that once given to a borrow projection, a symbolic value
          can't get updated/expanded: this means that we don't need to save
          any meta-value here.
       *)
  | AEndedProjLoans of msymbolic_value * (msymbolic_value * aproj) list
      (** An ended projector of loans over a symbolic value.
      
          See the explanations for {!AProjLoans}
          
          Note that we keep the original symbolic value as a meta-value.
       *)
  | AEndedProjBorrows of msymbolic_value
      (** The only purpose of {!AEndedProjBorrows} is to store, for synthesis
          purposes, the symbolic value which was generated and given back upon
          ending the borrow.
       *)
  | AIgnoredProjBorrows
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_aproj";
        variety = "iter";
        ancestors = [ "iter_aproj_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_aproj";
        variety = "map";
        ancestors = [ "map_aproj_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

type region = RegionVarId.id Types.region [@@deriving show, ord]
type region_var_id = RegionVarId.id [@@deriving show, ord]
type region_id = RegionId.id [@@deriving show, ord]
type region_id_set = RegionId.Set.t [@@deriving show, ord]
type abstraction_id = AbstractionId.id [@@deriving show, ord]
type abstraction_id_set = AbstractionId.Set.t [@@deriving show, ord]

(** Ancestor for {!typed_avalue} iter visitor *)
class ['self] iter_typed_avalue_base =
  object (self : 'self)
    inherit [_] iter_aproj
    method visit_region_var_id : 'env -> region_var_id -> unit = fun _ _ -> ()

    method visit_region : 'env -> region -> unit =
      fun env r ->
        match r with
        | Static -> ()
        | Var rid -> self#visit_region_var_id env rid

    method visit_region_id : 'env -> region_id -> unit = fun _ _ -> ()

    method visit_region_id_set : 'env -> region_id_set -> unit =
      fun env ids -> RegionId.Set.iter (self#visit_region_id env) ids

    method visit_abstraction_id : 'env -> abstraction_id -> unit = fun _ _ -> ()

    method visit_abstraction_id_set : 'env -> abstraction_id_set -> unit =
      fun env ids -> AbstractionId.Set.iter (self#visit_abstraction_id env) ids
  end

(** Ancestor for {!typed_avalue} map visitor *)
class ['self] map_typed_avalue_base =
  object (self : 'self)
    inherit [_] map_aproj

    method visit_region_var_id : 'env -> region_var_id -> region_var_id =
      fun _ x -> x

    method visit_region : 'env -> region -> region =
      fun env r ->
        match r with
        | Static -> Static
        | Var rid -> Var (self#visit_region_var_id env rid)

    method visit_region_id : 'env -> region_id -> region_id = fun _ x -> x

    method visit_region_id_set : 'env -> region_id_set -> region_id_set =
      fun env ids -> RegionId.Set.map (self#visit_region_id env) ids

    method visit_abstraction_id : 'env -> abstraction_id -> abstraction_id =
      fun _ x -> x

    method visit_abstraction_id_set
        : 'env -> abstraction_id_set -> abstraction_id_set =
      fun env ids -> AbstractionId.Set.map (self#visit_abstraction_id env) ids
  end

(** Abstraction values are used inside of abstractions to properly model
    borrowing relations introduced by function calls.

    When calling a function, we lose information about the borrow graph:
    part of it is thus "abstracted" away.
*)
type avalue =
  | AAdt of adt_avalue
  | ABottom (* TODO: remove once we change the way internal borrows are ended *)
  | ALoan of aloan_content
  | ABorrow of aborrow_content
  | ASymbolic of aproj
  | AIgnored
      (** A value which doesn't contain borrows, or which borrows we
          don't own and thus ignore.

          In the comments, we display it as [_].
       *)

and adt_avalue = {
  variant_id : (VariantId.id option[@opaque]);
  field_values : typed_avalue list;
}

(** A loan content as stored in an abstraction.

    We use the children avalues for synthesis purposes: though not necessary
    to maintain the borrow graph, we maintain a structured representation of
    the avalues to synthesize values for the backward functions in the translation.

    Note that the children avalues are independent of the parent avalues.
    For instance, the child avalue contained in an {!AMutLoan} will likely
    contain other, independent loans.
*)
and aloan_content =
  | AMutLoan of loan_id * typed_avalue
      (** A mutable loan owned by an abstraction.

          The avalue is the child avalue.
         
          Example:
          ========
          {[
            fn f<'a>(...) -> &'a mut &'a mut u32;

            let px = f(...);
          ]}
          
          We get (after some symbolic exansion):
          {[
            abs0 {
              a_mut_loan l0 (a_mut_loan l1 _)
            }
            px -> mut_borrow l0 (mut_borrow @s1)
          ]}
       *)
  | ASharedLoan of loan_id_set * typed_value * typed_avalue
      (** A shared loan owned by an abstraction.

          The avalue is the child avalue.

          Example:
          ========
          {[
            fn f<'a>(...) -> &'a u32;

            let px = f(...);
          ]}
          
          We get:
          {[
            abs0 { a_shared_loan {l0} @s0 _ }
            px -> shared_loan l0
          ]}
     *)
  | AEndedMutLoan of {
      child : typed_avalue;
      given_back : typed_avalue;
      given_back_meta : mvalue;
    }
      (** An ended mutable loan in an abstraction.
          We need it because abstractions must keep track of the values
          we gave back to them, so that we can correctly instantiate
          backward functions.
          
          [given_back]: stores the projected given back value (useful when
          there are nested borrows: ending a loan might consume borrows which
          need to be projected in the abstraction).

          Rk.: *DO NOT* use [visit_AEndedMutLoan]. If we update the order of
          the arguments and you forget to swap them at the level of
          [visit_AEndedMutLoan], you will not notice it.          
      
          Example 1:
          ==========
          {[
            abs0 { a_mut_loan l0 _ }
            x -> mut_borrow l0 (U32 3)
          ]}
          
          After ending [l0]:
          
          {[
            abs0 { a_ended_mut_loan { child = _; given_back = _; given_back_meta = U32 3; }
            x -> ⊥
          ]}

          Example 2 (nested borrows):
          ===========================
          {[
            abs0 { a_mut_loan l0 _ }
            ... // abstraction containing a_mut_loan l1
            x -> mut_borrow l0 (mut_borrow l1 (U32 3))
          ]}

          After ending [l0]:

          {[
            abs0 {
              a_ended_mut_loan {
                child = _;
                given_back = a_mut_borrow l1 _;
                given_back_meta = (mut_borrow l1 (U32 3));
              }
            }
            ...
            x -> ⊥
          ]}
       *)
  | AEndedSharedLoan of typed_value * typed_avalue
      (** Similar to {!AEndedMutLoan} but in this case we don't consume given
          back values when the loan ends. We remember the shared value because
          it now behaves as a "regular" value (which might contain borrows we need
          to keep track of...).
       *)
  | AIgnoredMutLoan of loan_id option * typed_avalue
      (** An ignored mutable loan.
      
          We need to keep track of ignored mutable loans, because we may have
          to apply projections on the values given back to those loans (say
          you have a borrow of type [&'a mut &'b mut], in the abstraction 'b,
          the outer loan is ignored, however you need to keep track of it so
          that when ending the borrow corresponding to 'a you can correctly
          project on the inner given back value).

          Note that we need to do so only for borrows consumed by parent
          abstractions, hence the optional loan id.
       
          Example:
          ========
          {[
            fn f<'a,'b>(...) -> &'a mut &'b mut u32;
            let x = f(...);

            > abs'a { a_mut_loan l0 (a_ignored_mut_loan None _) _ }
            > abs'b { a_ignored_mut_loan (Some l0) (a_mut_loan l1 _) }
            > x -> mut_borrow l0 (mut_borrow l1 @s1)
          ]}

          If we end [l0]:
          {[
            abs'a { ... }
            abs'b {
              a_ended_ignored_mut_loan {
                child = a_mut_loan l1 _;
                given_back = a_mut_borrow l1 _;
                given_back_meta = mut_borrow l1 @s1
              }
            }
            x -> ⊥
          ]}

       *)
  | AEndedIgnoredMutLoan of {
      child : typed_avalue;
      given_back : typed_avalue;
      given_back_meta : mvalue;
    }
      (** Similar to {!AEndedMutLoan}, for ignored loans.
          See the comments for {!AIgnoredMutLoan}.

          Rk.: *DO NOT* use [visit_AEndedIgnoredMutLoan] (for the reason why,
          see the comments for {!AEndedMutLoan}).
       *)
  | AIgnoredSharedLoan of typed_avalue
      (** An ignored shared loan.
            
          Example:
          ========
          {[
            fn f<'a,'b>(...) -> &'a &'b u32;
            let x = f(...);

            > abs'a { a_shared_loan {l0} (shared_borrow l1) (a_ignored_shared_loan _) }
            > abs'b { a_ignored_shared_loan (a_shared_loan {l1} @s1 _) }
            > x -> shared_borrow l0
          ]}
       *)

(** Note that contrary to {!aloan_content}, here the children avalues are
    not independent of the parent avalues. For instance, a value
    [AMutBorrow (_, AMutBorrow (_, ...)] (ignoring the types) really is
    to be seen like a [mut_borrow ... (mut_borrow ...)] (i.e., it is a nested
    borrow).
    
    TODO: be more precise about the ignored borrows (keep track of the borrow
    ids)?
*)
and aborrow_content =
  | AMutBorrow of borrow_id * typed_avalue
      (** A mutable borrow owned by an abstraction.
      
          Is used when an abstraction "consumes" borrows, when giving borrows
          as arguments to a function.

          Example:
          ========
          {[
            fn f<'a>(px : &'a mut u32);

            > x -> mut_loan l0
            > px -> mut_borrow l0 (U32 0)

            f(move px);

            > x -> mut_loan l0
            > px -> ⊥
            > abs0 { a_mut_borrow l0 (U32 0) _ }
          ]}
     *)
  | ASharedBorrow of borrow_id
      (** A shared borrow owned by an abstraction.
    
          Example:
          ========
          {[
            fn f<'a>(px : &'a u32);

            > x -> shared_loan {l0} (U32 0)
            > px -> shared_borrow l0

            f(move px);

            > x -> shared_loan {l0} (U32 0)
            > px -> ⊥
            > abs0 { a_shared_borrow l0 _ }
          ]}
     *)
  | AIgnoredMutBorrow of borrow_id option * typed_avalue
      (** An ignored mutable borrow.
      
          We need to keep track of ignored mut borrows because when ending such
          borrows, we need to project the loans of the given back value to
          insert them in the proper abstractions.
          
          Note that we need to do so only for borrows consumed by parent
          abstractions (hence the optional borrow id).
          
          Rem.: we don't have an equivalent for shared borrows because if
          we ignore a shared borrow we don't need to keep track it (we directly
          use {!AProjSharedBorrow} to project the shared value).

          TODO: the explanations below are obsolete

          Example:
          ========
          {[
            fn f<'a,'b>(ppx : &'a mut &'b mut u32);

            > x -> mut_loan l0
            > px -> mut_loan l1
            > ppx -> mut_borrow l1 (mut_borrow l0 (U32 0))

            f(move ppx);

            > x -> mut_loan l0
            > px -> mut_loan l1
            > ppx -> ⊥
            > abs'a { a_mut_borrow l1 (a_ignored_mut_borrow None _) }
            > abs'b {parents={abs'a}} { a_ignored_mut_borrow (Some l1) (a_mut_borrow l0 _) }

            ... // abs'a ends

            > x -> mut_loan l0
            > px -> @s0
            > ppx -> ⊥
            > abs'b {
            >   a_ended_ignored_mut_borrow {
            >     child = a_mut_borrow l0 _;
            >     given_back = a_proj_loans (@s0 <: &'b mut u32) // <-- loan projector
            >   }
            > }

            ... // [@s0] gets expanded to [&mut l2 @s1]

            > x -> mut_loan l0
            > px -> &mut l2 @s1
            > ppx -> ⊥
            > abs'b {
            >   a_ended_ignored_mut_borrow {
            >     child = a_mut_borrow l0 _;
            >     given_back = a_mut_loan l2 _;
            >   }
            > }

          ]}

          Note that we could use [AIgnoredMutLoan] in the case the borrow id is not
          [None], which would allow us to simplify the rules (to not have rules
          to specifically handle the case of AIgnoredMutBorrow with Some borrow
          id) and also remove the AEndedIgnoredMutBorrow variant.
          For now, we prefer to be more precise that required.
       *)
  | AEndedMutBorrow of msymbolic_value * typed_avalue
      (** The sole purpose of {!AEndedMutBorrow} is to store the (symbolic) value
          that we gave back as a meta-value, to help with the synthesis.
       *)
  | AEndedSharedBorrow
      (** We don't really need {!AEndedSharedBorrow}: we simply want to be
          precise, and not insert ⊥ when ending borrows.
       *)
  | AEndedIgnoredMutBorrow of {
      child : typed_avalue;
      given_back : typed_avalue;
      given_back_meta : msymbolic_value;
          (** [given_back_meta] is used to store the (symbolic) value we gave back
              upon ending the borrow.

              Rk.: *DO NOT* use [visit_AEndedIgnoredMutLoan].
              See the comment for {!AEndedMutLoan}.
           *)
    }  (** See the explanations for {!AIgnoredMutBorrow} *)
  | AProjSharedBorrow of abstract_shared_borrows
      (** A projected shared borrow.

          When giving shared borrows as arguments to function calls, we
          introduce new borrows to keep track of the fact that the function
          might reborrow values inside. Note that as shared values are immutable,
          we don't really need to remember the structure of the shared values.

          Example:
          ========
          Below, when calling [f], we need to introduce one shared re-borrow per
          *inner* borrow (the borrows for 'b and 'c but not 'a) consumed by the
          function. Those reborrows are introduced by projecting over the shared
          value. For each one of those, we introduce an [abstract_shared_borrow]
          in the abstraction.
          {[
            fn f<'a,'b>(pppx : &'a &'b &'c mut u32);

            > x    -> mut_loan l0
            > px   -> shared_loan {l1} (mut_borrow l0 (U32 0))
            > ppx  -> shared_loan {l2} (shared_borrow l1)
            > pppx -> shared_borrow l2

            f(move pppx);

            > x    -> mut_loan l0
            > px   -> shared_loan {l1, l3, l4} (mut_borrow l0 (U32 0))
            > ppx  -> shared_loan {l2} (shared_borrow l1)
            > pppx -> ⊥
            > abs'a { a_shared_borrow {l2} }
            > abs'b { a_proj_shared_borrow {l3} } // l3 reborrows l1
            > abs'c { a_proj_shared_borrow {l4} } // l4 reborrows l0
          ]}

          Rem.: we introduce {!AProjSharedBorrow} only when we project a shared
          borrow *which is ignored* (i.e., the shared borrow doesn't belong to
          the current abstraction, in which case we still project the shared
          value). The reason is that if the shared borrow belongs to the
          abstraction, then by introducing a shared borrow inside the
          abstraction we make sure the whole value is shared (and thus
          immutable) for as long as the abstraction lives, meaning reborrowing
          subvalues is redundant. However, if the borrow doesn't belong to the
          abstraction, we need to project the shared values because it may
          contain some borrows which *do* belong to the current abstraction.

          TODO: maybe we should factorized [ASharedBorrow] and [AProjSharedBorrow].
       *)

(** Rem.: the of avalues is not to be understood in the same manner as for values.
    To be more precise, shared aloans have the borrow type (i.e., a shared aloan
    has type [& (mut) T] instead of [T]).
 *)
and typed_avalue = { value : avalue; ty : rty }
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_typed_avalue";
        variety = "iter";
        ancestors = [ "iter_typed_avalue_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_typed_avalue";
        variety = "map";
        ancestors = [ "map_typed_avalue_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

(** TODO: make those variants of [abs_kind] *)
type loop_abs_kind =
  | LoopSynthInput
      (** See {!abs_kind.SynthInput} - this abstraction is an input abstraction
          for a loop body. *)
  | LoopCall
      (** An abstraction introduced because we (re-)entered a loop, that we see
          like a function call. *)
[@@deriving show, ord]

(** The kind of an abstraction, which keeps track of its origin *)
type abs_kind =
  | FunCall of (FunCallId.id * RegionGroupId.id)
      (** The abstraction was introduced because of a function call.

          It contains he identifier of the function call which introduced this
          abstraction, as well as the id of the backward function this
          abstraction stands for (backward functions are identified by the group
          of regions to which they are associated). This is not used by the
          symbolic execution: this is only used for pretty-printing and
          debugging in the symbolic AST, generated by the symbolic
          execution.
       *)
  | SynthInput of RegionGroupId.id
      (** The abstraction keeps track of the input values of the function
          we are currently synthesizing.

          We introduce one abstraction per (group of) region(s) in the function
          signature, the region group id identifies this group. Similarly to
          the [FunCall] case, this is not used by the symbolic execution.
       *)
  | SynthRet of RegionGroupId.id
      (** The abstraction "absorbed" the value returned by the function we
          are currently synthesizing

          See the explanations for [SynthInput].
       *)
  | Loop of (LoopId.id * RegionGroupId.id option * loop_abs_kind)
      (** The abstraction corresponds to a loop.

          The region group id is initially [None].
          After we computed a fixed point, we give a unique region group
          identifier for each loop abstraction.
       *)
  | Identity
      (** An identity abstraction, which only consumes and provides shared
          borrows/loans.

          We introduce them to abstract the context a bit, for instance
          to compute fixed-points.
        *)
[@@deriving show, ord]

(** Ancestor for {!abs} iter visitor *)
class ['self] iter_abs_base =
  object (_self : 'self)
    inherit [_] iter_typed_avalue
    method visit_abs_kind : 'env -> abs_kind -> unit = fun _ _ -> ()
  end

(** Ancestor for {!abs} map visitor *)
class ['self] map_abs_base =
  object (_self : 'self)
    inherit [_] map_typed_avalue
    method visit_abs_kind : 'env -> abs_kind -> abs_kind = fun _ x -> x
  end

(** Abstractions model the parts in the borrow graph where the borrowing relations
    have been abstracted because of a function call.
    
    In order to model the relations between the borrows, we use "abstraction values",
    which are a special kind of value.
*)
type abs = {
  abs_id : abstraction_id;
  kind : abs_kind;
  can_end : bool;
      (** Controls whether the region can be ended or not.
          
          This allows to "pin" some regions, and is useful when generating
          backward functions.
          
          For instance, if we have: [fn f<'a, 'b>(...) -> (&'a mut T, &'b mut T)],
          when generating the backward function for 'a, we have to make sure we
          don't need to end the return region for 'b (if it is the case, it means
          the function doesn't borrow check).
       *)
  parents : abstraction_id_set;  (** The parent abstractions *)
  original_parents : abstraction_id list;
      (** The original list of parents, ordered. This is used for synthesis. TODO: remove? *)
  regions : region_id_set;  (** Regions owned by this abstraction *)
  ancestors_regions : region_id_set;
      (** Union of the regions owned by this abstraction's ancestors (not
          including the regions of this abstraction itself) *)
  avalues : typed_avalue list;  (** The values in this abstraction *)
}
[@@deriving
  show,
    ord,
    visitors
      {
        name = "iter_abs";
        variety = "iter";
        ancestors = [ "iter_abs_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      },
    visitors
      {
        name = "map_abs";
        variety = "map";
        ancestors = [ "map_abs_base" ];
        nude = true (* Don't inherit {!VisitorsRuntime.iter} *);
        concrete = true;
      }]

(** A symbolic expansion
    
    A symbolic expansion doesn't represent a value, but rather an operation
    that we apply to values.
    
    TODO: this should rather be name "expanded_symbolic"
 *)
type symbolic_expansion =
  | SeLiteral of literal
  | SeAdt of (VariantId.id option * symbolic_value list)
  | SeMutRef of BorrowId.id * symbolic_value
  | SeSharedRef of BorrowId.Set.t * symbolic_value
[@@deriving show]
