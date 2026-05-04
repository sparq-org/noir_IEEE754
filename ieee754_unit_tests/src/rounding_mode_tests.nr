// ============================================================================
// IEEE 754 Rounding-Mode Boundary Tests
// ============================================================================
//
// These tests cover two correctness gaps surfaced by Copilot's review of
// PR #50 (`fix(circuits): directed-rounding bug classes`):
//
//   1. **Mixed-zero cancellation** -- per IEEE 754-2019 sec 6.3, the sum of
//      two zero operands of opposite sign is `+0` under every rounding-
//      direction attribute except roundTowardNegative (RNDD), under which it
//      is `-0`. Like-sign zero sums propagate the operands' shared sign
//      regardless of mode. Subtraction is implemented as `a + (-b)`, so the
//      mixed-zero subtract cases (`(+0) - (+0)`, `(-0) - (-0)`) become
//      `(+0) + (-0)` and `(-0) + (+0)` respectively and are exercised here
//      via direct add and via sub.
//
//   2. **Out-of-range `rounding_mode`** -- the public `_with_rounding`
//      arithmetic APIs accept the mode as a raw `u8`. The `should_round_up*`
//      helpers fall through to round-to-nearest-even for any value not in
//      `{0, 1, 2, 3, 4}`. Pre-fix this meant a caller passing e.g.
//      `rounding_mode = 17` would silently get RNE semantics. Post-fix every
//      `_with_rounding` entry point asserts the contract via
//      `crate::utils::assert_valid_rounding_mode`. The
//      `should_fail_with` tests below pin that contract.
// ============================================================================

use ieee754::float::{
    add_float32, add_float32_with_rounding, add_float64, add_float64_with_rounding,
    div_float32_with_rounding, div_float64_with_rounding, float32_from_bits, float32_to_bits,
    float32_zero, float64_from_bits, float64_to_bits, float64_zero, mul_float32_with_rounding,
    mul_float64_with_rounding, ROUNDING_MODE_NEAREST_AWAY, ROUNDING_MODE_NEAREST_EVEN,
    ROUNDING_MODE_TOWARD_NEGATIVE, ROUNDING_MODE_TOWARD_POSITIVE, ROUNDING_MODE_TOWARD_ZERO,
    sqrt_float32_with_rounding, sqrt_float64_with_rounding, sub_float32, sub_float32_with_rounding,
    sub_float64, sub_float64_with_rounding,
};

// ----------------------------------------------------------------------------
// Float32 mixed-zero cancellation across all five rounding modes
// ----------------------------------------------------------------------------
//
// Reference (computed via MPFR `mpfr_add` with binary32 precision and the
// matching `mpfr_rnd_t`):
//
// +0 + -0       -> +0 under RNE, RNA, RNDU, RNDZ;  -0 under RNDD
// -0 + +0       -> +0 under RNE, RNA, RNDU, RNDZ;  -0 under RNDD
// +0 + +0       -> +0 under all five
// -0 + -0       -> -0 under all five
// (+0) - (-0)   -> +0 + +0 -> +0 under all five
// (-0) - (+0)   -> -0 + -0 -> -0 under all five
// (+0) - (+0)   -> +0 + -0 -> as mixed-zero above
// (-0) - (-0)   -> -0 + +0 -> as mixed-zero above

#[test]
fn test_float32_mixed_zero_add_rne() {
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    assert(float32_to_bits(add_float32(pos, neg)) == 0x00000000);
    assert(float32_to_bits(add_float32(neg, pos)) == 0x00000000);
}

#[test]
fn test_float32_mixed_zero_add_explicit_rne() {
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    let r1 = add_float32_with_rounding(pos, neg, ROUNDING_MODE_NEAREST_EVEN);
    let r2 = add_float32_with_rounding(neg, pos, ROUNDING_MODE_NEAREST_EVEN);
    assert(float32_to_bits(r1) == 0x00000000);
    assert(float32_to_bits(r2) == 0x00000000);
}

#[test]
fn test_float32_mixed_zero_add_rna() {
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    let r1 = add_float32_with_rounding(pos, neg, ROUNDING_MODE_NEAREST_AWAY);
    let r2 = add_float32_with_rounding(neg, pos, ROUNDING_MODE_NEAREST_AWAY);
    assert(float32_to_bits(r1) == 0x00000000);
    assert(float32_to_bits(r2) == 0x00000000);
}

