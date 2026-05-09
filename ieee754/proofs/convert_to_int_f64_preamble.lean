import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Trivial-tier (Tier 5a): float64-to-integer round-toward-zero

The Noir helpers `float64_to_u32` and `float64_to_u64` (in
`ieee754/src/float64/convert.nr`) implement IEEE 754-2019 sec 5.4.1
"convertToIntegerTowardZero" with the saturation behaviour
documented inline:

* NaN -> 0
* +Inf -> 2^N - 1 (max representable u<N>)
* -Inf -> 0
* negative finite -> 0
* zero / denormal (biased exp = 0) -> 0
* otherwise: unbiased_exp = exponent - 1023; if < 0 the magnitude is
  < 1 so the result is 0; if >= N saturate to 2^N - 1; otherwise
  reconstruct the integer by shifting the implicit-bit-extended
  mantissa.

The literal Lean spec mirrors the Noir body line-by-line; both sides
reduce to the same `BitVec` expression by definitional unfolding. -/

namespace ConvertF64

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float64_to_u32` from
`ieee754/src/float64/convert.nr`. The Noir body always shifts right
in the normal path (exp < 32 < 52), reflected here verbatim. -/
def float64ToU32 (f : ModelsF64.Float64Bits) : BitVec 32 :=
  if ModelsF64.isNaN64 f then
    0
  else if ModelsF64.isInf64 f then
    if f.sign = 1 then 0 else 0xFFFFFFFF
  else if f.sign = 1 then
    0
  else if f.exponent = 0 then
    0
  else
    -- The Noir source casts `f.exponent : u16` to `i16` before
    -- subtracting 1023, mirrored here as a subtraction in the
    -- unbounded `Int`. For f.exponent in 1..=2046 (NaN/Inf/zero
    -- already filtered) the result lies in -1022..=1023, well
    -- inside i16 range, so the Noir cast cannot overflow and the
    -- two models agree.
    let unbiasedExp : Int := (f.exponent.toNat : Int) - 1023
    if unbiasedExp < 0 then
      0
    else if unbiasedExp >= 32 then
      0xFFFFFFFF
    else
      let fullMantissa : BitVec 64 := f.mantissa ||| ModelsF64.implicitBit64
      let exp : Nat := unbiasedExp.toNat
      -- 0 <= exp < 32 < 52: always shift right by (52 - exp).
      (fullMantissa >>> (52 - exp)).setWidth 32

/-- Literal hand-port of `float64_to_u64`. The Noir body's two-arm
shift (exp >= 52 -> shift left by exp - 52; exp < 52 -> shift right
by 52 - exp) is reflected verbatim. -/
def float64ToU64 (f : ModelsF64.Float64Bits) : BitVec 64 :=
  if ModelsF64.isNaN64 f then
    0
  else if ModelsF64.isInf64 f then
    if f.sign = 1 then 0 else 0xFFFFFFFFFFFFFFFF
  else if f.sign = 1 then
    0
  else if f.exponent = 0 then
    0
  else
    let unbiasedExp : Int := (f.exponent.toNat : Int) - 1023
    if unbiasedExp < 0 then
      0
    else if unbiasedExp >= 64 then
      0xFFFFFFFFFFFFFFFF
    else
      let fullMantissa : BitVec 64 := f.mantissa ||| ModelsF64.implicitBit64
      let exp : Nat := unbiasedExp.toNat
      if exp >= 52 then
        fullMantissa <<< (exp - 52)
      else
        fullMantissa >>> (52 - exp)

end ConvertF64

/-! ## Spec forms

For round-toward-zero conversions the optimised body *is* the
literal IEEE 754 spec — the case-structure already reflects sec
5.4.1's "convertToIntegerTowardZero" with saturation. Spec forms
delegate to the optimised case-structure verbatim. -/

namespace SpecConvertF64

/-- Spec for `float64_to_u32`: identical case-structure to the
optimised body. -/
def float64ToU32 (f : ModelsF64.Float64Bits) : BitVec 32 :=
  ConvertF64.float64ToU32 f

/-- Spec for `float64_to_u64`: identical case-structure to the
optimised body. -/
def float64ToU64 (f : ModelsF64.Float64Bits) : BitVec 64 :=
  ConvertF64.float64ToU64 f

end SpecConvertF64

end ZkpSparql.Ieee754.Equivalence
