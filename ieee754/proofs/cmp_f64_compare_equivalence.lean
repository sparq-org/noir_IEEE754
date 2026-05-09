namespace ZkpSparql.Ieee754.Equivalence

theorem float64_compare_equivalence :
    Cmp64.float64Compare = Spec64.ieee754TotalOrder64 := by
  funext a b
  unfold Cmp64.float64Compare Spec64.ieee754TotalOrder64
  rw [show Cmp64.float64Lt = Spec64.ieee754Lt64 from float64_lt_equivalence,
      show Cmp64.float64Gt = Spec64.ieee754Gt64 from float64_gt_equivalence]

end ZkpSparql.Ieee754.Equivalence
