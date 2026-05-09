/-! # Equivalence theorems: f64 classifiers

For each helper, the optimised hand-port equals the canonical
classifier in `Equivalence.ModelsF64`. Both sides are the same
`Bool` expression after unfolding, so `rfl` closes each goal. -/

theorem float64_is_nan_equivalence (x : Float64Bits) :
    float64IsNanOptimised x = isNaN64 x := rfl

theorem float64_is_infinity_equivalence (x : Float64Bits) :
    float64IsInfinityOptimised x = isInf64 x := rfl

theorem float64_is_zero_equivalence (x : Float64Bits) :
    float64IsZeroOptimised x = isZero64 x := rfl

theorem float64_is_denormal_equivalence (x : Float64Bits) :
    float64IsDenormalOptimised x = isDenormal64 x := rfl

end ZkpSparql.Ieee754.Equivalence
