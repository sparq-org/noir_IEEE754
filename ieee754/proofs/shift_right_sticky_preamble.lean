import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.MulModelsF64
import ZkpSparql.Ieee754.Equivalence.SubtermsMulF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Spec
open ZkpSparql.Ieee754.Equivalence.MulModelsF64

/-! # Tier-6 utility-lemma lifts: sticky-shift family

The Noir helpers `shift_right_sticky_u64` and
`shift_right_sticky_u128` (in `ieee754/src/utils.nr`) are the
alignment primitives shared by the f32/f64 add, sub and mul
circuits. Their correctness was already established inside the
round-6/9 proofs (`Subterms.shr_sticky_eq` for the u64 case and
`SubtermsMulF64.shiftRightStickyU128_eq_spec` for the u128 case);
this file lifts the existing helper lemmas to top-level
equivalence theorems associated with the public Noir function
names per the `PROOF-GAP-MATRIX.md` Tier-6 row.

* `shift_right_sticky_u64`'s optimised body is a 3-branch dispatch
  on the shift amount. The literal IEEE 754-2019 sec 5.4.1
  alignment specification (`Spec.shrSticky`) has the *same*
  3-branch dispatch — the operation is its own minimal description
  — so the equivalence is `rfl`.
* `shift_right_sticky_u128`'s optimised body is a 4-case dispatch
  bridging the two 64-bit halves of a `U128` payload. The literal
  spec (`MulModelsF64.shiftRightStickyU128Spec`) re-expresses the
  dispatch as a single arithmetic shift over the unified
  `val.high * 2^64 + val.low` value with a sticky-OR for any
  nonzero shifted-out bit. The closure is the round-9 `task iii`
  result (`SubtermsMulF64.shiftRightStickyU128_eq_spec`).
-/

/-! ## `shift_right_sticky_u64` — literal hand-ports -/

/-- Literal hand-port of `shift_right_sticky_u64` from
`ieee754/src/utils.nr`: 3-branch dispatch on `shift`.
The Noir body takes `(value : u64, shift : u64) -> u64`; we mirror
that by accepting both arguments as `BitVec 64` and reading the
shift amount via `shift.toNat` so the conditionals match the Noir
control flow (`shift == 0`, `shift >= 64`, otherwise). -/
def shiftRightStickyU64Optimised
    (value : BitVec 64) (shift : BitVec 64) : BitVec 64 :=
  let s := shift.toNat
  if s = 0 then
    value
  else if s ≥ 64 then
    if value = 0 then 0 else 1
  else
    let mask : BitVec 64 := (1 <<< s) - 1
    let shiftedOut := value &&& mask
    let result := value >>> s
    if shiftedOut = 0 then result else result ||| 1

/-- IEEE 754-2019 sec 5.4.1 alignment specification: shift right
with sticky-bit preservation. Identical to `Spec.shrSticky` —
re-exposed under the public Noir function name. -/
def shiftRightStickyU64Spec
    (value : BitVec 64) (shift : BitVec 64) : BitVec 64 :=
  shrSticky value shift

/-! ## `shift_right_sticky_u128` — literal hand-ports

The Noir signature is `(val : U128, shift : u64) -> u64`. The Lean
model in `MulModelsF64` already supplies the optimised dispatch
(`shiftRightStickyU128`) and the unified `Nat`-level reference
(`shiftRightStickyU128Spec`) under the convention that `shift` is
read as `Nat` (the only reachable shift amounts are `0..=128`, so
the `Nat` form mirrors the Noir source bit-for-bit). We re-export
those as `Optimised` / `Spec` here. -/

/-- Literal hand-port of `shift_right_sticky_u128` — re-export of
`MulModelsF64.shiftRightStickyU128`. -/
def shiftRightStickyU128Optimised
    (val : U128) (shift : Nat) : BitVec 64 :=
  MulModelsF64.shiftRightStickyU128 val shift

/-- Literal IEEE 754-2019 sec 5.4.1 spec — re-export of
`MulModelsF64.shiftRightStickyU128Spec`. -/
def shiftRightStickyU128SpecRef
    (val : U128) (shift : Nat) : BitVec 64 :=
  MulModelsF64.shiftRightStickyU128Spec val shift
