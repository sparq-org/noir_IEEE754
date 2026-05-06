import Mathlib.Data.BitVec
import Mathlib.Tactic
import ZkpSparql.Ieee754.Equivalence.ModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.ModelsF64

/-! # IEEE 754 binary64 comparison spec + Lean models

The optimised binary64 comparison ops live in
`circuits/noir_IEEE754/ieee754/src/float64/cmp.nr`. This module
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

The eight equivalence theorems in `cmp_f64_<op>_equivalence.lean`
show each Noir model equals its spec.

The bit-level representation reuses `ModelsF64.Float64Bits`
(mirrors `IEEE754Float64` in `ieee754::types`) and the classifiers
`ModelsF64.isNaN64` / `ModelsF64.isZero64` (mirrors
`float64_is_nan` / `float64_is_zero`). -/

/-! ## Natural spec for the IEEE 754 binary64 comparisons -/

namespace Spec64

/-- IEEE 754 §5.6.1 equality: false if either operand is NaN; true
if both operands are zero (regardless of sign); otherwise equality
of all three fields. -/
def ieee754Eq64 (a b : Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else if ModelsF64.isZero64 a && ModelsF64.isZero64 b then true
  else decide (a.sign = b.sign)
      && decide (a.exponent = b.exponent)
      && decide (a.mantissa = b.mantissa)

/-- IEEE 754 §5.6.1 strict less-than: false if either operand is
NaN, false if both are zero, otherwise lexicographic on (sign,
magnitude) with sign-flip for negatives. -/
def ieee754Lt64 (a b : Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else if ModelsF64.isZero64 a && ModelsF64.isZero64 b then false
  else if a.sign ≠ b.sign then decide (a.sign = 1)
  else if a.sign = 0 then
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat < b.exponent.toNat)
    else decide (a.mantissa.toNat < b.mantissa.toNat)
  else
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat > b.exponent.toNat)
    else decide (a.mantissa.toNat > b.mantissa.toNat)

/-- Less-than-or-equal: not NaN-unordered, and either lt or eq. -/
def ieee754Le64 (a b : Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else ieee754Lt64 a b || ieee754Eq64 a b

/-- Strict greater-than: `b < a`. -/
def ieee754Gt64 (a b : Float64Bits) : Bool := ieee754Lt64 b a

/-- Greater-than-or-equal: `b ≤ a`. -/
def ieee754Ge64 (a b : Float64Bits) : Bool := ieee754Le64 b a

/-- Unordered: at least one operand is NaN. -/
def ieee754Unordered64 (a b : Float64Bits) : Bool :=
  ModelsF64.isNaN64 a || ModelsF64.isNaN64 b

/-- IEEE 754-2019 §5.10 totalOrder, as a signed `Int` in `{-1, 0,
1}`: `-NaN < -Inf < … < -0 < +0 < … < +Inf < +NaN`. NaNs are
ordered by sign first, then by mantissa payload (with negative
NaNs ordered "larger payload = more negative"). For non-NaN
operands the result delegates to the standard `<` / `>` ops. -/
def ieee754TotalOrder64 (a b : Float64Bits) : Int :=
  let aNaN := ModelsF64.isNaN64 a
  let bNaN := ModelsF64.isNaN64 b
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
    if ieee754Lt64 a b then -1
    else if ieee754Gt64 a b then 1
    else 0

end Spec64

/-! ## Lean models of the optimised Noir comparison bodies

Each model captures the same input/output behaviour as the
corresponding Noir function in
`circuits/noir_IEEE754/ieee754/src/float64/cmp.nr`. The Noir
source uses an `Id.run`-style `mut` cascade; we collapse that
cascade into the equivalent direct `if`-expression so the Lean
model and the spec are syntactically identical (the equivalence
theorems below close by `rfl`). -/

namespace Cmp64

/-- Lean model of `float64_eq` (cmp.nr lines 19-40). -/
def float64Eq (a b : ModelsF64.Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else if ModelsF64.isZero64 a && ModelsF64.isZero64 b then true
  else decide (a.sign = b.sign)
      && decide (a.exponent = b.exponent)
      && decide (a.mantissa = b.mantissa)

/-- Lean model of `float64_ne` (cmp.nr lines 44-46). -/
def float64Ne (a b : ModelsF64.Float64Bits) : Bool := !float64Eq a b

/-- Lean model of `float64_lt` (cmp.nr lines 51-87). -/
def float64Lt (a b : ModelsF64.Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else if ModelsF64.isZero64 a && ModelsF64.isZero64 b then false
  else if a.sign ≠ b.sign then decide (a.sign = 1)
  else if a.sign = 0 then
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat < b.exponent.toNat)
    else decide (a.mantissa.toNat < b.mantissa.toNat)
  else
    if a.exponent ≠ b.exponent then decide (a.exponent.toNat > b.exponent.toNat)
    else decide (a.mantissa.toNat > b.mantissa.toNat)

/-- Lean model of `float64_le` (cmp.nr lines 92-104). -/
def float64Le (a b : ModelsF64.Float64Bits) : Bool :=
  if ModelsF64.isNaN64 a || ModelsF64.isNaN64 b then false
  else float64Lt a b || float64Eq a b

/-- Lean model of `float64_gt` (cmp.nr lines 109-112). -/
def float64Gt (a b : ModelsF64.Float64Bits) : Bool := float64Lt b a

/-- Lean model of `float64_ge` (cmp.nr lines 117-120). -/
def float64Ge (a b : ModelsF64.Float64Bits) : Bool := float64Le b a

/-- Lean model of `float64_unordered` (cmp.nr lines 124-126). -/
def float64Unordered (a b : ModelsF64.Float64Bits) : Bool :=
  ModelsF64.isNaN64 a || ModelsF64.isNaN64 b

/-- Lean model of `float64_compare` (cmp.nr lines 132-169).
Returns `Int` (the natural Lean representative of Noir `i8` values
`-1`, `0`, `1`). -/
def float64Compare (a b : ModelsF64.Float64Bits) : Int :=
  let aNaN := ModelsF64.isNaN64 a
  let bNaN := ModelsF64.isNaN64 b
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
    if float64Lt a b then -1
    else if float64Gt a b then 1
    else 0

end Cmp64

end ZkpSparql.Ieee754.Equivalence
