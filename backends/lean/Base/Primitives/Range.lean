/- Arrays/slices -/
import Lean
import Lean.Meta.Tactic.Simp
import Init.Data.List.Basic
import Mathlib.Tactic.RunCmd
import Mathlib.Tactic.Linarith
import Base.IList
import Base.Primitives.Scalar
import Base.Arith
import Base.Progress.Base

namespace Primitives

structure Range (α : Type u) where
  mk ::
  start: α
  end_: α

end Primitives
