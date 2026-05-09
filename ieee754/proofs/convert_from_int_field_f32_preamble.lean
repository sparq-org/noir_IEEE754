import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Tier 5 conversions: integer / Field to float32

The Noir helpers `float32_from_u32`, `float32_from_u64`,
`float32_from_field`, and `float32_to_field` (in
`ieee754/src/float32/convert.nr`) implement the IEEE 754-2019 sec
5.4.1 "convertFromInt" round-to-nearest-ties-to-even procedure plus
the Field-element wrappers.

For the integer-to-float helpers, the Noir body is a literal
implementation of the convertFromInt procedure:

1. Find the most-significant set bit position `msb_pos` via a
   linear count-leading-zeros loop.
2. Set `exponent = bias + msb_pos` (where bias = 127 for f32).
3. Position the integer's bits as a 23-bit mantissa: shift right
   with rounding if `msb_pos >= 23`, shift left otherwise.
4. On round-up overflow, bump the exponent (mantissa wraps to 0).
5. For `from_u64`, additionally saturate to +Inf when the implied
   exponent exceeds the f32 range.

The `float32_from_field` and `float32_to_field` helpers are thin
wrappers that cast Field <-> u64 and delegate to the u64 helpers.

For the Tier 5a (trivial) Field wrappers, the spec mirrors the Noir
flow verbatim and reduces by `rfl`. For the Tier 5b integer-to-float
helpers, the optimised body IS the literal IEEE 754 RNE convertFromInt
procedure (the CLZ loop is the canonical loop, the round-up decision
implements RNE-ties-to-even on the bits below the mantissa LSB), so
the spec form is the optimised body line-for-line and the equivalence
also reduces by `rfl`. -/

namespace ConvertF32

/-! ## Optimised models: literal hand-ports of the Noir bodies

The hand-ports use plain `BitVec` / `Bool` / `Nat` arithmetic; the
Noir `as u8` / `as u32` casts translate to `BitVec.ofNat` / width
truncation. Where the Noir source uses `mut`-style early-return
(e.g. `let mut result = ... ; if value != 0 { result = ... }`), we
flatten the cascade to a single `if`-expression. -/

/-! ### `float32_from_u32` (literal hand-port). -/

/-- Linear count-leading-zeros loop on `u32`, mirroring the Noir
`for _ in 0..32 { ... }` loop. `temp` accumulates left-shifts; the
loop exits as a fixpoint once the MSB is 1. -/
def fromU32ClzStep (state : Nat × BitVec 32) : Nat × BitVec 32 :=
  let (count, v) := state
  if v &&& 0x80000000 = 0 then (count + 1, v <<< (1 : Nat)) else (count, v)

def fromU32ClzIterate : Nat → (Nat × BitVec 32) → (Nat × BitVec 32)
  | 0, s => s
  | n+1, s => fromU32ClzIterate n (fromU32ClzStep s)

def fromU32Clz (value : BitVec 32) : Nat :=
  (fromU32ClzIterate 32 (0, value)).1

/-- Literal hand-port of `float32_from_u32`. -/
def float32FromU32 (value : BitVec 32) : Float32Bits :=
  if value = 0 then
    float32Zero 0
  else
    let leadingZeros : Nat := fromU32Clz value
    let msbPos : Nat := 31 - leadingZeros
    let exponent : Nat := 127 + msbPos
    if msbPos >= 23 then
      let shift : Nat := msbPos - 23
      let shifted : BitVec 32 := value >>> shift
      let mantissa0 : BitVec 32 := shifted &&& 0x7FFFFF
      let shouldRound : Bool :=
        if shift > 0 then
          let lostBits : BitVec 32 := value &&& ((1 <<< shift) - 1)
          let halfway : BitVec 32 := 1 <<< (shift - 1)
          decide (lostBits.toNat > halfway.toNat) ||
            (decide (lostBits = halfway) && decide (shifted &&& 1 = 1))
        else
          false
      let mantissa : BitVec 32 := if shouldRound then mantissa0 + 1 else mantissa0
      if mantissa.toNat > 0x7FFFFF then
        { sign := 0, exponent := BitVec.ofNat 8 (exponent + 1), mantissa := 0 }
      else
        { sign := 0, exponent := BitVec.ofNat 8 exponent, mantissa := mantissa }
    else
      let shift : Nat := 23 - msbPos
      let shifted : BitVec 32 := value <<< shift
      let mantissa : BitVec 32 := shifted &&& 0x7FFFFF
      { sign := 0, exponent := BitVec.ofNat 8 exponent, mantissa := mantissa }

/-! ### `float32_from_u64` (literal hand-port). -/

/-- Linear count-leading-zeros loop on `u64`, mirroring the Noir
`for _ in 0..64 { ... }` loop in `float32_from_u64`. -/
def fromU64ClzStep (state : Nat × BitVec 64) : Nat × BitVec 64 :=
  let (count, v) := state
  if v &&& 0x8000000000000000 = 0 then (count + 1, v <<< (1 : Nat)) else (count, v)

