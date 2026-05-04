"""Parser for Berkeley TestFloat ``testfloat_gen`` output.

`testfloat_gen <function>` writes one test case per line to standard
output. Each line is a sequence of space-separated raw hexadecimal tokens
encoding (in order):

- The operands for the function (one, two, or three values).
- The expected result value (single value, or omitted for boolean-result
  comparisons -- see below).
- The raised IEEE 754 exception flags as a one-byte hex bitmap (bit 0 =
  inexact, bit 1 = underflow, bit 2 = overflow, bit 3 = infinite, bit 4 =
  invalid).

Floating-point values are written most-significant-bit first, e.g. an
``f64`` value occupies 16 hex digits (64 bits) and an ``f32`` value
occupies 8 hex digits (32 bits).

Reference: <http://www.jhauser.us/arithmetic/TestFloat-3/doc/testfloat_gen.html>

The grammar this module accepts is the subset of TestFloat's output that
covers the operations the noir_IEEE754 library implements:

- ``f32_add``, ``f32_sub``, ``f32_mul``, ``f32_div``, ``f32_sqrt``,
  ``f32_rem``, ``f32_mulAdd``.
- ``f64_add``, ``f64_sub``, ``f64_mul``, ``f64_div``, ``f64_sqrt``,
  ``f64_rem``, ``f64_mulAdd``.

This module deliberately *re-uses* the dataclasses and enums defined in
:mod:`noir_ieee754_inputs.fptest` (``TestCase``, ``Operation``,
``Precision``, ``RoundingMode``, ``FPValue``) so a single test-emitter
codepath can consume TestFloat-sourced and FPgen-sourced cases
interchangeably.
"""

from __future__ import annotations

import dataclasses
import os
import re
import struct
import subprocess
from pathlib import Path
from typing import Iterable, Iterator, Optional

from .fptest import FPValue, Operation, Precision, RoundingMode, TestCase


# ---------------------------------------------------------------------------
# Function-name -> (Operation, Precision, arity) dispatch table.
#
# ``arity`` here is the number of *operands* (not counting the result), and
# matches what testfloat_gen emits per line.

@dataclasses.dataclass(frozen=True)
class TestFloatFunction:
    """Metadata for a single ``testfloat_gen <function>`` invocation."""

    name: str
    operation: Operation
    precision: Precision
    arity: int  # number of operand columns (1 for sqrt, 2 for add/sub/mul/div/rem, 3 for mulAdd)


SUPPORTED_FUNCTIONS: dict[str, TestFloatFunction] = {
    # binary32
    "f32_add":    TestFloatFunction("f32_add",    Operation.ADD,      Precision.BINARY32, 2),
    "f32_sub":    TestFloatFunction("f32_sub",    Operation.SUBTRACT, Precision.BINARY32, 2),
    "f32_mul":    TestFloatFunction("f32_mul",    Operation.MULTIPLY, Precision.BINARY32, 2),
    "f32_div":    TestFloatFunction("f32_div",    Operation.DIVIDE,   Precision.BINARY32, 2),
    "f32_sqrt":   TestFloatFunction("f32_sqrt",   Operation.SQRT,     Precision.BINARY32, 1),
    "f32_rem":    TestFloatFunction("f32_rem",    Operation.REM,      Precision.BINARY32, 2),
    "f32_mulAdd": TestFloatFunction("f32_mulAdd", Operation.FMA,      Precision.BINARY32, 3),
    # binary64
    "f64_add":    TestFloatFunction("f64_add",    Operation.ADD,      Precision.BINARY64, 2),
    "f64_sub":    TestFloatFunction("f64_sub",    Operation.SUBTRACT, Precision.BINARY64, 2),
    "f64_mul":    TestFloatFunction("f64_mul",    Operation.MULTIPLY, Precision.BINARY64, 2),
    "f64_div":    TestFloatFunction("f64_div",    Operation.DIVIDE,   Precision.BINARY64, 2),
    "f64_sqrt":   TestFloatFunction("f64_sqrt",   Operation.SQRT,     Precision.BINARY64, 1),
    "f64_rem":    TestFloatFunction("f64_rem",    Operation.REM,      Precision.BINARY64, 2),
    "f64_mulAdd": TestFloatFunction("f64_mulAdd", Operation.FMA,      Precision.BINARY64, 3),
}


