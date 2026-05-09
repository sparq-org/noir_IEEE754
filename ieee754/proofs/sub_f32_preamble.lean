-- # Lampe-literate splice fragment - sub_f32 preamble
--
-- This file is **not** a standalone Lean module. It is a literate
-- splice fragment consumed by `circuits/lampe-literate`: the build
-- tool concatenates this preamble with `sub_f32_equivalence.lean`
-- (matching the `LAMPE-LITERATE preamble:` / `proof:` directives in
-- `../src/float32/mod.nr`) into a generated module under the
-- gitignored `.lampe-literate/` scratch tree. The companion fragment
-- emits the matching `end ZkpSparql.Ieee754.Equivalence` so the
-- namespace balances **after** splicing, not in either fragment in
-- isolation. Editor / linter errors from opening this file directly
-- are expected; build it via `lampe-literate build`.

import ZkpSparql.Ieee754.Equivalence.Models
import ZkpSparql.Ieee754.Equivalence.Subterms

namespace ZkpSparql.Ieee754.Equivalence

open ZkpSparql.Ieee754.Equivalence.Models
open ZkpSparql.Ieee754.Equivalence.Subterms
