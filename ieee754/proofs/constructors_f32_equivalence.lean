/-! # Equivalence theorems: f32 constructors

Each optimised hand-port equals the canonical constructor in
`Equivalence.Models`. Both sides are the same `Float32Bits` struct
literal after definitional unfolding, so `rfl` closes each goal. -/

theorem float32_nan_equivalence :
    float32NanOptimised = float32NaN := rfl

theorem float32_infinity_equivalence (sign : BitVec 1) :
    float32InfinityOptimised sign = float32Inf sign := rfl

theorem float32_zero_equivalence (sign : BitVec 1) :
    float32ZeroOptimised sign = float32Zero sign := rfl

theorem float32_max_finite_equivalence (sign : BitVec 1) :
    float32MaxFiniteOptimised sign = float32MaxFinite sign := rfl

end ZkpSparql.Ieee754.Equivalence
