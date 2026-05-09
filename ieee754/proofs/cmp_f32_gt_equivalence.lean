namespace ZkpSparql.Ieee754.Equivalence

theorem float32_gt_equivalence :
    Cmp32.float32Gt = Spec32.ieee754Gt32 := by
  funext a b
  unfold Cmp32.float32Gt Spec32.ieee754Gt32
  exact congrFun (congrFun float32_lt_equivalence b) a

end ZkpSparql.Ieee754.Equivalence
