import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Trivial-tier helpers: bit-pattern constructors (f64)

The Noir constructors `float64_nan`, `float64_infinity`,
`float64_zero`, and `float64_max_finite` (in
`ieee754/src/float64/helpers.nr`) build a `IEEE754Float64` struct
from constant or sign-parameterised bit fields. The Lean models in
`Equivalence.ModelsF64` (`float64NaN`, `float64Inf`, `float64Zero`,
`float64MaxFinite`) mirror the same struct literals. Each
equivalence theorem reduces to `rfl`.

Encoding choices follow the Noir source bit-for-bit:

* `nan` returns the canonical positive quiet NaN
  (`sign = 0, exponent = 2047, mantissa = 0x8000000000000`).
* `infinity(sign)` keeps the requested sign with
  `exponent = 2047, mantissa = 0`.
* `zero(sign)` keeps the requested sign with
  `exponent = 0, mantissa = 0`.
* `max_finite(sign)` returns the largest-magnitude finite,
  `exponent = 0x7FE, mantissa = 0xFFFFFFFFFFFFF` (the IEEE 754-2019
  sec 7.4 directed-rounding overflow saturation target). -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float64_nan`. -/
def float64NanOptimised : Float64Bits :=
  { sign := 0, exponent := expMax64, mantissa := 0x8000000000000 }

/-- Literal hand-port of `float64_infinity`. -/
def float64InfinityOptimised (sign : BitVec 1) : Float64Bits :=
  { sign := sign, exponent := expMax64, mantissa := 0 }

/-- Literal hand-port of `float64_zero`. -/
def float64ZeroOptimised (sign : BitVec 1) : Float64Bits :=
  { sign := sign, exponent := 0, mantissa := 0 }

/-- Literal hand-port of `float64_max_finite`. The exponent is
`FLOAT64_EXPONENT_MAX - 1 = 0x7FE`; the mantissa is all-ones in the
52-bit field, i.e. `0xFFFFFFFFFFFFF`. -/
def float64MaxFiniteOptimised (sign : BitVec 1) : Float64Bits :=
  { sign := sign, exponent := 0x7FE, mantissa := 0xFFFFFFFFFFFFF }