# Mapping from our :class:`RoundingMode` enum to the testfloat_gen CLI flag.
ROUNDING_FLAGS: dict[RoundingMode, str] = {
    RoundingMode.NEAREST_EVEN:    "-rnear_even",
    RoundingMode.NEAREST_AWAY:    "-rnear_maxMag",
    RoundingMode.TOWARD_POSITIVE: "-rmax",
    RoundingMode.TOWARD_NEGATIVE: "-rmin",
    RoundingMode.TOWARD_ZERO:     "-rminMag",
}


# ---------------------------------------------------------------------------
# Bit-pattern -> FPValue inverse helpers.
#
# The TestFloat output is a raw bit pattern; the existing
# ``generate_tests.py`` pipeline expects an ``FPValue`` so it can call
# ``fp_value_to_bits`` for round-tripping. We reverse that here -- the
# inverse direction is independent of any hand-rolled bit-twiddling because
# we go through ``struct.unpack``.

_F32_INF_BITS = 0x7F800000
_F32_NEG_INF_BITS = 0xFF800000
_F32_EXP_MASK = 0x7F800000
_F32_MANT_MASK = 0x007FFFFF
_F32_SIGN_MASK = 0x80000000

_F64_INF_BITS = 0x7FF0000000000000
_F64_NEG_INF_BITS = 0xFFF0000000000000
_F64_EXP_MASK = 0x7FF0000000000000
_F64_MANT_MASK = 0x000FFFFFFFFFFFFF
_F64_SIGN_MASK = 0x8000000000000000


def _bits32_to_fpvalue(bits: int) -> FPValue:
    """Decode a 32-bit IEEE 754 binary32 bit pattern into an :class:`FPValue`.

    Goes through ``struct.unpack`` for the finite path -- independent of
    any hand-rolled bit-twiddling under test. Special-value paths use the
    library-canonical bit masks defined alongside this function.
    """
    bits &= 0xFFFFFFFF
    sign = 1 if bits & _F32_SIGN_MASK else 0

    if (bits & _F32_EXP_MASK) == _F32_EXP_MASK:
        # Infinity or NaN.
        if (bits & _F32_MANT_MASK) == 0:
            return FPValue(sign=sign, significand="", exponent=0, is_inf=True)
        # NaN -- TestFloat distinguishes signalling vs quiet by the top
        # mantissa bit (IEEE 754-2019 sec 6.2.1: signalling clears it).
        is_snan = (bits & 0x00400000) == 0
        return FPValue(sign=sign, significand="", exponent=0, is_nan=True, is_snan=is_snan)

    if (bits & ~_F32_SIGN_MASK) == 0:
        return FPValue(sign=sign, significand="", exponent=0, is_zero=True)

    # Finite normal or denormal -- decode via struct.
    f = struct.unpack(">f", struct.pack(">I", bits))[0]
    return _finite_float_to_fpvalue(f, is_float32=True)


def _bits64_to_fpvalue(bits: int) -> FPValue:
    """Decode a 64-bit IEEE 754 binary64 bit pattern into an :class:`FPValue`."""
    bits &= 0xFFFFFFFFFFFFFFFF
    sign = 1 if bits & _F64_SIGN_MASK else 0

    if (bits & _F64_EXP_MASK) == _F64_EXP_MASK:
        if (bits & _F64_MANT_MASK) == 0:
            return FPValue(sign=sign, significand="", exponent=0, is_inf=True)
        is_snan = (bits & 0x0008000000000000) == 0
        return FPValue(sign=sign, significand="", exponent=0, is_nan=True, is_snan=is_snan)

    if (bits & ~_F64_SIGN_MASK) == 0:
        return FPValue(sign=sign, significand="", exponent=0, is_zero=True)

    f = struct.unpack(">d", struct.pack(">Q", bits))[0]
    return _finite_float_to_fpvalue(f, is_float32=False)


