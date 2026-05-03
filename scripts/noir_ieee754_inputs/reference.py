"""MPFR-backed reference oracle for IEEE 754 binary arithmetic results.

This module exists so the test generator can compute the *expected* result of
``a op b`` under any IEEE 754 rounding mode, not just round-to-nearest-even
(the only mode the legacy ``float.fromhex`` + ``struct.pack`` route handles).

We use ``gmpy2.mpfr`` configured with a context whose ``precision`` /
``emin`` / ``emax`` / ``subnormalize`` settings match the target IEEE 754
format exactly:

================  =========  ======  ======  ==============
Format            precision  emin    emax    subnormalize
================  =========  ======  ======  ==============
binary32 (f32)    24         -148    128     True
binary64 (f64)    53         -1073   1024    True
================  =========  ======  ======  ==============

(MPFR's ``emin`` is one greater than the IEEE minimum exponent because MPFR
counts from the leading mantissa bit at position 0 rather than from the
implicit-1-and-fraction layout IEEE uses; ``subnormalize=True`` then enables
the gradual-underflow rounding rule, matching IEEE 754 sec 3.4.)

The MPFR result is cast to a native Python float and re-packed via
``struct``. This is exact: every binary32 value is representable in binary64,
and an mpfr at precision=53 within the binary64 exponent range is precisely a
binary64 value -- no double-rounding in either case.

Special values (NaN, +/-Inf) bypass the cast and return the canonical
quiet-NaN / signed-infinity bit patterns from
:mod:`noir_ieee754_inputs.constants`.

The current corpus only exercises round-to-nearest-even, in which case this
route must produce byte-identical results to the legacy ``float`` +
``struct`` route -- ``scripts/test_reference.py`` enforces that.
"""

from __future__ import annotations

import struct
from typing import Optional

from . import constants
from .fptest import Operation, RoundingMode


# MPFR rounding mode mapping. The integer values match the constants exposed by
# ``gmpy2`` (``RoundToNearest`` = 0, ``RoundToZero`` = 1, ``RoundUp`` = 2,
# ``RoundDown`` = 3, ``RoundAwayZero`` = 4). We do not import ``gmpy2`` at
# module load time so that ``constants`` / ``fptest`` consumers can keep
# working when ``gmpy2`` is unavailable.
#
# Note: MPFR's ``RoundAwayZero`` is the IEEE *directed* round-toward-away
# mode (every inexact result moves away from zero, regardless of distance),
# which is *not* IEEE 754's ``roundTiesToAway`` -- the latter is
# round-to-nearest with halfway ties broken by going away from zero. MPFR
# does not expose ``roundTiesToAway`` natively, so we synthesise it in
# :func:`_compute_ties_to_away` by computing at extra precision and
# inspecting the round / sticky bits manually.
_MPFR_ROUND = {
    RoundingMode.NEAREST_EVEN: 0,    # MPFR_RNDN -- IEEE roundTiesToEven
    RoundingMode.TOWARD_ZERO: 1,     # MPFR_RNDZ -- IEEE roundTowardZero
    RoundingMode.TOWARD_POSITIVE: 2, # MPFR_RNDU -- IEEE roundTowardPositive
    RoundingMode.TOWARD_NEGATIVE: 3, # MPFR_RNDD -- IEEE roundTowardNegative
    # NEAREST_AWAY handled separately -- see _compute_ties_to_away.
}


def _import_gmpy2():
    """Lazy import so the rest of the package is usable without gmpy2 installed."""
    try:
        import gmpy2  # type: ignore
    except ImportError as e:  # pragma: no cover - environment problem
        raise RuntimeError(
            "gmpy2 is required for compute_expected_bits(). Install it via "
            "`pip install -r scripts/requirements.txt` (the native deps GMP / "
            "MPFR / MPC must be present first -- see scripts/README.md)."
        ) from e
    return gmpy2


def _ieee_context(gmpy2, precision: int, rounding: RoundingMode):
    """Build a gmpy2 context that mirrors an IEEE 754 binary format.

    binary32: precision=24, emin=-148, emax=128
    binary64: precision=53, emin=-1073, emax=1024

    ``subnormalize=True`` turns on IEEE-style gradual underflow.
    """
    if precision == 24:
        emin, emax = -148, 128
    elif precision == 53:
        emin, emax = -1073, 1024
    else:
        raise ValueError(f"Unsupported IEEE precision: {precision}")
    return gmpy2.context(
        precision=precision,
        emin=emin,
        emax=emax,
        subnormalize=True,
        round=_MPFR_ROUND[rounding],
    )


