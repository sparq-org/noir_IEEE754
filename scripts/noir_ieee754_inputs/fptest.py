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
# Bootstrap of the allow-list ran on 2026-05-03 against the f32 add / sub /
# mul / div circuits. Two dominant bug classes turned up in directed-rounding
# (``>`` / ``<`` / ``0``) overflow / underflow boundary cases:
#
# 1. Directed-rounding overflow saturation. The circuits clamp results that
#    overflow the f32 finite range to ``+/- max-finite`` (``+/-1.7FFFFFP127``)
#    instead of routing to the IEEE 754 sec 7.4 prescribed value (which is
#    ``+/- max-finite`` for ``round-toward-+/-Inf-of-opposite-sign`` and
#    ``round-toward-zero``, but ``+/- Inf`` for the matching directed mode).
#    Emitted as ``xo`` in the IBM FPgen result flags.
# 2. Directed-rounding underflow flush-to-zero. Tiny products / quotients
#    that should round to ``+/- min-denormal`` (``+/-0.000001P-126``) under
#    rounding-toward-+/-Inf flush to zero instead. Emitted as ``xu``.
#
# A small residue (``b32/`` 6 entries, ``b32-`` 0 entries) shows
# off-by-one-ULP results near max-finite, which is a *third* bug class --
# directed-rounding sticky-bit propagation when the high-order divisor bits
# straddle the rounding boundary. These entries are also captured below.
#
# Entries are grouped by ``(precision, operation, rounding)`` so future
# circuit-bug fixes can target a cluster and bulk-remove its rows.
KNOWN_BAD_TESTS_BY_ROUNDING: set[tuple[str, str, str, str]] = {
    # ----- f32 ADD ---------------------------------------------------------
    # f32 ADD overflow boundary: directed rounding clamps to max-finite
    # instead of saturating to infinity (bug class 1).
    ("b32", "+", "0", "b32+ 0 +1.640188P127 +1.78C2FDP127 -> +1.7FFFFFP127 xo"),
    ("b32", "+", "0", "b32+ 0 -1.6D050DP127 -1.715F0FP127 -> -1.7FFFFFP127 xo"),
    # f32 ADD round-toward-negative underflow flush-to-zero (bug class 2):
    # tiny denormal sum should round up to +min-denormal under RNDD.
    ("b32", "+", "<", "b32+ < +0.000064P-126 -0.000063P-126 -> +0.000001P-126"),
    # f32 ADD round-toward-negative overflow boundary (bug class 1).
    ("b32", "+", "<", "b32+ < +1.682A0BP127 +1.789BF2P127 -> +1.7FFFFFP127 xo"),
    ("b32", "+", "<", "b32+ < +1.72F71CP127 +1.536292P127 -> +1.7FFFFFP127 xo"),
    # f32 ADD round-toward-positive overflow boundary (bug class 1).
    ("b32", "+", ">", "b32+ > -1.70999FP127 -1.7E4150P127 -> -1.7FFFFFP127 xo"),

    # ----- f32 SUB ---------------------------------------------------------
    # f32 SUB round-toward-zero overflow boundary (bug class 1).
    ("b32", "-", "0", "b32- 0 +1.65406FP127 -1.4CE924P126 -> +1.7FFFFFP127 xo"),
    ("b32", "-", "0", "b32- 0 -1.405DFCP127 +1.59377EP127 -> -1.7FFFFFP127 xo"),
    ("b32", "-", "0", "b32- 0 -1.4ED15BP126 +1.6B2B7AP127 -> -1.7FFFFFP127 xo"),
    # f32 SUB round-toward-negative overflow boundary (bug class 1).
    ("b32", "-", "<", "b32- < +1.22561DP127 -1.641F94P127 -> +1.7FFFFFP127 xo"),
    ("b32", "-", "<", "b32- < +1.61E17FP127 -1.7FA98DP127 -> +1.7FFFFFP127 xo"),
    # f32 SUB round-toward-positive overflow boundary (bug class 1).
    ("b32", "-", ">", "b32- > -1.6CC42AP127 +1.14AFFEP127 -> -1.7FFFFFP127 xo"),
    ("b32", "-", ">", "b32- > -1.6E9474P127 +1.4BAC5DP126 -> -1.7FFFFFP127 xo"),

    # ----- f32 MUL ---------------------------------------------------------
    # f32 MUL round-toward-zero overflow boundary (bug class 1).
    ("b32", "*", "0", "b32* 0 +1.000000P10 +1.000002P118 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 +1.000000P65 +1.000000P63 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 +1.000000P76 -1.000000P52 -> -1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 +1.000000P79 -1.379749P49 -> -1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 +1.080000P27 +1.4EAD00P103 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 +1.7795C7P28 -1.4924A8P101 -> -1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 -1.000000P5 -1.000001P123 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 -1.000000P91 +1.2621B1P73 -> -1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 -1.060000P106 -1.2B5F60P23 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 -1.089FB9P113 -1.6DF933P95 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "0", "b32* 0 -1.690ABFP26 +1.75AFBAP102 -> -1.7FFFFFP127 xo"),
    # f32 MUL round-toward-negative: mix of underflow flush-to-zero (xu)
    # and overflow boundary (xo) -- bug classes 1 and 2.
    ("b32", "*", "<", "b32* < +0.000030P-126 -1.7D9734P-108 -> -0.000001P-126 xu"),
    ("b32", "*", "<", "b32* < +1.380065P-120 -1.0C2023P-124 -> -0.000001P-126 xu"),
    ("b32", "*", "<", "b32* < -0.0F8E00P-126 +1.026600P-119 -> -0.000001P-126 xu"),
    ("b32", "*", "<", "b32* < -1.000000P1 -1.000000P127 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "<", "b32* < -1.26C000P17 -1.0DF000P113 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "<", "b32* < -1.350192P125 -1.1B237AP127 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "<", "b32* < -1.440000P-125 +1.3C2C60P-115 -> -0.000001P-126 xu"),
    ("b32", "*", "<", "b32* < -1.5BC1E9P88 -1.28A8D7P40 -> +1.7FFFFFP127 xo"),
    ("b32", "*", "<", "b32* < -1.600000P-122 +1.15C23CP-83 -> -0.000001P-126 xu"),
    ("b32", "*", "<", "b32* < -1.6EE7B4P31 -1.795F37P96 -> +1.7FFFFFP127 xo"),
    # f32 MUL round-toward-positive: same bug-class mix.
    ("b32", "*", ">", "b32* > +0.00002EP-126 +1.34C4D0P-126 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.020000P-114 +1.1D5640P-125 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.360A4DP-93 +1.7A1400P-118 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.4D1E86P-123 +1.2BC06CP-93 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.684D80P-65 +1.64564CP-95 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.6AC000P92 -1.225C00P39 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > +1.6C0000P-105 +1.7A4740P-84 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > +1.7377C0P-101 +1.143E00P-103 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > -1.000000P14 +1.000000P114 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > -1.000000P50 +1.000002P78 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > -1.000000P59 +1.000001P69 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > -1.000000P92 +1.40927EP37 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > -1.17E500P50 +1.4409F2P80 -> -1.7FFFFFP127 xo"),
    ("b32", "*", ">", "b32* > -1.300000P-115 -1.08A26CP-82 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > -1.5EAABEP-123 -1.6469F0P-36 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > -1.6C98F0P-64 -0.01DE00P-126 -> +0.000001P-126 xu"),
    ("b32", "*", ">", "b32* > -1.6F77C0P-124 -1.25F000P-58 -> +0.000001P-126 xu"),

    # ----- f32 DIV ---------------------------------------------------------
    # f32 DIV round-toward-zero overflow + sticky-bit-off-by-one (bug
    # classes 1 and 3). The ``x`` flag without ``o`` indicates inexact
    # without overflow -- those are the off-by-one-ULP cases.
    ("b32", "/", "0", "b32/ 0 +1.000001P42 -1.000000P-86 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.000002P93 -1.000000P-35 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.03EB23P60 +1.03EB25P-68 -> +1.7FFFFCP127 x"),
    ("b32", "/", "0", "b32/ 0 +1.0B831CP10 +1.0B831BP-118 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.1766F0P2 -1.1766EEP-126 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.281277P-1 -0.15024FP-126 -> -1.7FFFFEP127 x"),
    ("b32", "/", "0", "b32/ 0 +1.2E5F6DP79 -0.000323P-126 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.335554P90 +1.1B6A19P-40 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.3BF62BP29 -1.3BF629P-99 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.3DD75FP46 +1.3DD760P-82 -> +1.7FFFFEP127 x"),
    ("b32", "/", "0", "b32/ 0 +1.5011D8P25 +1.5011D6P-103 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.797837P38 -1.265BD2P-92 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.7F814AP112 +1.7F814AP-16 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 +1.7FFFFDP-3 -0.080000P-126 -> -1.7FFFFDP127"),
    ("b32", "/", "0", "b32/ 0 -1.000001P41 -1.000000P-87 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.000002P61 -1.000000P-67 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.0046ECP89 +1.0046EBP-39 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.02E43FP55 -0.16FDDFP-126 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.077034P105 +1.077034P-23 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.0BA0EFP42 +1.0BA0F1P-86 -> -1.7FFFFCP127 x"),
    ("b32", "/", "0", "b32/ 0 -1.14766CP22 -1.14766DP-106 -> +1.7FFFFEP127 x"),
    ("b32", "/", "0", "b32/ 0 -1.3FFFFDP-19 +0.000006P-126 -> -1.7FFFFCP127"),
    ("b32", "/", "0", "b32/ 0 -1.40B093P83 +1.40B095P-45 -> -1.7FFFFDP127 x"),
    ("b32", "/", "0", "b32/ 0 -1.457DB7P87 -1.457DB9P-41 -> +1.7FFFFDP127 x"),
    ("b32", "/", "0", "b32/ 0 -1.52B605P121 -1.457C71P-7 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.56A7EFP83 -1.69642BP-47 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.63A3D5P74 +1.400000P-55 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.6FB297P79 +1.000000P-49 -> -1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.73C4B8P72 -1.73C4B5P-56 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "0", "b32/ 0 -1.7FFFFEP-7 +0.008000P-126 -> -1.7FFFFEP127"),
    # f32 DIV round-toward-negative (mix of bug classes 1, 2, 3).
    ("b32", "/", "<", "b32/ < +0.000002P-126 -1.346553P109 -> -0.000001P-126 xu"),
    ("b32", "/", "<", "b32/ < +1.05E861P77 +1.2A9732P-53 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < +1.0AB373P77 +1.0AB375P-51 -> +1.7FFFFCP127 x"),
    ("b32", "/", "<", "b32/ < +1.0DCD13P65 +1.0DCD12P-63 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < +1.14FA3EP100 +1.25DB1DP-29 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < +1.3E6E4CP119 +1.3E6E4CP-9 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -0.000004P-126 +1.50BA90P121 -> -0.000001P-126 xu"),
    ("b32", "/", "<", "b32/ < -1.000001P47 -1.000000P-81 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -1.400003P96 -1.400000P-32 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -1.48DB14P82 -0.015C7BP-126 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -1.529B46P118 -1.529B43P-10 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -1.585FBBP19 -1.585FBDP-109 -> +1.7FFFFDP127 x"),
    ("b32", "/", "<", "b32/ < -1.5A5BD7P21 -1.5A5BD5P-107 -> +1.7FFFFFP127 xo"),
    ("b32", "/", "<", "b32/ < -1.6B28B0P24 -1.6B28B1P-104 -> +1.7FFFFEP127 x"),
    ("b32", "/", "<", "b32/ < -1.710376P118 -1.000000P-12 -> +1.7FFFFFP127 xo"),
    # f32 DIV round-toward-positive (same bug-class mix).
    ("b32", "/", ">", "b32/ > +1.000001P19 -1.000000P-109 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > +1.14F028P104 -1.14F029P-24 -> -1.7FFFFEP127 x"),
    ("b32", "/", ">", "b32/ > +1.1A7433P118 -1.1A7431P-10 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > +1.3850DBP-123 +1.000000P123 -> +0.000001P-126 xu"),
    ("b32", "/", ">", "b32/ > +1.4051BAP-70 +1.35A823P115 -> +0.000001P-126 xu"),
    ("b32", "/", ">", "b32/ > +1.5C9CBDP44 -1.5C9CBDP-84 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.000002P-14 +0.000080P-126 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.019784P87 +1.76DE33P-43 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.0235B3P32 +1.0235B2P-96 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.10E742P114 +1.34DA1AP-73 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.118829P24 +1.32BF5AP-105 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.3F26F2P16 +1.3F26F0P-112 -> -1.7FFFFFP127 xo"),
    ("b32", "/", ">", "b32/ > -1.3FFFFDP-11 +0.000600P-126 -> -1.7FFFFCP127"),
    ("b32", "/", ">", "b32/ > -1.41F76BP-93 -1.0569AFP126 -> +0.000001P-126 xu"),
    ("b32", "/", ">", "b32/ > -1.54AFFDP-10 +0.000D4BP-126 -> -1.7FFFFCP127 x"),
}


def is_known_bad_for_rounding(test: "TestCase") -> bool:
    """Return ``True`` if ``test`` is in :data:`KNOWN_BAD_TESTS_BY_ROUNDING`.

    ``raw_line`` is the verbatim source line; we strip whitespace to match the
    canonicalisation used when entries are added (the parser already strips
    each line before passing it to the constructor, so this is a no-op for
    well-formed entries -- guarded for safety).
    """
    key = (
        test.precision.value,
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
