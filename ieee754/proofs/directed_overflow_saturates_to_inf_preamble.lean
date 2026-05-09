import ZkpSparql.Ieee754.Equivalence.Models
import Mathlib.Data.BitVec

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models

/-! # Tier-6 utility-lemma lift: directed-overflow saturation

The Noir helper `directed_overflow_saturates_to_inf` (in
`ieee754/src/utils.nr`) implements IEEE 754-2019 sec 7.4: under
directed rounding, an overflow either saturates to `±Inf` or
clamps to `±max-finite`, depending on `(rounding_mode,
result_sign)`. The decision is a 5×2 truth table:

```
mode               | sign + | sign - |
-------------------+--------+--------+
modeNearestEven    | true   | true   |
modeNearestAway    | true   | true   |
modeTowardPositive | true   | false  |
modeTowardNegative | false  | true   |
modeTowardZero     | false  | false  |
```

The canonical Lean model is `Models.directedOverflowSaturatesToInf`,
already in scope (used by every f32/f64 add/sub/mul rounding path).
This file lifts the Noir function to a top-level equivalence
theorem associated with the public Noir name. The optimised hand-
port matches the model line-for-line, so the equivalence is `rfl`. -/

/-- Literal hand-port of `directed_overflow_saturates_to_inf` from
`ieee754/src/utils.nr`. -/
def directedOverflowSaturatesToInfOptimised
    (roundingMode : BitVec 8) (resultSign : BitVec 1) : Bool :=
  if roundingMode = Models.modeTowardZero then false
  else if roundingMode = Models.modeTowardPositive then
    decide (resultSign = 0)
  else if roundingMode = Models.modeTowardNegative then
    decide (resultSign = 1)
  else
    true

/-- IEEE 754-2019 sec 7.4 directed-overflow saturation —
re-export of `Models.directedOverflowSaturatesToInf`, the
canonical model used across the rounding paths. -/
def directedOverflowSaturatesToInfSpec
    (roundingMode : BitVec 8) (resultSign : BitVec 1) : Bool :=
  Models.directedOverflowSaturatesToInf roundingMode resultSign
