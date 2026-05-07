-- Imports for the `div_f32_equivalence` proof.
--
-- Mirrors the `mul_f32_equivalence` preamble: shared Spec / Subterms /
-- Models modules + the per-op DivModelsF32 (which carries both the
-- canonical `shouldRoundUp4Bit` and its inline-RNE divergence lemma
-- `shouldRoundUp4Bit_inline_eq`, in the absence of a workspace-side
-- f64-div module on `main`).
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.DivModelsF32

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.DivModelsF32
