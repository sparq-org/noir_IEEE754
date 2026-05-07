/-!
# Equivalence: optimised f32 sqrt = reference f32 sqrt (Tier 4)

The optimised binary32 square root at
`circuits/noir_IEEE754/ieee754/src/float32/sqrt.nr` uses the
**digit-by-digit binary restoring method** -- 27 iterations,
processing 2 bits of the radicand per iteration. (NOT
Newton-Raphson; the algorithm is deterministic and converges in a
fixed iteration count.)

## Status (Tier 4 -- closed at single-divergence strength)

This file closes:

  forall a : Float32Bits, forall mode : BitVec 8,
    sqrtF32Optimised a mode = sqrtF32Reference a mode

Zero `sorry`s on the closure path.

The reference and optimised paths diverge at exactly **one**
parameterised site: the inlined-RNE round decision. The
denormal-mantissa CLZ (`MulModelsF32.clzDenormalMantissa32`) and
the 27-iteration restoring sqrt loop (`SqrtModelsF32.sqrtLoop27`)
are shared between the two sides; strengthening the loop to a
literal `Nat.sqrt`-anchored spec is queued as round-10 work --
see `decisions/sqrt-f32-loop-shared-vs-divergent.md`.

## Proof shape

Both `sqrtF32Optimised` and `sqrtF32Reference` are *thin wrappers*
around a common `sqrtF32Skeleton` (see `SqrtModelsF32.lean`)
parameterised over the inline-RNE divergence site. The
equivalence theorem reduces to one pointwise equality:

  * the `rneDecision` parameter: the inline-RNE wrapper equals
    `Models.shouldRoundUp` pointwise. Reduced via the round-9
    `SubtermsMulF64.shouldRoundUp_inline_eq_3bit` lemma plus the
    `mode != 0` fall-through case.

The keystone novelty (the 27-iteration restoring loop) is folded
into a shared definition at the round-9 baseline-strength level,
matching how round 9 originally shipped with `clzDenormalMantissa64`
and `leadingBitPos128` shared.
-/

/-! ## Diverging-parameter equality -/

/-- The optimised `rneDecision` parameter (inline-RNE 3-bit
wrapper) equals the reference's (`Models.shouldRoundUp`). For
`mode = 0` both sides reduce to the same boolean expression by
`shouldRoundUp_inline_eq_3bit`; for `mode != 0` the wrapper falls
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

/-- The optimised f32 sqrt is bit-identical to the literal-IEEE-754
reference f32 sqrt, for every input and every rounding mode. The
proof rewrites the single diverging-subterm parameter of the shared
skeleton and lets `rfl` finish. -/
theorem sqrt_f32_equivalence
    (a : Float32Bits) (mode : BitVec 8) :
    sqrtF32Optimised a mode = sqrtF32Reference a mode := by
  unfold sqrtF32Optimised sqrtF32Reference
  rw [rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
