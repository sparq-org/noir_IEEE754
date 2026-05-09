/-! This file is a lampe-literate **proof fragment**, not a
standalone Lean module. It is referenced from
`ieee754/src/float32/convert.nr` via a `LAMPE-LITERATE proof:`
directive, and the materialiser splices its body into the
generated `Generated.lean` module *after* the matching preamble
(`convert_to_int_f32_preamble.lean`). Imports and the
`open ZkpSparql.Ieee754.Equivalence.Models` block live in the
preamble; this fragment therefore intentionally has no `import`
lines (Lean only accepts imports at the very top of a module, and
this body is concatenated mid-module). To work on the proof in
isolation, build via `lampe-literate` so the splice produces a
well-formed module.
-/

namespace ZkpSparql.Ieee754.Equivalence

theorem float32_to_u32_equivalence :
    ConvertF32.float32ToU32 = SpecConvertF32.float32ToU32 := by
  rfl

end ZkpSparql.Ieee754.Equivalence
