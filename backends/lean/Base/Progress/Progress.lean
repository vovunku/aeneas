import Lean
import Base.Arith
import Base.Progress.Base
import Base.Primitives -- TODO: remove?

namespace Progress

open Lean Elab Term Meta Tactic
open Utils

inductive TheoremOrLocal where
| Theorem (thName : Name)
| Local (asm : LocalDecl)

instance : ToMessageData TheoremOrLocal where
  toMessageData := λ x => match x with | .Theorem thName => m!"{thName}" | .Local asm => m!"{asm.userName}"

/- Type to propagate the errors of `progressWith`.
   We need this because we use the exceptions to backtrack, when trying to
   use the assumptions for instance. When there is actually an error we want
   to propagate to the user, we return it. -/
inductive ProgressError
| Ok
| Error (msg : MessageData)
deriving Inhabited

def progressWith (fExpr : Expr) (th : TheoremOrLocal)
  (keep : Option Name) (ids : Array (Option Name)) (splitPost : Bool)
  (asmTac : TacticM Unit) : TacticM ProgressError := do
  /- Apply the theorem
     We try to match the theorem with the goal
     In order to do so, we introduce meta-variables for all the parameters
     (i.e., quantified variables and assumpions), and unify those with the goal.
     Remark: we do not introduce meta-variables for the quantified variables
     which don't appear in the function arguments (we want to let them
     quantified).
     We also make sure that all the meta variables which appear in the
     function arguments have been instantiated
   -/
  let env ← getEnv
  let thTy ← do
    match th with
    | .Theorem thName =>
      let thDecl := env.constants.find! thName
      -- We have to introduce fresh meta-variables for the universes already
      let ul : List (Name × Level) ←
        thDecl.levelParams.mapM (λ x => do pure (x, ← mkFreshLevelMVar))
      let ulMap : HashMap Name Level := HashMap.ofList ul
      let thTy := thDecl.type.instantiateLevelParamsCore (λ x => ulMap.find! x)
      pure thTy
    | .Local asmDecl => pure asmDecl.type
  trace[Progress] "Looked up theorem/assumption type: {thTy}"
  -- TODO: the tactic fails if we uncomment withNewMCtxDepth
  -- withNewMCtxDepth do
  let (mvars, binders, thExBody) ← forallMetaTelescope thTy
  trace[Progress] "After stripping foralls: {thExBody}"
  -- Introduce the existentially quantified variables and the post-condition
  -- in the context
  let thBody ←
    existsTelescope thExBody.consumeMData fun _evars thBody => do
    trace[Progress] "After stripping existentials: {thBody}"
    let (thBody, _) ← optSplitConj thBody
    trace[Progress] "After splitting the conjunction: {thBody}"
    let (thBody, _) ← destEq thBody
    trace[Progress] "After splitting equality: {thBody}"
    -- There shouldn't be any existential variables in thBody
    pure thBody.consumeMData
  -- Match the body with the target
  trace[Progress] "Matching:\n- body:\n{thBody}\n- target:\n{fExpr}"
  let ok ← isDefEq thBody fExpr
  if ¬ ok then throwError "Could not unify the theorem with the target:\n- theorem: {thBody}\n- target: {fExpr}"
  let mgoal ← Tactic.getMainGoal
  postprocessAppMVars `progress mgoal mvars binders true true
  Term.synthesizeSyntheticMVarsNoPostponing
  let thBody ← instantiateMVars thBody
  trace[Progress] "thBody (after instantiation): {thBody}"
  -- Add the instantiated theorem to the assumptions (we apply it on the metavariables).
  let th ← do
    match th with
    | .Theorem thName => mkAppOptM thName (mvars.map some)
    | .Local decl => mkAppOptM' (mkFVar decl.fvarId) (mvars.map some)
  let asmName ← do match keep with | none => mkFreshAnonPropUserName | some n => do pure n
  let thTy ← inferType th
  let thAsm ← Utils.addDeclTac asmName th thTy (asLet := false)
  withMainContext do -- The context changed - TODO: remove once addDeclTac is updated
  let ngoal ← getMainGoal
  trace[Progress] "current goal: {ngoal}"
  trace[Progress] "current goal: {← ngoal.isAssigned}"
  -- The assumption should be of the shape:
  -- `∃ x1 ... xn, f args = ... ∧ ...`
  -- We introduce the existentially quantified variables and split the top-most
  -- conjunction if there is one. We use the provided `ids` list to name the
  -- introduced variables.
  let res ← splitAllExistsTac thAsm ids.toList fun h ids => do
    -- Split the conjunctions.
    -- For the conjunctions, we split according once to separate the equality `f ... = .ret ...`
    -- from the postcondition, if there is, then continue to split the postcondition if there
    -- are remaining ids.
    let splitEqAndPost (k : Expr → Option Expr → List (Option Name) → TacticM ProgressError) : TacticM ProgressError := do
      if ← isConj (← inferType h) then do
        let hName := (← h.fvarId!.getDecl).userName
        let (optIds, ids) ← do
          match ids with
          | [] => do pure (some (hName, ← mkFreshAnonPropUserName), [])
          | none :: ids => do pure (some (hName, ← mkFreshAnonPropUserName), ids)
          | some id :: ids => do pure (some (hName, id), ids)
        splitConjTac h optIds (fun hEq hPost => k hEq (some hPost) ids)
      else k h none ids
    -- Simplify the target by using the equality and some monad simplifications,
    -- then continue splitting the post-condition
    splitEqAndPost fun hEq hPost ids => do
    trace[Progress] "eq and post:\n{hEq} : {← inferType hEq}\n{hPost}"
    simpAt [] [``Primitives.bind_tc_ret, ``Primitives.bind_tc_fail, ``Primitives.bind_tc_div]
           [hEq.fvarId!] (.targets #[] true)
    -- Clear the equality, unless the user requests not to do so
    let mgoal ← do
      if keep.isSome then getMainGoal
      else do
        let mgoal ← getMainGoal
        mgoal.tryClearMany #[hEq.fvarId!]
    setGoals (mgoal :: (← getUnsolvedGoals))
    trace[Progress] "Goal after splitting eq and post and simplifying the target: {mgoal}"
    -- Continue splitting following the post following the user's instructions
    match hPost with
    | none =>
      -- Sanity check
      if ¬ ids.isEmpty then
        return (.Error m!"Too many ids provided ({ids}): there is no postcondition to split")
      else return .Ok
    | some hPost => do
      let rec splitPostWithIds (prevId : Name) (hPost : Expr) (ids0 : List (Option Name)) : TacticM ProgressError := do
        match ids0 with
        | [] =>
          /- We used all the user provided ids.
             Split the remaining conjunctions by using fresh ids if the user
             instructed to fully split the post-condition, otherwise stop -/
          if splitPost then
            splitFullConjTac true hPost (λ _ => pure .Ok)
          else pure .Ok
        | nid :: ids => do
          trace[Progress] "Splitting post: {← inferType hPost}"
          -- Split
          let nid ← do
            match nid with
            | none => mkFreshAnonPropUserName
            | some nid => pure nid
          trace[Progress] "\n- prevId: {prevId}\n- nid: {nid}\n- remaining ids: {ids}"
          if ← isConj (← inferType hPost) then
            splitConjTac hPost (some (prevId, nid)) (λ _ nhPost => splitPostWithIds nid nhPost ids)
          else return (.Error m!"Too many ids provided ({ids0}) not enough conjuncts to split in the postcondition")
      let curPostId := (← hPost.fvarId!.getDecl).userName
      splitPostWithIds curPostId hPost ids
  match res with
  | .Error _ => return res -- Can we get there? We're using "return"
  | .Ok =>
    -- Update the set of goals
    let curGoals ← getUnsolvedGoals
    let newGoals := mvars.map Expr.mvarId!
    let newGoals ← newGoals.filterM fun mvar => not <$> mvar.isAssigned
    trace[Progress] "new goals: {newGoals}"
    setGoals newGoals.toList
    allGoals asmTac
    let newGoals ← getUnsolvedGoals
    setGoals (newGoals ++ curGoals)
    trace[Progress] "progress: replaced the goals"
    --
    pure .Ok

-- Small utility: if `args` is not empty, return the name of the app in the first
-- arg, if it is a const.
def getFirstArgAppName (args : Array Expr) : MetaM (Option Name) := do
  if args.size = 0 then pure none
  else
    (args.get! 0).withApp fun f _ => do
    if f.isConst then pure (some f.constName)
    else pure none

def getFirstArg (args : Array Expr) : Option Expr := do
  if args.size = 0 then none
  else some (args.get! 0)

/- Helper: try to lookup a theorem and apply it, or continue with another tactic
   if it fails -/
def tryLookupApply (keep : Option Name) (ids : Array (Option Name)) (splitPost : Bool)
  (asmTac : TacticM Unit) (fExpr : Expr)
  (kind : String) (th : Option TheoremOrLocal) (x : TacticM Unit) : TacticM Unit := do
  let res ← do
    match th with
    | none =>
      trace[Progress] "Could not find a {kind}"
      pure none
    | some th => do
      trace[Progress] "Lookuped up {kind}: {th}"
      -- Apply the theorem
      let res ← do
        try
          let res ← progressWith fExpr th keep ids splitPost asmTac
          pure (some res)
        catch _ => none
  match res with
  | some .Ok => return ()
  | some (.Error msg) => throwError msg
  | none => x

-- The array of ids are identifiers to use when introducing fresh variables
def progressAsmsOrLookupTheorem (keep : Option Name) (withTh : Option TheoremOrLocal)
  (ids : Array (Option Name)) (splitPost : Bool) (asmTac : TacticM Unit) : TacticM Unit := do
  withMainContext do
  -- Retrieve the goal
  let mgoal ← Tactic.getMainGoal
  let goalTy ← mgoal.getType
  trace[Progress] "goal: {goalTy}"
  -- Dive into the goal to lookup the theorem
  let (fExpr, fName, args) ← do
    withPSpec goalTy fun desc =>
    -- TODO: check that no quantified variables in the arguments
    pure (desc.fExpr, desc.fName, desc.args)
  trace[Progress] "Function: {fName}"
  -- If the user provided a theorem/assumption: use it.
  -- Otherwise, lookup one.
  match withTh with
  | some th => do
    match ← progressWith fExpr th keep ids splitPost asmTac with
    | .Ok => return ()
    | .Error msg => throwError msg
  | none =>
    -- Try all the assumptions one by one and if it fails try to lookup a theorem.
    let ctx ← Lean.MonadLCtx.getLCtx
    let decls ← ctx.getDecls
    for decl in decls.reverse do
      trace[Progress] "Trying assumption: {decl.userName} : {decl.type}"
      let res ← do try progressWith fExpr (.Local decl) keep ids splitPost asmTac catch _ => continue
      match res with
      | .Ok => return ()
      | .Error msg => throwError msg
    -- It failed: try to lookup a theorem
    -- TODO: use a list of theorems, and try them one by one?
    trace[Progress] "No assumption succeeded: trying to lookup a theorem"
    let pspec ← do
      let thName ← pspecAttr.find? fName
      pure (thName.map fun th => .Theorem th)
    tryLookupApply keep ids splitPost asmTac fExpr "pspec theorem" pspec do
    -- It failed: try to lookup a *class* expr spec theorem (those are more
    -- specific than class spec theorems)
    let pspecClassExpr ← do
      match getFirstArg args with
      | none => pure none
      | some arg => do
        let thName ← pspecClassExprAttr.find? fName arg
        pure (thName.map fun th => .Theorem th)
    tryLookupApply keep ids splitPost asmTac fExpr "pspec class expr theorem" pspecClassExpr do
    -- It failed: try to lookup a *class* spec theorem
    let pspecClass ← do
      match ← getFirstArgAppName args with
      | none => pure none
      | some argName => do
        let thName ← pspecClassAttr.find? fName argName
        pure (thName.map fun th => .Theorem th)
    tryLookupApply keep ids splitPost asmTac fExpr "pspec class theorem" pspecClass do
    -- Try a recursive call - we try the assumptions of kind "auxDecl"
    let ctx ← Lean.MonadLCtx.getLCtx
    let decls ← ctx.getAllDecls
    let decls := decls.filter (λ decl => match decl.kind with
      | .default | .implDetail => false | .auxDecl => true)
    for decl in decls.reverse do
      trace[Progress] "Trying recursive assumption: {decl.userName} : {decl.type}"
      let res ← do try progressWith fExpr (.Local decl) keep ids splitPost asmTac catch _ => continue
      match res with
      | .Ok => return ()
      | .Error msg => throwError msg
    -- Nothing worked: failed
    throwError "Progress failed"

syntax progressArgs := ("keep" (ident <|> "_"))? ("with" ident)? ("as" " ⟨ " (ident <|> "_"),* " .."? " ⟩")?

def evalProgress (args : TSyntax `Progress.progressArgs) : TacticM Unit := do
  let args := args.raw
  -- Process the arguments to retrieve the identifiers to use
  trace[Progress] "Progress arguments: {args}"
  let (keepArg, withArg, asArgs) ←
    match args.getArgs.toList with
    | [keepArg, withArg, asArgs] => do pure (keepArg, withArg, asArgs)
    | _ => throwError "Unexpected: invalid arguments"
  let keep : Option Name ← do
    trace[Progress] "Keep arg: {keepArg}"
    let args := keepArg.getArgs
    if args.size > 0 then do
      trace[Progress] "Keep args: {args}"
      let arg := args.get! 1
      trace[Progress] "Keep arg: {arg}"
      if arg.isIdent then pure (some arg.getId)
      else do pure (some (← mkFreshAnonPropUserName))
    else do pure none
  trace[Progress] "Keep: {keep}"
  let withArg ← do
    let withArg := withArg.getArgs
    if withArg.size > 0 then
      let id := withArg.get! 1
      trace[Progress] "With arg: {id}"
      -- Attempt to lookup a local declaration
      match (← getLCtx).findFromUserName? id.getId with
      | some decl => do
        trace[Progress] "With arg: local decl"
        pure (some (.Local decl))
      | none => do
        -- Not a local declaration: should be a theorem
        trace[Progress] "With arg: theorem"
        addCompletionInfo <| CompletionInfo.id id id.getId (danglingDot := false) {} none
        let cs ← resolveGlobalConstWithInfos id
        match cs with
        | [] => throwError "Could not find theorem {id}"
        | id :: _ =>
          pure (some (.Theorem id))
    else pure none
  let ids :=
    let args := asArgs.getArgs
    let args := (args.get! 2).getSepArgs
    args.map (λ s => if s.isIdent then some s.getId else none)
  trace[Progress] "User-provided ids: {ids}"
  let splitPost : Bool :=
    let args := asArgs.getArgs
    (args.get! 3).getArgs.size > 0
  trace[Progress] "Split post: {splitPost}"
  /- For scalarTac we have a fast track: if the goal is not a linear
     arithmetic goal, we skip (note that otherwise, scalarTac would try
     to prove a contradiction) -/
  let scalarTac : TacticM Unit := do
    if ← Arith.goalIsLinearInt then
      -- Also: we don't try to split the goal if it is a conjunction
      -- (it shouldn't be)
      Arith.scalarTac false
    else
      throwError "Not a linear arithmetic goal"
  progressAsmsOrLookupTheorem keep withArg ids splitPost (
    withMainContext do
    trace[Progress] "trying to solve assumption: {← getMainGoal}"
    firstTac [assumptionTac, scalarTac])
  trace[Diverge] "Progress done"

elab "progress" args:progressArgs : tactic =>
  evalProgress args

namespace Test
  open Primitives Result

  set_option trace.Progress true
  set_option pp.rawOnError true

  #eval showStoredPSpec
  #eval showStoredPSpecClass

  example {ty} {x y : Scalar ty}
    (hmin : Scalar.min ty ≤ x.val + y.val)
    (hmax : x.val + y.val ≤ Scalar.max ty) :
    ∃ z, x + y = ret z ∧ z.val = x.val + y.val := by
    progress keep _ as ⟨ z, h1 .. ⟩
    simp [*, h1]

  example {ty} {x y : Scalar ty}
    (hmin : Scalar.min ty ≤ x.val + y.val)
    (hmax : x.val + y.val ≤ Scalar.max ty) :
    ∃ z, x + y = ret z ∧ z.val = x.val + y.val := by
    progress keep h with Scalar.add_spec as ⟨ z ⟩
    simp [*, h]

  /- Checking that universe instantiation works: the original spec uses
     `α : Type u` where u is quantified, while here we use `α : Type 0` -/
  example {α : Type} (v: Vec α) (i: Usize) (x : α)
    (hbounds : i.val < v.length) :
    ∃ nv, v.index_mut_back α i x = ret nv ∧
    nv.val = v.val.update i.val x := by
    progress
    simp [*]

end Test

end Progress
