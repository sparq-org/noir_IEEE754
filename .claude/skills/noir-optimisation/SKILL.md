---
name: noir-optimisation
description: >-
  Cost model and optimisation reference for Noir circuits. Use when sizing
  constraint budgets, deciding whether to push work into an `unconstrained`
  Brillig hint with an in-circuit verifier, comparing bit-decomposition vs
  dynamic-shift relations, reading `nargo info` / `bb gates` output, or
  weighing ACIR-opcode against Expression-Width regressions. Companion to
  `noir-circuit-patterns` — that skill covers SPARQL-primitive shapes;
  this one covers which shape wins after measurement. Always cite the
  primary sources here before claiming a saving — Noir docs
  (`/noir-lang/noir`), the Aztec profiler doc, and the in-repo `bench/`
  ledgers — intuition has misfired on this codebase before (PR #37).
---

# Noir optimisation — cost model + decision rules

A reference for someone already writing Noir circuits in this workspace.
Optimisation in Noir is empirical: measure with `nargo info` /
`benchmark_gates.py` / `benchmark_unconstrained.py` *before* declaring a win.
The 2026-05-03 round-1 of `unconstrained_ops` for IEEE 754 had us predict an
ACIR-opcode + Width win for `count_leading_zeros_u64_verified`; PR #37
measured **both regressing** in both isolated and composed regimes, and the
follow-up bit-decomposition spike (`c0f433d`, reverted in `63d0b95`) regressed
twice as hard again. Don't trust the textbook shape; measure.

For *which* primitive to write — BGP matchers, joins, filters — see
`noir-circuit-patterns`. This skill picks up where that one stops: given a
candidate gadget, does the proposed implementation beat the in-circuit-spec
baseline?

## 1. Cost model — three numbers, and which one to optimise

`nargo info` reports three quantities per function. Each means a different
thing and each is optimised differently.

### ACIR opcodes

ACIR (Abstract Circuit Intermediate Representation) is Noir's IR. An ACIR
*opcode* is one of six variants; they are not all equally expensive [1]:

- **`AssertZero`** — adds a polynomial constraint `P(w) = 0` over witnesses.
  This is the constraint generator; most arithmetic boils down to one or
  more of these. Its cost in backend gates depends on the polynomial's
  expression width (see below).
- **`BlackBoxFuncCall`** — a backend gadget (`range`, `AND`, `XOR`,
  `keccak256`, `pedersen`, `poseidon`, `sha256`, `blake2s`, `blake3`,
  `ecdsa`, `recursive_verify`, ...) [2]. *These can be the cheapest or the
  most expensive opcode in a circuit depending on the backend* — see §5.
- **`MemoryOp`** / **`MemoryInit`** — atomic read/write on a memory block
  and its initialisation. Used for in-circuit array indexing.
- **`BrilligCall`** — invokes Brillig (unconstrained) bytecode. **Free at
  proof time** (see §1.3); only the constrained verifier around it costs.
- **`Call`** — invokes a separately-compiled circuit; for recursion / proof
  composition.

`nargo info` reports the count of ACIR opcodes in the constrained portion of
each function (Brillig bytecode is reported separately). The Noir profiler
doc is explicit: *"the number of ACIR opcodes is an approximation of proving
performance. Actual performance depends on how the proving backend
interprets and translates these opcodes into proving gates"* [3].

### Expression Width

The `Expression Width` column of `nargo info` (printed as
`Bounded { width: N }` when not specified by the backend) bounds **the
maximum number of witness wires that may appear in a single `AssertZero`
gate** [4]. Backends like Barretenberg's UltraPlonk are width-4 PLONKish
arithmetisations: every gate has at most 4 wires, so a wide expression must
be split across multiple gates [5].

The `Expression Width` reported per-function is the *sum of witness counts
across all `AssertZero` opcodes in that function* — it is a closer proxy for
backend gate count than the raw ACIR opcode count is, because it accounts
for the cost of expanding wide constraints into width-4 gates. **This is
the metric that flipped sign in PR #37 — see §2.3.**

The flag `--expression-width N` (default 4 for the Barretenberg backend)
asks the SSA compiler to keep gate widths bounded; some passes still produce
wider expressions and get split downstream [4].

### Brillig opcodes

Brillig is Noir's unconstrained VM. Brillig opcodes execute *only at
witness-generation time*; they contribute zero cost to the proof and zero
cost to the verifier. *"Brillig: 538"* in `nargo info` is **not** a
proving cost — it is a hint for execution time, to flag witness generators
that may dominate the prover wall-clock (rare; the proof itself is the
bottleneck) [6, 7]. Misreading Brillig opcode counts as a cost is the most
common rookie mistake on this codebase.

The Noir profiler doc states the trade-off plainly: *"Rewriting constrained
operations with unconstrained operations can reduce ACIR opcodes, leading
to shorter proving times, but it may increase Brillig opcodes, resulting
in longer execution times. … This trade-off is often acceptable because
proving speeds are typically the main bottleneck"* [7].

### Per-backend translation

ACIR is a portable IR; backends translate it to their own gate system:

- **Barretenberg UltraHonk** — width-4 PLONKish + lookups (Plookup). An
  `AssertZero` gate maps to one or more 4-wire arithmetic gates depending
  on its expression width. `BlackBoxFuncCall::range` lowers to a lookup
  table with a fixed setup cost, so for small circuits range checks
  dominate backend gates even when their ACIR opcode count is small [3].
- **Plonk / TurboPlonk variants** — narrower gates, no lookups; the same
  ACIR opcode lowers to more gates than under UltraPlonk [8].
- The portable answer to *"how many gates does this cost?"* is to run
  `noir-profiler gates --artifact-path target/program.json --backend-path bb`
  with `--include_gates_per_opcode` and compare the flame graph to the ACIR
  opcode breakdown [9]. ACIR-only optimisation can mislead.

For this workspace's targets (Barretenberg UltraHonk via `bb`):

- **Width is the primary metric** — lower Width almost always lowers wall-clock
  proving time. PR #28 in `noir_XPath` swapped a baseline (`Width=1756`,
  ACIR=34) for an unconstrained-hint variant (`Width=714`, ACIR=506) — a
  -59% Width / +14× ACIR trade — and the call site swap was kept on the
  basis that Width is what the prover actually pays for [10].
