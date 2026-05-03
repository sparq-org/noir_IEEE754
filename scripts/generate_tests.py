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
import urllib.request
import urllib.error
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


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

# Known bad test cases in the IBM FPgen test suite (bugs in expected values)
# Format: set of (raw_line_without_flags,) tuples - we match by the operation + operands
KNOWN_BAD_TESTS = {
    # Divide-Divide-By-Zero-Exception.fptest line 6: incorrect expected result
    # +1.2CEE1BP-64 / +1.50EFBDP-30 should give 0x2E64A490, not 0x2E29F109
    "b32/ =0 +1.2CEE1BP-64 +1.50EFBDP-30",
    "b32/ =0 oz +1.2CEE1BP-64 +1.50EFBDP-30",  # Same test with overflow flag
}


def generate_synthetic_f64_tests() -> list['TestCase']:
    """Generate synthetic float64 test cases for corner cases.
    
    These tests cover the same categories as the IBM FPgen b32 tests but for f64:
    - Corner rounding (denormal * denormal -> denormal/zero)
    - Underflow transitions
    - Hamming distance edge cases
    - Sticky bit calculations
    - Division trailing zeros
    
    Note: Uses a fixed seed (42) for reproducible/deterministic test generation.
    """
    random.seed(42)  # Reproducible tests - ensures deterministic test generation
    
    tests = []
    
    # Float64 constants
    F64_BIAS = 1023
    F64_MIN_EXP = -1022  # Minimum normal exponent
    F64_MAX_EXP = 1023   # Maximum exponent
    F64_MANTISSA_BITS = 52
    F64_MIN_DENORM = 2**(-1074)  # Smallest positive denormal
    F64_MIN_NORMAL = 2**(-1022)  # Smallest positive normal
    
    # Helper to create TestCase for f64
    def make_f64_test(op: Operation, a_bits: int, b_bits: int, line_num: int, desc: str) -> 'TestCase':
        a = float64_from_bits(a_bits)
        b = float64_from_bits(b_bits)
        
        # Create FPValue from bits
        def bits_to_fpvalue(bits: int) -> 'FPValue':
            sign = (bits >> 63) & 1
            exp = (bits >> 52) & 0x7FF
            mant = bits & ((1 << 52) - 1)
            
            if exp == 0x7FF:
                if mant == 0:
                    return FPValue(sign=sign, significand="", exponent=0, is_inf=True)
                else:
                    return FPValue(sign=sign, significand="", exponent=0, is_nan=True)
            elif exp == 0:
                if mant == 0:
                    return FPValue(sign=sign, significand="", exponent=0, is_zero=True)
                else:
                    # Denormal
                    return FPValue(sign=sign, significand=f"0{mant:013X}", exponent=-1022)
            else:
                # Normal
                return FPValue(sign=sign, significand=f"1{mant:013X}", exponent=exp - F64_BIAS)
        
        op1 = bits_to_fpvalue(a_bits)
        op2 = bits_to_fpvalue(b_bits)
        
        # Compute expected result
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
        result_val = bits_to_fpvalue(result_bits)
        
        return TestCase(
            precision=Precision.BINARY64,
            operation=op,
            rounding=RoundingMode.NEAREST_EVEN,
            operand1=op1,
            operand2=op2,
            operand3=None,
            result=result_val,
            exception_flags="",
            line_number=line_num,
            raw_line=f"synthetic_f64 {desc}"
        )
    
    line_num = 0
    
    # ========== Corner Rounding Tests (like b32 Corner-Rounding.fptest) ==========
    # These test denormal * denormal -> zero/tiny denormal transitions
    
    # Smallest denormals multiplied
    for i in range(20):
        # Very small denormals that multiply to zero or smallest denormal
        a_mant = random.randint(1, 0xFFFF)  # Small mantissa
        b_mant = random.randint(1, 0xFFFF)
        a_bits = a_mant  # Denormal (exp=0)
        b_bits = b_mant
        if random.random() < 0.5:
            a_bits |= (1 << 63)  # Negative
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"corner_mul_denorm_{i}"))
        line_num += 1
    
    # Division with denormals
    for i in range(20):
        # Denormal / large number -> zero
        a_mant = random.randint(1, 0xFFFFFFFFFFF)
        a_bits = a_mant  # Denormal
        # Large divisor
        b_exp = random.randint(900, 1023)
        b_mant = random.randint(0, (1 << 52) - 1)
        b_bits = (b_exp << 52) | b_mant
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.DIVIDE, a_bits, b_bits, line_num, f"corner_div_denorm_{i}"))
        line_num += 1
    
    # ========== Underflow Tests ==========
    # Numbers that underflow from normal to denormal
    for i in range(30):
        # Small normal * small normal -> denormal
        a_exp = random.randint(1, 50)  # Very small normal exponent
        b_exp = random.randint(1, 50)
        a_mant = random.randint(0, (1 << 52) - 1)
        b_mant = random.randint(0, (1 << 52) - 1)
        a_bits = (a_exp << 52) | a_mant
        b_bits = (b_exp << 52) | b_mant
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"underflow_mul_{i}"))
        line_num += 1
    
    # Division underflow
    for i in range(20):
        # Small normal / large normal -> denormal
        a_exp = random.randint(1, 100)
        b_exp = random.randint(1500, 2046)
        a_mant = random.randint(0, (1 << 52) - 1)
        b_mant = random.randint(0, (1 << 52) - 1)
        a_bits = (a_exp << 52) | a_mant
        b_bits = (b_exp << 52) | b_mant
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.DIVIDE, a_bits, b_bits, line_num, f"underflow_div_{i}"))
        line_num += 1
    
    # ========== Hamming Distance Tests ==========
    # Adjacent values that differ by 1 ULP
    for i in range(30):
        # Create a value and add/subtract 1 ULP
        exp = random.randint(1, 2046)
        mant = random.randint(1, (1 << 52) - 2)
        base_bits = (exp << 52) | mant
        ulp_bits = base_bits + 1  # 1 ULP higher
        
        base = float64_from_bits(base_bits)
        ulp = float64_from_bits(ulp_bits)
        diff = ulp - base  # This is 1 ULP
        
        # Test addition of values that result in 1 ULP difference
        a_bits = float64_to_bits(base)
        b_bits = float64_to_bits(diff)
        tests.append(make_f64_test(Operation.ADD, a_bits, b_bits, line_num, f"hamming_add_{i}"))
        line_num += 1
        
        # Subtraction test
        tests.append(make_f64_test(Operation.SUBTRACT, float64_to_bits(ulp), b_bits, line_num, f"hamming_sub_{i}"))
        line_num += 1
    
    # ========== Sticky Bit Tests ==========
    # Values where sticky bit affects rounding
    for i in range(30):
        # Create values where intermediate result has sticky bits
        exp_a = random.randint(500, 1500)
        exp_b = random.randint(500, 1500)
        mant_a = random.randint((1 << 51), (1 << 52) - 1)  # Ensure many bits set
        mant_b = random.randint((1 << 51), (1 << 52) - 1)
        a_bits = (exp_a << 52) | mant_a
        b_bits = (exp_b << 52) | mant_b
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"sticky_mul_{i}"))
        line_num += 1
    
    # ========== Division Trailing Zeros Tests ==========
    # Division that results in exact values (no rounding needed)
    for i in range(20):
        # Powers of 2 division
        exp_a = random.randint(100, 1900)
        exp_b = random.randint(100, 1900)
        a_bits = exp_a << 52  # 1.0 * 2^(exp-1023)
        b_bits = exp_b << 52
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.DIVIDE, a_bits, b_bits, line_num, f"div_pow2_{i}"))
        line_num += 1
    
    # ========== Rounding Boundary Tests ==========
    # Values exactly at rounding boundaries
    for i in range(30):
        # Create values that are exactly at a rounding boundary (guard bit = 1, round = 0, sticky = 0)
        exp = random.randint(100, 1900)
        # Mantissa with specific bit pattern for rounding
        mant = random.randint(0, (1 << 48) - 1) << 4  # Clear low 4 bits
        mant |= 0x8  # Set guard bit exactly at midpoint
        a_bits = (exp << 52) | mant
        b_bits = (1023 << 52)  # 1.0
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"round_boundary_{i}"))
        line_num += 1
    
    # ========== Overflow Boundary Tests ==========
    for i in range(20):
        # Large values that multiply to near-overflow
        exp_a = random.randint(1800, 2046)
        exp_b = random.randint(1, 300)
        mant_a = random.randint(0, (1 << 52) - 1)
        mant_b = random.randint(0, (1 << 52) - 1)
        a_bits = (exp_a << 52) | mant_a
        b_bits = (exp_b << 52) | mant_b
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"overflow_mul_{i}"))
        line_num += 1
    
    # ========== Denormal Input Normalization Tests ==========
    # These specifically test the denormal normalization path (like the float32 fixes)
    for i in range(30):
        # Denormal with specific leading bit positions
        leading_pos = random.randint(0, 51)
        mant = (1 << leading_pos) | random.randint(0, (1 << leading_pos) - 1)
        a_bits = mant  # Denormal
        
        # Multiply by a normal value
        b_exp = random.randint(1, 100)
        b_mant = random.randint(0, (1 << 52) - 1)
        b_bits = (b_exp << 52) | b_mant
        if random.random() < 0.5:
            a_bits |= (1 << 63)
        if random.random() < 0.5:
            b_bits |= (1 << 63)
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"denorm_normalize_mul_{i}"))
        line_num += 1
        
        # Division with denormal dividend
        tests.append(make_f64_test(Operation.DIVIDE, a_bits, b_bits, line_num, f"denorm_normalize_div_{i}"))
        line_num += 1
    
    # ========== Specific Known Problematic Patterns ==========
    # These are patterns that were problematic for float32 and should be tested for float64
    
    # Denormal result that rounds up to normal
    for i in range(10):
        # Just below normal threshold
        a_bits = 0x000FFFFFFFFFFFFF  # Largest denormal
        b_exp = random.randint(1020, 1026)
        b_mant = random.randint(0, (1 << 52) - 1)
        b_bits = (b_exp << 52) | b_mant
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"denorm_to_normal_{i}"))
        line_num += 1
    
    # Very small result that might incorrectly round to zero
    for i in range(10):
        a_bits = 0x0000000000000001  # Smallest denormal
        b_exp = random.randint(1020, 1026)
        b_bits = b_exp << 52
        tests.append(make_f64_test(Operation.MULTIPLY, a_bits, b_bits, line_num, f"tiny_mul_{i}"))
        line_num += 1
    
    print(f"Generated {len(tests)} synthetic f64 test cases")
    return tests


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
    """
    Parse a floating-point value from the test file format.
    
    Format: <sign><significand>P<exponent>
    Examples: +1.01FD72P-118, -0.7FFFFFP-126, +Inf, -Zero, Q, S
    """
    value_str = value_str.strip()
    
    # Handle special values
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
    
    # Parse regular values: <sign><significand>P<exponent>
    # Examples: +1.01FD72P-118, -0.7FFFFFP-126
    match = re.match(r'^([+-]?)(\d+)\.([0-9A-Fa-f]+)P([+-]?\d+)$', value_str)
    if not match:
        raise ValueError(f"Cannot parse FP value: {value_str}")
    
    sign_str, int_part, frac_part, exp_str = match.groups()
    sign = 1 if sign_str == '-' else 0
    exponent = int(exp_str)
    
    # Combine integer and fractional parts
    # int_part is typically 0 or 1
    significand = int_part + frac_part
    
    return FPValue(sign=sign, significand=significand, exponent=exponent)


