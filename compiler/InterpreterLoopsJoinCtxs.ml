module T = Types
module PV = PrimitiveValues
module V = Values
module E = Expressions
module C = Contexts
module Subst = Substitute
module A = LlbcAst
module L = Logging
open TypesUtils
open ValuesUtils
module Inv = Invariants
module S = SynthesizeSymbolic
module UF = UnionFind
open InterpreterUtils
open InterpreterBorrows
open InterpreterLoopsCore
open InterpreterLoopsMatchCtxs

(** The local logger *)
let log = L.loops_join_ctxs_log

(** Reorder the loans and borrows in the fresh abstractions.

    We do this in order to enforce some structure in the environments: this
    allows us to find fixed-points. Note that this function needs to be
    called typically after we merge abstractions together (see {!collapse_ctx}
    for instance).
 *)
let reorder_loans_borrows_in_fresh_abs (old_abs_ids : V.AbstractionId.Set.t)
    (ctx : C.eval_ctx) : C.eval_ctx =
  let reorder_in_fresh_abs (abs : V.abs) : V.abs =
    (* Split between the loans and borrows *)
    let is_borrow (av : V.typed_avalue) : bool =
      match av.V.value with
      | ABorrow _ -> true
      | ALoan _ -> false
      | _ -> raise (Failure "Unexpected")
    in
    let aborrows, aloans = List.partition is_borrow abs.V.avalues in

    (* Reoder the borrows, and the loans.

       After experimenting, it seems that a good way of reordering the loans
       and the borrows to find fixed points is simply to sort them by increasing
       order of id (taking the smallest id of a set of ids, in case of sets).
    *)
    let get_borrow_id (av : V.typed_avalue) : V.BorrowId.id =
      match av.V.value with
      | V.ABorrow (V.AMutBorrow (bid, _) | V.ASharedBorrow bid) -> bid
      | _ -> raise (Failure "Unexpected")
    in
    let get_loan_id (av : V.typed_avalue) : V.BorrowId.id =
      match av.V.value with
      | V.ALoan (V.AMutLoan (lid, _)) -> lid
      | V.ALoan (V.ASharedLoan (lids, _, _)) -> V.BorrowId.Set.min_elt lids
      | _ -> raise (Failure "Unexpected")
    in
    (* We use ordered maps to reorder the borrows and loans *)
    let reorder (get_bid : V.typed_avalue -> V.BorrowId.id)
        (values : V.typed_avalue list) : V.typed_avalue list =
      List.map snd
        (V.BorrowId.Map.bindings
           (V.BorrowId.Map.of_list (List.map (fun v -> (get_bid v, v)) values)))
    in
    let aborrows = reorder get_borrow_id aborrows in
    let aloans = reorder get_loan_id aloans in
    let avalues = List.append aborrows aloans in
    { abs with V.avalues }
  in

  let reorder_in_abs (abs : V.abs) =
    if V.AbstractionId.Set.mem abs.abs_id old_abs_ids then abs
    else reorder_in_fresh_abs abs
  in

  let env = C.env_map_abs reorder_in_abs ctx.env in

  { ctx with C.env }

