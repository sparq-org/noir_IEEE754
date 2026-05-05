-- Imports for the eventual `mul_f32_equivalence` closure.
--
-- Mirrors round-9 `mul_f64`'s preamble: shared Spec / Subterms / Models
-- modules + the per-op Models / Subterms files. The width-narrowing
-- `MulModelsF32` / `SubtermsMulF32` modules are stubs today (created by
-- this scaffold's downstream Lean specialist); the imports stay listed
-- so the proof file resolves once those modules exist.
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
-- Per-op modules (to be authored by the Lean specialist closing this proof):
-- import ZkpSparql.Ieee754.Equivalence.MulModelsF32
-- import ZkpSparql.Ieee754.Equivalence.SubtermsMulF32

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
-- open ZkpSparql.Ieee754.Equivalence.MulModelsF32
-- open ZkpSparql.Ieee754.Equivalence.SubtermsMulF32
