// ============================================================================
// IEEE 754 Float32 Integer Conversion Functions
// ============================================================================

use crate::float32::helpers::{float32_infinity, float32_is_infinity, float32_is_nan, float32_zero};
use crate::types::{FLOAT32_IMPLICIT_BIT, IEEE754Float32};

// ============================================================================
// Integer to Float32 Conversions
// ============================================================================

/// Convert u32 to IEEE754Float32
/// Returns the float32 representation of the integer value
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_from_u32(value: u32) -> IEEE754Float32 {
    let mut result = float32_zero(0);

    if value != 0 {
        // Find the position of the most significant bit
        let mut leading_zeros = 0;
        let mut temp = value;
        for _i in 0..32 {
            let is_msb_set = temp >= 0x80000000;
            leading_zeros = if is_msb_set {
                leading_zeros
            } else {
                leading_zeros + 1
            };
            temp = if is_msb_set { temp } else { temp << 1 };
        }

        let msb_pos = 31 - leading_zeros;

        // Exponent with bias (127 for float32)
        let exponent = 127 + msb_pos;

        // Create mantissa by shifting value left to position the MSB at bit 23
        // and masking off the implicit bit
        result = if msb_pos >= 23 {
            // Need to shift right and potentially round
            let shift = msb_pos - 23;
            let shifted = value >> shift;
            let mut mantissa = shifted & 0x7FFFFF;

            // Check for rounding (look at bits that were shifted out)
            let should_round = if shift > 0 {
                let lost_bits = value & ((1 << shift) - 1);
                let halfway = 1 << (shift - 1);
                (lost_bits > halfway) | ((lost_bits == halfway) & ((shifted & 1) == 1))
            } else {
                false
            };

            mantissa = if should_round { mantissa + 1 } else { mantissa };

            // Handle mantissa overflow
            if mantissa > 0x7FFFFF {
                IEEE754Float32 { sign: 0, exponent: (exponent + 1) as u8, mantissa: 0 }
            } else {
                IEEE754Float32 { sign: 0, exponent: exponent as u8, mantissa }
            }
        } else {
            // Shift left to position
            let shift = 23 - msb_pos;
            let shifted = value << shift;
            let mantissa = shifted & 0x7FFFFF;
            IEEE754Float32 { sign: 0, exponent: exponent as u8, mantissa }
        };
    }

    result
}

/// Convert u64 to IEEE754Float32 (may lose precision for large values)
/// Returns the float32 representation of the integer value
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_from_u64(value: u64) -> IEEE754Float32 {
    let mut result = float32_zero(0);

    if value != 0 {
        // Find the position of the most significant bit
        let mut leading_zeros = 0;
        let mut temp = value;
        for _i in 0..64 {
            let is_msb_set = temp >= 0x8000000000000000;
            leading_zeros = if is_msb_set {
                leading_zeros
            } else {
                leading_zeros + 1
            };
            temp = if is_msb_set { temp } else { temp << 1 };
        }

        let msb_pos = 63 - leading_zeros;

        // Exponent with bias (127 for float32)
        let exponent = 127 + msb_pos;

        // Check for overflow (exponent > 255 means infinity)
        result = if exponent > 254 {
            float32_infinity(0)
        } else {
            // Create mantissa by shifting value to position the MSB at bit 23
            // For u64, we need to extract the top 24 bits (including implicit bit)
            let float_result = if msb_pos >= 23 {
                let shift = msb_pos - 23;
                // Safe cast: value >> shift extracts the top (shift + 1) bits, max 24 bits
                let shifted = (value >> shift) as u32;
                // Check for rounding (look at bits that were shifted out)
                let lost_bits = value & ((1 << shift) - 1);
                let mut result_mant = shifted & 0x7FFFFF;

                // Round to nearest, ties to even
                let should_round = if shift > 0 {
                    let halfway = 1 << (shift - 1);
                    (lost_bits > halfway) | ((lost_bits == halfway) & ((shifted & 1) == 1))
                } else {
                    false
                };

                result_mant = if should_round {
                    result_mant + 1
                } else {
                    result_mant
                };

                // Handle mantissa overflow
                if result_mant > 0x7FFFFF {
                    IEEE754Float32 { sign: 0, exponent: (exponent + 1) as u8, mantissa: 0 }
                } else {
                    IEEE754Float32 { sign: 0, exponent: exponent as u8, mantissa: result_mant }
                }
            } else {
                // msb_pos < 23: value has at most 23 bits, shift left to position
                let shift = 23 - msb_pos;
                // Safe cast: value has msb_pos+1 bits, after shift has at most 24 bits
                let shifted = (value << shift) as u32;
                let mantissa = shifted & 0x7FFFFF;
                IEEE754Float32 { sign: 0, exponent: exponent as u8, mantissa }
            };

            float_result
        };
    }

    result
}

