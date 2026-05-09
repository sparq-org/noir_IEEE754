namespace ZkpSparql.Ieee754.Equivalence

theorem float64_le_equivalence :
    Cmp64.float64Le = Spec64.ieee754Le64 := by
  funext a b
  unfold Cmp64.float64Le Spec64.ieee754Le64
  rw [show Cmp64.float64Lt = Spec64.ieee754Lt64 from float64_lt_equivalence,
      show Cmp64.float64Eq = Spec64.ieee754Eq64 from float64_eq_equivalence]

end ZkpSparql.Ieee754.Equivalence