(** Collapse an environment.

    We do this to simplify an environment, for the purpose of finding a loop
    fixed point.

    We do the following:
    - we look for all the *new* dummy values (we use sets of old ids to decide
      wether a value is new or not) and convert them into abstractions
    - whenever there is a new abstraction in the context, and some of its
      its borrows are associated to loans in another new abstraction, we
      merge them.
    In effect, this allows us to merge newly introduced abstractions/borrows
    with their parent abstractions.
    
    For instance, when evaluating the first loop iteration, we start in the
    following environment:
    {[
      abs@0 { ML l0 }
      ls -> MB l0 (s2 : loops::List<T>)
      i -> s1 : u32
    ]}
    
    and get the following environment upon reaching the [Continue] statement:
    {[
      abs@0 { ML l0 }
      ls -> MB l4 (s@6 : loops::List<T>)
      i -> s@7 : u32
      _@1 -> MB l0 (loops::List::Cons (ML l1, ML l2))
      _@2 -> MB l2 (@Box (ML l4))                      // tail
      _@3 -> MB l1 (s@3 : T)                           // hd
    ]}
    
    In this new environment, the dummy variables [_@1], [_@2] and [_@3] are
    considered as new.
    
    We first convert the new dummy values to abstractions. It gives:
    {[
      abs@0 { ML l0 }
      ls -> MB l4 (s@6 : loops::List<T>)
      i -> s@7 : u32
      abs@1 { MB l0, ML l1, ML l2 }
      abs@2 { MB l2, ML l4 }
      abs@3 { MB l1 }
    ]}

    We finally merge the new abstractions together. It gives:
    {[
      abs@0 { ML l0 }
      ls -> MB l4 (s@6 : loops::List<T>)
      i -> s@7 : u32
      abs@4 { MB l0, ML l4 }
    ]}

    [merge_funs]: those are used to merge loans or borrows which appear in both
    abstractions (rem.: here we mean that, for instance, both abstractions
    contain a shared loan with id l0).
    This can happen when merging environments (note that such environments are not well-formed -
    they become well formed again after collapsing).
 *)