// ============================================================================
// Float32 to Integer Conversions (truncate toward zero)
// ============================================================================

/// Convert IEEE754Float32 to u32 (truncate toward zero)
/// Returns 0 for NaN, 0 for values < 0, 0xFFFFFFFF for overflow
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_to_u32(f: IEEE754Float32) -> u32 {
    let mut result = 0;

    // Handle special cases
    let is_nan = float32_is_nan(f);
    let is_inf = float32_is_infinity(f);
    let is_negative = f.sign == 1;
    let is_zero_or_denormal = f.exponent == 0;

    result = if is_nan {
        0
    } else if is_inf {
        if is_negative {
            0
        } else {
            0xFFFFFFFF
        }
    } else if is_negative {
        0
    } else if is_zero_or_denormal {
        0
    } else {
        // Get the unbiased exponent
        let unbiased_exp = (f.exponent as i16) - 127;

        // If exponent is negative, the value is < 1, so truncates to 0
        // If exponent is too large, we overflow
        if (unbiased_exp < 0) {
            0
        } else if (unbiased_exp >= 32) {
            0xFFFFFFFF
        } else {
            // Reconstruct the value with implicit bit
            let full_mantissa = f.mantissa | FLOAT32_IMPLICIT_BIT;

            // The mantissa has the implicit bit at position 23
            // We need to shift it to get the integer part
            let exp = unbiased_exp as u32;

            if exp >= 23 {
                // Shift left (value >= 2^23)
                let shift = exp - 23;
                if shift >= 9 {
                    // Would overflow u32
                    0xFFFFFFFF
                } else {
                    full_mantissa << shift
                }
            } else {
                // Shift right (value < 2^23)
                full_mantissa >> (23 - exp)
            }
        }
    };

    result
}

/// Convert IEEE754Float32 to u64 (truncate toward zero)
/// Returns 0 for NaN, 0 for values < 0, 0xFFFFFFFFFFFFFFFF for overflow
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_to_u64(f: IEEE754Float32) -> u64 {
    let mut result: u64 = 0;

    // Handle special cases
    let is_nan = float32_is_nan(f);
    let is_inf = float32_is_infinity(f);
    let is_negative = f.sign == 1;
    let is_zero_or_denormal = f.exponent == 0;

    result = if is_nan {
        0
    } else if is_inf {
        if is_negative {
            0
        } else {
            0xFFFFFFFFFFFFFFFF
        }
    } else if is_negative {
        0
    } else if is_zero_or_denormal {
        0
    } else {
        // Get the unbiased exponent
        let unbiased_exp = (f.exponent as i16) - 127;

        // If exponent is negative, the value is < 1, so truncates to 0
        // If exponent is too large, we overflow
        if (unbiased_exp < 0) {
            0
        } else if (unbiased_exp >= 64) {
            0xFFFFFFFFFFFFFFFF
        } else {
            // Reconstruct the value with implicit bit
            let full_mantissa = (f.mantissa as u64) | (FLOAT32_IMPLICIT_BIT as u64);

            // The mantissa has the implicit bit at position 23
            // We need to shift it to get the integer part
            let exp = unbiased_exp as u64;

            if exp >= 23 {
                // Shift left (value >= 2^23)
                let shift = exp - 23;
                if shift >= 41 {
                    // Would overflow u64
                    0xFFFFFFFFFFFFFFFF
                } else {
                    full_mantissa << shift
                }
            } else {
                // Shift right (value < 2^23)
                full_mantissa >> (23 - exp)
            }
        }
    };

    result
}

// ============================================================================
// Field to Float32 Conversions
// ============================================================================

/// Convert Field to IEEE754Float32
/// Returns the float32 representation of the field element
/// Note: Field elements can be very large, so this will likely lose precision
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_from_field(value: Field) -> IEEE754Float32 {
    // Convert Field to u64 first (this may truncate for large field elements)
    // Field is internally a large integer, we take modulo 2^64 for conversion
    let value_u64 = value as u64;
    float32_from_u64(value_u64)
}

/// Convert IEEE754Float32 to Field (truncate toward zero)
/// Returns Field representation of the float's integer value
/// Returns 0 for NaN, 0 for negative values
///
/// # Warning
/// This function has not been extensively tested or reviewed. Use with caution.
pub fn float32_to_field(f: IEEE754Float32) -> Field {
    let value_u64 = float32_to_u64(f);
    value_u64 as Field
}
