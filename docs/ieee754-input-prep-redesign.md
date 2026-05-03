# IEEE 754 input-prep redesign

This document captures architectural concerns and decisions for the Python
test-generation pipeline that feeds Noir tests against the `ieee754` library.
It is a living working document; sections are added / amended as decisions
land.

## 1. Background

The `scripts/generate_tests.py` script ingests IBM FPgen `.fptest` test
vectors plus a number of synthetic test families and emits Noir test
packages under `test_packages/`. Two key transforms happen along the way:

1. **Operand decoding** -- `.fptest` vectors are written in the IBM FPgen
   syntax (`<sign><significand>P<exponent>`); we convert each operand to its
   IEEE 754 bit pattern.
2. **Expected-result computation** -- given the two operand bit patterns,
   the operation, and the rounding mode, we compute the IEEE 754 bit pattern
   of the expected result. The Noir test then asserts the circuit's output
   matches.

Both transforms must be **independent** of the Noir library implementation
under test, otherwise a shared bug in one direction (e.g. wrong sticky-bit
rounding) wouldn't be detectable by the test suite.

## 2. Scope

(Other sections elided in this document slice; populated as decisions land.)

## 5. Concern 4 -- independent extraction

The expected-result computation must be independent of the circuit it tests.
The pipeline currently has two reference oracles, layered fast-path-first:

1. **Round-to-nearest-even fast path** -- `float.fromhex` decodes the
   operand into a Python `float` (binary64), the operation runs in native
   hardware, and `struct.pack('>f', ...)` / `struct.pack('>d', ...)`
   re-extracts the IEEE 754 bits. Hardware floats on every supported CI
   platform implement IEEE 754 round-to-nearest-even, so this path is
   correct for the only rounding mode the current corpus exercises.

2. **MPFR-backed reference** -- `scripts/noir_ieee754_inputs/reference.py`
   wraps `gmpy2.mpfr` in a context whose precision / `emin` / `emax` /
   `subnormalize` settings exactly mirror the target IEEE 754 binary
   format. Every IEEE rounding mode (RNE / RNA / toward +Inf / toward
   -Inf / toward zero) is available. Non-default rounding modes are
   delegated to this oracle inside `_compute_expected_bits`.

The two routes are cross-checked in `scripts/test_reference.py`: under
round-to-nearest-even they agree byte-for-byte on hand-picked corner cases,
on 2x1024 randomised binary32 / binary64 cases across all four binary
operations, and on every test in the shipping corpus (verified by running
the generator with the MPFR route forced on for RNE and `diff`'ing the
output -- byte-identical across 77,850 tests).

The fast path is therefore decorative once the MPFR route is in place; we
keep both because the cross-check is the only continuously-running guarantee
that *neither* oracle has drifted. Either route can carry the full corpus
on its own, and a regression in one would surface in `test_reference.py`
before it could ship.

## 7. Decisions

### 7.7 (2026-05-03) -- adopt `gmpy2` for the MPFR oracle

DECIDED: pull `gmpy2` in as a Python dependency now, in parallel with other
input-prep work. The build-from-source-on-some-platforms cost (Windows in
particular) is acceptable; getting MPFR-backed rounding-mode-aware reference
computation in place unblocks non-default-rounding-mode tests (currently
skipped per the README) and gives `_compute_expected_bits` a single source
of truth for every rounding mode.

Implementation notes:

* `gmpy2 >= 2.2.1` declared in `scripts/requirements.txt`; CI installs the
  GMP / MPFR / MPC native libraries in the `generate-tests` job before
  invoking `pip install`.
* `scripts/noir_ieee754_inputs/reference.py` exposes
  `compute_expected_bits(operation, operand_a_bits, operand_b_bits,
  rounding_mode, precision)` returning the IEEE 754 bit pattern of the
  rounded result.
* `_compute_expected_bits` in `scripts/generate_tests.py` keeps the legacy
  fast path for round-to-nearest-even (the only mode the current corpus
  exercises) and routes every other rounding mode through `reference.py`.
* `generate_noir_test` still gates non-RNE cases at the call site --
  unblocking them is a separate decision Jesse hasn't made yet.
* `scripts/test_reference.py` cross-checks the two routes on 8000+ cases.
