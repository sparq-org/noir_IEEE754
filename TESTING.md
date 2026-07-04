# Test preservation: `jeswr/noir_IEEE754` (deprecated) → `sparq_ieee754`

This repository's contents were replaced by the `sparq_ieee754` library
developed in [sparq-org/sparq](https://github.com/sparq-org/sparq) under
`zk/ieee754`. The previous library (`Float32`/`Float64` structs) was a distinct
codebase; the replacement generates `f16`/`f32`/`f64`/`f128` at compile time
from a single width parameter.

Per the migration requirement, this document maps the **deprecated suite's**
test coverage onto the **new suite** so no tested behaviour is silently lost.

## New suite (what runs today, pinned `nargo 1.0.0-beta.21`)

Measured on this toolchain at migration time:

| Suite | Command | Passing |
| --- | --- | ---: |
| In-source unit tests | `nargo test --silence-warnings` | 29 |
| Generated arithmetic + conversion vectors | `bash scripts/test_generated_vectors.sh` | 121 |
| Public-API surface | `bash scripts/test_public_api.sh` (positive) | 6 |
| Private-internals rejection | `bash scripts/test_public_api.sh` (negative, expect-compile-fail) | 4 |
| **Total** | | **156 + 4 rejection checks** |

Plus: `differential/` — a Rust differential-oracle harness that cross-checks the
circuits against a host IEEE reference; `scripts/lint_private_function_usage.py`
(passes). The generated arithmetic vectors are produced against an exact
rational IEEE reference (`scripts/generate_float_vectors.py`), and optional IBM
FPgen `.fptest` ingestion is available opt-in (`--include-fpgen`).

The new suite covers all four widths (`f16`/`f32`/`f64`/`f128`); the deprecated
suite covered only `Float32`/`Float64`.

## Deprecated suite inventory (229 Noir `#[test]`s + 76 Lean proofs)

| Deprecated file | Tests | Area |
| --- | ---: | --- |
| `ieee754_unit_tests/src/float32_tests.nr` | 55 | f32 add/sub/mul/div, cmp, sqrt, abs, constants |
| `ieee754_unit_tests/src/float64_tests.nr` | 56 | f64 add/sub/mul/div, cmp, sqrt, abs, constants, subnormal edges |
| `ieee754_unit_tests/src/float32_convert_tests.nr` | 33 | f32 ↔ u32/u64/Field conversions |
| `ieee754_unit_tests/src/float64_convert_tests.nr` | 35 | f64 ↔ u32/u64/Field conversions |
| `ieee754_unit_tests/src/rounding_mode_tests.nr` | 37 | explicit directed-rounding-mode arithmetic |
| `noir/lib/reference_tests/src/main.nr` | 13 | exact-rational reference equivalence |
| `ieee754/proofs/*.lean` | 76 | Lean formal-equivalence proofs |

## Mapping

### Covered by the new suite (152 of 229 Noir tests)

| Deprecated behaviour | Covered by |
| --- | --- |
| Arithmetic `add`/`sub`/`mul`/`div` (basic, different exponents, with/opposite signs, with zero/one) — f32/f64 (~24 tests) | `tests/generated_arithmetic` (121 randomised + special vectors, all 4 widths, exact-rational reference) + in-source `arithmetic_handles_subnormals_and_special_values`, `arithmetic_scales_across_generated_float_widths`, `arithmetic_traits_are_wired_to_ops`; `differential/` oracle |
| Special values in arithmetic: `add_nan`, `add_infinity`, `mul_infinity`, `mul_with_zero`, `div_by_zero`, `div_zero_dividend`, `div_infinity` | Special-value vectors + `arithmetic_handles_subnormals_and_special_values` (NaN canonicalisation asserted) |
| f64 subnormal edges: `min_denormal_plus_*`, `max_denormal_*` (7 tests) | Subnormal coverage in the specials test + generated vectors span subnormal operands |
| Comparison `eq`/`ne`/`lt`/`le`/`gt`/`ge`/`unordered`/`compare`, incl. `eq_zeros` (±0), `*_nan`, `lt_infinity` (~28 f32+f64) | `comparison_predicates_follow_ieee_semantics` + `comparison_predicates_scale_across_widths` (assert ±0 equal, NaN unordered on every predicate, ±∞ ordering, subnormal ordering, all widths) + `comparison_predicates_are_public_api` |
| `sqrt` basic/one/two/nine/quarter/zero/infinity/negative/nan (~18 f32+f64) | `sqrt_handles_special_values`, `sqrt_handles_exact_and_rounded_roots`, `sqrt_is_public_api` |
| `from_to_bits`, `special_values`, bits round-trip | `generated_float_types_round_trip_through_parts`, `new_accepts_canonical_boundary_values`, `f32/f64_new_rejects_malicious_mantissa_overlap` (injective `bits()` — a soundness strengthening over the old suite) |
| Integer → float: `from_u32`/`from_u64` (zero/one/power-of-two/large/max) (~15) | `unsigned_integer_conversions_follow_ieee_rounding`, `signed_integer_conversions_preserve_sign_and_rounding`, `integer_conversions_are_public_api`, generated conversion vectors (`From<u8..u128, i8..i64>`) |
| Float → integer: `to_u32`/`to_u64` (zero/one/truncate/large/negative/infinity/nan/fractional) (~20) | `float_to_int_casts_truncate_toward_zero`, `float_to_i64_rejects_below_min`/`two_pow_63`/`infinity`, `float_to_u64_rejects_nan`/`negative_values`/`two_pow_64`, `float_to_int_casts_are_public_api`, generated `f64_to_i64`/`f64_to_u64` valid+invalid vectors |
| int↔float round-trips | Generated conversion vectors (round-trip is checked against the exact reference both directions) |
| Default round-to-nearest-even results, incl. halfway ties, overflow-to-inf, cancellation (`reference_tests`, 13) | Generated arithmetic vectors use an exact-rational RNE reference (ties-to-even, overflow, cancellation) + `differential/` oracle; supersedes the hand-written reference-equivalence tests |

### Absent from the new public API — documented, not portable (77 tests)

These target functionality the replacement library **intentionally does not
expose**. A test cannot be ported to an API that does not exist; each is
recorded here so the decision is explicit (tracked for possible re-addition in
sparq-org/sparq).

| Deprecated behaviour | Tests | Why not ported |
| --- | ---: | --- |
| `abs` (positive/negative/zero/infinity/nan), f32+f64 | 10 | `abs` is not part of the current public API. IEEE `abs` is a bit-mask on the sign field; if re-added it belongs in `sparq-org/sparq` first, then syncs here. |
| Named constant constructors (`constant_zero`/`neg_zero`/`one`/`neg_one`/`infinity`/`neg_infinity`/`nan`/`signaling_nan`), f32+f64 | 16 | The new API constructs from raw bits via `new(bits)`; there are no named-constant constructors. The bit patterns those constants assert are exercised by `new_accepts_canonical_boundary_values` and the round-trip tests. |
| Field↔float conversion (`from_field`/`to_field`/`field_roundtrip`), f32+f64 | 14 | The new API exposes integer↔float conversion (`From<u8..u128, i8..i64>` and float→int casts) but not `Field`↔float. `Field` is not a fixed-width integer; the integer conversions cover the intended use. |
| Explicit directed-rounding-mode arithmetic (`*_rne`/`rna`/`rndu`/`rndd`/`rndz`, `*_all_modes`, `*_rounding_mode_out_of_range`, `accepts_all_documented_modes`) | 37 | The new arithmetic operators are round-to-nearest-even only (no rounding-mode parameter); directed rounding survives only for round-to-integral. The RNE-mode assertions in these tests remain covered by the generated vectors (RNE reference); the directed-mode (`rndu`/`rndd`/`rndz`/`rna`) and out-of-range-parameter assertions have no corresponding API. |

### Superseded verification artifact (76 Lean proofs)

`ieee754/proofs/*.lean` were Lean formal-equivalence proofs of the old circuits
against a reference. The new library replaces that approach with the runtime
**differential oracle** (`differential/` + the exact-rational generated-vector
reference), which cross-checks the generated circuits against a host IEEE
reference on every run. No Lean toolchain is required. The formal-proof
approach is not carried over; its soundness intent is served by the differential
harness plus the injective-`bits()` in-circuit invariants
(`*_new_rejects_malicious_mantissa_overlap`).

## Summary

- Old tests covered by the new suite: **152** (of 229 Noir tests).
- Old tests documented obsolete / absent-by-scope: **77**.
- Old tests ported (added new tests): **0** — every coverage gap corresponds to
  a feature the new library does not expose, so there is no API to port a test
  against; and this repo is synced from `sparq-org/sparq`, where any re-added
  feature (and its test) must land first.
- Lean formal proofs (76): superseded by the differential-oracle harness.