- **ACIR opcode count is the secondary metric**, useful for
  back-of-envelope sizing and for comparing two implementations whose
  Widths are similar.
- **Backend gates** (`bb gates`) are the ground truth — but they vary with
  the backend version, so don't pin decisions on them without the
  toolchain pinned in `Nargo.toml`.

## 2. The `unconstrained + verified` pattern — when it pays

Textbook claim: *compute expensively in Brillig, verify cheaply in ACIR*.
The Noir docs offer the canonical example — `u64_to_u8` decomposition,
65 ACIR → 33 ACIR by computing the bytes in Brillig and asserting
`sum_i bytes[i] * 2^(56-8i) == num` in the verifier [6]. **This is a 49%
ACIR cut for a verifier that does only multiplications by *constants* and
one Field equality.** The shape generalises poorly.

### 2.1 The actual condition for a win

`cost(verifier) < cost(in-circuit-spec)`. The verifier must avoid the three
cost sinks that defeat constant-folding:

- **(a) data-dependent shifts.** `value >> count` where `count` is a
  witness lowers via `remove_bit_shifts` [11] to a runtime decomposition
  that scales linearly with the maximum shift amount. A shift by a
  *constant* is folded; a shift by a witness is not.
- **(b) data-dependent indexing.** `arr[i]` where `i` is a witness lowers
  to `MemoryOp` plus a range check on `i`; a constant index is folded out
  entirely.
- **(c) non-foldable surrounding context.** A loop with a constant bound
  and no witness reads is unrolled by the `unrolling` SSA pass and then
  constant-folded; the same loop with a witness-dependent bound is *not*
  unrolled.

### 2.2 Patterns where the unconstrained pattern wins reliably

- **Integer division.** Witness `q, r`; verify `q * d + r == n`,
  `r < d`. Verifier is one `AssertZero` plus one range check.
- **Square root.** Witness `s`; verify `s * s <= n < (s + 1) * (s + 1)`.
  This is the form Noir docs give as the headline example [6].
- **Merkle inclusion.** Witness the path; recompute the root from the
  leaf + path with a constant-arity hash gadget, equality-assert against
  the public root.
- **Byte / bit decomposition with constant stride.** As in the Noir doc's
  `u64_to_u8` example: the recombination is `sum_i x_i * 2^(stride*i)` —
  every shift amount is a *compile-time constant* [6].

### 2.3 Patterns where it loses — the PR #37 case study

