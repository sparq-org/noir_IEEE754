namespace ZkpSparql.Ieee754.Equivalence

theorem float64_lt_equivalence :
    Cmp64.float64Lt = Spec64.ieee754Lt64 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
