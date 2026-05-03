#!/usr/bin/env python3
"""
IEEE 754 Test Suite to Noir Test Generator

This script parses .fptest files from the IBM FPgen test suite 
(https://github.com/sergev/ieee754-test-suite) and generates Noir test code.

Test files are automatically downloaded and cached locally.

Test file format:
  <precision><op> <rounding> [exception-flags] <operand1> [operand2] [operand3] -> <result> [result-flags]

Where:
  - precision: b32 (binary32/float), b64 (binary64/double), etc.
  - op: + (add), - (subtract), * (multiply), / (divide), *+ (fma), etc.
  - rounding: =0 (nearest even), =^ (nearest away), > (toward +inf), < (toward -inf), 0 (toward zero)
  - operand format: <sign><significand>P<exponent> or special values (+Inf, -Inf, +Zero, -Zero, Q, S)

Usage:
  python generate_tests.py [--output <output_file.nr>]
  python generate_tests.py --files Add-Shift.fptest Basic-Types-Inputs.fptest
  python generate_tests.py --all
"""

import argparse
import math
import os
import random
import re
import struct
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional

# Make the colocated input-prep package importable when this script is run as
# a top-level module from any working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from noir_ieee754_inputs.fptest import (  # noqa: E402
    FPValue,
    Operation,
    Precision,
    RoundingMode,
    TestCase,
    fp_value_to_bits32,
    fp_value_to_bits64,
    parse_fptest_file,
)


# IEEE 754 conversion utilities using Python's struct module
def float32_from_bits(bits: int) -> float:
    """Convert 32-bit integer to float32."""
    return struct.unpack('f', struct.pack('I', bits & 0xFFFFFFFF))[0]

def float32_to_bits(f: float) -> int:
    """Convert float32 to 32-bit integer."""
    return struct.unpack('I', struct.pack('f', f))[0]

def float64_from_bits(bits: int) -> float:
    """Convert 64-bit integer to float64."""
    return struct.unpack('d', struct.pack('Q', bits & 0xFFFFFFFFFFFFFFFF))[0]

def float64_to_bits(f: float) -> int:
    """Convert float64 to 64-bit integer."""
    return struct.unpack('Q', struct.pack('d', f))[0]


# GitHub raw URL base for the IEEE 754 test suite
TEST_SUITE_BASE_URL = "https://raw.githubusercontent.com/sergev/ieee754-test-suite/master"

# Available test files in the repository (binary floating-point only, not decimal)
AVAILABLE_TEST_FILES = [
    "Add-Cancellation-And-Subnorm-Result.fptest",
    "Add-Cancellation.fptest",
    "Add-Shift-And-Special-Significands.fptest",
    "Add-Shift.fptest",
    "Basic-Types-Inputs.fptest",
    "Basic-Types-Intermediate.fptest",
    "Compare-Different-Input-Field-Relations.fptest",
    "Corner-Rounding.fptest",
    "Divide-Divide-By-Zero-Exception.fptest",
    "Divide-Trailing-Zeros.fptest",
    "Hamming-Distance.fptest",
    "Input-Special-Significand.fptest",
    "Overflow.fptest",
    "Rounding.fptest",
    "Sticky-Bit-Calculation.fptest",
    "Underflow.fptest",
    "Vicinity-Of-Rounding-Boundaries.fptest",
]

# Default cache directory (relative to script location)
DEFAULT_CACHE_DIR = ".ieee754_test_cache"


def generate_synthetic_f64_tests() -> list['TestCase']:
    """Generate synthetic float64 test cases for corner cases.

    Delegates to focused per-scenario generators. Uses a fixed seed (42)
    so runs are deterministic; the seed is set once at the top so the
    generators below share a single PRNG stream.
    """
    random.seed(42)

    generators = [
        _gen_corner_mul_denorm,
        _gen_corner_div_denorm,
        _gen_underflow_mul,
        _gen_underflow_div,
        _gen_hamming_add_sub,
        _gen_sticky_mul,
        _gen_div_pow2,
        _gen_round_boundary,
        _gen_overflow_mul,
        _gen_denorm_normalize,
        _gen_denorm_to_normal,
        _gen_tiny_mul,
    ]

    tests: list['TestCase'] = []
    for generator in generators:
        tests.extend(generator(len(tests)))

    print(f"Generated {len(tests)} synthetic f64 test cases")
    return tests


# Special bit patterns for IEEE 754 -- used by ``_compute_expected_bits`` to
# emit canonical NaN / infinity / zero bit patterns in the generated Noir
# tests. Phase 2b replaces these dicts with named library constants.
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


# Float64 layout constants (used by synthetic-f64 generators below).
_F64_BIAS = 1023
_F64_SIGN_BIT = 1 << 63
_F64_MANTISSA_MASK = (1 << 52) - 1