# Special bit patterns for IEEE 754
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
    
    # Parse significand: "1" + hex_fraction or "0" + hex_fraction (for denormals)
    int_part = int(val.significand[0])
    frac_hex = val.significand[1:]
    
    if is_float32:
        # Float32: 23-bit mantissa, 8-bit exponent (bias 127)
        MANTISSA_BITS = 23
        EXP_BIAS = 127
        EXP_MAX = 254  # Max normal exponent (biased)
        # Test format uses 6 hex digits = 24 bits, we need 23
        # Pad/truncate to exactly 6 hex digits
        frac_hex_padded = frac_hex.ljust(6, '0')[:6]
        frac_bits_24 = int(frac_hex_padded, 16)
        # Round from 24 bits to 23 bits (round to nearest, ties to even)
        lsb = (frac_bits_24 >> 1) & 1
        round_bit = frac_bits_24 & 1
        frac_bits_23 = frac_bits_24 >> 1
        if round_bit and (lsb or (frac_bits_24 & 0)):  # round up
            frac_bits_23 += round_bit
        mantissa = frac_bits_23 & 0x7FFFFF
    else:
        # Float64: 52-bit mantissa, 11-bit exponent (bias 1023)
        MANTISSA_BITS = 52
        EXP_BIAS = 1023
        EXP_MAX = 2046
        # Test format uses 13 hex digits = 52 bits exactly
        frac_hex_padded = frac_hex.ljust(13, '0')[:13]
        mantissa = int(frac_hex_padded, 16) & ((1 << 52) - 1)
    
    # Calculate biased exponent
    biased_exp = val.exponent + EXP_BIAS
    
    # Handle denormals (int_part == 0) and normal numbers (int_part == 1)
    if int_part == 0:
        # Denormal: exponent field is 0, mantissa as-is
        biased_exp = 0
    elif biased_exp <= 0:
        # Underflow to denormal
        biased_exp = 0
    elif biased_exp > EXP_MAX:
        # Overflow to infinity
        return special['neg_inf'] if val.sign else special['pos_inf']
    
    # Assemble IEEE 754 bits
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
    
    # Skip empty lines and comments
    if not line or line.startswith('--') or line.startswith('#'):
        return None
    
    # Skip headers like "Floating point tests: ..."
    if line.startswith('Floating point tests') or line.startswith('Copyright'):
        return None
    
    # Skip known bad tests (bugs in the IBM FPgen test suite)
    # We check if the line starts with any known bad prefix
    for bad_prefix in KNOWN_BAD_TESTS:
        if line.startswith(bad_prefix):
            return None
    
    # Parse precision and operation
    # Format: b32+ or b64- or b32* etc.
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
    
    # Parse rounding mode
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
    
    # Check for exception flags before operands
    exception_flags = ""
    exc_match = re.match(r'^([iI])\s+(.*)$', rest)
    if exc_match:
        exception_flags = exc_match.group(1)
        rest = exc_match.group(2)
    
    # Split by -> to get operands and result
    if ' -> ' not in rest:
        return None
    
    operands_str, result_str = rest.split(' -> ', 1)
    
    # Parse result and result flags
    result_parts = result_str.split()
    if not result_parts:
        return None
    
    result_value_str = result_parts[0]
    result_flags = ' '.join(result_parts[1:]) if len(result_parts) > 1 else ''
    
    # Parse operands (space-separated)
    operand_strs = operands_str.split()
    if not operand_strs:
        return None
    
    try:
        operand1 = parse_fp_value(operand_strs[0])
        operand2 = parse_fp_value(operand_strs[1]) if len(operand_strs) > 1 else None
        operand3 = parse_fp_value(operand_strs[2]) if len(operand_strs) > 2 else None
        result = parse_fp_value(result_value_str)
    except ValueError as e:
        # Skip malformed values
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
    
    # Convert operands to bits
    # For force_f64 mode, first convert to f32, then to f64 value, then to f64 bits
    if force_f64 and original_is_f32:
        # Get the float32 values first
        bits1_f32 = fp_value_to_bits32(test.operand1)
        bits2_f32 = fp_value_to_bits32(test.operand2)
        f1 = float32_from_bits(bits1_f32)
        f2 = float32_from_bits(bits2_f32)
        # Convert to f64 bits (Python floats are f64, so this is straightforward)
        bits1 = float64_to_bits(f1)
        bits2 = float64_to_bits(f2)
    else:
        to_bits = fp_value_to_bits32 if is_float32 else fp_value_to_bits64
        from_bits = float32_from_bits if is_float32 else float64_from_bits
        bits1 = to_bits(test.operand1)
        bits2 = to_bits(test.operand2)
        f1, f2 = from_bits(bits1), from_bits(bits2)
    
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
    use_packages: bool = True
) -> list[dict]:
    """Generate a CI matrix JSON file for GitHub Actions.
    
    Lists all packages that will be generated. Large test files are automatically
    split into multiple packages by generate_noir_packages.
    
    Args:
        max_tests_per_package: Maximum tests per package (50 chunks * 25 tests = 1250)
        use_packages: If True, generate matrix for separate packages (new style)
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


def generate_noir_file_per_source(
    tests_by_file: dict[str, list[TestCase]], 
    output_dir: str, 
    add_debug: bool = False,
    chunk_size: int = 25,
    force_f64: bool = False,
    generate_both: bool = False
) -> dict[str, int]:
    """Generate separate Noir test files for each source file, chunked into groups.
    
    Args:
        tests_by_file: Dict mapping source filenames to test cases
        output_dir: Output directory for generated files
        add_debug: Add println statements for debugging
        chunk_size: Number of tests per chunk file
        force_f64: If True, convert f32 tests to f64 only
        generate_both: If True, generate both f32 and f64 tests (overrides force_f64)
    """
    results = {}
    module_names = []
    
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
        
        # Create folder and write chunks
        module_dir = os.path.join(output_dir, module_name)
        os.makedirs(module_dir, exist_ok=True)
        
        chunks = [all_test_code[i:i + chunk_size] for i in range(0, len(all_test_code), chunk_size)]
        chunk_names = []
        
        for chunk_idx, chunk in enumerate(chunks):
            chunk_name = f"chunk_{chunk_idx:04d}"
            chunk_names.append(chunk_name)
            
            # Analyze this chunk to determine required imports
            analysis = analyze_test_code(chunk)
            header = generate_noir_header_from_analysis(f"{source_file} (chunk {chunk_idx})", analysis)
            
            with open(os.path.join(module_dir, f"{chunk_name}.nr"), 'w') as f:
                f.write(header)
                f.write('\n'.join(chunk))
        
        # Generate mod.nr for this module
        with open(os.path.join(module_dir, "mod.nr"), 'w') as f:
            f.write(f"// Auto-generated module index for {source_file}\n")
            f.write(f"// Contains {len(all_test_code)} tests in {len(chunks)} chunks of {chunk_size}\n\n")
            f.writelines(f"mod {name};\n" for name in chunk_names)
        
        print(f"Generated {len(all_test_code)} tests in {len(chunks)} chunks to {module_dir}/")
        results[source_file] = len(all_test_code)
        module_names.append(module_name)
    
    # Generate top-level module index
    with open(os.path.join(output_dir, "mod.nr"), 'w') as f:
        f.write("// Auto-generated module index for IEEE 754 tests\n")
        f.write("// Each module corresponds to a source .fptest file\n\n")
        f.writelines(f"mod {name};\n" for name in sorted(module_names))
    
    print(f"\nGenerated module index at {output_dir}/mod.nr")
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
  %(prog)s --all --split                # Generate chunked test folders per source (old style)
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
        help='Output directory for split test files (use with --split)'
    )
    parser.add_argument(
        '--split',
        action='store_true',
        help='Generate separate test files for each source file (old style, as modules in src/)'
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
        help='Number of tests per chunk file when using --split (default: 25)'
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
        help='Maximum number of tests to generate (per file when using --split)'
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
        help='Generate CI matrix JSON file for GitHub Actions (use with --split)'
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
                use_packages=True
            )
    
    elif args.split:
        # Generate separate files per source
        output_dir = args.output_dir or "src/ieee754_tests"
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
        
        print(f"\nParsed {total_parsed} total test cases")
        
        results = generate_noir_file_per_source(
            tests_by_file, 
            output_dir, 
            add_debug=args.debug,
            chunk_size=args.chunk_size,
            force_f64=args.generate_f64,
            generate_both=args.generate_f64  # When --generate-f64 is set, generate both
        )
        
        total_generated = sum(results.values())
        print(f"\nTotal: {total_generated} tests generated across {len(results)} files")
        
        # Generate CI matrix if requested
        if args.ci_matrix:
            generate_ci_matrix(tests_by_file, args.ci_matrix, chunk_size=args.chunk_size, force_f64=args.generate_f64, generate_both=args.generate_f64)
        
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
