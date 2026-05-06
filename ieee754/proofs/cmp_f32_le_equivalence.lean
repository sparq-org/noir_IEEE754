namespace ZkpSparql.Ieee754.Equivalence

theorem float32_le_equivalence :
    Cmp32.float32Le = Spec32.ieee754Le32 := by
  funext a b
  unfold Cmp32.float32Le Spec32.ieee754Le32
  rw [show Cmp32.float32Lt = Spec32.ieee754Lt32 from float32_lt_equivalence,
      show Cmp32.float32Eq = Spec32.ieee754Eq32 from float32_eq_equivalence]

end ZkpSparql.Ieee754.Equivalence