def bits_to_fpvalue(bits: int) -> FPValue:
    """Decode IEEE 754 binary64 bits into an FPValue for synthetic-test scaffolding.

    Lossy on NaN: any NaN maps to ``is_nan=True`` with no payload and no
    signalling/quiet distinction. Sufficient for the synthetic-f64 generators,
    which never construct payloaded NaNs, so this is not a true inverse of
    ``fp_value_to_bits``.
    """
    sign = (bits >> 63) & 1
    exp = (bits >> 52) & 0x7FF
    mant = bits & _F64_MANTISSA_MASK

    if exp == 0x7FF:
        if mant == 0:
            return FPValue(sign=sign, significand="", exponent=0, is_inf=True)
        return FPValue(sign=sign, significand="", exponent=0, is_nan=True)
    if exp == 0:
        if mant == 0:
            return FPValue(sign=sign, significand="", exponent=0, is_zero=True)
        # Denormal: leading hex digit is 0 to indicate no implicit leading 1.
        return FPValue(sign=sign, significand=f"0{mant:013X}", exponent=-1022)
    # Normal: leading hex digit is 1 for the implicit bit.
    return FPValue(sign=sign, significand=f"1{mant:013X}", exponent=exp - _F64_BIAS)


def _random_sign_bit() -> int:
    """Return the f64 sign-bit mask with 50/50 probability, else 0."""
    return _F64_SIGN_BIT if random.random() < 0.5 else 0


def _make_synthetic_f64_test(op: 'Operation', a_bits: int, b_bits: int, line_num: int, desc: str) -> 'TestCase':
    """Build a synthetic float64 TestCase for ``a op b`` using IEEE 754 arithmetic on the host."""
    a = float64_from_bits(a_bits)
    b = float64_from_bits(b_bits)

    result_float = 0.0
    if op == Operation.ADD:
        result_float = a + b
    elif op == Operation.SUBTRACT:
        result_float = a - b
    elif op == Operation.MULTIPLY:
        result_float = a * b
    elif op == Operation.DIVIDE:
        if b != 0:
            result_float = a / b

    result_bits = float64_to_bits(result_float)

    return TestCase(
        precision=Precision.BINARY64,
        operation=op,
        rounding=RoundingMode.NEAREST_EVEN,
        operand1=bits_to_fpvalue(a_bits),
        operand2=bits_to_fpvalue(b_bits),
        operand3=None,
        result=bits_to_fpvalue(result_bits),
        exception_flags="",
        line_number=line_num,
        raw_line=f"synthetic_f64 {desc}",
    )


def _gen_corner_mul_denorm(start_line: int) -> list['TestCase']:
    """Tiny denormal x denormal multiplications (corner-rounding to zero or smallest denormal)."""
    tests = []
    for i in range(20):
        a_bits = random.randint(1, 0xFFFF) | _random_sign_bit()
        b_bits = random.randint(1, 0xFFFF) | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"corner_mul_denorm_{i}"
        ))
    return tests


def _gen_corner_div_denorm(start_line: int) -> list['TestCase']:
    """Denormal dividend / large normal divisor (drives result towards zero)."""
    tests = []
    for i in range(20):
        a_bits = random.randint(1, 0xFFFFFFFFFFF) | _random_sign_bit()
        b_exp = random.randint(900, 1023)
        b_mant = random.randint(0, _F64_MANTISSA_MASK)
        b_bits = (b_exp << 52) | b_mant | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.DIVIDE, a_bits, b_bits, start_line + i, f"corner_div_denorm_{i}"
        ))
    return tests


def _gen_underflow_mul(start_line: int) -> list['TestCase']:
    """Small normal x small normal that underflows to a denormal product."""
    tests = []
    for i in range(30):
        a_exp = random.randint(1, 50)
        b_exp = random.randint(1, 50)
        a_mant = random.randint(0, _F64_MANTISSA_MASK)
        b_mant = random.randint(0, _F64_MANTISSA_MASK)
        a_bits = (a_exp << 52) | a_mant | _random_sign_bit()
        b_bits = (b_exp << 52) | b_mant | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"underflow_mul_{i}"
        ))
    return tests


def _gen_underflow_div(start_line: int) -> list['TestCase']:
    """Small normal / large normal that underflows the quotient to a denormal."""
    tests = []
    for i in range(20):
        a_exp = random.randint(1, 100)
        b_exp = random.randint(1500, 2046)
        a_mant = random.randint(0, _F64_MANTISSA_MASK)
        b_mant = random.randint(0, _F64_MANTISSA_MASK)
        a_bits = (a_exp << 52) | a_mant | _random_sign_bit()
        b_bits = (b_exp << 52) | b_mant | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.DIVIDE, a_bits, b_bits, start_line + i, f"underflow_div_{i}"
        ))
    return tests