def _bits_from_mpfr(gmpy2, value, *, is_float32: bool, sign_hint: Optional[int] = None) -> int:
    """Extract IEEE 754 bits from an MPFR value already at the target precision.

    Special-cases NaN / +/-Inf / +/-Zero to canonical bit patterns;
    ``sign_hint`` lets the caller force the sign of an exact zero result
    (MPFR's signed-zero handling is preserved by ``gmpy2.is_signed``).
    """
    if gmpy2.is_nan(value):
        return constants.FLOAT32_NAN if is_float32 else constants.FLOAT64_NAN

    if gmpy2.is_infinite(value):
        if is_float32:
            return constants.FLOAT32_NEG_INFINITY if value < 0 else constants.FLOAT32_INFINITY
        return constants.FLOAT64_NEG_INFINITY if value < 0 else constants.FLOAT64_INFINITY

    if value == 0:
        # MPFR preserves the sign of zero; ``gmpy2.is_signed`` exposes it.
        negative = sign_hint == 1 if sign_hint is not None else gmpy2.is_signed(value)
        if is_float32:
            return constants.FLOAT32_NEG_ZERO if negative else constants.FLOAT32_ZERO
        return constants.FLOAT64_NEG_ZERO if negative else constants.FLOAT64_ZERO

    # Finite non-zero. The mpfr is already at the target precision (24 / 53)
    # and within the IEEE exponent range; round-trip through Python's float
    # is exact (every binary32 is exactly a binary64; an mpfr at precision=53
    # within IEEE binary64 range *is* a binary64).
    f = float(value)
    if is_float32:
        return struct.unpack('>I', struct.pack('>f', f))[0]
    return struct.unpack('>Q', struct.pack('>d', f))[0]


def _bits_to_mpfr(gmpy2, bits: int, *, is_float32: bool):
    """Decode IEEE 754 bits into an mpfr value at the target precision.

    The decode goes via Python's ``float`` (binary64) and ``mpfr(f, precision)``,
    which preserves the value exactly for both binary32 and binary64 inputs.
    NaNs are funnelled to a canonical quiet-NaN; the caller is responsible
    for skipping NaN-result tests before bit comparison anyway.
    """
    if is_float32:
        f = struct.unpack('>f', struct.pack('>I', bits & 0xFFFFFFFF))[0]
        precision = 24
    else:
        f = struct.unpack('>d', struct.pack('>Q', bits & 0xFFFFFFFFFFFFFFFF))[0]
        precision = 53
    return gmpy2.mpfr(f, precision)


def compute_expected_bits(
    operation: Operation,
    operand_a_bits: int,
    operand_b_bits: int,
    rounding_mode: RoundingMode,
    precision: int,
) -> int:
    """Compute the IEEE 754 bits of ``operand_a op operand_b`` via MPFR.

    Args:
      operation: one of :class:`Operation` (only ADD / SUBTRACT / MULTIPLY /
        DIVIDE are currently supported -- FMA / SQRT / REM raise).
      operand_a_bits, operand_b_bits: the operand bit patterns at the target
        precision (32-bit ints for binary32, 64-bit ints for binary64).
      rounding_mode: which IEEE rounding mode to apply.
      precision: 24 for binary32, 53 for binary64.

    Returns:
      The IEEE 754 bit pattern of the rounded result, in the same width as
      the operands (32 bits for f32, 64 bits for f64).

    Raises:
      ValueError: if ``operation`` or ``precision`` is unsupported.
    """
    if precision not in (24, 53):
        raise ValueError(f"Unsupported precision {precision}; expected 24 or 53.")
    if rounding_mode not in _MPFR_ROUND and rounding_mode != RoundingMode.NEAREST_AWAY:
        raise ValueError(f"Unsupported rounding mode {rounding_mode!r}.")

    gmpy2 = _import_gmpy2()
    is_float32 = precision == 24

    if rounding_mode == RoundingMode.NEAREST_AWAY:
        return _compute_ties_to_away(
            gmpy2, operation, operand_a_bits, operand_b_bits, precision
        )

    a = _bits_to_mpfr(gmpy2, operand_a_bits, is_float32=is_float32)
    b = _bits_to_mpfr(gmpy2, operand_b_bits, is_float32=is_float32)

    ctx = _ieee_context(gmpy2, precision, rounding_mode)
    with gmpy2.context(ctx):
        result = _apply_op(gmpy2, operation, a, b)

    return _bits_from_mpfr(gmpy2, result, is_float32=is_float32)


