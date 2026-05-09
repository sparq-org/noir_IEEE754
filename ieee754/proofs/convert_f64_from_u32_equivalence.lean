import ZkpSparql.Ieee754.Equivalence.ConvertFromIntFieldF64Preamble

namespace ZkpSparql.Ieee754.Equivalence

theorem float64_from_u32_equivalence :
    ConvertF64.float64FromU32 = SpecConvertF64.float64FromU32 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