def _gen_hamming_add_sub(start_line: int) -> list['TestCase']:
    """Adjacent values differing by 1 ULP: addition and subtraction (Hamming-distance edge cases).

    Both operands of each test share a single sign bit so the 1-ULP adjacency
    invariant (``base + diff == ulp`` and ``ulp - diff == base``) holds for
    negative operands too: with a shared sign s, ``s·base + s·diff == s·ulp``.
    Independent signs would break the relationship for the mixed-sign cases.
    """
    tests = []
    line_num = start_line
    for i in range(30):
        exp = random.randint(1, 2046)
        mant = random.randint(1, (1 << 52) - 2)
        base_bits = (exp << 52) | mant
        ulp_bits = base_bits + 1

        base = float64_from_bits(base_bits)
        ulp = float64_from_bits(ulp_bits)
        diff = ulp - base

        sign_add = _random_sign_bit()
        a_bits = float64_to_bits(base) | sign_add
        b_bits = float64_to_bits(diff) | sign_add
        tests.append(_make_synthetic_f64_test(
            Operation.ADD, a_bits, b_bits, line_num, f"hamming_add_{i}"
        ))
        line_num += 1

        sign_sub = _random_sign_bit()
        a_bits_sub = float64_to_bits(ulp) | sign_sub
        b_bits_sub = float64_to_bits(diff) | sign_sub
        tests.append(_make_synthetic_f64_test(
            Operation.SUBTRACT, a_bits_sub, b_bits_sub, line_num, f"hamming_sub_{i}"
        ))
        line_num += 1
    return tests


def _gen_sticky_mul(start_line: int) -> list['TestCase']:
    """Multiplications whose intermediate product has many low bits set (sticky-bit rounding)."""
    tests = []
    for i in range(30):
        exp_a = random.randint(500, 1500)
        exp_b = random.randint(500, 1500)
        mant_a = random.randint((1 << 51), (1 << 52) - 1)
        mant_b = random.randint((1 << 51), (1 << 52) - 1)
        a_bits = (exp_a << 52) | mant_a | _random_sign_bit()
        b_bits = (exp_b << 52) | mant_b | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"sticky_mul_{i}"
        ))
    return tests


def _gen_div_pow2(start_line: int) -> list['TestCase']:
    """Division of pure powers of two (exact result, no rounding required)."""
    tests = []
    for i in range(20):
        exp_a = random.randint(100, 1900)
        exp_b = random.randint(100, 1900)
        a_bits = (exp_a << 52) | _random_sign_bit()
        b_bits = (exp_b << 52) | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.DIVIDE, a_bits, b_bits, start_line + i, f"div_pow2_{i}"
        ))
    return tests


def _gen_round_boundary(start_line: int) -> list['TestCase']:
    """Operands whose mantissa sits exactly on a guard-bit rounding boundary."""
    tests = []
    for i in range(30):
        exp = random.randint(100, 1900)
        mant = random.randint(0, (1 << 48) - 1) << 4
        mant |= 0x8  # Set the guard bit at the midpoint.
        a_bits = (exp << 52) | mant | _random_sign_bit()
        b_bits = (1023 << 52) | _random_sign_bit()  # +-1.0
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"round_boundary_{i}"
        ))
    return tests


def _gen_overflow_mul(start_line: int) -> list['TestCase']:
    """Multiplications whose magnitude lands near the f64 overflow boundary."""
    tests = []
    for i in range(20):
        exp_a = random.randint(1800, 2046)
        exp_b = random.randint(1, 300)
        mant_a = random.randint(0, _F64_MANTISSA_MASK)
        mant_b = random.randint(0, _F64_MANTISSA_MASK)
        a_bits = (exp_a << 52) | mant_a | _random_sign_bit()
        b_bits = (exp_b << 52) | mant_b | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"overflow_mul_{i}"
        ))
    return tests


def _gen_denorm_normalize(start_line: int) -> list['TestCase']:
    """Denormal inputs with varying leading-bit positions, exercising the normalisation path."""
    tests = []
    line_num = start_line
    for i in range(30):
        leading_pos = random.randint(0, 51)
        mant = (1 << leading_pos) | random.randint(0, (1 << leading_pos) - 1)
        a_bits = mant | _random_sign_bit()

        b_exp = random.randint(1, 100)
        b_mant = random.randint(0, _F64_MANTISSA_MASK)
        b_bits = (b_exp << 52) | b_mant | _random_sign_bit()

        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, line_num, f"denorm_normalize_mul_{i}"
        ))
        line_num += 1
        tests.append(_make_synthetic_f64_test(
            Operation.DIVIDE, a_bits, b_bits, line_num, f"denorm_normalize_div_{i}"
        ))
        line_num += 1
    return tests


def _gen_denorm_to_normal(start_line: int) -> list['TestCase']:
    """Largest denormal multiplied by values straddling the normal threshold."""
    tests = []
    for i in range(10):
        a_bits = 0x000FFFFFFFFFFFFF | _random_sign_bit()
        b_exp = random.randint(1020, 1026)
        b_mant = random.randint(0, _F64_MANTISSA_MASK)
        b_bits = (b_exp << 52) | b_mant | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"denorm_to_normal_{i}"
        ))
    return tests


def _gen_tiny_mul(start_line: int) -> list['TestCase']:
    """Smallest denormal multiplied by values near 1.0 (must not flush to zero incorrectly)."""
    tests = []
    for i in range(10):
        a_bits = 0x0000000000000001 | _random_sign_bit()
        b_exp = random.randint(1020, 1026)
        b_bits = (b_exp << 52) | _random_sign_bit()
        tests.append(_make_synthetic_f64_test(
            Operation.MULTIPLY, a_bits, b_bits, start_line + i, f"tiny_mul_{i}"
        ))
    return tests


