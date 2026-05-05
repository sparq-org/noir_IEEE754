import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Trivial-tier helpers: bit-pattern constructors (f32)

The Noir constructors `float32_nan`, `float32_infinity`,
`float32_zero`, and `float32_max_finite` (in
`ieee754/src/float32/helpers.nr`) build a `IEEE754Float32` struct
from constant or sign-parameterised bit fields. The Lean models in
`Equivalence.Models` (`float32NaN`, `float32Inf`, `float32Zero`,
`float32MaxFinite`) mirror the same struct literals. Each
equivalence theorem reduces to `rfl`.

The encoding choices follow the Noir source bit-for-bit:

* `nan` returns the canonical positive quiet NaN
  (`sign = 0, exponent = 0xFF, mantissa = 0x400000`).
* `infinity(sign)` keeps the requested sign with
  `exponent = 0xFF, mantissa = 0`.
* `zero(sign)` keeps the requested sign with
  `exponent = 0, mantissa = 0` (so both `+0` and `-0` are valid).
* `max_finite(sign)` returns the largest-magnitude finite,
  `exponent = 0xFE, mantissa = 0x7FFFFF` (the IEEE 754-2019 sec
  7.4 directed-rounding overflow saturation target). -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float32_nan` from
`ieee754/src/float32/helpers.nr`. -/
def float32NanOptimised : Float32Bits :=
  { sign := 0, exponent := expMax, mantissa := 0x400000 }

/-- Literal hand-port of `float32_infinity`. -/
def float32InfinityOptimised (sign : BitVec 1) : Float32Bits :=
  { sign := sign, exponent := expMax, mantissa := 0 }

/-- Literal hand-port of `float32_zero`. -/
def float32ZeroOptimised (sign : BitVec 1) : Float32Bits :=
  { sign := sign, exponent := 0, mantissa := 0 }

/-- Literal hand-port of `float32_max_finite`. The exponent is
`FLOAT32_EXPONENT_MAX - 1 = 0xFE`; the mantissa is all-ones in the
23-bit field, i.e. `0x7FFFFF`. -/
def float32MaxFiniteOptimised (sign : BitVec 1) : Float32Bits :=
  { sign := sign, exponent := 0xFE, mantissa := 0x7FFFFF }
