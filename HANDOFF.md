# noir_IEEE754 — work remaining

Snapshot 2026-05-10 (post-Wave-16 sub-repo merge train). Read together
with `CLAUDE.md`, `IMPLEMENTATION_PLAN.md`, `CONTRIBUTING.md`, and
`.claude/README.md`.

## Recent state

- **All five Tier-4 closures landed at round-9-baseline strength.**
  `mul_f32` (#63), `div_f32` (#87), `div_f64` (#68), `sqrt_f32` (#69),
  `sqrt_f64` closed via subsequent merges. Each ships with its
  shared denormal-mantissa CLZ + leading-bit + (for sqrt) restoring
  loop helper, mirroring how round 9 (`mul_f64`) originally shipped.
- **Round-9 `mul_f64` strengthening done.** Workspace `#82` closed
  task iv (`clzDenormalMantissa64` 32-leaf dispatch) and `#83` closed
  task ii (`leadingBitPos128` via `clz64` anchor). Task iii
  (`shiftRightStickyU128`) had already closed 2026-05-04.
  `mul_f64_equivalence` is now strong on all three round-9 helpers.
- **f32 + f64 testfloat surface green.**
  `KNOWN_BAD_TESTS_BY_ROUNDING` is the empty set
  (`scripts/noir_ieee754_inputs/fptest.py:70`). Directed-rounding
  bug classes from PR #50 are closed; the f64-hardening allow-list
  metric has reached zero.
- **Tier-2 round-trip lemmas closed.** The previously-`sorry`-stubbed
  `<w>_from_bits ∘ <w>_to_bits = id` for f32 (#70) and f64 (#72)
  landed in the bulk merge #92 and now have `Status: closed` headers
  in `bits_roundtrip_<w>_equivalence.lean`. **No live Tier-2 sorries
  remain.**
- **Lampe-literate option-3 is the canonical layout.** PR #60
  bootstrapped it on `add_f32`; #74 / #75 / #76 / #78 migrated the
  rest of the original Tier-1 baseline; the workspace
  `proofs/Ieee754/.../*.lean` tree no longer contains
  per-equivalence Lean files (only the shared models in
  `ZkpSparql/`).

## Outstanding work — priority order

### 1. Round-9-baseline strengthening across the five Tier-4 closures

The five closures all share the same single-divergence shape but
defer their denormal-mantissa CLZ (and, for sqrt, the restoring
loop) into a helper that is shared between optimised and reference
paths. Strengthening lifts each helper to a literal-loop spec —
analogous to how round-9 task ii (`leadingBitPos128`) and task iv
(`clzDenormalMantissa64`) were strengthened for `mul_f64`.

| Closure | PR (closed) | Shared helpers to strengthen | f64 template |
| ------- | ----------- | ---------------------------- | ------------ |
| `mul_f32` | #63 | `clzDenormalMantissa32`, `leadingBitPos64` | round-9 tasks ii / iv |
| `div_f32` | #87 | `clzDenormalMantissa32F32Div` | round-9 task iv (32-leaf) |
| `div_f64` | #68 | `divU128ByU64` per-step (workspace `SubtermsDivF64.divU128ByU64_eq_spec` is `sorry`) | new — multi-day |
| `sqrt_f32` | #69 | `sqrtLoop27` on U64 | new — round-10 |
| `sqrt_f64` | #71 + closure | `sqrtLoop56` on U128, `clzDenormalMantissa64` (still shared on this side) | new — round-10 |

Recommended order: f32 first (`mul_f32`, `div_f32`), since the
round-9 `clzDenormalMantissa64_eq_spec_masked` literal-loop template
narrows almost mechanically to 32 leaves. The sqrt loops are
genuinely new work — see `decisions/sqrt-f64-loop-shared-vs-divergent.md`
in the workspace.

### 2. Close the `mul_u64_to_u128` Tier-6 stub

`ieee754/proofs/mul_u64_to_u128_equivalence.lean:73` has the only
remaining `sorry` in the sub-repo proof tree. Closure is mechanical
`Nat`-arithmetic — sketched in the file's preamble. One PR, one
Lean session.

### 3. Add IBM FPgen coverage for sqrt

Square root is unit-test-only. `IMPLEMENTATION_PLAN.md` queues
adding Berkeley TestFloat sqrt vectors (it is the only operation
without end-to-end MPFR-oracle coverage). The harness already
supports TestFloat (#44); plugging in sqrt is a scripts-side
change plus a new `--suite f32-sqrt` / `--suite f64-sqrt` group.

### 4. Workspace-side strength gap (cross-cutting)

`proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/SubtermsDivF64.lean:154`
holds a `sorry` for the per-step `divU128ByU64` long-division
verification. This is a strength gap for `div_f64`, not a closure
gap — the equivalence theorem closes via the round-9-baseline
helper. Strengthening is multi-day; treat it as round-10 work.

### 5. Watch list — non-blocking

- **`gate-count-pr` workflow on main** can fail to push gate-count
  updates because the `main` branch ruleset blocks the bot. See
  workspace `STABILISATION-TODOS.md` for the planned fix (workflow
  opens an auto-merge PR rather than direct-pushing).
- **Square root + comparison** ops are unit-tested only — no IBM
  FPgen coverage. Comparison covered by hand-rolled tables; sqrt
  is item #3 above.
- **FMA + remainder** not implemented. Out of scope for the current
  paper; flag for a future PR if needed.

## Working in isolation from this sub-repo

If you opened Claude Code with `circuits/noir_IEEE754/` as the cwd
(rather than the workspace root), the materials in `.claude/` are
the personas + skills lifted from the workspace. See
`.claude/README.md` for the contents and how to refresh them.

The Lampe / Lean equivalence-proof workflow still requires running
`lampe-literate build …` from the **workspace root** so the
workspace `lampe-literate.toml` resolves shared modules. From an
isolated sub-repo session, that means `cd ..` (twice) before the
build; the sub-repo cannot self-build the proofs alone.

`nargo check` and `python3 scripts/run_tests.py` run cleanly from
the sub-repo root.

## Sub-repo discipline

Every change should:

- carry a Conventional Commit message (see `CONTRIBUTING.md`);
- pass the post-commit roborev review;
- not bypass `--no-verify`;
- run `nargo check` from `ieee754/` before pushing;
- run `python3 scripts/run_tests.py --suite f32` (and `--suite
  f64` for f64-touching changes);
- update `gate_counts.json` if circuit gate counts change (CI
  comments the diff on the PR).

## Out of scope (the paper / workspace handle these)

- BBS+ / SD-JWT integration. The IEEE 754 circuits are a building
  block; the paper composes them with VC commitment shapes.
- ZKP-SPARQL evaluation logic. That's `circuits/sparql_noir`.
- Paper writing. That's the workspace `paper/` tree.
- The lampe-literate build orchestrator. Separate repo
  (`circuits/lampe-literate` in the workspace,
  https://github.com/jeswr/lampe-literate standalone).
