-- Imports for the eventual `sqrt_f64_equivalence` closure.
--
-- Mirrors round-9 `mul_f64`'s import set. Per-op `SqrtModelsF64` /
-- `SubtermsSqrtF64` modules are stubs today, authored by the Lean
-- specialist closing this proof.
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.SpecF64
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.SubtermsF64
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.ModelsF64
-- Per-op modules (to be authored):
-- import ZkpSparql.Ieee754.Equivalence.SqrtModelsF64
-- import ZkpSparql.Ieee754.Equivalence.SubtermsSqrtF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.ModelsF64
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.SubtermsF64
-- open ZkpSparql.Ieee754.Equivalence.SqrtModelsF64
-- open ZkpSparql.Ieee754.Equivalence.SubtermsSqrtF64
