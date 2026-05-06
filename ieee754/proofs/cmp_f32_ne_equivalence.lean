namespace ZkpSparql.Ieee754.Equivalence

theorem float32_ne_equivalence :
    Cmp32.float32Ne = (fun a b => !Spec32.ieee754Eq32 a b) := by
  funext a b
  unfold Cmp32.float32Ne
  rw [show Cmp32.float32Eq = Spec32.ieee754Eq32 from float32_eq_equivalence]

end ZkpSparql.Ieee754.Equivalence
