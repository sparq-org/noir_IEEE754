import Mathlib.Data.BitVec
import Mathlib.Tactic
import ZkpSparql.Ieee754.Equivalence.Models

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # IEEE 754 binary32 comparison spec + Lean models

The optimised binary32 comparison ops live in
`circuits/noir_IEEE754/ieee754/src/float32/cmp.nr`. This module
captures their semantics two ways:

* the **natural spec** — direct case analysis on the IEEE 754
  ordering rules (NaN unordered, +0 = -0, lexicographic on (sign,
  magnitude) with sign-flip for negatives);
* the **Noir model** — a Lean function that computes the same
  value as the Noir source. The Noir source uses an `Id.run`-style
  `mut` cascade (early-set to a default, then conditionally
  overwrite). The Lean model below collapses that cascade into a
  direct `if`-expression — semantically identical, syntactically
  shorter.

The eight equivalence theorems in `cmp_f32_<op>_equivalence.lean`
show each Noir model equals its spec.

The bit-level representation reuses `Models.Float32Bits` (mirrors
`IEEE754Float32` in `ieee754::types`) and the classifiers
`Models.isNaN` / `Models.isZero` (mirrors `float32_is_nan` /
`float32_is_zero`). -/

/-! ## Natural spec for the IEEE 754 binary32 comparisons -/

namespace Spec32

/-- IEEE 754 §5.6.1 equality: false if either operand is NaN; true
if both operands are zero (regardless of sign); otherwise equality
of all three fields. -/
def ieee754Eq32 (a b : Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else if Models.isZero a && Models.isZero b then true
  else decide (a.sign = b.sign)
      && decide (a.exponent = b.exponent)
      && decide (a.mantissa = b.mantissa)

/-- IEEE 754 §5.6.1 strict less-than: false if either operand is
NaN, false if both are zero, otherwise lexicographic on (sign,
magnitude) with sign-flip for negatives. -/
def ieee754Lt32 (a b : Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else if Models.isZero a && Models.isZero b then false
  else if a.sign ≠ b.sign then decide (a.sign = 1)
  else if a.sign = 0 then
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat < b.exponent.toNat)
    else decide (a.mantissa.toNat < b.mantissa.toNat)
  else
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat > b.exponent.toNat)
    else decide (a.mantissa.toNat > b.mantissa.toNat)

