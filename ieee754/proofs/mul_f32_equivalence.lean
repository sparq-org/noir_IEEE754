/-!
# Equivalence: optimised f32 mul = reference f32 mul (Tier 4, round 9 width-narrow)

The optimised `mul_float32_with_rounding` is bit-identical to the
literal-IEEE-754 reference at single-precision widths. **Width-narrowing
port of round 9 mul_f64.**

## Methodology (skeleton-and-divergence)

Both the optimised and reference f32 mul models in
`ZkpSparql.Ieee754.Equivalence.MulModelsF32` factor through a single
`mulF32Skeleton` that is parameterised on the round-decision predicate
`rneDecision`. They diverge at exactly **one** syntactic point:

* The optimised path inlines the `rounding_mode == 0` (RNE) special
  case as `(guardBits > 4) | ((guardBits == 4) & (resultMant & 1))`,
  bypassing the dispatch through `Models.shouldRoundUp`.

The wrapper proof is structurally identical to the round-9 mul_f64
`rne_param_eq` and reuses the round-9 width-agnostic lemma
`SubtermsMulF64.shouldRoundUp_inline_eq_3bit` directly (the lemma
operates on `BitVec 64` guard / mantissa lanes regardless of float
width).

The denormal-mantissa CLZ (`clzDenormalMantissa32`) and the 64-bit
leading-bit search are still shared between the two paths, matching
the round-9 baseline strength on the f64 side. Strengthening them to
literal-loop references is queued analogously to round-9 task ii /
task iv (see `todos/round9-mul-reference-strength.md` for the f64
template).

## Diverging-parameter equality
-/

/-- The optimised `rneDecision` parameter (inline-RNE 3-bit wrapper)
equals the reference's (`Models.shouldRoundUp`). For `mode = 0` both
sides reduce to the same boolean expression by
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

/-- The optimised f32 mul is bit-identical to the literal-IEEE-754
reference f32 mul, for every input and every rounding mode. The proof
rewrites the single diverging-subterm parameter of the shared skeleton
and lets `rfl` finish. -/
theorem mul_f32_equivalence
    (a b : Float32Bits) (mode : BitVec 8) :
    mulF32Optimised a b mode = mulF32Reference a b mode := by
  unfold mulF32Optimised mulF32Reference
  rw [rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
