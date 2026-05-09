/-! ## Diverging-parameter equality

Tier 4 baseline closes the f64 div equivalence with a **single**
diverging subterm: the inline-RNE 4-bit shortcut for `mode == 0`.
All heavier helpers (`div_u128_by_u64`, `clz_denormal_mantissa64`,
`shift_right_sticky_u64`) are shared between the optimised and
reference paths verbatim, so they are non-divergences in the
baseline closure.

The strengthening item -- lifting `div_u128_by_u64` to a `Nat`-
level literal-spec reference (the round-9-task-iii analogue) --
is queued in `SubtermsDivF64.divU128ByU64_eq_spec`. -/

/-- The optimised `rneDecision` parameter (inline-RNE 4-bit
wrapper) equals the reference's (`shouldRoundUp4Bit`). For
`mode = 0` both sides reduce to the same boolean expression by
`shouldRoundUp4Bit_inline_eq`; for `mode ≠ 0` the wrapper falls
through to `shouldRoundUp4Bit` directly. -/
private theorem rne_param_eq_4bit :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 8) ||
          (decide (gb = 8) && decide (rm &&& 1 = 1))
      else
        shouldRoundUp4Bit gb rm rs m) = shouldRoundUp4Bit := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp4Bit_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

/-! ## Main theorem -/

/-- The optimised f64 div is bit-identical to the literal IEEE
754 reference f64 div, for every input and every rounding mode.
The proof rewrites the single diverging-subterm parameter of the
shared skeleton and lets `rfl` finish.

**Strength.** Round-9 baseline (one divergence parameter, with
the heavier helpers shared between sides). The strengthening
item -- lifting `div_u128_by_u64` to a `Nat`-level literal-spec
reference via `SubtermsDivF64.divU128ByU64_eq_spec` -- carries
one `sorry` in `SubtermsDivF64.lean` (the multi-day per-step
invariant induction over the 128-iteration long-division loop;
the `divisor = 0` and `dividend.high = 0` sub-cases are closed).
This `sorry` is a strength gap in the helper, not in the main
theorem: `divU128ByU64` is shared between sides verbatim, so
the equivalence proof itself does not depend on
`divU128ByU64_eq_spec`. -/
theorem div_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    divF64Optimised a b mode = divF64Reference a b mode := by
  unfold divF64Optimised divF64Reference
  rw [rne_param_eq_4bit]

end ZkpSparql.Ieee754.Equivalence
