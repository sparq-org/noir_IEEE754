# noir_IEEE754 — work remaining

Snapshot 2026-05-05. Read together with `CLAUDE.md`,
`IMPLEMENTATION_PLAN.md` and `CONTRIBUTING.md`.

## Recent state

- **f32 testfloat surface green.** All five rounding modes exercised
  end-to-end via the MPFR-backed reference oracle.
- **f64 has known-bad cases** tracked in
  `KNOWN_BAD_TESTS_BY_ROUNDING` (`scripts/noir_ieee754_inputs/fptest.py`).
  Reducing this allow-list is the f64-hardening progress metric.
- **Mechanised equivalence rounds 1-9 closed.** Round 9 (`mul_f64`)
  is at 2-of-3 helpers strength — see "Round-9 mul strengthening"
  below.
- **PR #60** (`feat/lampe-literate-comment-blocks`) migrates the
  round-6 `add_f32_equivalence` to lampe-literate's option-3
  directive grammar with external `add_f32_{preamble,equivalence}.lean`
  files. CI all 19 checks green; awaits Jesse skim/merge.
- **3 dependabot PRs** (#26, #30, #32) — auto-merge armed, branches
  updated against main; will clear as CI runs.

## Priority order

### 1. Merge PR #60 (lampe-literate option-3 worked example)

https://github.com/jeswr/noir_IEEE754/pull/60

CI all green; the only remaining gate is Jesse's skim. Once merged,
the f32-add proof directives + external `.lean` files become the
template for the rest of the migration.

### 2. Migrate IEEE 754 rounds 7-9 to lampe-literate

After PR #60 merges, remaining rounds need the same treatment:

| Round | Theorem | Source `.nr` | Owns |
| ----- | ------- | ------------ | ---- |
| 7a    | `sub_f32_equivalence` | `ieee754/src/float32/sub.nr` (or current location) | TBD |
| 7b    | `add_f64_equivalence` | `ieee754/src/float64/add.nr` | TBD |
| 8     | `sub_f64_equivalence` | `ieee754/src/float64/sub.nr` | TBD |
| 9     | `mul_f64_equivalence` | `ieee754/src/float64/mul.nr` | TBD |

For each:

1. Locate the workspace `proofs/Ieee754/.../*.lean` file.
2. Identify the proof body (`theorem ... := by ...`) and its
   preamble (imports, `open` blocks).
3. Copy the proof body into
   `ieee754/proofs/<basename>_equivalence.lean` (Unicode preserved).
4. Copy the preamble into
   `ieee754/proofs/<basename>_preamble.lean`.
5. Add `// LAMPE-LITERATE preamble:` and `// LAMPE-LITERATE proof:`
   directive lines beside the optimised function in the matching
   `.nr` file.
6. From the workspace root: `lampe-literate build
   circuits/noir_IEEE754/ieee754/src/float<32|64>/<name>.nr` —
   verify `lake build` greens.
7. From `ieee754/`: `nargo check` — verify directives stay
   ASCII-only.
8. Delete the workspace `.lean` source.
9. Open one PR per round.

After all four rounds migrate, delete the workspace
`proofs/Ieee754/` tree entirely; update
`equivalence-spike-2026-05-04.md` to point at the new layout.

### 3. Round-9 mul Lean strengthening (tasks ii + iv)

Round 9 (`mul_f64_equivalence`) closes through a shared skeleton
with three divergence helpers. Two of three are at literal-loop
strength; one is still shared between optimised + reference paths.

| Helper | Strength | Notes |
| ------ | -------- | ----- |
| `rneDecision` | strong | round-9-original, single-divergence-parameter form |
| `shiftRightStickyU128` | **strong** | task iii closed 2026-05-04 — all 4 cross-word cases of the `Nat`-level spec match (`shift = 0` / `< 64` / `64-127` / `≥ 128`) |
| `clzDenormalMantissa64` | weak | task iv — pending |
| `leadingBitPos128` | weak | task ii — pending |

See `todos/round9-mul-reference-strength.md` (workspace) for the
methodology gotcha. Do **task iv first** (denormal-mantissa CLZ,
32 leaves, contained overflow on bits 52-63) before task ii
(128-bit leading-bit-search, 256 leaves).

### 4. f64-hardening — reduce `KNOWN_BAD_TESTS_BY_ROUNDING`

The allow-list at `scripts/noir_ieee754_inputs/fptest.py` is the
visible progress metric. Each PR that fixes a circuit bug should
delete one or more entries. The targets are denormal handling,
underflow rounding, and a small set of subtle exponent-bias bugs.
Use `scripts/run_tests.py --suite f64 --emit-failed-tests` to
find current failures.

### 5. Sub-repo discipline

Every change should:

- carry a Conventional Commit message;
- pass the post-commit roborev review;
- not bypass `--no-verify`;
- run `nargo check` from `ieee754/` before pushing;
- run `python3 scripts/run_tests.py --suite f32` (and `--suite
  f64` for f64-touching changes);
- update `gate_counts.json` if circuit gate counts change (CI
  comments the diff on the PR).

## Open dependabots (auto-merging)

| # | Subject |
| - | ------- |
| 26 | semantic-release 25.0.2 → 25.0.3 |
| 30 | undici + @actions/http-client multi-bump |
| 32 | handlebars 4.7.8 → 4.7.9 |

Auto-merge is armed; branches updated against main 2026-05-05.
Will clear as CI runs.

## Known limitations

- **`gate-count-pr` workflow on main** can fail to push gate-count
  updates because the `main` branch ruleset blocks the bot. See
  workspace `STABILISATION-TODOS.md` for the planned fix
  (workflow opens an auto-merge PR rather than direct-pushing).
- **Square root + comparison** ops are unit-tested only — no IBM
  FPgen coverage. Adding FPgen coverage for `sqrt` is queued in
  `IMPLEMENTATION_PLAN.md`.
- **FMA + remainder** not implemented. Out of scope for the
  current paper; flag for a future PR if needed.

## Out of scope (the paper handles these)

- BBS+ / SD-JWT integration. The IEEE 754 circuits are a building
  block; the paper composes them with VC commitment shapes.
- ZKP-SPARQL evaluation logic. That's `circuits/sparql_noir`.
- Paper writing. That's the workspace `paper/` tree.
