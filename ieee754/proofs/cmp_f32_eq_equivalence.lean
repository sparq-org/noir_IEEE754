namespace ZkpSparql.Ieee754.Equivalence

theorem float32_eq_equivalence :
    Cmp32.float32Eq = Spec32.ieee754Eq32 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
