---
name: lean-proof-patterns
description: Lean 4 + mathlib patterns for stating and proving the soundness / completeness theorems that bridge the ZKP-SPARQL paper's circuit semantics and its standard-SPARQL semantics. Use when defining RDF / SPARQL types in Lean, stating operator correctness theorems, choosing tactics, structuring a proof crate, or pinning a Lean toolchain. Always confirm tactic / mathlib lemma names via the leanprover context7 docs before writing.
---

# Lean proof patterns for ZKP-SPARQL

Patterns for the Lean 4 proofs that establish correctness of the
circuit-level SPARQL semantics against the standard algebra. Verify
specific syntax against `/leanprover/lean4` and
`/websites/leanprover-community_github_io` via context7 before
writing.

## Always-do

- **Pin the toolchain.** Every proof crate has a `lean-toolchain`
  pinning an exact Lean version. Mathlib pinned via lake to a known
  revision.
- **Query context7 first** for tactic / lemma names. Lean / mathlib
  evolve quickly; the recall failure mode is "tactic exists with
  slightly different name", and the compiler error is unhelpful.
- **Stub theorems with `sorry` and a comment** when blocked. Track
  `sorry` count in CI; treat any new `sorry` as a debt entry.
- **Mirror the paper's theorem numbering.** If the paper says
  Theorem 3.2, the Lean theorem has a comment `-- Paper: Theorem 3.2`
  and a name like `theorem operator_correct_3_2`.
- **Prefer mathlib tactics over hand-rolled term mode.** First-line
  choices: `simp`, `omega`, `decide`, `linarith`, `aesop`, `exact?`,
  `apply?`.

## Crate skeleton

```
proofs/
├── lean-toolchain
├── lakefile.toml
└── ZkpSparql/
    ├── Rdf/
    │   ├── Graph.lean            -- RDF graph model
    │   └── Canonicalisation.lean -- URDNA bridge
    ├── Sparql/
    │   ├── Algebra.lean          -- standard PAG algebra
    │   └── Operators.lean        -- per-operator semantics
    ├── Circuit/
    │   └── Semantics.lean        -- formalisation of circuit semantics
    └── Correspondence/
        └── Soundness.lean        -- operator-by-operator correctness theorems
```

Adapt as the paper's structure firms up — this is a starting shape.

## Stating a correspondence theorem

Canonical shape:

```lean
namespace ZkpSparql.Correspondence

/-- Soundness: every solution the circuit accepts is a solution of
    the standard SPARQL algebra. -/
theorem op_sound
    {G : Rdf.Graph} {q : Sparql.Pattern} {μ : Sparql.Solution} :
    Circuit.Semantics.Accepts G q μ →
    μ ∈ Sparql.Algebra.eval G q := by
  sorry

/-- Completeness: every standard solution is accepted by the circuit. -/
theorem op_complete
    {G : Rdf.Graph} {q : Sparql.Pattern} {μ : Sparql.Solution} :
    μ ∈ Sparql.Algebra.eval G q →
    Circuit.Semantics.Accepts G q μ := by
  sorry

end ZkpSparql.Correspondence
```

Keep this shape uniform across operators so the paper can table them.

## Modelling RDF in Lean

- Triples as a structure of three `Term`s (where `Term := IRI |
  Literal | BlankNode`).
- Graphs as a `Multiset Triple` (or `Finset` if blank-node
  canonicalisation is folded in upstream).
- Canonicalisation is a separate function that takes a graph and
  returns a deterministic encoding; the correspondence theorems
  quantify over canonicalised graphs.

## Tactic notes

- `decide` works only on decidable propositions over finite types —
  great for small concrete examples, useless for the soundness
  meta-theorem.
- `aesop` is good for proof search over inductive predicates;
  configure a custom rule-set for SPARQL operators if `aesop` keeps
  needing the same hints.
- For arithmetic on cardinalities / sizes, `omega` handles linear
  integer goals; `nlinarith` for non-linear; `positivity` for
  non-negativity goals.
- `simp` lemmas about your own definitions: tag with `@[simp]`
  sparingly — over-tagging makes goals diverge.

## Pinning mathlib

`lakefile.toml`:

```toml
[[require]]
name = "mathlib"
git = "https://github.com/leanprover-community/mathlib4"
rev = "<exact-sha>"
```

Bump revs deliberately — never rely on `master`. Document the bump
rationale in the commit message.

## When to escalate

If a soundness proof is blocked because the circuit and the standard
semantics genuinely *don't* agree (not just a missing lemma),
**escalate to `sparql-semantics` and the main session immediately**.
The fix is in the spec / circuit, not in the proof.
