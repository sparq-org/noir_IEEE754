/-!
# Equivalence: optimised f32 sqrt = reference f32 sqrt (Tier 4 scaffold)

Status: **sorry-stub**. Methodology documented; proof body to be filled by the
next Lean specialist agent.

## Methodology (skeleton-and-divergence, Tier 4)

The optimised binary32 square root at
`circuits/noir_IEEE754/ieee754/src/float32/sqrt.nr` uses the
**digit-by-digit binary restoring method** -- 27 iterations, processing 2
bits of the radicand per iteration. (NOT Newton-Raphson; the algorithm is
deterministic and converges in a fixed iteration count.)

**Algorithm summary (optimised):**
1. Classify operand; handle special cases (NaN, +/-Inf, +/-0, negative-non-zero
   per IEEE 754-2019 sec.5.4.1 / sec.6.2).
2. Normalise denormal via 5-step CLZ binary search.
3. Adjust mantissa for odd exponent (multiply by 2 if odd).
4. Form `radicand = adjusted_mant << 29`.
5. **Restoring-square-root loop** -- 27 iterations:
   - Shift `remainder` left by 2; OR-in next 2 radicand bits.
   - Test `remainder >= (sqrt_result << 2) | 1`; if true, subtract and
     OR-in 1 into `sqrt_result`; otherwise just shift `sqrt_result` left.
6. Sticky-bit OR-in if `remainder != 0`.
7. RNE / directed-mode rounding via inline-RNE 3-bit shortcut (mode 0) or
   `should_round_up` fallback.

## Steps

1. **Author a literal-spec reference** in
   `circuits/noir_IEEE754/ieee754/reference/sqrt_f32_reference.nr.ref`. The
   reference can use the **same restoring-method shape** -- the 27-iteration
   loop is already deterministic. The reference deliberately *de-fuses*
   normalisation + rounding (kept as separate steps for traceability
   against IEEE 754-2019 sec.5.4.1).
2. **Hand-mirror both sides into Lean models** in `SqrtModelsF32.lean`. The
   optimised model transcribes `sqrt_float32_with_rounding` line for line.
   The 27-iteration loop becomes a `Nat`-recursion or a `List.range 27`
   fold over `(remainder, sqrtResult)` state.
3. **Factor through `sqrtF32Skeleton` with the divergence parameters** below:
   * **`rneDecision`** -- inline-RNE 3-bit shortcut vs `Models.shouldRoundUp`.
     Reuse the round-9 `SubtermsMulF64.shouldRoundUp_inline_eq_3bit` lemma
     (width-agnostic). The wrapper proof is structurally identical to
     round-9 `rne_param_eq`.
   * **`sqrtLoop`** -- the optimised 27-iteration restoring loop vs a
     reference `sqrtLoopSpec` (or `Nat.sqrt`-derived form). Author
     `sqrtLoop_eq_spec` -- the loop-invariant proof. The invariant after
     iteration `i` is:
        `remainder = radicand >> (52 - 2*(i+1)) -- sqrt_result^2`
     where the equation holds modulo the trailing low bits not yet
     consumed. Closure plan: prove the invariant by induction on `i`
     (`Nat.rec` over `0..27`), using `BitVec.shiftLeft` / `BitVec.shiftRight`
     identities and a per-step lemma `sqrtStep_correct` that captures the
     `(4*r + b) >= (4*s + 1) <=> (s+1)^2 <= radicand_so_far` algebra.
   * **`stickyOfRemainder`** -- one-bit sticky test; trivial `rfl`.
4. **Per-helper lemma audit.**
   * `clzDenormalMantissa32` -- shared with mul_f32 / div_f32 (if those
     scaffolds land first). Stay `sorry`-shared or close via `bv_decide`.
   * `shift_right_sticky_u64` -- shared between optimised + reference.
     Closes via `Subterms.shr_sticky_eq` (round 1).
   * The 27-iteration `for i in 0..27` Noir loop -- in Lean this becomes
     a `Nat.iterate 27 sqrtStep init` or a `List.range 27 |>.foldl`.
     The Lampe-extraction shape will fix the canonical form.
5. **Tie together** with
   `theorem sqrt_f32_equivalence : sqrtF32Optimised = sqrtF32Reference`
   following the round-9 one-liner: `unfold + rw [sqrt_loop_param_eq,
   rne_param_eq]`.

See `proofs/Ieee754/equivalence-spike-2026-05-04.md` round-9 entries and
`proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/MulF64.lean` for the worked
methodology. The 27-iteration loop's invariant proof is novel for this
scaffold (mul / div / add / sub do not have an iterated step of this
shape) -- expect it to be the heaviest lemma in the closure.
-/

/-- The optimised f32 sqrt is bit-identical to the literal-IEEE-754
reference f32 sqrt, for every input and every rounding mode. **Sorry-stub**
-- proof body to be filled per the methodology comment above. -/
theorem sqrt_f32_equivalence : True := by
  -- TODO: replace with
  --   theorem sqrt_f32_equivalence (a : Float32Bits) (mode : BitVec 8) :
  --       sqrtF32Optimised a mode = sqrtF32Reference a mode := by ...
  -- once `sqrtF32Optimised` and `sqrtF32Reference` exist in
  -- `ZkpSparql.Ieee754.Equivalence.SqrtModelsF32`.
  sorry

end ZkpSparql.Ieee754.Equivalence