`count_leading_zeros_u64_verified` was the predicted win that reversed.
The verifier shape was: witness `count`; assert `count <= 64`; if
`count == 64` then `value == 0`; else assert bit `(63 - count)` of `value`
is set and `value >> (count + 1) == 0`. The **dynamic right-shift
`value >> (count + 1)`** is the cost driver — the shift amount is a
witness, so cost (a) above bites.

Measured numbers (`gate_counts.json`, `primitive_benchmarks` block, commit
`b5dfae9` for the merged variant; commit `1a92ded` for the spike) [12, 13]:

| Variant                                       | Width | ACIR |
|-----------------------------------------------|------:|-----:|
| `clz_u64_isolated_binsearch_baseline`         |    96 |   17 |
| `clz_u64_isolated_verified` (merged)          |   112 |  100 |
| `clz_u64_isolated_verified_bitdecomp` (spike) |   270 |  203 |
| `clz_u64_composed_binsearch_baseline`         |   133 |   34 |
| `clz_u64_composed_verified` (merged)          |   164 |  100 |
| `clz_u64_composed_verified_bitdecomp` (spike) |   322 |  220 |

Three observations:

1. The dynamic-shift verifier is **+17 Width / +83 ACIR** isolated vs the
   6-step binary-search baseline, and **+31 Width / +66 ACIR** composed.
   The verifier's data-dependent shift is what the binary-search baseline
   *avoids* — six static shift-by-constant operations are constant-folded
   into a width-bounded comparison chain.
2. The bit-decomposition spike (witness `bits[64]` + one-hot `is_leading`
   + cumulative-prefix flag) regressed even harder. It has no
   data-dependent shift, but it has 64 boolean range checks plus the
   `sum_i bits[i] * 2^i == value` constraint, which is itself a wide
   expression. **Bit-decomposition is not a free win; it just moves the
   cost from a shift opcode into a row of range checks plus a wide
   AssertZero.**
3. The composed regime adds roughly the same delta as the isolated regime
   (~+30 Width / ~+66 ACIR), so the regression is *not* an artefact of
   constant-folding the lone call: a real call site loses too.

The merged primitive in PR #37 lives in the public API for two reasons:
(i) Lampe extraction needs a stable target name regardless of which
relation eventually wins; (ii) future helpers may compose with it under
constant inputs where the verifier *is* foldable. **No call site has
been swapped.**

### 2.4 Heuristic — when to spike vs when to skip

Spike a `_verified` variant only when **all three** of these hold:

1. The in-circuit spec contains an obviously expensive sub-computation
   (a CLZ via 6 conditional shifts, a hash with witness-driven input
   length, a division, ...).
2. The proposed verifier relation can be expressed *without* a
   data-dependent shift, a data-dependent index, or a >100-element loop
   over witnesses.
3. There is a Lean obligation in `proofs/<crate>/` that pins the
   relation's uniqueness — otherwise the unconstrained hint is unsound
   and roborev will find it (PR #36's `pub unconstrained` hint was
   crate-privatised in `c7ecb8a` for exactly this reason).

If any of these fails, write the in-circuit spec directly and don't spend
the round.

## 3. Bit-decomposition vs dynamic shift — the canonical trade-off

Two relations come up repeatedly when verifying an integer-shape claim:

### 3.1 Dynamic shift

```
let probe : u32 = (value >> top_bit_pos) & 1;       // (a) — data-dependent
assert(probe == 1);
let above : u32 = value >> (top_bit_pos + 1);       // (a) again
assert(above == 0);
```

**Cost.** The SSA pass `remove_bit_shifts` lowers each runtime shift to a
loop that constructs the bit-extraction by case analysis on the shift
amount [11]. For a `uN` operand and a max shift of `M`, each runtime shift
costs O(M) constraints on a worst-case-shift basis. Two shifts plus the
ambient `AssertZero`s sit at the **+~80 ACIR / +~17 Width** point measured
in §2.3 for `N=64, M=64`.

### 3.2 Bit decomposition

```
// witness `bits: [Field; N]`
for i in 0..N { assert(bits[i] * (bits[i] - 1) == 0); }   // each is boolean
let mut sum : Field = 0;
for i in 0..N { sum += bits[i] * (1 << i); }              // constants
assert(sum == value);
// ... plus one-hot leading-bit indicator + monotone-prefix flag for CLZ.
```

