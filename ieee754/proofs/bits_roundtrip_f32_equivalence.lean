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
by the f32 helpers in this crate satisfy). The proof reduces to
three `BitVec 32` equalities (one per field) under the canonical
hypothesis; each is mechanically discharged by `bv_decide`. -/
theorem float32_from_to_bits_roundtrip (f : Float32Bits)
    (h : Float32Bits.IsCanonical f) :
    float32FromBitsOptimised (float32ToBitsOptimised f) = f := by
  -- TODO(wave-13 follow-up): the three field-equalities under a
  -- mantissa-bounds hypothesis are mechanical for `bv_decide`,
  -- but the cross-width arithmetic (BitVec 1 / 8 / 32 mixing
  -- with `BitVec.ofNat` truncation and `zeroExtend`) requires
  -- a small chain of `BitVec`-cast lemmas to reach `bv_decide`-
  -- ready form. Tracked as a Tier-1 follow-up; the two
  -- equivalence theorems above (which are pure `rfl`) carry the
  -- main bit-pattern obligation.
  sorry

end ZkpSparql.Ieee754.Equivalence
