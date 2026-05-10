# noir_IEEE754 Claude Code config

Scaffolding for working on this sub-repo in isolation (i.e. opening
Claude Code with `circuits/noir_IEEE754` as the cwd, rather than the
workspace root).

## Contents

- `agents/` — three personas lifted from the workspace `.claude/agents/`:
  `noir-circuits` (circuit work), `lean-proofs` (Lean equivalence
  proofs), `workspace-devops` (CI / toolchain). The `description`
  fields still mention the wider ZKP-SPARQL paper context — that is
  intentional, since this sub-repo is a building block for that
  paper.
- `skills/` — seven skills relevant to circuit + proof work in this
  repo: `noir-circuit-patterns`, `noir-optimisation`,
  `lean-proof-patterns`, `tdd`, `diagnose`,
  `git-guardrails-claude-code`, `dry-extract-on-second-use`. Skills
  scoped to SPARQL / VC / paper concerns are deliberately omitted.
- `settings.json` — permissions for `nargo` / `bb` / `lake` /
  `lean` / `elan` / `lampe-literate` / `python3` / `gh` (read-only
  PR/issue queries) / `roborev` and the standard git surface.

## Sync with the workspace

These files are **copies**, not symlinks. If the workspace
`.claude/skills/<name>/` evolves, those edits do not propagate here
automatically — re-copy from the workspace as needed.

## Where to start when picking up work

Read in order:

1. `../CLAUDE.md` (sub-repo conventions)
2. `../HANDOFF.md` (current outstanding work)
3. `../IMPLEMENTATION_PLAN.md` (operation-coverage matrix)

Don't edit `../CONTRIBUTING.md` lightly — Conventional Commits + the
post-commit roborev hook are load-bearing for the release pipeline.
