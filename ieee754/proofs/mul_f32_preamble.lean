-- Imports for the `mul_f32_equivalence` proof.
--
-- Mirrors the round-9 `mul_f64` preamble: shared Spec / Subterms /
-- Models modules + the per-op MulModels and SubtermsMulF64 (the latter
-- is reused for its width-agnostic inline-RNE wrapper lemma).
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.MulModelsF32
import ZkpSparql.Ieee754.Equivalence.SubtermsMulF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.MulModelsF32
open ZkpSparql.Ieee754.Equivalence.SubtermsMulF64
