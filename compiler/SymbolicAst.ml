(** The "symbolic" AST is the AST directly generated by the symbolic execution.
    It is very rough and meant to be extremely straightforward to build during
    the symbolic execution: we later apply transformations to generate the
    pure AST that we export. *)

module T = Types
module V = Values
module E = Expressions
module A = LlbcAst

(** "Meta"-place: a place stored as meta-data.

    Whenever we need to introduce new symbolic variables, for instance because
    of symbolic expansions, we try to store a "place", which gives information
    about the origin of the values (this place information comes from assignment
    information, etc.).
    We later use this place information to generate meaningful name, to prettify
    the generated code.
 *)
type mplace = {
  bv : Contexts.var_binder;
      (** It is important that we store the binder, and not just the variable id,
          because the most important information in a place is the name of the
          variable!
       *)
  projection : E.projection;
      (** We store the projection because we can, but it is actually not that useful *)
}

type call_id =
  | Fun of A.fun_id * V.FunCallId.id
      (** A "regular" function (i.e., a function which is not a primitive operation) *)
  | Unop of E.unop
  | Binop of E.binop
[@@deriving show, ord]

type call = {
  call_id : call_id;
  abstractions : V.AbstractionId.id list;
  type_params : T.ety list;
  args : V.typed_value list;
  args_places : mplace option list;  (** Meta information *)
  dest : V.symbolic_value;
  dest_place : mplace option;  (** Meta information *)
}

(** Meta information, not necessary for synthesis but useful to guide it to
    generate a pretty output.
 *)

type meta =
  | Assignment of mplace * V.typed_value * mplace option
      (** We generated an assignment (destination, assigned value, src) *)

(** **Rk.:** here, {!expression} is not at all equivalent to the expressions
    used in LLBC: they are a first step towards lambda-calculus expressions.
 *)
type expression =
  | Return of V.typed_value option
      (** There are two cases:
          - the AST is for a forward function: the typed value should contain
            the value which was in the return variable
          - the AST is for a backward function: the typed value should be [None]
       *)
  | Panic
  | FunCall of call * expression
  | EndAbstraction of V.abs * expression
  | EvalGlobal of A.GlobalDeclId.id * V.symbolic_value * expression
      (** Evaluate a global to a fresh symbolic value *)
  | Expansion of mplace option * V.symbolic_value * expansion
      (** Expansion of a symbolic value.
    
          The place is "meta": it gives the path to the symbolic value (if available)
          which got expanded (this path is available when the symbolic expansion
          comes from a path evaluation, during an assignment for instance).
          We use it to compute meaningful names for the variables we introduce,
          to prettify the generated code.
       *)
  | Meta of meta * expression  (** Meta information *)

and expansion =
  | ExpandNoBranch of V.symbolic_expansion * expression
      (** A symbolic expansion which doesn't generate a branching.
          Includes:
          - concrete expansion
          - borrow expansion
          *Doesn't* include:
          - expansion of ADTs with one variant
       *)
  | ExpandAdt of
      (T.VariantId.id option * V.symbolic_value list * expression) list
      (** ADT expansion *)
  | ExpandBool of expression * expression
      (** A boolean expansion (i.e, an [if ... then ... else ...]) *)
  | ExpandInt of
      T.integer_type * (V.scalar_value * expression) list * expression
      (** An integer expansion (i.e, a switch over an integer). The last
          expression is for the "otherwise" branch. *)