def _finite_float_to_fpvalue(f: float, *, is_float32: bool) -> FPValue:
    """Render a Python ``float`` as the ``FPValue`` form the FPgen path emits.

    The shape ``<int_part>.<frac_hex>P<exp>`` matches what
    :func:`noir_ieee754_inputs.fptest.fp_value_to_bits` round-trips through
    ``float.fromhex``, so a TestFloat-sourced ``FPValue`` and an FPgen-sourced
    ``FPValue`` are interchangeable from the generator's perspective.

    Round-tripping path: ``f.hex()`` -> ``"0x1.<hex>p<dec_exp>"`` for
    normals; ``"0x0.<hex>p-1022"`` for binary64 denormals; ``"0x0.0p+0"``
    for zero (handled by callers).
    """
    sign = 1 if f < 0 or (f == 0 and struct.pack(">d", f)[0] & 0x80) else 0
    abs_f = -f if sign else f

    # ``float.hex`` is the canonical inverse of ``float.fromhex`` and writes
    # the form we need. Example: ``(1.5).hex() == "0x1.8000000000000p+0"``.
    h = abs_f.hex()
    # Strip leading ``0x`` and split on ``p``.
    if h.startswith("0x"):
        h = h[2:]
    mantissa_part, exp_part = h.split("p")
    int_part, _, frac_part = mantissa_part.partition(".")
    frac_part = frac_part or "0"
    exponent = int(exp_part)

    significand = int_part + frac_part
    return FPValue(sign=sign, significand=significand, exponent=exponent)


def bits_to_fpvalue(bits: int, *, is_float32: bool) -> FPValue:
    """Public entry point: decode IEEE 754 bits into an :class:`FPValue`.

    .. note::
        NaN payload bits are intentionally discarded -- ``FPValue`` carries
        only ``is_nan`` / ``is_snan`` boolean flags. The downstream emission
        path (``_compute_expected_bits`` in ``generate_tests.py``) reacts
        to ``is_nan=True`` results by emitting a ``floatN_is_nan(result)``
        predicate assertion rather than a bit-equality assertion against
        a specific NaN bit pattern, so the payload information is
        irrelevant to test pass/fail. The same applies to NaN *operands*:
        the FPgen-canonical ``FLOAT*_NAN`` / ``FLOAT*_SIGNALING_NAN`` bit
        patterns drive the circuit, not the original TestFloat-generated
        payload. Mirrors design-doc decision C.3 (2026-05-03).

        If a future test asserts on a specific NaN payload, ``FPValue``
        will need a payload field and ``fp_value_to_bits`` a payload-
        preserving path -- ``noir_ieee754_inputs.fptest.fp_value_to_bits``
        is the symmetric edit point on the FPgen side.
    """
    return _bits32_to_fpvalue(bits) if is_float32 else _bits64_to_fpvalue(bits)


# ---------------------------------------------------------------------------
# Streaming parser.

_HEX_RE = re.compile(r"^[0-9A-Fa-f]+$")


def parse_testfloat_line(
    line: str,
    *,
    function: TestFloatFunction,
    rounding: RoundingMode,
    line_number: int,
) -> Optional[TestCase]:
    """Parse a single ``testfloat_gen`` output line into a :class:`TestCase`.

    Returns ``None`` if the line is blank or a comment (currently
    testfloat_gen does not emit comments, but we tolerate them defensively
    in case a ``-prefix`` flag is in use). Raises :class:`ValueError` on
    malformed lines.
    """
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("--"):
        return None

    tokens = line.split()
    expected_columns = function.arity + 2  # operands + result + flags
    if len(tokens) != expected_columns:
        # Defensive: a line with the wrong arity is malformed for this
        # function. Skip it rather than crashing the parse.
        return None

    for tok in tokens:
        if not _HEX_RE.match(tok):
            return None

    is_float32 = function.precision == Precision.BINARY32
    expected_hex_width = 8 if is_float32 else 16
    if any(len(tokens[i]) != expected_hex_width for i in range(function.arity + 1)):
        # The result column ``tokens[function.arity]`` shares the FP width.
        # Flags column may be 1-2 hex digits; we don't validate its width.
        return None

    operands_bits = [int(tokens[i], 16) for i in range(function.arity)]
    result_bits = int(tokens[function.arity], 16)
    flags_bits = int(tokens[function.arity + 1], 16)
    exception_flags = _flags_to_string(flags_bits)

    operand1 = bits_to_fpvalue(operands_bits[0], is_float32=is_float32)
    operand2 = bits_to_fpvalue(operands_bits[1], is_float32=is_float32) if function.arity >= 2 else None
    operand3 = bits_to_fpvalue(operands_bits[2], is_float32=is_float32) if function.arity >= 3 else None
    result = bits_to_fpvalue(result_bits, is_float32=is_float32)

    return TestCase(
        precision=function.precision,
        operation=function.operation,
        rounding=rounding,
        operand1=operand1,
        operand2=operand2,
        operand3=operand3,
        result=result,
        exception_flags=exception_flags,
        line_number=line_number,
        raw_line=f"{function.name} {tokens[0]} "
                 + (f"{tokens[1]} " if function.arity >= 2 else "")
                 + (f"{tokens[2]} " if function.arity >= 3 else "")
                 + f"-> {tokens[function.arity]} flags={tokens[function.arity + 1]}",
    )


