// ============================================================================
// IEEE 754 Float64 Unit Tests
// ============================================================================

use ieee754::float::{
    add_float64, div_float64, float64_from_bits, float64_infinity, float64_is_infinity,
    float64_is_nan, float64_is_zero, float64_nan, float64_to_bits, float64_zero, mul_float64,
    sub_float64, abs_float64,
    // Comparison operations
    float64_eq, float64_ne, float64_lt, float64_le, float64_gt, float64_ge, float64_unordered,
    float64_compare,
    // Square root
    sqrt_float64,
};

// ============================================================================
// Float64 Conversion Tests
// ============================================================================

#[test]
fn test_float64_from_to_bits() {
    // Test 1.0 = 0x3FF0000000000000
    let one_bits: u64 = 0x3FF0000000000000;
    let one = float64_from_bits(one_bits);
    assert(one.sign == 0);
    assert(one.exponent == 1023);
    assert(one.mantissa == 0);
    assert(float64_to_bits(one) == one_bits);

    // Test -1.0 = 0xBFF0000000000000
    let neg_one_bits: u64 = 0xBFF0000000000000;
    let neg_one = float64_from_bits(neg_one_bits);
    assert(neg_one.sign == 1);
    assert(neg_one.exponent == 1023);
    assert(neg_one.mantissa == 0);
    assert(float64_to_bits(neg_one) == neg_one_bits);
}

#[test]
fn test_float64_special_values() {
    // Test NaN
    let nan = float64_nan();
    assert(float64_is_nan(nan));
    assert(!float64_is_infinity(nan));
    assert(!float64_is_zero(nan));

    // Test Infinity
    let inf = float64_infinity(0);
    assert(!float64_is_nan(inf));
    assert(float64_is_infinity(inf));
    assert(!float64_is_zero(inf));

    // Test Zero
    let zero = float64_zero(0);
    assert(!float64_is_nan(zero));
    assert(!float64_is_infinity(zero));
    assert(float64_is_zero(zero));
}

// ============================================================================
// Float64 Addition Tests
// ============================================================================

#[test]
fn test_float64_add_basic() {
    // 1.0 + 1.0 = 2.0
    let one = float64_from_bits(0x3FF0000000000000);
    let result = add_float64(one, one);
    let expected = float64_from_bits(0x4000000000000000); // 2.0
    assert(float64_to_bits(result) == float64_to_bits(expected));
}

#[test]
fn test_float64_add_different_exponents() {
    // 1.0 + 0.5 = 1.5
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let half = float64_from_bits(0x3FE0000000000000); // 0.5
    let result = add_float64(one, half);
    let expected = float64_from_bits(0x3FF8000000000000); // 1.5
    assert(float64_to_bits(result) == float64_to_bits(expected));
}

#[test]
fn test_float64_add_with_zero() {
    let one = float64_from_bits(0x3FF0000000000000);
    let zero = float64_zero(0);

    // 1.0 + 0.0 = 1.0
    let result = add_float64(one, zero);
    assert(float64_to_bits(result) == 0x3FF0000000000000);

    // 0.0 + 1.0 = 1.0
    let result2 = add_float64(zero, one);
    assert(float64_to_bits(result2) == 0x3FF0000000000000);
}

#[test]
fn test_float64_add_opposite_signs() {
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let neg_one = float64_from_bits(0xBFF0000000000000); // -1.0

    // 1.0 + (-1.0) = 0.0
    let result = add_float64(one, neg_one);
    assert(float64_is_zero(result));
}

#[test]
fn test_float64_add_nan() {
    let nan = float64_nan();
    let one = float64_from_bits(0x3FF0000000000000);

    // NaN + anything = NaN
    let result = add_float64(nan, one);
    assert(float64_is_nan(result));

    // anything + NaN = NaN
    let result2 = add_float64(one, nan);
    assert(float64_is_nan(result2));
}

