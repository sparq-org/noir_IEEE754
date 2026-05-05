/-!
# Equivalence: optimised f64 div = reference f64 div (Tier 4 scaffold)

Status: **sorry-stub**. Methodology documented; proof body to be filled by the
next Lean specialist agent.

## Methodology (skeleton-and-divergence, Tier 4)

The optimised binary64 division at
`circuits/noir_IEEE754/ieee754/src/float64/div.nr` uses **128-bit-by-64-bit
long division** via the `div_u128_by_u64` helper (after a 53-bit dividend
shift, mantissa width 53). This is structurally similar to `div_f32` but
* the dividend is a `U128` (high/low pair), not a `u64`;
* the divide step is a **multi-word** operation handled by
  `div_u128_by_u64` -- a Newton-Raphson-style or schoolbook helper that
  must itself be verified (or modelled as a Lean spec function).

**Algorithm summary (optimised):**
1. Classify operands; handle special cases per IEEE 754-2019 sec.6.2 / sec.7.2.
2. Normalise denormals via 6-step CLZ binary search (`clzDenormalMantissa64`
   shared with mul_f64).
3. Build `U128` dividend = `mant_a` shifted left by 53 - shift_amount;
   `quotient = div_u128_by_u64(shifted_dividend, mant_b)`; remainder
   collapses to a sticky bit.
4. Normalise quotient (3-way split on bit 57 / bit 56 leading-bit position
   -- analogous to f32 div's bit-28 / bit-27 trichotomy).
5. RNE / directed-mode rounding via `should_round_up_4bit`.

## Steps

1. **Author a literal-spec reference** in
   `circuits/noir_IEEE754/ieee754/reference/div_f64_reference.nr.ref`. The
   reference can use the **same long-division shape** but de-fuse
   normalisation + rounding (kept as separate steps for traceability
   against IEEE 754-2019 sec.7.2).
2. **Hand-mirror both sides into Lean models** in `DivModelsF64.lean`. The
   optimised model transcribes `div_float64_with_rounding` line for line;
   the reference model transcribes the new `.nr.ref`.
3. **Factor through `divF64Skeleton` with the divergence parameters** below:
   * **`rneDecision` / `should_round_up_4bit`** -- inline-RNE 4-bit shortcut
     vs `Models.shouldRoundUp`. Author `shouldRoundUp_inline_eq_4bit`
     (4-bit guard); reuse the round-9 `shouldRoundUp_inline_eq_3bit`
     pattern with the constant updated to 8 (= 1 << 3 for 4 guard bits).
   * **`divU128ByU64`** -- the Noir helper's `BitVec`-level dispatch vs a
     reference `Nat`-level division spec. Author
     `divU128ByU64_eq_spec` -- the 128-bit analogue of round-9
     `shiftRightStickyU128_eq_spec`'s shape: case-split on the divisor's
     range, bridge via `Nat.div`, `BitVec.toNat_div`, and the helper's
     local arithmetic. **This is the heaviest divergence** -- expect a
     multi-day proof comparable in size to round-9
     `shiftRightStickyU128_eq_spec`.
   * **`stickyOfRemainder`** -- one-bit sticky test; trivial `rfl` after
     `decide` unfolding (mirrors div_f32).
   * **`quotientNormalise`** -- 3-way trichotomy on the quotient's leading
     bit, analogous to div_f32 but at f64 widths. Author
     `quotientNormalise_eq` as a 3-way case-split.
4. **Per-helper lemma audit.**
   * `clzDenormalMantissa64` -- shared with round-9 mul_f64 (still
     `sorry`-shared per `todos/round9-mul-reference-strength.md`); this
     proof can stay `sorry`-shared too. Strengthening would benefit from
     the same `bv_decide` push that round-10 work targets for mul_f64.
   * `shift_right_sticky_u64` -- shared between optimised and reference
     (no divergence parameter). Closes via `Subterms.shr_sticky_eq` (round
     1) or `SubtermsF64.shr_sticky_eq_64` if a width-specialised version
     exists.
5. **Tie together** with
   `theorem div_f64_equivalence : divF64Optimised = divF64Reference`
   following the round-9 one-liner: `unfold + rw [<divergence-param-eqs>]`.

See `proofs/Ieee754/equivalence-spike-2026-05-04.md` round-9 entries and
`proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/MulF64.lean` for the worked
methodology.
-/

/-- The optimised f64 div is bit-identical to the literal-IEEE-754 reference
f64 div, for every input and every rounding mode. **Sorry-stub** -- proof
body to be filled per the methodology comment above. -/
theorem div_f64_equivalence : True := by
  -- TODO: replace with
  --   theorem div_f64_equivalence (a b : Float64Bits) (mode : BitVec 8) :
  --       divF64Optimised a b mode = divF64Reference a b mode := by ...
  -- once `divF64Optimised` and `divF64Reference` exist in
  -- `ZkpSparql.Ieee754.Equivalence.DivModelsF64`.
  sorry

end ZkpSparql.Ieee754.Equivalence
