/-! # Equivalence theorems: f32 bits round-trip

The optimised bit-extraction / bit-packing equals the canonical
spec by definitional unfolding. The round-trip theorem
`float32_from_bits (float32_to_bits f) = f` requires the canonical
invariant `f.mantissa < 2^23`; under that hypothesis the goal
reduces to a `BitVec`-arithmetic equality discharged by
`bv_decide`. -/

/-- `float32_from_bits` equals its spec form. -/
theorem float32_from_bits_equivalence (bits : BitVec 32) :
    float32FromBitsOptimised bits = float32FromBitsSpec bits := rfl

/-- `float32_to_bits` equals its spec form. -/
theorem float32_to_bits_equivalence (f : Float32Bits) :
    float32ToBitsOptimised f = float32ToBitsSpec f := rfl

/-- Round-trip: `from_bits ∘ to_bits = id` on canonical values
(those whose mantissa fits in 23 bits, which all values produced
by the f32 helpers in this crate satisfy). The proof first turns
the `Nat`-bound canonicality hypothesis into a `BitVec`-arithmetic
equality (`mantissa >>> 23 = 0`) so `bv_decide` can consume it,
then folds the `BitVec.ofNat _ x.toNat` width-truncations into
`BitVec.setWidth` via `BitVec.ofNat_toNat` and discharges the
three field-equalities by `bv_decide`. -/
theorem float32_from_to_bits_roundtrip (f : Float32Bits)
    (h : Float32Bits.IsCanonical f) :
    float32FromBitsOptimised (float32ToBitsOptimised f) = f := by
  -- Convert the `Nat`-bound `mantissa.toNat < 2^23` to the BitVec
  -- equation `mantissa >>> 23 = 0`, which `bv_decide` can use.
  have hshift : f.mantissa >>> (23 : Nat) = 0#32 := by
    have hbound : f.mantissa.toNat < 0x800000 := h
    apply BitVec.eq_of_toNat_eq
    rw [BitVec.toNat_ushiftRight]
    simp only [BitVec.toNat_ofNat, Nat.zero_mod, Nat.shiftRight_eq_div_pow]
    exact Nat.div_eq_of_lt (by simpa using hbound)
  rcases f with ⟨sign, exponent, mantissa⟩
  simp only [float32FromBitsOptimised, float32ToBitsOptimised,
    Float32Bits.mk.injEq, BitVec.ofNat_toNat]
  refine ⟨?_, ?_, ?_⟩
  all_goals bv_decide

end ZkpSparql.Ieee754.Equivalence
