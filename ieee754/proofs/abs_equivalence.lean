/-! # Equivalence theorems: f32 + f64 abs

Both sides are the same `Float<W>Bits` struct expression after
unfolding, so `rfl` closes each goal. -/

theorem abs_float32_equivalence (a : Float32Bits) :
    absFloat32Optimised a = absFloat32Spec a := rfl

theorem abs_float64_equivalence (a : Float64Bits) :
    absFloat64Optimised a = absFloat64Spec a := rfl

end ZkpSparql.Ieee754.Equivalence
