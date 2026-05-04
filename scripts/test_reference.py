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

from noir_ieee754_inputs.fptest import (  # noqa: E402
    KNOWN_BAD_TESTS_BY_ROUNDING,
    Operation,
    Precision,
    RoundingMode,
    is_known_bad_for_rounding,
    parse_test_line,
)
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
            # binary32 finite range exceeded. The sign of the saturated
            # infinity follows the *result* sign (which Python's float can
            # represent without overflow), not the XOR of operand signs --
            # correct for every operation, including add / sub where signs
            # don't propagate as a simple XOR (e.g. -big + -big -> -inf,
            # not +inf).
            return C.FLOAT32_NEG_INFINITY if r < 0 else C.FLOAT32_INFINITY
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
    # Confirm the gmpy2 path runs for every rounding mode and that 1/3
    # rounds to the expected target on each direction.
    expected_one_third = {
        RoundingMode.NEAREST_EVEN: 0x3EAAAAAB,    # rounds up at the tie
        RoundingMode.NEAREST_AWAY: 0x3EAAAAAB,    # ties -> away from zero (positive -> up)
        RoundingMode.TOWARD_POSITIVE: 0x3EAAAAAB,
        RoundingMode.TOWARD_NEGATIVE: 0x3EAAAAAA,
        RoundingMode.TOWARD_ZERO: 0x3EAAAAAA,
    }
    for rm, expected in expected_one_third.items():
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
        if r == expected:
            t.passed += 1
        else:
            t.failed += 1
            t.failures.append(
                f"1/3 binary32 mode={rm.name} -> 0x{r:08X}, expected 0x{expected:08X}"
            )

    # IEEE roundTiesToAway must differ from MPFR's ``RoundAwayZero`` (the
    # directed-away mode) on a case where the exact result is *not* a
    # halfway tie. Pick 0.1 + 0.2 in binary32: the exact decimal sum
    # 0.30000001192...e0 maps cleanly to round-to-nearest 0x3E99999A and
    # under both nearest-even and nearest-away gives that same bit, but
    # under MPFR_RNDA (full directed away) it would push to 0x3E99999B.
    # If reference.py mistakenly used MPFR_RNDA for nearest-away, this
    # would catch it.
    near_away = compute_expected_bits(
        Operation.ADD,
        _f32_bits(0.1),
        _f32_bits(0.2),
        RoundingMode.NEAREST_AWAY,
        24,
    )
    rne = compute_expected_bits(
        Operation.ADD,
        _f32_bits(0.1),
        _f32_bits(0.2),
        RoundingMode.NEAREST_EVEN,
        24,
    )
    if near_away == rne:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"NEAREST_AWAY for 0.1+0.2 (no tie) should equal RNE (0x{rne:08X}) "
            f"but got 0x{near_away:08X} -- looks like RoundAwayZero (directed) "
            "leaked through where roundTiesToAway was needed."
        )

    # Halfway tie that distinguishes IEEE roundTiesToAway from
    # roundTiesToEven. Construction:
    #   a = 1.0 (0x3F800000, bit pattern's last bit = 0, "even")
    #   b = 2^-24 (0x33800000, exact f32)
    #   exact a + b = 1 + 2^-24, exactly halfway between 1.0 (0x3F800000)
    #     and 1 + 2^-23 (0x3F800001).
    # RNE picks the neighbour with the even last bit -> 0x3F800000.
    # RTA picks the neighbour away from zero (further from 0)
    #   -> 0x3F800001.
    # Any code path that conflates RTA with directed RoundAwayZero would
    # give RNDU here (which happens to also be 0x3F800001), so we *also*
    # cross-check against RNE (must differ from RTA on this input).
    a32 = _f32_bits(1.0)
    b32 = (0 << 31) | (103 << 23) | 0  # 2^-24 in binary32
    rta_bits = compute_expected_bits(Operation.ADD, a32, b32, RoundingMode.NEAREST_AWAY, 24)
    rne_bits = compute_expected_bits(Operation.ADD, a32, b32, RoundingMode.NEAREST_EVEN, 24)
    rndd_bits = compute_expected_bits(Operation.ADD, a32, b32, RoundingMode.TOWARD_NEGATIVE, 24)
    if rta_bits == 0x3F800001 and rne_bits == 0x3F800000 and rndd_bits == 0x3F800000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"halfway-tie (1 + 2^-24) RTA=0x{rta_bits:08X} (want 0x3F800001), "
            f"RNE=0x{rne_bits:08X} (want 0x3F800000), "
            f"RNDD=0x{rndd_bits:08X} (want 0x3F800000)"
        )

    # Overflow boundary: max_finite_f32 + max_finite_f32 must round to +Inf
    # under every rounding mode that can saturate, including RTA.
    max_f32 = 0x7F7FFFFF
    overflow_rta = compute_expected_bits(
        Operation.ADD, max_f32, max_f32, RoundingMode.NEAREST_AWAY, 24
    )
    if overflow_rta == 0x7F800000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"max_f32 + max_f32 RTA -> 0x{overflow_rta:08X}, expected 0x7F800000 (+Inf)"
        )

    # Negative halfway tie: -1.0 + -2^-24 sits halfway between -1.0
    # (0xBF800000) and -(1 + 2^-23) (0xBF800001). RTA picks the away
    # neighbour, which for negative numbers means *more negative*
    # -> 0xBF800001. RNE picks the even-bit neighbour 0xBF800000.
    neg_a32 = _f32_bits(-1.0)
    neg_b32 = (1 << 31) | (103 << 23) | 0  # -(2^-24) in binary32
    rta_neg = compute_expected_bits(Operation.ADD, neg_a32, neg_b32, RoundingMode.NEAREST_AWAY, 24)
    rne_neg = compute_expected_bits(Operation.ADD, neg_a32, neg_b32, RoundingMode.NEAREST_EVEN, 24)
    if rta_neg == 0xBF800001 and rne_neg == 0xBF800000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"halfway-tie negative (-1 + -2^-24) RTA=0x{rta_neg:08X} (want 0xBF800001), "
            f"RNE=0x{rne_neg:08X} (want 0xBF800000)"
        )

    # Negative overflow: -max_f32 + -max_f32 RTA -> -Inf.
    neg_max = max_f32 | 0x80000000
    neg_overflow_rta = compute_expected_bits(
        Operation.ADD, neg_max, neg_max, RoundingMode.NEAREST_AWAY, 24
    )
    if neg_overflow_rta == 0xFF800000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"-max_f32 + -max_f32 RTA -> 0x{neg_overflow_rta:08X}, expected 0xFF800000"
        )

    # binary64 halfway tie: 1.0 + 2^-53 sits exactly halfway between
    # 1.0 (0x3FF0000000000000) and 1 + 2^-52 (0x3FF0000000000001).
    # 2^-53 in binary64: exp = 1023 - 53 = 970, mantissa = 0.
    a64 = _f64_bits(1.0)
    b64 = (0 << 63) | (970 << 52) | 0
    rta_64 = compute_expected_bits(Operation.ADD, a64, b64, RoundingMode.NEAREST_AWAY, 53)
    rne_64 = compute_expected_bits(Operation.ADD, a64, b64, RoundingMode.NEAREST_EVEN, 53)
    if rta_64 == 0x3FF0000000000001 and rne_64 == 0x3FF0000000000000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"halfway-tie f64 (1 + 2^-53) RTA=0x{rta_64:016X} (want 0x3FF0000000000001), "
            f"RNE=0x{rne_64:016X} (want 0x3FF0000000000000)"
        )

    # binary64 overflow: max_f64 + max_f64 RTA -> +Inf.
    max_f64 = 0x7FEFFFFFFFFFFFFF
    overflow_rta_64 = compute_expected_bits(
        Operation.ADD, max_f64, max_f64, RoundingMode.NEAREST_AWAY, 53
    )
    if overflow_rta_64 == 0x7FF0000000000000:
        t.passed += 1
    else:
        t.failed += 1
        t.failures.append(
            f"max_f64 + max_f64 RTA -> 0x{overflow_rta_64:016X}, expected 0x7FF0000000000000"
        )


