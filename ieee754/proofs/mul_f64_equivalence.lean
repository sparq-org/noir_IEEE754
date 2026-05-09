/-! # `mul_f64_equivalence` — lampe-literate splice fragment

**This file is an include-only fragment.** It is not a stand-alone
Lean module: it has no `import` block and no `namespace` opener,
and it deliberately closes a namespace (`end ZkpSparql.Ieee754.Equivalence`)
that it does not open in this file. Loading it directly in an editor
or via `lake build` will *not* typecheck.

The fragment is consumed by `lampe-literate build`, which splices
`mul_f64_preamble.lean` (carrying the `import` / `namespace` /
`open` lines) at the top, then this file's body, then writes the
combined module into the scratch tree before invoking `lake build`.
The splice directives live alongside `mul_float64_with_rounding`
in `ieee754/src/float64/mul.nr`:

```
// LAMPE-LITERATE preamble: ../../proofs/mul_f64_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/mul_f64_equivalence.lean fn=mul_float64_with_rounding name=mul_f64_equivalence
```

See `circuits/lampe-literate/README.md` (workspace) for the
directive grammar.

## Diverging-parameter equalities

Round 9 closes the f64 mul equivalence with three diverging
subterms (see `todos/round9-mul-reference-strength.md` in the
workspace):

* the inline-RNE 3-bit wrapper (round-9 baseline),
* the 128-bit sticky right shift (round-9 task iii — closed),
* the denormal-mantissa CLZ (round-9 task iv — partial).

Each is witnessed by a pointwise equality lemma in
`SubtermsMulF64.lean`. -/

/-- The optimised `clzDenormal` parameter
(`clzDenormalMantissa64`, the 6-stage binary search) equals the
reference's (`clzDenormalMantissa64Spec`, the literal-loop scan)
pointwise. Witnessed by the round-9 task-iv closure
`SubtermsMulF64.clzDenormalMantissa64_eq_spec` (partial — see
that lemma's doc-string for the residual). -/
private theorem clz_denormal_param_eq :
    clzDenormalMantissa64 = clzDenormalMantissa64Spec := by
  funext mantRaw
  exact clzDenormalMantissa64_eq_spec mantRaw

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
The proof rewrites the three diverging-subterm parameters of the
shared skeleton and lets `rfl` finish. -/
theorem mul_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    mulF64Optimised a b mode = mulF64Reference a b mode := by
  unfold mulF64Optimised mulF64Reference
  rw [clz_denormal_param_eq, shr_sticky_param_eq, rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
