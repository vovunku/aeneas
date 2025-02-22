(** Define base utilities for the extraction *)

open Pure
open TranslateCore
module C = Contexts
module RegionVarId = T.RegionVarId
module F = Format

(** The local logger *)
let log = L.pure_to_extract_log

type region_group_info = {
  id : RegionGroupId.id;
      (** The id of the region group.
          Note that a simple way of generating unique names for backward
          functions is to use the region group ids.
       *)
  region_names : string option list;
      (** The names of the region variables included in this group.
          Note that names are not always available...
       *)
}

module StringSet = Collections.MakeSet (Collections.OrderedString)
module StringMap = Collections.MakeMap (Collections.OrderedString)

type name = Names.name
type type_name = Names.type_name
type global_name = Names.global_name
type fun_name = Names.fun_name

(** Characterizes a declaration.

    Is in particular useful to derive the proper keywords to introduce the
    declarations/definitions.
 *)
type decl_kind =
  | SingleNonRec
      (** A single, non-recursive definition.

          F*:  [let x = ...]
          Coq: [Definition x := ...]
       *)
  | SingleRec
      (** A single, recursive definition.

          F*:  [let rec x = ...]
          Coq: [Fixpoint x := ...]
       *)
  | MutRecFirst
      (** The first definition of a group of mutually-recursive definitions.

          F*:  [type x0 = ... and x1 = ...]
          Coq: [Fixpoint x0 := ... with x1 := ...]
       *)
  | MutRecInner
      (** An inner definition in a group of mutually-recursive definitions. *)
  | MutRecLast
      (** The last definition in a group of mutually-recursive definitions.

          We need this because in some theorem provers like Coq, we need to
          delimit group of mutually recursive definitions (in particular, we
          need to insert an end delimiter).
       *)
  | Assumed
      (** An assumed definition.

         F*:  [assume val x]
         Coq: [Axiom x : Type.]
      *)
  | Declared
      (** Declare a type in an interface or a module signature.

          Rem.: for now, in Coq, we don't declare module signatures: we
          thus assume the corresponding declarations.

          F*:  [val x : Type0]
          Coq: [Axiom x : Type.]
       *)

(** Return [true] if the declaration is the last from its group of declarations.

    We need this because in some provers (e.g., Coq), we need to delimit the
    end of a (group of) definition(s) (in Coq: with a ".").
 *)
let decl_is_last_from_group (kind : decl_kind) : bool =
  match kind with
  | SingleNonRec | SingleRec | MutRecLast | Assumed | Declared -> true
  | MutRecFirst | MutRecInner -> false

let decl_is_from_rec_group (kind : decl_kind) : bool =
  match kind with
  | SingleNonRec | Assumed | Declared -> false
  | SingleRec | MutRecFirst | MutRecInner | MutRecLast -> true

let decl_is_from_mut_rec_group (kind : decl_kind) : bool =
  match kind with
  | SingleNonRec | SingleRec | Assumed | Declared -> false
  | MutRecFirst | MutRecInner | MutRecLast -> true

let decl_is_first_from_group (kind : decl_kind) : bool =
  match kind with
  | SingleNonRec | SingleRec | MutRecFirst | Assumed | Declared -> true
  | MutRecLast | MutRecInner -> false

