// Spot tests for the reference IEEE 754 add. These are the round-1
// bit-for-bit equivalence smoke checks runnable from `nargo test`. The
// MPFR-against-reference loop tracked in
// `scripts/test_reference_equivalence.py` is currently a smoke-check on
// the MPFR oracle only; the full reference-vs-MPFR sweep is gated by a
// follow-up PR (see `noir/lib/reference/README.md`).

use ieee754::float32::{add_float32_with_rounding, float32_from_bits, float32_to_bits};
use ieee754::types::{
    ROUNDING_MODE_NEAREST_AWAY, ROUNDING_MODE_NEAREST_EVEN, ROUNDING_MODE_TOWARD_NEGATIVE,
    ROUNDING_MODE_TOWARD_POSITIVE, ROUNDING_MODE_TOWARD_ZERO,
};
use ieee754_reference::add_f32_reference;

fn main() {}

fn assert_match(a_bits: u32, b_bits: u32, mode: u8) {
    let a = float32_from_bits(a_bits);
    let b = float32_from_bits(b_bits);
    let opt = add_float32_with_rounding(a, b, mode);
    let refr = add_f32_reference(a, b, mode);
    assert(float32_to_bits(opt) == float32_to_bits(refr));
}

#[test]
fn ref_eq_one_plus_two_rne() {
    assert_match(0x3F800000, 0x40000000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_pos_zero_plus_pos_zero() {
    assert_match(0x00000000, 0x00000000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_pos_zero_plus_neg_zero_default() {
    // sec 6.3: +0 + -0 -> +0 under RNE.
    assert_match(0x00000000, 0x80000000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_pos_zero_plus_neg_zero_rndd() {
    // sec 6.3: +0 + -0 -> -0 under roundTowardNegative.
    assert_match(0x00000000, 0x80000000, ROUNDING_MODE_TOWARD_NEGATIVE);
}

#[test]
fn ref_eq_inf_minus_inf_is_nan() {
    // sec 6.1: +Inf + -Inf is invalid -> NaN.
    assert_match(0x7F800000, 0xFF800000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_nan_propagates() {
    assert_match(0x7FC00000, 0x3F800000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_smallest_denorms() {
    assert_match(0x00000001, 0x00000001, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_max_plus_max_overflow_rne() {
    // max_f32 + max_f32 -> +Inf under RNE.
    assert_match(0x7F7FFFFF, 0x7F7FFFFF, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_max_plus_max_overflow_rndz() {
    // max_f32 + max_f32 -> +max under roundTowardZero.
    assert_match(0x7F7FFFFF, 0x7F7FFFFF, ROUNDING_MODE_TOWARD_ZERO);
}

#[test]
fn ref_eq_halfway_tie_rne() {
    // 1 + 2^-24: halfway tie. RNE -> 0x3F800000; RTA -> 0x3F800001.
    assert_match(0x3F800000, 0x33800000, ROUNDING_MODE_NEAREST_EVEN);
}

#[test]
fn ref_eq_halfway_tie_rta() {
    assert_match(0x3F800000, 0x33800000, ROUNDING_MODE_NEAREST_AWAY);
}

#[test]
fn ref_eq_halfway_tie_rndu() {
    assert_match(0x3F800000, 0x33800000, ROUNDING_MODE_TOWARD_POSITIVE);
}

#[test]
fn ref_eq_cancellation_to_zero() {
    // 1.0 + (-1.0) = +0 under default modes; -0 under roundTowardNegative.
    assert_match(0x3F800000, 0xBF800000, ROUNDING_MODE_NEAREST_EVEN);
    assert_match(0x3F800000, 0xBF800000, ROUNDING_MODE_TOWARD_NEGATIVE);
}