let collapse_ctx (loop_id : V.LoopId.id)
    (merge_funs : merge_duplicates_funcs option) (old_ids : ids_sets)
    (ctx0 : C.eval_ctx) : C.eval_ctx =
  (* Debug *)
  log#ldebug
    (lazy
      ("collapse_ctx:\n\n- fixed_ids:\n" ^ show_ids_sets old_ids
     ^ "\n\n- ctx0:\n" ^ eval_ctx_to_string ctx0 ^ "\n\n"));

  let abs_kind = V.Loop (loop_id, None, LoopSynthInput) in
  let can_end = true in
  let destructure_shared_values = true in
  let is_fresh_abs_id (id : V.AbstractionId.id) : bool =
    not (V.AbstractionId.Set.mem id old_ids.aids)
  in
  let is_fresh_did (id : C.DummyVarId.id) : bool =
    not (C.DummyVarId.Set.mem id old_ids.dids)
  in
  (* Convert the dummy values to abstractions (note that when we convert
     values to abstractions, the resulting abstraction should be destructured) *)
  (* Note that we preserve the order of the dummy values: we replace them with
     abstractions in place - this makes matching easier *)
  let env =
    List.concat
      (List.map
         (fun ee ->
           match ee with
           | C.Abs _ | C.Frame | C.Var (VarBinder _, _) -> [ ee ]
           | C.Var (DummyBinder id, v) ->
               if is_fresh_did id then
                 let absl =
                   convert_value_to_abstractions abs_kind can_end
                     destructure_shared_values ctx0 v
                 in
                 List.map (fun abs -> C.Abs abs) absl
               else [ ee ])
         ctx0.env)
  in
  let ctx = { ctx0 with C.env } in
  log#ldebug
    (lazy
      ("collapse_ctx: after converting values to abstractions:\n"
     ^ show_ids_sets old_ids ^ "\n\n- ctx:\n" ^ eval_ctx_to_string ctx ^ "\n\n"
      ));

  log#ldebug
    (lazy
      ("collapse_ctx: after decomposing the shared values in the abstractions:\n"
     ^ show_ids_sets old_ids ^ "\n\n- ctx:\n" ^ eval_ctx_to_string ctx ^ "\n\n"
      ));

  (* Explore all the *new* abstractions, and compute various maps *)
  let explore (abs : V.abs) = is_fresh_abs_id abs.abs_id in
  let ids_maps =
    compute_abs_borrows_loans_maps (merge_funs = None) explore env
  in
  let {
    abs_ids;
    abs_to_borrows;
    abs_to_loans = _;
    abs_to_borrows_loans;
    borrow_to_abs = _;
    loan_to_abs;
    borrow_loan_to_abs;
  } =
    ids_maps
  in

  (* Change the merging behaviour depending on the input parameters *)
  let abs_to_borrows, loan_to_abs =
    if merge_funs <> None then (abs_to_borrows_loans, borrow_loan_to_abs)
    else (abs_to_borrows, loan_to_abs)
  in

  (* Merge the abstractions together *)
  let merged_abs : V.AbstractionId.id UF.elem V.AbstractionId.Map.t =
    V.AbstractionId.Map.of_list (List.map (fun id -> (id, UF.make id)) abs_ids)
  in

  let ctx = ref ctx in

  (* Merge all the mergeable abs.

     We iterate over the abstractions, then over the borrows in the abstractions.
     We do this because we want to control the order in which abstractions
     are merged (the ids are iterated in increasing order). Otherwise, we
     could simply iterate over all the borrows in [borrow_to_abs]...
  *)
  List.iter
    (fun abs_id0 ->
      let bids = V.AbstractionId.Map.find abs_id0 abs_to_borrows in
      let bids = V.BorrowId.Set.elements bids in
      List.iter
        (fun bid ->
          match V.BorrowId.Map.find_opt bid loan_to_abs with
          | None -> (* Nothing to do *) ()
          | Some abs_ids1 ->
              V.AbstractionId.Set.iter
                (fun abs_id1 ->
                  (* We need to merge - unless we have already merged *)
                  (* First, find the representatives for the two abstractions (the
                     representative is the abstraction into which we merged) *)
                  let abs_ref0 =
                    UF.find (V.AbstractionId.Map.find abs_id0 merged_abs)
                  in
                  let abs_id0 = UF.get abs_ref0 in
                  let abs_ref1 =
                    UF.find (V.AbstractionId.Map.find abs_id1 merged_abs)
                  in
                  let abs_id1 = UF.get abs_ref1 in
                  (* If the two ids are the same, it means the abstractions were already merged *)
                  if abs_id0 = abs_id1 then ()
                  else (
                    (* We actually need to merge the abstractions *)

                    (* Debug *)
                    log#ldebug
                      (lazy
                        ("collapse_ctx: merging abstraction "
                        ^ V.AbstractionId.to_string abs_id1
                        ^ " into "
                        ^ V.AbstractionId.to_string abs_id0
                        ^ ":\n\n" ^ eval_ctx_to_string !ctx));

                    (* Update the environment - pay attention to the order: we
                       we merge [abs_id1] *into* [abs_id0] *)
                    let nctx, abs_id =
                      merge_into_abstraction abs_kind can_end merge_funs !ctx
                        abs_id1 abs_id0
                    in
                    ctx := nctx;

                    (* Update the union find *)
                    let abs_ref_merged = UF.union abs_ref0 abs_ref1 in
                    UF.set abs_ref_merged abs_id))
                abs_ids1)
        bids)
    abs_ids;

  log#ldebug
    (lazy
      ("collapse_ctx:\n\n- fixed_ids:\n" ^ show_ids_sets old_ids
     ^ "\n\n- after collapse:\n" ^ eval_ctx_to_string !ctx ^ "\n\n"));

  (* Reorder the loans and borrows in the fresh abstractions *)
  let ctx = reorder_loans_borrows_in_fresh_abs old_ids.aids !ctx in

  log#ldebug
    (lazy
      ("collapse_ctx:\n\n- fixed_ids:\n" ^ show_ids_sets old_ids
     ^ "\n\n- after collapse and reorder borrows/loans:\n"
     ^ eval_ctx_to_string ctx ^ "\n\n"));

  (* Return the new context *)
  ctx

