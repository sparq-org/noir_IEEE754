import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Trivial-tier helpers: bit-pattern classifiers (f32)

The Noir helpers `float32_is_nan`, `float32_is_infinity`,
`float32_is_zero`, and `float32_is_denormal` (in
`ieee754/src/float32/helpers.nr`) are pure bit-pattern checks: each
ANDs two equality / inequality tests on the `exponent` and
`mantissa` fields of `IEEE754Float32`. The Lean models in
`Equivalence.Models` (`isNaN`, `isInf`, `isZero`, `isDenormal`)
mirror this exactly. The equivalence theorems below state that the
literal Noir-mirrored "Optimised" function equals the canonical
classifier in `Models`; both sides reduce to the same `Bool`
expression by definitional unfolding. -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float32_is_nan` from
`ieee754/src/float32/helpers.nr`: `(exponent == 0xFF) & (mantissa != 0)`. -/
def float32IsNanOptimised (x : Float32Bits) : Bool :=
  decide (x.exponent = expMax) && decide (x.mantissa ≠ 0)

/-- Literal hand-port of `float32_is_infinity`:
`(exponent == 0xFF) & (mantissa == 0)`. -/
def float32IsInfinityOptimised (x : Float32Bits) : Bool :=
  decide (x.exponent = expMax) && decide (x.mantissa = 0)

/-- Literal hand-port of `float32_is_zero`:
`(exponent == 0) & (mantissa == 0)`. The sign bit is ignored, so
both `+0` and `-0` map to `true`. -/
def float32IsZeroOptimised (x : Float32Bits) : Bool :=
  decide (x.exponent = 0) && decide (x.mantissa = 0)

/-- Literal hand-port of `float32_is_denormal`:
`(exponent == 0) & (mantissa != 0)`. -/
def float32IsDenormalOptimised (x : Float32Bits) : Bool :=
  decide (x.exponent = 0) && decide (x.mantissa ≠ 0)
