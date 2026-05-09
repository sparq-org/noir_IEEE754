import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Trivial-tier helpers: bits round-trip (f32)

The Noir helpers `float32_from_bits` and `float32_to_bits` (in
`ieee754/src/float32/helpers.nr`) repackage between the raw-`u32`
encoding of an IEEE 754 binary32 and the structured
`IEEE754Float32` triple `(sign, exponent, mantissa)`. The two
operations are inverses on the structured representation: every
triple with a 23-bit mantissa round-trips through both directions
back to itself.

The Noir bodies hand-port literally to `BitVec` arithmetic:

```noir
pub fn float32_from_bits(bits: u32) -> IEEE754Float32 {
    let sign = ((bits >> 31) & 1) as u1;
    let exponent = ((bits >> 23) & 0xFF) as u8;
    let mantissa = bits & 0x7FFFFF;
    IEEE754Float32 { sign, exponent, mantissa }
}

pub fn float32_to_bits(f: IEEE754Float32) -> u32 {
    ((f.sign as u32) << 31) | ((f.exponent as u32) << 23) | f.mantissa
}
```

Width casts (`as u1`, `as u8`, `as u32`) translate to
`BitVec.ofNat` / `BitVec.zeroExtend` over the underlying `Nat`. -/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float32_from_bits`. Width casts use
`BitVec.ofNat` to truncate to the target width — exactly what the
Noir `as u1` / `as u8` casts do. -/
def float32FromBitsOptimised (bits : BitVec 32) : Float32Bits :=
  let sign : BitVec 1 := BitVec.ofNat 1 (((bits >>> (31 : Nat)) &&& 1).toNat)
  let exponent : BitVec 8 := BitVec.ofNat 8 (((bits >>> (23 : Nat)) &&& 0xFF).toNat)
  let mantissa : BitVec 32 := bits &&& 0x7FFFFF
  { sign := sign, exponent := exponent, mantissa := mantissa }

/-- Literal hand-port of `float32_to_bits`. The `as u32` casts
zero-extend the smaller widths up to `BitVec 32`. -/
def float32ToBitsOptimised (f : Float32Bits) : BitVec 32 :=
  ((f.sign.zeroExtend 32) <<< (31 : Nat))
    ||| ((f.exponent.zeroExtend 32) <<< (23 : Nat))
    ||| f.mantissa

/-! ## Spec forms

Reuse the optimised forms; for trivial-tier the Noir bit-pattern
*is* the canonical spec. -/

/-- Spec for `from_bits`: identical bit-extraction layout. -/
def float32FromBitsSpec (bits : BitVec 32) : Float32Bits :=
  float32FromBitsOptimised bits

/-- Spec for `to_bits`: identical bit-packing layout. -/
def float32ToBitsSpec (f : Float32Bits) : BitVec 32 :=
  float32ToBitsOptimised f

/-! ## Validity predicate for round-trip

A `Float32Bits` is *canonical* when its `mantissa` field uses only
the low 23 bits — the IEEE 754 binary32 mantissa width. Values
constructed via `from_bits` always satisfy this; values produced
by the Noir helpers (`zero`, `inf`, `nan`, `max_finite`, every
arithmetic operator) likewise stay canonical. The round-trip
identity holds exactly on canonical values. -/

def Float32Bits.IsCanonical (f : Float32Bits) : Prop :=
  f.mantissa.toNat < 0x800000
