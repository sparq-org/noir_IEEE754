namespace ZkpSparql.Ieee754.Equivalence

theorem float64_ge_equivalence :
    Cmp64.float64Ge = Spec64.ieee754Ge64 := by
  funext a b
  unfold Cmp64.float64Ge Spec64.ieee754Ge64
  exact congrFun (congrFun float64_le_equivalence b) a

end ZkpSparql.Ieee754.Equivalence