(** Return [true] if the declaration is not the last from its group of declarations.

    We need this because in some provers (e.g., HOL4), we need to delimit
    the inner declarations (with `/\` for instance).
 *)
let decl_is_not_last_from_group (kind : decl_kind) : bool =
  not (decl_is_last_from_group kind)

(* TODO: this should a module we give to a functor! *)

type type_decl_kind = Enum | Struct

(** A formatter's role is twofold:
    1. Come up with name suggestions.
    For instance, provided some information about a function (its basename,
    information about the region group, etc.) it should come up with an
    appropriate name for the forward/backward function.

    It can of course apply many transformations, like changing to camel case/
    snake case, adding prefixes/suffixes, etc.

    2. Format some specific terms, like constants.
 *)
type formatter = {
  bool_name : string;
  char_name : string;
  int_name : integer_type -> string;
  str_name : string;
  type_decl_kind_to_qualif :
    decl_kind -> type_decl_kind option -> string option;
      (** Compute the qualified for a type definition/declaration.

          For instance: "type", "and", etc.

          Remark: can return [None] for some backends like HOL4.
       *)
  fun_decl_kind_to_qualif : decl_kind -> string option;
      (** Compute the qualified for a function definition/declaration.

          For instance: "let", "let rec", "and", etc.

          Remark: can return [None] for some backends like HOL4.
       *)
  field_name : name -> FieldId.id -> string option -> string;
      (** Inputs:
          - type name
          - field id
          - field name

          Note that fields don't always have names, but we still need to
          generate some names if we want to extract the structures to records...
          We might want to extract such structures to tuples, later, but field
          access then causes trouble because not all provers accept syntax like
          [x.3] where [x] is a tuple.
       *)
  variant_name : name -> string -> string;
      (** Inputs:
          - type name
          - variant name
       *)
  struct_constructor : name -> string;
      (** Structure constructors are used when constructing structure values.

          For instance, in F*:
          {[
            type pair = { x : nat; y : nat }
            let p : pair = Mkpair 0 1
          ]}

          Inputs:
          - type name
       *)
  type_name : type_name -> string;
      (** Provided a basename, compute a type name. *)
  global_name : global_name -> string;
      (** Provided a basename, compute a global name. *)
  fun_name :
    fun_name ->
    int ->
    LoopId.id option ->
    int ->
    region_group_info option ->
    bool * int ->
    string;
      (** Compute the name of a regular (non-assumed) function.

          Inputs:
          - function basename (TODO: shouldn't appear for assumed functions?...)
          - number of loops in the function (useful to check if we need to use
            indices to derive unique names for the loops for instance - if there is
            exactly one loop, we don't need to use indices)
          - loop id (if pertinent)
          - number of region groups
          - region group information in case of a backward function
            ([None] if forward function)
          - pair:
            - do we generate the forward function (it may have been filtered)?
            - the number of *extracted backward functions* (same comment as for
              the number of loops)
              The number of extracted backward functions if not necessarily
              equal to the number of region groups, because we may have
              filtered some of them.
          TODO: use the fun id for the assumed functions.
       *)
  termination_measure_name :
    A.FunDeclId.id -> fun_name -> int -> LoopId.id option -> string;
      (** Generates the name of the termination measure used to prove/reason about
          termination. The generated code uses this clause where needed,
          but its body must be defined by the user.

          F* and Lean only.

          Inputs:
          - function id: this is especially useful to identify whether the
            function is an assumed function or a local function
          - function basename
          - the number of loops in the parent function. This is used for
            the same purpose as in {!field:fun_name}.
          - loop identifier, if this is for a loop
       *)
  decreases_proof_name :
    A.FunDeclId.id -> fun_name -> int -> LoopId.id option -> string;
      (** Generates the name of the proof used to prove/reason about
          termination. The generated code uses this clause where needed,
          but its body must be defined by the user.

          Lean only.

          Inputs:
          - function id: this is especially useful to identify whether the
            function is an assumed function or a local function
          - function basename
          - the number of loops in the parent function. This is used for
            the same purpose as in {!field:fun_name}.
          - loop identifier, if this is for a loop
       *)
  opaque_pre : unit -> string;
      (** TODO: obsolete, remove.

          The prefix to use for opaque definitions.

          We need this because for some backends like Lean and Coq, we group
          opaque definitions in module signatures, meaning that using those
          definitions requires to prefix them with a module parameter name (such
          as "opaque_defs.").

          For instance, if we have an opaque function [f : int -> int], which
          is used by the non-opaque function [g], we would generate (in Coq):
          {[
            (* The module signature declaring the opaque definitions *)
            module type OpaqueDefs = {
              f_fwd : int -> int
              ... (* Other definitions *)
            }

            (* The definitions generated for the non-opaque definitions *)
            module Funs (opaque: OpaqueDefs) = {
              let g ... =
                ...
                opaque_defs.f_fwd
                ...
            }
          ]}

          Upon using [f] in [g], we don't directly use the the name "f_fwd",
          but prefix it with the "opaque_defs." identifier.
       *)
  var_basename : StringSet.t -> string option -> ty -> string;
      (** Generates a variable basename.

          Inputs:
          - the set of names used in the context so far
          - the basename we got from the symbolic execution, if we have one
          - the type of the variable (can be useful for heuristics, in order
            not to always use "x" for instance, whenever naming anonymous
            variables)

          Note that once the formatter generated a basename, we add an index
          if necessary to prevent name clashes: the burden of name clashes checks
          is thus on the caller's side.
       *)
  type_var_basename : StringSet.t -> string -> string;
      (** Generates a type variable basename. *)
  const_generic_var_basename : StringSet.t -> string -> string;
      (** Generates a const generic variable basename. *)
  append_index : string -> int -> string;
      (** Appends an index to a name - we use this to generate unique
          names: when doing so, the role of the formatter is just to concatenate
          indices to names, the responsability of finding a proper index is
          delegated to helper functions.
       *)
  extract_literal : F.formatter -> bool -> literal -> unit;
      (** Format a constant value.

          Inputs:
          - formatter
          - [inside]: if [true], the value should be wrapped in parentheses
            if it is made of an application (ex.: [U32 3])
          - the constant value
       *)
  extract_unop :
    (bool -> texpression -> unit) ->
    F.formatter ->
    bool ->
    unop ->
    texpression ->
    unit;
      (** Format a unary operation

          Inputs:
          - a formatter for expressions (called on the argument of the unop)
          - extraction context (see below)
          - formatter
          - expression formatter
          - [inside]
          - unop
          - argument
       *)
  extract_binop :
    (bool -> texpression -> unit) ->
    F.formatter ->
    bool ->
    E.binop ->
    integer_type ->
    texpression ->
    texpression ->
    unit;
      (** Format a binary operation

          Inputs:
          - a formatter for expressions (called on the arguments of the binop)
          - extraction context (see below)
          - formatter
          - expression formatter
          - [inside]
          - binop
          - argument 0
          - argument 1
       *)
}

(** We use identifiers to look for name clashes *)
type id =
  | GlobalId of A.GlobalDeclId.id
  | FunId of fun_id
  | TerminationMeasureId of (A.fun_id * LoopId.id option)
      (** The definition which provides the decreases/termination measure.
          We insert calls to this clause to prove/reason about termination:
          the body of those clauses must be defined by the user, in the
          proper files.

          More specifically:
          - in F*, this is the content of the [decreases] clause.
            Example:
            ========
            {[
              let rec sum (ls : list nat) : Tot nat (decreases ls) = ...
            ]}
          - in Lean, this is the content of the [termination_by] clause.
       *)
  | DecreasesProofId of (A.fun_id * LoopId.id option)
      (** The definition which provides the decreases/termination proof.
          We insert calls to this clause to prove/reason about termination:
          the body of those clauses must be defined by the user, in the
          proper files.

          More specifically:
          - F* doesn't use this.
          - in Lean, this is the tactic used by the [decreases_by] annotations.
       *)
  | TypeId of type_id
  | StructId of type_id
      (** We use this when we manipulate the names of the structure
          constructors.

          For instance, in F*:
          {[
            type pair = { x: nat; y : nat }
            let p : pair = Mkpair 0 1
          ]}
       *)
  | VariantId of type_id * VariantId.id
      (** If often happens that variant names must be unique (it is the case in
          F* ) which is why we register them here.
       *)
  | FieldId of type_id * FieldId.id
      (** If often happens that in the case of structures, the field names
          must be unique (it is the case in F* ) which is why we register
          them here.
       *)
  | TypeVarId of TypeVarId.id
  | ConstGenericVarId of ConstGenericVarId.id
  | VarId of VarId.id
  | UnknownId
      (** Used for stored various strings like keywords, definitions which
          should always be in context, etc. and which can't be linked to one
          of the above.
       *)
[@@deriving show, ord]

module IdOrderedType = struct
  type t = id

  let compare = compare_id
  let to_string = show_id
  let pp_t = pp_id
  let show_t = show_id
end

module IdMap = Collections.MakeMap (IdOrderedType)
module IdSet = Collections.MakeSet (IdOrderedType)

(** The names map stores the mappings from names to identifiers and vice-versa.

    We use it for lookups (during the translation) and to check for name clashes.

    [id_to_name] is for debugging.
  *)
type names_map = {
  id_to_name : string IdMap.t;
  name_to_id : id StringMap.t;
      (** The name to id map is used to look for name clashes, and generate nice
          debugging messages: if there is a name clash, it is useful to know
          precisely which identifiers are mapped to the same name...
       *)
  names_set : StringSet.t;
  opaque_ids : IdSet.t;
      (** TODO: this is obsolete. Remove.

          The set of opaque definitions.

          See {!formatter.opaque_pre} for detailed explanations about why
          we need to know which definitions are opaque to compute names.

          Also note that the opaque ids don't contain the ids of the assumed
          definitions. In practice, assumed definitions are opaque_defs. However, they
          are not grouped in the opaque module, meaning we never need to
          prefix them (with, say, "opaque_defs."): we thus consider them as non-opaque
          with regards to the names map.
       *)
}

let names_map_add (id_to_string : id -> string) (is_opaque : bool) (id : id)
    (name : string) (nm : names_map) : names_map =
  (* Check if there is a clash *)
  (match StringMap.find_opt name nm.name_to_id with
  | None -> () (* Ok *)
  | Some clash ->
      (* There is a clash: print a nice debugging message for the user *)
      let id1 = "\n- " ^ id_to_string clash in
      let id2 = "\n- " ^ id_to_string id in
      let err =
        "Name clash detected: the following identifiers are bound to the same \
         name \"" ^ name ^ "\":" ^ id1 ^ id2
      in
      log#serror err;
      raise (Failure err));
  (* Sanity check *)
  assert (not (StringSet.mem name nm.names_set));
  (* Insert *)
  let id_to_name = IdMap.add id name nm.id_to_name in
  let name_to_id = StringMap.add name id nm.name_to_id in
  let names_set = StringSet.add name nm.names_set in
  let opaque_ids =
    if is_opaque then IdSet.add id nm.opaque_ids else nm.opaque_ids
  in
  { id_to_name; name_to_id; names_set; opaque_ids }

let names_map_add_assumed_type (id_to_string : id -> string) (id : assumed_ty)
    (name : string) (nm : names_map) : names_map =
  let is_opaque = false in
  names_map_add id_to_string is_opaque (TypeId (Assumed id)) name nm

let names_map_add_assumed_struct (id_to_string : id -> string) (id : assumed_ty)
    (name : string) (nm : names_map) : names_map =
  let is_opaque = false in
  names_map_add id_to_string is_opaque (StructId (Assumed id)) name nm

let names_map_add_assumed_variant (id_to_string : id -> string)
    (id : assumed_ty) (variant_id : VariantId.id) (name : string)
    (nm : names_map) : names_map =
  let is_opaque = false in
  names_map_add id_to_string is_opaque
    (VariantId (Assumed id, variant_id))
    name nm

let names_map_add_function (id_to_string : id -> string) (is_opaque : bool)
    (fid : fun_id) (name : string) (nm : names_map) : names_map =
  names_map_add id_to_string is_opaque (FunId fid) name nm

(** The unsafe names map stores mappings from identifiers to names which might
    collide. For some backends and some names, it might be acceptable to have
    collisions. For instance, in Lean, different records can have fields with
    the same name because Lean uses the typing information to resolve the
    ambiguities.

    This map complements the {!names_map}, which checks for collisions.
  *)
type unsafe_names_map = { id_to_name : string IdMap.t }

let unsafe_names_map_add (id : id) (name : string) (nm : unsafe_names_map) :
    unsafe_names_map =
  { id_to_name = IdMap.add id name nm.id_to_name }

(** Make a (variable) basename unique (by adding an index).

    We do this in an inefficient manner (by testing all indices starting from
    0) but it shouldn't be a bottleneck.

    Also note that at some point, we thought about trying to reuse names of
    variables which are not used anymore, like here:
    {[
      let x = ... in
      ...
      let x0 = ... in // We could use the name "x" if [x] is not used below
      ...
    ]}

    However it is a good idea to keep things as they are for F*: as F* is
    designed for extrinsic proofs, a proof about a function follows this
    function's structure. The consequence is that we often end up
    copy-pasting function bodies. As in the proofs (in assertions and
    when calling lemmas) we often need to talk about the "past" (i.e.,
    previous values), it is very useful to generate code where all variable
    names are assigned at most once.

    [append]: function to append an index to a string
 *)
let basename_to_unique (names_set : StringSet.t)
    (append : string -> int -> string) (basename : string) : string =
  let rec gen (i : int) : string =
    let s = append basename i in
    if StringSet.mem s names_set then gen (i + 1) else s
  in
  if StringSet.mem basename names_set then gen 0 else basename

type fun_name_info = { keep_fwd : bool; num_backs : int }

(** Extraction context.

    Note that the extraction context contains information coming from the
    LLBC AST (not only the pure AST). This is useful for naming, for instance:
    we use the region information to generate the names of the backward
    functions, etc.
 *)
type extraction_ctx = {
  trans_ctx : trans_ctx;
  names_map : names_map;
      (** The map for id to names, where we forbid name collisions
          (ex.: we always forbid function name collisions). *)
  unsafe_names_map : unsafe_names_map;
      (** The map for id to names, where we allow name collisions
          (ex.: we might allow record field name collisions). *)
  fmt : formatter;
  indent_incr : int;
      (** The indent increment we insert whenever we need to indent more *)
  use_opaque_pre : bool;
      (** Do we use the "opaque_defs." prefix for the opaque definitions?

          Opaque function definitions might refer opaque types: if we are in the
          opaque module, we musn't use the "opaque_defs." prefix, otherwise we
          use it.
          Also see {!names_map.opaque_ids}.
       *)
  use_dep_ite : bool;
      (** For Lean: do we use dependent-if then else expressions?

          Example:
          {[
            if h: b then ... else ...
            -- ^^
            -- makes the if then else dependent
          ]}
        *)
  fun_name_info : fun_name_info PureUtils.RegularFunIdMap.t;
      (** Information used to filter and name functions - we use it
          to print comments in the generated code, to help link
          the generated code to the original code (information such
          as: "this function is the backward function of ...", or
          "this function is the merged forward/backward function of ..."
          in case a Rust function only has one backward translation
          and we filter the forward function because it returns unit.
        *)
}

(** Debugging function, used when communicating name collisions to the user,
    and also to print ids for internal debugging (in case of lookup miss for
    instance).
 *)
let id_to_string (id : id) (ctx : extraction_ctx) : string =
  let global_decls = ctx.trans_ctx.global_context.global_decls in
  let fun_decls = ctx.trans_ctx.fun_context.fun_decls in
  let type_decls = ctx.trans_ctx.type_context.type_decls in
  (* TODO: factorize the pretty-printing with what is in PrintPure *)
  let get_type_name (id : type_id) : string =
    match id with
    | AdtId id ->
        let def = TypeDeclId.Map.find id type_decls in
        Print.name_to_string def.name
    | Assumed aty -> show_assumed_ty aty
    | Tuple -> raise (Failure "Unreachable")
  in
  match id with
  | GlobalId gid ->
      let name = (A.GlobalDeclId.Map.find gid global_decls).name in
      "global name: " ^ Print.global_name_to_string name
  | FunId fid -> (
      match fid with
      | FromLlbc (fid, lp_id, rg_id) ->
          let fun_name =
            match fid with
            | Regular fid ->
                Print.fun_name_to_string
                  (A.FunDeclId.Map.find fid fun_decls).name
            | Assumed aid -> A.show_assumed_fun_id aid
          in

          let lp_kind =
            match lp_id with
            | None -> ""
            | Some lp_id -> "loop " ^ LoopId.to_string lp_id ^ ", "
          in

          let fwd_back_kind =
            match rg_id with
            | None -> "forward"
            | Some rg_id -> "backward " ^ RegionGroupId.to_string rg_id
          in
          "fun name (" ^ lp_kind ^ fwd_back_kind ^ "): " ^ fun_name
      | Pure fid -> PrintPure.pure_assumed_fun_id_to_string fid)
  | DecreasesProofId (fid, lid) ->
      let fun_name =
        match fid with
        | Regular fid ->
            Print.fun_name_to_string (A.FunDeclId.Map.find fid fun_decls).name
        | Assumed aid -> A.show_assumed_fun_id aid
      in
      let loop =
        match lid with
        | None -> ""
        | Some lid -> ", loop: " ^ LoopId.to_string lid
      in
      "decreases proof for function: " ^ fun_name ^ loop
  | TerminationMeasureId (fid, lid) ->
      let fun_name =
        match fid with
        | Regular fid ->
            Print.fun_name_to_string (A.FunDeclId.Map.find fid fun_decls).name
        | Assumed aid -> A.show_assumed_fun_id aid
      in
      let loop =
        match lid with
        | None -> ""
        | Some lid -> ", loop: " ^ LoopId.to_string lid
      in
      "termination measure for function: " ^ fun_name ^ loop
  | TypeId id -> "type name: " ^ get_type_name id
  | StructId id -> "struct constructor of: " ^ get_type_name id
  | VariantId (id, variant_id) ->
      let variant_name =
        match id with
        | Tuple -> raise (Failure "Unreachable")
        | Assumed Result ->
            if variant_id = result_return_id then "@result::Return"
            else if variant_id = result_fail_id then "@result::Fail"
            else raise (Failure "Unreachable")
        | Assumed Error ->
            if variant_id = error_failure_id then "@error::Failure"
            else if variant_id = error_out_of_fuel_id then "@error::OutOfFuel"
            else raise (Failure "Unreachable")
        | Assumed Option ->
            if variant_id = option_some_id then "@option::Some"
            else if variant_id = option_none_id then "@option::None"
            else raise (Failure "Unreachable")
        | Assumed (State | Vec | Fuel | Array | Slice | Str | Range) ->
            raise (Failure "Unreachable")
        | AdtId id -> (
            let def = TypeDeclId.Map.find id type_decls in
            match def.kind with
            | Struct _ | Opaque -> raise (Failure "Unreachable")
            | Enum variants ->
                let variant = VariantId.nth variants variant_id in
                Print.name_to_string def.name ^ "::" ^ variant.variant_name)
      in
      "variant name: " ^ variant_name
  | FieldId (id, field_id) ->
      let field_name =
        match id with
        | Tuple -> raise (Failure "Unreachable")
        | Assumed
            ( State | Result | Error | Fuel | Option | Vec | Array | Slice | Str
            | Range ) ->
            (* We can't directly have access to the fields of those types *)
            raise (Failure "Unreachable")
        | AdtId id -> (
            let def = TypeDeclId.Map.find id type_decls in
            match def.kind with
            | Enum _ | Opaque -> raise (Failure "Unreachable")
            | Struct fields ->
                let field = FieldId.nth fields field_id in
                let field_name =
                  match field.field_name with
                  | None -> FieldId.to_string field_id
                  | Some name -> name
                in
                Print.name_to_string def.name ^ "." ^ field_name)
      in
      "field name: " ^ field_name
  | UnknownId -> "keyword"
  | TypeVarId id -> "type_var_id: " ^ TypeVarId.to_string id
  | ConstGenericVarId id ->
      "const_generic_var_id: " ^ ConstGenericVarId.to_string id
  | VarId id -> "var_id: " ^ VarId.to_string id

(** We might not check for collisions for some specific ids (ex.: field names) *)
let allow_collisions (id : id) : bool =
  match id with
  | FieldId (_, _) -> !Config.record_fields_short_names
  | _ -> false

let ctx_add (is_opaque : bool) (id : id) (name : string) (ctx : extraction_ctx)
    : extraction_ctx =
  (* We do not use the same name map if we allow/disallow collisions *)
  if allow_collisions id then (
    assert (not is_opaque);
    {
      ctx with
      unsafe_names_map = unsafe_names_map_add id name ctx.unsafe_names_map;
    })
  else
    (* The id_to_string function to print nice debugging messages if there are
     * collisions *)
    let id_to_string (id : id) : string = id_to_string id ctx in
    let names_map =
      names_map_add id_to_string is_opaque id name ctx.names_map
    in
    { ctx with names_map }

(** [with_opaque_pre]: if [true] and the definition is opaque, add the opaque prefix *)
let ctx_get (with_opaque_pre : bool) (id : id) (ctx : extraction_ctx) : string =
  (* We do not use the same name map if we allow/disallow collisions *)
  if allow_collisions id then IdMap.find id ctx.unsafe_names_map.id_to_name
  else
    match IdMap.find_opt id ctx.names_map.id_to_name with
    | Some s ->
        let is_opaque = IdSet.mem id ctx.names_map.opaque_ids in
        if with_opaque_pre && is_opaque then ctx.fmt.opaque_pre () ^ s else s
    | None ->
        log#serror ("Could not find: " ^ id_to_string id ctx);
        raise Not_found

let ctx_get_global (with_opaque_pre : bool) (id : A.GlobalDeclId.id)
    (ctx : extraction_ctx) : string =
  ctx_get with_opaque_pre (GlobalId id) ctx

let ctx_get_function (with_opaque_pre : bool) (id : fun_id)
    (ctx : extraction_ctx) : string =
  ctx_get with_opaque_pre (FunId id) ctx

let ctx_get_local_function (with_opaque_pre : bool) (id : A.FunDeclId.id)
    (lp : LoopId.id option) (rg : RegionGroupId.id option)
    (ctx : extraction_ctx) : string =
  ctx_get_function with_opaque_pre (FromLlbc (Regular id, lp, rg)) ctx

let ctx_get_type (with_opaque_pre : bool) (id : type_id) (ctx : extraction_ctx)
    : string =
  assert (id <> Tuple);
  ctx_get with_opaque_pre (TypeId id) ctx

let ctx_get_local_type (with_opaque_pre : bool) (id : TypeDeclId.id)
    (ctx : extraction_ctx) : string =
  ctx_get_type with_opaque_pre (AdtId id) ctx

let ctx_get_assumed_type (id : assumed_ty) (ctx : extraction_ctx) : string =
  (* In practice, the assumed types are opaque. However, assumed types
     are never grouped in the opaque module, meaning we never need to
     prefix them: we thus consider them as non-opaque with regards to the
     names map.
  *)
  let is_opaque = false in
  ctx_get_type is_opaque (Assumed id) ctx

let ctx_get_var (id : VarId.id) (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (VarId id) ctx

let ctx_get_type_var (id : TypeVarId.id) (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (TypeVarId id) ctx

let ctx_get_const_generic_var (id : ConstGenericVarId.id) (ctx : extraction_ctx)
    : string =
  let is_opaque = false in
  ctx_get is_opaque (ConstGenericVarId id) ctx

let ctx_get_field (type_id : type_id) (field_id : FieldId.id)
    (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (FieldId (type_id, field_id)) ctx

let ctx_get_struct (with_opaque_pre : bool) (def_id : type_id)
    (ctx : extraction_ctx) : string =
  ctx_get with_opaque_pre (StructId def_id) ctx

let ctx_get_variant (def_id : type_id) (variant_id : VariantId.id)
    (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (VariantId (def_id, variant_id)) ctx

let ctx_get_decreases_proof (def_id : A.FunDeclId.id)
    (loop_id : LoopId.id option) (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (DecreasesProofId (Regular def_id, loop_id)) ctx

let ctx_get_termination_measure (def_id : A.FunDeclId.id)
    (loop_id : LoopId.id option) (ctx : extraction_ctx) : string =
  let is_opaque = false in
  ctx_get is_opaque (TerminationMeasureId (Regular def_id, loop_id)) ctx

(** Generate a unique type variable name and add it to the context *)
let ctx_add_type_var (basename : string) (id : TypeVarId.id)
    (ctx : extraction_ctx) : extraction_ctx * string =
  let is_opaque = false in
  let name = ctx.fmt.type_var_basename ctx.names_map.names_set basename in
  let name =
    basename_to_unique ctx.names_map.names_set ctx.fmt.append_index name
  in
  let ctx = ctx_add is_opaque (TypeVarId id) name ctx in
  (ctx, name)

(** Generate a unique const generic variable name and add it to the context *)
let ctx_add_const_generic_var (basename : string) (id : ConstGenericVarId.id)
    (ctx : extraction_ctx) : extraction_ctx * string =
  let is_opaque = false in
  let name =
    ctx.fmt.const_generic_var_basename ctx.names_map.names_set basename
  in
  let name =
    basename_to_unique ctx.names_map.names_set ctx.fmt.append_index name
  in
  let ctx = ctx_add is_opaque (ConstGenericVarId id) name ctx in
  (ctx, name)

(** See {!ctx_add_type_var} *)
let ctx_add_type_vars (vars : (string * TypeVarId.id) list)
    (ctx : extraction_ctx) : extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (name, id) -> ctx_add_type_var name id ctx)
    ctx vars

(** Generate a unique variable name and add it to the context *)
let ctx_add_var (basename : string) (id : VarId.id) (ctx : extraction_ctx) :
    extraction_ctx * string =
  let is_opaque = false in
  let name =
    basename_to_unique ctx.names_map.names_set ctx.fmt.append_index basename
  in
  let ctx = ctx_add is_opaque (VarId id) name ctx in
  (ctx, name)

(** See {!ctx_add_var} *)
let ctx_add_vars (vars : var list) (ctx : extraction_ctx) :
    extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (v : var) ->
      let name = ctx.fmt.var_basename ctx.names_map.names_set v.basename v.ty in
      ctx_add_var name v.id ctx)
    ctx vars

let ctx_add_type_params (vars : type_var list) (ctx : extraction_ctx) :
    extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (var : type_var) -> ctx_add_type_var var.name var.index ctx)
    ctx vars

let ctx_add_const_generic_params (vars : const_generic_var list)
    (ctx : extraction_ctx) : extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (var : const_generic_var) ->
      ctx_add_const_generic_var var.name var.index ctx)
    ctx vars

let ctx_add_type_const_generic_params (tvars : type_var list)
    (cgvars : const_generic_var list) (ctx : extraction_ctx) :
    extraction_ctx * string list * string list =
  let ctx, tys = ctx_add_type_params tvars ctx in
  let ctx, cgs = ctx_add_const_generic_params cgvars ctx in
  (ctx, tys, cgs)

let ctx_add_type_decl_struct (def : type_decl) (ctx : extraction_ctx) :
    extraction_ctx * string =
  assert (match def.kind with Struct _ -> true | _ -> false);
  let is_opaque = false in
  let cons_name = ctx.fmt.struct_constructor def.name in
  let ctx = ctx_add is_opaque (StructId (AdtId def.def_id)) cons_name ctx in
  (ctx, cons_name)

let ctx_add_type_decl (def : type_decl) (ctx : extraction_ctx) : extraction_ctx
    =
  let is_opaque = def.kind = Opaque in
  let def_name = ctx.fmt.type_name def.name in
  let ctx = ctx_add is_opaque (TypeId (AdtId def.def_id)) def_name ctx in
  ctx

let ctx_add_field (def : type_decl) (field_id : FieldId.id) (field : field)
    (ctx : extraction_ctx) : extraction_ctx * string =
  let is_opaque = false in
  let name = ctx.fmt.field_name def.name field_id field.field_name in
  let ctx = ctx_add is_opaque (FieldId (AdtId def.def_id, field_id)) name ctx in
  (ctx, name)

let ctx_add_fields (def : type_decl) (fields : (FieldId.id * field) list)
    (ctx : extraction_ctx) : extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (vid, v) -> ctx_add_field def vid v ctx)
    ctx fields

let ctx_add_variant (def : type_decl) (variant_id : VariantId.id)
    (variant : variant) (ctx : extraction_ctx) : extraction_ctx * string =
  let is_opaque = false in
  let name = ctx.fmt.variant_name def.name variant.variant_name in
  (* Add the type name prefix for Lean *)
  let name =
    if !Config.backend = Lean then
      let type_name = ctx.fmt.type_name def.name in
      type_name ^ "." ^ name
    else name
  in
  let ctx =
    ctx_add is_opaque (VariantId (AdtId def.def_id, variant_id)) name ctx
  in
  (ctx, name)

let ctx_add_variants (def : type_decl)
    (variants : (VariantId.id * variant) list) (ctx : extraction_ctx) :
    extraction_ctx * string list =
  List.fold_left_map
    (fun ctx (vid, v) -> ctx_add_variant def vid v ctx)
    ctx variants

let ctx_add_struct (def : type_decl) (ctx : extraction_ctx) :
    extraction_ctx * string =
  assert (match def.kind with Struct _ -> true | _ -> false);
  let is_opaque = false in
  let name = ctx.fmt.struct_constructor def.name in
  let ctx = ctx_add is_opaque (StructId (AdtId def.def_id)) name ctx in
  (ctx, name)

let ctx_add_decreases_proof (def : fun_decl) (ctx : extraction_ctx) :
    extraction_ctx =
  let is_opaque = false in
  let name =
    ctx.fmt.decreases_proof_name def.def_id def.basename def.num_loops
      def.loop_id
  in
  ctx_add is_opaque
    (DecreasesProofId (Regular def.def_id, def.loop_id))
    name ctx

let ctx_add_termination_measure (def : fun_decl) (ctx : extraction_ctx) :
    extraction_ctx =
  let is_opaque = false in
  let name =
    ctx.fmt.termination_measure_name def.def_id def.basename def.num_loops
      def.loop_id
  in
  ctx_add is_opaque
    (TerminationMeasureId (Regular def.def_id, def.loop_id))
    name ctx

let ctx_add_global_decl_and_body (def : A.global_decl) (ctx : extraction_ctx) :
    extraction_ctx =
  (* TODO: update once the body id can be an option *)
  let is_opaque = false in
  let name = ctx.fmt.global_name def.name in
  let decl = GlobalId def.def_id in
  let body = FunId (FromLlbc (Regular def.body_id, None, None)) in
  let ctx = ctx_add is_opaque decl (name ^ "_c") ctx in
  let ctx = ctx_add is_opaque body (name ^ "_body") ctx in
  ctx

let ctx_add_fun_decl (trans_group : bool * pure_fun_translation)
    (def : fun_decl) (ctx : extraction_ctx) : extraction_ctx =
  (* Sanity check: the function should not be a global body - those are handled
   * separately *)
  assert (not def.is_global_decl_body);
  (* Lookup the LLBC def to compute the region group information *)
  let def_id = def.def_id in
  let llbc_def =
    A.FunDeclId.Map.find def_id ctx.trans_ctx.fun_context.fun_decls
  in
  let sg = llbc_def.signature in
  let num_rgs = List.length sg.regions_hierarchy in
  let keep_fwd, (_, backs) = trans_group in
  let num_backs = List.length backs in
  let rg_info =
    match def.back_id with
    | None -> None
    | Some rg_id ->
        let rg = T.RegionGroupId.nth sg.regions_hierarchy rg_id in
        let regions =
          List.map
            (fun rid -> T.RegionVarId.nth sg.region_params rid)
            rg.regions
        in
        let region_names =
          List.map (fun (r : T.region_var) -> r.name) regions
        in
        Some { id = rg_id; region_names }
  in
  let is_opaque = def.body = None in
  (* Add the function name *)
  let def_name =
    ctx.fmt.fun_name def.basename def.num_loops def.loop_id num_rgs rg_info
      (keep_fwd, num_backs)
  in
  let fun_id = (A.Regular def_id, def.loop_id, def.back_id) in
  let ctx = ctx_add is_opaque (FunId (FromLlbc fun_id)) def_name ctx in
  (* Add the name info *)
  {
    ctx with
    fun_name_info =
      PureUtils.RegularFunIdMap.add fun_id { keep_fwd; num_backs }
        ctx.fun_name_info;
  }

type names_map_init = {
  keywords : string list;
  assumed_adts : (assumed_ty * string) list;
  assumed_structs : (assumed_ty * string) list;
  assumed_variants : (assumed_ty * VariantId.id * string) list;
  assumed_llbc_functions :
    (A.assumed_fun_id * RegionGroupId.id option * string) list;
  assumed_pure_functions : (pure_assumed_fun_id * string) list;
}

(** Initialize a names map with a proper set of keywords/names coming from the
    target language/prover. *)
let initialize_names_map (fmt : formatter) (init : names_map_init) : names_map =
  let int_names = List.map fmt.int_name T.all_int_types in
  let keywords =
    List.concat
      [
        [ fmt.bool_name; fmt.char_name; fmt.str_name ]; int_names; init.keywords;
      ]
  in
  let names_set = StringSet.of_list keywords in
  let name_to_id =
    StringMap.of_list (List.map (fun x -> (x, UnknownId)) keywords)
  in
  let opaque_ids = IdSet.empty in
  (* We fist initialize [id_to_name] as empty, because the id of a keyword is [UnknownId].
   * Also note that we don't need this mapping for keywords: we insert keywords only
   * to check collisions. *)
  let id_to_name = IdMap.empty in
  let nm = { id_to_name; name_to_id; names_set; opaque_ids } in
  (* For debugging - we are creating bindings for assumed types and functions, so
   * it is ok if we simply use the "show" function (those aren't simply identified
   * by numbers) *)
  let id_to_string = show_id in
  (* Then we add:
   * - the assumed types
   * - the assumed struct constructors
   * - the assumed variants
   * - the assumed functions
   *)
  let nm =
    List.fold_left
      (fun nm (type_id, name) ->
        names_map_add_assumed_type id_to_string type_id name nm)
      nm init.assumed_adts
  in
  let nm =
    List.fold_left
      (fun nm (type_id, name) ->
        names_map_add_assumed_struct id_to_string type_id name nm)
      nm init.assumed_structs
  in
  let nm =
    List.fold_left
      (fun nm (type_id, variant_id, name) ->
        names_map_add_assumed_variant id_to_string type_id variant_id name nm)
      nm init.assumed_variants
  in
  let assumed_functions =
    List.map
      (fun (fid, rg, name) -> (FromLlbc (A.Assumed fid, None, rg), name))
      init.assumed_llbc_functions
    @ List.map (fun (fid, name) -> (Pure fid, name)) init.assumed_pure_functions
  in
  let nm =
    (* In practice, the assumed function are opaque. However, assumed functions
       are never grouped in the opaque module, meaning we never need to
       prefix them: we thus consider them as non-opaque with regards to the
       names map.
    *)
    let is_opaque = false in
    List.fold_left
      (fun nm (fid, name) ->
        names_map_add_function id_to_string is_opaque fid name nm)
      nm assumed_functions
  in
  (* Return *)
  nm

let compute_type_decl_name (fmt : formatter) (def : type_decl) : string =
  fmt.type_name def.name

(** Helper function: generate a suffix for a function name, i.e., generates
    a suffix like "_loop", "loop1", etc. to append to a function name.
 *)
let default_fun_loop_suffix (num_loops : int) (loop_id : LoopId.id option) :
    string =
  match loop_id with
  | None -> ""
  | Some loop_id ->
      (* If this is for a loop, generally speaking, we append the loop index.
         If this function admits only one loop, we omit it. *)
      if num_loops = 1 then "_loop" else "_loop" ^ LoopId.to_string loop_id

(** A helper function: generates a function suffix from a region group
    information.
    TODO: move all those helpers.
*)
let default_fun_suffix (num_loops : int) (loop_id : LoopId.id option)
    (num_region_groups : int) (rg : region_group_info option)
    ((keep_fwd, num_backs) : bool * int) : string =
  let lp_suff = default_fun_loop_suffix num_loops loop_id in

  (* There are several cases:
     - [rg] is [Some]: this is a forward function:
       - we add "_fwd"
     - [rg] is [None]: this is a backward function:
       - this function has one extracted backward function:
         - if the forward function has been filtered, we add "_fwd_back":
           the forward function is useless, so the unique backward function
           takes its place, in a way
         - otherwise we add "_back"
       - this function has several backward functions: we add "_back" and an
         additional suffix to identify the precise backward function
     Note that we always add a suffix (in case there are no region groups,
     we could not add the "_fwd" suffix) to prevent name clashes between
     definitions (in particular between type and function definitions).
  *)
  let rg_suff =
    (* TODO: make all the backends match what is done for Lean *)
    match rg with
    | None -> (
        match !Config.backend with
        | FStar | Coq | HOL4 -> "_fwd"
        | Lean ->
            (* In order to avoid name conflicts:
             * - if the forward is eliminated, we add the suffix "_fwd" (it won't be used)
             * - otherwise, no suffix (because the backward functions will have a suffix)
             *)
            if num_backs = 1 && not keep_fwd then "_fwd" else "")
    | Some rg ->
        assert (num_region_groups > 0 && num_backs > 0);
        if num_backs = 1 then
          (* Exactly one backward function *)
          match !Config.backend with
          | FStar | Coq | HOL4 -> if not keep_fwd then "_fwd_back" else "_back"
          | Lean -> if not keep_fwd then "" else "_back"
        else if
          (* Several region groups/backward functions:
             - if all the regions in the group have names, we use those names
             - otherwise we use an index
          *)
          List.for_all Option.is_some rg.region_names
        then
          (* Concatenate the region names *)
          "_back" ^ String.concat "" (List.map Option.get rg.region_names)
        else (* Use the region index *)
          "_back" ^ RegionGroupId.to_string rg.id
  in
  lp_suff ^ rg_suff
