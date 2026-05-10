---
name: dry-extract-on-second-use
description: Don't Repeat Yourself, Jesse-style — first-time-ever logic stays inline; second-occurrence of the same logic across packages or sub-repos becomes an extracted shared module (an `sdks/<name>` sub-repo or a workspace-internal helper). Use when reviewing a diff that introduces a near-duplicate of existing code, when noticing a copy-paste during implementation, or when deciding whether to inline vs extract a helper. Stops premature abstraction (one occurrence) and stops accumulated debt (third occurrence).
---

# DRY — extract on the *second* occurrence, not the first

Jesse's standing rule: **the second time the same logic appears across
packages or sub-repos, extract it.** Not the first (premature
abstraction is worse than duplication), and not the third (by then the
copies have already drifted).

## When this skill applies

- Reviewing a diff (yours or a teammate's) that introduces a
  near-duplicate of code already living somewhere else in the
  workspace.
- Implementing a feature and noticing you're typing something that
  feels like code you wrote in another sub-repo recently.
- Deciding whether a one-off helper deserves to live in `sdks/` or
  stay private.

## The discipline

### Count occurrences honestly

- **One occurrence?** Leave it inline. You don't yet know what the
  abstraction should be.
- **Two occurrences across packages or sub-repos?** Extract.
  - If the logic is a pure function with stable inputs/outputs → a
    helper module in a sub-repo under `sdks/`.
  - If the logic is a circuit primitive used by two circuits → a Noir
    library.
  - If the logic is a Lean lemma proved twice → a single `Lemmas.lean`
    module both crates depend on.
- **Three occurrences?** You've waited too long. Extract immediately
  and back-fill the migration in the same PR.

"Across packages" is the load-bearing phrase. Two copies *inside the
same package* are usually fine — local repetition is cheap. The
expensive duplication is across module boundaries that won't be
maintained together.

### Don't generalise on extraction

When you extract, capture the **two existing call-sites' shape**, not
an imagined third call-site's shape. If a third call-site later needs
something different, generalise *then*. The wrong abstraction is
worse than no abstraction.

### Sub-repo discipline (this workspace)

A new shared module typically becomes its own sub-repo:

1. Create `sdks/<name>/` with its own `.git`, README, and toolchain
   pinning.
2. Run `gh repo create jeswr/<name> --private`.
3. Push the initial commit to the new remote.
4. Add an entry to `.subrepos.json` so `bootstrap.sh` rehydrates it
   after a fresh clone.
5. In each call-site, depend on the new sub-repo (Cargo path, npm
   `file:`, lake require, or whatever the language wants).

The bootstrap entry is **mandatory** — without it, anyone cloning
fresh gets a broken workspace.

### Anti-patterns

- **Premature abstraction.** "I might need this elsewhere" — don't.
  Wait for the second occurrence.
- **Copy-paste then "I'll DRY it later".** Later doesn't come.
  Either inline the second occurrence (rejecting it from the diff)
  or extract immediately.
- **Generalising on extraction.** Adding configuration knobs the
  current call-sites don't need. The shape is what the call-sites
  use today.
- **Extracting into the wrong layer.** A SPARQL semantics helper
  shared between `noir-circuits` and `lean-proofs` doesn't go into a
  Noir library or a Lean library — it goes into a third place
  (probably the paper's machine-readable spec) that both depend on.

## Reference

- Jesse's auto-memory: "Extract repeated logic into SDKs — second
  occurrence of the same logic across packages = extract to sdks/.
  Don't tolerate copy-paste."
