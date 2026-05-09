namespace ZkpSparql.Ieee754.Equivalence

theorem float32_ge_equivalence :
    Cmp32.float32Ge = Spec32.ieee754Ge32 := by
  funext a b
  unfold Cmp32.float32Ge Spec32.ieee754Ge32
  exact congrFun (congrFun float32_le_equivalence b) a

end ZkpSparql.Ieee754.Equivalence
