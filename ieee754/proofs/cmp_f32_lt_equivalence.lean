namespace ZkpSparql.Ieee754.Equivalence

theorem float32_lt_equivalence :
    Cmp32.float32Lt = Spec32.ieee754Lt32 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
