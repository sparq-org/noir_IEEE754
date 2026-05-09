/-! ## Round-7b dependency: `add_f64_equivalence`

The round-8 `sub_f64_equivalence` reduces mechanically to round-7b's
`add_f64_equivalence` applied to `(a, negateF64 b, mode)` (IEEE
754-2019 §6.3). The round-7b closure body is inlined here so this
splice (`circuits/noir_IEEE754/ieee754/src/float64/mod.nr`) is
self-contained and does not have to reach into the splice tree
generated for `add.nr`. The two splices live in separate scratch
trees, so the duplication never produces a name collision at
build time. -/

private theorem clz_param_eq :
    Subterms.clzBinary = Subterms.clzLoop := by
  funext v; exact (Subterms.clz_eq v).symm

private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 0x80) ||
          (decide (gb = 0x80) && decide (rm &&& 1 = 1))
      else
        shouldRoundUp8Bit gb rm rs m) = shouldRoundUp8Bit := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp8Bit_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

theorem add_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    addF64Optimised a b mode = addF64Reference a b mode := by
  unfold addF64Optimised addF64Reference
  rw [clz_param_eq, rne_param_eq]

/-! ## Round-8: sub equivalence

IEEE 754-2019 §6.3 mandates `subtract(a, b) = add(a, negate(b))`.
Both the optimised circuit and the reference take that definition
literally, so the equivalence reduces to `add_f64_equivalence`. -/

/-- Flip the sign bit of a `Float64Bits`. Mirrors the Noir
construction `IEEE754Float64 { sign = 1 - b.sign, exponent =
b.exponent, mantissa = b.mantissa }` from
`ieee754::float64::sub_float64_with_rounding`. -/
def negateF64 (b : Float64Bits) : Float64Bits :=
  { sign := 1 - b.sign, exponent := b.exponent, mantissa := b.mantissa }

/-- Line-by-line transcription of `sub_float64_with_rounding`. -/
def subF64Optimised (a b : Float64Bits) (mode : BitVec 8) : Float64Bits :=
  addF64Optimised a (negateF64 b) mode

/-- Reference: subtraction = `add(a, negate(b))`. -/
def subF64Reference (a b : Float64Bits) (mode : BitVec 8) : Float64Bits :=
  addF64Reference a (negateF64 b) mode

/-- The optimised f64 sub is bit-identical to the literal-IEEE-754
reference f64 sub, for every input and every rounding mode. -/
theorem sub_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    subF64Optimised a b mode = subF64Reference a b mode := by
  unfold subF64Optimised subF64Reference
  exact add_f64_equivalence a (negateF64 b) mode

end ZkpSparql.Ieee754.Equivalence
