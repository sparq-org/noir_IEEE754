import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Trivial-tier helpers: absolute value (f32 + f64)

The Noir helpers `abs_float32` and `abs_float64` (in
`ieee754/src/float{32,64}/mod.nr`) clear the sign bit by
constructing a fresh struct with `sign := 0` and the original
`exponent` / `mantissa`. The IEEE 754-2019 sec 5.5.1 abs operation
is exactly this: a sign-bit clear, applied uniformly to all
encodings (so `abs(-NaN)` is `+NaN`, `abs(-0)` is `+0`, etc.).
Each equivalence theorem reduces to `rfl`. -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `abs_float32`. -/
def absFloat32Optimised (a : Float32Bits) : Float32Bits :=
  { sign := 0, exponent := a.exponent, mantissa := a.mantissa }

/-- Literal hand-port of `abs_float64`. -/
def absFloat64Optimised (a : Float64Bits) : Float64Bits :=
  { sign := 0, exponent := a.exponent, mantissa := a.mantissa }

/-! ## Spec forms — sign-bit clear

The IEEE 754-2019 sec 5.5.1 spec is "set the sign bit to zero".
Both spec and optimised forms are the same struct expression. -/

def absFloat32Spec (a : Float32Bits) : Float32Bits :=
  { sign := 0, exponent := a.exponent, mantissa := a.mantissa }

def absFloat64Spec (a : Float64Bits) : Float64Bits :=
  { sign := 0, exponent := a.exponent, mantissa := a.mantissa }
