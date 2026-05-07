/-!
# Equivalence: optimised f32 div = reference f32 div (Tier 4)

The optimised `div_float32_with_rounding` is bit-identical to the
literal-IEEE-754 reference at single-precision widths.

## Methodology (skeleton-and-divergence)

Both the optimised and reference f32 div models in
`ZkpSparql.Ieee754.Equivalence.DivModelsF32` factor through a single
`divF32Skeleton` parameterised on the round-decision predicate
`rneDecision`. They diverge at exactly **one** syntactic point:

* The optimised path inlines the `rounding_mode == 0` (RNE) special
  case as `(guard > 8) | ((guard == 8) & (mant & 1))` (4-bit guard
  form, midpoint at 8), bypassing the dispatch through
  `DivModelsF64.shouldRoundUp4Bit`.

The wrapper proof reuses the round-9 / mul_f32 closure shape; the
only difference vs `mul_f32_equivalence` is the midpoint constant
(8 for the 4-bit-guard division form, 4 for the 3-bit-guard
multiplication form).

The `shouldRoundUp4Bit_inline_eq` lemma is reused verbatim from the
f64-div closure (`SubtermsDivF64`); it is width-agnostic because the
guard / mantissa lanes are `BitVec 64` regardless of the float
precision.

The other syntactic differences flagged in the original Tier-4
methodology doc-comment turn out to be **non-divergences**:

* **Sticky-from-remainder** is the same `if remainder ≠ 0 then mant
  ||| 1 else mant` idiom on both sides; shared verbatim through the
  skeleton.
* **Quotient normalisation** is the same `(bit_28_set, bit_27_clear ∧
  ¬bit_28_set ∧ quotient ≠ 0)` two-`if` cascade on both sides;
  shared verbatim. The mutual exclusion (`bit_27_clear` cannot be
  true when `bit_28_set` is true and `quotient ≠ 0`) means the
  cascade is well-defined for every input.

The denormal-mantissa CLZ (`clzDenormalMantissa32F32Div`) and the
Noir builtin `u64 / u64` / `u64 % u64` are also shared (the divide
step itself converges: Noir's builtin `/` is deterministic; nothing
to verify). This matches the round-9 baseline strength.
-/

/-! ## Diverging-parameter equality -/

/-- The optimised `rneDecision` parameter (inline-RNE 4-bit wrapper)
equals the reference's (`DivModelsF64.shouldRoundUp4Bit`). For
`mode = 0` both sides reduce to the same boolean expression by
`shouldRoundUp4Bit_inline_eq`; for `mode ≠ 0` the wrapper falls
through to `DivModelsF64.shouldRoundUp4Bit` directly. -/
private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 8) ||
          (decide (gb = 8) && decide (rm &&& 1 = 1))
      else
        DivModelsF64.shouldRoundUp4Bit gb rm rs m) =
    DivModelsF64.shouldRoundUp4Bit := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (SubtermsDivF64.shouldRoundUp4Bit_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

/-! ## Main theorem -/

/-- The optimised f32 div is bit-identical to the literal-IEEE-754
reference f32 div, for every input and every rounding mode. The proof
rewrites the single diverging-subterm parameter of the shared
skeleton and lets `rfl` finish. -/
theorem div_f32_equivalence
    (a b : Float32Bits) (mode : BitVec 8) :
    DivModelsF32.divF32Optimised a b mode = DivModelsF32.divF32Reference a b mode := by
  unfold DivModelsF32.divF32Optimised DivModelsF32.divF32Reference
  rw [rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
