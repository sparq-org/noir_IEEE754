// ============================================================================
// IEEE 754 Float64 Integer Conversion Tests
// ============================================================================

use ieee754::float::{
    float64_from_bits, float64_from_u32, float64_from_u64, float64_to_bits, float64_to_u32,
    float64_to_u64, float64_zero,
};

// ============================================================================
// Float64 from u32 Tests
// ============================================================================

#[test]
fn test_float64_from_u32_zero() {
    let result = float64_from_u32(0);
    assert(float64_to_bits(result) == 0x0000000000000000);
}

#[test]
fn test_float64_from_u32_one() {
    // 1u32 -> 1.0f64 = 0x3FF0000000000000
    let result = float64_from_u32(1);
    assert(float64_to_bits(result) == 0x3FF0000000000000);
}

#[test]
fn test_float64_from_u32_two() {
    // 2u32 -> 2.0f64 = 0x4000000000000000
    let result = float64_from_u32(2);
    assert(float64_to_bits(result) == 0x4000000000000000);
}

#[test]
fn test_float64_from_u32_power_of_two() {
    // 16u32 -> 16.0f64 = 0x4030000000000000
    let result = float64_from_u32(16);
    assert(float64_to_bits(result) == 0x4030000000000000);
}

#[test]
fn test_float64_from_u32_large() {
    // 1000u32 -> 1000.0f64 = 0x408F400000000000
    let result = float64_from_u32(1000);
    assert(float64_to_bits(result) == 0x408F400000000000);
}

#[test]
fn test_float64_from_u32_max() {
    // 0xFFFFFFFF (4294967295) -> 0x41EFFFFFFFE00000
    let result = float64_from_u32(0xFFFFFFFF);
    assert(float64_to_bits(result) == 0x41EFFFFFFFE00000);
}

// ============================================================================
// Float64 from u64 Tests
// ============================================================================

#[test]
fn test_float64_from_u64_zero() {
    let result = float64_from_u64(0);
    assert(float64_to_bits(result) == 0x0000000000000000);
}

#[test]
fn test_float64_from_u64_one() {
    let result = float64_from_u64(1);
    assert(float64_to_bits(result) == 0x3FF0000000000000);
}

#[test]
fn test_float64_from_u64_large() {
    // 1000u64 -> 1000.0f64
    let result = float64_from_u64(1000);
    assert(float64_to_bits(result) == 0x408F400000000000);
}

// ============================================================================
// Float64 to u32 Tests
// ============================================================================

#[test]
fn test_float64_to_u32_zero() {
    let f = float64_zero(0);
    let result = float64_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float64_to_u32_one() {
    // 1.0f64 -> 1u32
    let f = float64_from_bits(0x3FF0000000000000);
    let result = float64_to_u32(f);
    assert(result == 1);
}

#[test]
fn test_float64_to_u32_two() {
    // 2.0f64 -> 2u32
    let f = float64_from_bits(0x4000000000000000);
    let result = float64_to_u32(f);
    assert(result == 2);
}

#[test]
fn test_float64_to_u32_truncate() {
    // 2.7f64 -> 2u32 (truncate)
    let f = float64_from_bits(0x4005999999999999); // ~2.7
    let result = float64_to_u32(f);
    assert(result == 2);
}

#[test]
fn test_float64_to_u32_large() {
    // 1000.0f64 -> 1000u32
    let f = float64_from_bits(0x408F400000000000);
    let result = float64_to_u32(f);
    assert(result == 1000);
}

#[test]
fn test_float64_to_u32_negative() {
    // -5.0f64 -> 0u32 (negative values become 0)
    let f = float64_from_bits(0xC014000000000000);
    let result = float64_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float64_to_u32_infinity() {
    // +Inf -> max u32
    let f = float64_from_bits(0x7FF0000000000000);
    let result = float64_to_u32(f);
    assert(result == 0xFFFFFFFF);

    // -Inf -> 0
    let f_neg = float64_from_bits(0xFFF0000000000000);
    let result_neg = float64_to_u32(f_neg);
    assert(result_neg == 0);
}

#[test]
fn test_float64_to_u32_nan() {
    // NaN -> 0
    let f = float64_from_bits(0x7FF8000000000000);
    let result = float64_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float64_to_u32_fractional() {
    // 0.5f64 -> 0u32 (< 1 truncates to 0)
    let f = float64_from_bits(0x3FE0000000000000);
    let result = float64_to_u32(f);
    assert(result == 0);
}

// ============================================================================
// Float64 to u64 Tests
// ============================================================================

#[test]
fn test_float64_to_u64_zero() {
    let f = float64_zero(0);
    let result = float64_to_u64(f);
    assert(result == 0);
}

#[test]
fn test_float64_to_u64_one() {
    let f = float64_from_bits(0x3FF0000000000000);
    let result = float64_to_u64(f);
    assert(result == 1);
}

#[test]
fn test_float64_to_u64_large() {
    // 1000.0f64 -> 1000u64
    let f = float64_from_bits(0x408F400000000000);
    let result = float64_to_u64(f);
    assert(result == 1000);
}

#[test]
fn test_float64_to_u64_negative() {
    // -5.0f64 -> 0u64
    let f = float64_from_bits(0xC014000000000000);
    let result = float64_to_u64(f);
    assert(result == 0);
}

#[test]
fn test_float64_to_u64_infinity() {
    // +Inf -> max u64
    let f = float64_from_bits(0x7FF0000000000000);
    let result = float64_to_u64(f);
    assert(result == 0xFFFFFFFFFFFFFFFF);
}

// ============================================================================
// Round-trip Tests
// ============================================================================

#[test]
fn test_float64_u32_roundtrip_small() {
    let original: u32 = 42;
    let f = float64_from_u32(original);
    let result = float64_to_u32(f);
    assert(result == original);
}

#[test]
fn test_float64_u32_roundtrip_powers_of_two() {
    let original: u32 = 1024;
    let f = float64_from_u32(original);
    let result = float64_to_u32(f);
    assert(result == original);
}

#[test]
fn test_float64_u32_roundtrip_max() {
    let original: u32 = 0xFFFFFFFF;
    let f = float64_from_u32(original);
    let result = float64_to_u32(f);
    assert(result == original);
}

#[test]
fn test_float64_u64_roundtrip_small() {
    let original: u64 = 42;
    let f = float64_from_u64(original);
    let result = float64_to_u64(f);
    assert(result == original);
}

#[test]
fn test_float64_u64_roundtrip_powers_of_two() {
    let original: u64 = 1024;
    let f = float64_from_u64(original);
    let result = float64_to_u64(f);
    assert(result == original);
}