def generate_noir_test_name(test: TestCase, index: int, force_f64: bool = False) -> str:
    """Generate a Noir test function name for a test case.

    When force_f64 is True the name reflects the effective f64 precision
    even if the source TestCase is f32.
    """
    is_f32 = test.precision == Precision.BINARY32 and not force_f64
    precision = "f32" if is_f32 else "f64"
    op_names = {
        Operation.ADD: "add",
        Operation.SUBTRACT: "sub",
        Operation.MULTIPLY: "mul",
        Operation.DIVIDE: "div",
        Operation.FMA: "fma",
        Operation.SQRT: "sqrt",
        Operation.REM: "rem",
    }
    op = op_names.get(test.operation, "op")
    return f"test_{precision}_{op}_{index}"


def _compute_expected_bits(test: 'TestCase', f1: float, f2: float, is_float32: bool) -> tuple[int, bool]:
    """Compute the expected result bits for this test case using Python's hardware float.

    Returns (expected_bits, is_nan).
    """
    if test.result.is_nan:
        expected = _FLOAT32_SPECIAL['qnan'] if is_float32 else _FLOAT64_SPECIAL['qnan']
        return expected, True

    if test.operation == Operation.ADD:
        result_float = f1 + f2
    elif test.operation == Operation.SUBTRACT:
        result_float = f1 - f2
    elif test.operation == Operation.MULTIPLY:
        result_float = f1 * f2
    elif test.operation == Operation.DIVIDE:
        if f2 == 0:
            # Division by zero — fall back to the test file's expected bits since
            # Python raises ZeroDivisionError instead of producing IEEE Inf/NaN.
            to_bits_result = fp_value_to_bits32 if is_float32 else fp_value_to_bits64
            return to_bits_result(test.result), False
        result_float = f1 / f2

    if math.isnan(result_float):
        expected = _FLOAT32_SPECIAL['qnan'] if is_float32 else _FLOAT64_SPECIAL['qnan']
        return expected, True
    if math.isinf(result_float):
        if result_float > 0:
            expected = _FLOAT32_SPECIAL['pos_inf'] if is_float32 else _FLOAT64_SPECIAL['pos_inf']
        else:
            expected = _FLOAT32_SPECIAL['neg_inf'] if is_float32 else _FLOAT64_SPECIAL['neg_inf']
        return expected, False
    if is_float32:
        return float32_to_bits(result_float), False
    return float64_to_bits(result_float), False


def _operand_bits_and_floats(test: 'TestCase', force_f64: bool) -> tuple[int, int, float, float]:
    """Convert test operands to in-circuit bit representations and Python floats.

    Handles the f32->f64 coercion case (force_f64 with float32 inputs).
    Returns (bits_a, bits_b, float_a, float_b).
    """
    original_is_f32 = test.precision == Precision.BINARY32
    is_float32 = original_is_f32 and not force_f64

    if force_f64 and original_is_f32:
        # Round through float32 first so the f64 circuit sees the same value
        # the source f32 test case carried.
        bits1_f32 = fp_value_to_bits32(test.operand1)
        bits2_f32 = fp_value_to_bits32(test.operand2)
        f1 = float32_from_bits(bits1_f32)
        f2 = float32_from_bits(bits2_f32)
        bits1 = float64_to_bits(f1)
        bits2 = float64_to_bits(f2)
        return bits1, bits2, f1, f2

    to_bits = fp_value_to_bits32 if is_float32 else fp_value_to_bits64
    from_bits = float32_from_bits if is_float32 else float64_from_bits
    bits1 = to_bits(test.operand1)
    bits2 = to_bits(test.operand2)
    return bits1, bits2, from_bits(bits1), from_bits(bits2)


