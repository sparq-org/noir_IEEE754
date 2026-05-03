"""Python mirrors of the IEEE 754 constants exported by ``ieee754::types``.

Each value here is intentionally identical to the corresponding ``pub global``
in ``ieee754/src/types.nr``. The two declarations are independent (this
module is hand-written, the Noir module is hand-written) which keeps the
test generator from sharing a bit-twiddling implementation with the library
under test -- a property the design doc calls out as load-bearing for
detecting shared bugs.

References: IEEE 754-2019 sec 3.4 (binary32 / binary64 layouts).
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# binary32

FLOAT32_ZERO = 0x00000000
FLOAT32_NEG_ZERO = 0x80000000
FLOAT32_ONE = 0x3F800000
FLOAT32_NEG_ONE = 0xBF800000
FLOAT32_INFINITY = 0x7F800000
FLOAT32_NEG_INFINITY = 0xFF800000
FLOAT32_NAN = 0x7FC00000
FLOAT32_SIGNALING_NAN = 0x7FA00000

FLOAT32_SIGN_MASK = 0x80000000
FLOAT32_EXPONENT_MASK = 0x7F800000
FLOAT32_MANTISSA_MASK = 0x007FFFFF

FLOAT32_MIN_DENORMAL = 0x00000001
FLOAT32_MAX_DENORMAL = 0x007FFFFF
FLOAT32_MIN_NORMAL = 0x00800000
FLOAT32_MAX_NORMAL = 0x7F7FFFFF

FLOAT32_EXP_BIAS = 127
FLOAT32_EXP_MAX_BIASED = 254  # largest biased exponent for a normal number

# ---------------------------------------------------------------------------
# binary64

FLOAT64_ZERO = 0x0000000000000000
FLOAT64_NEG_ZERO = 0x8000000000000000
FLOAT64_ONE = 0x3FF0000000000000
FLOAT64_NEG_ONE = 0xBFF0000000000000
FLOAT64_INFINITY = 0x7FF0000000000000
FLOAT64_NEG_INFINITY = 0xFFF0000000000000
FLOAT64_NAN = 0x7FF8000000000000
FLOAT64_SIGNALING_NAN = 0x7FF4000000000000

FLOAT64_SIGN_MASK = 0x8000000000000000
FLOAT64_EXPONENT_MASK = 0x7FF0000000000000
FLOAT64_MANTISSA_MASK = 0x000FFFFFFFFFFFFF

FLOAT64_MIN_DENORMAL = 0x0000000000000001
FLOAT64_MAX_DENORMAL = 0x000FFFFFFFFFFFFF
FLOAT64_MIN_NORMAL = 0x0010000000000000
FLOAT64_MAX_NORMAL = 0x7FEFFFFFFFFFFFFF

FLOAT64_EXP_BIAS = 1023
FLOAT64_EXP_MAX_BIASED = 2046

# ---------------------------------------------------------------------------
# Pack helpers

def f32_pack(sign: int, biased_exponent: int, mantissa: int) -> int:
    """Assemble a binary32 bit pattern from its three fields.

    ``sign`` is 0 or 1, ``biased_exponent`` is in [0, 255], ``mantissa`` is
    in [0, 2^23 - 1]. No range checking; callers feed already-validated
    fields.
    """
    return (
        ((sign & 1) << 31)
        | ((biased_exponent & 0xFF) << 23)
        | (mantissa & FLOAT32_MANTISSA_MASK)
    )


def f64_pack(sign: int, biased_exponent: int, mantissa: int) -> int:
    """Assemble a binary64 bit pattern from its three fields.

    ``sign`` is 0 or 1, ``biased_exponent`` is in [0, 2047], ``mantissa`` is
    in [0, 2^52 - 1].
    """
    return (
        ((sign & 1) << 63)
        | ((biased_exponent & 0x7FF) << 52)
        | (mantissa & FLOAT64_MANTISSA_MASK)
    )


# Render tables: bit pattern -> Noir library constant name. Only values that
# the Noir library exposes by name are renderable, so callers fall back to a
# hex literal otherwise.
_FLOAT32_NAMED: dict[int, str] = {
    FLOAT32_ZERO: "FLOAT32_ZERO",
    FLOAT32_NEG_ZERO: "FLOAT32_NEG_ZERO",
    FLOAT32_ONE: "FLOAT32_ONE",
    FLOAT32_NEG_ONE: "FLOAT32_NEG_ONE",
    FLOAT32_INFINITY: "FLOAT32_INFINITY",
    FLOAT32_NEG_INFINITY: "FLOAT32_NEG_INFINITY",
    FLOAT32_NAN: "FLOAT32_NAN",
    FLOAT32_SIGNALING_NAN: "FLOAT32_SIGNALING_NAN",
    FLOAT32_MIN_DENORMAL: "FLOAT32_MIN_DENORMAL",
    FLOAT32_MAX_DENORMAL: "FLOAT32_MAX_DENORMAL",
    FLOAT32_MIN_NORMAL: "FLOAT32_MIN_NORMAL",
    FLOAT32_MAX_NORMAL: "FLOAT32_MAX_NORMAL",
}

_FLOAT64_NAMED: dict[int, str] = {
    FLOAT64_ZERO: "FLOAT64_ZERO",
    FLOAT64_NEG_ZERO: "FLOAT64_NEG_ZERO",
    FLOAT64_ONE: "FLOAT64_ONE",
    FLOAT64_NEG_ONE: "FLOAT64_NEG_ONE",
    FLOAT64_INFINITY: "FLOAT64_INFINITY",
    FLOAT64_NEG_INFINITY: "FLOAT64_NEG_INFINITY",
    FLOAT64_NAN: "FLOAT64_NAN",
    FLOAT64_SIGNALING_NAN: "FLOAT64_SIGNALING_NAN",
    FLOAT64_MIN_DENORMAL: "FLOAT64_MIN_DENORMAL",
    FLOAT64_MAX_DENORMAL: "FLOAT64_MAX_DENORMAL",
    FLOAT64_MIN_NORMAL: "FLOAT64_MIN_NORMAL",
    FLOAT64_MAX_NORMAL: "FLOAT64_MAX_NORMAL",
}


def render_special_or_hex(bits: int, *, is_float32: bool) -> str:
    """Render a bit pattern as the Noir library constant name when one matches.

    Falls back to a zero-padded hex literal of the appropriate width.
    """
    table = _FLOAT32_NAMED if is_float32 else _FLOAT64_NAMED
    name = table.get(bits)
    if name is not None:
        return name
    width = 8 if is_float32 else 16
    return f"0x{bits:0{width}X}"


def named_constant(bits: int, *, is_float32: bool) -> str | None:
    """Return the Noir library constant name for ``bits``, or ``None``."""
    table = _FLOAT32_NAMED if is_float32 else _FLOAT64_NAMED
    return table.get(bits)
