// ============================================================================
// IEEE 754 Float32 Operations Module
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
    float32_from_bits, float32_infinity, float32_is_denormal, float32_is_infinity, float32_is_nan,
    float32_is_zero, float32_max_finite, float32_nan, float32_to_bits, float32_zero,
};

pub use add::{add_float32, add_float32_with_rounding};
pub use cmp::{
    float32_compare, float32_eq, float32_ge, float32_gt, float32_le, float32_lt, float32_ne,
    float32_unordered,
};
pub use convert::{
    float32_from_field, float32_from_u32, float32_from_u64, float32_to_field, float32_to_u32,
    float32_to_u64,
};
pub use div::{div_float32, div_float32_with_rounding};
pub use mul::{mul_float32, mul_float32_with_rounding};
pub use sqrt::{sqrt_float32, sqrt_float32_with_rounding};

// Subtraction is implemented as a + (-b)
use crate::types::{IEEE754Float32, ROUNDING_MODE_NEAREST_EVEN};

// IEEE 754 compliant subtraction for 32-bit floats with rounding mode
// Implemented as a + (-b).
//
// ----------------------------------------------------------------------------
// Lean equivalence proof (round 7a). See `circuits/lampe-literate` for the
// build tool that resolves the LAMPE-LITERATE directives below, splices the
// referenced proof fragments into a generated Lean module, and runs `lake
// build` against the workspace's shared `Models.lean` / `Subterms.lean`.
// Generated `.lean` files land in a gitignored scratch dir; only this Noir
// source plus the literate splice-fragment `.lean` files are version-
// controlled. Note: the `.lean` files referenced below are splice fragments,
// not standalone Lean modules -- the namespace opens in the preamble fragment
// and closes in the equivalence fragment, so each file is invalid in
// isolation but balances after the build tool concatenates them. The proof
// fragment inlines round-6 `add_f32_equivalence` (as `private`) because IEEE
// 754-2019 sec 6.3 reduces sub to add(a, negate(b)); the splice tree for
// this `.nr` is disjoint from `add.nr`'s, so the duplication never collides.
// ----------------------------------------------------------------------------
//
// LAMPE-LITERATE preamble: ../../proofs/sub_f32_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/sub_f32_equivalence.lean fn=sub_float32_with_rounding name=sub_f32_equivalence
pub fn sub_float32_with_rounding(
    a: IEEE754Float32,
    b: IEEE754Float32,
    rounding_mode: u8,
) -> IEEE754Float32 {
    // Negate b's sign and add
    let neg_b = IEEE754Float32 { sign: 1 - b.sign, exponent: b.exponent, mantissa: b.mantissa };
    add_float32_with_rounding(a, neg_b, rounding_mode)
}

// IEEE 754 compliant subtraction for 32-bit floats (default rounding mode)
// Backward-compatible wrapper that uses round-to-nearest-ties-to-even
pub fn sub_float32(a: IEEE754Float32, b: IEEE754Float32) -> IEEE754Float32 {
    sub_float32_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN)
}

// IEEE 754 compliant absolute value for 32-bit floats
// Returns the magnitude of the float (sign bit set to 0)
// Note: abs(NaN) returns NaN (with sign bit cleared)
pub fn abs_float32(a: IEEE754Float32) -> IEEE754Float32 {
    IEEE754Float32 { sign: 0, exponent: a.exponent, mantissa: a.mantissa }
}
