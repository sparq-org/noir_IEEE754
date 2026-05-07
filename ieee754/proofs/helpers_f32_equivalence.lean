/-! # Equivalence theorems: f32 classifiers

For each helper, the optimised hand-port equals the canonical
classifier in `Equivalence.Models`. Both sides are the same `Bool`
expression after unfolding, so `rfl` closes each goal. -/

theorem float32_is_nan_equivalence (x : Float32Bits) :
    float32IsNanOptimised x = isNaN x := rfl

theorem float32_is_infinity_equivalence (x : Float32Bits) :
    float32IsInfinityOptimised x = isInf x := rfl

theorem float32_is_zero_equivalence (x : Float32Bits) :
    float32IsZeroOptimised x = isZero x := rfl

theorem float32_is_denormal_equivalence (x : Float32Bits) :
    float32IsDenormalOptimised x = isDenormal x := rfl

end ZkpSparql.Ieee754.Equivalence
