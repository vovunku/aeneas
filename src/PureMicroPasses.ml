(** The following module defines micro-passes which operate on the pure AST *)

open Errors
open Pure
open PureUtils
open TranslateCore

(** The local logger *)
let log = L.pure_micro_passes_log

type config = {
  unfold_monadic_let_bindings : bool;
      (** Controls the unfolding of monadic let-bindings to explicit matches:
          `y <-- f x; ...`
          becomes:
          `match f x with | Failure -> Failure | Return y -> ...`
     
          This is useful when extracting to F*: the support for monadic
          definitions is not super powerful.
       *)
  filter_unused_monadic_calls : bool;
      (** Controls whether we try to filter the calls to monadic functions
          (which can fail) when their outputs are not used.
          
          See the comments for [expression_contains_child_call_in_all_paths]
          for additional explanations.
       *)
}
(** A configuration to control the application of the passes *)

(** Small utility.

    We sometimes have to insert new fresh variables in a function body, in which
    case we need to make their indices greater than the indices of all the variables
    in the body.
    TODO: things would be simpler if we used a better representation of the
    variables indices...
 *)
let get_expression_min_var_counter (e : expression) : VarId.generator =
  let obj =
    object
      inherit [_] reduce_expression

      method zero _ = VarId.zero

      method plus id0 id1 _ = VarId.max (id0 ()) (id1 ())
      (* Get the maximum *)

      method! visit_var _ v _ = v.id
    end
  in
  let id = obj#visit_expression () e () in
  VarId.generator_from_incr_id id

type pn_ctx = string VarId.Map.t
(** "pretty-name context": see [compute_pretty_names] *)

(** This function computes pretty names for the variables in the pure AST. It
    relies on the "meta"-place information in the AST to generate naming
    constraints, and then uses those to compute the names.
    
    The way it works is as follows:
    - we only modify the names of the unnamed variables
    - whenever we see an rvalue/lvalue which is exactly an unnamed variable,
      and this value is linked to some meta-place information which contains
      a name and an empty path, we consider we should use this name
      
    Something important is that, for every variable we find, the name of this
    variable is influenced by the information we find *below* in the AST.

    For instance, the following situations happen:
    
    - let's say we evaluate:
      ```
      match (ls : List<T>) {
        List::Cons(x, hd) => {
          ...
        }
      }
      ```
      
      Actually, in MIR, we get:
      ```
      tmp := discriminant(ls);
      switch tmp {
        0 => {
          x := (ls as Cons).0;
          hd := (ls as Cons).1;
          ...
        }
      }
      ```
      If `ls` maps to a symbolic value `s0` upon evaluating the match in symbolic
      mode, we expand this value upon evaluating `tmp = discriminant(ls)`.
      However, at this point, we don't know which should be the names of
      the symbolic values we introduce for the fields of `Cons`!
      Let's imagine we have (for the `Cons` branch): `s0 ~~> Cons s1 s2`.
      The assigments lead to the following binding in the evaluation context:
      ```
      x -> s1
      hd -> s2
      ```
      
      When generating the symbolic AST, we save as meta-information that we
      assign `s1` to the place `x` and `s2` to the place `hd`. This way,
      we learn we can use the names `x` and `hd` for the variables which are
      introduced by the match:
      ```
      match ls with
      | Cons x hd -> ...
      | ...
      ```
   - TODO: inputs and end abstraction...
 *)
