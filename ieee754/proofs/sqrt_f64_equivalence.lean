/-!
# Equivalence: optimised f64 sqrt = reference f64 sqrt (Tier 4 scaffold)

Status: **sorry-stub**. Methodology documented; proof body to be filled by the
next Lean specialist agent.

## Methodology (skeleton-and-divergence, Tier 4)

The optimised binary64 square root at
`circuits/noir_IEEE754/ieee754/src/float64/sqrt.nr` uses the
**digit-by-digit binary restoring method** -- 56 iterations, processing 2
bits of the radicand per iteration. Width-widened analogue of f32 sqrt:
   * `U128` remainder (vs `u64` in f32);
   * 56 iterations for 112-bit input (vs 27 for 54-bit in f32);
   * 53-bit significand path (vs 24-bit in f32).

NOT Newton-Raphson; the algorithm is deterministic and converges in a fixed
iteration count.

**Algorithm summary (optimised):**
1. Classify operand; handle special cases.
2. Normalise denormal via 6-step CLZ binary search
   (`clzDenormalMantissa64` shared with mul_f64).
3. Adjust mantissa for odd exponent.
4. Form `radicand` (U128).
5. **Restoring-square-root loop** -- 56 iterations on a `(U128 remainder,
   u64 sqrt_result)` state.
6. Sticky-bit OR-in if `remainder != 0`.
7. RNE / directed-mode rounding via inline-RNE 4-bit shortcut (mode 0) or
   `should_round_up` fallback.

## Steps

1. **Author a literal-spec reference** in
   `circuits/noir_IEEE754/ieee754/reference/sqrt_f64_reference.nr.ref`.
   The reference can use the **same restoring-method shape** (the 56-iter
   loop is already deterministic). De-fuse normalisation + rounding.
2. **Hand-mirror both sides into Lean models** in `SqrtModelsF64.lean`. The
   56-iteration loop becomes a `Nat`-recursion or `List.range 56` fold over
   `(remainder : BitVec 128, sqrtResult : BitVec 64)` state.
3. **Factor through `sqrtF64Skeleton` with the divergence parameters** below:
   * **`rneDecision`** -- inline-RNE 3-bit shortcut (`guard_bits = result_mant
     & 0x7`, threshold 4 with LSB tie-break) vs `Models.shouldRoundUp`.
     Reuse the round-9 `SubtermsMulF64.shouldRoundUp_inline_eq_3bit` lemma
     directly -- it is width-agnostic on the guard / mantissa lanes.
   * **`sqrtLoop64`** -- the optimised 56-iteration restoring loop on
     `U128` state vs a reference `sqrtLoop64Spec`. Author
     `sqrtLoop64_eq_spec` -- the loop-invariant proof. The invariant is the
     same as f32 sqrt's (`remainder = radicand_so_far - sqrtResult^2`,
     algebraically), but at U128 width. **If sqrt_f32 lands first**, the
     U128-version may be portable from the f32 lemma's structure (induction
     on iteration count, per-step lemma `sqrtStep64_correct`).
   * **`stickyOfRemainder`** -- `U128`-level test (high == 0 && low == 0);
     trivial after `BitVec.toNat` unfolding.
4. **Per-helper lemma audit.**
   * `clzDenormalMantissa64` -- shared with round-9 mul_f64 (still
     `sorry`-shared per `todos/round9-mul-reference-strength.md`); stay
     `sorry`-shared.
   * `shift_right_sticky_u64` -- shared between optimised + reference.
     Closes via `Subterms.shr_sticky_eq` (round 1) or
     `SubtermsF64.shr_sticky_eq_64` if a width-specialised version exists.
   * `U128` arithmetic helpers (`U128`-shift-by-2, `U128`-`>=`, `U128`-sub)
     -- these are **shared** between optimised and reference; close via a
     small `BitVec 128` lemma library or by inlining the `Nat`-level form.
5. **Tie together** with
   `theorem sqrt_f64_equivalence : sqrtF64Optimised = sqrtF64Reference`
   following the round-9 one-liner: `unfold + rw [<divergence-param-eqs>]`.

See `proofs/Ieee754/equivalence-spike-2026-05-04.md` round-9 entries and
`proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/MulF64.lean` for the worked
methodology. Land sqrt_f32 first -- the f32 loop-invariant proof structure
ports directly to f64 once the U128 arithmetic library is in place.
-/

/-- The optimised f64 sqrt is bit-identical to the literal-IEEE-754
reference f64 sqrt, for every input and every rounding mode. **Sorry-stub**
-- proof body to be filled per the methodology comment above. -/
theorem sqrt_f64_equivalence : True := by
  -- TODO: replace with
  --   theorem sqrt_f64_equivalence (a : Float64Bits) (mode : BitVec 8) :
  --       sqrtF64Optimised a mode = sqrtF64Reference a mode := by ...
  -- once `sqrtF64Optimised` and `sqrtF64Reference` exist in
  -- `ZkpSparql.Ieee754.Equivalence.SqrtModelsF64`.
  sorry

end ZkpSparql.Ieee754.Equivalence