#[test]
fn test_float32_mixed_zero_add_rndu() {
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    let r1 = add_float32_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_POSITIVE);
    let r2 = add_float32_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_POSITIVE);
    assert(float32_to_bits(r1) == 0x00000000);
    assert(float32_to_bits(r2) == 0x00000000);
}

#[test]
fn test_float32_mixed_zero_add_rndd() {
    // The only rounding mode under which `+0 + -0 = -0` per IEEE 754-2019
    // sec 6.3.
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    let r1 = add_float32_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_NEGATIVE);
    let r2 = add_float32_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float32_to_bits(r1) == 0x80000000);
    assert(float32_to_bits(r2) == 0x80000000);
}

#[test]
fn test_float32_mixed_zero_add_rndz() {
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    let r1 = add_float32_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_ZERO);
    let r2 = add_float32_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_ZERO);
    assert(float32_to_bits(r1) == 0x00000000);
    assert(float32_to_bits(r2) == 0x00000000);
}

#[test]
fn test_float32_like_sign_zero_add_all_modes() {
    // Like-sign zero sums propagate the shared sign in all modes.
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    for mode in 0..5 {
        let m = mode as u8;
        assert(float32_to_bits(add_float32_with_rounding(pos, pos, m)) == 0x00000000);
        assert(float32_to_bits(add_float32_with_rounding(neg, neg, m)) == 0x80000000);
    }
}

// ----------------------------------------------------------------------------
// Float32 mixed-zero via subtraction (a + (-b))
// ----------------------------------------------------------------------------

#[test]
fn test_float32_zero_minus_zero_rndd() {
    // (+0) - (+0) = +0 + (-0) = -0 under RNDD; +0 elsewhere.
    let pos = float32_zero(0);
    let r_default = sub_float32(pos, pos);
    assert(float32_to_bits(r_default) == 0x00000000);
    let r_rndd = sub_float32_with_rounding(pos, pos, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float32_to_bits(r_rndd) == 0x80000000);
}

#[test]
fn test_float32_neg_zero_minus_neg_zero_rndd() {
    // (-0) - (-0) = -0 + (+0) = -0 under RNDD; +0 elsewhere.
    let neg = float32_zero(1);
    let r_default = sub_float32(neg, neg);
    assert(float32_to_bits(r_default) == 0x00000000);
    let r_rndd = sub_float32_with_rounding(neg, neg, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float32_to_bits(r_rndd) == 0x80000000);
}

#[test]
fn test_float32_pos_zero_minus_neg_zero_all_modes() {
    // (+0) - (-0) = +0 + (+0) = +0 under all five modes.
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    for mode in 0..5 {
        let m = mode as u8;
        let r = sub_float32_with_rounding(pos, neg, m);
        assert(float32_to_bits(r) == 0x00000000);
    }
}

#[test]
fn test_float32_neg_zero_minus_pos_zero_all_modes() {
    // (-0) - (+0) = -0 + (-0) = -0 under all five modes.
    let pos = float32_zero(0);
    let neg = float32_zero(1);
    for mode in 0..5 {
        let m = mode as u8;
        let r = sub_float32_with_rounding(neg, pos, m);
        assert(float32_to_bits(r) == 0x80000000);
    }
}

// ----------------------------------------------------------------------------
// Float32 exact cancellation of equal-magnitude opposite-sign non-zero operands
// ----------------------------------------------------------------------------

#[test]
fn test_float32_exact_cancellation_rndd() {
    // 1.0 + (-1.0) = -0 under RNDD; +0 under every other mode.
    let one = float32_from_bits(0x3F800000);
    let neg_one = float32_from_bits(0xBF800000);
    let r_default = add_float32(one, neg_one);
    assert(float32_to_bits(r_default) == 0x00000000);
    let r_rndd = add_float32_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float32_to_bits(r_rndd) == 0x80000000);
    let r_rne = add_float32_with_rounding(one, neg_one, ROUNDING_MODE_NEAREST_EVEN);
    assert(float32_to_bits(r_rne) == 0x00000000);
    let r_rndu = add_float32_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_POSITIVE);
    assert(float32_to_bits(r_rndu) == 0x00000000);
    let r_rndz = add_float32_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_ZERO);
    assert(float32_to_bits(r_rndz) == 0x00000000);
    let r_rna = add_float32_with_rounding(one, neg_one, ROUNDING_MODE_NEAREST_AWAY);
    assert(float32_to_bits(r_rna) == 0x00000000);
}