def _apply_op(gmpy2, operation: Operation, a, b):
    if operation == Operation.ADD:
        return a + b
    if operation == Operation.SUBTRACT:
        return a - b
    if operation == Operation.MULTIPLY:
        return a * b
    if operation == Operation.DIVIDE:
        # Division-by-zero in MPFR returns a signed infinity (or NaN for
        # 0/0), matching IEEE 754 sec 7.3 -- no special-casing required.
        return a / b
    raise ValueError(
        f"Operation {operation!r} not yet wired through MPFR; only "
        "ADD / SUBTRACT / MULTIPLY / DIVIDE are supported."
    )


def _compute_ties_to_away(
    gmpy2, operation: Operation, a_bits: int, b_bits: int, precision: int,
) -> int:
    """IEEE 754 roundTiesToAway, synthesised on top of MPFR.

    MPFR doesn't have a native ``roundTiesToAway`` mode (its ``RoundAwayZero``
    is the directed round-away-from-zero mode, which moves every inexact
    result, not just halfway ties). We synthesise it by:

    1. Computing the operation at ``precision + 2`` bits with MPFR_RNDN -- two
       extra bits is enough to capture the IEEE round bit and a sticky-bit
       summary for any of ADD / SUB / MUL / DIV.
    2. Comparing the high-precision result to two candidate
       ``precision``-bit results: round-up (away from zero) and
       round-down (toward zero). For exact results the two agree; for
       inexact non-tie results either RNDU or RNDZ (depending on sign) is
       correct; for halfway ties we deliberately pick round-away.

    The classic boundary-cases (overflow to Inf, underflow to denorm or
    zero) work out correctly because each candidate round itself uses an
    IEEE-shaped MPFR context that handles those.
    """
    is_float32 = precision == 24

    a = _bits_to_mpfr(gmpy2, a_bits, is_float32=is_float32)
    b = _bits_to_mpfr(gmpy2, b_bits, is_float32=is_float32)

    # Extra-precision exact-or-near-exact result, no IEEE clamping yet.
    extra_ctx = gmpy2.context(precision=precision + 8, round=gmpy2.RoundToNearest)
    with gmpy2.context(extra_ctx):
        exact = _apply_op(gmpy2, operation, a, b)

    if gmpy2.is_nan(exact):
        return constants.FLOAT32_NAN if is_float32 else constants.FLOAT64_NAN

    # Toward zero (RNDZ) and away from zero (RNDA) at the target precision.
    ctx_z = _ieee_context_explicit(gmpy2, precision, gmpy2.RoundToZero)
    ctx_a = _ieee_context_explicit(gmpy2, precision, gmpy2.RoundAwayZero)
    with gmpy2.context(ctx_z):
        toward_zero = _apply_op(gmpy2, operation, a, b)
    with gmpy2.context(ctx_a):
        away = _apply_op(gmpy2, operation, a, b)

    # Pick the candidate (toward_zero vs away) closest to ``exact``; ties
    # break to ``away`` per IEEE roundTiesToAway.
    if toward_zero == away:
        # Exact at target precision (or both clamped to the same boundary).
        return _bits_from_mpfr(gmpy2, away, is_float32=is_float32)

    diff_z = abs(exact - toward_zero)
    diff_a = abs(exact - away)
    if diff_a <= diff_z:
        chosen = away
    else:
        chosen = toward_zero
    return _bits_from_mpfr(gmpy2, chosen, is_float32=is_float32)


def _ieee_context_explicit(gmpy2, precision: int, round_mode: int):
    """Like :func:`_ieee_context` but takes a raw MPFR round constant directly."""
    if precision == 24:
        emin, emax = -148, 128
    elif precision == 53:
        emin, emax = -1073, 1024
    else:
        raise ValueError(f"Unsupported IEEE precision: {precision}")
    return gmpy2.context(
        precision=precision,
        emin=emin,
        emax=emax,
        subnormalize=True,
        round=round_mode,
    )
