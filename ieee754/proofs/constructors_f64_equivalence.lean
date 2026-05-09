/-! # Equivalence theorems: f64 constructors

Each optimised hand-port equals the canonical constructor in
`Equivalence.ModelsF64`. Both sides are the same `Float64Bits`
struct literal after definitional unfolding, so `rfl` closes each
goal. -/

theorem float64_nan_equivalence :
    float64NanOptimised = float64NaN := rfl

theorem float64_infinity_equivalence (sign : BitVec 1) :
    float64InfinityOptimised sign = float64Inf sign := rfl

theorem float64_zero_equivalence (sign : BitVec 1) :
    float64ZeroOptimised sign = float64Zero sign := rfl

theorem float64_max_finite_equivalence (sign : BitVec 1) :
    float64MaxFiniteOptimised sign = float64MaxFinite sign := rfl

end ZkpSparql.Ieee754.Equivalence
