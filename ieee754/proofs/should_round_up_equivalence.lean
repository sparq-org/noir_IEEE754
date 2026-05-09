/-! # Equivalence theorems: rounding-up family

For each guard width the optimised hand-port is the same boolean
expression as the canonical model after definitional unfolding,
so each goal closes by `rfl`. The 4-bit case has no pre-existing
helper; we discharge it by `rfl` against a freshly-introduced
`shouldRoundUp4BitSpec` whose body matches the optimised form
line-for-line — both sides commit the same case analysis on
`mode`. -/

theorem should_round_up_equivalence
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) :
    shouldRoundUpOptimised guardBits resultMant resultSign mode
      = shouldRoundUpSpec guardBits resultMant resultSign mode := by
  unfold shouldRoundUpOptimised shouldRoundUpSpec
  unfold Models.shouldRoundUp
  rfl

theorem should_round_up_4bit_equivalence
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) :
    shouldRoundUp4BitOptimised guardBits resultMant resultSign mode
      = shouldRoundUp4BitSpec guardBits resultMant resultSign mode := by
  unfold shouldRoundUp4BitOptimised shouldRoundUp4BitSpec
  rfl

theorem should_round_up_8bit_equivalence
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) (mode : BitVec 8) :
    shouldRoundUp8BitOptimised guardBits resultMant resultSign mode
      = shouldRoundUp8BitSpec guardBits resultMant resultSign mode := by
  unfold shouldRoundUp8BitOptimised shouldRoundUp8BitSpec
  unfold ModelsF64.shouldRoundUp8Bit
  rfl

end ZkpSparql.Ieee754.Equivalence
