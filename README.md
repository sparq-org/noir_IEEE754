# sparq_ieee754 — IEEE 754 binary floating point for Noir

> **This repository is the source of truth for the library.** The former
> in-tree copy at `zk/ieee754` in
> [sparq-org/sparq](https://github.com/sparq-org/sparq) was removed when sparq
> switched to depending on this repo's tagged releases (sparq PR #1602);
> develop, file issues, and open pull requests **here**. (This repo supersedes
> the earlier `jeswr/noir_IEEE754` contents, which are deprecated.)

A Noir library providing IEEE 754 `f16`, `f32`, `f64`, and `f128` types,
generated at compile time from a single width parameter, with
gate-count-optimised arithmetic kernels (hint-and-verify witnesses, bounded
pow2 shift proofs, normalized-only round-pack paths).

> [!CAUTION]
> **Security Warning.** This library has **not been security reviewed** and
> should not be used in production systems without a thorough audit. Parts of
> the implementation are AI-assisted; edge cases may remain.

## Usage

Add a dependency (path dependency shown; adapt to your Noir dependency form):

```toml
[dependencies]
sparq_ieee754 = { path = "path/to/sparq_ieee754" }
```

```noir
use sparq_ieee754::{f16, f32, f64, f128};

fn main(a_bits: u64, b_bits: u64) -> pub u64 {
    let a = f64::new(a_bits);     // construct from raw IEEE 754 bits
    let b = f64::new(b_bits);
    let c = (a + b) * a / b - b;  // Add/Sub/Mul/Div are implemented
    c.bits()                      // recover raw bits
}
```

### Public API

The public API is intentionally only the generated `f16`, `f32`, `f64`, and
`f128` structs:

- `new(bits)` — construct from raw bits (`u16`/`u32`/`u64`/`u128`);
  constrains `(sign, exponent, mantissa)` to canonical IEEE field widths so
  `bits()` is injective (soundness fix sq-3x7dl.1).
- `bits()` — recover raw bits.
- `std::ops::Add`, `Sub`, `Mul`, `Div` — round-to-nearest-even arithmetic with
  full subnormal, infinity, and NaN handling (NaNs are canonicalised).
- `std::convert::From<u8 | u16 | u32 | u64 | u128 | i8 | i16 | i32 | i64>` —
  integer-to-float conversion with IEEE round-to-nearest-even.
- Comparison predicates `eq`/`ne`/`lt`/`le`/`gt`/`ge` with IEEE NaN semantics
  (`x.ne(x)` is the NaN test).
- `sqrt` (round-to-nearest-even).
- Round-to-integral methods and float-to-integer casts (truncating toward
  zero, with out-of-range/NaN/infinity rejection).
- `abs` — IEEE 754-2019 5.5.1 quiet bit-level sign clear (NaN payloads pass
  through unchanged).
- Named constant constructors `zero`/`neg_zero`/`one`/`neg_one`/`infinity`/
  `neg_infinity`/`nan`/`signaling_nan` (comptime-constant bit patterns; the
  library implements no signaling semantics — `signaling_nan()` exists for
  bit-level interoperability only).
- `from_field` (Field → float, round-to-nearest-even; the field element is
  interpreted as an unsigned integer and must be < 2^128 — larger values fail
  an in-circuit range assert) and `to_field` (float → Field, truncating toward
  zero via the `to_u64` kernel with its NaN/infinity/range rejections).

Everything else (`FloatParts`, the `ops` kernels, `codegen`, `sizing`,
generated struct fields, `to_parts`) is private by design and enforced by
`scripts/test_public_api.sh` and `scripts/lint_private_function_usage.py`.

## Layout

- `src/lib.nr` — crate root; root-level generated-type triggers and tests.
- `src/codegen.nr` — comptime generation of the public float structs and impls
  via `#[generate_float_type(N)]`.
- `src/parts.nr` — internal `FloatParts<E, M>` carrier.
- `src/sizing.nr` — comptime layout/type helpers.
- `src/ops/kernels.nr` — arithmetic kernels: u64 kernel for f16/f32/f64, wide
  `u128`/Field kernel for f128, conversion helpers, proof helpers.
- `tests/` — external-package test sources (public API surface, private-field
  and private-method rejection, generated arithmetic vectors). These are
  copied into temporary packages by the scripts below, not built in place.
- `differential/` — Rust differential oracle harness that cross-checks the
  circuits against a host IEEE reference.
- `scripts/` — test and benchmark harnesses (see `scripts/README.md`).
- `bench/` — committed gate baselines (see `bench/README.md`).
- `AGENTS.md` — agent handoff: invariants, optimisation rules, known-good and
  known-bad patterns.
- `TESTING.md` — mapping from the deprecated `jeswr/noir_IEEE754` test suite to
  this suite's coverage.

## Validation

The pinned toolchain is `nargo 1.0.0-beta.21`. Run:

```sh
nargo test --silence-warnings
bash ./scripts/test_generated_vectors.sh
bash ./scripts/test_public_api.sh
python3 scripts/lint_private_function_usage.py
```

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs the same
validation on the pinned toolchain.

## Benchmarks

`scripts/benchmark_float_ops.py` is the canonical amortised UltraHonk gate
harness: it builds temporary binary packages, runs `nargo compile`, reads
`circuit_size` from `bb gates -s ultra_honk` at small-N and big-N, and
estimates per-call cost from the difference.

```sh
python3 scripts/benchmark_float_ops.py --output /tmp/candidate_float_ops.json
python3 scripts/compare_float_benchmarks.py /tmp/candidate_float_ops.json --max-regression 1
```

The committed per-call gate baselines live in `bench/` (see `bench/README.md`);
`bench/float_ops_latest.json` is the reference the comparison script gates
against.

## Known gaps

Remaining known gaps, tracked as beads in the sparq repo:

- Directed rounding for arithmetic — `Add`/`Sub`/`Mul`/`Div` are
  round-to-nearest-even only (directed rounding exists only for
  round-to-integral). Re-adding the deprecated library's rounding-mode
  arithmetic is a kernel-level feature (mode-threaded round-pack in both the
  u64 and wide kernels, with a directed-rounding host oracle) tracked as
  sparq bead sq-xs0pa.
- f128 rows in the Rust differential oracle harness — deferred until a stable
  conformant host reference is adopted (tracked as sq-3x7dl.14.2); f128 is
  covered by the exact-rational generated vectors.
