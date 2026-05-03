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
from dataclasses import dataclass
from enum import Enum
from typing import Optional


# Known bad test cases in the IBM FPgen test suite (bugs in expected values).
# We match by the operation + operands prefix of the raw line.
KNOWN_BAD_TESTS = {
    # Divide-Divide-By-Zero-Exception.fptest line 6: incorrect expected result.
    # +1.2CEE1BP-64 / +1.50EFBDP-30 should give 0x2E64A490, not 0x2E29F109.
    "b32/ =0 +1.2CEE1BP-64 +1.50EFBDP-30",
    "b32/ =0 oz +1.2CEE1BP-64 +1.50EFBDP-30",  # Same test with overflow flag.
}


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


# Special bit patterns for IEEE 754 (kept for fp_value_to_bits; phase 2c will
# replace this hand-rolled bit decomposition with a float.fromhex + struct
# pipeline).
_FLOAT32_SPECIAL = {
    'qnan': 0x7FC00000,
    'snan': 0x7F800001,
    'pos_inf': 0x7F800000,
    'neg_inf': 0xFF800000,
    'pos_zero': 0x00000000,
    'neg_zero': 0x80000000,
}

_FLOAT64_SPECIAL = {
    'qnan': 0x7FF8000000000000,
    'snan': 0x7FF0000000000001,
    'pos_inf': 0x7FF0000000000000,
    'neg_inf': 0xFFF0000000000000,
    'pos_zero': 0x0000000000000000,
    'neg_zero': 0x8000000000000000,
}


def fp_value_to_bits(val: FPValue, is_float32: bool = True) -> int:
    """Convert an FPValue to IEEE 754 bits using direct bit manipulation.

    The test format uses 24 bits (6 hex digits) for float32 mantissa and
    52 bits (13 hex digits) for float64. We convert directly to avoid
    precision loss from Python float arithmetic.
    """
    special = _FLOAT32_SPECIAL if is_float32 else _FLOAT64_SPECIAL

    if val.is_nan:
        return special['snan'] if val.is_snan else special['qnan']
    if val.is_inf:
        return special['neg_inf'] if val.sign else special['pos_inf']
    if val.is_zero:
        return special['neg_zero'] if val.sign else special['pos_zero']

    int_part = int(val.significand[0])
    frac_hex = val.significand[1:]

    if is_float32:
        # Float32: 23-bit mantissa, 8-bit exponent (bias 127).
        EXP_BIAS = 127
        EXP_MAX = 254
        # Test format uses 6 hex digits = 24 bits, we need 23. Pad/truncate to
        # exactly 6 hex digits, then round to nearest, ties to even. No sticky
        # bits apply here, so the half-way tie reduces to "round up only when
        # the LSB of the result is odd".
        frac_hex_padded = frac_hex.ljust(6, '0')[:6]
        frac_bits_24 = int(frac_hex_padded, 16)
        lsb = (frac_bits_24 >> 1) & 1
        round_bit = frac_bits_24 & 1
        frac_bits_23 = frac_bits_24 >> 1
        if round_bit and lsb:
            frac_bits_23 += 1
        mantissa = frac_bits_23 & 0x7FFFFF
    else:
        # Float64: 52-bit mantissa, 11-bit exponent (bias 1023).
        EXP_BIAS = 1023
        EXP_MAX = 2046
        frac_hex_padded = frac_hex.ljust(13, '0')[:13]
        mantissa = int(frac_hex_padded, 16) & ((1 << 52) - 1)

    biased_exp = val.exponent + EXP_BIAS

    if int_part == 0:
        # Denormal: exponent field is 0, mantissa as-is.
        biased_exp = 0
    elif biased_exp <= 0:
        # Underflow to denormal.
        biased_exp = 0
    elif biased_exp > EXP_MAX:
        # Overflow to infinity.
        return special['neg_inf'] if val.sign else special['pos_inf']

    if is_float32:
        bits = (val.sign << 31) | (biased_exp << 23) | mantissa
    else:
        bits = (val.sign << 63) | (biased_exp << 52) | mantissa

    return bits


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