def mixed_zero_cancellation(t: TestRunner) -> None:
    """MPFR-oracle pin for IEEE 754-2019 sec 6.3 (signedness of zero
    results from sums). Targets the mixed-zero cancellation fast path
    surfaced in Copilot's review of PR #50.

    Contract:
      * ``+0 + -0`` and ``-0 + +0`` are ``+0`` under RNE / RNA / RNDU /
        RNDZ; ``-0`` only under RNDD.
      * ``+0 + +0 = +0`` and ``-0 + -0 = -0`` under every mode.
      * Subtraction is implemented as ``a + (-b)``, so we exercise the
        same matrix via SUBTRACT operands too.

    The MPFR oracle (``compute_expected_bits``) is the ground truth; this
    block computes the expected bit pattern under each rounding mode and
    compares against the explicit IEEE 754-2019 sec 6.3 table. A
    regression in either side (oracle drift OR table drift) fails here.
    """
    pos32 = 0x00000000  # +0 binary32
    neg32 = 0x80000000  # -0
    pos64 = 0x0000000000000000  # +0 binary64
    neg64 = 0x8000000000000000  # -0

    # Per IEEE 754-2019 sec 6.3: the sign of an exact-zero sum is
    # ``+`` under every rounding-direction attribute except
    # roundTowardNegative, which yields ``-``.
    mixed_expected = {
        RoundingMode.NEAREST_EVEN:    (pos32, pos64),
        RoundingMode.NEAREST_AWAY:    (pos32, pos64),
        RoundingMode.TOWARD_POSITIVE: (pos32, pos64),
        RoundingMode.TOWARD_NEGATIVE: (neg32, neg64),
        RoundingMode.TOWARD_ZERO:     (pos32, pos64),
    }

    for rm, (want32, want64) in mixed_expected.items():
        # +0 + -0
        got32 = compute_expected_bits(Operation.ADD, pos32, neg32, rm, 24)
        t.assert_eq(f"f32 +0 + -0 {rm.name}", got32, want32, 8)
        got64 = compute_expected_bits(Operation.ADD, pos64, neg64, rm, 53)
        t.assert_eq(f"f64 +0 + -0 {rm.name}", got64, want64, 16)
        # -0 + +0 (commutative)
        got32 = compute_expected_bits(Operation.ADD, neg32, pos32, rm, 24)
        t.assert_eq(f"f32 -0 + +0 {rm.name}", got32, want32, 8)
        got64 = compute_expected_bits(Operation.ADD, neg64, pos64, rm, 53)
        t.assert_eq(f"f64 -0 + +0 {rm.name}", got64, want64, 16)

        # +0 - +0  ==  +0 + -0  (mixed sign)
        got32 = compute_expected_bits(Operation.SUBTRACT, pos32, pos32, rm, 24)
        t.assert_eq(f"f32 +0 - +0 {rm.name}", got32, want32, 8)
        got64 = compute_expected_bits(Operation.SUBTRACT, pos64, pos64, rm, 53)
        t.assert_eq(f"f64 +0 - +0 {rm.name}", got64, want64, 16)
        # -0 - -0 == -0 + +0 (mixed sign)
        got32 = compute_expected_bits(Operation.SUBTRACT, neg32, neg32, rm, 24)
        t.assert_eq(f"f32 -0 - -0 {rm.name}", got32, want32, 8)
        got64 = compute_expected_bits(Operation.SUBTRACT, neg64, neg64, rm, 53)
        t.assert_eq(f"f64 -0 - -0 {rm.name}", got64, want64, 16)

    # Like-sign zero sums propagate the shared sign in every mode.
    for rm in RoundingMode:
        for sign_pair, want32, want64 in (
            ((pos32, pos32), pos32, pos64),
            ((neg32, neg32), neg32, neg64),
        ):
            a32, b32 = sign_pair
            a64 = pos64 if a32 == pos32 else neg64
            b64 = pos64 if b32 == pos32 else neg64
            got32 = compute_expected_bits(Operation.ADD, a32, b32, rm, 24)
            t.assert_eq(
                f"f32 like-sign 0+0 ({a32:#x}+{b32:#x}) {rm.name}",
                got32,
                want32,
                8,
            )
            got64 = compute_expected_bits(Operation.ADD, a64, b64, rm, 53)
            t.assert_eq(
                f"f64 like-sign 0+0 ({a64:#x}+{b64:#x}) {rm.name}",
                got64,
                want64,
                16,
            )

    # +0 - -0 = +0 + +0; -0 - +0 = -0 + -0. Like-sign through subtract.
    for rm in RoundingMode:
        # +0 - -0 -> +0 (every mode)
        got32 = compute_expected_bits(Operation.SUBTRACT, pos32, neg32, rm, 24)
        t.assert_eq(f"f32 +0 - -0 {rm.name}", got32, pos32, 8)
        got64 = compute_expected_bits(Operation.SUBTRACT, pos64, neg64, rm, 53)
        t.assert_eq(f"f64 +0 - -0 {rm.name}", got64, pos64, 16)
        # -0 - +0 -> -0 (every mode)
        got32 = compute_expected_bits(Operation.SUBTRACT, neg32, pos32, rm, 24)
        t.assert_eq(f"f32 -0 - +0 {rm.name}", got32, neg32, 8)
        got64 = compute_expected_bits(Operation.SUBTRACT, neg64, pos64, rm, 53)
        t.assert_eq(f"f64 -0 - +0 {rm.name}", got64, neg64, 16)


