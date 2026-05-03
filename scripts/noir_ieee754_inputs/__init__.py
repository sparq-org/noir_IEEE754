"""Helpers for translating IEEE 754 test inputs into the Noir IEEE 754 library.

This package factors out the file-format and bit-pattern logic that previously
lived inline in ``scripts/generate_tests.py`` so that the generator stays
focused on Noir-test emission. The submodule layout is:

- :mod:`fptest` -- IBM FPgen ``.fptest`` parser plus the ``fp_value_to_bits``
  helper.
"""

from .fptest import (
    FPValue,
    KNOWN_BAD_TESTS,
    Operation,
    Precision,
    RoundingMode,
    TestCase,
    fp_value_to_bits,
    fp_value_to_bits32,
    fp_value_to_bits64,
    parse_fp_value,
    parse_fptest_file,
    parse_test_line,
)

__all__ = [
    "FPValue",
    "KNOWN_BAD_TESTS",
    "Operation",
    "Precision",
    "RoundingMode",
    "TestCase",
    "fp_value_to_bits",
    "fp_value_to_bits32",
    "fp_value_to_bits64",
    "parse_fp_value",
    "parse_fptest_file",
    "parse_test_line",
]
