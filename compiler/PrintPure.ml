(** This module defines printing functions for the types defined in Pure.ml *)

open Pure
open PureUtils

type type_formatter = {
  type_var_id_to_string : TypeVarId.id -> string;
  type_decl_id_to_string : TypeDeclId.id -> string;
  const_generic_var_id_to_string : ConstGenericVarId.id -> string;
  global_decl_id_to_string : GlobalDeclId.id -> string;
}

type value_formatter = {
  type_var_id_to_string : TypeVarId.id -> string;
  type_decl_id_to_string : TypeDeclId.id -> string;
  const_generic_var_id_to_string : ConstGenericVarId.id -> string;
  global_decl_id_to_string : GlobalDeclId.id -> string;
  adt_variant_to_string : TypeDeclId.id -> VariantId.id -> string;
  var_id_to_string : VarId.id -> string;
  adt_field_names : TypeDeclId.id -> VariantId.id option -> string list option;
}

let value_to_type_formatter (fmt : value_formatter) : type_formatter =
  {
    type_var_id_to_string = fmt.type_var_id_to_string;
    type_decl_id_to_string = fmt.type_decl_id_to_string;
    const_generic_var_id_to_string = fmt.const_generic_var_id_to_string;
    global_decl_id_to_string = fmt.global_decl_id_to_string;
  }

(* TODO: we need to store which variables we have encountered so far, and
   remove [var_id_to_string].
*)
type ast_formatter = {
  type_var_id_to_string : TypeVarId.id -> string;
  type_decl_id_to_string : TypeDeclId.id -> string;
  const_generic_var_id_to_string : ConstGenericVarId.id -> string;
  adt_variant_to_string : TypeDeclId.id -> VariantId.id -> string;
  var_id_to_string : VarId.id -> string;
  adt_field_to_string :
    TypeDeclId.id -> VariantId.id option -> FieldId.id -> string option;
  adt_field_names : TypeDeclId.id -> VariantId.id option -> string list option;
  fun_decl_id_to_string : FunDeclId.id -> string;
  global_decl_id_to_string : GlobalDeclId.id -> string;
}

let ast_to_value_formatter (fmt : ast_formatter) : value_formatter =
  {
    type_var_id_to_string = fmt.type_var_id_to_string;
    type_decl_id_to_string = fmt.type_decl_id_to_string;
    const_generic_var_id_to_string = fmt.const_generic_var_id_to_string;
    global_decl_id_to_string = fmt.global_decl_id_to_string;
    adt_variant_to_string = fmt.adt_variant_to_string;
    var_id_to_string = fmt.var_id_to_string;
    adt_field_names = fmt.adt_field_names;
  }

let ast_to_type_formatter (fmt : ast_formatter) : type_formatter =
  let fmt = ast_to_value_formatter fmt in
  value_to_type_formatter fmt

let name_to_string = Print.name_to_string
let fun_name_to_string = Print.fun_name_to_string
let global_name_to_string = Print.global_name_to_string
let option_to_string = Print.option_to_string
let type_var_to_string = Print.Types.type_var_to_string
let const_generic_var_to_string = Print.Types.const_generic_var_to_string
let integer_type_to_string = Print.PrimitiveValues.integer_type_to_string
let literal_type_to_string = Print.PrimitiveValues.literal_type_to_string
let scalar_value_to_string = Print.PrimitiveValues.scalar_value_to_string
let literal_to_string = Print.PrimitiveValues.literal_to_string

let mk_type_formatter (type_decls : T.type_decl TypeDeclId.Map.t)
    (global_decls : A.global_decl GlobalDeclId.Map.t)
    (type_params : type_var list)
    (const_generic_params : const_generic_var list) : type_formatter =
  let type_var_id_to_string vid =
    let var = T.TypeVarId.nth type_params vid in
    type_var_to_string var
  in
  let const_generic_var_id_to_string vid =
    let var = T.ConstGenericVarId.nth const_generic_params vid in
    const_generic_var_to_string var
  in
  let type_decl_id_to_string def_id =
    let def = T.TypeDeclId.Map.find def_id type_decls in
    name_to_string def.name
  in
  let global_decl_id_to_string def_id =
    let def = T.GlobalDeclId.Map.find def_id global_decls in
    name_to_string def.name
  in
  {
    type_var_id_to_string;
    type_decl_id_to_string;
    const_generic_var_id_to_string;
    global_decl_id_to_string;
  }