#[test]
fn test_float64_add_infinity() {
    let inf = float64_infinity(0);
    let neg_inf = float64_infinity(1);
    let one = float64_from_bits(0x3FF0000000000000);

    // Inf + 1.0 = Inf
    let result = add_float64(inf, one);
    assert(float64_is_infinity(result));
    assert(result.sign == 0);

    // Inf + Inf = Inf
    let result2 = add_float64(inf, inf);
    assert(float64_is_infinity(result2));

    // Inf + (-Inf) = NaN
    let result3 = add_float64(inf, neg_inf);
    assert(float64_is_nan(result3));
}

// ============================================================================
// Float64 Subtraction Tests
// ============================================================================

#[test]
fn test_float64_sub_basic() {
    // 3.0 - 2.0 = 1.0
    let three = float64_from_bits(0x4008000000000000); // 3.0
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let result = sub_float64(three, two);
    assert(float64_to_bits(result) == 0x3FF0000000000000); // 1.0
}

// ============================================================================
// Float64 Multiplication Tests
// ============================================================================

#[test]
fn test_float64_mul_basic() {
    // 2.0 * 3.0 = 6.0
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let three = float64_from_bits(0x4008000000000000); // 3.0
    let result = mul_float64(two, three);
    assert(float64_to_bits(result) == 0x4018000000000000); // 6.0
}

// ============================================================================
// Float64 Division Tests
// ============================================================================

#[test]
fn test_float64_div_basic() {
    // 6.0 / 2.0 = 3.0
    let six = float64_from_bits(0x4018000000000000); // 6.0
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let result = div_float64(six, two);
    assert(float64_to_bits(result) == 0x4008000000000000); // 3.0
}

// ============================================================================
// Float64 Comparison Tests
// ============================================================================

#[test]
fn test_float64_eq_basic() {
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let one_copy = float64_from_bits(0x3FF0000000000000); // 1.0

    // 1.0 == 1.0
    assert(float64_eq(one, one_copy));

    // 1.0 != 2.0
    assert(!float64_eq(one, two));
}

#[test]
fn test_float64_eq_zeros() {
    let pos_zero = float64_zero(0);
    let neg_zero = float64_zero(1);

    // +0 == -0
    assert(float64_eq(pos_zero, neg_zero));
    assert(float64_eq(neg_zero, pos_zero));
}

#[test]
fn test_float64_eq_nan() {
    let nan = float64_nan();
    let one = float64_from_bits(0x3FF0000000000000);

    // NaN != NaN
    assert(!float64_eq(nan, nan));

    // NaN != 1.0
    assert(!float64_eq(nan, one));
    assert(!float64_eq(one, nan));
}

#[test]
fn test_float64_ne_basic() {
    let one = float64_from_bits(0x3FF0000000000000);
    let two = float64_from_bits(0x4000000000000000);

    assert(float64_ne(one, two));
    assert(!float64_ne(one, one));
}

#[test]
fn test_float64_lt_basic() {
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let neg_one = float64_from_bits(0xBFF0000000000000); // -1.0

    // 1.0 < 2.0
    assert(float64_lt(one, two));

    // 2.0 is not < 1.0
    assert(!float64_lt(two, one));

    // 1.0 is not < 1.0
    assert(!float64_lt(one, one));

    // -1.0 < 1.0
    assert(float64_lt(neg_one, one));

    // 1.0 is not < -1.0
    assert(!float64_lt(one, neg_one));
}

#[test]
fn test_float64_lt_zeros() {
    let pos_zero = float64_zero(0);
    let neg_zero = float64_zero(1);

    // +0 is not < -0 (they are equal)
    assert(!float64_lt(pos_zero, neg_zero));
    assert(!float64_lt(neg_zero, pos_zero));
}

#[test]
fn test_float64_lt_infinity() {
    let inf = float64_infinity(0);
    let neg_inf = float64_infinity(1);
    let one = float64_from_bits(0x3FF0000000000000);

    // 1.0 < Inf
    assert(float64_lt(one, inf));

    // -Inf < 1.0
    assert(float64_lt(neg_inf, one));

    // -Inf < Inf
    assert(float64_lt(neg_inf, inf));

    // Inf is not < 1.0
    assert(!float64_lt(inf, one));
}

