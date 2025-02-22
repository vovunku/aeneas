module T = Types
module PV = PrimitiveValues
module V = Values
module LA = LlbcAst
open Scalars
module E = Expressions
open Utils
module C = Contexts
module Subst = Substitute
module L = Logging
open TypesUtils
open ValuesUtils
module Inv = Invariants
module S = SynthesizeSymbolic
open Cps
open InterpreterUtils
open InterpreterExpansion
open InterpreterPaths

(** The local logger *)
let log = L.expressions_log

(** As long as there are symbolic values at a given place (potentially in subvalues)
    which contain borrows and are primitively copyable, expand them.
    
    We use this function before copying values.
    
    Note that the place should have been prepared so that there are no remaining
    loans.
*)
let expand_primitively_copyable_at_place (config : C.config)
    (access : access_kind) (p : E.place) : cm_fun =
 fun cf ctx ->
  (* Small helper *)
  let rec expand : cm_fun =
   fun cf ctx ->
    let v = read_place access p ctx in
    match
      find_first_primitively_copyable_sv_with_borrows
        ctx.type_context.type_infos v
    with
    | None -> cf ctx
    | Some sv ->
        let cc =
          expand_symbolic_value_no_branching config sv
            (Some (S.mk_mplace p ctx))
        in
        comp cc expand cf ctx
  in
  (* Apply *)
  expand cf ctx

(** Read a place (CPS-style function).

    We also check that the value *doesn't contain bottoms or reserved
    borrows*.
 *)
let read_place (access : access_kind) (p : E.place)
    (cf : V.typed_value -> m_fun) : m_fun =
 fun ctx ->
  let v = read_place access p ctx in
  (* Check that there are no bottoms in the value *)
  assert (not (bottom_in_value ctx.ended_regions v));
  (* Check that there are no reserved borrows in the value *)
  assert (not (reserved_in_value v));
  (* Call the continuation *)
  cf v ctx