(* TODO: there is a bit of duplication with Print.fun_decl_to_ast_formatter.

   TODO: use the pure defs as inputs? Note that it is a bit annoying for the
   functions (there is a difference between the forward/backward functions...)
   while we only need those definitions to lookup proper names for the def ids.
*)
let mk_ast_formatter (type_decls : T.type_decl TypeDeclId.Map.t)
    (fun_decls : A.fun_decl FunDeclId.Map.t)
    (global_decls : A.global_decl GlobalDeclId.Map.t)
    (type_params : type_var list)
    (const_generic_params : const_generic_var list) : ast_formatter =
  let type_var_id_to_string vid =
    let var = T.TypeVarId.nth type_params vid in
    type_var_to_string var
  in
  let const_generic_var_id_to_string vid =
    let var = T.ConstGenericVarId.nth const_generic_params vid in
    const_generic_var_to_string var
  in
  let type_decl_id_to_string def_id =
    let def = T.TypeDeclId.Map.find def_id type_decls in
    name_to_string def.name
  in
  let adt_variant_to_string =
    Print.Types.type_ctx_to_adt_variant_to_string_fun type_decls
  in
  let var_id_to_string vid =
    (* TODO: somehow lookup in the context *)
    "^" ^ VarId.to_string vid
  in
  let adt_field_names =
    Print.Types.type_ctx_to_adt_field_names_fun type_decls
  in
  let adt_field_to_string =
    Print.Types.type_ctx_to_adt_field_to_string_fun type_decls
  in
  let fun_decl_id_to_string def_id =
    let def = FunDeclId.Map.find def_id fun_decls in
    fun_name_to_string def.name
  in
  let global_decl_id_to_string def_id =
    let def = GlobalDeclId.Map.find def_id global_decls in
    global_name_to_string def.name
  in
  {
    type_var_id_to_string;
    const_generic_var_id_to_string;
    type_decl_id_to_string;
    adt_variant_to_string;
    var_id_to_string;
    adt_field_names;
    adt_field_to_string;
    fun_decl_id_to_string;
    global_decl_id_to_string;
  }

let assumed_ty_to_string (aty : assumed_ty) : string =
  match aty with
  | State -> "State"
  | Result -> "Result"
  | Error -> "Error"
  | Fuel -> "Fuel"
  | Option -> "Option"
  | Vec -> "Vec"
  | Array -> "Array"
  | Slice -> "Slice"
  | Str -> "Str"
  | Range -> "Range"

let type_id_to_string (fmt : type_formatter) (id : type_id) : string =
  match id with
  | AdtId id -> fmt.type_decl_id_to_string id
  | Tuple -> ""
  | Assumed aty -> assumed_ty_to_string aty

(* TODO: duplicates  Charon.PrintTypes.const_generic_to_string *)
let const_generic_to_string (fmt : type_formatter) (cg : T.const_generic) :
    string =
  match cg with
  | ConstGenericGlobal id -> fmt.global_decl_id_to_string id
  | ConstGenericVar id -> fmt.const_generic_var_id_to_string id
  | ConstGenericValue lit -> literal_to_string lit

let rec ty_to_string (fmt : type_formatter) (inside : bool) (ty : ty) : string =
  match ty with
  | Adt (id, tys, cgs) -> (
      let tys = List.map (ty_to_string fmt false) tys in
      let cgs = List.map (const_generic_to_string fmt) cgs in
      let params = List.append tys cgs in
      match id with
      | Tuple ->
          assert (cgs = []);
          "(" ^ String.concat " * " tys ^ ")"
      | AdtId _ | Assumed _ ->
          let params_s =
            if params = [] then "" else " " ^ String.concat " " params
          in
          let ty_s = type_id_to_string fmt id ^ params_s in
          if params <> [] && inside then "(" ^ ty_s ^ ")" else ty_s)
  | TypeVar tv -> fmt.type_var_id_to_string tv
  | Literal lty -> literal_type_to_string lty
  | Arrow (arg_ty, ret_ty) ->
      let ty =
        ty_to_string fmt true arg_ty ^ " -> " ^ ty_to_string fmt false ret_ty
      in
      if inside then "(" ^ ty ^ ")" else ty