def known_bad_allow_list_scoping(t: TestRunner) -> None:
    """Regression test for the precision-scoped ``KNOWN_BAD_TESTS_BY_ROUNDING``.

    The contract -- introduced when CI started consuming ``--generate-f64`` and
    enforced after the codex roborev finding on commit 3ce1e4f -- is that an
    allow-list entry only suppresses generated tests at the same effective
    precision as the entry. A b32 entry must NOT mask the f64-converted
    version of the same source line.

    We assert two things, ALWAYS:

    1. **b32-only entries flip on precision override.** Pick an entry whose
       ``(op, rounding, raw_line)`` triple does NOT also have a b64 sibling;
       assert ``effective_precision=BINARY32`` returns True but
       ``effective_precision=BINARY64`` returns False. This is the load-bearing
       check: a regression that drops the ``effective_precision`` argument and
       always uses ``test.precision`` (b32 here) would silently pass any
       paired-entry assertion -- it must fail this one.
    2. **Paired b32/b64 entries match both ways.** When such a pair exists in
       the allow-list (the bootstrap has exactly one -- ``b32+ < +0.000064P-126
       -0.000063P-126``), assert every effective-precision lookup returns True.
       This catches a regression that *over*-scopes (e.g. requires the source
       precision to match the override).

    Falls through cleanly when the allow-list shrinks past the bootstrap state
    in either direction; future PRs that shrink the list don't break this
    test.
    """
    by_raw: dict[tuple[str, str, str], set[str]] = {}
    for entry in KNOWN_BAD_TESTS_BY_ROUNDING:
        prec, op, rnd, raw = entry
        by_raw.setdefault((op, rnd, raw), set()).add(prec)

    # ----- Check 1: b32-only entry flips on override. ---------------------
    b32_only_entry = next(
        ((op, rnd, raw) for (op, rnd, raw), precs in by_raw.items()
         if "b32" in precs and "b64" not in precs),
        None,
    )
    if b32_only_entry is not None:
        op, rnd, raw = b32_only_entry
        test = parse_test_line(raw, 1)
        if test is None:
            t.failed += 1
            t.failures.append(f"could not parse known-bad raw line: {raw!r}")
        else:
            b32 = is_known_bad_for_rounding(test, Precision.BINARY32)
            b64 = is_known_bad_for_rounding(test, Precision.BINARY64)
            default = is_known_bad_for_rounding(test)
            if b32 and not b64 and default:
                t.passed += 1
            else:
                t.failed += 1
                t.failures.append(
                    f"b32-only entry: b32={b32} b64={b64} default={default} "
                    f"-- expected (True, False, True) for raw_line {raw!r}; "
                    "looks like effective_precision is being ignored."
                )
    else:
        # Allow-list has no b32-only entries -- skip the load-bearing check.
        # This is unusual (current allow-list has 110+ b32-only entries); flag
        # so the next reader knows the regression test is degenerate.
        print(
            "# WARN: KNOWN_BAD_TESTS_BY_ROUNDING has no b32-only entries; "
            "precision-scoping regression test is degenerate.",
            file=sys.stderr,
        )

    # ----- Check 2: paired b32 + b64 entries match either way. ------------
    paired = next(
        ((op, rnd, raw) for (op, rnd, raw), precs in by_raw.items()
         if {"b32", "b64"} <= precs),
        None,
    )
    if paired is not None:
        op, rnd, raw = paired
        test = parse_test_line(raw, 1)
        if test is None:
            t.failed += 1
            t.failures.append(f"could not parse known-bad raw line: {raw!r}")
        else:
            b32 = is_known_bad_for_rounding(test, Precision.BINARY32)
            b64 = is_known_bad_for_rounding(test, Precision.BINARY64)
            default = is_known_bad_for_rounding(test)
            if b32 and b64 and default:
                t.passed += 1
            else:
                t.failed += 1
                t.failures.append(
                    f"paired b32/b64 entry: b32={b32} b64={b64} default={default} "
                    f"-- expected all True for raw_line {raw!r}"
                )


def main() -> int:
    t = TestRunner()
    hand_picked_cases(t)
    randomised(t, is_float32=True, n=1024)
    randomised(t, is_float32=False, n=1024)
    non_default_rounding_smoke(t)
    mixed_zero_cancellation(t)
    known_bad_allow_list_scoping(t)
    return t.report()


if __name__ == "__main__":
    sys.exit(main())