#[test]
fn test_float64_lt_nan() {
    let nan = float64_nan();
    let one = float64_from_bits(0x3FF0000000000000);

    // NaN comparisons are always false
    assert(!float64_lt(nan, one));
    assert(!float64_lt(one, nan));
    assert(!float64_lt(nan, nan));
}

#[test]
fn test_float64_le_basic() {
    let one = float64_from_bits(0x3FF0000000000000);
    let two = float64_from_bits(0x4000000000000000);

    // 1.0 <= 2.0
    assert(float64_le(one, two));

    // 1.0 <= 1.0
    assert(float64_le(one, one));

    // 2.0 is not <= 1.0
    assert(!float64_le(two, one));
}

#[test]
fn test_float64_gt_basic() {
    let one = float64_from_bits(0x3FF0000000000000);
    let two = float64_from_bits(0x4000000000000000);

    // 2.0 > 1.0
    assert(float64_gt(two, one));

    // 1.0 is not > 2.0
    assert(!float64_gt(one, two));

    // 1.0 is not > 1.0
    assert(!float64_gt(one, one));
}

#[test]
fn test_float64_ge_basic() {
    let one = float64_from_bits(0x3FF0000000000000);
    let two = float64_from_bits(0x4000000000000000);

    // 2.0 >= 1.0
    assert(float64_ge(two, one));

    // 1.0 >= 1.0
    assert(float64_ge(one, one));

    // 1.0 is not >= 2.0
    assert(!float64_ge(one, two));
}

#[test]
fn test_float64_unordered() {
    let nan = float64_nan();
    let one = float64_from_bits(0x3FF0000000000000);

    // NaN makes comparison unordered
    assert(float64_unordered(nan, one));
    assert(float64_unordered(one, nan));
    assert(float64_unordered(nan, nan));

    // No NaN means ordered
    assert(!float64_unordered(one, one));
}

#[test]
fn test_float64_compare_basic() {
    let one = float64_from_bits(0x3FF0000000000000);
    let two = float64_from_bits(0x4000000000000000);

    // 1.0 < 2.0 -> -1
    assert(float64_compare(one, two) == -1);

    // 2.0 > 1.0 -> 1
    assert(float64_compare(two, one) == 1);

    // 1.0 == 1.0 -> 0
    assert(float64_compare(one, one) == 0);
}

#[test]
fn test_float64_compare_nan() {
    let nan = float64_nan();
    let neg_nan =
        ieee754::float::IEEE754Float64 { sign: 1, exponent: 2047, mantissa: 0x8000000000000 };
    let one = float64_from_bits(0x3FF0000000000000);

    // +NaN > everything
    assert(float64_compare(nan, one) == 1);

    // -NaN < everything
    assert(float64_compare(neg_nan, one) == -1);

    // everything < +NaN
    assert(float64_compare(one, nan) == -1);

    // everything > -NaN
    assert(float64_compare(one, neg_nan) == 1);
}

// ============================================================================
// Float64 Square Root Tests
// ============================================================================

#[test]
fn test_float64_sqrt_basic() {
    // sqrt(4.0) = 2.0
    let four = float64_from_bits(0x4010000000000000); // 4.0
    let result = sqrt_float64(four);
    assert(float64_to_bits(result) == 0x4000000000000000); // 2.0
}

#[test]
fn test_float64_sqrt_one() {
    // sqrt(1.0) = 1.0
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let result = sqrt_float64(one);
    assert(float64_to_bits(result) == 0x3FF0000000000000); // 1.0
}

#[test]
fn test_float64_sqrt_two() {
    // sqrt(2.0) = ~1.4142135623730951
    let two = float64_from_bits(0x4000000000000000); // 2.0
    let result = sqrt_float64(two);
    // Expected: 0x3FF6A09E667F3BCD (1.4142135623730951)
    assert(float64_to_bits(result) == 0x3FF6A09E667F3BCD);
}

