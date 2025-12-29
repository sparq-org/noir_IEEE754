// ============================================================================
// IEEE 754 Float64 Integer Conversion Functions
// ============================================================================

use crate::float64::helpers::{float64_infinity, float64_is_infinity, float64_is_nan, float64_zero};
use crate::types::{FLOAT64_IMPLICIT_BIT, IEEE754Float64};

// ============================================================================
// Integer to Float64 Conversions
// ============================================================================

/// Convert u32 to IEEE754Float64
/// Returns the float64 representation of the integer value (exact conversion)
pub fn float64_from_u32(value: u32) -> IEEE754Float64 {
    let mut result = float64_zero(0);

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

        // Exponent with bias (1023 for float64)
        let exponent = 1023 + msb_pos;

        // Create mantissa by shifting value left to position the MSB at bit 52
        // and masking off the implicit bit
        let mantissa = if msb_pos >= 52 {
            // This can't happen for u32 since msb_pos <= 31
            0
        } else {
            // Shift left to position (u32 always fits in float64 mantissa)
            let shift = 52 - msb_pos;
            let shifted = (value as u64) << shift;
            shifted & 0xFFFFFFFFFFFFF
        };

        result = IEEE754Float64 { sign: 0, exponent: exponent as u16, mantissa };
    }

    result
}

/// Convert u64 to IEEE754Float64 (may lose precision for very large values)
/// Returns the float64 representation of the integer value
pub fn float64_from_u64(value: u64) -> IEEE754Float64 {
    let mut result = float64_zero(0);

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

        // Exponent with bias (1023 for float64)
        let exponent = 1023 + msb_pos;

        // Check for overflow (exponent > 2047 means infinity)
        result = if exponent > 2046 {
            float64_infinity(0)
        } else {
            // Create mantissa by shifting value to position the MSB at bit 52
            let float_result = if msb_pos >= 52 {
                let shift = msb_pos - 52;
                let shifted = value >> shift;
                // Check for rounding (look at bits that were shifted out)
                let lost_bits = value & ((1 << shift) - 1);
                let mut result_mant = shifted & 0xFFFFFFFFFFFFF;

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
                if result_mant > 0xFFFFFFFFFFFFF {
                    IEEE754Float64 { sign: 0, exponent: (exponent + 1) as u16, mantissa: 0 }
                } else {
                    IEEE754Float64 { sign: 0, exponent: exponent as u16, mantissa: result_mant }
                }
            } else {
                let shift = 52 - msb_pos;
                let shifted = value << shift;
                let mantissa = shifted & 0xFFFFFFFFFFFFF;
                IEEE754Float64 { sign: 0, exponent: exponent as u16, mantissa }
            };

            float_result
        };
    }

    result
}

// ============================================================================
// Float64 to Integer Conversions (truncate toward zero)
// ============================================================================

/// Convert IEEE754Float64 to u32 (truncate toward zero)
/// Returns 0 for NaN, 0 for values < 0, 0xFFFFFFFF for overflow
pub fn float64_to_u32(f: IEEE754Float64) -> u32 {
    let mut result = 0;

    // Handle special cases
    let is_nan = float64_is_nan(f);
    let is_inf = float64_is_infinity(f);
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
        let unbiased_exp = (f.exponent as i16) - 1023;

        // If exponent is negative, the value is < 1, so truncates to 0
        // If exponent is too large, we overflow
        if (unbiased_exp < 0) {
            0
        } else if (unbiased_exp >= 32) {
            0xFFFFFFFF
        } else {
            // Reconstruct the value with implicit bit
            let full_mantissa = f.mantissa | FLOAT64_IMPLICIT_BIT;

            // The mantissa has the implicit bit at position 52
            // We need to shift it to get the integer part
            let exp = unbiased_exp as u64;

            if exp >= 52 {
                // Shift left (value >= 2^52)
                let shift = exp - 52;
                if shift == 0 {
                    // No shift needed, just cast
                    full_mantissa as u32
                } else {
                    // Check if this would overflow u32
                    let high_bits = full_mantissa >> (32 - shift);
                    if high_bits != 0 {
                        0xFFFFFFFF
                    } else {
                        (full_mantissa << shift) as u32
                    }
                }
            } else {
                // Shift right (value < 2^52)
                (full_mantissa >> (52 - exp)) as u32
            }
        }
    };

    result
}

/// Convert IEEE754Float64 to u64 (truncate toward zero)
/// Returns 0 for NaN, 0 for values < 0, 0xFFFFFFFFFFFFFFFF for overflow
pub fn float64_to_u64(f: IEEE754Float64) -> u64 {
    let mut result: u64 = 0;

    // Handle special cases
    let is_nan = float64_is_nan(f);
    let is_inf = float64_is_infinity(f);
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
        let unbiased_exp = (f.exponent as i16) - 1023;

        // If exponent is negative, the value is < 1, so truncates to 0
        // If exponent is too large, we overflow
        if (unbiased_exp < 0) {
            0
        } else if (unbiased_exp >= 64) {
            0xFFFFFFFFFFFFFFFF
        } else {
            // Reconstruct the value with implicit bit
            let full_mantissa = f.mantissa | FLOAT64_IMPLICIT_BIT;

            // The mantissa has the implicit bit at position 52
            // We need to shift it to get the integer part
            let exp = unbiased_exp as u64;

            if exp >= 52 {
                // Shift left (value >= 2^52)
                let shift = exp - 52;
                if shift >= 12 {
                    // Would overflow u64
                    0xFFFFFFFFFFFFFFFF
                } else {
                    full_mantissa << shift
                }
            } else {
                // Shift right (value < 2^52)
                full_mantissa >> (52 - exp)
            }
        }
    };

    result
}