let compute_pretty_names (def : fun_def) : fun_def =
  (* Small helpers *)
  (* 
   * When we do branchings, we need to merge (the constraints saved in) the
   * contexts returned by the different branches.
   *
   * Note that by doing so, some mappings from var id to name
   * in one context may be overriden by the ones in the other context.
   *
   * This should be ok because:
   * - generally, the overriden variables should have been introduced *inside*
   *   the branches, in which case we don't care
   * - or they were introduced before, in which case the naming should generally
   *   be consistent? In the worse case, it isn't, but it leads only to less
   *   readable code, not to unsoundness. This case should be pretty rare,
   *   also.
   *)
  let merge_ctxs (ctx0 : pn_ctx) (ctx1 : pn_ctx) : pn_ctx =
    VarId.Map.fold (fun id name ctx -> VarId.Map.add id name ctx) ctx0 ctx1
  in
  let merge_ctxs_ls (ctxs : pn_ctx list) : pn_ctx =
    List.fold_left (fun ctx0 ctx1 -> merge_ctxs ctx0 ctx1) VarId.Map.empty ctxs
  in

  let add_var (ctx : pn_ctx) (v : var) : pn_ctx =
    assert (not (VarId.Map.mem v.id ctx));
    match v.basename with
    | None -> ctx
    | Some name -> VarId.Map.add v.id name ctx
  in
  let update_var (ctx : pn_ctx) (v : var) : var =
    match v.basename with
    | Some _ -> v
    | None -> (
        match VarId.Map.find_opt v.id ctx with
        | None -> v
        | Some basename -> { v with basename = Some basename })
  in
  let update_typed_lvalue ctx (lv : typed_lvalue) : typed_lvalue =
    let obj =
      object
        inherit [_] map_typed_lvalue

        method! visit_var _ v = update_var ctx v
      end
    in
    obj#visit_typed_lvalue () lv
  in

  let add_constraint (mp : mplace) (var_id : VarId.id) (ctx : pn_ctx) : pn_ctx =
    match (mp.name, mp.projection) with
    | Some name, [] ->
        (* Check if the variable already has a name - if not: insert the new name *)
        if VarId.Map.mem var_id ctx then ctx else VarId.Map.add var_id name ctx
    | _ -> ctx
  in
  let add_right_constraint (mp : mplace) (rv : typed_rvalue) (ctx : pn_ctx) :
      pn_ctx =
    match rv.value with
    | RvPlace { var = var_id; projection = [] } -> add_constraint mp var_id ctx
    | _ -> ctx
  in
  let add_opt_right_constraint (mp : mplace option) (rv : typed_rvalue)
      (ctx : pn_ctx) : pn_ctx =
    match mp with None -> ctx | Some mp -> add_right_constraint mp rv ctx
  in
  let add_left_constraint (lv : typed_lvalue) (ctx : pn_ctx) : pn_ctx =
    let obj =
      object (self)
        inherit [_] reduce_typed_lvalue

        method zero _ = VarId.Map.empty

        method plus ctx0 ctx1 _ = merge_ctxs (ctx0 ()) (ctx1 ())

        method! visit_var _ v () = add_var (self#zero ()) v
      end
    in
    let ctx1 = obj#visit_typed_lvalue () lv () in
    merge_ctxs ctx ctx1
  in

  (* *)
  let rec update_expression (e : expression) (ctx : pn_ctx) :
      pn_ctx * expression =
    match e with
    | Value (v, mp) -> update_value v mp ctx
    | Call call -> update_call call ctx
    | Let (monadic, lb, re, e) -> update_let monadic lb re e ctx
    | Switch (scrut, body) -> update_switch_body scrut body ctx
    | Meta (meta, e) -> update_meta meta e ctx
  (* *)
  and update_value (v : typed_rvalue) (mp : mplace option) (ctx : pn_ctx) :
      pn_ctx * expression =
    let ctx = add_opt_right_constraint mp v ctx in
    (ctx, Value (v, mp))
  (* *)
  and update_call (call : call) (ctx : pn_ctx) : pn_ctx * expression =
    let ctx, args =
      List.fold_left_map
        (fun ctx arg -> update_expression arg ctx)
        ctx call.args
    in
    let call = { call with args } in
    (ctx, Call call)
  (* *)
  and update_let (monadic : bool) (lv : typed_lvalue) (re : expression)
      (e : expression) (ctx : pn_ctx) : pn_ctx * expression =
    let ctx = add_left_constraint lv ctx in
    let ctx, re = update_expression re ctx in
    let ctx, e = update_expression e ctx in
    let lv = update_typed_lvalue ctx lv in
    (ctx, Let (monadic, lv, re, e))
  (* *)
  and update_switch_body (scrut : expression) (body : switch_body)
      (ctx : pn_ctx) : pn_ctx * expression =
    let ctx, scrut = update_expression scrut ctx in

    let ctx, body =
      match body with
      | If (e_true, e_false) ->
          let ctx1, e_true = update_expression e_true ctx in
          let ctx2, e_false = update_expression e_false ctx in
          let ctx = merge_ctxs ctx1 ctx2 in
          (ctx, If (e_true, e_false))
      | SwitchInt (int_ty, branches, otherwise) ->
          let ctx_branches_ls =
            List.map
              (fun (v, br) ->
                let ctx, br = update_expression br ctx in
                (ctx, (v, br)))
              branches
          in
          let ctx, otherwise = update_expression otherwise ctx in
          let ctxs, branches = List.split ctx_branches_ls in
          let ctxs = merge_ctxs_ls ctxs in
          let ctx = merge_ctxs ctx ctxs in
          (ctx, SwitchInt (int_ty, branches, otherwise))
      | Match branches ->
          let ctx_branches_ls =
            List.map
              (fun br ->
                let ctx = add_left_constraint br.pat ctx in
                let ctx, branch = update_expression br.branch ctx in
                let pat = update_typed_lvalue ctx br.pat in
                (ctx, { pat; branch }))
              branches
          in
          let ctxs, branches = List.split ctx_branches_ls in
          let ctx = merge_ctxs_ls ctxs in
          (ctx, Match branches)
    in
    (ctx, Switch (scrut, body))
  (* *)
  and update_meta (meta : meta) (e : expression) (ctx : pn_ctx) :
      pn_ctx * expression =
    match meta with
    | Assignment (mp, rvalue) ->
        let ctx = add_right_constraint mp rvalue ctx in
        update_expression e ctx
  in

  let input_names =
    List.filter_map
      (fun (v : var) ->
        match v.basename with None -> None | Some name -> Some (v.id, name))
      def.inputs
  in
  let ctx = VarId.Map.of_list input_names in
  let _, body = update_expression def.body ctx in
  { def with body }

(** Remove the meta-information *)
let remove_meta (def : fun_def) : fun_def =
  let obj =
    object
      inherit [_] map_expression as super

      method! visit_Meta env _ e = super#visit_expression env e
    end
  in
  let body = obj#visit_expression () def.body in
  { def with body }

(** Inline the useless variable reassignments (a lot of variable assignments
    like `let x = y in ...ÿ` are introduced through the compilation to MIR
    and by the translation, and the variable used on the left is often unnamed.

    [inline_named]: if `true`, inline all the assignments of the form
    `let VAR = VAR in ...`, otherwise inline only the ones where the variable
    on the left is anonymous.
 *)
let inline_useless_var_reassignments (inline_named : bool) (def : fun_def) :
    fun_def =
  (* Register a substitution.
     When registering that we need to substitute v0 with v1, we check
     if v1 is itself substituted by v2, in which case we register:
     `v0 --> v2` instead of `v0 --> v1`
  *)
  let add_subst v0 v1 m =
    match VarId.Map.find_opt v1 m with
    | None -> VarId.Map.add v0 v1 m
    | Some v2 -> VarId.Map.add v0 v2 m
  in

  let obj =
    object
      inherit [_] map_expression as super

      method! visit_Let env monadic lv re e =
        (* Check that:
         * - the let-binding is not monadic
         * - the left-value is a variable
         * - the assigned expression is a value *)
        match (monadic, lv.value, re) with
        | false, LvVar (Var (lv_var, _)), Value (rv, _) -> (
            (* Check that:
             * - the left variable is unnamed or that [inline_named] is true
             * - the right-value is a variable
             *)
            match ((inline_named, lv_var.basename), rv.value) with
            | (true, _ | false, None), RvPlace { var; projection = [] } ->
                (* Update the environment and explore the next expression
                 * (dropping the currrent let) *)
                let env = add_subst lv_var.id var env in
                super#visit_expression env e
            | _ -> super#visit_Let env monadic lv re e)
        | _ -> super#visit_Let env monadic lv re e
      (** Visit the let-bindings to filter the useless ones (and update
          the substitution map while doing so *)

      method! visit_place env p =
        (* Check if we need to substitute *)
        match VarId.Map.find_opt p.var env with
        | None -> (* No substitution *) p
        | Some nv ->
            (* Substitute *)
            { p with var = nv }
      (** Visit the places used as rvalues, to substitute them if necessary *)
    end
  in
  let body = obj#visit_expression VarId.Map.empty def.body in
  { def with body }

(** Given a forward or backward function call, is there, for every execution
    path, a child backward function called later with exactly the same input
    list prefix? We use this to filter useless function calls: if there are
    such child calls, we can remove this one (in case its outputs are not
    used).
    We do this check because we can't simply remove function calls whose
    outputs are not used, as they might fail. However, if a function fails,
    its children backward functions then fail on the same inputs (ignoring
    the additional inputs those receive).
    
    For instance, if we have:
    ```
    fn f<'a>(x : &'a mut T);
    ```
    
    We often have  things like this in the synthesized code:
    ```
    _ <-- f x;
    ...
    nx <-- f@back'a x y;
    ...
    ```

    In this situation, we can remove the call `f x`.
 *)
let expression_contains_child_call_in_all_paths (ctx : trans_ctx) (call0 : call)
    (e : expression) : bool =
  let check_call call1 : bool =
    (* Check the func_ids, to see if call1's function is a child of call0's function *)
    match (call0.func, call1.func) with
    | Regular (id0, rg_id0), Regular (id1, rg_id1) ->
        (* Both are "regular" calls: check if they come from the same rust function *)
        if id0 = id1 then
          (* Same rust functions: check the regions hierarchy *)
          let call1_is_child =
            match (rg_id0, rg_id1) with
            | None, _ ->
                (* The function used in call0 is the forward function: the one
                 * used in call1 is necessarily a child *)
                true
            | Some _, None ->
                (* Opposite of previous case *)
                false
            | Some rg_id0, Some rg_id1 ->
                if rg_id0 = rg_id1 then true
                else
                  (* We need to use the regions hierarchy *)
                  (* First, lookup the signature of the CFIM function *)
                  let sg =
                    CfimAstUtils.lookup_fun_sig id0 ctx.fun_context.fun_defs
                  in
                  (* Compute the set of ancestors of the function in call1 *)
                  let call1_ancestors =
                    CfimAstUtils.list_parent_region_groups sg rg_id1
                  in
                  (* Check if the function used in call0 is inside *)
                  T.RegionGroupId.Set.mem rg_id0 call1_ancestors
          in
          (* If call1 is a child, then we need to check if the input arguments
           * used in call0 are a prefix of the input arguments used in call1
           * (note call1 being a child, it will likely consume strictly more
           * given back values).
           * *)
          if call1_is_child then
            let call1_args =
              Collections.List.prefix (List.length call0.args) call1.args
            in
            let args = List.combine call0.args call1_args in
            (* Note that the input values are expressions, *which may contain
             * meta-values* (which we need to ignore). We only consider the
             * case where both expressions are actually values. *)
            let input_eq (v0, v1) =
              match (v0, v1) with
              | Value (v0, _), Value (v1, _) -> v0 = v1
              | _ -> false
            in
            call0.type_params = call1.type_params && List.for_all input_eq args
          else (* Not a child *)
            false
        else (* Not the same function *)
          false
    | _ -> false
  in

  let visitor =
    object (self)
      inherit [_] reduce_expression

      method zero _ = false

      method plus b0 b1 _ = b0 () && b1 ()

      method! visit_expression env e =
        match e with
        | Value (_, _) -> fun _ -> false
        | Let (_, _, Call call1, e) ->
            let call_is_child = check_call call1 in
            if call_is_child then fun () -> true
            else self#visit_expression env e
        | Let (_, _, re, e) ->
            fun () ->
              self#visit_expression env re () && self#visit_expression env e ()
        | Call call1 -> fun () -> check_call call1
        | Meta (_, e) -> self#visit_expression env e
        | Switch (_, body) -> self#visit_switch_body env body
      (** We need to reimplement the way we compose the booleans *)

      method! visit_switch_body env body =
        match body with
        | If (e1, e2) ->
            fun () ->
              self#visit_expression env e1 () && self#visit_expression env e2 ()
        | SwitchInt (_, branches, otherwise) ->
            fun () ->
              List.for_all
                (fun (_, br) -> self#visit_expression env br ())
                branches
              && self#visit_expression env otherwise ()
        | Match branches ->
            fun () ->
              List.for_all
                (fun br -> self#visit_expression env br.branch ())
                branches
    end
  in
  visitor#visit_expression () e ()

(** Filter the unused assignments (removes the unused variables, filters
    the function calls) *)
let filter_unused (filter_monadic_calls : bool) (ctx : trans_ctx)
    (def : fun_def) : fun_def =
  (* We first need a transformation on *left-values*, which filters the unused
   * variables and tells us whether the value contains any variable which has
   * not been replaced by `_` (in which case we need to keep the assignment,
   * etc.).
   * 
   * This is implemented as a map-reduce.
   *
   * Returns: ( filtered_left_value, *all_dummies* )
   *
   * `all_dummies`:
   * If the returned boolean is true, it means that all the variables appearing
   * in the filtered left-value are *dummies* (meaning that if this left-value
   * appears at the left of a let-binding, this binding might potentially be
   * removed).
   *)
  let lv_visitor =
    object
      inherit [_] mapreduce_typed_lvalue

      method zero _ = true

      method plus b0 b1 _ = b0 () && b1 ()

      method! visit_var_or_dummy env v =
        match v with
        | Dummy -> (Dummy, fun _ -> true)
        | Var (v, mp) ->
            if VarId.Set.mem v.id env then (Var (v, mp), fun _ -> false)
            else (Dummy, fun _ -> true)
    end
  in
  let filter_typed_lvalue (used_vars : VarId.Set.t) (lv : typed_lvalue) :
      typed_lvalue * bool =
    let lv, all_dummies = lv_visitor#visit_typed_lvalue used_vars lv in
    (lv, all_dummies ())
  in

  (* We then implement the transformation on *expressions* through a mapreduce.
   * Note that the transformation is bottom-up.
   * The map filters the unused assignments, the reduce computes the set of
   * used variables.
   *)
  let expr_visitor =
    object (self)
      inherit [_] mapreduce_expression as super

      method zero _ = VarId.Set.empty

      method plus s0 s1 _ = VarId.Set.union (s0 ()) (s1 ())

      method! visit_place _ p = (p, fun _ -> VarId.Set.singleton p.var)
      (** Whenever we visit a place, we need to register the used variable *)

      method! visit_expression env e =
        match e with
        | Value (_, _) | Call _ | Switch (_, _) | Meta (_, _) ->
            super#visit_expression env e
        | Let (monadic, lv, re, e) ->
            (* Compute the set of values used in the next expression *)
            let e, used = self#visit_expression env e in
            let used = used () in
            (* Filter the left values *)
            let lv, all_dummies = filter_typed_lvalue used lv in
            (* Small utility - called if we can't filter the let-binding *)
            let dont_filter () =
              let re, used_re = self#visit_expression env re in
              let used = VarId.Set.union used (used_re ()) in
              (Let (monadic, lv, re, e), fun _ -> used)
            in
            (* Potentially filter the let-binding *)
            if all_dummies then
              if not monadic then
                (* Not a monadic let-binding: simple case *)
                (e, fun _ -> used)
              else
                (* Monadic let-binding: trickier.
                 * We can filter if the right-expression is a function call,
                 * under some conditions. *)
                match (filter_monadic_calls, re) with
                | true, Call call ->
                    (* We need to check if there is a child call - see
                     * the comments for:
                     * [expression_contains_child_call_in_all_paths] *)
                    let has_child_call =
                      expression_contains_child_call_in_all_paths ctx call e
                    in
                    if has_child_call then (* Filter *)
                      (e, fun _ -> used)
                    else (* No child call: don't filter *)
                      dont_filter ()
                | _ ->
                    (* Not a call or not allowed to filter: we can't filter *)
                    dont_filter ()
            else (* There are used variables: don't filter *)
              dont_filter ()
    end
  in
  (* Visit the body *)
  let body, used_vars = expr_visitor#visit_expression () def.body in
  (* Visit the parameters *)
  let used_vars = used_vars () in
  let inputs_lvs =
    List.map (fun lv -> fst (filter_typed_lvalue used_vars lv)) def.inputs_lvs
  in
  (* Return *)
  { def with body; inputs_lvs }

(** Add unit arguments for functions with no arguments, and change their return type. *)
let to_monadic (def : fun_def) : fun_def =
  (* Update the body *)
  let obj =
    object
      inherit [_] map_expression as super

      method! visit_call env call =
        (* If no arguments, introduce unit *)
        if call.args = [] then
          let args = [ Value (unit_rvalue, None) ] in
          { call with args } (* Otherwise: nothing to do *)
        else super#visit_call env call
    end
  in
  let body = obj#visit_expression () def.body in
  let def = { def with body } in

  (* Update the signature: first the input types *)
  let def =
    if def.inputs = [] then (
      assert (def.signature.inputs = []);
      let signature = { def.signature with inputs = [ unit_ty ] } in
      let var_cnt = get_expression_min_var_counter def.body in
      let id, _ = VarId.fresh var_cnt in
      let var = { id; basename = None; ty = unit_ty } in
      let inputs = [ var ] in
      { def with signature; inputs })
    else def
  in
  (* Then the output type *)
  let output_ty =
    match (def.back_id, def.signature.outputs) with
    | None, [ out_ty ] ->
        (* Forward function: there is always exactly one output *)
        mk_result_ty out_ty
    | Some _, outputs ->
        (* Backward function: we have to group them *)
        mk_result_ty (mk_tuple_ty outputs)
    | _ -> failwith "Unreachable"
  in
  let outputs = [ output_ty ] in
  let signature = { def.signature with outputs } in
  { def with signature }

(** Convert the unit variables to `()` if they are used as right-values or
    `_` if they are used as left values in patterns. *)
let unit_vars_to_unit (def : fun_def) : fun_def =
  (* The map visitor *)
  let obj =
    object
      inherit [_] map_expression as super

      method! visit_var_or_dummy _ v =
        match v with
        | Dummy -> Dummy
        | Var (v, mp) -> if v.ty = unit_ty then Dummy else Var (v, mp)
      (** Replace in lvalues *)

      method! visit_typed_rvalue env rv =
        if rv.ty = unit_ty then unit_rvalue else super#visit_typed_rvalue env rv
      (** Replace in rvalues *)
    end
  in
  (* Update the body *)
  let body = obj#visit_expression () def.body in
  (* Update the input parameters *)
  let inputs_lvs = List.map (obj#visit_typed_lvalue ()) def.inputs_lvs in
  (* Return *)
  { def with body; inputs_lvs }

(** Unfold the monadic let-bindings to explicit matches. *)
let unfold_monadic_let_bindings (ctx : trans_ctx) (def : fun_def) : fun_def =
  def
(* (* It is a very simple map *)
     let obj =
       object
         inherit [_] map_expression as super

         method! visit_Let env monadic lv e re =
          if not monadic then super#visit_Let env monadic lv e re
          else
            let fail_pat = mk_result_fail_lvalue lv.ty in
            let success_pat = mk_result_return_lvalue lv in
            let e = Switch

       end
     in
     (* Update the body *)
     let body = obj#visit_expression () def.body in
     (* Return *)
   { def with body}*)

(** Apply all the micro-passes to a function.

    [ctx]: used only for printing.
 *)
let apply_passes_to_def (config : config) (ctx : trans_ctx) (def : fun_def) :
    fun_def =
  (* Debug *)
  log#ldebug
    (lazy
      ("PureMicroPasses.apply_passes_to_def: "
      ^ Print.name_to_string def.basename
      ^ " ("
      ^ Print.option_to_string T.RegionGroupId.to_string def.back_id
      ^ ")"));

  (* First, find names for the variables which are unnamed *)
  let def = compute_pretty_names def in
  log#ldebug
    (lazy ("compute_pretty_name:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* TODO: we might want to leverage more the assignment meta-data, for
   * aggregates for instance. *)

  (* TODO: reorder the branches of the matches/switches *)

  (* The meta-information is now useless: remove it *)
  let def = remove_meta def in
  log#ldebug (lazy ("remove_meta:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* Add unit arguments for functions with no arguments, and change their return type.
   * **Rk.**: from now onwards, the types in the AST are correct (until now,
   * functions had return type `t` where they should have return type `result t`).
   * Also, from now onwards, the outputs list has length 1. x*)
  let def = to_monadic def in
  log#ldebug (lazy ("to_monadic:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* Convert the unit variables to `()` if they are used as right-values or
   * `_` if they are used as left values. *)
  let def = unit_vars_to_unit def in
  log#ldebug
    (lazy ("unit_vars_to_unit:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* Inline the useless variable reassignments *)
  let inline_named_vars = true in
  let def = inline_useless_var_reassignments inline_named_vars def in
  log#ldebug
    (lazy
      ("inline_useless_var_assignments:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* Filter the unused variables, assignments, function calls, etc. *)
  let def = filter_unused config.filter_unused_monadic_calls ctx def in
  log#ldebug (lazy ("filter_unused:\n\n" ^ fun_def_to_string ctx def ^ "\n"));

  (* Unfold the monadic let-bindings *)
  let def =
    if config.unfold_monadic_let_bindings then (
      let def = unfold_monadic_let_bindings ctx def in
      log#ldebug
        (lazy
          ("unfold_monadic_let_bindings:\n\n" ^ fun_def_to_string ctx def ^ "\n"));
      def)
    else (
      log#ldebug
        (lazy "ignoring unfold_monadic_let_bindings due to the configuration\n");
      def)
  in

  (* We are done *)
  def

let apply_passes_to_pure_fun_translation (config : config) (ctx : trans_ctx)
    (trans : pure_fun_translation) : pure_fun_translation =
  let forward, backwards = trans in
  let forward = apply_passes_to_def config ctx forward in
  let backwards = List.map (apply_passes_to_def config ctx) backwards in
  (forward, backwards)