/-- Less-than-or-equal: not NaN-unordered, and either lt or eq. -/
def ieee754Le32 (a b : Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else ieee754Lt32 a b || ieee754Eq32 a b

/-- Strict greater-than: `b < a`. -/
def ieee754Gt32 (a b : Float32Bits) : Bool := ieee754Lt32 b a

/-- Greater-than-or-equal: `b ≤ a`. -/
def ieee754Ge32 (a b : Float32Bits) : Bool := ieee754Le32 b a

/-- Unordered: at least one operand is NaN. -/
def ieee754Unordered32 (a b : Float32Bits) : Bool :=
  Models.isNaN a || Models.isNaN b

/-- Three-way comparison mirroring the Noir `float32_compare`
implementation, as a signed `Int` in `{-1, 0, 1}`. This is a
near-totalOrder rather than literal IEEE 754-2019 §5.10
totalOrder — it deviates from §5.10 in two ways that match the
Noir source:

* For non-NaN operands the result delegates to `ieee754Lt32` /
  `ieee754Gt32`, which treat `+0` and `-0` as equal. §5.10
  totalOrder requires `-0 < +0`; here `ieee754TotalOrder32 (-0)
  (+0) = 0`.
* For NaN-vs-NaN with equal sign the comparison is over the full
  mantissa field (including the quiet/signalling bit), so two
  NaNs that share a payload but differ in `is_quiet` order
  differently. §5.10 only specifies a payload-based ordering.

Both deviations are intentional: the spec is the Lean witness
that the equivalence theorem
`Cmp32.float32Compare = Spec32.ieee754TotalOrder32` holds for
the Noir implementation as written. Downstream consumers that
need literal §5.10 totalOrder should derive it from this spec
plus an explicit signed-zero / quiet-bit case split. -/
def ieee754TotalOrder32 (a b : Float32Bits) : Int :=
  let aNaN := Models.isNaN a
  let bNaN := Models.isNaN b
  if aNaN && bNaN then
    if a.sign ≠ b.sign then
      (if a.sign = 1 then -1 else 1)
    else
      if a.mantissa.toNat < b.mantissa.toNat then
        (if a.sign = 1 then 1 else -1)
      else if a.mantissa.toNat > b.mantissa.toNat then
        (if a.sign = 1 then -1 else 1)
      else 0
  else if aNaN then
    (if a.sign = 1 then -1 else 1)
  else if bNaN then
    (if b.sign = 1 then 1 else -1)
  else
    if ieee754Lt32 a b then -1
    else if ieee754Gt32 a b then 1
    else 0

end Spec32

/-! ## Lean models of the optimised Noir comparison bodies

Each model captures the same input/output behaviour as the
corresponding Noir function in
`circuits/noir_IEEE754/ieee754/src/float32/cmp.nr`. The Noir
source uses an `Id.run`-style `mut` cascade; we collapse that
cascade into the equivalent direct `if`-expression so the Lean
model and the spec are syntactically identical (the equivalence
theorems below close by `rfl`). -/

namespace Cmp32

/-- Lean model of `float32_eq` (cmp.nr lines 33-54). The Noir
`mut` cascade `result := false; if !aNaN && !bNaN then if zero
then true else fields-eq` is the same value as the direct
`if`-expression here. -/
def float32Eq (a b : Models.Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else if Models.isZero a && Models.isZero b then true
  else decide (a.sign = b.sign)
      && decide (a.exponent = b.exponent)
      && decide (a.mantissa = b.mantissa)

/-- Lean model of `float32_ne` (cmp.nr lines 60-62). -/
def float32Ne (a b : Models.Float32Bits) : Bool := !float32Eq a b

/-- Lean model of `float32_lt` (cmp.nr lines 69-105). -/
def float32Lt (a b : Models.Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else if Models.isZero a && Models.isZero b then false
  else if a.sign ≠ b.sign then decide (a.sign = 1)
  else if a.sign = 0 then
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat < b.exponent.toNat)
    else decide (a.mantissa.toNat < b.mantissa.toNat)
  else
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat > b.exponent.toNat)
    else decide (a.mantissa.toNat > b.mantissa.toNat)

/-- Lean model of `float32_le` (cmp.nr lines 112-124). -/
def float32Le (a b : Models.Float32Bits) : Bool :=
  if Models.isNaN a || Models.isNaN b then false
  else float32Lt a b || float32Eq a b

/-- Lean model of `float32_gt` (cmp.nr lines 131-134). -/
def float32Gt (a b : Models.Float32Bits) : Bool := float32Lt b a

/-- Lean model of `float32_ge` (cmp.nr lines 141-144). -/
def float32Ge (a b : Models.Float32Bits) : Bool := float32Le b a

/-- Lean model of `float32_unordered` (cmp.nr lines 150-152). -/
def float32Unordered (a b : Models.Float32Bits) : Bool :=
  Models.isNaN a || Models.isNaN b

/-- Lean model of `float32_compare` (cmp.nr lines 160-197).
Returns `Int` (the natural Lean representative of Noir `i8` values
`-1`, `0`, `1`). -/
def float32Compare (a b : Models.Float32Bits) : Int :=
  let aNaN := Models.isNaN a
  let bNaN := Models.isNaN b
  if aNaN && bNaN then
    if a.sign ≠ b.sign then
      (if a.sign = 1 then -1 else 1)
    else
      if a.mantissa.toNat < b.mantissa.toNat then
        (if a.sign = 1 then 1 else -1)
      else if a.mantissa.toNat > b.mantissa.toNat then
        (if a.sign = 1 then -1 else 1)
      else 0
  else if aNaN then
    (if a.sign = 1 then -1 else 1)
  else if bNaN then
    (if b.sign = 1 then 1 else -1)
  else
    if float32Lt a b then -1
    else if float32Gt a b then 1
    else 0

end Cmp32

end ZkpSparql.Ieee754.Equivalence
