/-! # Equivalence theorems: f64 bits round-trip

Mirrors the f32 round-trip story for binary64. The two direct
equivalences reduce to `rfl`; the round-trip identity holds on
canonical values (mantissa < 2^52). -/

/-- `float64_from_bits` equals its spec form. -/
theorem float64_from_bits_equivalence (bits : BitVec 64) :
    float64FromBitsOptimised bits = float64FromBitsSpec bits := rfl

/-- `float64_to_bits` equals its spec form. -/
theorem float64_to_bits_equivalence (f : Float64Bits) :
    float64ToBitsOptimised f = float64ToBitsSpec f := rfl

/-- Round-trip: `from_bits ∘ to_bits = id` on canonical values
(those whose mantissa fits in 52 bits and whose biased exponent
fits in 11 bits). The proof mirrors the f32 closure: convert the
two `Nat`-bounds in the canonicality hypothesis to BitVec
shift-equations (`mantissa >>> 52 = 0` and `exponent >>> 11 = 0`),
fold the `BitVec.ofNat _ x.toNat` width-truncations via
`BitVec.ofNat_toNat`, and discharge the three field-equalities
with `bv_decide`. -/
theorem float64_from_to_bits_roundtrip (f : Float64Bits)
    (h : Float64Bits.IsCanonical f) :
    float64FromBitsOptimised (float64ToBitsOptimised f) = f := by
  obtain ⟨hmant, hexp⟩ := h
  have hmshift : f.mantissa >>> (52 : Nat) = 0#64 := by
    apply BitVec.eq_of_toNat_eq
    rw [BitVec.toNat_ushiftRight]
    simp only [BitVec.toNat_ofNat, Nat.zero_mod, Nat.shiftRight_eq_div_pow]
    exact Nat.div_eq_of_lt (by simpa using hmant)
  have heshift : f.exponent >>> (11 : Nat) = 0#16 := by
    apply BitVec.eq_of_toNat_eq
    rw [BitVec.toNat_ushiftRight]
    simp only [BitVec.toNat_ofNat, Nat.zero_mod, Nat.shiftRight_eq_div_pow]
    exact Nat.div_eq_of_lt (by simpa using hexp)
  rcases f with ⟨sign, exponent, mantissa⟩
  simp only [float64FromBitsOptimised, float64ToBitsOptimised,
    Float64Bits.mk.injEq, BitVec.ofNat_toNat]
  refine ⟨?_, ?_, ?_⟩
  all_goals bv_decide

end ZkpSparql.Ieee754.Equivalence
