import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # Trivial-tier helpers: bits round-trip (f64)

The Noir helpers `float64_from_bits` and `float64_to_bits` (in
`ieee754/src/float64/helpers.nr`) repackage between the raw-`u64`
encoding of an IEEE 754 binary64 and the structured
`IEEE754Float64` triple `(sign, exponent, mantissa)`. The two
operations are inverses on canonical structured values (those
whose mantissa fits in 52 bits).

The Noir bodies hand-port literally to `BitVec` arithmetic:

```noir
pub fn float64_from_bits(bits: u64) -> IEEE754Float64 {
    let sign = ((bits >> 63) & 1) as u1;
    let exponent = ((bits >> 52) & 0x7FF) as u16;
    let mantissa = bits & 0xFFFFFFFFFFFFF;
    IEEE754Float64 { sign, exponent, mantissa }
}

pub fn float64_to_bits(f: IEEE754Float64) -> u64 {
    ((f.sign as u64) << 63) | ((f.exponent as u64) << 52) | f.mantissa
}
```
-/

/-! ## Optimised models: literal hand-ports of the Noir bodies -/

/-- Literal hand-port of `float64_from_bits`. Width casts use
`BitVec.ofNat` to truncate to the target width — exactly what the
Noir `as u1` / `as u16` casts do. -/
def float64FromBitsOptimised (bits : BitVec 64) : Float64Bits :=
  let sign : BitVec 1 := BitVec.ofNat 1 (((bits >>> (63 : Nat)) &&& 1).toNat)
  let exponent : BitVec 16 := BitVec.ofNat 16 (((bits >>> (52 : Nat)) &&& 0x7FF).toNat)
  let mantissa : BitVec 64 := bits &&& 0xFFFFFFFFFFFFF
  { sign := sign, exponent := exponent, mantissa := mantissa }

/-- Literal hand-port of `float64_to_bits`. The `as u64` casts
zero-extend the smaller widths up to `BitVec 64`. -/
def float64ToBitsOptimised (f : Float64Bits) : BitVec 64 :=
  ((f.sign.zeroExtend 64) <<< (63 : Nat))
    ||| ((f.exponent.zeroExtend 64) <<< (52 : Nat))
    ||| f.mantissa

/-! ## Spec forms

Reuse the optimised forms; for trivial-tier the Noir bit-pattern
*is* the canonical spec. -/

/-- Spec for `from_bits`: identical bit-extraction layout. -/
def float64FromBitsSpec (bits : BitVec 64) : Float64Bits :=
  float64FromBitsOptimised bits

/-- Spec for `to_bits`: identical bit-packing layout. -/
def float64ToBitsSpec (f : Float64Bits) : BitVec 64 :=
  float64ToBitsOptimised f

/-! ## Validity predicate for round-trip

A `Float64Bits` is *canonical* when its `mantissa` field uses only
the low 52 bits and its `exponent` field uses only the low 11 bits
— the IEEE 754 binary64 mantissa / biased-exponent widths. The
Lean record is wider than IEEE 754 specifies (`mantissa : BitVec
64`, `exponent : BitVec 16`); without these bounds the
hypothetical high bits would survive `from_bits ∘ to_bits` only if
the `to_bits` shifts truncated them, which they do not. -/

def Float64Bits.IsCanonical (f : Float64Bits) : Prop :=
  f.mantissa.toNat < 0x10000000000000 ∧ f.exponent.toNat < 0x800
