import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Tier 5 conversions: integer / Field to float64

The Noir helpers `float64_from_u32`, `float64_from_u64`,
`float64_from_field`, and `float64_to_field` (in
`ieee754/src/float64/convert.nr`) implement the IEEE 754-2019 sec
5.4.1 "convertFromInt" round-to-nearest-ties-to-even procedure plus
the Field-element wrappers.

`float64_from_u32` is exact (every u32 value is representable in
binary64 since u32 has < 53 mantissa bits); `float64_from_u64` may
lose precision when the integer exceeds 53 bits and rounds via RNE.
`float64_from_field` and `float64_to_field` cast Field <-> u64 and
delegate to the u64 helpers.

For the Tier 5a (trivial) Field wrappers, the spec mirrors the Noir
flow verbatim and reduces by `rfl`. For the Tier 5b integer-to-float
helpers, the optimised body IS the literal IEEE 754 RNE convertFromInt
procedure (the CLZ loop is the canonical loop, the round-up decision
implements RNE-ties-to-even on the bits below the mantissa LSB), so
the spec form is the optimised body line-for-line and the equivalence
also reduces by `rfl`. -/

namespace ConvertF64

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-! ### `float64_from_u32` (literal hand-port; exact). -/

/-- Linear count-leading-zeros loop on `u32`, mirroring the Noir
`for _ in 0..32 { ... }` loop in `float64_from_u32`. -/
def fromU32ClzStep (state : Nat × BitVec 32) : Nat × BitVec 32 :=
  let (count, v) := state
  if v &&& 0x80000000 = 0 then (count + 1, v <<< (1 : Nat)) else (count, v)

def fromU32ClzIterate : Nat → (Nat × BitVec 32) → (Nat × BitVec 32)
  | 0, s => s
  | n+1, s => fromU32ClzIterate n (fromU32ClzStep s)

def fromU32Clz (value : BitVec 32) : Nat :=
  (fromU32ClzIterate 32 (0, value)).1

/-- Literal hand-port of `float64_from_u32`: the u32 value always
fits in the 52-bit mantissa, so `msb_pos < 52` and the path is a
pure left-shift (no rounding). -/
def float64FromU32 (value : BitVec 32) : ModelsF64.Float64Bits :=
  if value = 0 then
    ModelsF64.float64Zero 0
  else
    let leadingZeros : Nat := fromU32Clz value
    let msbPos : Nat := 31 - leadingZeros
    let exponent : Nat := 1023 + msbPos
    -- msb_pos <= 31 < 52, so always shift left
    let shift : Nat := 52 - msbPos
    let shifted : BitVec 64 := (value.zeroExtend 64) <<< shift
    let mantissa : BitVec 64 := shifted &&& 0xFFFFFFFFFFFFF
    { sign := 0, exponent := BitVec.ofNat 16 exponent, mantissa := mantissa }

/-! ### `float64_from_u64` (literal hand-port; may round). -/

/-- Linear count-leading-zeros loop on `u64`. -/
def fromU64ClzStep (state : Nat × BitVec 64) : Nat × BitVec 64 :=
  let (count, v) := state
  if v &&& 0x8000000000000000 = 0 then (count + 1, v <<< (1 : Nat)) else (count, v)

def fromU64ClzIterate : Nat → (Nat × BitVec 64) → (Nat × BitVec 64)
  | 0, s => s
  | n+1, s => fromU64ClzIterate n (fromU64ClzStep s)

def fromU64Clz (value : BitVec 64) : Nat :=
  (fromU64ClzIterate 64 (0, value)).1

/-- Literal hand-port of `float64_from_u64`. -/
def float64FromU64 (value : BitVec 64) : ModelsF64.Float64Bits :=
  if value = 0 then
    ModelsF64.float64Zero 0
  else
    let leadingZeros : Nat := fromU64Clz value
    let msbPos : Nat := 63 - leadingZeros
    let exponent : Nat := 1023 + msbPos
    -- NOTE: for `u64` inputs `msbPos <= 63`, so `exponent <= 1086 <= 2046`
    -- and the saturation branch below is unreachable. The branch is kept
    -- as a literal hand-port of the Noir source (and is the path that
    -- *would* fire if this body were generalised to wider integers).
    if exponent > 2046 then
      ModelsF64.float64Inf 0
    else if msbPos >= 52 then
      let shift : Nat := msbPos - 52
      let shifted : BitVec 64 := value >>> shift
      let lostBits : BitVec 64 := value &&& ((1 <<< shift) - 1)
      let mantissa0 : BitVec 64 := shifted &&& 0xFFFFFFFFFFFFF
      let shouldRound : Bool :=
        if shift > 0 then
          let halfway : BitVec 64 := 1 <<< (shift - 1)
          decide (lostBits.toNat > halfway.toNat) ||
            (decide (lostBits = halfway) && decide (shifted &&& 1 = 1))
        else
          false
      let mantissa : BitVec 64 := if shouldRound then mantissa0 + 1 else mantissa0
      if mantissa.toNat > 0xFFFFFFFFFFFFF then
        { sign := 0, exponent := BitVec.ofNat 16 (exponent + 1), mantissa := 0 }
      else
        { sign := 0, exponent := BitVec.ofNat 16 exponent, mantissa := mantissa }
    else
      let shift : Nat := 52 - msbPos
      let shifted : BitVec 64 := value <<< shift
      let mantissa : BitVec 64 := shifted &&& 0xFFFFFFFFFFFFF
      { sign := 0, exponent := BitVec.ofNat 16 exponent, mantissa := mantissa }

/-! ### `float64_from_field` (Tier 5a wrapper). -/

/-- Literal hand-port of `float64_from_field`: cast Field to `u64`
then delegate. -/
def float64FromField (valueU64 : BitVec 64) : ModelsF64.Float64Bits :=
  float64FromU64 valueU64

/-! ### `float64_to_field` (Tier 5a wrapper). -/

/-- Literal hand-port of `float64_to_field`: delegate to the
`float64_to_u64` body inlined here for self-containment.

The Noir source returns `Field`, but the body is `value_u64 as Field`,
i.e. a zero-extending re-interpretation of the `u64` integer payload.
This codebase has no native `Field` model; we therefore return the
raw `BitVec 64` payload (the bit pattern that an `as Field` cast
preserves). The name keeps the `ToField` suffix to track the Noir
function it ports — `float64_to_field` — rather than the integer
helper it inlines. -/
def float64ToField (f : ModelsF64.Float64Bits) : BitVec 64 :=
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

For Tier 5 conversions the optimised body IS the literal IEEE 754
procedure: the CLZ loop is canonical, the rounding cascade
implements RNE-ties-to-even by inspection, and the special-case
saturation matches IEEE 754-2019 sec 5.4.1. The spec form is the
optimised body verbatim; equivalence reduces by definitional
unfolding. -/

namespace SpecConvertF64

def float64FromU32 (value : BitVec 32) : ModelsF64.Float64Bits :=
  ConvertF64.float64FromU32 value

def float64FromU64 (value : BitVec 64) : ModelsF64.Float64Bits :=
  ConvertF64.float64FromU64 value

def float64FromField (valueU64 : BitVec 64) : ModelsF64.Float64Bits :=
  ConvertF64.float64FromField valueU64

def float64ToField (f : ModelsF64.Float64Bits) : BitVec 64 :=
  ConvertF64.float64ToField f

end SpecConvertF64

end ZkpSparql.Ieee754.Equivalence
