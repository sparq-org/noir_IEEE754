"""Smoke-check the MPFR oracle against the binary32 ADD corpus.

Round-1 spike (2026-05-04): the MPFR-driven equivalence proof against
``noir/lib/reference::add_f32_reference`` is gated by a follow-up PR (see
``noir/lib/reference/README.md`` for the methodology). For now this script
only confirms that the MPFR oracle (``noir_ieee754_inputs.reference``)
returns a 32-bit value over the round-1 corpus -- it surfaces an
oracle-side regression early, before the nargo-driven equivalence loop
lands.

The reference-vs-optimised equivalence is exercised today by
``nargo test --package reference_tests`` (Noir-side ``#[test]`` smoke
suite); the long-term equivalence gate is the Lean proof tracked in the
parent ``zkp-sparql-workspace`` repo at
``proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/AddF32.lean``.

Invocation::

    cd circuits/noir_IEEE754
    python3 scripts/test_reference_equivalence.py
"""

from __future__ import annotations

import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from noir_ieee754_inputs.fptest import Operation, RoundingMode  # noqa: E402
from noir_ieee754_inputs.reference import compute_expected_bits  # noqa: E402


# Corpus matches `test_reference.py` and adds the §6.3 / §7.4 edge cases.
def _f32_bits(f: float) -> int:
    return struct.unpack(">I", struct.pack(">f", f))[0]


HAND_CASES: list[tuple[int, int, RoundingMode]] = [
    (_f32_bits(1.0), _f32_bits(2.0), RoundingMode.NEAREST_EVEN),
    (_f32_bits(0.1), _f32_bits(0.2), RoundingMode.NEAREST_EVEN),
    (0x00000000, 0x00000000, RoundingMode.NEAREST_EVEN),
    (0x00000000, 0x80000000, RoundingMode.NEAREST_EVEN),  # +0 + -0 -> +0 (RNE)
    (0x00000000, 0x80000000, RoundingMode.TOWARD_NEGATIVE),  # +0 + -0 -> -0
    (0x80000000, 0x80000000, RoundingMode.NEAREST_EVEN),  # -0 + -0 -> -0
    (0x7F800000, 0xFF800000, RoundingMode.NEAREST_EVEN),  # +Inf + -Inf -> NaN
    (0x7F800000, 0x3F800000, RoundingMode.NEAREST_EVEN),  # +Inf + 1 -> +Inf
    (0x7FC00000, 0x3F800000, RoundingMode.NEAREST_EVEN),  # NaN propagates
    (0x00000001, 0x00000001, RoundingMode.NEAREST_EVEN),  # smallest denorms
    (0x00800000, 0x80800000, RoundingMode.NEAREST_EVEN),  # min normal cancels
    (0x3F800000, 0xBF800000, RoundingMode.NEAREST_EVEN),  # 1 + -1 -> +0 (RNE)
    (0x3F800000, 0xBF800000, RoundingMode.TOWARD_NEGATIVE),  # 1 + -1 -> -0
    (0x7F7FFFFF, 0x7F7FFFFF, RoundingMode.NEAREST_EVEN),  # max + max -> +Inf
    (0x7F7FFFFF, 0x7F7FFFFF, RoundingMode.TOWARD_ZERO),  # -> +max-finite
    (0x3F800000, 0x33800000, RoundingMode.NEAREST_EVEN),  # halfway tie RNE
    (0x3F800000, 0x33800000, RoundingMode.NEAREST_AWAY),  # halfway tie RTA
    (0x3F800000, 0x33800000, RoundingMode.TOWARD_POSITIVE),
]


def main() -> int:
    rng = random.Random(0xADD32EF)
    cases = list(HAND_CASES)
    # Add a handful of randomised cases per rounding mode.
    for mode in (
        RoundingMode.NEAREST_EVEN,
        RoundingMode.NEAREST_AWAY,
        RoundingMode.TOWARD_POSITIVE,
        RoundingMode.TOWARD_NEGATIVE,
        RoundingMode.TOWARD_ZERO,
    ):
        for _ in range(32):
            a = rng.randint(0, 0xFFFFFFFF)
            b = rng.randint(0, 0xFFFFFFFF)
            cases.append((a, b, mode))

    # MPFR-only smoke-check: confirm the oracle returns a 32-bit value
    # over every corpus entry. The reference-vs-optimised equivalence
    # itself runs via `nargo test --package reference_tests`.
    print(f"corpus size: {len(cases)}")
    failures = 0
    for a_bits, b_bits, mode in cases:
        oracle = compute_expected_bits(Operation.ADD, a_bits, b_bits, mode, 24)
        if oracle < 0 or oracle > 0xFFFFFFFF:
            failures += 1
            print(f"oracle out of range for a=0x{a_bits:08X} b=0x{b_bits:08X} mode={mode.name}: {oracle}")
    if failures:
        print(f"{failures} oracle-range failures")
        return 1
    print(f"OK: {len(cases)} cases evaluated against MPFR oracle without errors.")
    print("Reference-vs-optimised equivalence is gated by `nargo test --package reference_tests`")
    print("  and (long term) by the workspace Lean proof "
          "`proofs/Ieee754/ZkpSparql/Ieee754/Equivalence/AddF32.lean`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