#[test]
fn test_float64_sqrt_nine() {
    // sqrt(9.0) = 3.0
    let nine = float64_from_bits(0x4022000000000000); // 9.0
    let result = sqrt_float64(nine);
    assert(float64_to_bits(result) == 0x4008000000000000); // 3.0
}

#[test]
fn test_float64_sqrt_quarter() {
    // sqrt(0.25) = 0.5
    let quarter = float64_from_bits(0x3FD0000000000000); // 0.25
    let result = sqrt_float64(quarter);
    assert(float64_to_bits(result) == 0x3FE0000000000000); // 0.5
}

#[test]
fn test_float64_sqrt_zero() {
    // sqrt(+0) = +0
    let pos_zero = float64_zero(0);
    let result = sqrt_float64(pos_zero);
    assert(float64_is_zero(result));
    assert(result.sign == 0);

    // sqrt(-0) = -0
    let neg_zero = float64_zero(1);
    let result2 = sqrt_float64(neg_zero);
    assert(float64_is_zero(result2));
    assert(result2.sign == 1);
}

#[test]
fn test_float64_sqrt_infinity() {
    // sqrt(+Inf) = +Inf
    let inf = float64_infinity(0);
    let result = sqrt_float64(inf);
    assert(float64_is_infinity(result));
    assert(result.sign == 0);
}

#[test]
fn test_float64_sqrt_negative() {
    // sqrt(negative) = NaN
    let neg_one = float64_from_bits(0xBFF0000000000000); // -1.0
    let result = sqrt_float64(neg_one);
    assert(float64_is_nan(result));

    // sqrt(-Inf) = NaN
    let neg_inf = float64_infinity(1);
    let result2 = sqrt_float64(neg_inf);
    assert(float64_is_nan(result2));
}

#[test]
fn test_float64_sqrt_nan() {
    // sqrt(NaN) = NaN
    let nan = float64_nan();
    let result = sqrt_float64(nan);
    assert(float64_is_nan(result));
}

// ============================================================================
// Float64 Absolute Value Tests
// ============================================================================

#[test]
fn test_float64_abs_positive() {
    // abs(1.0) = 1.0
    let one = float64_from_bits(0x3FF0000000000000); // 1.0
    let result = abs_float64(one);
    assert(float64_to_bits(result) == 0x3FF0000000000000);

    // abs(3.14) = 3.14
    let pi = float64_from_bits(0x40091EB851EB851F); // ~3.14
    let result2 = abs_float64(pi);
    assert(float64_to_bits(result2) == 0x40091EB851EB851F);
}

#[test]
fn test_float64_abs_negative() {
    // abs(-1.0) = 1.0
    let neg_one = float64_from_bits(0xBFF0000000000000); // -1.0
    let result = abs_float64(neg_one);
    assert(float64_to_bits(result) == 0x3FF0000000000000); // 1.0

    // abs(-3.14) = 3.14
    let neg_pi = float64_from_bits(0xC0091EB851EB851F); // ~-3.14
    let result2 = abs_float64(neg_pi);
    assert(float64_to_bits(result2) == 0x40091EB851EB851F); // ~3.14
}

#[test]
fn test_float64_abs_zero() {
    // abs(+0) = +0
    let pos_zero = float64_zero(0);
    let result = abs_float64(pos_zero);
    assert(float64_is_zero(result));
    assert(result.sign == 0);

    // abs(-0) = +0
    let neg_zero = float64_zero(1);
    let result2 = abs_float64(neg_zero);
    assert(float64_is_zero(result2));
    assert(result2.sign == 0);
}

#[test]
fn test_float64_abs_infinity() {
    // abs(+Inf) = +Inf
    let pos_inf = float64_infinity(0);
    let result = abs_float64(pos_inf);
    assert(float64_is_infinity(result));
    assert(result.sign == 0);

    // abs(-Inf) = +Inf
    let neg_inf = float64_infinity(1);
    let result2 = abs_float64(neg_inf);
    assert(float64_is_infinity(result2));
    assert(result2.sign == 0);
}

