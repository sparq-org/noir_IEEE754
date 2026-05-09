namespace ZkpSparql.Ieee754.Equivalence

theorem float32_unordered_equivalence :
    Cmp32.float32Unordered = Spec32.ieee754Unordered32 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