def generate_noir_test(test: TestCase, index: int, add_debug: bool = False, force_f64: bool = False) -> Optional[str]:
    """Generate Noir test code for a single test case.
    
    Args:
        test: The test case to generate code for
        index: Test index for naming
        add_debug: Whether to add println statements
        force_f64: If True, convert f32 test cases to f64 (using f64 arithmetic)
    """
    
    # Support add, subtract, multiply, and divide
    if test.operation not in (Operation.ADD, Operation.SUBTRACT, Operation.MULTIPLY, Operation.DIVIDE):
        return None
    
    # Only support round-to-nearest-even for now
    if test.rounding != RoundingMode.NEAREST_EVEN:
        return None
    
    # Need two operands for binary operations
    if test.operand2 is None:
        return None
    
    # Determine if we're generating f32 or f64 test
    # If force_f64 is True and the test is f32, convert to f64
    original_is_f32 = test.precision == Precision.BINARY32
    is_float32 = original_is_f32 and not force_f64
    
    prec = "32" if is_float32 else "64"
    sign_bit = 0x80000000 if is_float32 else 0x8000000000000000
    hex_width = 8 if is_float32 else 16
    
    bits1, bits2, f1, f2 = _operand_bits_and_floats(test, force_f64)
    
    # Skip tests where an operand underflows to zero when it wasn't supposed to be zero
    # The test file may expect a finite result, but IEEE float32 will give infinity/NaN
    if not test.operand1.is_zero and f1 == 0:
        return None  # operand1 underflowed to zero
    if not test.operand2.is_zero and f2 == 0:
        return None  # operand2 underflowed to zero (division by zero)
    
    expected, result_is_nan = _compute_expected_bits(test, f1, f2, is_float32)
    
    # Determine the Noir function to call
    op_func_map = {
        Operation.ADD: "add",
        Operation.SUBTRACT: "sub",
        Operation.MULTIPLY: "mul",
        Operation.DIVIDE: "div",
    }
    op_func = op_func_map[test.operation]
    
    test_name = generate_noir_test_name(test, index, force_f64=force_f64 and original_is_f32)
    bits1_str = f"0x{bits1:0{hex_width}X}"
    bits2_str = f"0x{bits2:0{hex_width}X}"
    expected_str = f"0x{expected:0{hex_width}X}"
    
    # Generate test body
    if result_is_nan:
        assertion = f"assert(float{prec}_is_nan(result));"
    elif add_debug:
        assertion = f"""let result_bits = float{prec}_to_bits(result);
    println(f"a: {{{bits1_str}}} b: {{{bits2_str}}} result: {{result_bits}} expected: {expected_str}");
    assert(result_bits == {expected_str});"""
    else:
        assertion = f"""let result_bits = float{prec}_to_bits(result);
    assert(result_bits == {expected_str});"""
    
    return f"""#[test]
fn {test_name}() {{
    // {test.raw_line}
    let a = float{prec}_from_bits({bits1_str});
    let b = float{prec}_from_bits({bits2_str});
    let result = {op_func}_float{prec}(a, b);
    {assertion}
}}
"""


def analyze_test_code(test_code: list[str]) -> dict[str, bool]:
    """Analyze test code to determine which imports are needed.
    
    Returns a dict of import flags.
    """
    code_str = "\n".join(test_code)
    return {
        # Float32 operations
        'add_float32': "add_float32" in code_str,
        'sub_float32': "sub_float32" in code_str,
        'mul_float32': "mul_float32" in code_str,
        'div_float32': "div_float32" in code_str,
        'float32_from_bits': "float32_from_bits" in code_str,
        'float32_to_bits': "float32_to_bits" in code_str,
        'float32_is_nan': "float32_is_nan" in code_str,
        # Float64 operations
        'add_float64': "add_float64" in code_str,
        'sub_float64': "sub_float64" in code_str,
        'mul_float64': "mul_float64" in code_str,
        'div_float64': "div_float64" in code_str,
        'float64_from_bits': "float64_from_bits" in code_str,
        'float64_to_bits': "float64_to_bits" in code_str,
        'float64_is_nan': "float64_is_nan" in code_str,
    }


def _render_noir_header(source_info: str, analysis: dict[str, bool], use_path: str) -> str:
    imports = sorted(name for name, needed in analysis.items() if needed)
    imports_str = ", ".join(imports)

    return f"""// Auto-generated IEEE 754 test cases
// Generated from: {source_info}
// Test suite source: https://github.com/sergev/ieee754-test-suite

use {use_path}::{{{imports_str}}};

"""


def generate_noir_header_from_analysis_for_package(source_info: str, analysis: dict[str, bool]) -> str:
    """Generate Noir test file header with only required imports for separate packages."""
    return _render_noir_header(source_info, analysis, "ieee754::float")


def generate_noir_header_from_analysis(source_info: str, analysis: dict[str, bool]) -> str:
    """Generate Noir test file header with only required imports."""
    return _render_noir_header(source_info, analysis, "crate::float")


def generate_noir_file(tests: list[TestCase], output_path: str, source_files: list[str], add_debug: bool = False, force_f64: bool = False):
    """Generate a complete Noir test file from test cases."""
    test_code = [
        code for i, test in enumerate(tests)
        if (code := generate_noir_test(test, i, add_debug, force_f64))
    ]
    
    analysis = analyze_test_code(test_code)
    header = generate_noir_header_from_analysis(', '.join(source_files), analysis)
    
    with open(output_path, 'w') as f:
        f.write(header)
        f.write('\n'.join(test_code))
    
    print(f"Generated {len(test_code)} tests to {output_path}")
    return len(test_code)


def _source_to_module_name(source_file: str) -> str:
    """Convert a source filename to a valid Noir module name."""
    base_name = os.path.splitext(source_file)[0]
    return "test_" + re.sub(r'[^a-zA-Z0-9]', '_', base_name).lower()


