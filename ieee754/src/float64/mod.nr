// ============================================================================
// IEEE 754 Float64 Operations Module
// ============================================================================

pub(crate) mod helpers;
pub(crate) mod add;
pub(crate) mod mul;
pub(crate) mod div;
pub(crate) mod cmp;
pub(crate) mod sqrt;
pub(crate) mod convert;

// Re-export all public functions
pub use helpers::{
    float64_from_bits, float64_infinity, float64_is_denormal, float64_is_infinity, float64_is_nan,
    float64_is_zero, float64_nan, float64_to_bits, float64_zero,
};

pub use add::{add_float64, add_float64_with_rounding};
pub use cmp::{
    float64_compare, float64_eq, float64_ge, float64_gt, float64_le, float64_lt, float64_ne,
    float64_unordered,
};
pub use convert::{
    float64_from_field, float64_from_u32, float64_from_u64, float64_to_field, float64_to_u32,
    float64_to_u64,
};
pub use div::{div_float64, div_float64_with_rounding};
pub use mul::{mul_float64, mul_float64_with_rounding};
pub use sqrt::{sqrt_float64, sqrt_float64_with_rounding};

// Subtraction is implemented as a + (-b)
use crate::types::{IEEE754Float64, ROUNDING_MODE_NEAREST_EVEN};

// IEEE 754 compliant subtraction for 64-bit floats with rounding mode
// Implemented as a + (-b).
//
// ----------------------------------------------------------------------------
// Lean equivalence proof (round 8). See `circuits/lampe-literate` for the
// build tool that resolves the LAMPE-LITERATE directives below, splices the
// referenced proof file into a generated Lean module, and runs `lake build`
// against the workspace's shared `ModelsF64.lean` / `SubtermsF64.lean`.
// Generated `.lean` files land in a gitignored scratch dir; only this Noir
// source plus the standalone `.lean` proof files are version-controlled.
// The proof file inlines round-7b `add_f64_equivalence` because IEEE 754-2019
// sec 6.3 reduces sub to add(a, negate(b)); the splice tree for this `.nr`
// is disjoint from `add.nr`'s, so the duplication never collides.
// ----------------------------------------------------------------------------
//
// LAMPE-LITERATE preamble: ../../proofs/sub_f64_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/sub_f64_equivalence.lean fn=sub_float64_with_rounding name=sub_f64_equivalence
pub fn sub_float64_with_rounding(
    a: IEEE754Float64,
    b: IEEE754Float64,
    rounding_mode: u8,
) -> IEEE754Float64 {
    // Negate b's sign and add
    let neg_b = IEEE754Float64 { sign: 1 - b.sign, exponent: b.exponent, mantissa: b.mantissa };
    add_float64_with_rounding(a, neg_b, rounding_mode)
}

// IEEE 754 compliant subtraction for 64-bit floats (default rounding mode)
// Backward-compatible wrapper that uses round-to-nearest-ties-to-even
pub fn sub_float64(a: IEEE754Float64, b: IEEE754Float64) -> IEEE754Float64 {
    sub_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN)
}

// IEEE 754 compliant absolute value for 64-bit floats
// Returns the magnitude of the float (sign bit set to 0)
// Note: abs(NaN) returns NaN (with sign bit cleared)
//
// LAMPE-LITERATE preamble: ../../proofs/abs_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/abs_equivalence.lean fn=abs_float64 name=abs_float64_equivalence
pub fn abs_float64(a: IEEE754Float64) -> IEEE754Float64 {
    IEEE754Float64 { sign: 0, exponent: a.exponent, mantissa: a.mantissa }
}