let access_rplace_reorganize_and_read (config : C.config)
    (expand_prim_copy : bool) (access : access_kind) (p : E.place)
    (cf : V.typed_value -> m_fun) : m_fun =
 fun ctx ->
  (* Make sure we can evaluate the path *)
  let cc = update_ctx_along_read_place config access p in
  (* End the proper loans at the place itself *)
  let cc = comp cc (end_loans_at_place config access p) in
  (* Expand the copyable values which contain borrows (which are necessarily shared
   * borrows) *)
  let cc =
    if expand_prim_copy then
      comp cc (expand_primitively_copyable_at_place config access p)
    else cc
  in
  (* Read the place - note that this checks that the value doesn't contain bottoms *)
  let read_place = read_place access p in
  (* Compose *)
  comp cc read_place cf ctx

let access_rplace_reorganize (config : C.config) (expand_prim_copy : bool)
    (access : access_kind) (p : E.place) : cm_fun =
 fun cf ctx ->
  access_rplace_reorganize_and_read config expand_prim_copy access p
    (fun _v -> cf)
    ctx

(** Convert an operand constant operand value to a typed value *)
let literal_to_typed_value (ty : PV.literal_type) (cv : V.literal) :
    V.typed_value =
  (* Check the type while converting - we actually need some information
     * contained in the type *)
  log#ldebug
    (lazy
      ("literal_to_typed_value:" ^ "\n- cv: "
      ^ Print.PrimitiveValues.literal_to_string cv));
  match (ty, cv) with
  (* Scalar, boolean... *)
  | PV.Bool, Bool v -> { V.value = V.Literal (Bool v); ty = T.Literal ty }
  | Char, Char v -> { V.value = V.Literal (Char v); ty = T.Literal ty }
  | Integer int_ty, PV.Scalar v ->
      (* Check the type and the ranges *)
      assert (int_ty = v.int_ty);
      assert (check_scalar_value_in_range v);
      { V.value = V.Literal (PV.Scalar v); ty = T.Literal ty }
  (* Remaining cases (invalid) *)
  | _, _ -> raise (Failure "Improperly typed constant value")

(** Copy a value, and return the resulting value.

    Note that copying values might update the context. For instance, when
    copying shared borrows, we need to insert new shared borrows in the context.

    Also, this function is actually more general than it should be: it can be
    used to copy concrete ADT values, while ADT copy should be done through the
    Copy trait (i.e., by calling a dedicated function). This is why we added a
    parameter to control this copy ([allow_adt_copy]). Note that here by ADT we
    mean the user-defined ADTs (not tuples or assumed types).
 *)
let rec copy_value (allow_adt_copy : bool) (config : C.config)
    (ctx : C.eval_ctx) (v : V.typed_value) : C.eval_ctx * V.typed_value =
  log#ldebug
    (lazy
      ("copy_value: "
      ^ typed_value_to_string ctx v
      ^ "\n- context:\n" ^ eval_ctx_to_string ctx));
  (* Remark: at some point we rewrote this function to use iterators, but then
   * we reverted the changes: the result was less clear actually. In particular,
   * the fact that we have exhaustive matches below makes very obvious the cases
   * in which we need to fail *)
  match v.V.value with
  | V.Literal _ -> (ctx, v)
  | V.Adt av ->
      (* Sanity check *)
      (match v.V.ty with
      | T.Adt (T.Assumed (T.Box | Vec), _, _, _) ->
          raise (Failure "Can't copy an assumed value other than Option")
      | T.Adt (T.AdtId _, _, _, _) -> assert allow_adt_copy
      | T.Adt ((T.Assumed Option | T.Tuple), _, _, _) -> () (* Ok *)
      | T.Adt (T.Assumed (Slice | T.Array), [], [ ty ], []) ->
          assert (ty_is_primitively_copyable ty)
      | _ -> raise (Failure "Unreachable"));
      let ctx, fields =
        List.fold_left_map
          (copy_value allow_adt_copy config)
          ctx av.field_values
      in
      (ctx, { v with V.value = V.Adt { av with field_values = fields } })
  | V.Bottom -> raise (Failure "Can't copy ⊥")
  | V.Borrow bc -> (
      (* We can only copy shared borrows *)
      match bc with
      | SharedBorrow bid ->
          (* We need to create a new borrow id for the copied borrow, and
           * update the context accordingly *)
          let bid' = C.fresh_borrow_id () in
          let ctx = InterpreterBorrows.reborrow_shared bid bid' ctx in
          (ctx, { v with V.value = V.Borrow (SharedBorrow bid') })
      | MutBorrow (_, _) -> raise (Failure "Can't copy a mutable borrow")
      | V.ReservedMutBorrow _ ->
          raise (Failure "Can't copy a reserved mut borrow"))
  | V.Loan lc -> (
      (* We can only copy shared loans *)
      match lc with
      | V.MutLoan _ -> raise (Failure "Can't copy a mutable loan")
      | V.SharedLoan (_, sv) ->
          (* We don't copy the shared loan: only the shared value inside *)
          copy_value allow_adt_copy config ctx sv)
  | V.Symbolic sp ->
      (* We can copy only if the type is "primitively" copyable.
       * Note that in the general case, copy is a trait: copying values
       * thus requires calling the proper function. Here, we copy values
       * for very simple types such as integers, shared borrows, etc. *)
      assert (ty_is_primitively_copyable (Subst.erase_regions sp.V.sv_ty));
      (* If the type is copyable, we simply return the current value. Side
       * remark: what is important to look at when copying symbolic values
       * is symbolic expansion. The important subcase is the expansion of shared
       * borrows: when doing so, every occurrence of the same symbolic value
       * must use a fresh borrow id. *)
      (ctx, v)

(** Reorganize the environment in preparation for the evaluation of an operand.

    Evaluating an operand requires reorganizing the environment to get access
    to a given place (by ending borrows, expanding symbolic values...) then
    applying the operand operation (move, copy, etc.).
    
    Sometimes, we want to decouple the two operations.
    Consider the following example:
    {[
      context = {
        x -> shared_borrow l0
        y -> shared_loan {l0} v
      }

      dest <- f(move x, move y);
      ...
    ]}
    Because of the way {!end_borrow} is implemented, when giving back the borrow
    [l0] upon evaluating [move y], we won't notice that [shared_borrow l0] has
    disappeared from the environment (it has been moved and not assigned yet,
    and so is hanging in "thin air").
    
    By first "preparing" the operands evaluation, we make sure no such thing
    happens. To be more precise, we make sure all the updates to borrows triggered
    by access *and* move operations have already been applied.

    Rk.: in the formalization, we always have an explicit "reorganization" step
    in the rule premises, before the actual operand evaluation, that allows to
    reorganize the environment so that it satisfies the proper conditions. This
    function's role is to do the reorganization.
    
    Rk.: doing this is actually not completely necessary because when
    generating MIR, rustc introduces intermediate assignments for all the function
    parameters. Still, it is better for soundness purposes, and corresponds to
    what we do in the formalization (because we don't enforce the same constraints
    as MIR in the formalization).
 *)
let prepare_eval_operand_reorganize (config : C.config) (op : E.operand) :
    cm_fun =
 fun cf ctx ->
  let prepare : cm_fun =
   fun cf ctx ->
    match op with
    | Expressions.Constant (ty, cv) ->
        (* No need to reorganize the context *)
        literal_to_typed_value (TypesUtils.ty_as_literal ty) cv |> ignore;
        cf ctx
    | Expressions.Copy p ->
        (* Access the value *)
        let access = Read in
        (* Expand the symbolic values, if necessary *)
        let expand_prim_copy = true in
        access_rplace_reorganize config expand_prim_copy access p cf ctx
    | Expressions.Move p ->
        (* Access the value *)
        let access = Move in
        let expand_prim_copy = false in
        access_rplace_reorganize config expand_prim_copy access p cf ctx
  in
  (* Apply *)
  prepare cf ctx

(** Evaluate an operand, without reorganizing the context before *)
let eval_operand_no_reorganize (config : C.config) (op : E.operand)
    (cf : V.typed_value -> m_fun) : m_fun =
 fun ctx ->
  (* Debug *)
  log#ldebug
    (lazy
      ("eval_operand_no_reorganize: op: " ^ operand_to_string ctx op
     ^ "\n- ctx:\n" ^ eval_ctx_to_string ctx ^ "\n"));
  (* Evaluate *)
  match op with
  | Expressions.Constant (ty, cv) ->
      cf (literal_to_typed_value (TypesUtils.ty_as_literal ty) cv) ctx
  | Expressions.Copy p ->
      (* Access the value *)
      let access = Read in
      let cc = read_place access p in
      (* Copy the value *)
      let copy cf v : m_fun =
       fun ctx ->
        (* Sanity checks *)
        assert (not (bottom_in_value ctx.ended_regions v));
        assert (
          Option.is_none
            (find_first_primitively_copyable_sv_with_borrows
               ctx.type_context.type_infos v));
        (* Actually perform the copy *)
        let allow_adt_copy = false in
        let ctx, v = copy_value allow_adt_copy config ctx v in
        (* Continue *)
        cf v ctx
      in
      (* Compose and apply *)
      comp cc copy cf ctx
  | Expressions.Move p ->
      (* Access the value *)
      let access = Move in
      let cc = read_place access p in
      (* Move the value *)
      let move cf v : m_fun =
       fun ctx ->
        (* Check that there are no bottoms in the value we are about to move *)
        assert (not (bottom_in_value ctx.ended_regions v));
        let bottom : V.typed_value = { V.value = Bottom; ty = v.ty } in
        let ctx = write_place access p bottom ctx in
        cf v ctx
      in
      (* Compose and apply *)
      comp cc move cf ctx

let eval_operand (config : C.config) (op : E.operand)
    (cf : V.typed_value -> m_fun) : m_fun =
 fun ctx ->
  (* Debug *)
  log#ldebug
    (lazy
      ("eval_operand: op: " ^ operand_to_string ctx op ^ "\n- ctx:\n"
     ^ eval_ctx_to_string ctx ^ "\n"));
  (* We reorganize the context, then evaluate the operand *)
  comp
    (prepare_eval_operand_reorganize config op)
    (eval_operand_no_reorganize config op)
    cf ctx

(** Small utility.

    See [prepare_eval_operand_reorganize].
 *)
let prepare_eval_operands_reorganize (config : C.config) (ops : E.operand list)
    : cm_fun =
  fold_left_apply_continuation (prepare_eval_operand_reorganize config) ops

(** Evaluate several operands. *)
let eval_operands (config : C.config) (ops : E.operand list)
    (cf : V.typed_value list -> m_fun) : m_fun =
 fun ctx ->
  (* Prepare the operands *)
  let prepare = prepare_eval_operands_reorganize config ops in
  (* Evaluate the operands *)
  let eval =
    fold_left_list_apply_continuation (eval_operand_no_reorganize config) ops
  in
  (* Compose and apply *)
  comp prepare eval cf ctx

let eval_two_operands (config : C.config) (op1 : E.operand) (op2 : E.operand)
    (cf : V.typed_value * V.typed_value -> m_fun) : m_fun =
  let eval_op = eval_operands config [ op1; op2 ] in
  let use_res cf res =
    match res with
    | [ v1; v2 ] -> cf (v1, v2)
    | _ -> raise (Failure "Unreachable")
  in
  comp eval_op use_res cf

let eval_unary_op_concrete (config : C.config) (unop : E.unop) (op : E.operand)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
  (* Evaluate the operand *)
  let eval_op = eval_operand config op in
  (* Apply the unop *)
  let apply cf (v : V.typed_value) : m_fun =
    match (unop, v.V.value) with
    | E.Not, V.Literal (Bool b) ->
        cf (Ok { v with V.value = V.Literal (Bool (not b)) })
    | E.Neg, V.Literal (PV.Scalar sv) -> (
        let i = Z.neg sv.PV.value in
        match mk_scalar sv.int_ty i with
        | Error _ -> cf (Error EPanic)
        | Ok sv -> cf (Ok { v with V.value = V.Literal (PV.Scalar sv) }))
    | E.Cast (src_ty, tgt_ty), V.Literal (PV.Scalar sv) -> (
        assert (src_ty = sv.int_ty);
        let i = sv.PV.value in
        match mk_scalar tgt_ty i with
        | Error _ -> cf (Error EPanic)
        | Ok sv ->
            let ty = T.Literal (Integer tgt_ty) in
            let value = V.Literal (PV.Scalar sv) in
            cf (Ok { V.ty; value }))
    | _ -> raise (Failure "Invalid input for unop")
  in
  comp eval_op apply cf

let eval_unary_op_symbolic (config : C.config) (unop : E.unop) (op : E.operand)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
 fun ctx ->
  (* Evaluate the operand *)
  let eval_op = eval_operand config op in
  (* Generate a fresh symbolic value to store the result *)
  let apply cf (v : V.typed_value) : m_fun =
   fun ctx ->
    let res_sv_id = C.fresh_symbolic_value_id () in
    let res_sv_ty =
      match (unop, v.V.ty) with
      | E.Not, (T.Literal Bool as lty) -> lty
      | E.Neg, (T.Literal (Integer _) as lty) -> lty
      | E.Cast (_, tgt_ty), _ -> T.Literal (Integer tgt_ty)
      | _ -> raise (Failure "Invalid input for unop")
    in
    let res_sv =
      { V.sv_kind = V.FunCallRet; V.sv_id = res_sv_id; sv_ty = res_sv_ty }
    in
    (* Call the continuation *)
    let expr = cf (Ok (mk_typed_value_from_symbolic_value res_sv)) ctx in
    (* Synthesize the symbolic AST *)
    S.synthesize_unary_op ctx unop v
      (S.mk_opt_place_from_op op ctx)
      res_sv None expr
  in
  (* Compose and apply *)
  comp eval_op apply cf ctx

let eval_unary_op (config : C.config) (unop : E.unop) (op : E.operand)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
  match config.mode with
  | C.ConcreteMode -> eval_unary_op_concrete config unop op cf
  | C.SymbolicMode -> eval_unary_op_symbolic config unop op cf

(** Small helper for [eval_binary_op_concrete]: computes the result of applying
    the binop *after* the operands have been successfully evaluated
 *)
let eval_binary_op_concrete_compute (binop : E.binop) (v1 : V.typed_value)
    (v2 : V.typed_value) : (V.typed_value, eval_error) result =
  (* Equality check binops (Eq, Ne) accept values from a wide variety of types.
   * The remaining binops only operate on scalars. *)
  if binop = Eq || binop = Ne then (
    (* Equality operations *)
    assert (v1.ty = v2.ty);
    (* Equality/inequality check is primitive only for a subset of types *)
    assert (ty_is_primitively_copyable v1.ty);
    let b = v1 = v2 in
    Ok { V.value = V.Literal (Bool b); ty = T.Literal Bool })
  else
    (* For the non-equality operations, the input values are necessarily scalars *)
    match (v1.V.value, v2.V.value) with
    | V.Literal (PV.Scalar sv1), V.Literal (PV.Scalar sv2) -> (
        (* There are binops which require the two operands to have the same
           type, and binops for which it is not the case.
           There are also binops which return booleans, and binops which
           return integers.
        *)
        match binop with
        | E.Lt | E.Le | E.Ge | E.Gt ->
            (* The two operands must have the same type and the result is a boolean *)
            assert (sv1.int_ty = sv2.int_ty);
            let b =
              match binop with
              | E.Lt -> Z.lt sv1.PV.value sv2.PV.value
              | E.Le -> Z.leq sv1.PV.value sv2.PV.value
              | E.Ge -> Z.geq sv1.PV.value sv2.PV.value
              | E.Gt -> Z.gt sv1.PV.value sv2.PV.value
              | E.Div | E.Rem | E.Add | E.Sub | E.Mul | E.BitXor | E.BitAnd
              | E.BitOr | E.Shl | E.Shr | E.Ne | E.Eq ->
                  raise (Failure "Unreachable")
            in
            Ok
              ({ V.value = V.Literal (Bool b); ty = T.Literal Bool }
                : V.typed_value)
        | E.Div | E.Rem | E.Add | E.Sub | E.Mul | E.BitXor | E.BitAnd | E.BitOr
          -> (
            (* The two operands must have the same type and the result is an integer *)
            assert (sv1.int_ty = sv2.int_ty);
            let res =
              match binop with
              | E.Div ->
                  if sv2.PV.value = Z.zero then Error ()
                  else mk_scalar sv1.int_ty (Z.div sv1.PV.value sv2.PV.value)
              | E.Rem ->
                  (* See [https://github.com/ocaml/Zarith/blob/master/z.mli] *)
                  if sv2.PV.value = Z.zero then Error ()
                  else mk_scalar sv1.int_ty (Z.rem sv1.PV.value sv2.PV.value)
              | E.Add -> mk_scalar sv1.int_ty (Z.add sv1.PV.value sv2.PV.value)
              | E.Sub -> mk_scalar sv1.int_ty (Z.sub sv1.PV.value sv2.PV.value)
              | E.Mul -> mk_scalar sv1.int_ty (Z.mul sv1.PV.value sv2.PV.value)
              | E.BitXor -> raise Unimplemented
              | E.BitAnd -> raise Unimplemented
              | E.BitOr -> raise Unimplemented
              | E.Lt | E.Le | E.Ge | E.Gt | E.Shl | E.Shr | E.Ne | E.Eq ->
                  raise (Failure "Unreachable")
            in
            match res with
            | Error _ -> Error EPanic
            | Ok sv ->
                Ok
                  {
                    V.value = V.Literal (PV.Scalar sv);
                    ty = T.Literal (Integer sv1.int_ty);
                  })
        | E.Shl | E.Shr -> raise Unimplemented
        | E.Ne | E.Eq -> raise (Failure "Unreachable"))
    | _ -> raise (Failure "Invalid inputs for binop")

let eval_binary_op_concrete (config : C.config) (binop : E.binop)
    (op1 : E.operand) (op2 : E.operand)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
  (* Evaluate the operands *)
  let eval_ops = eval_two_operands config op1 op2 in
  (* Compute the result of the binop *)
  let compute cf (res : V.typed_value * V.typed_value) =
    let v1, v2 = res in
    cf (eval_binary_op_concrete_compute binop v1 v2)
  in
  (* Compose and apply *)
  comp eval_ops compute cf

let eval_binary_op_symbolic (config : C.config) (binop : E.binop)
    (op1 : E.operand) (op2 : E.operand)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
 fun ctx ->
  (* Evaluate the operands *)
  let eval_ops = eval_two_operands config op1 op2 in
  (* Compute the result of applying the binop *)
  let compute cf ((v1, v2) : V.typed_value * V.typed_value) : m_fun =
   fun ctx ->
    (* Generate a fresh symbolic value to store the result *)
    let res_sv_id = C.fresh_symbolic_value_id () in
    let res_sv_ty =
      if binop = Eq || binop = Ne then (
        (* Equality operations *)
        assert (v1.ty = v2.ty);
        (* Equality/inequality check is primitive only for a subset of types *)
        assert (ty_is_primitively_copyable v1.ty);
        T.Literal Bool)
      else
        (* Other operations: input types are integers *)
        match (v1.V.ty, v2.V.ty) with
        | T.Literal (Integer int_ty1), T.Literal (Integer int_ty2) -> (
            match binop with
            | E.Lt | E.Le | E.Ge | E.Gt ->
                assert (int_ty1 = int_ty2);
                T.Literal Bool
            | E.Div | E.Rem | E.Add | E.Sub | E.Mul | E.BitXor | E.BitAnd
            | E.BitOr ->
                assert (int_ty1 = int_ty2);
                T.Literal (Integer int_ty1)
            | E.Shl | E.Shr -> raise Unimplemented
            | E.Ne | E.Eq -> raise (Failure "Unreachable"))
        | _ -> raise (Failure "Invalid inputs for binop")
    in
    let res_sv =
      { V.sv_kind = V.FunCallRet; V.sv_id = res_sv_id; sv_ty = res_sv_ty }
    in
    (* Call the continuattion *)
    let v = mk_typed_value_from_symbolic_value res_sv in
    let expr = cf (Ok v) ctx in
    (* Synthesize the symbolic AST *)
    let p1 = S.mk_opt_place_from_op op1 ctx in
    let p2 = S.mk_opt_place_from_op op2 ctx in
    S.synthesize_binary_op ctx binop v1 p1 v2 p2 res_sv None expr
  in
  (* Compose and apply *)
  comp eval_ops compute cf ctx

let eval_binary_op (config : C.config) (binop : E.binop) (op1 : E.operand)
    (op2 : E.operand) (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun
    =
  match config.mode with
  | C.ConcreteMode -> eval_binary_op_concrete config binop op1 op2 cf
  | C.SymbolicMode -> eval_binary_op_symbolic config binop op1 op2 cf

let eval_rvalue_ref (config : C.config) (p : E.place) (bkind : E.borrow_kind)
    (cf : V.typed_value -> m_fun) : m_fun =
 fun ctx ->
  match bkind with
  | E.Shared | E.TwoPhaseMut | E.Shallow ->
      (* **REMARK**: we initially treated shallow borrows like shared borrows.
         In practice this restricted the behaviour too much, so for now we
         forbid them.
      *)
      assert (bkind <> E.Shallow);

      (* Access the value *)
      let access =
        match bkind with
        | E.Shared | E.Shallow -> Read
        | E.TwoPhaseMut -> Write
        | _ -> raise (Failure "Unreachable")
      in

      let expand_prim_copy = false in
      let prepare =
        access_rplace_reorganize_and_read config expand_prim_copy access p
      in
      (* Evaluate the borrowing operation *)
      let eval (cf : V.typed_value -> m_fun) (v : V.typed_value) : m_fun =
       fun ctx ->
        (* Generate the fresh borrow id *)
        let bid = C.fresh_borrow_id () in
        (* Compute the loan value, with which to replace the value at place p *)
        let nv =
          match v.V.value with
          | V.Loan (V.SharedLoan (bids, sv)) ->
              (* Shared loan: insert the new borrow id *)
              let bids1 = V.BorrowId.Set.add bid bids in
              { v with V.value = V.Loan (V.SharedLoan (bids1, sv)) }
          | _ ->
              (* Not a shared loan: add a wrapper *)
              let v' =
                V.Loan (V.SharedLoan (V.BorrowId.Set.singleton bid, v))
              in
              { v with V.value = v' }
        in
        (* Update the borrowed value in the context *)
        let ctx = write_place access p nv ctx in
        (* Compute the rvalue - simply a shared borrow with a the fresh id.
         * Note that the reference is *mutable* if we do a two-phase borrow *)
        let ref_kind =
          match bkind with
          | E.Shared | E.Shallow -> T.Shared
          | E.TwoPhaseMut -> T.Mut
          | _ -> raise (Failure "Unreachable")
        in
        let rv_ty = T.Ref (T.Erased, v.ty, ref_kind) in
        let bc =
          match bkind with
          | E.Shared | E.Shallow ->
              (* See the remark at the beginning of the match branch: we
                 handle shallow borrows like shared borrows *)
              V.SharedBorrow bid
          | E.TwoPhaseMut -> V.ReservedMutBorrow bid
          | _ -> raise (Failure "Unreachable")
        in
        let rv : V.typed_value = { V.value = V.Borrow bc; ty = rv_ty } in
        (* Continue *)
        cf rv ctx
      in
      (* Compose and apply *)
      comp prepare eval cf ctx
  | E.Mut ->
      (* Access the value *)
      let access = Write in
      let expand_prim_copy = false in
      let prepare =
        access_rplace_reorganize_and_read config expand_prim_copy access p
      in
      (* Evaluate the borrowing operation *)
      let eval (cf : V.typed_value -> m_fun) (v : V.typed_value) : m_fun =
       fun ctx ->
        (* Compute the rvalue - wrap the value in a mutable borrow with a fresh id *)
        let bid = C.fresh_borrow_id () in
        let rv_ty = T.Ref (T.Erased, v.ty, Mut) in
        let rv : V.typed_value =
          { V.value = V.Borrow (V.MutBorrow (bid, v)); ty = rv_ty }
        in
        (* Compute the value with which to replace the value at place p *)
        let nv = { v with V.value = V.Loan (V.MutLoan bid) } in
        (* Update the value in the context *)
        let ctx = write_place access p nv ctx in
        (* Continue *)
        cf rv ctx
      in
      (* Compose and apply *)
      comp prepare eval cf ctx

let eval_rvalue_aggregate (config : C.config)
    (aggregate_kind : E.aggregate_kind) (ops : E.operand list)
    (cf : V.typed_value -> m_fun) : m_fun =
  (* Evaluate the operands *)
  let eval_ops = eval_operands config ops in
  (* Compute the value *)
  let compute (cf : V.typed_value -> m_fun) (values : V.typed_value list) :
      m_fun =
   fun ctx ->
    (* Match on the aggregate kind *)
    match aggregate_kind with
    | E.AggregatedTuple ->
        let tys = List.map (fun (v : V.typed_value) -> v.V.ty) values in
        let v = V.Adt { variant_id = None; field_values = values } in
        let ty = T.Adt (T.Tuple, [], tys, []) in
        let aggregated : V.typed_value = { V.value = v; ty } in
        (* Call the continuation *)
        cf aggregated ctx
    | E.AggregatedOption (variant_id, ty) ->
        (* Sanity check *)
        if variant_id = T.option_none_id then assert (values = [])
        else if variant_id = T.option_some_id then
          assert (List.length values = 1)
        else raise (Failure "Unreachable");
        (* Construt the value *)
        let aty = T.Adt (T.Assumed T.Option, [], [ ty ], []) in
        let av : V.adt_value =
          { V.variant_id = Some variant_id; V.field_values = values }
        in
        let aggregated : V.typed_value = { V.value = Adt av; ty = aty } in
        (* Call the continuation *)
        cf aggregated ctx
    | E.AggregatedAdt (def_id, opt_variant_id, regions, types, cgs) ->
        (* Sanity checks *)
        let type_decl = C.ctx_lookup_type_decl ctx def_id in
        assert (List.length type_decl.region_params = List.length regions);
        let expected_field_types =
          Subst.ctx_adt_get_instantiated_field_etypes ctx def_id opt_variant_id
            types cgs
        in
        assert (
          expected_field_types
          = List.map (fun (v : V.typed_value) -> v.V.ty) values);
        (* Construct the value *)
        let av : V.adt_value =
          { V.variant_id = opt_variant_id; V.field_values = values }
        in
        let aty = T.Adt (T.AdtId def_id, regions, types, cgs) in
        let aggregated : V.typed_value = { V.value = Adt av; ty = aty } in
        (* Call the continuation *)
        cf aggregated ctx
    | E.AggregatedRange ety ->
        (* There should be two fields exactly *)
        let v0, v1 =
          match values with
          | [ v0; v1 ] -> (v0, v1)
          | _ -> raise (Failure "Unreachable")
        in
        (* Ranges are parametric over the type of indices. For now we only
           support scalars, which can be of any type *)
        assert (literal_type_is_integer (ty_as_literal ety));
        assert (v0.ty = ety);
        assert (v1.ty = ety);
        (* Construct the value *)
        let av : V.adt_value =
          { V.variant_id = None; V.field_values = values }
        in
        let aty = T.Adt (T.Assumed T.Range, [], [ ety ], []) in
        let aggregated : V.typed_value = { V.value = Adt av; ty = aty } in
        (* Call the continuation *)
        cf aggregated ctx
    | E.AggregatedArray (ety, cg) -> (
        (* Sanity check: all the values have the proper type *)
        assert (List.for_all (fun (v : V.typed_value) -> v.V.ty = ety) values);
        (* Sanity check: the number of values is consistent with the length *)
        let len = (literal_as_scalar (const_generic_as_literal cg)).value in
        assert (len = Z.of_int (List.length values));
        let ty = T.Adt (T.Assumed T.Array, [], [ ety ], [ cg ]) in
        (* In order to generate a better AST, we introduce a symbolic
           value equal to the array. The reason is that otherwise, the
           array we introduce here might be duplicated in the generated
           code: by introducing a symbolic value we introduce a let-binding
           in the generated code. *)
        let saggregated =
          mk_fresh_symbolic_typed_value_from_ety V.Aggregate ty
        in
        (* Call the continuation *)
        match cf saggregated ctx with
        | None -> None
        | Some e ->
            (* Introduce the symbolic value in the AST *)
            let sv = ValuesUtils.value_as_symbolic saggregated.value in
            Some (SymbolicAst.IntroSymbolic (ctx, None, sv, Array values, e)))
  in
  (* Compose and apply *)
  comp eval_ops compute cf

let eval_rvalue_not_global (config : C.config) (rvalue : E.rvalue)
    (cf : (V.typed_value, eval_error) result -> m_fun) : m_fun =
 fun ctx ->
  log#ldebug (lazy "eval_rvalue");
  (* Small helpers *)
  let wrap_in_result (cf : (V.typed_value, eval_error) result -> m_fun)
      (v : V.typed_value) : m_fun =
    cf (Ok v)
  in
  let comp_wrap f = comp f wrap_in_result cf in
  (* Delegate to the proper auxiliary function *)
  match rvalue with
  | E.Use op -> comp_wrap (eval_operand config op) ctx
  | E.Ref (p, bkind) -> comp_wrap (eval_rvalue_ref config p bkind) ctx
  | E.UnaryOp (unop, op) -> eval_unary_op config unop op cf ctx
  | E.BinaryOp (binop, op1, op2) -> eval_binary_op config binop op1 op2 cf ctx
  | E.Aggregate (aggregate_kind, ops) ->
      comp_wrap (eval_rvalue_aggregate config aggregate_kind ops) ctx
  | E.Discriminant _ ->
      raise
        (Failure
           "Unreachable: discriminant reads should have been eliminated from \
            the AST")
  | E.Global _ -> raise (Failure "Unreachable")

let eval_fake_read (config : C.config) (p : E.place) : cm_fun =
 fun cf ctx ->
  let expand_prim_copy = false in
  let cf_prepare cf =
    access_rplace_reorganize_and_read config expand_prim_copy Read p cf
  in
  let cf_continue cf v : m_fun =
   fun ctx ->
    assert (not (bottom_in_value ctx.ended_regions v));
    cf ctx
  in
  comp cf_prepare cf_continue cf ctx
