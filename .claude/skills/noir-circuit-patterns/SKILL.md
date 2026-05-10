---
name: noir-circuit-patterns
description: Patterns and gotchas for writing Noir circuits that implement SPARQL primitives over committed RDF graphs. Use when implementing BGP matchers, joins, filters, projections, or hashing-to-field strategies; when sizing constraint budgets; when laying out public inputs that bind to a commitment scheme; or when interfacing nargo / Barretenberg (bb) tooling. Always confirm syntax against the noir-lang context7 docs (/noir-lang/noir) before writing code.
---

# Noir circuit patterns for ZKP-SPARQL

Reusable patterns for the Noir circuits that prove correct SPARQL
evaluation over committed RDF graphs. These are starting points;
verify any specific syntax via the `/noir-lang/noir` context7 docs
before pasting into code.

## Always-do

- **Pin the toolchain.** `Nargo.toml` declares `compiler_version`.
  README of the circuit dir documents the matching `bb` version.
- **Query context7 first.** Before guessing a stdlib function name, a
  trait bound, or a generic syntax, run
  `mcp__context7__query-docs` against `/noir-lang/noir`. The Noir
  language has evolved fast; recall is unreliable.
- **Document `main`'s public inputs.** A commented-out line per
  public input naming what it commits to and why.
- **Test every primitive.** Noir supports `#[test]` in source — use
  it. Cover an accept case and at least one reject case.
- **Comment constraint cost.** When writing a non-trivial gadget,
  estimate where the dominant cost lies (hashing? bit-decompositions?
  range proofs?) and note it.

## Triple commitment patterns

The credential graph is committed before the circuit consumes it. The
two natural shapes:

- **Per-triple Pedersen / Poseidon hash, accumulated into a Merkle
  tree.** The prover supplies a triple + a Merkle path; the circuit
  verifies the path against a public root. Best when triples are
  accessed sparsely (e.g. BGP with few patterns).
- **Sorted sequence committed via a single sponge hash.** The prover
  supplies the full ordered triple list; the circuit re-hashes and
  asserts equality with a public commitment. Best when most of the
  graph is touched anyway, or when sortedness is needed downstream
  (e.g. for sort-merge joins).

Either way, **domain-separate** the hash inputs (e.g. tag a triple
hash with a `b"triple-v1"` prefix) and document the tag in a
single table shared with `vc-cryptography`.

## BGP matching

For a triple pattern `(s ?x p o ?y)` with two variables:

1. Extract the candidate triple from the committed graph (Merkle
   path or sponge index).
2. Constrain the constants (`s`, `p`) to equal the corresponding
   triple positions.
3. Bind the variables (`?x`, `?y`) to the remaining positions.
4. The output is a witness binding for downstream operators.

Multi-pattern BGPs are joins over the per-pattern bindings — see
joins.

## Joins

- **Sort-merge** when both sides are sorted on the join key (cheap
  per-row, but needs a sort proof or pre-sorted commitment).
- **Lookup-table / set-membership** when one side is small and can be
  pre-loaded as a polynomial commitment.
- **Hash join** is rarely the right choice in-circuit because
  building a hash table burns constraints linear in the build side.

For a paper at the BGP level, sort-merge against a graph already
committed as a sorted sponge is usually the right default.

## Filters

`FILTER (?x > 5)` and friends decompose into:

- a comparison gadget (use `std::cmp` where it exists; else a
  bit-decomposition).
- a conditional select that drops the row.

Comparisons on field elements need a bit-decomposition unless the
values are known small. Document the bit budget in a comment.

## Projection / DISTINCT

Projection is free; DISTINCT requires either:

- a sort + adjacent-deduplicate pass, or
- a multi-set hash (commit to the unordered solution multi-set and
  argue equality).

The multi-set hash route plays nicely with Barretenberg's native
field; prefer it unless the verifier explicitly wants the result
ordered.

## Public input layout — the contract

Every `main` exports a precise public-input layout:

```
fn main(
    // -- public --
    graph_commitment: Field,        // Pedersen / Poseidon root over committed triples
    query_commitment: Field,        // commitment to the SPARQL query the prover claims to evaluate
    result_commitment: Field,       // commitment to the disclosed result multi-set
    // -- private --
    graph_witness: ...,             // triples + Merkle paths
    binding_trace: ...,             // intermediate operator bindings
    // ...
) -> pub Field {
    // verify graph commitment, evaluate, re-commit result, equality-assert
}
```

The exact shape evolves; what's invariant is that the verifier sees
*only* the three commitments + the result.

## Tooling cheats

- `nargo check` — fast type-check.
- `nargo test` — runs `#[test]` functions.
- `nargo execute` — run a circuit with a `Prover.toml` and inspect
  intermediate witnesses; useful for debugging before proving.
- `bb prove` / `bb verify` — proving / verifying via Barretenberg.
- `nargo info` — constraint count and gate breakdown; the budget
  document.

## When to escalate

If a primitive doesn't fit the constraint budget, **escalate to
`sparql-semantics` and the main session before optimising blindly** —
the right move may be to refine the supported fragment, not to
golf the gadget.

## See also

- `noir-optimisation` — cost model + decision rules. Read before
  spiking any `unconstrained + verified` primitive: §2 has the
  profitability conditions, §3 the bit-decomposition vs dynamic-shift
  trade-off, §8 the pre-spike checklist.
