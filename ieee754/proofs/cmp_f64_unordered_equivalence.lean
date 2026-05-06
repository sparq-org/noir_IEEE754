namespace ZkpSparql.Ieee754.Equivalence

theorem float64_unordered_equivalence :
    Cmp64.float64Unordered = Spec64.ieee754Unordered64 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
