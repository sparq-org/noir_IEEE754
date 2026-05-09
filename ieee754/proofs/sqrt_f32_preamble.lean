-- Imports for the `sqrt_f32_equivalence` closure.
--
-- The skeleton-and-divergence pattern (round 9 mul_f64 / round-9-width-narrow
-- mul_f32) is the template; this closure uses a single divergence parameter
-- (the inline-RNE 3-bit shortcut) and shares the 27-iteration restoring sqrt
-- loop between optimised and reference. See
-- `decisions/sqrt-f32-loop-shared-vs-divergent.md`.
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.SubtermsMulF64
import ZkpSparql.Ieee754.Equivalence.MulModelsF64
import ZkpSparql.Ieee754.Equivalence.MulModelsF32
import ZkpSparql.Ieee754.Equivalence.SqrtModelsF32

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.SubtermsMulF64
open ZkpSparql.Ieee754.Equivalence.SqrtModelsF32
