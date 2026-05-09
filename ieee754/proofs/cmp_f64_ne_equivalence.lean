namespace ZkpSparql.Ieee754.Equivalence

theorem float64_ne_equivalence :
    Cmp64.float64Ne = (fun a b => !Spec64.ieee754Eq64 a b) := by
  funext a b
  unfold Cmp64.float64Ne
  rw [show Cmp64.float64Eq = Spec64.ieee754Eq64 from float64_eq_equivalence]

end ZkpSparql.Ieee754.Equivalence
