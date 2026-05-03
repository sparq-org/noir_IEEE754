"""Helpers for translating IEEE 754 test inputs into the Noir IEEE 754 library.

This package factors out the file-format and bit-pattern logic that previously
lived inline in ``scripts/generate_tests.py`` so that the generator stays
focused on Noir-test emission. The submodule layout is:

- :mod:`constants` -- Python mirrors of the ``FLOAT*_*`` ``pub global``s in
  ``ieee754::types``, plus ``f32_pack`` / ``f64_pack`` helpers and
  ``render_special_or_hex`` for emitting Noir source.
- :mod:`fptest` -- IBM FPgen ``.fptest`` parser plus the ``fp_value_to_bits``
  helper.
- :mod:`reference` -- MPFR-backed (``gmpy2``) reference oracle for the
  expected result of ``a op b`` under any IEEE 754 rounding mode.
  ``compute_expected_bits`` is the public entry point.
"""

from . import constants
from .fptest import (
    FPValue,
    KNOWN_BAD_TESTS,
    KNOWN_BAD_TESTS_BY_ROUNDING,
    Operation,
    Precision,
    RoundingMode,
    TestCase,
    fp_value_to_bits,
    fp_value_to_bits32,
    fp_value_to_bits64,
    is_known_bad_for_rounding,
    parse_fp_value,
    parse_fptest_file,
    parse_test_line,
)

__all__ = [
    "FPValue",
    "KNOWN_BAD_TESTS",
    "KNOWN_BAD_TESTS_BY_ROUNDING",
    "Operation",
    "Precision",
    "RoundingMode",
    "TestCase",
    "constants",
    "fp_value_to_bits",
    "fp_value_to_bits32",
    "fp_value_to_bits64",
    "is_known_bad_for_rounding",
    "parse_fp_value",
    "parse_fptest_file",
    "parse_test_line",
]
