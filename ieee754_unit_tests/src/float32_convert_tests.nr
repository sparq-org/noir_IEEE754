// ============================================================================
// IEEE 754 Float32 Integer Conversion Tests
// ============================================================================

use ieee754::float::{
    float32_from_bits, float32_from_field, float32_from_u32, float32_from_u64, float32_to_bits,
    float32_to_field, float32_to_u32, float32_to_u64, float32_zero,
};

// ============================================================================
// Float32 from u32 Tests
// ============================================================================

#[test]
fn test_float32_from_u32_zero() {
    let result = float32_from_u32(0);
    assert(float32_to_bits(result) == 0x00000000);
}

#[test]
fn test_float32_from_u32_one() {
    // 1u32 -> 1.0f32 = 0x3F800000
    let result = float32_from_u32(1);
    assert(float32_to_bits(result) == 0x3F800000);
}

#[test]
fn test_float32_from_u32_two() {
    // 2u32 -> 2.0f32 = 0x40000000
    let result = float32_from_u32(2);
    assert(float32_to_bits(result) == 0x40000000);
}

#[test]
fn test_float32_from_u32_power_of_two() {
    // 16u32 -> 16.0f32 = 0x41800000
    let result = float32_from_u32(16);
    assert(float32_to_bits(result) == 0x41800000);
}

#[test]
fn test_float32_from_u32_large() {
    // 1000u32 -> 1000.0f32 = 0x447A0000
    let result = float32_from_u32(1000);
    assert(float32_to_bits(result) == 0x447A0000);
}

#[test]
fn test_float32_from_u32_max() {
    // 0xFFFFFFFF (4294967295) -> 0x4F800000 (4294967296.0)
    let result = float32_from_u32(0xFFFFFFFF);
    assert(float32_to_bits(result) == 0x4F800000);
}

// ============================================================================
// Float32 from u64 Tests
// ============================================================================

#[test]
fn test_float32_from_u64_zero() {
    let result = float32_from_u64(0);
    assert(float32_to_bits(result) == 0x00000000);
}

#[test]
fn test_float32_from_u64_one() {
    let result = float32_from_u64(1);
    assert(float32_to_bits(result) == 0x3F800000);
}

#[test]
fn test_float32_from_u64_large() {
    // 1000u64 -> 1000.0f32
    let result = float32_from_u64(1000);
    assert(float32_to_bits(result) == 0x447A0000);
}

// ============================================================================
// Float32 to u32 Tests
// ============================================================================

#[test]
fn test_float32_to_u32_zero() {
    let f = float32_zero(0);
    let result = float32_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_u32_one() {
    // 1.0f32 -> 1u32
    let f = float32_from_bits(0x3F800000);
    let result = float32_to_u32(f);
    assert(result == 1);
}

#[test]
fn test_float32_to_u32_two() {
    // 2.0f32 -> 2u32
    let f = float32_from_bits(0x40000000);
    let result = float32_to_u32(f);
    assert(result == 2);
}

#[test]
fn test_float32_to_u32_truncate() {
    // 2.7f32 -> 2u32 (truncate)
    let f = float32_from_bits(0x402CCCCD); // ~2.7
    let result = float32_to_u32(f);
    assert(result == 2);
}

#[test]
fn test_float32_to_u32_large() {
    // 1000.0f32 -> 1000u32
    let f = float32_from_bits(0x447A0000);
    let result = float32_to_u32(f);
    assert(result == 1000);
}

#[test]
fn test_float32_to_u32_negative() {
    // -5.0f32 -> 0u32 (negative values become 0)
    let f = float32_from_bits(0xC0A00000);
    let result = float32_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_u32_infinity() {
    // +Inf -> max u32
    let f = float32_from_bits(0x7F800000);
    let result = float32_to_u32(f);
    assert(result == 0xFFFFFFFF);

    // -Inf -> 0
    let f_neg = float32_from_bits(0xFF800000);
    let result_neg = float32_to_u32(f_neg);
    assert(result_neg == 0);
}

#[test]
fn test_float32_to_u32_nan() {
    // NaN -> 0
    let f = float32_from_bits(0x7FC00000);
    let result = float32_to_u32(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_u32_fractional() {
    // 0.5f32 -> 0u32 (< 1 truncates to 0)
    let f = float32_from_bits(0x3F000000);
    let result = float32_to_u32(f);
    assert(result == 0);
}

// ============================================================================
// Float32 to u64 Tests
// ============================================================================

#[test]
fn test_float32_to_u64_zero() {
    let f = float32_zero(0);
    let result = float32_to_u64(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_u64_one() {
    let f = float32_from_bits(0x3F800000);
    let result = float32_to_u64(f);
    assert(result == 1);
}

#[test]
fn test_float32_to_u64_large() {
    // 1000.0f32 -> 1000u64
    let f = float32_from_bits(0x447A0000);
    let result = float32_to_u64(f);
    assert(result == 1000);
}

#[test]
fn test_float32_to_u64_negative() {
    // -5.0f32 -> 0u64
    let f = float32_from_bits(0xC0A00000);
    let result = float32_to_u64(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_u64_infinity() {
    // +Inf -> max u64
    let f = float32_from_bits(0x7F800000);
    let result = float32_to_u64(f);
    assert(result == 0xFFFFFFFFFFFFFFFF);
}

// ============================================================================
// Round-trip Tests
// ============================================================================

#[test]
fn test_float32_u32_roundtrip_small() {
    let original: u32 = 42;
    let f = float32_from_u32(original);
    let result = float32_to_u32(f);
    assert(result == original);
}

#[test]
fn test_float32_u32_roundtrip_powers_of_two() {
    let original: u32 = 1024;
    let f = float32_from_u32(original);
    let result = float32_to_u32(f);
    assert(result == original);
}

#[test]
fn test_float32_u64_roundtrip_small() {
    let original: u64 = 42;
    let f = float32_from_u64(original);
    let result = float32_to_u64(f);
    assert(result == original);
}

// ============================================================================
// Float32 Field Conversion Tests
// ============================================================================

#[test]
fn test_float32_from_field_zero() {
    let field_val: Field = 0;
    let result = float32_from_field(field_val);
    assert(float32_to_bits(result) == 0x00000000);
}

#[test]
fn test_float32_from_field_one() {
    let field_val: Field = 1;
    let result = float32_from_field(field_val);
    assert(float32_to_bits(result) == 0x3F800000); // 1.0
}

#[test]
fn test_float32_from_field_large() {
    let field_val: Field = 1000;
    let result = float32_from_field(field_val);
    assert(float32_to_bits(result) == 0x447A0000); // 1000.0
}

#[test]
fn test_float32_to_field_zero() {
    let f = float32_zero(0);
    let result = float32_to_field(f);
    assert(result == 0);
}

#[test]
fn test_float32_to_field_one() {
    let f = float32_from_bits(0x3F800000); // 1.0
    let result = float32_to_field(f);
    assert(result == 1);
}

#[test]
fn test_float32_to_field_large() {
    let f = float32_from_bits(0x447A0000); // 1000.0
    let result = float32_to_field(f);
    assert(result == 1000);
}

#[test]
fn test_float32_field_roundtrip() {
    let original: Field = 42;
    let f = float32_from_field(original);
    let result = float32_to_field(f);
    assert(result == original);
}
