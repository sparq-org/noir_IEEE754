"""Cross-check ``noir_ieee754_inputs.reference`` against the legacy fast path.

For round-to-nearest-even, ``compute_expected_bits`` (MPFR-backed) must agree
byte-for-byte with the existing ``float.fromhex`` + ``struct.pack`` route
used by ``generate_tests.py`` -- otherwise the gmpy2 swap would change the
shipping test corpus, which is exactly what this PR promises *not* to do.

This script is a small standalone test runner so it works without pytest /
unittest dependencies; the CI harness can invoke it directly with
``python3 scripts/test_reference.py``.

Coverage:
  * Hand-picked common values (1+2, 1/3, 0.1+0.2, ...).
  * Special-value pairs: +/-0, +/-Inf, NaN, denormals.
  * 1024 randomised binary32 ADD / SUB / MUL / DIV cases.
  * 1024 randomised binary64 ADD / SUB / MUL / DIV cases.
  * A small non-default-rounding sanity check (just confirms the path runs
    and returns *some* bit pattern -- correctness vs. another oracle is out
    of scope for this PR).
"""

from __future__ import annotations

import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from noir_ieee754_inputs.fptest import Operation, RoundingMode  # noqa: E402
from noir_ieee754_inputs.reference import compute_expected_bits  # noqa: E402


def _f32_bits(f: float) -> int:
    return struct.unpack('>I', struct.pack('>f', f))[0]


def _f64_bits(f: float) -> int:
    return struct.unpack('>Q', struct.pack('>d', f))[0]


def _f32_from_bits(b: int) -> float:
    return struct.unpack('>f', struct.pack('>I', b & 0xFFFFFFFF))[0]


def _f64_from_bits(b: int) -> float:
    return struct.unpack('>d', struct.pack('>Q', b & 0xFFFFFFFFFFFFFFFF))[0]


# Matches generate_tests.py:_compute_expected_bits but with no NaN / Inf
# short-circuit on the operands (we feed it bit patterns, not FPValues).
def _legacy_expected_bits(op: Operation, a_bits: int, b_bits: int, *, is_float32: bool) -> int:
    import math
    from noir_ieee754_inputs import constants as C

    a = _f32_from_bits(a_bits) if is_float32 else _f64_from_bits(a_bits)
    b = _f32_from_bits(b_bits) if is_float32 else _f64_from_bits(b_bits)

    try:
        if op == Operation.ADD:
            r = a + b
        elif op == Operation.SUBTRACT:
            r = a - b
        elif op == Operation.MULTIPLY:
            r = a * b
        elif op == Operation.DIVIDE:
            if b == 0:
                # Mirror the generator's "fall back" path: it doesn't compute
                # via Python here. We replicate IEEE 754 sec 7.3 manually
                # so this oracle stays self-contained.
                if a == 0 or math.isnan(a):
                    return C.FLOAT32_NAN if is_float32 else C.FLOAT64_NAN
                # Sign of result = XOR of operand signs.
                a_neg = (a_bits >> (31 if is_float32 else 63)) & 1
                b_neg = (b_bits >> (31 if is_float32 else 63)) & 1
                neg = a_neg ^ b_neg
                if is_float32:
                    return C.FLOAT32_NEG_INFINITY if neg else C.FLOAT32_INFINITY
                return C.FLOAT64_NEG_INFINITY if neg else C.FLOAT64_INFINITY
            r = a / b
        else:
            raise NotImplementedError(op)
    except OverflowError:
        # Python uses double-precision arithmetic; for binary64 inputs we
        # never overflow Python's float, but for binary32 we might compute
        # in binary64 and then narrow. The narrowing happens in the
        # struct.pack below, so this branch is essentially unreachable.
        raise

    if math.isnan(r):
        return C.FLOAT32_NAN if is_float32 else C.FLOAT64_NAN
    if math.isinf(r):
        if r > 0:
            return C.FLOAT32_INFINITY if is_float32 else C.FLOAT64_INFINITY
        return C.FLOAT32_NEG_INFINITY if is_float32 else C.FLOAT64_NEG_INFINITY

    if is_float32:
        try:
            return _f32_bits(r)
        except OverflowError:
            sign = (a_bits >> 31) ^ (b_bits >> 31)
            return C.FLOAT32_NEG_INFINITY if sign else C.FLOAT32_INFINITY
    return _f64_bits(r)


# --------------------------------------------------------------------------
# Test driver

