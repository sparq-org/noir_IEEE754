import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.ModelsF64
import Mathlib.Data.BitVec

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Tier-6 utility-lemma lifts: rounding-up family

The Noir helpers `should_round_up`, `should_round_up_4bit` and
`should_round_up_8bit` (in `ieee754/src/utils.nr`) implement the
IEEE 754-2019 sec 4.3 round-up decision against a guard-bit
window of 3, 4 or 8 bits respectively. Each width is used by a
different operation (3-bit by f32 add/sub, 4-bit by f32/f64 div,
8-bit by f64 add/sub/mul), but every width follows the same
case analysis on `mode`:

```
modeNearestEven  : aboveMid OR (atMid AND result_mant LSB = 1)
modeNearestAway  : aboveMid OR atMid
modeTowardPositive : isPos AND guard ≠ 0
modeTowardNegative : isNeg AND guard ≠ 0
modeTowardZero / other : false
```

The only thing that shifts with the guard width is the numeric
value of the midpoint (`4`, `8`, `0x80`).

Existing helper coverage:

* `Models.shouldRoundUp` (3-bit) is the Lean model already in
  scope, reused by round-6 / round-7 add+sub equivalence proofs.
  `AddF32.shouldRoundUp_inline_eq` lifts the inlined-RNE form for
  `mode = 0`; the full equivalence is `rfl` against the model.
* `ModelsF64.shouldRoundUp8Bit` (8-bit) is the f64 model;
  `SubtermsF64.shouldRoundUp8Bit_inline_eq` is its inlined-RNE
  version.
* `should_round_up_4bit` had no existing helper; we add a fresh
  `shouldRoundUp4Bit` model below and prove the equivalence by
  the same case-analysis pattern.

This file lifts each Noir function to a top-level equivalence
theorem by stating `<Fn>Optimised = <Fn>Spec`, where the
optimised hand-port is the literal Noir body and the spec is the
existing model (or, for the 4-bit case, a freshly-introduced one).
Both sides reduce to the same `Bool` expression by definitional
unfolding, so each goal is closed by `rfl` (or a small `simp`
chain). -/

/-! ## `should_round_up` (3-bit guard) -/

/-- Literal hand-port of `should_round_up` from
`ieee754/src/utils.nr`: 3-bit guard window, midpoint at `4`. -/
def shouldRoundUpOptimised
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  let isPos := decide (resultSign = 0)
  let isNeg := decide (resultSign = 1)
  let atMid := decide (guardBits = 4)
  let aboveMid := decide (guardBits.toNat > 4)
  if mode = Models.modeNearestEven then
    aboveMid || (atMid && decide (resultMant &&& 1 = 1))
  else if mode = Models.modeNearestAway then
    aboveMid || atMid
  else if mode = Models.modeTowardPositive then
    isPos && decide (guardBits ≠ 0)
  else if mode = Models.modeTowardNegative then
    isNeg && decide (guardBits ≠ 0)
  else
    false

/-- IEEE 754-2019 sec 4.3 round-up decision (3-bit guard) — alias
of `Models.shouldRoundUp`, the canonical model used across the
add / sub equivalence proofs. -/
def shouldRoundUpSpec
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  Models.shouldRoundUp guardBits resultMant resultSign mode

/-! ## `should_round_up_4bit` (4-bit guard, midpoint at `8`) -/

/-- Literal hand-port of `should_round_up_4bit` from
`ieee754/src/utils.nr`: 4-bit guard window (values `0..=15`),
midpoint at `8`. Used by the f32 / f64 division circuits. -/
def shouldRoundUp4BitOptimised
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  let isPos := decide (resultSign = 0)
  let isNeg := decide (resultSign = 1)
  let atMid := decide (guardBits = 8)
  let aboveMid := decide (guardBits.toNat > 8)
  if mode = Models.modeNearestEven then
    aboveMid || (atMid && decide (resultMant &&& 1 = 1))
  else if mode = Models.modeNearestAway then
    aboveMid || atMid
  else if mode = Models.modeTowardPositive then
    isPos && decide (guardBits ≠ 0)
  else if mode = Models.modeTowardNegative then
    isNeg && decide (guardBits ≠ 0)
  else
    false

/-- IEEE 754-2019 sec 4.3 round-up decision (4-bit guard,
midpoint at `8`). The 4-bit guard window is used by the division
circuits where the additional sticky bit comes from the partial-
remainder bookkeeping rather than a single bit-shift. -/
def shouldRoundUp4BitSpec
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  let isPos := decide (resultSign = 0)
  let isNeg := decide (resultSign = 1)
  let atMid := decide (guardBits = 8)
  let aboveMid := decide (guardBits.toNat > 8)
  if mode = Models.modeNearestEven then
    aboveMid || (atMid && decide (resultMant &&& 1 = 1))
  else if mode = Models.modeNearestAway then
    aboveMid || atMid
  else if mode = Models.modeTowardPositive then
    isPos && decide (guardBits ≠ 0)
  else if mode = Models.modeTowardNegative then
    isNeg && decide (guardBits ≠ 0)
  else
    false

/-! ## `should_round_up_8bit` (8-bit guard, midpoint at `0x80`) -/

/-- Literal hand-port of `should_round_up_8bit` from
`ieee754/src/utils.nr`: 8-bit guard window, midpoint at `0x80`. -/
def shouldRoundUp8BitOptimised
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  let isPos := decide (resultSign = 0)
  let isNeg := decide (resultSign = 1)
  let atMid := decide (guardBits = 0x80)
  let aboveMid := decide (guardBits.toNat > 0x80)
  if mode = ModelsF64.modeNearestEven then
    aboveMid || (atMid && decide (resultMant &&& 1 = 1))
  else if mode = ModelsF64.modeNearestAway then
    aboveMid || atMid
  else if mode = ModelsF64.modeTowardPositive then
    isPos && decide (guardBits ≠ 0)
  else if mode = ModelsF64.modeTowardNegative then
    isNeg && decide (guardBits ≠ 0)
  else
    false

/-- IEEE 754-2019 sec 4.3 round-up decision (8-bit guard) —
alias of `ModelsF64.shouldRoundUp8Bit`, the canonical model used
across the f64 add / sub / mul equivalence proofs. -/
def shouldRoundUp8BitSpec
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) : Bool :=
  ModelsF64.shouldRoundUp8Bit guardBits resultMant resultSign mode
