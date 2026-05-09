/-! # Equivalence theorem: `directed_overflow_saturates_to_inf`

The optimised hand-port and the canonical model
(`Models.directedOverflowSaturatesToInf`) commit the same case
analysis on `roundingMode`, so the equivalence is `rfl` after a
single `unfold` of the spec model. -/

theorem directed_overflow_saturates_to_inf_equivalence
    (roundingMode : BitVec 8) (resultSign : BitVec 1) :
    directedOverflowSaturatesToInfOptimised roundingMode resultSign
      = directedOverflowSaturatesToInfSpec roundingMode resultSign := by
  unfold directedOverflowSaturatesToInfOptimised
    directedOverflowSaturatesToInfSpec
  unfold Models.directedOverflowSaturatesToInf
  rfl

end ZkpSparql.Ieee754.Equivalence