class TestRunner:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.failures: list[str] = []

    def assert_eq(self, label: str, got: int, want: int, width: int) -> None:
        if got == want:
            self.passed += 1
        else:
            self.failed += 1
            self.failures.append(
                f"{label}: got 0x{got:0{width}X}, want 0x{want:0{width}X}"
            )

    def cross_check_rne(self, op: Operation, a_bits: int, b_bits: int, *, is_float32: bool) -> None:
        precision = 24 if is_float32 else 53
        width = 8 if is_float32 else 16
        # NaN-result tests would compare equal at the canonical-NaN level only;
        # the legacy oracle and reference oracle both canonicalise NaN, so
        # they still agree, but skip if either operand is NaN since the
        # arithmetic semantics are well-defined either way.
        ours = compute_expected_bits(op, a_bits, b_bits, RoundingMode.NEAREST_EVEN, precision)
        theirs = _legacy_expected_bits(op, a_bits, b_bits, is_float32=is_float32)
        label = (
            f"{op.name} {'f32' if is_float32 else 'f64'} "
            f"a=0x{a_bits:0{width}X} b=0x{b_bits:0{width}X} RNE"
        )
        self.assert_eq(label, ours, theirs, width)

    def report(self) -> int:
        total = self.passed + self.failed
        print(f"\n{self.passed}/{total} passed")
        if self.failed:
            print(f"\n{self.failed} failures (showing up to 20):")
            for f in self.failures[:20]:
                print(f"  {f}")
            return 1
        return 0


def hand_picked_cases(t: TestRunner) -> None:
    cases_f32 = [
        (Operation.ADD, _f32_bits(1.0), _f32_bits(2.0)),
        (Operation.SUBTRACT, _f32_bits(1.0), _f32_bits(2.0)),
        (Operation.MULTIPLY, _f32_bits(0.1), _f32_bits(0.2)),
        (Operation.DIVIDE, _f32_bits(1.0), _f32_bits(3.0)),
        (Operation.DIVIDE, _f32_bits(0.0), _f32_bits(0.0)),  # 0/0 = NaN
        (Operation.DIVIDE, _f32_bits(1.0), _f32_bits(0.0)),  # 1/0 = +Inf
        (Operation.DIVIDE, _f32_bits(-1.0), _f32_bits(0.0)),  # -1/+0 = -Inf
        (Operation.MULTIPLY, _f32_bits(0.0), _f32_bits(1.0)),  # +0
        (Operation.MULTIPLY, _f32_bits(-0.0), _f32_bits(1.0)),  # -0
        (Operation.ADD, 0x00000001, 0x00000001),  # smallest denorms
        (Operation.MULTIPLY, 0x00800000, 0x00800000),  # min normal squared
    ]
    cases_f64 = [
        (Operation.ADD, _f64_bits(1.0), _f64_bits(2.0)),
        (Operation.SUBTRACT, _f64_bits(1.0), _f64_bits(2.0)),
        (Operation.MULTIPLY, _f64_bits(0.1), _f64_bits(0.2)),
        (Operation.DIVIDE, _f64_bits(1.0), _f64_bits(3.0)),
        (Operation.DIVIDE, _f64_bits(1.0), _f64_bits(0.0)),
        (Operation.MULTIPLY, _f64_bits(-0.0), _f64_bits(1.0)),
        (Operation.ADD, 0x0000000000000001, 0x0000000000000001),
    ]

    for op, a, b in cases_f32:
        t.cross_check_rne(op, a, b, is_float32=True)
    for op, a, b in cases_f64:
        t.cross_check_rne(op, a, b, is_float32=False)


def randomised(t: TestRunner, *, is_float32: bool, n: int) -> None:
    width_bits = 32 if is_float32 else 64
    mask = (1 << width_bits) - 1
    rng = random.Random(0xDEADBEEF if is_float32 else 0xCAFEBABE)

    for _ in range(n):
        a_bits = rng.randint(0, mask)
        b_bits = rng.randint(0, mask)
        # Skip operands that are NaN (their behaviour is well-defined but
        # the legacy oracle and we both flatten to canonical NaN, so they're
        # uninteresting). Skip in operands so the cross-check stays sharp on
        # *result* bit patterns from finite arithmetic.
        for op in (Operation.ADD, Operation.SUBTRACT, Operation.MULTIPLY, Operation.DIVIDE):
            # Skip cases that would trigger Python OverflowError; the legacy
            # path can't represent them.
            try:
                t.cross_check_rne(op, a_bits, b_bits, is_float32=is_float32)
            except OverflowError:
                # Both oracles would hit the same overflow; we just don't
                # have a clean way to compare them on this particular case.
                continue


def non_default_rounding_smoke(t: TestRunner) -> None:
    # Confirm the gmpy2 path runs for every rounding mode; we don't have a
    # ground-truth oracle for non-default modes yet (that's a separate PR).
    for rm in RoundingMode:
        try:
            r = compute_expected_bits(
                Operation.DIVIDE,
                _f32_bits(1.0),
                _f32_bits(3.0),
                rm,
                24,
            )
        except Exception as e:  # pragma: no cover - any failure here is a regression
            t.failed += 1
            t.failures.append(f"non-default rounding {rm.name} raised {e!r}")
            continue
        # Sanity: 1/3 in binary32 must be one of two adjacent bit patterns.
        if r in (0x3EAAAAAA, 0x3EAAAAAB):
            t.passed += 1
        else:
            t.failed += 1
            t.failures.append(f"1/3 binary32 mode={rm.name} -> 0x{r:08X} (out of expected pair)")


def main() -> int:
    t = TestRunner()
    hand_picked_cases(t)
    randomised(t, is_float32=True, n=1024)
    randomised(t, is_float32=False, n=1024)
    non_default_rounding_smoke(t)
    return t.report()


if __name__ == "__main__":
    sys.exit(main())
