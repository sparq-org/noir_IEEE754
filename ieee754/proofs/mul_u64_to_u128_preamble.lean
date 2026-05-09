import ZkpSparql.Ieee754.Equivalence.MulModelsF64
import Mathlib.Data.BitVec

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.MulModelsF64

/-! # Tier-6 utility-lemma lift: 64×64 → 128 multiplication

The Noir helper `mul_u64_to_u128` (in `ieee754/src/utils.nr`)
computes the unsigned product of two 64-bit values using the
classic four-32-bit-partial-products method with explicit carry
handling — a workaround for the absence of a single-instruction
64×64 → 128 multiplier in the Noir backend.

The canonical Lean model is `MulModelsF64.mulU64ToU128`, already
in scope, defined directly via `Nat` arithmetic:

```
mulU64ToU128 a b :=
  let p := a.toNat * b.toNat
  { high := BitVec.ofNat 64 (p / 2^64), low := BitVec.ofNat 64 (p % 2^64) }
```

The model is what every f64-mul reference / optimised proof uses
for this site (the round-9 audit observed both paths factor
through the same Noir helper, hence non-divergence inside
`mul_f64`). This file lifts the helper to a top-level equivalence
theorem associated with the public Noir name.

## Proof strategy

The optimised body computes:

```
a_lo := a & 0xFFFFFFFF;         a_hi := a >> 32;
b_lo := b & 0xFFFFFFFF;         b_hi := b >> 32;
p0 := a_lo * b_lo;              p1 := a_lo * b_hi;
p2 := a_hi * b_lo;              p3 := a_hi * b_hi;
mid_sum := p1 + p2;
mid_carry := if mid_sum < p1 then 1 else 0;
mid_lo_shifted := (mid_sum & 0xFFFFFFFF) << 32;
low := p0.wrapping_add(mid_lo_shifted);
low_carry := if low < p0 then 1 else 0;
high := p3 + (mid_sum >> 32) + (mid_carry << 32) + low_carry;
{ high, low }
```

Reconstructing the 128-bit value
`high.toNat * 2^64 + low.toNat = a.toNat * b.toNat` requires:

1. Establishing that each `p_i` equals `a_<half>.toNat * b_<half>.toNat`
   (no overflow because each operand is bounded by `2^32`, so the
   product fits in 64 bits).
2. Showing `mid_sum + mid_carry * 2^64 = p1 + p2` exactly (the
   single-bit carry detection is correct because both operands are
   `BitVec 64`).
3. Showing `low + low_carry * 2^64 = p0 + (mid_sum & lo32) * 2^32`
   using the wrapping-add semantics.
4. Combining (2) and (3) with the algebra
   `a*b = (a_hi*2^32 + a_lo)*(b_hi*2^32 + b_lo)
       = p3*2^64 + (p1+p2)*2^32 + p0`.

The proof reduces to `Nat`-level arithmetic once each step is
discharged — there is no information loss going from `BitVec` to
`Nat` because every intermediate value fits in 64 bits.

`bv_decide` may close the whole thing automatically; if not, the
manual route is:

```
  unfold mulU64ToU128Optimised mulU64ToU128Spec MulModelsF64.mulU64ToU128
  congr 1 <;> · -- high then low
    apply BitVec.toNat_inj
    -- carry-arithmetic chain of `Nat.mul_div_cancel` / `Nat.mod`
```

For now this is a sorry-stub; closing it is mechanical Nat-arithmetic
work but spans a few hundred lines. -/

/-- Literal hand-port of `mul_u64_to_u128` from
`ieee754/src/utils.nr`: 4-partial-product unsigned multiplication
with explicit carry. The `wrapping_add` calls become plain
`BitVec`-level addition (which is wrapping by construction). -/
def mulU64ToU128Optimised (a b : BitVec 64) : U128 :=
  let aLo : BitVec 64 := a &&& 0xFFFFFFFF
  let aHi : BitVec 64 := a >>> 32
  let bLo : BitVec 64 := b &&& 0xFFFFFFFF
  let bHi : BitVec 64 := b >>> 32
  let p0 : BitVec 64 := aLo * bLo
  let p1 : BitVec 64 := aLo * bHi
  let p2 : BitVec 64 := aHi * bLo
  let p3 : BitVec 64 := aHi * bHi
  let midSum : BitVec 64 := p1 + p2
  let midCarry : BitVec 64 := if midSum.toNat < p1.toNat then 1 else 0
  let midLoShifted : BitVec 64 := (midSum &&& 0xFFFFFFFF) <<< 32
  let low : BitVec 64 := p0 + midLoShifted
  let lowCarry : BitVec 64 := if low.toNat < p0.toNat then 1 else 0
  let high : BitVec 64 :=
    p3 + (midSum >>> 32) + (midCarry <<< 32) + lowCarry
  { high := high, low := low }

/-- IEEE 754-2019 sec 5.4.1-friendly literal spec — re-export of
`MulModelsF64.mulU64ToU128`, the `Nat`-level reference. -/
def mulU64ToU128Spec (a b : BitVec 64) : U128 :=
  MulModelsF64.mulU64ToU128 a b
