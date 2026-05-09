-- Imports for the `sqrt_f64_equivalence` closure.
--
-- The skeleton-and-divergence pattern (round 9 mul_f64 / sqrt_f32) is the
-- template; this closure uses a single divergence parameter (the inline-RNE
-- 3-bit shortcut) and shares the 56-iteration restoring sqrt loop on U128
-- state between optimised and reference. See
-- `decisions/sqrt-f64-loop-shared-vs-divergent.md` (which itself ports the
-- sqrt_f32 decision to wider state).
import ZkpSparql.Ieee754.Equivalence.Spec
import ZkpSparql.Ieee754.Equivalence.SpecF64
import ZkpSparql.Ieee754.Equivalence.Subterms
import ZkpSparql.Ieee754.Equivalence.SubtermsF64
import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.ModelsF64
import ZkpSparql.Ieee754.Equivalence.SubtermsMulF64
import ZkpSparql.Ieee754.Equivalence.MulModelsF64
import ZkpSparql.Ieee754.Equivalence.SqrtModelsF64

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.ModelsF64
open ZkpSparql.Ieee754.Equivalence.Subterms
open ZkpSparql.Ieee754.Equivalence.SubtermsF64
open ZkpSparql.Ieee754.Equivalence.SubtermsMulF64
open ZkpSparql.Ieee754.Equivalence.MulModelsF64
open ZkpSparql.Ieee754.Equivalence.SqrtModelsF64