let field_to_string fmt inside (f : field) : string =
  match f.field_name with
  | None -> ty_to_string fmt inside f.field_ty
  | Some field_name ->
      let s = field_name ^ " : " ^ ty_to_string fmt false f.field_ty in
      if inside then "(" ^ s ^ ")" else s

let variant_to_string fmt (v : variant) : string =
  v.variant_name ^ "("
  ^ String.concat ", " (List.map (field_to_string fmt false) v.fields)
  ^ ")"

let type_decl_to_string (fmt : type_formatter) (def : type_decl) : string =
  let types = def.type_params in
  let name = name_to_string def.name in
  let params =
    if types = [] then ""
    else " " ^ String.concat " " (List.map type_var_to_string types)
  in
  match def.kind with
  | Struct fields ->
      if List.length fields > 0 then
        let fields =
          String.concat ","
            (List.map (fun f -> "\n  " ^ field_to_string fmt false f) fields)
        in
        "struct " ^ name ^ params ^ "{" ^ fields ^ "}"
      else "struct " ^ name ^ params ^ "{}"
  | Enum variants ->
      let variants =
        List.map (fun v -> "|  " ^ variant_to_string fmt v) variants
      in
      let variants = String.concat "\n" variants in
      "enum " ^ name ^ params ^ " =\n" ^ variants
  | Opaque -> "opaque type " ^ name ^ params

let var_to_varname (v : var) : string =
  match v.basename with
  | Some name -> name ^ "^" ^ VarId.to_string v.id
  | None -> "^" ^ VarId.to_string v.id

let var_to_string (fmt : type_formatter) (v : var) : string =
  let varname = var_to_varname v in
  "(" ^ varname ^ " : " ^ ty_to_string fmt false v.ty ^ ")"

let rec mprojection_to_string (fmt : ast_formatter) (inside : string)
    (p : mprojection) : string =
  match p with
  | [] -> inside
  | pe :: p' -> (
      let s = mprojection_to_string fmt inside p' in
      match pe.pkind with
      | E.ProjOption variant_id ->
          assert (variant_id = T.option_some_id);
          assert (pe.field_id = T.FieldId.zero);
          "(" ^ s ^ "as Option::Some)." ^ T.FieldId.to_string pe.field_id
      | E.ProjTuple _ -> "(" ^ s ^ ")." ^ T.FieldId.to_string pe.field_id
      | E.ProjAdt (adt_id, opt_variant_id) -> (
          let field_name =
            match fmt.adt_field_to_string adt_id opt_variant_id pe.field_id with
            | Some field_name -> field_name
            | None -> T.FieldId.to_string pe.field_id
          in
          match opt_variant_id with
          | None -> "(" ^ s ^ ")." ^ field_name
          | Some variant_id ->
              let variant_name = fmt.adt_variant_to_string adt_id variant_id in
              "(" ^ s ^ " as " ^ variant_name ^ ")." ^ field_name))

let mplace_to_string (fmt : ast_formatter) (p : mplace) : string =
  let name = match p.name with None -> "" | Some name -> name in
  (* We add the "llbc" suffix to the variable index, because meta-places
   * use indices of the variables in the original LLBC program, while
   * regular places use indices for the pure variables: we want to make
   * this explicit, otherwise it is confusing. *)
  let name = name ^ "^" ^ E.VarId.to_string p.var_id ^ "llbc" in
  mprojection_to_string fmt name p.projection