**Cost.** N booleanity asserts plus one wide `AssertZero` for the
recombination. The booleanity asserts are cheap individually but the
recombination expression has N witness terms, so it splits across
`ceil(N / (width - 1))` width-4 gates. For `N=64` the splitting cost
dominates, hence the **+158 Width / +103 ACIR** delta of the spike vs the
merged variant in §2.3.

### 3.3 When does each win?

- **Static shift amount** (compile-time constant): always wins; the SSA
  passes constant-fold it [11].
- **Small dynamic range** (`M < ~16`, e.g. `count_leading_zeros_u23`):
  dynamic shift wins; the per-shift O(M) cost is small enough that the
  bit-decomposition's wide-expression cost is uncompetitive. Empirical
  evidence: PR #36 merged the dynamic-shift relation for u23 and the
  next round (PR #37) tried to repeat the win at u64 and did not.
- **Large dynamic range** (`M >= ~32`): neither verifier beats the
  in-circuit binary-search baseline today, on this workspace's measurements
  (§2.3).
- **Bit decomposition wins when** the bits are reused multiple times in
  the same circuit (the booleanity + recombination is amortised), or
  when downstream constraints take individual bits as input (e.g. a
  digit-by-digit comparison). It does **not** win on a one-shot
  `count_leading_zeros` verifier.

## 4. Constant-folding rules

What the SSA optimisation passes do, in roughly the order they run [14]
(`compiler/noirc_evaluator/src/ssa/opt/`):

- `inlining` — function calls inlined; enables downstream folding.
- `unrolling` — loops with compile-time-known bounds and no `break` on
  a witness condition are unrolled.
- `mem2reg` — promotes memory references to SSA values; enables more
  folding.
- `constant_folding/` — folds expressions whose inputs are all constants
  after SSA propagation. This is a directory of related sub-passes; new
  passes have been added when fuzzers have caught misses [15].
- `simple_optimization` / `simplify_cfg` / `flatten_cfg` — the
  `flatten_cfg` pass is **non-optional**, because ACIR has no
  control-flow operators; it removes all branches, replacing them with
  conditional selections [14]. After flattening, both arms of an `if`
  contribute constraints; only the witness-selected one contributes to
  the *answer*, but **both still cost gates**.
- `remove_bit_shifts` — lowers `>>` and `<<` by a witness amount to a
  bit-decomposition loop [11].
- `remove_unused_instructions` / `die/` — dead-instruction elimination,
  scheduled after `flatten_cfg` per the architecture doc [14].

Practical rules that follow from the pass ordering:

- **Static is foldable.** A constant in a shift amount, an array index,
  or a loop bound is folded; nothing makes it past `flatten_cfg` into
  ACIR.
- **Witnesses are not foldable.** Any operation whose result depends on a
  `pub`/private input survives into ACIR.
- **Both branches cost.** `if` over a witness condition is flattened to
  conditional select (`x = c ? a : b`), so both `a` and `b` must be
  computed and constrained. Don't write `if cheap_check { expensive }
  else { 0 }` to "skip" a cost — `expensive` is constrained either way.
- **Loop-unrolling thresholds.** Loops with witness-dependent bounds are
  not unrolled; the body must not depend on the iteration index for the
  unroller to fold the iteration count out.
- **Constant-folding implication for benchmarks.** A microbenchmark that
  passes a *literal constant* into a CLZ helper measures the
  constant-folded happy path; it does not measure what the prover pays
  at a real call site. The PR #37 harness (`benchmark_gates.py`'s
  `PRIMITIVE_BENCHMARKS` block) explicitly threads a `pub u64` witness
  through to defeat folding [12]. Use the same harness shape for any
  `_verified` candidate.

## 5. Black-box / Plookup primitives

`BlackBoxFuncCall` opcodes lower to backend gadgets and can be either the
cheapest or the most expensive opcode in a circuit. Available black-boxes
in `nargo 1.0.0-beta.17` (and stable through `1.0.0-beta.20`) [2, 16]:

- Logical: `AND`, `XOR`, `RANGE` — invoked via `&`, `^`, `assert(x < 2^N)`.
- Hashes: `keccakf1600`, `sha256` (compress), `blake2s`, `blake3`,
  `pedersen_hash`, `pedersen_commitment`, `poseidon2_permutation`.
- Crypto: `ecdsa_secp256k1`, `ecdsa_secp256r1`, `embedded_curve_add`,
  `multi_scalar_mul`, `aes128_encrypt`.
- Recursion: `recursive_aggregation` — for in-circuit proof verification.

When to reach for a black box:

- **Hashes always go through black boxes** if the hash is one of the
  supported set. Implementing Poseidon in arithmetic constraints is a
  ~100× regression for nothing.
- **Range checks: `assert(x < 2^N)` lowers to `BlackBoxFunc::RANGE`.**
  Under Barretenberg UltraHonk this uses Plookup with a fixed setup
  cost; the profiler doc cautions that for small circuits range checks
  can dominate backend gates even when their ACIR opcode count is
  small [3]. Don't over-assert — if a `u32` is already typed `u32`, it
  is range-checked once at the function boundary, not on every use.
- **Lookups are not generally available** — at time of writing, Noir
  exposes Plookup-style lookup arguments only via the `RANGE` black-box
  for arithmetic and the keyed gadgets above. There is no general
  `lookup_table(...)` user-defined gadget. If you find yourself wanting
  one, document the gap and use a polynomial commitment over the table
  instead (see `noir-circuit-patterns` §"Joins" — *lookup-table /
  set-membership* pattern).

`nargo info` does **not** distinguish black-box-call ACIR opcodes from
`AssertZero` opcodes in its summary count; the breakdown is visible only
through `noir-profiler gates --include_gates_per_opcode` [9]. If a
backend-gate flame graph shows >50% of gates in `blackbox::range`,
investigate whether range-check density can be reduced rather than
optimising the surrounding arithmetic.

## 6. Reading `nargo info` and `bb gates`

A `nargo info` line looks like:

```
| ieee754  | main             | Bounded { width: 4 }  |  610  |  34  |
| Package  | Function         | Expression Width      | ACIR  | Brillig |
```

`benchmark_gates.py` parses this exact shape [17]; the same parser feeds
the `gate_counts.json` ledger.

What each column tells you:

- **Package / Function** — which compilation unit the row is for. A row
  per public function plus rows for compiler-generated helpers
  (`directive_invert` for division, `directive_integer_quotient`, plus
  any `unconstrained` Brillig hint compiled separately) [10].
- **Expression Width** — see §1.2. `Bounded { width: 4 }` is the
  *constraint*, the integer printed alongside is the *measured sum of
  widths* per `AssertZero` opcode. **This is the column to optimise for
  proving wall-clock under Barretenberg.**
- **ACIR Opcodes** — see §1.1. The integer count of ACIR opcodes in
  the constrained portion of the function. Ancillary helpers add to the
  total — sum the helper rows when comparing variants (PR #28 in
  `noir_XPath` does this explicitly) [10].
- **Brillig Opcodes** — see §1.3. **Free at proof time.** Don't
  optimise for this column.

`bb gates` adds to this picture: it reports the actual backend gate count
after Barretenberg has translated ACIR. Use it for a final answer; use
`nargo info` for iteration. If `bb gates` and `nargo info` disagree on
which variant wins, trust `bb gates` — but pin the `bb` version.

Common misreadings, in decreasing order of how often this codebase has
made them:

1. **"Brillig: 538"** read as a cost driver. It is not. (PR #37 round-1
   estimate.)
2. **ACIR-only comparison.** Comparing `add_float64` ACIR=34 across
   commits without checking Width hides 5× regressions in proving time.
   Width tracking was added to `benchmark_gates.py` in PR #37 specifically
   because of this hole [12].
3. **Forgetting ancillary helpers.** A `_verified` primitive's `nargo info`
   is `main` + `unconstrained_hint_fn` + `directive_invert` + ... — sum
   them. (PR #28 in `noir_XPath` instituted the convention [10].)
4. **Microbenchmark with a literal constant input.** Constant-folding
   makes the verifier disappear in the easy case; the prover never sees
   that path with a real witness.

## 7. Common pitfalls

### Mixed bit-widths

Noir is strict about integer type matching for bitwise ops:
`(value as u64) & (mask as u8)` is rejected. The first 2026-04 attempt at
unconstrained-ops introduced 45 type-mismatch errors of this shape; the
fix is **explicit `u<N>` annotations on every literal and intermediate**:

```rust
let masked: u32 = value & 0x007F_FFFF_u32;
let probe: u32  = (low23 >> top_bit_pos) & 1_u32;
```

The `unconstrained_ops.nr` module's preamble documents this discipline as a
crate-wide convention [18].

### Unconstrained outputs leaking

A `pub unconstrained fn` exposes the *unverified hint* through the public
API, letting downstream callers bypass the verifier. Roborev's PR #36
review caught this exact bug (`c7ecb8a` made `count_leading_zeros_u23_unconstrained`
crate-private). **Rule: every `unconstrained` hint is private to the
module that contains its verifier.** The only sanctioned public symbol is
the `_verified` wrapper.

### Range-check density

Every `assert(x < 2^N)` lowers to `BlackBoxFunc::RANGE` (§5). If the
upstream type is already `uN`, the value is already range-checked at the
function boundary; re-asserting is a free regression. The Noir docs flag
this for `Field as u32` index conversions: *"Converting a `Field` to `u32`
can be costly due to modulo operations. This cost can be mitigated by
using `assert_max_bit_size::<32>()` and `as u32`, especially when array
out-of-bound checks are already performed, as these checks can make the
explicit range check redundant"* [19].

### Shared-test-helper anti-pattern

A verifier copy-pasted into adversarial tests drifts. The convention in
this workspace is that the production `_verified` function and the
adversarial tests both call the same crate-private
`verify_clz_*_relation(...)` helper — see PR #37's pattern [12]. This
means a regression in the production verifier is also caught by the
adversarial-tests path; with a copy, it can hide for a release.

### Both arms of `if` cost

After `flatten_cfg` (§4), both arms of an `if` contribute constraints
even when only one is "selected" by the witness. Don't write
`if x == 0 { skip_expensive } else { expensive }` expecting to save
gates on the zero path — write a single straight-line expression and let
constant-folding handle constant inputs.

### Public-input layout drift

`main`'s public-input layout is a contract; changing the order silently
breaks every existing prover. `noir-circuit-patterns` §"Public input
layout" is the source of truth.

## 8. Decision checklist for a new `_verified` primitive

Run this before spending a round on a new candidate:

1. **What's the in-circuit-spec baseline?** Write it. Constant-foldable?
   If a literal input collapses it to <10 ACIR opcodes, the witness path
   probably wins on Width too.
2. **What relation am I proposing for the verifier?** Sketch it on paper.
   Does it have a data-dependent shift (cost (a))? A data-dependent
   index (cost (b))? A loop bounded by a witness (cost (c))? Each
   "yes" is a strike.
3. **Can I sketch the verifier's ACIR opcode count from the relation
   shape?** N booleanity asserts + 1 wide recombination ≈ N + N/3
   opcodes; one dynamic shift ≈ M opcodes for max shift M; two = 2M.
   Write the prediction *before* benchmarking; if measurement disagrees
   by >2×, the relation is not what you thought it was.
4. **Is there a black-box that does this directly?** §5. Don't
   reimplement Poseidon.
5. **Have I budgeted for both isolated AND composed measurement?** The
   composed measurement is the only one that answers "should we swap
   the call site?" — see §4 closing rule.
6. **Does the relation match the Lean obligation in `proofs/<crate>/`?**
   The Lampe extraction needs the verifier's relation to match the
   `*_unique` and `*_correct` lemmas line-for-line. If you change the
   relation shape, also update the obligation; otherwise the soundness
   argument drifts.
7. **Has a previous spike already tried this?** Check the in-repo
   benchmark ledgers (`circuits/noir_IEEE754/gate_counts.json`,
   `circuits/noir_XPath/bench/unconstrained_gate_counts.json`) and the
   commit log for `spike:` / `bench:` prefixes. Don't re-run a
   negative spike.

## 9. References

Noir documentation (retrieved 2026-05-03; pinned to docs version
`v1.0.0-beta.20` unless noted):

1. ACIR opcodes enum — `acvm-repo/acir/src/circuit/opcodes.rs`,
   `noir-lang/noir` — six variants: `AssertZero`, `BlackBoxFuncCall`,
   `MemoryOp`, `MemoryInit`, `BrilligCall`, `Call`. Also documented at
   `https://noir-lang.github.io/noir/docs/acir/circuit/index.html`.
2. Black-box functions —
   `https://noir-lang.org/docs/noir/standard_library/black_box_fns`.
3. Profiler — *"Understanding bottlenecks"* —
   `https://noir-lang.org/docs/tooling/profiler`. Source of the "ACIR
   opcodes are at best approximations of proving performances" quote
   and the `blackbox::range` / Plookup setup-cost discussion.
4. Issue noir-lang/noir#7525 — *"bug: expression width not honored in
   certain gates"* — defines expression width as the maximum number of
   witness wires per `AssertZero` gate, with the `--expression-width N`
   flag and the bounded-codegen behaviour.
5. Aztec forum — *"Barretenberg UltraPlonk → Halo2"*,
   `https://forum.aztec.network/t/barretenburg-ultraplonk-halo2/353`,
   confirms UltraPlonk's width-4 PLONKish arithmetisation.
6. Unconstrained Functions concept doc —
   `https://noir-lang.org/docs/noir/concepts/unconstrained` — canonical
   `u64_to_u8` example, 65 → 33 ACIR opcodes, the
   `is_unconstrained()` conditional pattern.
7. Profiler — *"Balancing proving and execution optimisations"* — same
   URL as [3]. Source of the "Brillig opcodes are not a proving cost"
   framing.
8. `Savio-Sou/noir-benchmarks` —
   `https://github.com/Savio-Sou/noir-benchmarks` — Plonk / TurboPlonk
   / UltraPlonk gate-count comparison for Pedersen hashes.
9. `noir-profiler gates` invocation —
   `https://noir-lang.org/docs/tooling/profiler#flamegraphing`.
10. `noir_XPath` PR #28 — *"bench: add unsigned_to_string harness"*,
    commit `be56b80`. First measurement: baseline Width=1756 ACIR=34
    vs unconstrained Width=714 ACIR=506 — Width −59% / ACIR +14×.
    Establishes the ancillary-helper-summing convention.
11. SSA pass `remove_bit_shifts` —
    `compiler/noirc_evaluator/src/ssa/opt/remove_bit_shifts.rs`. Lowers
    runtime shifts to bit-decomposition.
12. `noir_IEEE754` PR #37 — *"feat(circuits): count_leading_zeros_u64
    via unconstrained + verified pattern"*, merge commit `9f10b5e`.
    Source of the §2.3 case-study numbers and the `benchmark_gates.py`
    `PRIMITIVE_BENCHMARKS` Width-tracking block.
13. `noir_IEEE754` commits `c0f433d` (spike), `1a92ded` (bench),
    `b87abb4` + `63d0b95` (reverts). Source of the bit-decomposition
    spike measurements (Width=270/322, ACIR=203/220).
14. Noir compiler architecture — `docs/compiler/architecture.md`. SSA
    pass list and ordering, including the non-optional `flatten-cfg`
    pass and the dead-instruction-elimination ordering constraint.
15. SSA optimisation passes directory listing — every entry under
    `compiler/noirc_evaluator/src/ssa/opt/` in the master branch
    (alias_analysis, array_get, array_set, brillig_*, checked_to_unchecked,
    constant_folding/, defunctionalize, die/, flatten_cfg/, hint,
    inlining/, load_store_forwarding, loop_invariant/, mem2reg,
    normalize_value_ids, preprocess_fns, remove_bit_shifts,
    remove_truncate_after_range_check, remove_unused_instructions,
    simple_optimization, simplify_cfg, unrolling, ...).
16. Black-box functions reference —
    `docs/versioned_docs/version-v1.0.0-beta.20/noir/standard_library/black_box_fns.md`.
17. `circuits/noir_IEEE754/scripts/benchmark_gates.py` — the table
    parser used across this workspace. Lines 160-168 document the
    column layout `Package | Function | Expression Width | ACIR
    Opcodes | Brillig Opcodes`.
18. `circuits/noir_IEEE754/ieee754/src/unconstrained_ops.nr` — module
    preamble documents the explicit-`u<N>`-annotation discipline; the
    crate-private hint convention; the `verify_*_relation` shared-test
    helper pattern.
19. Noir `Field`-to-`u32` conversion guidance —
    `https://noir-lang.org/docs/noir/concepts/data_types/arrays`.
    Source of the `assert_max_bit_size::<32>()` pattern.

In-repo benchmark ledgers (read these before every optimisation round):

- `circuits/noir_IEEE754/gate_counts.json` — arithmetic-op headline +
  `primitive_benchmarks` block for the unconstrained-ops series.
- `circuits/noir_XPath/bench/unconstrained_gate_counts.json` — focused
  baseline-vs-variant ledger; format documented in
  `circuits/noir_XPath/scripts/README.md`.