def generate_ci_matrix(
    tests_by_file: dict[str, list[TestCase]],
    output_path: str,
    chunk_size: int = 25,
    max_tests_per_package: int = 1250,
    force_f64: bool = False,
    generate_both: bool = False,
) -> list[dict]:
    """Generate a CI matrix JSON file for GitHub Actions.

    Lists all packages that will be generated. Large test files are automatically
    split into multiple packages by generate_noir_packages.

    Args:
        max_tests_per_package: Maximum tests per package (50 chunks * 25 tests = 1250)
    """
    import json
    
    groups = []
    
    # Always add unit tests group first
    groups.append({
        "name": "unit-tests",
        "module": "_unit_",
        "package": "ieee754_unit_tests"
    })
    
    for source_file, tests in sorted(tests_by_file.items()):
        module_name = _source_to_module_name(source_file)
        
        # Count how many test functions will be generated
        if generate_both:
            f32_count = sum(1 for i, test in enumerate(tests) if generate_noir_test(test, i, force_f64=False) is not None)
            f64_count = sum(1 for i, test in enumerate(tests) if generate_noir_test(test, i, force_f64=True) is not None)
            test_count = f32_count + f64_count
        else:
            test_count = sum(1 for i, test in enumerate(tests) if generate_noir_test(test, i, force_f64=force_f64) is not None)
        
        if test_count == 0:
            continue
        
        # Calculate how many packages this test file will generate
        num_packages = (test_count + max_tests_per_package - 1) // max_tests_per_package
        
        if num_packages == 1:
            # Single package
            package_name = f"ieee754_{module_name}"
            groups.append({
                "name": module_name.replace("test_", ""),
                "module": module_name,
                "package": package_name
            })
        else:
            # Multiple packages - add each one
            for pkg_idx in range(num_packages):
                package_name = f"ieee754_{module_name}_part{pkg_idx}"
                groups.append({
                    "name": f"{module_name.replace('test_', '')}_part{pkg_idx}",
                    "module": module_name,
                    "package": package_name
                })
    
    # Write JSON file
    with open(output_path, 'w') as f:
        json.dump({"groups": groups}, f, indent=2)
    
    print(f"Generated CI matrix with {len(groups)} groups to {output_path}")
    return groups


def generate_noir_packages(
    tests_by_file: dict[str, list[TestCase]], 
    output_dir: str, 
    add_debug: bool = False,
    chunk_size: int = 25,
    max_tests_per_package: int = 1250,
    force_f64: bool = False,
    generate_both: bool = False
) -> dict[str, int]:
    """Generate separate Noir packages for each source file.
    
    Each test module becomes one or more Noir packages with:
    - Nargo.toml with dependency on ieee754
    - src/main.nr importing chunks as modules
    - src/chunk_XXXX.nr files with test functions
    
    Large test files are automatically split into multiple packages.
    
    Args:
        tests_by_file: Dict mapping source filenames to test cases
        output_dir: Output directory for generated packages (e.g., 'test_packages')
        add_debug: Add println statements for debugging
        chunk_size: Number of tests per chunk file
        max_tests_per_package: Maximum tests per package before splitting (default 1250 = 50 chunks)
        force_f64: If True, convert f32 tests to f64 only
        generate_both: If True, generate both f32 and f64 tests (overrides force_f64)
    """
    results = {}
    package_names = []
    
    for source_file, tests in tests_by_file.items():
        module_name = _source_to_module_name(source_file)
        
        # Generate all test code
        if generate_both:
            # Generate both f32 tests (index 0..n-1) and f64 tests (index n..2n-1)
            # For native f64 tests (like synthetic tests), only generate once (in the f64 pass)
            f32_tests = [
                code for i, test in enumerate(tests)
                if test.precision == Precision.BINARY32 and (code := generate_noir_test(test, i, add_debug, force_f64=False))
            ]
            # For native f64 tests, don't set force_f64 (they're already f64)
            # For f32 tests, convert to f64
            f64_tests = []
            for i, test in enumerate(tests):
                if test.precision == Precision.BINARY64:
                    # Native f64 test - generate directly
                    code = generate_noir_test(test, len(tests) + i, add_debug, force_f64=False)
                else:
                    # f32 test - convert to f64
                    code = generate_noir_test(test, len(tests) + i, add_debug, force_f64=True)
                if code:
                    f64_tests.append(code)
            all_test_code = f32_tests + f64_tests
        else:
            all_test_code = [
                code for i, test in enumerate(tests)
                if (code := generate_noir_test(test, i, add_debug, force_f64))
            ]
        
        if not all_test_code:
            continue
        
        # Split into multiple packages if too large
        num_packages = (len(all_test_code) + max_tests_per_package - 1) // max_tests_per_package
        
        for pkg_idx in range(num_packages):
            # Get tests for this package
            start_idx = pkg_idx * max_tests_per_package
            end_idx = min(start_idx + max_tests_per_package, len(all_test_code))
            package_test_code = all_test_code[start_idx:end_idx]
            
            # Package name includes part suffix if split
            if num_packages == 1:
                package_name = f"ieee754_{module_name}"
            else:
                package_name = f"ieee754_{module_name}_part{pkg_idx}"
            
            # Create package folder structure
            package_dir = os.path.join(output_dir, package_name)
            src_dir = os.path.join(package_dir, "src")
            os.makedirs(src_dir, exist_ok=True)
            
            # Write Nargo.toml
            nargo_toml = f'''[package]
name = "{package_name}"
type = "bin"
authors = [""]

[dependencies]
ieee754 = {{ path = "../../ieee754" }}
'''
            with open(os.path.join(package_dir, "Nargo.toml"), 'w') as f:
                f.write(nargo_toml)
            
            # Generate chunks for this package
            chunks = [package_test_code[i:i + chunk_size] for i in range(0, len(package_test_code), chunk_size)]
            chunk_names = []
            
            for chunk_idx, chunk in enumerate(chunks):
                chunk_name = f"chunk_{chunk_idx:04d}"
                chunk_names.append(chunk_name)
                
                # Analyze this chunk to determine required imports
                analysis = analyze_test_code(chunk)
                header = generate_noir_header_from_analysis_for_package(f"{source_file} (chunk {chunk_idx})", analysis)
                
                with open(os.path.join(src_dir, f"{chunk_name}.nr"), 'w') as f:
                    f.write(header)
                    f.write('\n'.join(chunk))
            
            # Generate src/main.nr for this package (bin package needs main)
            part_info = f" (part {pkg_idx + 1}/{num_packages})" if num_packages > 1 else ""
            with open(os.path.join(src_dir, "main.nr"), 'w') as f:
                f.write(f"// Auto-generated IEEE 754 test package for {source_file}{part_info}\n")
                f.write(f"// Contains {len(package_test_code)} tests in {len(chunks)} chunks of {chunk_size}\n\n")
                f.writelines(f"mod {name};\n" for name in chunk_names)
                f.write("\nfn main() {}\n")
            
            print(f"Generated package {package_name} with {len(package_test_code)} tests in {len(chunks)} chunks")
            package_names.append(package_name)
        
        results[source_file] = len(all_test_code)
    
    print(f"\nGenerated {len(package_names)} test packages in {output_dir}/")
    return results