let adt_variant_to_string (fmt : value_formatter) (adt_id : type_id)
    (variant_id : VariantId.id option) : string =
  match adt_id with
  | Tuple -> "Tuple"
  | AdtId def_id -> (
      (* "Regular" ADT *)
      match variant_id with
      | Some vid -> fmt.adt_variant_to_string def_id vid
      | None -> fmt.type_decl_id_to_string def_id)
  | Assumed aty -> (
      (* Assumed type *)
      match aty with
      | State | Array | Slice | Str ->
          (* Those types are opaque: we can't get there *)
          raise (Failure "Unreachable")
      | Vec -> "@Vec"
      | Range -> "@Range"
      | Result ->
          let variant_id = Option.get variant_id in
          if variant_id = result_return_id then "@Result::Return"
          else if variant_id = result_fail_id then "@Result::Fail"
          else
            raise (Failure "Unreachable: improper variant id for result type")
      | Error ->
          let variant_id = Option.get variant_id in
          if variant_id = error_failure_id then "@Error::Failure"
          else if variant_id = error_out_of_fuel_id then "@Error::OutOfFuel"
          else raise (Failure "Unreachable: improper variant id for error type")
      | Fuel ->
          let variant_id = Option.get variant_id in
          if variant_id = fuel_zero_id then "@Fuel::Zero"
          else if variant_id = fuel_succ_id then "@Fuel::Succ"
          else raise (Failure "Unreachable: improper variant id for fuel type")
      | Option ->
          let variant_id = Option.get variant_id in
          if variant_id = option_some_id then "@Option::Some "
          else if variant_id = option_none_id then "@Option::None"
          else
            raise (Failure "Unreachable: improper variant id for result type"))

let adt_field_to_string (fmt : value_formatter) (adt_id : type_id)
    (field_id : FieldId.id) : string =
  match adt_id with
  | Tuple ->
      raise (Failure "Unreachable")
      (* Tuples don't use the opaque field id for the field indices, but [int] *)
  | AdtId def_id -> (
      (* "Regular" ADT *)
      let fields = fmt.adt_field_names def_id None in
      match fields with
      | None -> FieldId.to_string field_id
      | Some fields -> FieldId.nth fields field_id)
  | Assumed aty -> (
      (* Assumed type *)
      match aty with
      | Range -> FieldId.to_string field_id
      | State | Fuel | Vec | Array | Slice | Str ->
          (* Opaque types: we can't get there *)
          raise (Failure "Unreachable")
      | Result | Error | Option ->
          (* Enumerations: we can't get there *)
          raise (Failure "Unreachable"))

(** TODO: we don't need a general function anymore (it is now only used for
    patterns)
 *)
let adt_g_value_to_string (fmt : value_formatter)
    (value_to_string : 'v -> string) (variant_id : VariantId.id option)
    (field_values : 'v list) (ty : ty) : string =
  let field_values = List.map value_to_string field_values in
  match ty with
  | Adt (Tuple, _, _) ->
      (* Tuple *)
      "(" ^ String.concat ", " field_values ^ ")"
  | Adt (AdtId def_id, _, _) ->
      (* "Regular" ADT *)
      let adt_ident =
        match variant_id with
        | Some vid -> fmt.adt_variant_to_string def_id vid
        | None -> fmt.type_decl_id_to_string def_id
      in
      if field_values <> [] then
        match fmt.adt_field_names def_id variant_id with
        | None ->
            let field_values = String.concat ", " field_values in
            adt_ident ^ " (" ^ field_values ^ ")"
        | Some field_names ->
            let field_values = List.combine field_names field_values in
            let field_values =
              List.map
                (fun (field, value) -> field ^ " = " ^ value ^ ";")
                field_values
            in
            let field_values = String.concat " " field_values in
            adt_ident ^ " { " ^ field_values ^ " }"
      else adt_ident
  | Adt (Assumed aty, _, _) -> (
      (* Assumed type *)
      match aty with
      | State ->
          (* This type is opaque: we can't get there *)
          raise (Failure "Unreachable")
      | Result ->
          let variant_id = Option.get variant_id in
          if variant_id = result_return_id then
            match field_values with
            | [ v ] -> "@Result::Return " ^ v
            | _ -> raise (Failure "Result::Return takes exactly one value")
          else if variant_id = result_fail_id then
            match field_values with
            | [ v ] -> "@Result::Fail " ^ v
            | _ -> raise (Failure "Result::Fail takes exactly one value")
          else
            raise (Failure "Unreachable: improper variant id for result type")
      | Error ->
          assert (field_values = []);
          let variant_id = Option.get variant_id in
          if variant_id = error_failure_id then "@Error::Failure"
          else if variant_id = error_out_of_fuel_id then "@Error::OutOfFuel"
          else raise (Failure "Unreachable: improper variant id for error type")
      | Fuel ->
          let variant_id = Option.get variant_id in
          if variant_id = fuel_zero_id then (
            assert (field_values = []);
            "@Fuel::Zero")
          else if variant_id = fuel_succ_id then
            match field_values with
            | [ v ] -> "@Fuel::Succ " ^ v
            | _ -> raise (Failure "@Fuel::Succ takes exactly one value")
          else raise (Failure "Unreachable: improper variant id for fuel type")
      | Option ->
          let variant_id = Option.get variant_id in
          if variant_id = option_some_id then
            match field_values with
            | [ v ] -> "@Option::Some " ^ v
            | _ -> raise (Failure "Option::Some takes exactly one value")
          else if variant_id = option_none_id then (
            assert (field_values = []);
            "@Option::None")
          else
            raise (Failure "Unreachable: improper variant id for result type")
      | Vec | Array | Slice | Str ->
          assert (variant_id = None);
          let field_values =
            List.mapi (fun i v -> string_of_int i ^ " -> " ^ v) field_values
          in
          let id = assumed_ty_to_string aty in
          id ^ " [" ^ String.concat "; " field_values ^ "]"
      | Range ->
          assert (variant_id = None);
          let field_values =
            List.mapi (fun i v -> string_of_int i ^ " -> " ^ v) field_values
          in
          let id = assumed_ty_to_string aty in
          id ^ " {" ^ String.concat "; " field_values ^ "}")
  | _ ->
      let fmt = value_to_type_formatter fmt in
      raise
        (Failure
           ("Inconsistently typed value: expected ADT type but found:"
          ^ "\n- ty: " ^ ty_to_string fmt false ty ^ "\n- variant_id: "
           ^ Print.option_to_string VariantId.to_string variant_id))

let rec typed_pattern_to_string (fmt : ast_formatter) (v : typed_pattern) :
    string =
  match v.value with
  | PatConstant cv -> literal_to_string cv
  | PatVar (v, None) -> var_to_string (ast_to_type_formatter fmt) v
  | PatVar (v, Some mp) ->
      let mp = "[@mplace=" ^ mplace_to_string fmt mp ^ "]" in
      "(" ^ var_to_varname v ^ " " ^ mp ^ " : "
      ^ ty_to_string (ast_to_type_formatter fmt) false v.ty
      ^ ")"
  | PatDummy -> "_"
  | PatAdt av ->
      adt_g_value_to_string
        (ast_to_value_formatter fmt)
        (typed_pattern_to_string fmt)
        av.variant_id av.field_values v.ty

let fun_sig_to_string (fmt : ast_formatter) (sg : fun_sig) : string =
  let ty_fmt = ast_to_type_formatter fmt in
  let type_params = List.map type_var_to_string sg.type_params in
  let inputs = List.map (ty_to_string ty_fmt false) sg.inputs in
  let output = ty_to_string ty_fmt false sg.output in
  let all_types = List.concat [ type_params; inputs; [ output ] ] in
  String.concat " -> " all_types

let inst_fun_sig_to_string (fmt : ast_formatter) (sg : inst_fun_sig) : string =
  let ty_fmt = ast_to_type_formatter fmt in
  let inputs = List.map (ty_to_string ty_fmt false) sg.inputs in
  let output = ty_to_string ty_fmt false sg.output in
  let all_types = List.append inputs [ output ] in
  String.concat " -> " all_types

let fun_suffix (lp_id : LoopId.id option) (rg_id : T.RegionGroupId.id option) :
    string =
  let lp_suff =
    match lp_id with
    | None -> ""
    | Some lp_id -> "^loop" ^ LoopId.to_string lp_id
  in

  let rg_suff =
    match rg_id with
    | None -> ""
    | Some rg_id -> "@" ^ T.RegionGroupId.to_string rg_id
  in

  lp_suff ^ rg_suff

let llbc_assumed_fun_id_to_string (fid : A.assumed_fun_id) : string =
  match fid with
  | A.Replace -> "core::mem::replace"
  | A.BoxNew -> "alloc::boxed::Box::new"
  | A.BoxDeref -> "core::ops::deref::Deref::deref"
  | A.BoxDerefMut -> "core::ops::deref::DerefMut::deref_mut"
  | A.BoxFree -> "alloc::alloc::box_free"
  | A.VecNew -> "alloc::vec::Vec::new"
  | A.VecPush -> "alloc::vec::Vec::push"
  | A.VecInsert -> "alloc::vec::Vec::insert"
  | A.VecLen -> "alloc::vec::Vec::len"
  | A.VecIndex -> "core::ops::index::Index<alloc::vec::Vec>::index"
  | A.VecIndexMut -> "core::ops::index::IndexMut<alloc::vec::Vec>::index_mut"
  | ArrayIndexShared -> "@ArrayIndexShared"
  | ArrayIndexMut -> "@ArrayIndexMut"
  | ArrayToSliceShared -> "@ArrayToSliceShared"
  | ArrayToSliceMut -> "@ArrayToSliceMut"
  | ArraySubsliceShared -> "@ArraySubsliceShared"
  | ArraySubsliceMut -> "@ArraySubsliceMut"
  | SliceLen -> "@SliceLen"
  | SliceIndexShared -> "@SliceIndexShared"
  | SliceIndexMut -> "@SliceIndexMut"
  | SliceSubsliceShared -> "@SliceSubsliceShared"
  | SliceSubsliceMut -> "@SliceSubsliceMut"

let pure_assumed_fun_id_to_string (fid : pure_assumed_fun_id) : string =
  match fid with
  | Return -> "return"
  | Fail -> "fail"
  | Assert -> "assert"
  | FuelDecrease -> "fuel_decrease"
  | FuelEqZero -> "fuel_eq_zero"

let regular_fun_id_to_string (fmt : ast_formatter) (fun_id : fun_id) : string =
  match fun_id with
  | FromLlbc (fid, lp_id, rg_id) ->
      let f =
        match fid with
        | Regular fid -> fmt.fun_decl_id_to_string fid
        | Assumed fid -> llbc_assumed_fun_id_to_string fid
      in
      f ^ fun_suffix lp_id rg_id
  | Pure fid -> pure_assumed_fun_id_to_string fid

let unop_to_string (unop : unop) : string =
  match unop with
  | Not -> "¬"
  | Neg _ -> "-"
  | Cast (src, tgt) ->
      "cast<" ^ integer_type_to_string src ^ "," ^ integer_type_to_string tgt
      ^ ">"

let binop_to_string = Print.Expressions.binop_to_string

let fun_or_op_id_to_string (fmt : ast_formatter) (fun_id : fun_or_op_id) :
    string =
  match fun_id with
  | Fun fun_id -> regular_fun_id_to_string fmt fun_id
  | Unop unop -> unop_to_string unop
  | Binop (binop, int_ty) ->
      binop_to_string binop ^ "<" ^ integer_type_to_string int_ty ^ ">"

(** [inside]: controls the introduction of parentheses *)
let rec texpression_to_string (fmt : ast_formatter) (inside : bool)
    (indent : string) (indent_incr : string) (e : texpression) : string =
  match e.e with
  | Var var_id ->
      let s = fmt.var_id_to_string var_id in
      if inside then "(" ^ s ^ ")" else s
  | Const cv -> literal_to_string cv
  | App _ ->
      (* Recursively destruct the app, to have a pair (app, arguments list) *)
      let app, args = destruct_apps e in
      (* Convert to string *)
      app_to_string fmt inside indent indent_incr app args
  | Abs _ ->
      let xl, e = destruct_abs_list e in
      let e = abs_to_string fmt indent indent_incr xl e in
      if inside then "(" ^ e ^ ")" else e
  | Qualif _ ->
      (* Qualifier without arguments *)
      app_to_string fmt inside indent indent_incr e []
  | Let (monadic, lv, re, e) ->
      let e = let_to_string fmt indent indent_incr monadic lv re e in
      if inside then "(" ^ e ^ ")" else e
  | Switch (scrutinee, body) ->
      let e = switch_to_string fmt indent indent_incr scrutinee body in
      if inside then "(" ^ e ^ ")" else e
  | Loop loop ->
      let e = loop_to_string fmt indent indent_incr loop in
      if inside then "(" ^ e ^ ")" else e
  | StructUpdate supd -> (
      let s =
        match supd.init with
        | None -> ""
        | Some vid -> " " ^ fmt.var_id_to_string vid ^ " with"
      in
      let indent1 = indent ^ indent_incr in
      let indent2 = indent1 ^ indent_incr in
      (* The id should be a custom type decl id or an array *)
      match supd.struct_id with
      | AdtId aid ->
          let field_names = Option.get (fmt.adt_field_names aid None) in
          let fields =
            List.map
              (fun (fid, fe) ->
                let field = FieldId.nth field_names fid in
                let fe =
                  texpression_to_string fmt false indent2 indent_incr fe
                in
                "\n" ^ indent1 ^ field ^ " := " ^ fe ^ ";")
              supd.updates
          in
          let bl = if fields = [] then "" else "\n" ^ indent in
          "{" ^ s ^ String.concat "" fields ^ bl ^ "}"
      | Assumed Array ->
          let fields =
            List.map
              (fun (_, fe) ->
                texpression_to_string fmt false indent2 indent_incr fe)
              supd.updates
          in
          "[ " ^ String.concat ", " fields ^ " ]"
      | _ -> raise (Failure "Unexpected"))
  | Meta (meta, e) -> (
      let meta_s = meta_to_string fmt meta in
      let e = texpression_to_string fmt inside indent indent_incr e in
      match meta with
      | Assignment _ | SymbolicAssignment _ | Tag _ ->
          let e = meta_s ^ "\n" ^ indent ^ e in
          if inside then "(" ^ e ^ ")" else e
      | MPlace _ -> "(" ^ meta_s ^ " " ^ e ^ ")")

and app_to_string (fmt : ast_formatter) (inside : bool) (indent : string)
    (indent_incr : string) (app : texpression) (args : texpression list) :
    string =
  (* There are two possibilities: either the [app] is an instantiated,
   * top-level qualifier (function, ADT constructore...), or it is a "regular"
   * expression *)
  let app, tys =
    match app.e with
    | Qualif qualif ->
        (* Qualifier case *)
        (* Convert the qualifier identifier *)
        let qualif_s =
          match qualif.id with
          | FunOrOp fun_id -> fun_or_op_id_to_string fmt fun_id
          | Global global_id -> fmt.global_decl_id_to_string global_id
          | AdtCons adt_cons_id ->
              let variant_s =
                adt_variant_to_string
                  (ast_to_value_formatter fmt)
                  adt_cons_id.adt_id adt_cons_id.variant_id
              in
              ConstStrings.constructor_prefix ^ variant_s
          | Proj { adt_id; field_id } ->
              let value_fmt = ast_to_value_formatter fmt in
              let adt_s = adt_variant_to_string value_fmt adt_id None in
              let field_s = adt_field_to_string value_fmt adt_id field_id in
              (* Adopting an F*-like syntax *)
              ConstStrings.constructor_prefix ^ adt_s ^ "?." ^ field_s
        in
        (* Convert the type instantiation *)
        let ty_fmt = ast_to_type_formatter fmt in
        let tys = List.map (ty_to_string ty_fmt true) qualif.type_args in
        (* *)
        (qualif_s, tys)
    | _ ->
        (* "Regular" expression case *)
        let inside = args <> [] || (args = [] && inside) in
        (texpression_to_string fmt inside indent indent_incr app, [])
  in
  (* Convert the arguments.
   * The arguments are expressions, so indentation might get weird... (though
   * those expressions will in most cases just be values) *)
  let arg_to_string =
    let inside = true in
    let indent1 = indent ^ indent_incr in
    texpression_to_string fmt inside indent1 indent_incr
  in
  let args = List.map arg_to_string args in
  let all_args = List.append tys args in
  (* Put together *)
  let e =
    if all_args = [] then app else app ^ " " ^ String.concat " " all_args
  in
  (* Add parentheses *)
  if all_args <> [] && inside then "(" ^ e ^ ")" else e

and abs_to_string (fmt : ast_formatter) (indent : string) (indent_incr : string)
    (xl : typed_pattern list) (e : texpression) : string =
  let xl = List.map (typed_pattern_to_string fmt) xl in
  let e = texpression_to_string fmt false indent indent_incr e in
  "λ " ^ String.concat " " xl ^ ". " ^ e

and let_to_string (fmt : ast_formatter) (indent : string) (indent_incr : string)
    (monadic : bool) (lv : typed_pattern) (re : texpression) (e : texpression) :
    string =
  let indent1 = indent ^ indent_incr in
  let inside = false in
  let re = texpression_to_string fmt inside indent1 indent_incr re in
  let e = texpression_to_string fmt inside indent indent_incr e in
  let lv = typed_pattern_to_string fmt lv in
  if monadic then lv ^ " <-- " ^ re ^ ";\n" ^ indent ^ e
  else "let " ^ lv ^ " = " ^ re ^ " in\n" ^ indent ^ e

and switch_to_string (fmt : ast_formatter) (indent : string)
    (indent_incr : string) (scrutinee : texpression) (body : switch_body) :
    string =
  let indent1 = indent ^ indent_incr in
  (* Printing can mess up on the scrutinee, because it is an expression - but
   * in most situations it will be a value or a function call, so it should be
   * ok*)
  let scrut = texpression_to_string fmt true indent1 indent_incr scrutinee in
  let e_to_string = texpression_to_string fmt false indent1 indent_incr in
  match body with
  | If (e_true, e_false) ->
      let e_true = e_to_string e_true in
      let e_false = e_to_string e_false in
      "if " ^ scrut ^ "\n" ^ indent ^ "then\n" ^ indent1 ^ e_true ^ "\n"
      ^ indent ^ "else\n" ^ indent1 ^ e_false
  | Match branches ->
      let branch_to_string (b : match_branch) : string =
        let pat = typed_pattern_to_string fmt b.pat in
        indent ^ "| " ^ pat ^ " ->\n" ^ indent1 ^ e_to_string b.branch
      in
      let branches = List.map branch_to_string branches in
      "match " ^ scrut ^ " with\n" ^ String.concat "\n" branches

and loop_to_string (fmt : ast_formatter) (indent : string)
    (indent_incr : string) (loop : loop) : string =
  let indent1 = indent ^ indent_incr in
  let indent2 = indent1 ^ indent_incr in
  let type_fmt = ast_to_type_formatter fmt in
  let loop_inputs =
    "fresh_vars: ["
    ^ String.concat "; " (List.map (var_to_string type_fmt) loop.inputs)
    ^ "]"
  in
  let back_output_tys =
    let tys =
      match loop.back_output_tys with
      | None -> ""
      | Some tys ->
          String.concat "; "
            (List.map (ty_to_string (ast_to_type_formatter fmt) false) tys)
    in
    "back_output_tys: [" ^ tys ^ "]"
  in
  let fun_end =
    texpression_to_string fmt false indent2 indent_incr loop.fun_end
  in
  let loop_body =
    texpression_to_string fmt false indent2 indent_incr loop.loop_body
  in
  "loop {\n" ^ indent1 ^ loop_inputs ^ "\n" ^ indent1 ^ back_output_tys ^ "\n"
  ^ indent1 ^ "fun_end: {\n" ^ indent2 ^ fun_end ^ "\n" ^ indent1 ^ "}\n"
  ^ indent1 ^ "loop_body: {\n" ^ indent2 ^ loop_body ^ "\n" ^ indent1 ^ "}\n"
  ^ indent ^ "}"

and meta_to_string (fmt : ast_formatter) (meta : meta) : string =
  let meta =
    match meta with
    | Assignment (lp, rv, rp) ->
        let rp =
          match rp with
          | None -> ""
          | Some rp -> " [@src=" ^ mplace_to_string fmt rp ^ "]"
        in
        "@assign(" ^ mplace_to_string fmt lp ^ " := "
        ^ texpression_to_string fmt false "" "" rv
        ^ rp ^ ")"
    | SymbolicAssignment (var_id, rv) ->
        "@symb_assign(" ^ VarId.to_string var_id ^ " := "
        ^ texpression_to_string fmt false "" "" rv
        ^ ")"
    | MPlace mp -> "@mplace=" ^ mplace_to_string fmt mp
    | Tag msg -> "@tag \"" ^ msg ^ "\""
  in
  "@meta[" ^ meta ^ "]"

let fun_decl_to_string (fmt : ast_formatter) (def : fun_decl) : string =
  let type_fmt = ast_to_type_formatter fmt in
  let name =
    fun_name_to_string def.basename ^ fun_suffix def.loop_id def.back_id
  in
  let signature = fun_sig_to_string fmt def.signature in
  match def.body with
  | None -> "val " ^ name ^ " :\n  " ^ signature
  | Some body ->
      let inside = false in
      let indent = "  " in
      let inputs = List.map (var_to_string type_fmt) body.inputs in
      let inputs =
        if inputs = [] then indent
        else "  fun " ^ String.concat " " inputs ^ " ->\n" ^ indent
      in
      let body = texpression_to_string fmt inside indent indent body.body in
      "let " ^ name ^ " :\n  " ^ signature ^ " =\n" ^ inputs ^ body
