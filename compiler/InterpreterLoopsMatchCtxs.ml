(** This module implements support to match contexts for loops.

    The matching functions are used for instance to compute joins, or
    to check if two contexts are equivalent (modulo conversion).
 *)

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
open Cps
open InterpreterUtils
open InterpreterBorrows
open InterpreterLoopsCore

(** The local logger *)
let log = L.loops_match_ctxs_log

let compute_abs_borrows_loans_maps (no_duplicates : bool)
    (explore : V.abs -> bool) (env : C.env) : abs_borrows_loans_maps =
  let abs_ids = ref [] in
  let abs_to_borrows = ref V.AbstractionId.Map.empty in
  let abs_to_loans = ref V.AbstractionId.Map.empty in
  let abs_to_borrows_loans = ref V.AbstractionId.Map.empty in
  let borrow_to_abs = ref V.BorrowId.Map.empty in
  let loan_to_abs = ref V.BorrowId.Map.empty in
  let borrow_loan_to_abs = ref V.BorrowId.Map.empty in

  let module R (Id0 : Identifiers.Id) (Id1 : Identifiers.Id) = struct
    (*
       [check_singleton_sets]: check that the mapping maps to a singletong.
       [check_not_already_registered]: check if the mapping was not already registered.
    *)
    let register_mapping (check_singleton_sets : bool)
        (check_not_already_registered : bool) (map : Id1.Set.t Id0.Map.t ref)
        (id0 : Id0.id) (id1 : Id1.id) : unit =
      (* Sanity check *)
      (if check_singleton_sets || check_not_already_registered then
         match Id0.Map.find_opt id0 !map with
         | None -> ()
         | Some set ->
             assert (
               (not check_not_already_registered) || not (Id1.Set.mem id1 set)));
      (* Update the mapping *)
      map :=
        Id0.Map.update id0
          (fun ids ->
            match ids with
            | None -> Some (Id1.Set.singleton id1)
            | Some ids ->
                (* Sanity check *)
                assert (not check_singleton_sets);
                assert (
                  (not check_not_already_registered)
                  || not (Id1.Set.mem id1 ids));
                (* Update *)
                Some (Id1.Set.add id1 ids))
          !map
  end in
  let module RAbsBorrow = R (V.AbstractionId) (V.BorrowId) in
  let module RBorrowAbs = R (V.BorrowId) (V.AbstractionId) in
  let register_borrow_id abs_id bid =
    RAbsBorrow.register_mapping false no_duplicates abs_to_borrows abs_id bid;
    RAbsBorrow.register_mapping false false abs_to_borrows_loans abs_id bid;
    RBorrowAbs.register_mapping no_duplicates no_duplicates borrow_to_abs bid
      abs_id;
    RBorrowAbs.register_mapping false false borrow_loan_to_abs bid abs_id
  in

  let register_loan_id abs_id bid =
    RAbsBorrow.register_mapping false no_duplicates abs_to_loans abs_id bid;
    RAbsBorrow.register_mapping false false abs_to_borrows_loans abs_id bid;
    RBorrowAbs.register_mapping no_duplicates no_duplicates loan_to_abs bid
      abs_id;
    RBorrowAbs.register_mapping false false borrow_loan_to_abs bid abs_id
  in

  let explore_abs =
    object (self : 'self)
      inherit [_] V.iter_typed_avalue as super

      (** Make sure we don't register the ignored ids *)
      method! visit_aloan_content abs_id lc =
        match lc with
        | AMutLoan _ | ASharedLoan _ ->
            (* Process those normally *)
            super#visit_aloan_content abs_id lc
        | AIgnoredMutLoan (_, child)
        | AEndedIgnoredMutLoan { child; given_back = _; given_back_meta = _ }
        | AIgnoredSharedLoan child ->
            (* Ignore the id of the loan, if there is *)
            self#visit_typed_avalue abs_id child
        | AEndedMutLoan _ | AEndedSharedLoan _ -> raise (Failure "Unreachable")

      (** Make sure we don't register the ignored ids *)
      method! visit_aborrow_content abs_id bc =
        match bc with
        | AMutBorrow _ | ASharedBorrow _ | AProjSharedBorrow _ ->
            (* Process those normally *)
            super#visit_aborrow_content abs_id bc
        | AIgnoredMutBorrow (_, child)
        | AEndedIgnoredMutBorrow { child; given_back = _; given_back_meta = _ }
          ->
            (* Ignore the id of the borrow, if there is *)
            self#visit_typed_avalue abs_id child
        | AEndedMutBorrow _ | AEndedSharedBorrow ->
            raise (Failure "Unreachable")

      method! visit_borrow_id abs_id bid = register_borrow_id abs_id bid
      method! visit_loan_id abs_id lid = register_loan_id abs_id lid
    end
  in

  C.env_iter_abs
    (fun abs ->
      let abs_id = abs.abs_id in
      if explore abs then (
        abs_to_borrows :=
          V.AbstractionId.Map.add abs_id V.BorrowId.Set.empty !abs_to_borrows;
        abs_to_loans :=
          V.AbstractionId.Map.add abs_id V.BorrowId.Set.empty !abs_to_loans;
        abs_ids := abs.abs_id :: !abs_ids;
        List.iter (explore_abs#visit_typed_avalue abs.abs_id) abs.avalues)
      else ())
    env;

  (* Rem.: there is no need to reverse the abs ids, because we explored the environment
     starting with the freshest values and abstractions *)
  {
    abs_ids = !abs_ids;
    abs_to_borrows = !abs_to_borrows;
    abs_to_loans = !abs_to_loans;
    abs_to_borrows_loans = !abs_to_borrows_loans;
    borrow_to_abs = !borrow_to_abs;
    loan_to_abs = !loan_to_abs;
    borrow_loan_to_abs = !borrow_loan_to_abs;
  }

(** Match two types during a join. *)
let rec match_types (match_distinct_types : 'r T.ty -> 'r T.ty -> 'r T.ty)
    (match_regions : 'r -> 'r -> 'r) (ty0 : 'r T.ty) (ty1 : 'r T.ty) : 'r T.ty =
  let match_rec = match_types match_distinct_types match_regions in
  match (ty0, ty1) with
  | Adt (id0, regions0, tys0, cgs0), Adt (id1, regions1, tys1, cgs1) ->
      assert (id0 = id1);
      assert (cgs0 = cgs1);
      let id = id0 in
      let cgs = cgs1 in
      let regions =
        List.map
          (fun (id0, id1) -> match_regions id0 id1)
          (List.combine regions0 regions1)
      in
      let tys =
        List.map (fun (ty0, ty1) -> match_rec ty0 ty1) (List.combine tys0 tys1)
      in
      Adt (id, regions, tys, cgs)
  | TypeVar vid0, TypeVar vid1 ->
      assert (vid0 = vid1);
      let vid = vid0 in
      TypeVar vid
  | Literal lty0, Literal lty1 ->
      assert (lty0 = lty1);
      ty0
  | Never, Never -> ty0
  | Ref (r0, ty0, k0), Ref (r1, ty1, k1) ->
      let r = match_regions r0 r1 in
      let ty = match_rec ty0 ty1 in
      assert (k0 = k1);
      let k = k0 in
      Ref (r, ty, k)
  | _ -> match_distinct_types ty0 ty1

module MakeMatcher (M : PrimMatcher) : Matcher = struct
  let rec match_typed_values (ctx : C.eval_ctx) (v0 : V.typed_value)
      (v1 : V.typed_value) : V.typed_value =
    let match_rec = match_typed_values ctx in
    let ty = M.match_etys v0.V.ty v1.V.ty in
    match (v0.V.value, v1.V.value) with
    | V.Literal lv0, V.Literal lv1 ->
        if lv0 = lv1 then v1 else M.match_distinct_literals ty lv0 lv1
    | V.Adt av0, V.Adt av1 ->
        if av0.variant_id = av1.variant_id then
          let fields = List.combine av0.field_values av1.field_values in
          let field_values =
            List.map (fun (f0, f1) -> match_rec f0 f1) fields
          in
          let value : V.value =
            V.Adt { variant_id = av0.variant_id; field_values }
          in
          { V.value; ty = v1.V.ty }
        else (
          (* For now, we don't merge ADTs which contain borrows *)
          assert (not (value_has_borrows ctx v0.V.value));
          assert (not (value_has_borrows ctx v1.V.value));
          (* Merge *)
          M.match_distinct_adts ty av0 av1)
    | Bottom, Bottom -> v0
    | Borrow bc0, Borrow bc1 ->
        let bc =
          match (bc0, bc1) with
          | SharedBorrow bid0, SharedBorrow bid1 ->
              let bid = M.match_shared_borrows match_rec ty bid0 bid1 in
              V.SharedBorrow bid
          | MutBorrow (bid0, bv0), MutBorrow (bid1, bv1) ->
              let bv = match_rec bv0 bv1 in
              assert (not (value_has_borrows ctx bv.V.value));
              let bid, bv = M.match_mut_borrows ty bid0 bv0 bid1 bv1 bv in
              V.MutBorrow (bid, bv)
          | ReservedMutBorrow _, _
          | _, ReservedMutBorrow _
          | SharedBorrow _, MutBorrow _
          | MutBorrow _, SharedBorrow _ ->
              (* If we get here, either there is a typing inconsistency, or we are
                 trying to match a reserved borrow, which shouldn't happen because
                 reserved borrow should be eliminated very quickly - they are introduced
                 just before function calls which activate them *)
              raise (Failure "Unexpected")
        in
        { V.value = V.Borrow bc; ty }
    | Loan lc0, Loan lc1 ->
        (* TODO: maybe we should enforce that the ids are always exactly the same -
           without matching *)
        let lc =
          match (lc0, lc1) with
          | SharedLoan (ids0, sv0), SharedLoan (ids1, sv1) ->
              let sv = match_rec sv0 sv1 in
              assert (not (value_has_borrows ctx sv.V.value));
              let ids, sv = M.match_shared_loans ty ids0 ids1 sv in
              V.SharedLoan (ids, sv)
          | MutLoan id0, MutLoan id1 ->
              let id = M.match_mut_loans ty id0 id1 in
              V.MutLoan id
          | SharedLoan _, MutLoan _ | MutLoan _, SharedLoan _ ->
              raise (Failure "Unreachable")
        in
        { V.value = Loan lc; ty = v1.V.ty }
    | Symbolic sv0, Symbolic sv1 ->
        (* For now, we force all the symbolic values containing borrows to
           be eagerly expanded, and we don't support nested borrows *)
        assert (not (value_has_borrows ctx v0.V.value));
        assert (not (value_has_borrows ctx v1.V.value));
        (* Match *)
        let sv = M.match_symbolic_values sv0 sv1 in
        { v1 with V.value = V.Symbolic sv }
    | Loan lc, _ -> (
        match lc with
        | SharedLoan (ids, _) -> raise (ValueMatchFailure (LoansInLeft ids))
        | MutLoan id -> raise (ValueMatchFailure (LoanInLeft id)))
    | _, Loan lc -> (
        match lc with
        | SharedLoan (ids, _) -> raise (ValueMatchFailure (LoansInRight ids))
        | MutLoan id -> raise (ValueMatchFailure (LoanInRight id)))
    | Symbolic sv, _ -> M.match_symbolic_with_other true sv v1
    | _, Symbolic sv -> M.match_symbolic_with_other false sv v0
    | Bottom, _ -> M.match_bottom_with_other true v1
    | _, Bottom -> M.match_bottom_with_other false v0
    | _ ->
        log#ldebug
          (lazy
            ("Unexpected match case:\n- value0: "
            ^ typed_value_to_string ctx v0
            ^ "\n- value1: "
            ^ typed_value_to_string ctx v1));
        raise (Failure "Unexpected match case")

  and match_typed_avalues (ctx : C.eval_ctx) (v0 : V.typed_avalue)
      (v1 : V.typed_avalue) : V.typed_avalue =
    log#ldebug
      (lazy
        ("match_typed_avalues:\n- value0: "
        ^ typed_avalue_to_string ctx v0
        ^ "\n- value1: "
        ^ typed_avalue_to_string ctx v1));

    let match_rec = match_typed_values ctx in
    let match_arec = match_typed_avalues ctx in
    let ty = M.match_rtys v0.V.ty v1.V.ty in
    match (v0.V.value, v1.V.value) with
    | V.AAdt av0, V.AAdt av1 ->
        if av0.variant_id = av1.variant_id then
          let fields = List.combine av0.field_values av1.field_values in
          let field_values =
            List.map (fun (f0, f1) -> match_arec f0 f1) fields
          in
          let value : V.avalue =
            V.AAdt { variant_id = av0.variant_id; field_values }
          in
          { V.value; ty }
        else (* Merge *)
          M.match_distinct_aadts v0.V.ty av0 v1.V.ty av1 ty
    | ABottom, ABottom -> mk_abottom ty
    | AIgnored, AIgnored -> mk_aignored ty
    | ABorrow bc0, ABorrow bc1 -> (
        log#ldebug (lazy "match_typed_avalues: borrows");
        match (bc0, bc1) with
        | ASharedBorrow bid0, ASharedBorrow bid1 ->
            log#ldebug (lazy "match_typed_avalues: shared borrows");
            M.match_ashared_borrows v0.V.ty bid0 v1.V.ty bid1 ty
        | AMutBorrow (bid0, av0), AMutBorrow (bid1, av1) ->
            log#ldebug (lazy "match_typed_avalues: mut borrows");
            log#ldebug
              (lazy
                "match_typed_avalues: mut borrows: matching children values");
            let av = match_arec av0 av1 in
            log#ldebug
              (lazy "match_typed_avalues: mut borrows: matched children values");
            M.match_amut_borrows v0.V.ty bid0 av0 v1.V.ty bid1 av1 ty av
        | AIgnoredMutBorrow _, AIgnoredMutBorrow _ ->
            (* The abstractions are destructured: we shouldn't get there *)
            raise (Failure "Unexpected")
        | AProjSharedBorrow asb0, AProjSharedBorrow asb1 -> (
            match (asb0, asb1) with
            | [], [] ->
                (* This case actually stands for ignored shared borrows, when
                   there are no nested borrows *)
                v0
            | _ ->
                (* We should get there only if there are nested borrows *)
                raise (Failure "Unexpected"))
        | _ ->
            (* TODO: getting there is not necessarily inconsistent (it may
               just be because the environments don't match) so we may want
               to call a specific function (which could raise the proper
               exception).
               Rem.: we shouldn't get to the ended borrow cases, because
               an abstraction should never contain ended borrows unless
               we are *currently* ending it, in which case we need
               to completely end it before continuing.
            *)
            raise (Failure "Unexpected"))
    | ALoan lc0, ALoan lc1 -> (
        log#ldebug (lazy "match_typed_avalues: loans");
        (* TODO: maybe we should enforce that the ids are always exactly the same -
           without matching *)
        match (lc0, lc1) with
        | ASharedLoan (ids0, sv0, av0), ASharedLoan (ids1, sv1, av1) ->
            log#ldebug (lazy "match_typed_avalues: shared loans");
            let sv = match_rec sv0 sv1 in
            let av = match_arec av0 av1 in
            assert (not (value_has_borrows ctx sv.V.value));
            M.match_ashared_loans v0.V.ty ids0 sv0 av0 v1.V.ty ids1 sv1 av1 ty
              sv av
        | AMutLoan (id0, av0), AMutLoan (id1, av1) ->
            log#ldebug (lazy "match_typed_avalues: mut loans");
            log#ldebug
              (lazy "match_typed_avalues: mut loans: matching children values");
            let av = match_arec av0 av1 in
            log#ldebug
              (lazy "match_typed_avalues: mut loans: matched children values");
            M.match_amut_loans v0.V.ty id0 av0 v1.V.ty id1 av1 ty av
        | AIgnoredMutLoan _, AIgnoredMutLoan _
        | AIgnoredSharedLoan _, AIgnoredSharedLoan _ ->
            (* Those should have been filtered when destructuring the abstractions -
               they are necessary only when there are nested borrows *)
            raise (Failure "Unreachable")
        | _ -> raise (Failure "Unreachable"))
    | ASymbolic _, ASymbolic _ ->
        (* For now, we force all the symbolic values containing borrows to
           be eagerly expanded, and we don't support nested borrows *)
        raise (Failure "Unreachable")
    | _ -> M.match_avalues v0 v1
end

module MakeJoinMatcher (S : MatchJoinState) : PrimMatcher = struct
  (** Small utility *)
  let push_abs (abs : V.abs) : unit = S.nabs := abs :: !S.nabs

  let push_absl (absl : V.abs list) : unit = List.iter push_abs absl

  let match_etys ty0 ty1 =
    assert (ty0 = ty1);
    ty0

  let match_rtys ty0 ty1 =
    (* The types must be equal - in effect, this forbids to match symbolic
       values containing borrows *)
    assert (ty0 = ty1);
    ty0

  let match_distinct_literals (ty : T.ety) (_ : V.literal) (_ : V.literal) :
      V.typed_value =
    mk_fresh_symbolic_typed_value_from_ety V.LoopJoin ty

  let match_distinct_adts (ty : T.ety) (adt0 : V.adt_value) (adt1 : V.adt_value)
      : V.typed_value =
    (* Check that the ADTs don't contain borrows - this is redundant with checks
       performed by the caller, but we prefer to be safe with regards to future
       updates
    *)
    let check_no_borrows (v : V.typed_value) =
      assert (not (value_has_borrows S.ctx v.V.value))
    in
    List.iter check_no_borrows adt0.field_values;
    List.iter check_no_borrows adt1.field_values;

    (* Check if there are loans: we request to end them *)
    let check_loans (left : bool) (fields : V.typed_value list) : unit =
      match InterpreterBorrowsCore.get_first_loan_in_values fields with
      | Some (V.SharedLoan (ids, _)) ->
          if left then raise (ValueMatchFailure (LoansInLeft ids))
          else raise (ValueMatchFailure (LoansInRight ids))
      | Some (V.MutLoan id) ->
          if left then raise (ValueMatchFailure (LoanInLeft id))
          else raise (ValueMatchFailure (LoanInRight id))
      | None -> ()
    in
    check_loans true adt0.field_values;
    check_loans false adt1.field_values;

    (* No borrows, no loans: we can introduce a symbolic value *)
    mk_fresh_symbolic_typed_value_from_ety V.LoopJoin ty

  let match_shared_borrows _ (ty : T.ety) (bid0 : V.borrow_id)
      (bid1 : V.borrow_id) : V.borrow_id =
    if bid0 = bid1 then bid0
    else
      (* We replace bid0 and bid1 with a fresh borrow id, and introduce
         an abstraction which links all of them:
         {[
           { SB bid0, SB bid1, SL {bid2} }
         ]}
      *)
      let rid = C.fresh_region_id () in
      let bid2 = C.fresh_borrow_id () in

      (* Generate a fresh symbolic value for the shared value *)
      let _, bv_ty, kind = ty_as_ref ty in
      let sv = mk_fresh_symbolic_typed_value_from_ety V.LoopJoin bv_ty in

      let borrow_ty =
        mk_ref_ty (T.Var rid) (ety_no_regions_to_rty bv_ty) kind
      in

      (* Generate the avalues for the abstraction *)
      let mk_aborrow (bid : V.borrow_id) : V.typed_avalue =
        let value = V.ABorrow (V.ASharedBorrow bid) in
        { V.value; ty = borrow_ty }
      in
      let borrows = [ mk_aborrow bid0; mk_aborrow bid1 ] in

      let loan =
        V.ASharedLoan
          ( V.BorrowId.Set.singleton bid2,
            sv,
            mk_aignored (ety_no_regions_to_rty bv_ty) )
      in
      (* Note that an aloan has a borrow type *)
      let loan = { V.value = V.ALoan loan; ty = borrow_ty } in

      let avalues = List.append borrows [ loan ] in

      (* Generate the abstraction *)
      let abs =
        {
          V.abs_id = C.fresh_abstraction_id ();
          kind = V.Loop (S.loop_id, None, LoopSynthInput);
          can_end = true;
          parents = V.AbstractionId.Set.empty;
          original_parents = [];
          regions = T.RegionId.Set.singleton rid;
          ancestors_regions = T.RegionId.Set.empty;
          avalues;
        }
      in
      push_abs abs;

      (* Return the new borrow *)
      bid2

  let match_mut_borrows (ty : T.ety) (bid0 : V.borrow_id) (bv0 : V.typed_value)
      (bid1 : V.borrow_id) (bv1 : V.typed_value) (bv : V.typed_value) :
      V.borrow_id * V.typed_value =
    if bid0 = bid1 then (
      (* If the merged value is not the same as the original value, we introduce
         an abstraction:

         {[
           { MB bid0, ML nbid }  // where nbid fresh
         ]}

         and we use bid' for the borrow id that we return.

         We do this because we want to make sure that, whenever a mutably
         borrowed value is modified in a loop iteration, then there is
         a fresh abstraction between this borrowed value and the fixed
         abstractions.

         Example:
         ========
         {[
           fn clear(v: &mut Vec<u32>) {
               let mut i = 0;
               while i < v.len() {
                   v[i] = 0;
                   i += 1;
               }
           }
         ]}

         When entering the loop, we have the following environment:
         {[
           abs'0 { ML l0 } // input abstraction
           v -> MB l0 s0
           i -> 0
         ]}

         At every iteration, we update the symbolic value of the vector [v]
         (i.e., [s0]).

         For now, because the translation of the loop is responsible of the
         execution of the end of the function (up to the [return]), we want
         the loop to reborrow the vector [v]: this way, the forward loop
         function returns nothing (it returns what [clear] returns, that is
         to say [unit]) while the backward loop function gives back a new value
         for [v] (i.e., a new symbolic value which will replace [s0]).

         In the future, we will also compute joins at the *loop exits*: when we
         do so, we won't introduce reborrows like above: the forward loop function
         will update [v], while the backward loop function will return nothing.
      *)
      assert (not (value_has_borrows S.ctx bv.V.value));

      if bv0 = bv1 then (
        assert (bv0 = bv);
        (bid0, bv))
      else
        let rid = C.fresh_region_id () in
        let nbid = C.fresh_borrow_id () in

        let kind = T.Mut in
        let bv_ty = ety_no_regions_to_rty bv.V.ty in
        let borrow_ty = mk_ref_ty (T.Var rid) bv_ty kind in

        let borrow_av =
          let ty = borrow_ty in
          let value = V.ABorrow (V.AMutBorrow (bid0, mk_aignored bv_ty)) in
          mk_typed_avalue ty value
        in

        let loan_av =
          let ty = borrow_ty in
          let value = V.ALoan (V.AMutLoan (nbid, mk_aignored bv_ty)) in
          mk_typed_avalue ty value
        in

        let avalues = [ borrow_av; loan_av ] in

        (* Generate the abstraction *)
        let abs =
          {
            V.abs_id = C.fresh_abstraction_id ();
            kind = V.Loop (S.loop_id, None, LoopSynthInput);
            can_end = true;
            parents = V.AbstractionId.Set.empty;
            original_parents = [];
            regions = T.RegionId.Set.singleton rid;
            ancestors_regions = T.RegionId.Set.empty;
            avalues;
          }
        in
        push_abs abs;

        (* Return the new borrow *)
        (nbid, bv))
    else
      (* We replace bid0 and bid1 with a fresh borrow id, and introduce
         an abstraction which links all of them:
         {[
           { MB bid0, MB bid1, ML bid2 }
         ]}
      *)
      let rid = C.fresh_region_id () in
      let bid2 = C.fresh_borrow_id () in

      (* Generate a fresh symbolic value for the borrowed value *)
      let _, bv_ty, kind = ty_as_ref ty in
      let sv = mk_fresh_symbolic_typed_value_from_ety V.LoopJoin bv_ty in

      let borrow_ty =
        mk_ref_ty (T.Var rid) (ety_no_regions_to_rty bv_ty) kind
      in

      (* Generate the avalues for the abstraction *)
      let mk_aborrow (bid : V.borrow_id) (bv : V.typed_value) : V.typed_avalue =
        let bv_ty = ety_no_regions_to_rty bv.V.ty in
        let value = V.ABorrow (V.AMutBorrow (bid, mk_aignored bv_ty)) in
        { V.value; ty = borrow_ty }
      in
      let borrows = [ mk_aborrow bid0 bv0; mk_aborrow bid1 bv1 ] in

      let loan = V.AMutLoan (bid2, mk_aignored (ety_no_regions_to_rty bv_ty)) in
      (* Note that an aloan has a borrow type *)
      let loan = { V.value = V.ALoan loan; ty = borrow_ty } in

      let avalues = List.append borrows [ loan ] in

      (* Generate the abstraction *)
      let abs =
        {
          V.abs_id = C.fresh_abstraction_id ();
          kind = V.Loop (S.loop_id, None, LoopSynthInput);
          can_end = true;
          parents = V.AbstractionId.Set.empty;
          original_parents = [];
          regions = T.RegionId.Set.singleton rid;
          ancestors_regions = T.RegionId.Set.empty;
          avalues;
        }
      in
      push_abs abs;

      (* Return the new borrow *)
      (bid2, sv)

  let match_shared_loans (_ : T.ety) (ids0 : V.loan_id_set)
      (ids1 : V.loan_id_set) (sv : V.typed_value) :
      V.loan_id_set * V.typed_value =
    (* Check if the ids are the same - Rem.: we forbid the sets of loans
       to be different. However, if we dive inside data-structures (by
       using a shared borrow) the shared values might themselves contain
       shared loans, which need to be matched. For this reason, we destructure
       the shared values (see {!destructure_abs}).
    *)
    let extra_ids_left = V.BorrowId.Set.diff ids0 ids1 in
    let extra_ids_right = V.BorrowId.Set.diff ids1 ids0 in
    if not (V.BorrowId.Set.is_empty extra_ids_left) then
      raise (ValueMatchFailure (LoansInLeft extra_ids_left));
    if not (V.BorrowId.Set.is_empty extra_ids_right) then
      raise (ValueMatchFailure (LoansInRight extra_ids_right));

    (* This should always be true if we get here *)
    assert (ids0 = ids1);
    let ids = ids0 in

    (* Return *)
    (ids, sv)

  let match_mut_loans (_ : T.ety) (id0 : V.loan_id) (id1 : V.loan_id) :
      V.loan_id =
    if id0 = id1 then id0
    else
      (* We forbid this case for now: if we get there, we force to end
         both borrows *)
      raise (ValueMatchFailure (LoanInLeft id0))

  let match_symbolic_values (sv0 : V.symbolic_value) (sv1 : V.symbolic_value) :
      V.symbolic_value =
    let id0 = sv0.sv_id in
    let id1 = sv1.sv_id in
    if id0 = id1 then (
      (* Sanity check *)
      assert (sv0 = sv1);
      (* Return *)
      sv0)
    else (
      (* The caller should have checked that the symbolic values don't contain
         borrows *)
      assert (not (ty_has_borrows S.ctx.type_context.type_infos sv0.sv_ty));
      (* We simply introduce a fresh symbolic value *)
      mk_fresh_symbolic_value V.LoopJoin sv0.sv_ty)

  let match_symbolic_with_other (left : bool) (sv : V.symbolic_value)
      (v : V.typed_value) : V.typed_value =
    (* Check that:
       - there are no borrows in the symbolic value
       - there are no borrows in the "regular" value
       If there are loans in the regular value, raise an exception.
    *)
    assert (not (ty_has_borrows S.ctx.type_context.type_infos sv.sv_ty));
    assert (not (value_has_borrows S.ctx v.V.value));
    let value_is_left = not left in
    (match InterpreterBorrowsCore.get_first_loan_in_value v with
    | None -> ()
    | Some (SharedLoan (ids, _)) ->
        if value_is_left then raise (ValueMatchFailure (LoansInLeft ids))
        else raise (ValueMatchFailure (LoansInRight ids))
    | Some (MutLoan id) ->
        if value_is_left then raise (ValueMatchFailure (LoanInLeft id))
        else raise (ValueMatchFailure (LoanInRight id)));
    (* Return a fresh symbolic value *)
    mk_fresh_symbolic_typed_value V.LoopJoin sv.sv_ty

  let match_bottom_with_other (left : bool) (v : V.typed_value) : V.typed_value
      =
    (* If there are outer loans in the non-bottom value, raise an exception.
       Otherwise, convert it to an abstraction and return [Bottom].
    *)
    let with_borrows = false in
    let value_is_left = not left in
    match
      InterpreterBorrowsCore.get_first_outer_loan_or_borrow_in_value
        with_borrows v
    with
    | Some (BorrowContent _) -> raise (Failure "Unreachable")
    | Some (LoanContent lc) -> (
        match lc with
        | V.SharedLoan (ids, _) ->
            if value_is_left then raise (ValueMatchFailure (LoansInLeft ids))
            else raise (ValueMatchFailure (LoansInRight ids))
        | V.MutLoan id ->
            if value_is_left then raise (ValueMatchFailure (LoanInLeft id))
            else raise (ValueMatchFailure (LoanInRight id)))
    | None ->
        (* Convert the value to an abstraction *)
        let abs_kind = V.Loop (S.loop_id, None, LoopSynthInput) in
        let can_end = true in
        let destructure_shared_values = true in
        let absl =
          convert_value_to_abstractions abs_kind can_end
            destructure_shared_values S.ctx v
        in
        push_absl absl;
        (* Return [Bottom] *)
        mk_bottom v.V.ty

  (* As explained in comments: we don't use the join matcher to join avalues,
     only concrete values *)

  let match_distinct_aadts _ _ _ _ _ = raise (Failure "Unreachable")
  let match_ashared_borrows _ _ _ _ = raise (Failure "Unreachable")
  let match_amut_borrows _ _ _ _ _ _ _ _ = raise (Failure "Unreachable")
  let match_ashared_loans _ _ _ _ _ _ _ _ _ _ _ = raise (Failure "Unreachable")
  let match_amut_loans _ _ _ _ _ _ _ _ = raise (Failure "Unreachable")
  let match_avalues _ _ = raise (Failure "Unreachable")
end

module MakeCheckEquivMatcher (S : MatchCheckEquivState) : CheckEquivMatcher =
struct
  module MkGetSetM (Id : Identifiers.Id) = struct
    module Inj = Id.InjSubst

    let add (msg : string) (m : Inj.t ref) (k0 : Id.id) (k1 : Id.id) =
      (* Check if k0 is already registered as a key *)
      match Inj.find_opt k0 !m with
      | None ->
          (* Not registered: check if k1 is in the set of values,
             otherwise add the binding *)
          if Inj.Set.mem k1 (Inj.elements !m) then
            raise
              (Distinct
                 (msg ^ "adding [k0=" ^ Id.to_string k0 ^ " -> k1="
                ^ Id.to_string k1 ^ " ]: k1 already in the set of elements"))
          else (
            m := Inj.add k0 k1 !m;
            k1)
      | Some k1' ->
          (* It is: check that the bindings are consistent *)
          if k1 <> k1' then raise (Distinct (msg ^ "already a binding for k0"))
          else k1

    let match_e (msg : string) (m : Inj.t ref) (k0 : Id.id) (k1 : Id.id) : Id.id
        =
      (* TODO: merge the add and merge functions *)
      add msg m k0 k1

    let match_el (msg : string) (m : Inj.t ref) (kl0 : Id.id list)
        (kl1 : Id.id list) : Id.id list =
      List.map (fun (k0, k1) -> match_e msg m k0 k1) (List.combine kl0 kl1)

    (** Figuring out mappings between sets of ids is hard in all generality...
        We use the fact that the fresh ids should have been generated
        the same way (i.e., in the same order) and match the ids two by
        two in increasing order.
     *)
    let match_es (msg : string) (m : Inj.t ref) (ks0 : Id.Set.t)
        (ks1 : Id.Set.t) : Id.Set.t =
      Id.Set.of_list
        (match_el msg m (Id.Set.elements ks0) (Id.Set.elements ks1))
  end

  module GetSetRid = MkGetSetM (T.RegionId)

  let match_rid = GetSetRid.match_e "match_rid: " S.rid_map
  let match_rids = GetSetRid.match_es "match_rids: " S.rid_map

  module GetSetBid = MkGetSetM (V.BorrowId)

  let match_blid msg = GetSetBid.match_e msg S.blid_map
  let match_blidl msg = GetSetBid.match_el msg S.blid_map
  let match_blids msg = GetSetBid.match_es msg S.blid_map

  let match_borrow_id =
    if S.check_equiv then match_blid "match_borrow_id: "
    else GetSetBid.match_e "match_borrow_id: " S.borrow_id_map

  let match_borrow_idl =
    if S.check_equiv then match_blidl "match_borrow_idl: "
    else GetSetBid.match_el "match_borrow_idl: " S.borrow_id_map

  let match_borrow_ids =
    if S.check_equiv then match_blids "match_borrow_ids: "
    else GetSetBid.match_es "match_borrow_ids: " S.borrow_id_map

  let match_loan_id =
    if S.check_equiv then match_blid "match_loan_id: "
    else GetSetBid.match_e "match_loan_id: " S.loan_id_map

  let match_loan_idl =
    if S.check_equiv then match_blidl "match_loan_idl: "
    else GetSetBid.match_el "match_loan_idl: " S.loan_id_map

  let match_loan_ids =
    if S.check_equiv then match_blids "match_loan_ids: "
    else GetSetBid.match_es "match_loan_ids: " S.loan_id_map

  module GetSetSid = MkGetSetM (V.SymbolicValueId)
  module GetSetAid = MkGetSetM (V.AbstractionId)

  let match_aid = GetSetAid.match_e "match_aid: " S.aid_map
  let match_aidl = GetSetAid.match_el "match_aidl: " S.aid_map
  let match_aids = GetSetAid.match_es "match_aids: " S.aid_map

  (** *)
  let match_etys ty0 ty1 =
    if ty0 <> ty1 then raise (Distinct "match_etys") else ty0

  let match_rtys ty0 ty1 =
    let match_distinct_types _ _ = raise (Distinct "match_rtys") in
    let match_regions r0 r1 =
      match (r0, r1) with
      | T.Static, T.Static -> r1
      | Var rid0, Var rid1 ->
          let rid = match_rid rid0 rid1 in
          Var rid
      | _ -> raise (Distinct "match_rtys")
    in
    match_types match_distinct_types match_regions ty0 ty1

  let match_distinct_literals (ty : T.ety) (_ : V.literal) (_ : V.literal) :
      V.typed_value =
    mk_fresh_symbolic_typed_value_from_ety V.LoopJoin ty

  let match_distinct_adts (_ty : T.ety) (_adt0 : V.adt_value)
      (_adt1 : V.adt_value) : V.typed_value =
    raise (Distinct "match_distinct_adts")

  let match_shared_borrows
      (match_typed_values : V.typed_value -> V.typed_value -> V.typed_value)
      (_ty : T.ety) (bid0 : V.borrow_id) (bid1 : V.borrow_id) : V.borrow_id =
    log#ldebug
      (lazy
        ("MakeCheckEquivMatcher: match_shared_borrows: " ^ "bid0: "
       ^ V.BorrowId.to_string bid0 ^ ", bid1: " ^ V.BorrowId.to_string bid1));

    let bid = match_borrow_id bid0 bid1 in
    (* If we don't check for equivalence (i.e., we apply a fixed-point),
       we lookup the shared values and match them.
    *)
    let _ =
      if S.check_equiv then ()
      else
        let v0 = S.lookup_shared_value_in_ctx0 bid0 in
        let v1 = S.lookup_shared_value_in_ctx1 bid1 in
        log#ldebug
          (lazy
            ("MakeCheckEquivMatcher: match_shared_borrows: looked up values:"
           ^ "sv0: "
            ^ typed_value_to_string S.ctx v0
            ^ ", sv1: "
            ^ typed_value_to_string S.ctx v1));

        let _ = match_typed_values v0 v1 in
        ()
    in
    bid

  let match_mut_borrows (_ty : T.ety) (bid0 : V.borrow_id)
      (_bv0 : V.typed_value) (bid1 : V.borrow_id) (_bv1 : V.typed_value)
      (bv : V.typed_value) : V.borrow_id * V.typed_value =
    let bid = match_borrow_id bid0 bid1 in
    (bid, bv)

  let match_shared_loans (_ : T.ety) (ids0 : V.loan_id_set)
      (ids1 : V.loan_id_set) (sv : V.typed_value) :
      V.loan_id_set * V.typed_value =
    let ids = match_loan_ids ids0 ids1 in
    (ids, sv)

  let match_mut_loans (_ : T.ety) (bid0 : V.loan_id) (bid1 : V.loan_id) :
      V.loan_id =
    match_loan_id bid0 bid1

  let match_symbolic_values (sv0 : V.symbolic_value) (sv1 : V.symbolic_value) :
      V.symbolic_value =
    let id0 = sv0.sv_id in
    let id1 = sv1.sv_id in

    log#ldebug
      (lazy
        ("MakeCheckEquivMatcher: match_symbolic_values: " ^ "sv0: "
        ^ V.SymbolicValueId.to_string id0
        ^ ", sv1: "
        ^ V.SymbolicValueId.to_string id1));

    (* If we don't check for equivalence, we also update the map from sids
       to values *)
    if S.check_equiv then
      (* Create the joined symbolic value *)
      let sv_id =
        GetSetSid.match_e "match_symbolic_values: ids: " S.sid_map id0 id1
      in
      let sv_ty = match_rtys sv0.V.sv_ty sv1.V.sv_ty in
      let sv_kind =
        if sv0.V.sv_kind = sv1.V.sv_kind then sv0.V.sv_kind
        else raise (Distinct "match_symbolic_values: sv_kind")
      in
      let sv = { V.sv_id; sv_ty; sv_kind } in
      sv
    else (
      (* Check: fixed values are fixed *)
      assert (id0 = id1 || not (V.SymbolicValueId.InjSubst.mem id0 !S.sid_map));

      (* Update the symbolic value mapping *)
      let sv1 = mk_typed_value_from_symbolic_value sv1 in

      (* Update the symbolic value mapping *)
      S.sid_to_value_map :=
        V.SymbolicValueId.Map.add_strict id0 sv1 !S.sid_to_value_map;

      (* Return - the returned value is not used: we can return  whatever
         we want *)
      sv0)

  let match_symbolic_with_other (left : bool) (sv : V.symbolic_value)
      (v : V.typed_value) : V.typed_value =
    if S.check_equiv then raise (Distinct "match_symbolic_with_other")
    else (
      assert left;
      let id = sv.sv_id in
      (* Check: fixed values are fixed *)
      assert (not (V.SymbolicValueId.InjSubst.mem id !S.sid_map));
      (* Update the binding for the target symbolic value *)
      S.sid_to_value_map :=
        V.SymbolicValueId.Map.add_strict id v !S.sid_to_value_map;
      (* Return - the returned value is not used, so we can return whatever we want *)
      v)

  let match_bottom_with_other (left : bool) (v : V.typed_value) : V.typed_value
      =
    (* It can happen that some variables get initialized in some branches
       and not in some others, which causes problems when matching. *)
    (* TODO: the returned value is not used, while it should: in generality it
       should be ok to match a fixed-point with the environment we get at
       a continue, where the fixed point contains some bottom values. *)
    if left && not (value_has_loans_or_borrows S.ctx v.V.value) then
      mk_bottom v.V.ty
    else raise (Distinct "match_bottom_with_other")

  let match_distinct_aadts _ _ _ _ _ = raise (Distinct "match_distinct_adts")

  let match_ashared_borrows _ty0 bid0 _ty1 bid1 ty =
    let bid = match_borrow_id bid0 bid1 in
    let value = V.ABorrow (V.ASharedBorrow bid) in
    { V.value; ty }

  let match_amut_borrows _ty0 bid0 _av0 _ty1 bid1 _av1 ty av =
    let bid = match_borrow_id bid0 bid1 in
    let value = V.ABorrow (V.AMutBorrow (bid, av)) in
    { V.value; ty }

  let match_ashared_loans _ty0 ids0 _v0 _av0 _ty1 ids1 _v1 _av1 ty v av =
    let bids = match_loan_ids ids0 ids1 in
    let value = V.ALoan (V.ASharedLoan (bids, v, av)) in
    { V.value; ty }

  let match_amut_loans _ty0 id0 _av0 _ty1 id1 _av1 ty av =
    log#ldebug
      (lazy
        ("MakeCheckEquivMatcher:match_amut_loans:" ^ "\n- id0: "
       ^ V.BorrowId.to_string id0 ^ "\n- id1: " ^ V.BorrowId.to_string id1
       ^ "\n- ty: " ^ rty_to_string S.ctx ty ^ "\n- av: "
        ^ typed_avalue_to_string S.ctx av));

    let id = match_loan_id id0 id1 in
    let value = V.ALoan (V.AMutLoan (id, av)) in
    { V.value; ty }

  let match_avalues v0 v1 =
    log#ldebug
      (lazy
        ("avalues don't match:\n- v0: "
        ^ typed_avalue_to_string S.ctx v0
        ^ "\n- v1: "
        ^ typed_avalue_to_string S.ctx v1));
    raise (Distinct "match_avalues")
end

let match_ctxs (check_equiv : bool) (fixed_ids : ids_sets)
    (lookup_shared_value_in_ctx0 : V.BorrowId.id -> V.typed_value)
    (lookup_shared_value_in_ctx1 : V.BorrowId.id -> V.typed_value)
    (ctx0 : C.eval_ctx) (ctx1 : C.eval_ctx) : ids_maps option =
  log#ldebug
    (lazy
      ("match_ctxs:\n\n- fixed_ids:\n" ^ show_ids_sets fixed_ids
     ^ "\n\n- ctx0:\n"
      ^ eval_ctx_to_string_no_filter ctx0
      ^ "\n\n- ctx1:\n"
      ^ eval_ctx_to_string_no_filter ctx1
      ^ "\n\n"));

  (* Initialize the maps and instantiate the matcher *)
  let module IdMap (Id : Identifiers.Id) = struct
    let mk_map_ref (ids : Id.Set.t) : Id.InjSubst.t ref =
      ref
        (Id.InjSubst.of_list (List.map (fun x -> (x, x)) (Id.Set.elements ids)))
  end in
  let rid_map =
    let module IdMap = IdMap (T.RegionId) in
    IdMap.mk_map_ref fixed_ids.rids
  in
  let blid_map =
    let module IdMap = IdMap (V.BorrowId) in
    IdMap.mk_map_ref fixed_ids.blids
  in
  let borrow_id_map =
    let module IdMap = IdMap (V.BorrowId) in
    IdMap.mk_map_ref fixed_ids.borrow_ids
  in
  let loan_id_map =
    let module IdMap = IdMap (V.BorrowId) in
    IdMap.mk_map_ref fixed_ids.loan_ids
  in
  let aid_map =
    let module IdMap = IdMap (V.AbstractionId) in
    IdMap.mk_map_ref fixed_ids.aids
  in
  let sid_map =
    let module IdMap = IdMap (V.SymbolicValueId) in
    IdMap.mk_map_ref fixed_ids.sids
  in
  (* In case we don't try to check equivalence but want to compute a mapping
     from a source context to a target context, we use a map from symbolic
     value ids to values (rather than to ids).
  *)
  let sid_to_value_map : V.typed_value V.SymbolicValueId.Map.t ref =
    ref V.SymbolicValueId.Map.empty
  in

  let module S : MatchCheckEquivState = struct
    let check_equiv = check_equiv
    let ctx = ctx0
    let rid_map = rid_map
    let blid_map = blid_map
    let borrow_id_map = borrow_id_map
    let loan_id_map = loan_id_map
    let sid_map = sid_map
    let sid_to_value_map = sid_to_value_map
    let aid_map = aid_map
    let lookup_shared_value_in_ctx0 = lookup_shared_value_in_ctx0
    let lookup_shared_value_in_ctx1 = lookup_shared_value_in_ctx1
  end in
  let module CEM = MakeCheckEquivMatcher (S) in
  let module M = MakeMatcher (CEM) in
  (* Match the environments - we assume that they have the same structure
     (and fail if they don't) *)

  (* Small utility: check that ids are fixed/mapped to themselves *)
  let ids_are_fixed (ids : ids_sets) : bool =
    let { aids; blids = _; borrow_ids; loan_ids; dids; rids; sids } = ids in
    V.AbstractionId.Set.subset aids fixed_ids.aids
    && V.BorrowId.Set.subset borrow_ids fixed_ids.borrow_ids
    && V.BorrowId.Set.subset loan_ids fixed_ids.loan_ids
    && C.DummyVarId.Set.subset dids fixed_ids.dids
    && T.RegionId.Set.subset rids fixed_ids.rids
    && V.SymbolicValueId.Set.subset sids fixed_ids.sids
  in

  (* We need to pick a context for some functions like [match_typed_values]:
     the context is only used to lookup module data, so we can pick whichever
     we want.
     TODO: this is not very clean. Maybe we should just carry the relevant data
     (i.e.e, not the whole context) around.
  *)
  let ctx = ctx0 in

  (* Rem.: this function raises exceptions of type [Distinct] *)
  let match_abstractions (abs0 : V.abs) (abs1 : V.abs) : unit =
    let {
      V.abs_id = abs_id0;
      kind = kind0;
      can_end = can_end0;
      parents = parents0;
      original_parents = original_parents0;
      regions = regions0;
      ancestors_regions = ancestors_regions0;
      avalues = avalues0;
    } =
      abs0
    in

    let {
      V.abs_id = abs_id1;
      kind = kind1;
      can_end = can_end1;
      parents = parents1;
      original_parents = original_parents1;
      regions = regions1;
      ancestors_regions = ancestors_regions1;
      avalues = avalues1;
    } =
      abs1
    in

    let _ = CEM.match_aid abs_id0 abs_id1 in
    if kind0 <> kind1 || can_end0 <> can_end1 then
      raise (Distinct "match_abstractions: kind or can_end");
    let _ = CEM.match_aids parents0 parents1 in
    let _ = CEM.match_aidl original_parents0 original_parents1 in
    let _ = CEM.match_rids regions0 regions1 in
    let _ = CEM.match_rids ancestors_regions0 ancestors_regions1 in

    log#ldebug (lazy "match_abstractions: matching values");
    let _ =
      List.map
        (fun (v0, v1) -> M.match_typed_avalues ctx v0 v1)
        (List.combine avalues0 avalues1)
    in
    log#ldebug (lazy "match_abstractions: values matched OK");
    ()
  in

  (* Rem.: this function raises exceptions of type [Distinct] *)
  let rec match_envs (env0 : C.env) (env1 : C.env) : unit =
    log#ldebug
      (lazy
        ("match_ctxs: match_envs:\n\n- fixed_ids:\n" ^ show_ids_sets fixed_ids
       ^ "\n\n- rid_map: "
        ^ T.RegionId.InjSubst.show_t !rid_map
        ^ "\n- blid_map: "
        ^ V.BorrowId.InjSubst.show_t !blid_map
        ^ "\n- sid_map: "
        ^ V.SymbolicValueId.InjSubst.show_t !sid_map
        ^ "\n- aid_map: "
        ^ V.AbstractionId.InjSubst.show_t !aid_map
        ^ "\n\n- ctx0:\n"
        ^ eval_ctx_to_string_no_filter { ctx0 with env = List.rev env0 }
        ^ "\n\n- ctx1:\n"
        ^ eval_ctx_to_string_no_filter { ctx1 with env = List.rev env1 }
        ^ "\n\n"));

    match (env0, env1) with
    | ( C.Var (C.DummyBinder b0, v0) :: env0',
        C.Var (C.DummyBinder b1, v1) :: env1' ) ->
        (* Sanity check: if the dummy value is an old value, the bindings must
           be the same and their values equal (and the borrows/loans/symbolic *)
        if C.DummyVarId.Set.mem b0 fixed_ids.dids then (
          (* Fixed values: the values must be equal *)
          assert (b0 = b1);
          assert (v0 = v1);
          (* The ids present in the left value must be fixed *)
          let ids, _ = compute_typed_value_ids v0 in
          assert ((not S.check_equiv) || ids_are_fixed ids));
        (* We still match the values - allows to compute mappings (which
           are the identity actually) *)
        let _ = M.match_typed_values ctx v0 v1 in
        match_envs env0' env1'
    | C.Var (C.VarBinder b0, v0) :: env0', C.Var (C.VarBinder b1, v1) :: env1'
      ->
        assert (b0 = b1);
        (* Match the values *)
        let _ = M.match_typed_values ctx v0 v1 in
        (* Continue *)
        match_envs env0' env1'
    | C.Abs abs0 :: env0', C.Abs abs1 :: env1' ->
        log#ldebug (lazy "match_ctxs: match_envs: matching abs");
        (* Same as for the dummy values: there are two cases *)
        if V.AbstractionId.Set.mem abs0.abs_id fixed_ids.aids then (
          log#ldebug (lazy "match_ctxs: match_envs: matching abs: fixed abs");
          (* Still in the prefix: the abstractions must be the same *)
          assert (abs0 = abs1);
          (* Their ids must be fixed *)
          let ids, _ = compute_abs_ids abs0 in
          assert ((not S.check_equiv) || ids_are_fixed ids);
          (* Continue *)
          match_envs env0' env1')
        else (
          log#ldebug
            (lazy "match_ctxs: match_envs: matching abs: not fixed abs");
          (* Match the values *)
          match_abstractions abs0 abs1;
          (* Continue *)
          match_envs env0' env1')
    | [], [] ->
        (* Done *)
        ()
    | _ ->
        (* The elements don't match *)
        raise (Distinct "match_ctxs: match_envs: env elements don't match")
  in

  (* Match the environments.

     Rem.: we don't match the ended regions (would it make any sense actually?) *)
  try
    (* Remove the frame delimiter (the first element of an environment is a frame delimiter) *)
    let env0 = List.rev ctx0.env in
    let env1 = List.rev ctx1.env in
    let env0, env1 =
      match (env0, env1) with
      | C.Frame :: env0, C.Frame :: env1 -> (env0, env1)
      | _ -> raise (Failure "Unreachable")
    in

    match_envs env0 env1;
    let maps =
      {
        aid_map = !aid_map;
        blid_map = !blid_map;
        borrow_id_map = !borrow_id_map;
        loan_id_map = !loan_id_map;
        rid_map = !rid_map;
        sid_map = !sid_map;
        sid_to_value_map = !sid_to_value_map;
      }
    in
    Some maps
  with Distinct msg ->
    log#ldebug (lazy ("match_ctxs: distinct: " ^ msg));
    None

let ctxs_are_equivalent (fixed_ids : ids_sets) (ctx0 : C.eval_ctx)
    (ctx1 : C.eval_ctx) : bool =
  let check_equivalent = true in
  let lookup_shared_value _ = raise (Failure "Unreachable") in
  Option.is_some
    (match_ctxs check_equivalent fixed_ids lookup_shared_value
       lookup_shared_value ctx0 ctx1)

let match_ctx_with_target (config : C.config) (loop_id : V.LoopId.id)
    (is_loop_entry : bool) (fp_bl_maps : borrow_loan_corresp)
    (fp_input_svalues : V.SymbolicValueId.id list) (fixed_ids : ids_sets)
    (src_ctx : C.eval_ctx) : st_cm_fun =
 fun cf tgt_ctx ->
  (* Debug *)
  log#ldebug
    (lazy
      ("match_ctx_with_target:\n" ^ "\n- fixed_ids: " ^ show_ids_sets fixed_ids
     ^ "\n" ^ "\n- src_ctx: " ^ eval_ctx_to_string src_ctx ^ "\n- tgt_ctx: "
     ^ eval_ctx_to_string tgt_ctx));

  (* We first reorganize [tgt_ctx] so that we can match [src_ctx] with it (by
     ending loans for instance - remember that the [src_ctx] is the fixed point
     context, which results from joins during which we ended the loans which
     were introduced during the loop iterations)
  *)
  (* End the loans which lead to mismatches when joining *)
  let rec cf_reorganize_join_tgt : cm_fun =
   fun cf tgt_ctx ->
    (* Collect fixed values in the source and target contexts: end the loans in the
       source context which don't appear in the target context *)
    let filt_src_env, _, _ = ctx_split_fixed_new fixed_ids src_ctx in
    let filt_tgt_env, _, _ = ctx_split_fixed_new fixed_ids tgt_ctx in

    log#ldebug
      (lazy
        ("match_ctx_with_target:\n" ^ "\n- fixed_ids: "
       ^ show_ids_sets fixed_ids ^ "\n" ^ "\n- filt_src_ctx: "
        ^ env_to_string src_ctx filt_src_env
        ^ "\n- filt_tgt_ctx: "
        ^ env_to_string tgt_ctx filt_tgt_env));

    (* Remove the abstractions *)
    let filter (ee : C.env_elem) : bool =
      match ee with Var _ -> true | Abs _ | Frame -> false
    in
    let filt_src_env = List.filter filter filt_src_env in
    let filt_tgt_env = List.filter filter filt_tgt_env in

    (* Match the values to check if there are loans to eliminate *)

    (* We need to pick a context for some functions like [match_typed_values]:
       the context is only used to lookup module data, so we can pick whichever
       we want.
       TODO: this is not very clean. Maybe we should just carry this data around.
    *)
    let ctx = tgt_ctx in

    let nabs = ref [] in

    let module S : MatchJoinState = struct
      (* The context is only used to lookup module data: we can pick whichever we want *)
      let ctx = ctx
      let loop_id = loop_id
      let nabs = nabs
    end in
    let module JM = MakeJoinMatcher (S) in
    let module M = MakeMatcher (JM) in
    try
      let _ =
        List.iter
          (fun (var0, var1) ->
            match (var0, var1) with
            | C.Var (C.DummyBinder b0, v0), C.Var (C.DummyBinder b1, v1) ->
                assert (b0 = b1);
                let _ = M.match_typed_values ctx v0 v1 in
                ()
            | C.Var (C.VarBinder b0, v0), C.Var (C.VarBinder b1, v1) ->
                assert (b0 = b1);
                let _ = M.match_typed_values ctx v0 v1 in
                ()
            | _ -> raise (Failure "Unexpected"))
          (List.combine filt_src_env filt_tgt_env)
      in
      (* No exception was thrown: continue *)
      cf tgt_ctx
    with ValueMatchFailure e ->
      (* Exception: end the corresponding borrows, and continue *)
      let cc =
        match e with
        | LoanInRight bid -> InterpreterBorrows.end_borrow config bid
        | LoansInRight bids -> InterpreterBorrows.end_borrows config bids
        | AbsInRight _ | AbsInLeft _ | LoanInLeft _ | LoansInLeft _ ->
            raise (Failure "Unexpected")
      in
      comp cc cf_reorganize_join_tgt cf tgt_ctx
  in

  (* Introduce the "identity" abstractions for the loop reentry.

     Match the target context with the source context so as to compute how to
     map the borrows from the target context (i.e., the fixed point context)
     to the borrows in the source context.

     Substitute the *loans* in the abstractions introduced by the target context
     (the abstractions of the fixed point) to properly link those abstraction:
     we introduce *identity* abstractions (the loans are equal to the borrows):
     we substitute the loans and introduce fresh ids for the borrows, symbolic
     values, etc. About the *identity abstractions*, see the comments for
     [compute_fixed_point_id_correspondance].

     TODO: this whole thing is very technical and error-prone.
     We should rely on a more primitive and safer function
     [add_identity_abs] to add the identity abstractions one by one.
  *)
  let cf_introduce_loop_fp_abs : m_fun =
   fun tgt_ctx ->
    (* Match the source and target contexts *)
    let filt_tgt_env, _, _ = ctx_split_fixed_new fixed_ids tgt_ctx in
    let filt_src_env, new_absl, new_dummyl =
      ctx_split_fixed_new fixed_ids src_ctx
    in
    assert (new_dummyl = []);
    let filt_tgt_ctx = { tgt_ctx with env = filt_tgt_env } in
    let filt_src_ctx = { src_ctx with env = filt_src_env } in

    let src_to_tgt_maps =
      let check_equiv = false in
      let fixed_ids = ids_sets_empty_borrows_loans fixed_ids in
      let open InterpreterBorrowsCore in
      let lookup_shared_loan lid ctx : V.typed_value =
        match snd (lookup_loan ek_all lid ctx) with
        | Concrete (V.SharedLoan (_, v)) -> v
        | Abstract (V.ASharedLoan (_, v, _)) -> v
        | _ -> raise (Failure "Unreachable")
      in
      let lookup_in_src id = lookup_shared_loan id src_ctx in
      let lookup_in_tgt id = lookup_shared_loan id tgt_ctx in
      (* Match *)
      Option.get
        (match_ctxs check_equiv fixed_ids lookup_in_src lookup_in_tgt
           filt_src_ctx filt_tgt_ctx)
    in
    let tgt_to_src_borrow_map =
      V.BorrowId.Map.of_list
        (List.map
           (fun (x, y) -> (y, x))
           (V.BorrowId.InjSubst.bindings src_to_tgt_maps.borrow_id_map))
    in

    (* Debug *)
    log#ldebug
      (lazy
        ("match_ctx_with_target: cf_introduce_loop_fp_abs:" ^ "\n\n- tgt_ctx: "
       ^ eval_ctx_to_string tgt_ctx ^ "\n\n- src_ctx: "
       ^ eval_ctx_to_string src_ctx ^ "\n\n- filt_tgt_ctx: "
        ^ eval_ctx_to_string_no_filter filt_tgt_ctx
        ^ "\n\n- filt_src_ctx: "
        ^ eval_ctx_to_string_no_filter filt_src_ctx
        ^ "\n\n- new_absl:\n"
        ^ eval_ctx_to_string
            { src_ctx with C.env = List.map (fun abs -> C.Abs abs) new_absl }
        ^ "\n\n- fixed_ids:\n" ^ show_ids_sets fixed_ids ^ "\n\n- fp_bl_maps:\n"
        ^ show_borrow_loan_corresp fp_bl_maps
        ^ "\n\n- src_to_tgt_maps: "
        ^ show_ids_maps src_to_tgt_maps));

    (* Update the borrows and symbolic ids in the source context.

       Going back to the [list_nth_mut_example], the original environment upon
       re-entering the loop is:

       {[
         abs@0 { ML l0 }
         ls -> MB l5 (s@6 : loops::List<T>)
         i -> s@7 : u32
         _@1 -> MB l0 (loops::List::Cons (ML l1, ML l2))
         _@2 -> MB l2 (@Box (ML l4))                      // tail
         _@3 -> MB l1 (s@3 : T)                           // hd
         abs@1 { MB l4, ML l5 }
       ]}

       The fixed-point environment is:
       {[
         env_fp = {
           abs@0 { ML l0 }
           ls -> MB l1 (s3 : loops::List<T>)
           i -> s4 : u32
           abs@fp {
             MB l0 // this borrow appears in [env0]
             ML l1
           }
         }
       ]}

       Through matching, we detect that in [env_fp], [l1] is matched
       to [l5]. We introduce a fresh borrow [l6] for [l1], and remember
       in the map [src_fresh_borrows_map] that: [{ l1 -> l6}].

       We get:
       {[
         abs@0 { ML l0 }
         ls -> MB l6 (s@6 : loops::List<T>) // l6 is fresh and doesn't have a corresponding loan
         i -> s@7 : u32
         _@1 -> MB l0 (loops::List::Cons (ML l1, ML l2))
         _@2 -> MB l2 (@Box (ML l4))                      // tail
         _@3 -> MB l1 (s@3 : T)                           // hd
         abs@1 { MB l4, ML l5 }
       ]}

       Later, we will introduce the identity abstraction:
       {[
         abs@2 { MB l5, ML l6 }
       ]}
    *)
    (* First, compute the set of borrows which appear in the fresh abstractions
       of the fixed-point: we want to introduce fresh ids only for those. *)
    let new_absl_ids, _ = compute_absl_ids new_absl in
    let src_fresh_borrows_map = ref V.BorrowId.Map.empty in
    let visit_tgt =
      object
        inherit [_] C.map_eval_ctx

        method! visit_borrow_id _ id =
          (* Map the borrow, if it needs to be mapped *)
          if
            (* We map the borrows for which we computed a mapping *)
            V.BorrowId.InjSubst.Set.mem id
              (V.BorrowId.InjSubst.elements src_to_tgt_maps.borrow_id_map)
            (* And which have corresponding loans in the fresh fixed-point abstractions *)
            && V.BorrowId.Set.mem
                 (V.BorrowId.Map.find id tgt_to_src_borrow_map)
                 new_absl_ids.loan_ids
          then (
            let src_id = V.BorrowId.Map.find id tgt_to_src_borrow_map in
            let nid = C.fresh_borrow_id () in
            src_fresh_borrows_map :=
              V.BorrowId.Map.add src_id nid !src_fresh_borrows_map;
            nid)
          else id
      end
    in
    let tgt_ctx = visit_tgt#visit_eval_ctx () tgt_ctx in

    log#ldebug
      (lazy
        ("match_ctx_with_target: cf_introduce_loop_fp_abs: \
          src_fresh_borrows_map:\n"
        ^ V.BorrowId.Map.show V.BorrowId.to_string !src_fresh_borrows_map
        ^ "\n"));

    (* Rem.: we don't update the symbolic values. It is not necessary
       because there shouldn't be any symbolic value containing borrows.

       Rem.: we will need to do something about the symbolic values in the
       abstractions and in the *variable bindings* once we allow symbolic
       values containing borrows to not be eagerly expanded.
    *)
    assert Config.greedy_expand_symbolics_with_borrows;

    (* Update the borrows and loans in the abstractions of the target context.

       Going back to the [list_nth_mut] example and by using [src_fresh_borrows_map],
       we instantiate the fixed-point abstractions that we will insert into the
       context.
       The abstraction is [abs { MB l0, ML l1 }].
       Because of [src_fresh_borrows_map], we substitute [l1] with [l6].
       Because of the match between the contexts, we substitute [l0] with [l5].
       We get:
       {[
         abs@2 { MB l5, ML l6 }
       ]}
    *)
    let region_id_map = ref T.RegionId.Map.empty in
    let get_rid rid =
      match T.RegionId.Map.find_opt rid !region_id_map with
      | Some rid -> rid
      | None ->
          let nid = C.fresh_region_id () in
          region_id_map := T.RegionId.Map.add rid nid !region_id_map;
          nid
    in
    let visit_src =
      object
        inherit [_] C.map_eval_ctx as super

        method! visit_borrow_id _ bid =
          log#ldebug
            (lazy
              ("match_ctx_with_target: cf_introduce_loop_fp_abs: \
                visit_borrow_id: " ^ V.BorrowId.to_string bid ^ "\n"));

          (* Lookup the id of the loan corresponding to this borrow *)
          let src_lid =
            V.BorrowId.InjSubst.find bid fp_bl_maps.borrow_to_loan_id_map
          in

          log#ldebug
            (lazy
              ("match_ctx_with_target: cf_introduce_loop_fp_abs: looked up \
                src_lid: "
              ^ V.BorrowId.to_string src_lid
              ^ "\n"));

          (* Lookup the tgt borrow id to which this borrow was mapped *)
          let tgt_bid =
            V.BorrowId.InjSubst.find src_lid src_to_tgt_maps.borrow_id_map
          in

          log#ldebug
            (lazy
              ("match_ctx_with_target: cf_introduce_loop_fp_abs: looked up \
                tgt_bid: "
              ^ V.BorrowId.to_string tgt_bid
              ^ "\n"));

          tgt_bid

        method! visit_loan_id _ id =
          log#ldebug
            (lazy
              ("match_ctx_with_target: cf_introduce_loop_fp_abs: \
                visit_loan_id: " ^ V.BorrowId.to_string id ^ "\n"));
          (* Map the borrow - rem.: we mapped the borrows *in the values*,
             meaning we know how to map the *corresponding loans in the
             abstractions* *)
          match V.BorrowId.Map.find_opt id !src_fresh_borrows_map with
          | None ->
              (* No mapping: this means that the borrow was mapped when
                 we matched values (it doesn't come from a fresh abstraction)
                 and because of this, it should actually be mapped to itself *)
              assert (
                V.BorrowId.InjSubst.find id src_to_tgt_maps.borrow_id_map = id);
              id
          | Some id -> id

        method! visit_symbolic_value_id _ _ = C.fresh_symbolic_value_id ()
        method! visit_abstraction_id _ _ = C.fresh_abstraction_id ()
        method! visit_region_id _ id = get_rid id

        (** We also need to change the abstraction kind *)
        method! visit_abs env abs =
          match abs.kind with
          | V.Loop (loop_id', rg_id, kind) ->
              assert (loop_id' = loop_id);
              assert (kind = V.LoopSynthInput);
              let can_end = false in
              let kind = V.Loop (loop_id, rg_id, V.LoopCall) in
              let abs = { abs with kind; can_end } in
              super#visit_abs env abs
          | _ -> super#visit_abs env abs
      end
    in
    let new_absl = List.map (visit_src#visit_abs ()) new_absl in
    let new_absl = List.map (fun abs -> C.Abs abs) new_absl in

    (* Add the abstractions from the target context to the source context *)
    let nenv = List.append new_absl tgt_ctx.env in
    let tgt_ctx = { tgt_ctx with env = nenv } in

    log#ldebug
      (lazy
        ("match_ctx_with_target:cf_introduce_loop_fp_abs:\n- result ctx:\n"
       ^ eval_ctx_to_string tgt_ctx));

    (* Sanity check *)
    if !Config.check_invariants then
      Invariants.check_borrowed_values_invariant tgt_ctx;

    (* End all the borrows which appear in the *new* abstractions *)
    let new_borrows =
      V.BorrowId.Set.of_list
        (List.map snd (V.BorrowId.Map.bindings !src_fresh_borrows_map))
    in
    let cc = InterpreterBorrows.end_borrows config new_borrows in

    (* Compute the loop input values *)
    let input_values =
      V.SymbolicValueId.Map.of_list
        (List.map
           (fun sid ->
             ( sid,
               V.SymbolicValueId.Map.find sid src_to_tgt_maps.sid_to_value_map
             ))
           fp_input_svalues)
    in

    (* Continue *)
    cc
      (cf
         (if is_loop_entry then EndEnterLoop (loop_id, input_values)
          else EndContinue (loop_id, input_values)))
      tgt_ctx
  in

  (* Compose and continue *)
  cf_reorganize_join_tgt cf_introduce_loop_fp_abs tgt_ctx