let mk_collapse_ctx_merge_duplicate_funs (loop_id : V.LoopId.id)
    (ctx : C.eval_ctx) : merge_duplicates_funcs =
  (* Rem.: the merge functions raise exceptions (that we catch). *)
  let module S : MatchJoinState = struct
    let ctx = ctx
    let loop_id = loop_id
    let nabs = ref []
  end in
  let module JM = MakeJoinMatcher (S) in
  let module M = MakeMatcher (JM) in
  (* Functions to match avalues (see {!merge_duplicates_funcs}).

     Those functions are used to merge borrows/loans with the *same ids*.

     They will always be called on destructured avalues (whose children are
     [AIgnored] - we enforce that through sanity checks). We rely on the join
     matcher [JM] to match the concrete values (for shared loans for instance).
     Note that the join matcher doesn't implement match functions for avalues
     (see the comments in {!MakeJoinMatcher}.
  *)
  let merge_amut_borrows id ty0 child0 _ty1 child1 =
    (* Sanity checks *)
    assert (is_aignored child0.V.value);
    assert (is_aignored child1.V.value);

    (* We need to pick a type for the avalue. The types on the left and on the
       right may use different regions: it doesn't really matter (here, we pick
       the one from the left), because we will merge those regions together
       anyway (see the comments for {!merge_into_abstraction}).
    *)
    let ty = ty0 in
    let child = child0 in
    let value = V.ABorrow (V.AMutBorrow (id, child)) in
    { V.value; ty }
  in

  let merge_ashared_borrows id ty0 ty1 =
    (* Sanity checks *)
    let _ =
      let _, ty0, _ = ty_as_ref ty0 in
      let _, ty1, _ = ty_as_ref ty1 in
      assert (not (ty_has_borrows ctx.type_context.type_infos ty0));
      assert (not (ty_has_borrows ctx.type_context.type_infos ty1))
    in

    (* Same remarks as for [merge_amut_borrows] *)
    let ty = ty0 in
    let value = V.ABorrow (V.ASharedBorrow id) in
    { V.value; ty }
  in

  let merge_amut_loans id ty0 child0 _ty1 child1 =
    (* Sanity checks *)
    assert (is_aignored child0.V.value);
    assert (is_aignored child1.V.value);
    (* Same remarks as for [merge_amut_borrows] *)
    let ty = ty0 in
    let child = child0 in
    let value = V.ALoan (V.AMutLoan (id, child)) in
    { V.value; ty }
  in
  let merge_ashared_loans ids ty0 (sv0 : V.typed_value) child0 _ty1
      (sv1 : V.typed_value) child1 =
    (* Sanity checks *)
    assert (is_aignored child0.V.value);
    assert (is_aignored child1.V.value);
    (* Same remarks as for [merge_amut_borrows].

       This time we need to also merge the shared values. We rely on the
       join matcher [JM] to do so.
    *)
    assert (not (value_has_loans_or_borrows ctx sv0.V.value));
    assert (not (value_has_loans_or_borrows ctx sv1.V.value));
    let ty = ty0 in
    let child = child0 in
    let sv = M.match_typed_values ctx sv0 sv1 in
    let value = V.ALoan (V.ASharedLoan (ids, sv, child)) in
    { V.value; ty }
  in
  {
    merge_amut_borrows;
    merge_ashared_borrows;
    merge_amut_loans;
    merge_ashared_loans;
  }

let merge_into_abstraction (loop_id : V.LoopId.id) (abs_kind : V.abs_kind)
    (can_end : bool) (ctx : C.eval_ctx) (aid0 : V.AbstractionId.id)
    (aid1 : V.AbstractionId.id) : C.eval_ctx * V.AbstractionId.id =
  let merge_funs = mk_collapse_ctx_merge_duplicate_funs loop_id ctx in
  merge_into_abstraction abs_kind can_end (Some merge_funs) ctx aid0 aid1

(** Collapse an environment, merging the duplicated borrows/loans.

    This function simply calls {!collapse_ctx} with the proper merging functions.

    We do this because when we join environments, we may introduce duplicated
    loans and borrows. See the explanations for {!join_ctxs}.
 *)
let collapse_ctx_with_merge (loop_id : V.LoopId.id) (old_ids : ids_sets)
    (ctx : C.eval_ctx) : C.eval_ctx =
  let merge_funs = mk_collapse_ctx_merge_duplicate_funs loop_id ctx in
  try collapse_ctx loop_id (Some merge_funs) old_ids ctx
  with ValueMatchFailure _ -> raise (Failure "Unexpected")

