-- Imports for the eventual `div_f32_equivalence` closure.
--
-- The skeleton-and-divergence pattern (round 9 mul_f64) is the template;
-- the per-op `DivModelsF32` / `SubtermsDivF32` modules will be authored
-- by the Lean specialist closing this proof.
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
-- Per-op modules (to be authored):
-- import ZkpSparql.Ieee754.Equivalence.DivModelsF32
-- import ZkpSparql.Ieee754.Equivalence.SubtermsDivF32

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
-- open ZkpSparql.Ieee754.Equivalence.DivModelsF32
-- open ZkpSparql.Ieee754.Equivalence.SubtermsDivF32