def get_cache_dir() -> Path:
    """Get the cache directory path, creating it if needed."""
    # Cache directory is relative to the project root (parent of scripts/)
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    cache_dir = project_root / DEFAULT_CACHE_DIR
    cache_dir.mkdir(exist_ok=True)
    return cache_dir


def download_test_file(filename: str, cache_dir: Path) -> Path:
    """Download a test file from the IEEE 754 test suite repository."""
    cache_path = cache_dir / filename
    
    if cache_path.exists():
        print(f"Using cached: {filename}")
        return cache_path
    
    url = f"{TEST_SUITE_BASE_URL}/{filename}"
    print(f"Downloading: {filename}...")
    
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            content = response.read()
            cache_path.write_bytes(content)
            print(f"  Downloaded {len(content):,} bytes")
            return cache_path
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Failed to download {filename}: HTTP {e.code}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Failed to download {filename}: {e.reason}") from e


def list_available_files():
    """Print list of available test files."""
    print("Available IEEE 754 test files:")
    for f in AVAILABLE_TEST_FILES:
        print(f"  - {f}")


def main():
    parser = argparse.ArgumentParser(
        description='Generate Noir tests from IEEE 754 test suite files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                              # Download and use Add-Shift.fptest (default)
  %(prog)s --files Add-Shift.fptest     # Use specific file(s)
  %(prog)s --all                        # Use all available test files
  %(prog)s --all --packages             # Generate separate test packages (recommended)
  %(prog)s --all --packages --chunk-size 50  # Use 50 tests per chunk file
  %(prog)s --list                       # List available test files
  %(prog)s --local test.fptest          # Use a local file instead of downloading
        """
    )
    parser.add_argument(
        '--files',
        nargs='+',
        metavar='FILE',
        help='Test files to download and use (from IEEE 754 test suite)'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Download and use all available test files'
    )
    parser.add_argument(
        '--local',
        nargs='+',
        metavar='PATH',
        help='Use local .fptest file(s) instead of downloading'
    )
    parser.add_argument(
        '--list',
        action='store_true',
        help='List available test files and exit'
    )
    parser.add_argument(
        '--output', '-o',
        default='ieee754_tests.nr',
        help='Output Noir file (default: ieee754_tests.nr)'
    )
    parser.add_argument(
        '--output-dir',
        default=None,
        help='Output directory for generated test packages (use with --packages)'
    )
    parser.add_argument(
        '--packages',
        action='store_true',
        help='Generate separate Noir packages for each test module (recommended for CI)'
    )
    parser.add_argument(
        '--chunk-size',
        type=int,
        default=25,
        help='Number of tests per chunk file within a package (default: 25)'
    )
    parser.add_argument(
        '--max-tests-per-package',
        type=int,
        default=1250,
        help='Maximum tests per package before splitting into multiple packages (default: 1250)'
    )
    parser.add_argument(
        '--operation',
        choices=['add', 'sub', 'mul', 'div', 'all'],
        default='all',
        help='Filter by operation type (default: all)')
    parser.add_argument(
        '--precision',
        choices=['f32', 'f64', 'all'],
        default='all',
        help='Filter by precision (default: all)'
    )
    parser.add_argument(
        '--generate-f64',
        action='store_true',
        help='Generate f64 tests from f32 test cases (converts operands to f64 and computes results)'
    )
    parser.add_argument(
        '--synthetic-f64',
        action='store_true',
        help='Generate synthetic f64 corner case tests (denormals, rounding boundaries, etc.)'
    )
    parser.add_argument(
        '--max-tests',
        type=int,
        default=None,
        help='Maximum number of tests to generate (per source file)'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Add println statements for debugging'
    )
    parser.add_argument(
        '--clear-cache',
        action='store_true',
        help='Clear the download cache before running'
    )
    parser.add_argument(
        '--ci-matrix',
        metavar='PATH',
        help='Generate CI matrix JSON file for GitHub Actions (use with --packages)'
    )
    
    args = parser.parse_args()
    
    # Handle --list
    if args.list:
        list_available_files()
        return
    
    # Get cache directory
    cache_dir = get_cache_dir()
    
    # Handle --clear-cache
    if args.clear_cache:
        import shutil
        if cache_dir.exists():
            shutil.rmtree(cache_dir)
            print(f"Cleared cache: {cache_dir}")
        cache_dir.mkdir(exist_ok=True)
    
    # Collect test files
    fptest_files = []
    
    if args.local:
        # Use local files
        for path in args.local:
            if os.path.isfile(path):
                fptest_files.append(path)
            elif os.path.isdir(path):
                for f in sorted(os.listdir(path)):
                    if f.endswith('.fptest'):
                        fptest_files.append(os.path.join(path, f))
            else:
                parser.error(f'Local path does not exist: {path}')
    elif args.all:
        # Download all available files
        for filename in AVAILABLE_TEST_FILES:
            try:
                path = download_test_file(filename, cache_dir)
                fptest_files.append(str(path))
            except RuntimeError as e:
                print(f"Warning: {e}")
    elif args.files:
        # Download specified files
        for filename in args.files:
            # Check if it's in the available list
            if filename not in AVAILABLE_TEST_FILES:
                print(f"Warning: '{filename}' not in known test files. Trying anyway...")
            try:
                path = download_test_file(filename, cache_dir)
                fptest_files.append(str(path))
            except RuntimeError as e:
                print(f"Warning: {e}")
    else:
        # Default: use Add-Shift.fptest
        try:
            path = download_test_file("Add-Shift.fptest", cache_dir)
            fptest_files.append(str(path))
        except RuntimeError as e:
            parser.error(str(e))
    
    if not fptest_files:
        parser.error('No .fptest files found')
    
    # Define filter functions
    def filter_tests(tests: list[TestCase]) -> list[TestCase]:
        result = tests
        
        # Filter by operation
        if args.operation != 'all':
            op_map = {
                'add': Operation.ADD,
                'sub': Operation.SUBTRACT,
                'mul': Operation.MULTIPLY,
                'div': Operation.DIVIDE,
            }
            target_op = op_map[args.operation]
            result = [t for t in result if t.operation == target_op]
        
        # Filter by precision
        if args.precision != 'all':
            target_precision = Precision.BINARY32 if args.precision == 'f32' else Precision.BINARY64
            result = [t for t in result if t.precision == target_precision]
        
        # Apply max tests limit
        if args.max_tests and len(result) > args.max_tests:
            result = result[:args.max_tests]
        
        return result
    
    if args.packages:
        # Generate separate packages for each test module
        output_dir = args.output_dir or "test_packages"
        os.makedirs(output_dir, exist_ok=True)
        
        tests_by_file = {}
        total_parsed = 0
        
        for filepath in fptest_files:
            source_name = os.path.basename(filepath)
            print(f"Parsing {source_name}...")
            tests = parse_fptest_file(filepath)
            total_parsed += len(tests)
            filtered = filter_tests(tests)
            if filtered:
                tests_by_file[source_name] = filtered
                print(f"  {len(tests)} parsed, {len(filtered)} after filtering")
        
        # Add synthetic f64 tests if requested
        if args.synthetic_f64:
            synthetic_tests = generate_synthetic_f64_tests()
            if synthetic_tests:
                tests_by_file["Synthetic-F64-Corner-Cases.synthetic"] = synthetic_tests
                total_parsed += len(synthetic_tests)
        
        print(f"\nParsed {total_parsed} total test cases")
        
        results = generate_noir_packages(
            tests_by_file, 
            output_dir, 
            add_debug=args.debug,
            chunk_size=args.chunk_size,
            max_tests_per_package=args.max_tests_per_package,
            force_f64=args.generate_f64,
            generate_both=args.generate_f64  # When --generate-f64 is set, generate both
        )
        
        total_generated = sum(results.values())
        print(f"\nTotal: {total_generated} tests generated across {len(results)} packages")
        
        # Generate CI matrix if requested
        if args.ci_matrix:
            generate_ci_matrix(
                tests_by_file,
                args.ci_matrix,
                chunk_size=args.chunk_size,
                max_tests_per_package=args.max_tests_per_package,
                force_f64=args.generate_f64,
                generate_both=args.generate_f64,
            )
    
    else:
        # Parse all test files into one list
        all_tests = []
        for filepath in fptest_files:
            print(f"Parsing {os.path.basename(filepath)}...")
            tests = parse_fptest_file(filepath)
            all_tests.extend(tests)
        
        print(f"Parsed {len(all_tests)} total test cases")
        
        all_tests = filter_tests(all_tests)
        print(f"After filtering: {len(all_tests)} tests")
        
        # Generate Noir file
        generate_noir_file(
            all_tests,
            args.output,
            [os.path.basename(f) for f in fptest_files],
            add_debug=args.debug,
            force_f64=args.generate_f64
        )


if __name__ == '__main__':
    main()