// ----------------------------------------------------------------------------
// Float64 mixed-zero cancellation across all five rounding modes
// ----------------------------------------------------------------------------

#[test]
fn test_float64_mixed_zero_add_rne() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    assert(float64_to_bits(add_float64(pos, neg)) == 0x0000000000000000);
    assert(float64_to_bits(add_float64(neg, pos)) == 0x0000000000000000);
}

#[test]
fn test_float64_mixed_zero_add_rna() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    let r1 = add_float64_with_rounding(pos, neg, ROUNDING_MODE_NEAREST_AWAY);
    let r2 = add_float64_with_rounding(neg, pos, ROUNDING_MODE_NEAREST_AWAY);
    assert(float64_to_bits(r1) == 0x0000000000000000);
    assert(float64_to_bits(r2) == 0x0000000000000000);
}

#[test]
fn test_float64_mixed_zero_add_rndu() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    let r1 = add_float64_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_POSITIVE);
    let r2 = add_float64_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_POSITIVE);
    assert(float64_to_bits(r1) == 0x0000000000000000);
    assert(float64_to_bits(r2) == 0x0000000000000000);
}

#[test]
fn test_float64_mixed_zero_add_rndd() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    let r1 = add_float64_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_NEGATIVE);
    let r2 = add_float64_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float64_to_bits(r1) == 0x8000000000000000);
    assert(float64_to_bits(r2) == 0x8000000000000000);
}

#[test]
fn test_float64_mixed_zero_add_rndz() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    let r1 = add_float64_with_rounding(pos, neg, ROUNDING_MODE_TOWARD_ZERO);
    let r2 = add_float64_with_rounding(neg, pos, ROUNDING_MODE_TOWARD_ZERO);
    assert(float64_to_bits(r1) == 0x0000000000000000);
    assert(float64_to_bits(r2) == 0x0000000000000000);
}

#[test]
fn test_float64_like_sign_zero_add_all_modes() {
    let pos = float64_zero(0);
    let neg = float64_zero(1);
    for mode in 0..5 {
        let m = mode as u8;
        assert(float64_to_bits(add_float64_with_rounding(pos, pos, m)) == 0x0000000000000000);
        assert(float64_to_bits(add_float64_with_rounding(neg, neg, m)) == 0x8000000000000000);
    }
}

// ----------------------------------------------------------------------------
// Float64 mixed-zero via subtraction
// ----------------------------------------------------------------------------

#[test]
fn test_float64_zero_minus_zero_rndd() {
    let pos = float64_zero(0);
    let r_default = sub_float64(pos, pos);
    assert(float64_to_bits(r_default) == 0x0000000000000000);
    let r_rndd = sub_float64_with_rounding(pos, pos, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float64_to_bits(r_rndd) == 0x8000000000000000);
}

#[test]
fn test_float64_neg_zero_minus_neg_zero_rndd() {
    let neg = float64_zero(1);
    let r_default = sub_float64(neg, neg);
    assert(float64_to_bits(r_default) == 0x0000000000000000);
    let r_rndd = sub_float64_with_rounding(neg, neg, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float64_to_bits(r_rndd) == 0x8000000000000000);
}

#[test]
fn test_float64_exact_cancellation_rndd() {
    // 1.0 + (-1.0) = -0 under RNDD; +0 under every other mode.
    let one = float64_from_bits(0x3FF0000000000000);
    let neg_one = float64_from_bits(0xBFF0000000000000);
    let r_default = add_float64(one, neg_one);
    assert(float64_to_bits(r_default) == 0x0000000000000000);
    let r_rndd = add_float64_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_NEGATIVE);
    assert(float64_to_bits(r_rndd) == 0x8000000000000000);
    let r_rne = add_float64_with_rounding(one, neg_one, ROUNDING_MODE_NEAREST_EVEN);
    assert(float64_to_bits(r_rne) == 0x0000000000000000);
    let r_rndu = add_float64_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_POSITIVE);
    assert(float64_to_bits(r_rndu) == 0x0000000000000000);
    let r_rndz = add_float64_with_rounding(one, neg_one, ROUNDING_MODE_TOWARD_ZERO);
    assert(float64_to_bits(r_rndz) == 0x0000000000000000);
    let r_rna = add_float64_with_rounding(one, neg_one, ROUNDING_MODE_NEAREST_AWAY);
    assert(float64_to_bits(r_rna) == 0x0000000000000000);
}

