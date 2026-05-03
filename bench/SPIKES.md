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

### 2026-05-03 follow-up -- merged dynamic-shift verifier dropped too

After this no-go verdict on the bit-decomposition shape, the merged
dynamic-shift `count_leading_zeros_u64_verified` from PR #37 was also
deleted (along with its 14 unit tests and the `clz_u64_*`
`PRIMITIVE_BENCHMARKS` entries). The numbers above show the verified
variant regressing on both Width and ACIR vs. the binary-search
baseline in both regimes -- with no candidate verifier shape that
recovers the gap. Per the experimental-API memory rule, dead
optimisation primitives don't stay in the public surface. Future
agents reaching for `clz_u64_verified` expecting different numbers
should consult this entry before reattempting -- the only remaining
unexplored axis is the `Field::to_le_bits::<64>()` intrinsic
hybrid noted above.

`count_leading_zeros_u23_verified` is kept -- it wins for small N per
the noir-optimisation skill's section 3.3.

---

## 2026-05-03 -- `shr_sticky_u64` Euclidean-division verifier

**Verdict:** **MIXED.** Verifier wins -5 Width / -7% in both regimes
but loses +103 ACIR / +303% in both; per the workspace rule
"Width is what the prover pays for under Barretenberg" the trade is
not strong enough to justify swapping call sites, so the primitive ships
as a stable public-API target only.

**Branch:** `feat/shr-sticky-u64-verified` (this PR; primitive +
benchmarks shipped, no call sites swapped).

**Toolchain:** `nargo 1.0.0-beta.17` on macOS, against `origin/main` at
`22dafd9` (post-PR #41 CI sync, post-PR #40 `clz_u64` deletion).

### Motivation

The first-round task asked: do the cost numbers for
`shift_right_sticky_u64_verified` look like `clz_u64`'s (regress on both
metrics, drop) or do they pay off? The relation shape is genuinely
different -- Euclidean-division reconstruction
`value = quotient * (1 << shift) + remainder` over `Field` plus an
existence-of-inverse witness for the sticky-direction clause -- so the
empirical answer was unknown until measurement.

### Constraint shape

For `shift == 0` and `shift >= 64` the verifier short-circuits to direct
equality / inequality assertions (cheap). For `1 <= shift <= 63`:

| Clause   | Constraint                                                                     |
|----------|--------------------------------------------------------------------------------|
| (3a)     | `value == quotient * pow2 + remainder` over `Field` (pow2 = `1 << shift`)      |
| (3b)     | `remainder < pow2` (range check on a u64 difference)                           |
| (3c.i)   | `(1 - sticky) * remainder == 0`  (`sticky == 0 => remainder == 0`)             |
| (3c.ii)  | `remainder * remainder_inv == sticky` with witnessed `remainder_inv: Field`    |

Plus one dynamic left-shift `1 << shift`. The baseline does two dynamic
shifts (`>> shift` and `1 << shift` for the mask), so the verifier nets
out *one fewer dynamic shift* in exchange for one Field multiplication
and the boolean-direction pinning.

### Numbers

Measured by `scripts/benchmark_gates.py`'s `PRIMITIVE_BENCHMARKS`,
isolated regime (verifier on its own, `(value, shift)` as `pub u64` to
defeat constant-folding) and composed regime (the `denorm_shift < 56`
denormal-mantissa shift block from `float64/mul.nr` line 303). Both
variants measured in the same run.

| Variant                                | Width | ACIR |
|----------------------------------------|------:|-----:|
| `shr_sticky_u64_isolated_baseline`     |    72 |   34 |
| `shr_sticky_u64_isolated_verified`     |    67 |  137 |
| `shr_sticky_u64_composed_baseline`     |   106 |   34 |
| `shr_sticky_u64_composed_verified`     |   101 |  137 |

Verifier delta: **-5 Width (-7%) / +103 ACIR (+303%)** in both regimes.
The composed delta is exactly the same as the isolated delta, so the
regression is structural (not a constant-folding artefact in the
isolated harness).

### Why the trade looks like this

The verifier saves one dynamic shift relative to the baseline (the
baseline computes both `(1 << shift) - 1` for the mask AND `value >>
shift` for the quotient; the verifier computes only `1 << shift` for
`pow2`). That's the -5 Width win.

But the verifier adds: a Field multiplication `quotient * pow2`, a
Field equality, two boolean-direction constraints, plus the `Field`
inverse witness's multiplicative constraint. Each of those is small in
Width but adds an `AssertZero` ACIR opcode -- hence the +103 ACIR
regression.

Comparison to the `clz_u64` round (PR #37, deleted in PR #40): clz_u64
regressed on **both** Width AND ACIR; this primitive regresses only on
ACIR. The difference is the relation shape -- Euclidean-division has
constant-multiplier structure (the `pow2` multiplier is small relative
to the BN254 modulus, so the Field multiplication has narrow expression
width); CLZ's two dynamic shifts contribute to Width additively.

### Implication for follow-on work

The Width edge is too small (-7%) to motivate swapping call sites: if a
future Lampe extraction round needs the verified-relation shape (because
the soundness proof depends on the algebraic relation rather than the
binary-search baseline's straight-line shifts), the primitive is
available. Otherwise, the in-tree `utils::shift_right_sticky_u64` is the
right choice.

Two angles worth measuring in a future spike, *not* this one:

- **Constant-shift call site.** The float32/mul.nr line 201 call has
  `guard_shift = 46 - 26 = 20` known at compile time; the verifier's
  `1 << shift` would constant-fold and the relation might collapse to
  cheaper-than-baseline. A focused `shr_sticky_u64_const20_*` benchmark
  would answer this; if the verifier wins by enough Width there, swap
  *that* call site only.

- **`shr_sticky_u128`.** The float64/mul.nr line 281 call uses the U128
  variant. Its in-circuit baseline is more complex; a U128 verified
  variant could plausibly win where the u64 one only marginally does.
  Out of scope for this round.

### Process

- Five commits on the branch: source-level primitive (`9c1f8cb` after
  rebase onto `e6d7107`), adversarial test follow-up (`0f497e5`)
  addressing roborev's flagged `shift>=64 sticky direction wrong` test
  gap, benchmark harness (`2b563e5`), harness-comment + primitive
  comparison (`2c4f142`) addressing the second roborev round, this
  ledger update, then a follow-up commit regenerating the JSON against
  the SPIKES commit.
- 36 ieee754 tests passed (15 baseline + 21 new shr_sticky tests, of
  which 11 happy-path + 10 adversarial).
- Roborev (codex / gpt-5.5) returned "No issues found" on the
  adversarial-test commit and on the harness-improvement commit;
  earlier roborev rounds raised the test-gap and stale-`git_commit`
  findings that those commits closed.

**Provenance note.** The committed JSON's `git_commit` field points at
the *parent* of the JSON's commit (the harness used to capture it can't
know its own commit hash before commit). After every bench run, the
recorded `git_commit` is therefore the most recent commit at run time;
to interpret a number against a future repo state, look at the
`git_commit` field plus the commit that introduced the JSON itself.

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
