/-! ## Round-6 dependency: `add_f32_equivalence`

The round-7 `sub_f32_equivalence` reduces mechanically to round-6's
`add_f32_equivalence` applied to `(a, negateF32 b, mode)` (IEEE
754-2019 §6.3). The round-6 closure body is inlined here so this
splice (`circuits/noir_IEEE754/ieee754/src/float32/mod.nr`) is
self-contained and does not have to reach into the splice tree
generated for `add.nr`. The two splices live in separate scratch
trees, so the duplication never produces a name collision at
build time. -/

/-- The optimised path's inlined round-to-nearest-even computation
is the body of `shouldRoundUp` for `mode = 0`. -/
theorem shouldRoundUp_inline_eq
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) :
    shouldRoundUp guardBits resultMant resultSign 0
      = (decide (guardBits.toNat > 4)
          || (decide (guardBits = 4) && decide (resultMant &&& 1 = 1))) := by
  unfold shouldRoundUp
  simp [modeNearestEven]

private theorem clz_param_eq : clzBinary = clzLoop := by
  funext v; exact (clz_eq v).symm

private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 4) ||
          (decide (gb = 4) && decide (rm &&& 1 = 1))
      else
        shouldRoundUp gb rm rs m) = shouldRoundUp := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

private theorem align_eq (a b : Float32Bits) :
    alignF32Optimised a b = alignF32Reference a b := by
  unfold alignF32Optimised alignF32Reference
  set expA : BitVec 64 := effectiveExp a with hExpA
  set expB : BitVec 64 := effectiveExp b with hExpB
  rcases lt_trichotomy expA.toNat expB.toNat with hlt | heq | hgt
  · have hngeA : ¬ expA.toNat ≥ expB.toNat := by omega
    have hngtA : ¬ expA.toNat > expB.toNat := by omega
    have hgtB : expB.toNat > expA.toNat := hlt
    have hshift_ne : (expB - expA).toNat ≠ 0 := by
      rw [BitVec.toNat_sub]
      have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
      have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
      omega
    simp only [Id.run, hngeA, hngtA, hgtB, if_true, if_false,
               ge_iff_le, Nat.not_le_of_lt, shr_sticky_eq _ _ hshift_ne]
    rfl
  · have hsub : expA - expB = 0 := by
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toNat_sub, heq]
      have hbound : expB.toNat ≤ 18446744073709551616 :=
        Nat.le_of_lt (BitVec.isLt _)
      change _ = (0 : BitVec 64).toNat
      simp; omega
    have hsub' : expB - expA = 0 := by
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toNat_sub, ← heq]
      have hbound : expA.toNat ≤ 18446744073709551616 :=
        Nat.le_of_lt (BitVec.isLt _)
      change _ = (0 : BitVec 64).toNat
      simp; omega
    have hge : expA.toNat ≥ expB.toNat := Nat.le_of_eq heq.symm
    have hngtA : ¬ expA.toNat > expB.toNat := by omega
    have hngtB : ¬ expB.toNat > expA.toNat := by omega
    have hexp_eq : expA = expB := by
      apply BitVec.eq_of_toNat_eq; exact heq
    simp only [Id.run, hngtA, hngtB, hge, ge_iff_le, hsub, hsub',
               shrStickyHelper_zero, if_true, if_false]
    rfl
  · have hge : expA.toNat ≥ expB.toNat := Nat.le_of_lt hgt
    have hngtB : ¬ expB.toNat > expA.toNat := by omega
    have hshift_ne : (expA - expB).toNat ≠ 0 := by
      rw [BitVec.toNat_sub]
      have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
      have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
      omega
    simp only [Id.run, hgt, hngtB, hge, ge_iff_le, if_true, if_false,
               shr_sticky_eq _ _ hshift_ne]
    rfl

theorem add_f32_equivalence
    (a b : Float32Bits) (mode : BitVec 8) :
    addF32Optimised a b mode = addF32Reference a b mode := by
  unfold addF32Optimised addF32Reference
  rw [align_eq a b, clz_param_eq, rne_param_eq]

/-! ## Round-7a: sub equivalence

IEEE 754-2019 §6.3 mandates `subtract(a, b) = add(a, negate(b))`.
Both the optimised circuit and the reference take that definition
literally, so the equivalence reduces to `add_f32_equivalence`. -/

/-- Flip the sign bit of a `Float32Bits`. Mirrors the Noir
construction `IEEE754Float32 { sign = 1 - b.sign, exponent =
b.exponent, mantissa = b.mantissa }` from
`ieee754::float32::sub_float32_with_rounding`. -/
def negateF32 (b : Float32Bits) : Float32Bits :=
  { sign := 1 - b.sign, exponent := b.exponent, mantissa := b.mantissa }

/-- Line-by-line transcription of `sub_float32_with_rounding`. -/
def subF32Optimised (a b : Float32Bits) (mode : BitVec 8) : Float32Bits :=
  addF32Optimised a (negateF32 b) mode

/-- Reference: subtraction = `add(a, negate(b))`. -/
def subF32Reference (a b : Float32Bits) (mode : BitVec 8) : Float32Bits :=
  addF32Reference a (negateF32 b) mode

/-- The optimised f32 sub is bit-identical to the literal-IEEE-754
reference f32 sub, for every input and every rounding mode. -/
theorem sub_f32_equivalence
    (a b : Float32Bits) (mode : BitVec 8) :
    subF32Optimised a b mode = subF32Reference a b mode := by
  unfold subF32Optimised subF32Reference
  exact add_f32_equivalence a (negateF32 b) mode

end ZkpSparql.Ieee754.Equivalence
