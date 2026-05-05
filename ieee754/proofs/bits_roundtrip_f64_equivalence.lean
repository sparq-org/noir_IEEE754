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
(those whose mantissa fits in 52 bits). -/
theorem float64_from_to_bits_roundtrip (f : Float64Bits)
    (h : Float64Bits.IsCanonical f) :
    float64FromBitsOptimised (float64ToBitsOptimised f) = f := by
  -- TODO(wave-13 follow-up): three field-equalities under a
  -- mantissa-bounds hypothesis; mechanical for `bv_decide` once
  -- the cross-width cast lemmas are in place. Same shape as the
  -- f32 stub.
  sorry

end ZkpSparql.Ieee754.Equivalence
