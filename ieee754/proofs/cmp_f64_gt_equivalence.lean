namespace ZkpSparql.Ieee754.Equivalence

theorem float64_gt_equivalence :
    Cmp64.float64Gt = Spec64.ieee754Gt64 := by
  funext a b
  unfold Cmp64.float64Gt Spec64.ieee754Gt64
  exact congrFun (congrFun float64_lt_equivalence b) a

end ZkpSparql.Ieee754.Equivalence
