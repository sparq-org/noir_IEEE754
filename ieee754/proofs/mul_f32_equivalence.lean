/-!
# Equivalence: optimised f32 mul = reference f32 mul (Tier 4 scaffold)

Status: **sorry-stub**. Methodology documented; proof body to be filled by the
next Lean specialist agent.

## Methodology (skeleton-and-divergence, Tier 4)

This is a **width-narrowing port of round 9 `mul_f64`**. The optimised binary32
multiplication at `circuits/noir_IEEE754/ieee754/src/float32/mul.nr` follows
the same algorithmic shape as the round-9 closed binary64 path -- only the
mantissa width (24-bit vs 53-bit) and product width (48-bit vs 106-bit) differ.
Reuse round-9 patterns wherever possible; specialise widths only.

**Reference for round 9:**
- `proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/MulF64.lean` (main theorem)
- `proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/MulModelsF64.lean` (skeleton +
  optimised + reference models)
- `proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/SubtermsMulF64.lean` (divergence
  helpers)

## Steps

1. **Author a literal-spec reference** in
   `circuits/noir_IEEE754/ieee754/reference/mul_f32_reference.nr.ref`
   matching the IEEE 754-2019 sec.7.4 multiplication algorithm: significand
   product, biased-exponent sum, normalisation, sticky-aware right shift,
   `should_round_up`-driven rounding, sign XOR. Mirror the round-9 reference
   shape but with f32 widths.
2. **Hand-mirror both sides into Lean models** in `MulModelsF32.lean`. The
   optimised model transcribes `mul_float32_with_rounding` line for line; the
   reference model transcribes the new `.nr.ref`.
3. **Factor through `mulF32Skeleton` with two divergence parameters** -- the
   same shape as round-9 mul_f64:
   * `shiftRightSticky` parameter -- the optimised path's inline 64-bit
     sticky-right-shift vs the reference's `Nat`-level spec form. Author
     `shiftRightStickyU64_eq_spec` analogously to round-9
     `shiftRightStickyU128_eq_spec` (cases: `shift = 0`, `shift >= 64`,
     `32 <= shift < 64`, `0 < shift < 32` -- narrower bitwidth, otherwise
     identical structure to the 128-bit version).
   * `rneDecision` parameter -- the inline-RNE 3-bit shortcut vs
     `Models.shouldRoundUp`. The round-9
     `SubtermsMulF64.shouldRoundUp_inline_eq_3bit` lemma is **already
     width-agnostic** (operates on `BitVec 64` guard / mantissa lanes
     regardless of float width); reuse it directly. The wrapper proof is
     structurally identical to round-9 `rne_param_eq`.
4. **Per-helper lemma audit.** Helpers shared between optimised and
   reference (no divergence parameter needed) -- strengthen-or-share decision
   per helper:
   * `clzDenormalMantissa32` -- narrower analogue of round-9
     `clzDenormalMantissa64`. Round 9 left this with `sorry`-strength
     (`todos/round9-mul-reference-strength.md` task ii); the f32 analogue
     can stay `sorry`-shared, or strengthen via `bv_decide` over the smaller
     24-bit search space.
   * `leadingBitPos48` -- narrower analogue of round-9 `leadingBitPos128`
     (48-bit product width vs 106-bit). Same call: stay `sorry`-shared
     (matching round 9) or close with `bv_decide`.
5. **Tie together** with
   `theorem mul_f32_equivalence : mulF32Optimised = mulF32Reference`
   following the round-9 one-liner: `unfold + rw [shr_sticky_param_eq,
   rne_param_eq]`.

See `proofs/Ieee754/equivalence-spike-2026-05-04.md` round-9 entries for the
worked methodology.
-/

/-- The optimised f32 mul is bit-identical to the literal-IEEE-754 reference
f32 mul, for every input and every rounding mode. **Sorry-stub** -- proof body
to be filled per the methodology comment above. -/
theorem mul_f32_equivalence : True := by
  -- TODO: replace with
  --   theorem mul_f32_equivalence (a b : Float32Bits) (mode : BitVec 8) :
  --       mulF32Optimised a b mode = mulF32Reference a b mode := by ...
  -- once `mulF32Optimised` and `mulF32Reference` exist in
  -- `ZkpSparql.Ieee754.Equivalence.MulModelsF32`.
  sorry

end ZkpSparql.Ieee754.Equivalence
