import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Trivial-tier (Tier 5a): float32-to-integer round-toward-zero

The Noir helpers `float32_to_u32` and `float32_to_u64` (in
`ieee754/src/float32/convert.nr`) implement IEEE 754-2019 sec 5.4.1
"convertToIntegerTowardZero" with the saturation behaviour
documented inline:

* NaN -> 0
* +Inf -> 2^N - 1 (max representable u<N>)
* -Inf -> 0
* negative finite -> 0 (round-toward-zero of a negative non-integer
  in [-1, 0) is 0; everything more negative is < representable)
* zero / denormal (biased exp = 0) -> 0
* otherwise: unbiased_exp = exponent - 127; if < 0 the magnitude is
  < 1 so the result is 0; if >= N the magnitude exceeds the integer
  range so we saturate to 2^N - 1; otherwise reconstruct the
  integer by shifting the implicit-bit-extended mantissa.

The literal Lean spec mirrors the Noir body line-by-line; both sides
reduce to the same `BitVec` expression by definitional unfolding. -/

namespace ConvertF32

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float32_to_u32` from
`ieee754/src/float32/convert.nr`. The four guarded special-case
branches (NaN, infinity, negative, zero/denormal) are translated
verbatim; the normal-path computes `unbiased_exp` and shifts the
implicit-bit-OR'd mantissa left or right.

The Noir source casts `f.exponent` (a `u8`) to `i16` before
subtracting the bias of 127. We model this with `Int`, which is
a strict superset of `i16` for the value range that reaches this
branch: NaN / Inf / zero / denormal are already filtered out, so
`f.exponent` is in `1..=254` and `(f.exponent : Int) - 127` is in
`-126..=127`. The value therefore never exceeds the `i16` range
(±32 767), so the wider Lean `Int` agrees with the Noir `i16` on
every reachable input — matching the Noir semantics without
needing a bit-precise `i16` model in Lean. -/
def float32ToU32 (f : Models.Float32Bits) : BitVec 32 :=
  if Models.isNaN f then
    0
  else if Models.isInf f then
    if f.sign = 1 then 0 else 0xFFFFFFFF
  else if f.sign = 1 then
    0
  else if f.exponent = 0 then
    0
  else
    -- unbiased_exp = (exponent : i16) - 127; modelled with `Int`.
    -- See the docstring above for the reachable-range argument
    -- justifying the `Int` model.
    let unbiasedExp : Int := (f.exponent.toNat : Int) - 127
    if unbiasedExp < 0 then
      0
    else if unbiasedExp >= 32 then
      0xFFFFFFFF
    else
      -- Mirror the u64 form: explicitly `zeroExtend` both operands
      -- to the target width before combining. `Models.Float32Bits.mantissa`
      -- and `Models.implicitBit` are already `BitVec 32` (so the
      -- extension is the identity), but writing it this way keeps
      -- the two definitions structurally consistent and robust to
      -- future changes in the field widths of `Models.Float32Bits`.
      let fullMantissa : BitVec 32 :=
        (f.mantissa.zeroExtend 32) ||| (Models.implicitBit.zeroExtend 32)
      let exp : Nat := unbiasedExp.toNat
      if exp >= 23 then
        fullMantissa <<< (exp - 23)
      else
        fullMantissa >>> (23 - exp)

/-- Literal hand-port of `float32_to_u64`. Same case-structure as
`float32_to_u32` widened to 64 bits; the saturation cap is
`0xFFFFFFFFFFFFFFFF` and the overflow threshold is `unbiased_exp >=
64`. The `unbiased_exp` modelling argument from `float32ToU32`
(Noir `i16` ↦ Lean `Int`, exact on every reachable input) carries
over verbatim. -/
def float32ToU64 (f : Models.Float32Bits) : BitVec 64 :=
  if Models.isNaN f then
    0
  else if Models.isInf f then
    if f.sign = 1 then 0 else 0xFFFFFFFFFFFFFFFF
  else if f.sign = 1 then
    0
  else if f.exponent = 0 then
    0
  else
    -- unbiased_exp = (exponent : i16) - 127; see `float32ToU32`.
    let unbiasedExp : Int := (f.exponent.toNat : Int) - 127
    if unbiasedExp < 0 then
      0
    else if unbiasedExp >= 64 then
      0xFFFFFFFFFFFFFFFF
    else
      let fullMantissa : BitVec 64 :=
        (f.mantissa.zeroExtend 64) ||| (Models.implicitBit.zeroExtend 64)
      let exp : Nat := unbiasedExp.toNat
      if exp >= 23 then
        fullMantissa <<< (exp - 23)
      else
        fullMantissa >>> (23 - exp)

end ConvertF32

/-! ## Spec forms

For round-toward-zero conversions the optimised body *is* the
literal IEEE 754 spec — the case-structure already reflects sec
5.4.1's "convertToIntegerTowardZero" with saturation. Spec forms
delegate to the optimised case-structure verbatim. -/

namespace SpecConvertF32

/-- Spec for `float32_to_u32`: identical case-structure to the
optimised body. -/
def float32ToU32 (f : Models.Float32Bits) : BitVec 32 :=
  ConvertF32.float32ToU32 f

/-- Spec for `float32_to_u64`: identical case-structure to the
optimised body. -/
def float32ToU64 (f : Models.Float32Bits) : BitVec 64 :=
  ConvertF32.float32ToU64 f

end SpecConvertF32

end ZkpSparql.Ieee754.Equivalence
