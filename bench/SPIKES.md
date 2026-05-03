# Spike ledger -- `noir_IEEE754`

This file records measurement-driven spikes whose conclusions we want
future agents (and humans) to find before reinvesting effort in the
same exploration. Each entry is one spike and follows the template at
the bottom of the file.

British English throughout.

---

## 2026-05-03 -- `clz_u64` verifier via explicit bit decomposition

**Verdict:** **NO-GO.** Spike regresses on both Width and ACIR, in both
isolated and composed regimes, vs. *both* the merged dynamic-shift
verifier (PR #37) and the binary-search baseline.

**Branch:** `spike/clz-bit-decomposition` (PR #38; this commit is the
only artefact left on the branch -- the implementation and bench
commits were reverted).

**Toolchain:** `nargo 1.0.0-beta.17` on macOS, against
`origin/main` at `9f10b5e` (the merged
`count_leading_zeros_u64_verified`).

### Motivation

PR #37 merged `count_leading_zeros_u64_verified` using a
dynamic-shift verifier (`value >> top_bit_pos`). Both Width and ACIR
regressed vs. the binary-search baseline, so call sites were not
swapped. The previous round's open question was whether replacing the
dynamic shift with an explicit bit-decomposition relation could close
the gap.

The proposal: witness `bits: [Field; 64]`, a one-hot
`is_leading: [Field; 64]`, and a non-zero indicator
`is_nonzero: Field`, then verify the relation algebraically.

### Constraint shape used in the spike

| Clause   | Constraint                                                                                          | Cost |
|----------|-----------------------------------------------------------------------------------------------------|------|
| (B)      | `bits[i] * (bits[i] - 1) == 0` for each `i`                                                         | 64x  |
| (D)      | `sum_i bits[i] * 2^i == value` (one Field equality)                                                 | 1    |
| (L)      | `is_leading[i] * (is_leading[i] - 1) == 0` for each `i`                                             | 64x  |
| (E)      | `is_nonzero in {0,1}`, `is_nonzero * value == value`, `(1 - is_nonzero) * value == 0`               | 3    |
| (E')     | `sum_i is_leading[i] == is_nonzero`                                                                 | 1    |
| (S)      | `is_leading[i] * bits[i] == is_leading[i]` for each `i`                                             | 64x  |
| (P)      | top-down cumulative `saw_one` prefix; `bits[idx] * (1 - saw_one) == 0` for each `idx`               | 64x  |
| (C)      | `count + is_nonzero + sum_i i * is_leading[i] == 64`                                                | 1    |

The "no bits above leading" clause (P) used the prefix-flag trick
(`saw_one[i] = sum_{j >= i} is_leading[j]` built top-down) so it
stayed O(N) rather than the naive O(N^2) pairwise form
`is_leading[i] * bits[j] == 0` for `j > i`. Without that trick the
verdict would have been even more lopsided.

### Numbers

Measured by `scripts/benchmark_gates.py`'s `PRIMITIVE_BENCHMARKS`,
both isolated and composed regimes (the composed regime mirrors the
subnormal-normalisation block from
`ieee754/src/float64/add.nr`). All three variants were measured on
the same harness in the same run.

| Variant                                      | Width | ACIR |
|----------------------------------------------|------:|-----:|
| `clz_u64_isolated_binsearch_baseline`        |    96 |   17 |
| `clz_u64_isolated_verified` (merged, PR #37) |   112 |  100 |
| `clz_u64_isolated_verified_bitdecomp`        |   270 |  203 |
| `clz_u64_composed_binsearch_baseline`        |   133 |   34 |
| `clz_u64_composed_verified` (merged, PR #37) |   164 |  100 |
| `clz_u64_composed_verified_bitdecomp`        |   322 |  220 |

### Why the spike was expensive

The bit-decomposition relation pays linearly per bit on five separate
clauses (B, L, S, P, plus the dot products in D and C). At 64 bits
that's roughly 5 x 64 = 320 boolean / multiply-accumulate constraints
before the verifier even reaches the count-consistency check. The
merged dynamic-shift verifier pays for one `value >> top_bit_pos`
plus one `value >> (top_bit_pos + 1)` plus a few small assertions:
expensive in absolute terms but **cheaper than 320 atomic Field
constraints**.

The Field arithmetic itself was the bottleneck: clauses (B), (L),
(S), and (P) are all degree-2 Field equalities applied 64 times each.
Bit-by-bit boolean checking does not get cheaper just because the
relation is "structural". The dot-product (D) and the position sum
(C) come essentially free in comparison.

The prefix-flag encoding for (P) **was** a real optimisation -- the
naive O(N^2) form would have added another ~2000 constraints on top.
But even with that optimisation the constant is wrong.

### Implication for `clz_u52_verified`

The shape that PR #37 left as a follow-up is `clz_u52_verified`. The
bit-decomposition relation would scale linearly in bit-width: at 52
bits it costs roughly 5 x 52 = 260 boolean constraints, still well
above the binary-search baseline's small handful of statically-known
shifts. **Skip the bit-decomposition variant for `clz_u52`** and
either:

- ship `clz_u52_verified` with the same dynamic-shift shape as the
  merged `clz_u64_verified` (consistent API, regress accepted as the
  cost of the verified-relation pattern), or
- consider a hybrid: keep the binary-search shape and *also* witness
  the count, asserting equality. That doesn't save gates either, but
  it sketches a different relation worth measuring before committing.

A third axis worth measuring (not part of this spike) is whether
`Field::to_le_bits::<64>()` -- which produces a canonical
bit-decomposition -- can be combined with a one-hot leading-bit
witness more cheaply than the manual decomposition relation here.
The compiler's intrinsic implementation of `to_le_bits` may amortise
the boolean-check cost in ways the hand-rolled relation cannot.
That's a candidate for a *future* spike, not this one.

### Process

- Source-level spike committed at `c0f433d`, benchmarks at `1a92ded`,
  both reverted at `b87abb4` and `63d0b95`. Net branch diff against
  `main` is this file alone.
- All 17 added tests passed (10 happy paths + 6 adversarial + 1 round
  trip).
- Roborev (codex / gpt-5.5) returned "No issues found" on both the
  spike and bench commits before the verdict.

---

## Template

```
## YYYY-MM-DD -- <one-line-description>

**Verdict:** WIN / MIXED / NO-GO. <one sentence>

**Branch:** `spike/...` (PR #<n>; <what's left on the branch>)

**Toolchain:** `nargo X.Y.Z-...`, against `origin/main` at `<sha>`.

### Motivation
<why this was worth trying>

### Numbers
<table: variant x metric>

### Implication for follow-on work
<concrete advice for the next agent looking at this area>

### Process
<commits, roborev outcomes, tests added>
```
