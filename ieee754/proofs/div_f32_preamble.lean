-- Imports for the `div_f32_equivalence` proof.
--
-- Mirrors the `mul_f32_equivalence` preamble: shared Spec / Subterms /
-- Models modules + the per-op DivModels and SubtermsDivF64 modules
-- (the latter is reused for its width-agnostic
-- `shouldRoundUp4Bit_inline_eq` lemma -- the lemma operates on
-- `BitVec 64` guard / mantissa lanes regardless of float width).
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.DivModelsF64
import ZkpSparql.Ieee754.Equivalence.DivModelsF32
import ZkpSparql.Ieee754.Equivalence.SubtermsDivF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.DivModelsF64
open ZkpSparql.Ieee754.Equivalence.DivModelsF32
open ZkpSparql.Ieee754.Equivalence.SubtermsDivF64
