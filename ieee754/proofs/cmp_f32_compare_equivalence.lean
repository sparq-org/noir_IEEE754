namespace ZkpSparql.Ieee754.Equivalence

theorem float32_compare_equivalence :
    Cmp32.float32Compare = Spec32.ieee754TotalOrder32 := by
  funext a b
  unfold Cmp32.float32Compare Spec32.ieee754TotalOrder32
  rw [show Cmp32.float32Lt = Spec32.ieee754Lt32 from float32_lt_equivalence,
      show Cmp32.float32Gt = Spec32.ieee754Gt32 from float32_gt_equivalence]

end ZkpSparql.Ieee754.Equivalence