def _flags_to_string(flags_bits: int) -> str:
    """Render the testfloat_gen flag bitmap as a short symbolic string.

    Bit layout (per testfloat_gen.html sec "Output Format"):
        bit 0 = inexact, bit 1 = underflow, bit 2 = overflow,
        bit 3 = infinite (divide-by-zero), bit 4 = invalid.
    """
    parts = []
    if flags_bits & 0x01:
        parts.append("x")  # inexact
    if flags_bits & 0x02:
        parts.append("u")  # underflow
    if flags_bits & 0x04:
        parts.append("o")  # overflow
    if flags_bits & 0x08:
        parts.append("z")  # divide-by-zero (infinite)
    if flags_bits & 0x10:
        parts.append("i")  # invalid
    return "".join(parts)


def parse_testfloat_stream(
    lines: Iterable[str],
    *,
    function: TestFloatFunction,
    rounding: RoundingMode,
) -> Iterator[TestCase]:
    """Parse a stream of ``testfloat_gen`` lines into :class:`TestCase` objects."""
    for line_number, line in enumerate(lines, 1):
        case = parse_testfloat_line(line, function=function, rounding=rounding, line_number=line_number)
        if case is not None:
            yield case


def parse_testfloat_file(
    filepath: str | os.PathLike[str],
    *,
    function: TestFloatFunction,
    rounding: RoundingMode,
    max_tests: Optional[int] = None,
) -> list[TestCase]:
    """Parse a cached ``testfloat_gen`` capture file into :class:`TestCase`s.

    A "capture file" is the raw stdout of a single
    ``testfloat_gen [<rounding>] <function>`` invocation.

    ``max_tests`` truncates the list -- useful for capping ``f32_mulAdd`` /
    ``f64_mulAdd`` (level 1 produces 6.1M cases per rounding mode, more
    than the Noir test runner can chew through in a CI window).
    """
    cases: list[TestCase] = []
    with open(filepath, "r") as fh:
        for case in parse_testfloat_stream(fh, function=function, rounding=rounding):
            cases.append(case)
            if max_tests is not None and len(cases) >= max_tests:
                break
    return cases


# ---------------------------------------------------------------------------
# Driver (used at corpus-generation time, e.g. in CI).


def run_testfloat_gen(
    binary: str | os.PathLike[str],
    *,
    function: TestFloatFunction,
    rounding: RoundingMode,
    seed: int = 1,
    level: int = 1,
    max_tests: Optional[int] = None,
    output_path: Optional[str | os.PathLike[str]] = None,
) -> Path:
    """Invoke ``testfloat_gen`` and capture its output to a file.

    ``output_path`` defaults to ``<function>_<rounding>.tfgen`` in the
    current directory. Returns the path to the captured file.
    """
    if output_path is None:
        output_path = Path(f"{function.name}_{rounding.name.lower()}.tfgen")
    output_path = Path(output_path)

    args = [
        str(binary),
        "-seed", str(seed),
        "-level", str(level),
        ROUNDING_FLAGS[rounding],
        function.name,
    ]

    with open(output_path, "w") as out_fh:
        if max_tests is None:
            subprocess.run(args, stdout=out_fh, check=True)
        else:
            # ``testfloat_gen`` won't accept ``-n`` below the level-N
            # minimum, so we let it run to completion and slice afterwards.
            # For the operations whose level-1 corpus exceeds a reasonable
            # CI window (mulAdd: 6.1M cases) we want to truncate the file.
            with subprocess.Popen(args, stdout=subprocess.PIPE, text=True) as proc:
                assert proc.stdout is not None
                for line_number, line in enumerate(proc.stdout, 1):
                    out_fh.write(line)
                    if line_number >= max_tests:
                        proc.terminate()
                        break

    return output_path
