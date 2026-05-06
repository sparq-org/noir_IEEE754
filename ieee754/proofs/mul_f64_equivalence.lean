/-! ## Diverging-parameter equalities

Round 9 closes the f64 mul equivalence at "weak" reference strength
(see `todos/round9-mul-reference-strength.md` in the workspace).
Two diverging-subterm sites: the inline-RNE 3-bit wrapper and the
128-bit sticky right shift. Both are witnessed by a pointwise
equality lemma in `SubtermsMulF64.lean`. -/

/-- The optimised `shiftRightSticky` parameter
(`shiftRightStickyU128`, the 4-case BitVec dispatch) equals the
reference's (`shiftRightStickyU128Spec`, the `Nat`-level spec)
pointwise. Witnessed by the round-9 task-iii closure
`SubtermsMulF64.shiftRightStickyU128_eq_spec`. -/
private theorem shr_sticky_param_eq :
    shiftRightStickyU128 = shiftRightStickyU128Spec := by
  funext val shift
  exact shiftRightStickyU128_eq_spec val shift

/-- The optimised `rneDecision` parameter (inline-RNE 3-bit
wrapper) equals the reference's (`Models.shouldRoundUp`). For
`mode = 0` both sides reduce to the same boolean expression by
`shouldRoundUp_inline_eq_3bit`; for `mode ≠ 0` the wrapper falls
through to `Models.shouldRoundUp` directly. -/
private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 4) ||
          (decide (gb = 4) && decide (rm &&& 1 = 1))
      else
        Models.shouldRoundUp gb rm rs m) = Models.shouldRoundUp := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp_inline_eq_3bit gb rm rs).symm
  · rw [if_neg hmode]

/-! ## Main theorem -/

/-- The optimised f64 mul is bit-identical to the round-9 IEEE
754 reference f64 mul, for every input and every rounding mode.
The proof rewrites the two diverging-subterm parameters of the
shared skeleton and lets `rfl` finish. -/
theorem mul_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    mulF64Optimised a b mode = mulF64Reference a b mode := by
  unfold mulF64Optimised mulF64Reference
  rw [shr_sticky_param_eq, rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
