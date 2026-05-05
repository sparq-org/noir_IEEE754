# noir_IEEE754 — Claude project notes

Read this at the start of every session. Captures the conventions
and constraints for working in this repo.

## What this is

IEEE 754 floating-point arithmetic in [Noir](https://noir-lang.org/) —
both binary32 (float) and binary64 (double), with all five rounding
modes, NaN / infinity / denormal handling, and an MPFR-backed
reference oracle for the IBM FPgen test suite.

The repo's two halves:

1. **The Noir library** — `ieee754/src/`, optimised circuits ready
   for use as zk inputs. Comparison, conversion, arithmetic.
2. **The Lean equivalence proofs** — `ieee754/proofs/` (after PR #60
   merges) plus, for now, the workspace `proofs/Ieee754/` tree.
   Each proof is a Lean theorem stating "optimised circuit ≡
   literal-spec reference". Built via [lampe-literate](https://github.com/jeswr/lampe-literate)
   as the build orchestrator + Lampe / mathlib / ProvenZk for the
   Lean side.

See `README.md` for the user-facing overview, `IMPLEMENTATION_PLAN.md`
for the operation-coverage matrix, `CONTRIBUTING.md` for commit-message
conventions, and `HANDOFF.md` for remaining work.

## Stack

- **Noir 1.0.0-beta.16** (currently) — circuits compile + run on
  beta.14 / 15 / 16; CI matrices all three. Use the official
  standard library.
- **nargo** for build / test / format. Always invoke from
  `ieee754/` (the Nargo package root).
- **Python 3.11+** for the test harness (`scripts/run_tests.py`,
  the IBM FPgen-driver, the MPFR-backed `reference.py`). Deps in
  `scripts/requirements.txt`.
- **Lean 4 + mathlib + Lampe + ProvenZk** for the equivalence
  proofs — orchestrated via lampe-literate. The exact revs are
  pinned in the workspace's `lampe-literate.toml`.

## Two soundness levels

This library has two layers of correctness, and a contributor needs
to know which they're touching:

1. **End-to-end (testfloat) soundness** — `scripts/run_tests.py`
   runs every IBM FPgen test case through the optimised circuit and
   compares against MPFR. As of 2026-05-04 the f32 surface is
   green; f64 has known-bad cases tracked in
   `KNOWN_BAD_TESTS_BY_ROUNDING`. **Reducing that allow-list is
   the f64-hardening progress metric.**
2. **Mechanised equivalence** — Lean proofs that the optimised
   circuit computes the same function as the literal-spec reference.
   Rounds 1-9 closed at varying strength levels (some hand-mirrored
   models, some with the reference port re-extracted). See
   `proofs/Ieee754/equivalence-spike-2026-05-04.md` in the workspace
   for the methodology log.

A bug found by testfloat may not violate the equivalence proof
(e.g. if the bug exists in both optimised and reference). A
mechanised-equivalence failure may not visibly fail any IBM test
(if the test corpus doesn't exercise the divergence). Both layers
are needed.

## Working conventions

- **Commit-message convention is Conventional Commits.** Drives
  semantic-release automated versioning. See `CONTRIBUTING.md` for
  scopes (`feat`, `fix`, `docs`, `chore`, ...). British English in
  prose; code identifiers follow Noir / Rust conventions.
- **Roborev reviews every commit.** Post-commit hook is already
  installed in this repo (`.git/hooks/post-commit`). Don't bypass
  with `--no-verify`.
- **All circuit changes need a testfloat run before claiming
  correctness.** `python3 scripts/run_tests.py --suite f32`
  (and / or `--suite f64`). The suite takes a few minutes; CI
  runs it on every PR via the `ieee754` matrix.
- **Equivalence-proof changes need `lampe-literate build`.** Once
  PR #60 has merged, the f32-add proof lives at
  `ieee754/proofs/add_f32_*.lean` and is built via
  `lampe-literate build ieee754/src/float32/add.nr` (run from the
  workspace root so the workspace `lampe-literate.toml` resolves).
  Until then, the legacy workspace `proofs/Ieee754/` tree is the
  source of truth for unmigrated rounds.
- **Use context7 MCP for Noir / Lean lookups:**
  - Noir: `/noir-lang/noir`
  - Lean 4: `/leanprover/lean4`
  - mathlib: `/websites/leanprover-community_github_io`
- **Branch protection on `main` requires `copilot-review-posted`
  SUCCESS.** When marking a PR ready, GitHub fires a fresh check
  on the new HEAD; if Copilot/roborev hasn't posted yet, push an
  empty commit + queue another roborev review.
- **No backwards-compat shims.** Library is pre-1.0; breaking
  changes are fine — bump the version per Conventional Commits
  rules.

## Repo layout

```
ieee754/
├── Nargo.toml              — package manifest
├── src/
│   ├── float32/            — f32 circuits (add, sub, mul, div, sqrt, cmp)
│   ├── float64/            — f64 circuits (same)
│   └── lib.nr              — public surface
├── proofs/                 — Lean equivalence proofs (after PR #60)
└── reference/              — literal-spec reference Noir (after PR #60+)

ieee754_unit_tests/         — unit tests (run via nargo)
test_packages/              — multi-package test scaffolding

scripts/
├── run_tests.py            — IBM FPgen driver
├── noir_ieee754_inputs/
│   ├── reference.py        — MPFR-backed oracle
│   └── fptest.py           — KNOWN_BAD_TESTS_BY_ROUNDING allow-list
├── benchmark_gates.py      — gate-count tracking
└── requirements.txt        — Python deps

bench/                      — gate-count snapshots over time
.github/workflows/          — CI: lint + test + gate-counts + copilot-review
```

## What this repo does NOT contain

- The lampe-literate tool itself (separate repo:
  https://github.com/jeswr/lampe-literate).
- Any SPARQL / VC / paper concerns. Those live in the workspace.

## Bootstrap from scratch

```sh
git clone https://github.com/jeswr/noir_IEEE754.git
cd noir_IEEE754
# Noir
nargo --version                                # need 1.0.0-beta.14+
cd ieee754 && nargo check && cd ..
# Python harness
python3 -m venv .venv && source .venv/bin/activate
pip install -r scripts/requirements.txt
python3 scripts/run_tests.py --suite f32       # ~few minutes
# Equivalence proofs (after lampe-literate#1 + noir_IEEE754#60 land)
# Run from the workspace root so workspace lampe-literate.toml resolves:
cd ../..
lampe-literate build circuits/noir_IEEE754/ieee754/src/float32/add.nr
```

The post-commit roborev hook is installed automatically by
`scripts/bootstrap.sh` at the workspace level; standalone
contributors can install it manually:

```sh
cat > .git/hooks/post-commit <<'HOOK'
#!/bin/sh
ROBOREV=$(command -v roborev 2>/dev/null)
[ -x "$ROBOREV" ] && "$ROBOREV" post-commit 2>/dev/null
exit 0
HOOK
chmod +x .git/hooks/post-commit
```