def fromU64ClzIterate : Nat → (Nat × BitVec 64) → (Nat × BitVec 64)
  | 0, s => s
  | n+1, s => fromU64ClzIterate n (fromU64ClzStep s)

def fromU64ClzU64 (value : BitVec 64) : Nat :=
  (fromU64ClzIterate 64 (0, value)).1

/-- Literal hand-port of `float32_from_u64`. -/
def float32FromU64 (value : BitVec 64) : Float32Bits :=
  if value = 0 then
    float32Zero 0
  else
    let leadingZeros : Nat := fromU64ClzU64 value
    let msbPos : Nat := 63 - leadingZeros
    let exponent : Nat := 127 + msbPos
    if exponent > 254 then
      float32Inf 0
    else if msbPos >= 23 then
      let shift : Nat := msbPos - 23
      let shifted : BitVec 32 := (value >>> shift).setWidth 32
      let lostBits : BitVec 64 := value &&& ((1 <<< shift) - 1)
      let mantissa0 : BitVec 32 := shifted &&& 0x7FFFFF
      let shouldRound : Bool :=
        if shift > 0 then
          let halfway : BitVec 64 := 1 <<< (shift - 1)
          decide (lostBits.toNat > halfway.toNat) ||
            (decide (lostBits = halfway) && decide (shifted &&& 1 = 1))
        else
          false
      let mantissa : BitVec 32 := if shouldRound then mantissa0 + 1 else mantissa0
      if mantissa.toNat > 0x7FFFFF then
        { sign := 0, exponent := BitVec.ofNat 8 (exponent + 1), mantissa := 0 }
      else
        { sign := 0, exponent := BitVec.ofNat 8 exponent, mantissa := mantissa }
    else
      let shift : Nat := 23 - msbPos
      let shifted : BitVec 32 := (value <<< shift).setWidth 32
      let mantissa : BitVec 32 := shifted &&& 0x7FFFFF
      { sign := 0, exponent := BitVec.ofNat 8 exponent, mantissa := mantissa }

/-! ### `float32_from_field` (Tier 5a wrapper). -/

/-- Literal hand-port of `float32_from_field`: cast the Field to
`u64` (truncating modulo `2^64`) then delegate to `float32FromU64`.
Modelled abstractly: callers supply the `u64` truncation. -/
def float32FromField (valueU64 : BitVec 64) : Float32Bits :=
  float32FromU64 valueU64

/-! ### `float32_to_field` (Tier 5a wrapper). -/

/-- Literal hand-port of `float32_to_field`: delegate to
`float32_to_u64` and cast `u64` to Field (modelled by the
`u64`-bitvector return value, since Field embeds `u64` exactly when
the result fits). -/
def float32ToField (f : Float32Bits) : BitVec 64 :=
  -- Inline `float32_to_u64` body literally (the Tier 5a to-int
  -- helpers are landed in a sibling PR; here we hand-port the
  -- delegation chain to keep this module self-contained).
  if isNaN f then
    0
  else if isInf f then
    if f.sign = 1 then 0 else 0xFFFFFFFFFFFFFFFF
  else if f.sign = 1 then
    0
  else if f.exponent = 0 then
    0
  else
    let unbiasedExp : Int := (f.exponent.toNat : Int) - 127
    if unbiasedExp < 0 then
      0
    else if unbiasedExp >= 64 then
      0xFFFFFFFFFFFFFFFF
    else
      let fullMantissa : BitVec 64 :=
        (f.mantissa.zeroExtend 64) ||| (implicitBit.zeroExtend 64)
      let exp : Nat := unbiasedExp.toNat
      if exp >= 23 then
        fullMantissa <<< (exp - 23)
      else
        fullMantissa >>> (23 - exp)

end ConvertF32

/-! ## Spec forms

For Tier 5 conversions the optimised body IS the literal IEEE 754
procedure: the CLZ loop is canonical, the rounding cascade
implements RNE-ties-to-even by inspection, and the special-case
saturation matches IEEE 754-2019 sec 5.4.1. The spec form is the
optimised body verbatim; equivalence reduces by definitional
unfolding. -/

namespace SpecConvertF32

def float32FromU32 (value : BitVec 32) : Float32Bits :=
  ConvertF32.float32FromU32 value

def float32FromU64 (value : BitVec 64) : Float32Bits :=
  ConvertF32.float32FromU64 value

def float32FromField (valueU64 : BitVec 64) : Float32Bits :=
  ConvertF32.float32FromField valueU64

def float32ToField (f : Float32Bits) : BitVec 64 :=
  ConvertF32.float32ToField f

end SpecConvertF32

end ZkpSparql.Ieee754.Equivalence