#[test]
fn test_float64_abs_nan() {
    // abs(NaN) = NaN (with sign bit cleared)
    let nan = float64_nan();
    let result = abs_float64(nan);
    assert(float64_is_nan(result));
    assert(result.sign == 0);
}

// ============================================================================
// Float64 Constant Tests
// ============================================================================

use ieee754::float::{
    FLOAT64_INFINITY, FLOAT64_NAN, FLOAT64_NEG_INFINITY, FLOAT64_NEG_ONE, FLOAT64_NEG_ZERO,
    FLOAT64_ONE, FLOAT64_SIGNALING_NAN, FLOAT64_ZERO, FLOAT64_MIN_DENORMAL, FLOAT64_MAX_DENORMAL,
    add_float64_with_rounding, sub_float64_with_rounding, ROUNDING_MODE_NEAREST_EVEN,
    ROUNDING_MODE_NEAREST_AWAY, ROUNDING_MODE_TOWARD_NEGATIVE, ROUNDING_MODE_TOWARD_POSITIVE,
    ROUNDING_MODE_TOWARD_ZERO,
};

#[test]
fn test_float64_constant_zero() {
    let zero = float64_from_bits(FLOAT64_ZERO);
    assert(float64_is_zero(zero));
    assert(zero.sign == 0);
}

#[test]
fn test_float64_constant_neg_zero() {
    let neg_zero = float64_from_bits(FLOAT64_NEG_ZERO);
    assert(float64_is_zero(neg_zero));
    assert(neg_zero.sign == 1);
}

#[test]
fn test_float64_constant_one() {
    let one = float64_from_bits(FLOAT64_ONE);
    assert(float64_to_bits(one) == 0x3FF0000000000000);
    assert(one.sign == 0);
    assert(one.exponent == 1023);
    assert(one.mantissa == 0);
}

#[test]
fn test_float64_constant_neg_one() {
    let neg_one = float64_from_bits(FLOAT64_NEG_ONE);
    assert(float64_to_bits(neg_one) == 0xBFF0000000000000);
    assert(neg_one.sign == 1);
    assert(neg_one.exponent == 1023);
    assert(neg_one.mantissa == 0);
}

#[test]
fn test_float64_constant_infinity() {
    let inf = float64_from_bits(FLOAT64_INFINITY);
    assert(float64_is_infinity(inf));
    assert(inf.sign == 0);
}

#[test]
fn test_float64_constant_neg_infinity() {
    let neg_inf = float64_from_bits(FLOAT64_NEG_INFINITY);
    assert(float64_is_infinity(neg_inf));
    assert(neg_inf.sign == 1);
}

#[test]
fn test_float64_constant_nan() {
    let nan = float64_from_bits(FLOAT64_NAN);
    assert(float64_is_nan(nan));
    assert(float64_to_bits(nan) == 0x7FF8000000000000);
}

#[test]
fn test_float64_constant_signaling_nan() {
    let snan = float64_from_bits(FLOAT64_SIGNALING_NAN);
    assert(float64_is_nan(snan));
    assert(float64_to_bits(snan) == 0x7FF4000000000000);
}

// ============================================================================
// Float64 denormal-result regression tests
// ============================================================================
//
// The "Denormal result" branch in `add_float64_with_rounding` previously
// applied a stray `result_mant >> 1` whenever it re-encoded an exp 1
// pre-rounding intermediate as a denormal at exp 0. That halved every
// denormal-output sum -- e.g. ``MIN_DENORMAL + MIN_DENORMAL`` returned
// ``0x1`` instead of ``0x2``. Berkeley TestFloat surfaced ~84 f64-add and
// ~124 f64-sub failures across rounding modes; the cases below pin the
// fix in the in-tree unit suite so the regression is caught even when the
// TestFloat corpus is not generated (its build is conditional on the
// ``.testfloat_cache`` directory).

