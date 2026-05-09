import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Trivial-tier helpers: bit-pattern classifiers (f64)

The Noir helpers `float64_is_nan`, `float64_is_infinity`,
`float64_is_zero`, and `float64_is_denormal` (in
`ieee754/src/float64/helpers.nr`) are pure bit-pattern checks on
the `exponent` and `mantissa` fields of `IEEE754Float64`. The Lean
classifiers in `Equivalence.ModelsF64` (`isNaN64`, `isInf64`,
`isZero64`, `isDenormal64`) mirror this exactly. Each equivalence
theorem reduces to `rfl`. -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float64_is_nan` from
`ieee754/src/float64/helpers.nr`: `(exponent == 2047) & (mantissa != 0)`. -/
def float64IsNanOptimised (x : Float64Bits) : Bool :=
  decide (x.exponent = expMax64) && decide (x.mantissa ≠ 0)

/-- Literal hand-port of `float64_is_infinity`:
`(exponent == 2047) & (mantissa == 0)`. -/
def float64IsInfinityOptimised (x : Float64Bits) : Bool :=
  decide (x.exponent = expMax64) && decide (x.mantissa = 0)

/-- Literal hand-port of `float64_is_zero`:
`(exponent == 0) & (mantissa == 0)`. The sign bit is ignored, so
both `+0` and `-0` map to `true`. -/
def float64IsZeroOptimised (x : Float64Bits) : Bool :=
  decide (x.exponent = 0) && decide (x.mantissa = 0)

/-- Literal hand-port of `float64_is_denormal`:
`(exponent == 0) & (mantissa != 0)`. -/
def float64IsDenormalOptimised (x : Float64Bits) : Bool :=
  decide (x.exponent = 0) && decide (x.mantissa ≠ 0)