// ----------------------------------------------------------------------------
// Out-of-range rounding-mode assertions
// ----------------------------------------------------------------------------
//
// `nargo test` runs `#[test]` functions with `should_fail`/
// `should_fail_with` annotations to assert that an expected assertion does
// fire. The contract is "rounding_mode in 0..=4"; any other value must abort
// the operation rather than silently fall through to RNE.

#[test(should_fail_with = "rounding_mode")]
fn test_float32_add_rounding_mode_out_of_range_5() {
    let one = float32_from_bits(0x3F800000);
    let _ = add_float32_with_rounding(one, one, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float32_add_rounding_mode_out_of_range_17() {
    let one = float32_from_bits(0x3F800000);
    let _ = add_float32_with_rounding(one, one, 17);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float32_add_rounding_mode_out_of_range_255() {
    let one = float32_from_bits(0x3F800000);
    let _ = add_float32_with_rounding(one, one, 255);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_add_rounding_mode_out_of_range_5() {
    let one = float64_from_bits(0x3FF0000000000000);
    let _ = add_float64_with_rounding(one, one, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_add_rounding_mode_out_of_range_42() {
    let one = float64_from_bits(0x3FF0000000000000);
    let _ = add_float64_with_rounding(one, one, 42);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float32_sub_rounding_mode_out_of_range() {
    // sub_float32_with_rounding inherits validation from add_float32_with_rounding.
    let one = float32_from_bits(0x3F800000);
    let _ = sub_float32_with_rounding(one, one, 9);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_sub_rounding_mode_out_of_range() {
    let one = float64_from_bits(0x3FF0000000000000);
    let _ = sub_float64_with_rounding(one, one, 200);
}

// ----------------------------------------------------------------------------
// Out-of-range assertions for mul / div / sqrt
// ----------------------------------------------------------------------------

#[test(should_fail_with = "rounding_mode")]
fn test_float32_mul_rounding_mode_out_of_range() {
    let two = float32_from_bits(0x40000000);
    let _ = mul_float32_with_rounding(two, two, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_mul_rounding_mode_out_of_range() {
    let two = float64_from_bits(0x4000000000000000);
    let _ = mul_float64_with_rounding(two, two, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float32_div_rounding_mode_out_of_range() {
    let two = float32_from_bits(0x40000000);
    let _ = div_float32_with_rounding(two, two, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_div_rounding_mode_out_of_range() {
    let two = float64_from_bits(0x4000000000000000);
    let _ = div_float64_with_rounding(two, two, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float32_sqrt_rounding_mode_out_of_range() {
    let four = float32_from_bits(0x40800000);
    let _ = sqrt_float32_with_rounding(four, 5);
}

#[test(should_fail_with = "rounding_mode")]
fn test_float64_sqrt_rounding_mode_out_of_range() {
    let four = float64_from_bits(0x4010000000000000);
    let _ = sqrt_float64_with_rounding(four, 5);
}

// ----------------------------------------------------------------------------
// Boundary check: every documented mode is accepted
// ----------------------------------------------------------------------------

#[test]
fn test_float32_add_accepts_all_documented_modes() {
    let one = float32_from_bits(0x3F800000);
    // No assertion fails; result is some legitimate bit pattern.
    let _ = add_float32_with_rounding(one, one, ROUNDING_MODE_NEAREST_EVEN);
    let _ = add_float32_with_rounding(one, one, ROUNDING_MODE_NEAREST_AWAY);
    let _ = add_float32_with_rounding(one, one, ROUNDING_MODE_TOWARD_POSITIVE);
    let _ = add_float32_with_rounding(one, one, ROUNDING_MODE_TOWARD_NEGATIVE);
    let _ = add_float32_with_rounding(one, one, ROUNDING_MODE_TOWARD_ZERO);
}

#[test]
fn test_float64_add_accepts_all_documented_modes() {
    let one = float64_from_bits(0x3FF0000000000000);
    let _ = add_float64_with_rounding(one, one, ROUNDING_MODE_NEAREST_EVEN);
    let _ = add_float64_with_rounding(one, one, ROUNDING_MODE_NEAREST_AWAY);
    let _ = add_float64_with_rounding(one, one, ROUNDING_MODE_TOWARD_POSITIVE);
    let _ = add_float64_with_rounding(one, one, ROUNDING_MODE_TOWARD_NEGATIVE);
    let _ = add_float64_with_rounding(one, one, ROUNDING_MODE_TOWARD_ZERO);
}
