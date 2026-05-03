"""Parser for IBM FPgen ``.fptest`` floating-point test vector files.

Test file format::

    <precision><op> <rounding> [exception-flags] <operand1> [operand2] [operand3] -> <result> [result-flags]

Where:

- ``precision``: ``b32`` (binary32 / float), ``b64`` (binary64 / double).
- ``op``: ``+`` (add), ``-`` (subtract), ``*`` (multiply), ``/`` (divide),
  ``*+`` (fma), ``V`` (sqrt), ``%`` (rem).
- ``rounding``: ``=0`` (nearest even), ``=^`` (nearest away), ``>`` (toward
  +inf), ``<`` (toward -inf), ``0`` (toward zero).
- Operand format: ``<sign><significand>P<exponent>`` or one of the special
  values ``+Inf``, ``-Inf``, ``+Zero``, ``-Zero``, ``Q``, ``S``.

The parser is a self-contained translation of the IBM FPgen vector grammar
that the noir_IEEE754 test generator consumes.
"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from . import constants


# Known bad test cases in the IBM FPgen test suite (bugs in expected values).
# We match by the operation + operands prefix of the raw line.
KNOWN_BAD_TESTS = {
    # Divide-Divide-By-Zero-Exception.fptest line 6: incorrect expected result.
    # +1.2CEE1BP-64 / +1.50EFBDP-30 should give 0x2E64A490, not 0x2E29F109.
    "b32/ =0 +1.2CEE1BP-64 +1.50EFBDP-30",
    "b32/ =0 oz +1.2CEE1BP-64 +1.50EFBDP-30",  # Same test with overflow flag.
}


# Allow-list for tests the noir_IEEE754 circuits cannot yet pass under
# non-default rounding modes. This mirrors :data:`KNOWN_BAD_TESTS` but is keyed
# on ``(precision_str, operation_str, rounding_str, raw_line)`` -- a fully
# qualified, file-order-stable identifier -- so individual failing cases can
# be skipped at generation time without globally disabling a rounding mode or
# operation. ``raw_line`` is matched against the parsed test's
# :attr:`TestCase.raw_line` (the verbatim ``.fptest`` line, no leading or
# trailing whitespace).
#
# Each entry should carry a one-line comment naming the underlying
# circuit-level bug. Future PRs that fix circuit bugs shrink this set; the
# allow-list size is the f64-hardening progress metric (see
# ``questions/enable-non-default-rounding-modes.md``, decision C).
#
# ``precision_str`` and ``rounding_str`` use the ``.value`` strings of
# :class:`Precision` and :class:`RoundingMode` (e.g. ``"b32"`` / ``"<"``);
# ``operation_str`` uses :attr:`Operation.value` (e.g. ``"+"`` / ``"/"``).
# Helper :func:`is_known_bad_for_rounding` checks membership.
#
# History: this set was bootstrapped on 2026-05-03 against the f32
# add / sub / mul / div circuits with 112 entries spanning four bug
# classes (overflow saturation, underflow flush, sticky-bit
# off-by-one in division near max-finite, and a single f64 cancellation
# signed-zero entry). All four classes are now fixed in
# ``ieee754/src/`` and the set is empty -- the post-PR-#49 directed-
# rounding gap is closed. New entries should be added with a comment
# naming the bug class and the IEEE 754-2019 section that prescribes
# the correct behaviour.
KNOWN_BAD_TESTS_BY_ROUNDING: set[tuple[str, str, str, str]] = set()


def is_known_bad_for_rounding(
    test: "TestCase",
    effective_precision: Optional["Precision"] = None,
) -> bool:
    """Return ``True`` if ``test`` is in :data:`KNOWN_BAD_TESTS_BY_ROUNDING`.

    ``raw_line`` is the verbatim source line; we strip whitespace to match the
    canonicalisation used when entries are added (the parser already strips
    each line before passing it to the constructor, so this is a no-op for
    well-formed entries -- guarded for safety).

    ``effective_precision`` overrides ``test.precision`` for the lookup. The
    test generator uses this when running in ``--generate-f64`` mode: the
    source ``.fptest`` line is binary32 (``b32``), but the *generated* Noir
    test exercises the f64 circuit on the b32 operand re-encoded as b64. An
    f32-circuit failure should not silently skip the f64-circuit version --
    the allow-list must let f32 and f64 entries differ, otherwise it conflates
    coverage of two distinct circuit families. Pass the precision the
    generated test will run against.
    """
    precision_str = (
        effective_precision.value if effective_precision is not None
        else test.precision.value
    )
    key = (
        precision_str,
        test.operation.value,
        test.rounding.value,
        test.raw_line.strip(),
    )
    return key in KNOWN_BAD_TESTS_BY_ROUNDING


class Precision(Enum):
    BINARY32 = "b32"
    BINARY64 = "b64"


class Operation(Enum):
    ADD = "+"
    SUBTRACT = "-"
    MULTIPLY = "*"
    DIVIDE = "/"
    FMA = "*+"
    SQRT = "V"
    REM = "%"


class RoundingMode(Enum):
    NEAREST_EVEN = "=0"
    NEAREST_AWAY = "=^"
    TOWARD_POSITIVE = ">"
    TOWARD_NEGATIVE = "<"
    TOWARD_ZERO = "0"


@dataclass
class FPValue:
    """Represents a floating-point value from the test file."""

    sign: int  # 0 for positive, 1 for negative
    significand: str  # hex string without the leading 1. part
    exponent: int  # unbiased exponent
    is_zero: bool = False
    is_inf: bool = False
    is_nan: bool = False
    is_snan: bool = False  # signaling NaN


@dataclass
class TestCase:
    """Represents a single test case."""

    precision: Precision
    operation: Operation
    rounding: RoundingMode
    operand1: FPValue
    operand2: Optional[FPValue]
    operand3: Optional[FPValue]  # for FMA
    result: FPValue
    exception_flags: str
    line_number: int
    raw_line: str


def parse_fp_value(value_str: str) -> FPValue:
    """Parse a floating-point value from the test file format.

    Format: ``<sign><significand>P<exponent>``.
    Examples: ``+1.01FD72P-118``, ``-0.7FFFFFP-126``, ``+Inf``, ``-Zero``,
    ``Q``, ``S``.
    """
    value_str = value_str.strip()

    if value_str in ("+Inf", "Inf"):
        return FPValue(sign=0, significand="", exponent=0, is_inf=True)
    if value_str == "-Inf":
        return FPValue(sign=1, significand="", exponent=0, is_inf=True)
    if value_str in ("+Zero", "Zero"):
        return FPValue(sign=0, significand="", exponent=0, is_zero=True)
    if value_str == "-Zero":
        return FPValue(sign=1, significand="", exponent=0, is_zero=True)
    if value_str == "Q":  # Quiet NaN
        return FPValue(sign=0, significand="", exponent=0, is_nan=True)
    if value_str == "S":  # Signaling NaN
        return FPValue(sign=0, significand="", exponent=0, is_nan=True, is_snan=True)
    if value_str == "#":  # Generic result (don't care)
        return FPValue(sign=0, significand="", exponent=0, is_nan=True)

    # Regular values: <sign><significand>P<exponent>
    match = re.match(r'^([+-]?)(\d+)\.([0-9A-Fa-f]+)P([+-]?\d+)$', value_str)
    if not match:
        raise ValueError(f"Cannot parse FP value: {value_str}")

    sign_str, int_part, frac_part, exp_str = match.groups()
    sign = 1 if sign_str == '-' else 0
    exponent = int(exp_str)

    significand = int_part + frac_part

    return FPValue(sign=sign, significand=significand, exponent=exponent)


def _float64_to_bits(f: float) -> int:
    """Independent IEEE 754 binary64 bit extraction via ``struct``.

    Goes through the canonical big-endian binary64 layout written by
    ``struct.pack('>d', ...)`` and unpacks as an unsigned 64-bit integer.
    Independent of any hand-rolled bit-twiddling under test.
    """
    return struct.unpack('>Q', struct.pack('>d', f))[0]


def _float32_to_bits(f: float) -> int:
    """Independent IEEE 754 binary32 bit extraction via ``struct``.

    ``struct.pack('>f', ...)`` rounds the input through binary32 using the
    platform's IEEE 754 round-to-nearest-even, mirroring what the f32
    circuit will see. Raises ``OverflowError`` on values whose magnitude
    exceeds the binary32 finite range; callers must handle that path
    explicitly.
    """
    return struct.unpack('>I', struct.pack('>f', f))[0]


def fp_value_to_bits(val: FPValue, is_float32: bool = True) -> int:
    """Convert an ``FPValue`` to IEEE 754 bits.

    Layered implementation, independent of any hand-rolled bit-twiddling:

    1. Special values (``+Inf`` / ``-Inf`` / ``+Zero`` / ``-Zero`` / ``Q`` /
       ``S``) resolve to named bit patterns from
       :mod:`noir_ieee754_inputs.constants`.
    2. Finite values get rendered as a Python hex literal in the form
       ``[+-]0x<int>.<frac>P<exp>`` and parsed with :func:`float.fromhex`,
       which is CPython core and accepts exactly the IBM FPgen syntax
       once a leading ``0x`` is prepended.
    3. The resulting Python ``float`` is repacked via ``struct.pack`` --
       ``'>d'`` for binary64, ``'>f'`` for binary32 (which also performs
       round-to-nearest-even down-rounding from the 64-bit Python value to
       the 32-bit format).
    4. Magnitudes that overflow the binary32 finite range are returned as
       ``+/- FLOAT32_INFINITY`` to match the historical behaviour of the
       hand-rolled implementation -- ``struct.pack('>f', x)`` would raise
       ``OverflowError`` otherwise. Underflow to zero is left to
       :func:`float.fromhex` / ``struct.pack`` themselves, which round to
       nearest-even.

    Round-to-nearest-even is the only rounding mode supported here, which
    matches the current generator (it skips every test with a different
    rounding mode). When non-default rounding modes ship, swap this for an
    MPFR-backed (``gmpy2``) implementation.
    """
    if val.is_nan:
        if val.is_snan:
            # Library-canonical SNaN encoding (decision C.3, 2026-05-03):
            # ``FLOAT32_SIGNALING_NAN`` / ``FLOAT64_SIGNALING_NAN`` are the
            # exact bit patterns the Noir library produces from its own
            # SNaN-handling paths, so emitting them here keeps the generator
            # and the library aligned. NaN-result tests assert via
            # ``floatN_is_nan`` and therefore do not depend on this choice;
            # SNaN *operand* encodings now match the library so quietened
            # expectations (e.g. ``S * x -> qNaN``) round-trip cleanly.
            return (
                constants.FLOAT32_SIGNALING_NAN
                if is_float32
                else constants.FLOAT64_SIGNALING_NAN
            )
        return constants.FLOAT32_NAN if is_float32 else constants.FLOAT64_NAN
    if val.is_inf:
        if is_float32:
            return constants.FLOAT32_NEG_INFINITY if val.sign else constants.FLOAT32_INFINITY
        return constants.FLOAT64_NEG_INFINITY if val.sign else constants.FLOAT64_INFINITY
    if val.is_zero:
        if is_float32:
            return constants.FLOAT32_NEG_ZERO if val.sign else constants.FLOAT32_ZERO
        return constants.FLOAT64_NEG_ZERO if val.sign else constants.FLOAT64_ZERO

    sign_str = "-" if val.sign else "+"
    int_part = val.significand[0]
    frac_hex = val.significand[1:] or "0"
    hex_literal = f"{sign_str}0x{int_part}.{frac_hex}P{val.exponent:+d}"

    try:
        f = float.fromhex(hex_literal)
    except OverflowError:
        # Magnitude exceeded the binary64 finite range. The hand-rolled
        # implementation flushed these to signed infinity in the target
        # format; preserve that contract.
        if is_float32:
            return constants.FLOAT32_NEG_INFINITY if val.sign else constants.FLOAT32_INFINITY
        return constants.FLOAT64_NEG_INFINITY if val.sign else constants.FLOAT64_INFINITY

    if is_float32:
        try:
            return _float32_to_bits(f)
        except OverflowError:
            # Magnitude exceeded the binary32 finite range.
            return constants.FLOAT32_NEG_INFINITY if val.sign else constants.FLOAT32_INFINITY
    return _float64_to_bits(f)


def fp_value_to_bits32(val: FPValue) -> int:
    """Convert an FPValue to IEEE 754 binary32 bits."""
    return fp_value_to_bits(val, is_float32=True)


def fp_value_to_bits64(val: FPValue) -> int:
    """Convert an FPValue to IEEE 754 binary64 bits."""
    return fp_value_to_bits(val, is_float32=False)


def parse_test_line(line: str, line_number: int) -> Optional[TestCase]:
    """Parse a single test line from an .fptest file."""
    line = line.strip()

    if not line or line.startswith('--') or line.startswith('#'):
        return None

    if line.startswith('Floating point tests') or line.startswith('Copyright'):
        return None

    for bad_prefix in KNOWN_BAD_TESTS:
        if line.startswith(bad_prefix):
            return None

    match = re.match(r'^(b32|b64)(\+|-|\*|/|\*\+|V|%)\s+(.*)$', line)
    if not match:
        return None

    precision_str, op_str, rest = match.groups()

    try:
        precision = Precision(precision_str)
    except ValueError:
        return None

    op_map = {
        '+': Operation.ADD,
        '-': Operation.SUBTRACT,
        '*': Operation.MULTIPLY,
        '/': Operation.DIVIDE,
        '*+': Operation.FMA,
        'V': Operation.SQRT,
        '%': Operation.REM,
    }

    if op_str not in op_map:
        return None
    operation = op_map[op_str]

    rounding_match = re.match(r'^(=0|=\^|>|<|0)\s+(.*)$', rest)
    if not rounding_match:
        return None

    rounding_str, rest = rounding_match.groups()

    rounding_map = {
        '=0': RoundingMode.NEAREST_EVEN,
        '=^': RoundingMode.NEAREST_AWAY,
        '>': RoundingMode.TOWARD_POSITIVE,
        '<': RoundingMode.TOWARD_NEGATIVE,
        '0': RoundingMode.TOWARD_ZERO,
    }
    rounding = rounding_map.get(rounding_str)
    if not rounding:
        return None

    exception_flags = ""
    exc_match = re.match(r'^([iI])\s+(.*)$', rest)
    if exc_match:
        exception_flags = exc_match.group(1)
        rest = exc_match.group(2)

    if ' -> ' not in rest:
        return None

    operands_str, result_str = rest.split(' -> ', 1)

    result_parts = result_str.split()
    if not result_parts:
        return None

    result_value_str = result_parts[0]
    result_flags = ' '.join(result_parts[1:]) if len(result_parts) > 1 else ''

    operand_strs = operands_str.split()
    if not operand_strs:
        return None

    try:
        operand1 = parse_fp_value(operand_strs[0])
        operand2 = parse_fp_value(operand_strs[1]) if len(operand_strs) > 1 else None
        operand3 = parse_fp_value(operand_strs[2]) if len(operand_strs) > 2 else None
        result = parse_fp_value(result_value_str)
    except ValueError:
        # Skip malformed values.
        return None

    return TestCase(
        precision=precision,
        operation=operation,
        rounding=rounding,
        operand1=operand1,
        operand2=operand2,
        operand3=operand3,
        result=result,
        exception_flags=exception_flags + result_flags,
        line_number=line_number,
        raw_line=line,
    )


def parse_fptest_file(filepath: str) -> list[TestCase]:
    """Parse all test cases from an .fptest file."""
    tests = []
    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f, 1):
            test = parse_test_line(line, line_num)
            if test:
                tests.append(test)
    return tests