let join_ctxs (loop_id : V.LoopId.id) (fixed_ids : ids_sets) (ctx0 : C.eval_ctx)
    (ctx1 : C.eval_ctx) : ctx_or_update =
  (* Debug *)
  log#ldebug
    (lazy
      ("join_ctxs:\n\n- fixed_ids:\n" ^ show_ids_sets fixed_ids
     ^ "\n\n- ctx0:\n"
      ^ eval_ctx_to_string_no_filter ctx0
      ^ "\n\n- ctx1:\n"
      ^ eval_ctx_to_string_no_filter ctx1
      ^ "\n\n"));

  let env0 = List.rev ctx0.env in
  let env1 = List.rev ctx1.env in

  (* We need to pick a context for some functions like [match_typed_values]:
     the context is only used to lookup module data, so we can pick whichever
     we want.
     TODO: this is not very clean. Maybe we should just carry this data around.
  *)
  let ctx = ctx0 in

  let nabs = ref [] in

  (* Explore the environments. *)
  let join_suffixes (env0 : C.env) (env1 : C.env) : C.env =
    (* Debug *)
    log#ldebug
      (lazy
        ("join_suffixes:\n\n- fixed_ids:\n" ^ show_ids_sets fixed_ids
       ^ "\n\n- ctx0:\n"
        ^ eval_ctx_to_string_no_filter { ctx0 with env = List.rev env0 }
        ^ "\n\n- ctx1:\n"
        ^ eval_ctx_to_string_no_filter { ctx1 with env = List.rev env1 }
        ^ "\n\n"));

    (* Sanity check: there are no values/abstractions which should be in the prefix *)
    let check_valid (ee : C.env_elem) : unit =
      match ee with
      | C.Var (C.VarBinder _, _) ->
          (* Variables are necessarily in the prefix *)
          raise (Failure "Unreachable")
      | Var (C.DummyBinder did, _) ->
          assert (not (C.DummyVarId.Set.mem did fixed_ids.dids))
      | Abs abs ->
          assert (not (V.AbstractionId.Set.mem abs.abs_id fixed_ids.aids))
      | Frame ->
          (* This should have been eliminated *)
          raise (Failure "Unreachable")
    in
    List.iter check_valid env0;
    List.iter check_valid env1;
    (* Concatenate the suffixes and append the abstractions introduced while
       joining the prefixes *)
    let absl = List.map (fun abs -> C.Abs abs) (List.rev !nabs) in
    List.concat [ env0; env1; absl ]
  in

  let module S : MatchJoinState = struct
    (* The context is only used to lookup module data: we can pick whichever we want *)
    let ctx = ctx
    let loop_id = loop_id
    let nabs = nabs
  end in
  let module JM = MakeJoinMatcher (S) in
  let module M = MakeMatcher (JM) in
  (* Rem.: this function raises exceptions *)
  let rec join_prefixes (env0 : C.env) (env1 : C.env) : C.env =
    match (env0, env1) with
    | ( (C.Var (C.DummyBinder b0, v0) as var0) :: env0',
        (C.Var (C.DummyBinder b1, v1) as var1) :: env1' ) ->
        (* Debug *)
        log#ldebug
          (lazy
            ("join_prefixes: DummyBinders:\n\n- fixed_ids:\n" ^ "\n"
           ^ show_ids_sets fixed_ids ^ "\n\n- value0:\n"
            ^ env_elem_to_string ctx var0
            ^ "\n\n- value1:\n"
            ^ env_elem_to_string ctx var1
            ^ "\n\n"));

        (* Two cases: the dummy value is an old value, in which case the bindings
           must be the same and we must join their values. Otherwise, it means we
           are not in the prefix anymore *)
        if C.DummyVarId.Set.mem b0 fixed_ids.dids then (
          (* Still in the prefix: match the values *)
          assert (b0 = b1);
          let b = b0 in
          let v = M.match_typed_values ctx v0 v1 in
          let var = C.Var (C.DummyBinder b, v) in
          (* Continue *)
          var :: join_prefixes env0' env1')
        else (* Not in the prefix anymore *)
          join_suffixes env0 env1
    | ( (C.Var (C.VarBinder b0, v0) as var0) :: env0',
        (C.Var (C.VarBinder b1, v1) as var1) :: env1' ) ->
        (* Debug *)
        log#ldebug
          (lazy
            ("join_prefixes: VarBinders:\n\n- fixed_ids:\n" ^ "\n"
           ^ show_ids_sets fixed_ids ^ "\n\n- value0:\n"
            ^ env_elem_to_string ctx var0
            ^ "\n\n- value1:\n"
            ^ env_elem_to_string ctx var1
            ^ "\n\n"));

        (* Variable bindings *must* be in the prefix and consequently their
           ids must be the same *)
        assert (b0 = b1);
        (* Match the values *)
        let b = b0 in
        let v = M.match_typed_values ctx v0 v1 in
        let var = C.Var (C.VarBinder b, v) in
        (* Continue *)
        var :: join_prefixes env0' env1'
    | (C.Abs abs0 as abs) :: env0', C.Abs abs1 :: env1' ->
        (* Debug *)
        log#ldebug
          (lazy
            ("join_prefixes: Abs:\n\n- fixed_ids:\n" ^ "\n"
           ^ show_ids_sets fixed_ids ^ "\n\n- abs0:\n" ^ abs_to_string ctx abs0
           ^ "\n\n- abs1:\n" ^ abs_to_string ctx abs1 ^ "\n\n"));

        (* Same as for the dummy values: there are two cases *)
        if V.AbstractionId.Set.mem abs0.abs_id fixed_ids.aids then (
          (* Still in the prefix: the abstractions must be the same *)
          assert (abs0 = abs1);
          (* Continue *)
          abs :: join_prefixes env0' env1')
        else (* Not in the prefix anymore *)
          join_suffixes env0 env1
    | _ ->
        (* The elements don't match: we are not in the prefix anymore *)
        join_suffixes env0 env1
  in

  try
    (* Remove the frame delimiter (the first element of an environment is a frame delimiter) *)
    let env0, env1 =
      match (env0, env1) with
      | C.Frame :: env0, C.Frame :: env1 -> (env0, env1)
      | _ -> raise (Failure "Unreachable")
    in

    log#ldebug
      (lazy
        ("- env0:\n" ^ C.show_env env0 ^ "\n\n- env1:\n" ^ C.show_env env1
       ^ "\n\n"));

    let env = List.rev (C.Frame :: join_prefixes env0 env1) in

    (* Construct the joined context - of course, the type, fun, etc. contexts
     * should be the same in the two contexts *)
    let {
      C.type_context;
      fun_context;
      global_context;
      region_groups;
      type_vars;
      const_generic_vars;
      env = _;
      ended_regions = ended_regions0;
    } =
      ctx0
    in
    let {
      C.type_context = _;
      fun_context = _;
      global_context = _;
      region_groups = _;
      type_vars = _;
      const_generic_vars = _;
      env = _;
      ended_regions = ended_regions1;
    } =
      ctx1
    in
    let ended_regions = T.RegionId.Set.union ended_regions0 ended_regions1 in
    Ok
      {
        C.type_context;
        fun_context;
        global_context;
        region_groups;
        type_vars;
        const_generic_vars;
        env;
        ended_regions;
      }
  with ValueMatchFailure e -> Error e

(** Destructure all the new abstractions *)
let destructure_new_abs (loop_id : V.LoopId.id)
    (old_abs_ids : V.AbstractionId.Set.t) (ctx : C.eval_ctx) : C.eval_ctx =
  let abs_kind = V.Loop (loop_id, None, V.LoopSynthInput) in
  let can_end = true in
  let destructure_shared_values = true in
  let is_fresh_abs_id (id : V.AbstractionId.id) : bool =
    not (V.AbstractionId.Set.mem id old_abs_ids)
  in
  let env =
    C.env_map_abs
      (fun abs ->
        if is_fresh_abs_id abs.abs_id then
          let abs =
            destructure_abs abs_kind can_end destructure_shared_values ctx abs
          in
          abs
        else abs)
      ctx.env
  in
  { ctx with env }

(** Refresh the ids of the fresh abstractions.

    We do this because {!prepare_ashared_loans} introduces some non-fixed
    abstractions in contexts which are later joined: we have to make sure two
    contexts we join don't have non-fixed abstractions with the same ids.
  *)
let refresh_abs (old_abs : V.AbstractionId.Set.t) (ctx : C.eval_ctx) :
    C.eval_ctx =
  let ids, _ = compute_context_ids ctx in
  let abs_to_refresh = V.AbstractionId.Set.diff ids.aids old_abs in
  let aids_subst =
    List.map
      (fun id -> (id, C.fresh_abstraction_id ()))
      (V.AbstractionId.Set.elements abs_to_refresh)
  in
  let aids_subst = V.AbstractionId.Map.of_list aids_subst in
  let subst id =
    match V.AbstractionId.Map.find_opt id aids_subst with
    | None -> id
    | Some id -> id
  in
  let env =
    Subst.env_subst_ids
      (fun x -> x)
      (fun x -> x)
      (fun x -> x)
      (fun x -> x)
      (fun x -> x)
      (fun x -> x)
      subst ctx.env
  in
  { ctx with C.env }

let loop_join_origin_with_continue_ctxs (config : C.config)
    (loop_id : V.LoopId.id) (fixed_ids : ids_sets) (old_ctx : C.eval_ctx)
    (ctxl : C.eval_ctx list) : (C.eval_ctx * C.eval_ctx list) * C.eval_ctx =
  (* # Join with the new contexts, one by one

     For every context, we repeteadly attempt to join it with the current
     result of the join: if we fail (because we need to end loans for instance),
     we update the context and retry.
     Rem.: we should never have to end loans in the aggregated context, only
     in the one we are trying to add to the join.
  *)
  let joined_ctx = ref old_ctx in
  let rec join_one_aux (ctx : C.eval_ctx) : C.eval_ctx =
    match join_ctxs loop_id fixed_ids !joined_ctx ctx with
    | Ok nctx ->
        joined_ctx := nctx;
        ctx
    | Error err ->
        let ctx =
          match err with
          | LoanInRight bid ->
              InterpreterBorrows.end_borrow_no_synth config bid ctx
          | LoansInRight bids ->
              InterpreterBorrows.end_borrows_no_synth config bids ctx
          | AbsInRight _ | AbsInLeft _ | LoanInLeft _ | LoansInLeft _ ->
              raise (Failure "Unexpected")
        in
        join_one_aux ctx
  in
  let join_one (ctx : C.eval_ctx) : C.eval_ctx =
    log#ldebug
      (lazy
        ("loop_join_origin_with_continue_ctxs:join_one: initial ctx:\n"
       ^ eval_ctx_to_string ctx));

    (* Destructure the abstractions introduced in the new context *)
    let ctx = destructure_new_abs loop_id fixed_ids.aids ctx in
    log#ldebug
      (lazy
        ("loop_join_origin_with_continue_ctxs:join_one: after destructure:\n"
       ^ eval_ctx_to_string ctx));

    (* Collapse the context we want to add to the join *)
    let ctx = collapse_ctx loop_id None fixed_ids ctx in
    log#ldebug
      (lazy
        ("loop_join_origin_with_continue_ctxs:join_one: after collapse:\n"
       ^ eval_ctx_to_string ctx));

    (* Refresh the fresh abstractions *)
    let ctx = refresh_abs fixed_ids.aids ctx in

    (* Join the two contexts  *)
    let ctx1 = join_one_aux ctx in
    log#ldebug
      (lazy
        ("loop_join_origin_with_continue_ctxs:join_one: after join:\n"
       ^ eval_ctx_to_string ctx1));

    (* Collapse again - the join might have introduce abstractions we want
       to merge with the others (note that those abstractions may actually
       lead to borrows/loans duplications) *)
    joined_ctx := collapse_ctx_with_merge loop_id fixed_ids !joined_ctx;
    log#ldebug
      (lazy
        ("loop_join_origin_with_continue_ctxs:join_one: after join-collapse:\n"
        ^ eval_ctx_to_string !joined_ctx));

    (* Sanity check *)
    if !Config.check_invariants then Invariants.check_invariants !joined_ctx;
    (* Return *)
    ctx1
  in

  let ctxl = List.map join_one ctxl in

  (* # Return *)
  ((old_ctx, ctxl), !joined_ctx)