#[test]
fn test_float64_min_denormal_plus_min_denormal() {
    let a = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let b = float64_from_bits(FLOAT64_MIN_DENORMAL);
    assert(float64_to_bits(add_float64(a, b)) == 0x0000000000000002);
}

#[test]
fn test_float64_min_denormal_plus_max_denormal_minus_one() {
    // ``MIN_DENORMAL + (MAX_DENORMAL - 1) = MAX_DENORMAL``.
    let a = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let b = float64_from_bits(0x000FFFFFFFFFFFFE);
    assert(float64_to_bits(add_float64(a, b)) == FLOAT64_MAX_DENORMAL);
}

#[test]
fn test_float64_min_denormal_plus_neg_max_denormal() {
    // Cancellation: MIN_DENORMAL + (-MAX_DENORMAL) = -(MAX_DENORMAL - 1).
    let a = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let b = float64_from_bits(0x800FFFFFFFFFFFFF);
    assert(float64_to_bits(add_float64(a, b)) == 0x800FFFFFFFFFFFFE);
}

#[test]
fn test_float64_min_denormal_plus_neg_min_normal() {
    // Borrow from the smallest normal magnitude into a denormal output.
    let a = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let b = float64_from_bits(0x8010000000000000);
    assert(float64_to_bits(add_float64(a, b)) == 0x800FFFFFFFFFFFFF);
}

#[test]
fn test_float64_max_denormal_plus_neg_min_denormal() {
    let a = float64_from_bits(FLOAT64_MAX_DENORMAL);
    let b = float64_from_bits(0x8000000000000001);
    assert(float64_to_bits(add_float64(a, b)) == 0x000FFFFFFFFFFFFE);
}

#[test]
fn test_float64_max_denormal_minus_max_denormal_minus_one() {
    // Denormal-denormal subtraction yielding ``MIN_DENORMAL``.
    let a = float64_from_bits(FLOAT64_MAX_DENORMAL);
    let b = float64_from_bits(0x000FFFFFFFFFFFFE);
    assert(float64_to_bits(sub_float64(a, b)) == FLOAT64_MIN_DENORMAL);
}

#[test]
fn test_float64_max_denormal_minus_min_normal() {
    // Cancellation through smallest-normal magnitude into a denormal output.
    let a = float64_from_bits(FLOAT64_MAX_DENORMAL);
    let b = float64_from_bits(0x0010000000000000);
    assert(float64_to_bits(sub_float64(a, b)) == 0x8000000000000001);
}

#[test]
fn test_float64_min_denormal_plus_min_denormal_all_modes() {
    let a = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let b = float64_from_bits(FLOAT64_MIN_DENORMAL);
    let r_rne = add_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN);
    let r_rna = add_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_AWAY);
    let r_rndp = add_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_POSITIVE);
    let r_rndn = add_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_NEGATIVE);
    let r_rndz = add_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_ZERO);
    // Exact result; rounding mode must not change the answer.
    assert(float64_to_bits(r_rne) == 0x0000000000000002);
    assert(float64_to_bits(r_rna) == 0x0000000000000002);
    assert(float64_to_bits(r_rndp) == 0x0000000000000002);
    assert(float64_to_bits(r_rndn) == 0x0000000000000002);
    assert(float64_to_bits(r_rndz) == 0x0000000000000002);
}

#[test]
fn test_float64_max_denormal_minus_min_normal_all_modes() {
    let a = float64_from_bits(FLOAT64_MAX_DENORMAL);
    let b = float64_from_bits(0x0010000000000000);
    // Exact -2^-1074 (= -MIN_DENORMAL); rounding mode must not change it.
    let expected: u64 = 0x8000000000000001;
    assert(float64_to_bits(sub_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN)) == expected);
    assert(float64_to_bits(sub_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_AWAY)) == expected);
    assert(
        float64_to_bits(sub_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_POSITIVE)) == expected,
    );
    assert(
        float64_to_bits(sub_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_NEGATIVE)) == expected,
    );
    assert(float64_to_bits(sub_float64_with_rounding(a, b, ROUNDING_MODE_TOWARD_ZERO)) == expected);
}
