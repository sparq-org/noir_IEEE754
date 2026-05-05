// ============================================================================
// IEEE 754 Float32 Addition
// ============================================================================

use crate::float32::helpers::{
    float32_infinity, float32_is_denormal, float32_is_infinity, float32_is_nan, float32_is_zero,
    float32_max_finite, float32_nan, float32_zero,
};
use crate::types::{
    FLOAT32_EXPONENT_MAX, FLOAT32_IMPLICIT_BIT, IEEE754Float32, ROUNDING_MODE_NEAREST_EVEN,
    ROUNDING_MODE_TOWARD_NEGATIVE,
};
use crate::utils::{assert_valid_rounding_mode, directed_overflow_saturates_to_inf, should_round_up};

// IEEE 754 compliant addition for 32-bit floats with rounding mode.
//
// `rounding_mode` must be one of the `ROUNDING_MODE_*` constants in
// `crate::types` (i.e. `0..=4`). Any other value triggers an assertion
// failure -- silently treating an unknown mode as round-to-nearest-even is
// a footgun that masks calling-side bugs.
//
// ----------------------------------------------------------------------------
// Lean equivalence proof. See `circuits/lampe-literate` for the build tool
// that resolves the LAMPE-LITERATE directives below, splices the referenced
// proof file into a generated Lean module, and runs `lake build` against the
// workspace's shared `Models.lean` / `Subterms.lean` / `Spec.lean`. Generated
// `.lean` files land in a gitignored scratch dir; only this Noir source plus
// the standalone `.lean` proof files are version-controlled. Method:
// skeleton-and-specialisations (round 7;
// `proofs/Ieee754/equivalence-spike-2026-05-04.md`).
// ----------------------------------------------------------------------------
//
// LAMPE-LITERATE preamble: ../../proofs/add_f32_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/add_f32_equivalence.lean fn=add_float32_with_rounding name=add_f32_equivalence
pub fn add_float32_with_rounding(
    a: IEEE754Float32,
    b: IEEE754Float32,
    rounding_mode: u8,
) -> IEEE754Float32 {
    assert_valid_rounding_mode(rounding_mode);
    let a_is_nan = float32_is_nan(a);
    let b_is_nan = float32_is_nan(b);
    let a_is_inf = float32_is_infinity(a);
    let b_is_inf = float32_is_infinity(b);
    let a_is_zero = float32_is_zero(a);
    let b_is_zero = float32_is_zero(b);
    let a_is_denormal = float32_is_denormal(a);
    let b_is_denormal = float32_is_denormal(b);

    let mant_a_raw: u64 = if a_is_denormal {
        a.mantissa as u64
    } else {
        (a.mantissa | FLOAT32_IMPLICIT_BIT) as u64
    };
    let mant_b_raw: u64 = if b_is_denormal {
        b.mantissa as u64
    } else {
        (b.mantissa | FLOAT32_IMPLICIT_BIT) as u64
    };
    let exp_a_eff: u64 = if a_is_denormal | a_is_zero {
        1
    } else {
        a.exponent as u64
    };
    let exp_b_eff: u64 = if b_is_denormal | b_is_zero {
        1
    } else {
        b.exponent as u64
    };

    let mut mant_a: u64 = mant_a_raw << 3;
    let mut mant_b: u64 = mant_b_raw << 3;
    let mut result_exp: u64 = exp_a_eff;

    if exp_a_eff > exp_b_eff {
        let shift = exp_a_eff - exp_b_eff;
        if shift >= 64 {
            mant_b = if mant_b != 0 { 1 } else { 0 };
        } else {
            let mask = (1 << shift) - 1;
            let sticky = mant_b & mask;
            mant_b = mant_b >> shift;
            if sticky != 0 {
                mant_b = mant_b | 1;
            }
        }
        result_exp = exp_a_eff;
    } else if exp_b_eff > exp_a_eff {
        let shift = exp_b_eff - exp_a_eff;
        if shift >= 64 {
            mant_a = if mant_a != 0 { 1 } else { 0 };
        } else {
            let mask = (1 << shift) - 1;
            let sticky = mant_a & mask;
            mant_a = mant_a >> shift;
            if sticky != 0 {
                mant_a = mant_a | 1;
            }
        }
        result_exp = exp_b_eff;
    }

    let mut result_mant: u64 = 0;
    let mut result_sign: u1 = 0;
    if a.sign == b.sign {
        result_mant = mant_a + mant_b;
        result_sign = a.sign;
    } else {
        if mant_a >= mant_b {
            result_mant = mant_a - mant_b;
            result_sign = a.sign;
        } else {
            result_mant = mant_b - mant_a;
            result_sign = b.sign;
        }
    }

    // Overflow normalization
    let overflow_threshold: u64 = (FLOAT32_IMPLICIT_BIT as u64) << 4;
    if result_mant >= overflow_threshold {
        let sticky = result_mant & 1;
        result_mant = (result_mant >> 1) | sticky;
        result_exp = result_exp + 1;
    }

    // Underflow normalization using binary search for leading zeros
    let normal_position: u64 = (FLOAT32_IMPLICIT_BIT as u64) << 3;
    if (result_mant != 0) & (result_mant < normal_position) {
        let target_bit: u64 = 26;
        let mut leading_zeros: u64 = 0;
        let mut v = result_mant;
        if v & 0xFFFFFFFF00000000 == 0 {
            leading_zeros += 32;
            v <<= 32;
        }
        if v & 0xFFFF000000000000 == 0 {
            leading_zeros += 16;
            v <<= 16;
        }
        if v & 0xFF00000000000000 == 0 {
            leading_zeros += 8;
            v <<= 8;
        }
        if v & 0xF000000000000000 == 0 {
            leading_zeros += 4;
            v <<= 4;
        }
        if v & 0xC000000000000000 == 0 {
            leading_zeros += 2;
            v <<= 2;
        }
        if v & 0x8000000000000000 == 0 {
            leading_zeros += 1;
        }

        let shift_needed = leading_zeros - (64 - target_bit - 1);
        let max_shift = if result_exp > 1 { result_exp - 1 } else { 0 };
        let actual_shift = if shift_needed <= max_shift {
            shift_needed
        } else {
            max_shift
        };

        result_mant = result_mant << actual_shift;
        result_exp = result_exp - actual_shift;
    }

    // Denormal result
    let mut is_denormal_result = false;
    if (result_exp == 0) | ((result_exp == 1) & (result_mant < normal_position)) {
        result_exp = 0;
        is_denormal_result = true;
    }

    // Rounding
    let guard_bits = result_mant & 0x7;
    result_mant = result_mant >> 3;
    let should_round = if rounding_mode == 0 {
        // NEAREST_EVEN (optimized inline)
        (guard_bits > 4) | ((guard_bits == 4) & ((result_mant & 1) == 1))
    } else {
        should_round_up(guard_bits, result_mant, result_sign, rounding_mode)
    };
    if should_round {
        result_mant = result_mant + 1;
        if result_mant >= ((FLOAT32_IMPLICIT_BIT as u64) << 1) {
            result_mant = result_mant >> 1;
            result_exp = result_exp + 1;
        } else if is_denormal_result & (result_mant >= (FLOAT32_IMPLICIT_BIT as u64)) {
            result_exp = 1;
        }
    }

    // Build result
    let overflows_to_inf = result_exp >= (FLOAT32_EXPONENT_MAX as u64);
    let result_is_zero = result_mant == 0;
    let final_mantissa = if is_denormal_result & (result_exp == 0) {
        (result_mant & 0x7FFFFF) as u32
    } else {
        (result_mant & ((FLOAT32_IMPLICIT_BIT - 1) as u64)) as u32
    };
    let normal_result =
        IEEE754Float32 { sign: result_sign, exponent: result_exp as u8, mantissa: final_mantissa };

    let mut result = normal_result;
    if result_is_zero {
        // IEEE 754-2019 sec 6.3 (signedness of zero results from sums):
        // exact-zero cancellation of opposite-sign operands of equal
        // magnitude is `+0` under every rounding-direction attribute
        // except roundTowardNegative, under which it is `-0`. The
        // pre-fix circuit hard-coded `+0`. NB: like-sign zero sums fall
        // through to the ``a_is_zero & b_is_zero`` clause below, which
        // already implements 6.3 (`a.sign & b.sign`).
        let cancellation_sign: u1 = if rounding_mode == ROUNDING_MODE_TOWARD_NEGATIVE {
            1
        } else {
            0
        };
        result = float32_zero(cancellation_sign);
    }
    if overflows_to_inf {
        // IEEE 754-2019 sec 7.4 (overflow under directed rounding): under
        // ``roundTowardZero`` the overflow result is the destination's
        // largest finite with the sign of the intermediate result; under
        // ``roundTowardPositive`` / ``roundTowardNegative`` it is +/- Inf
        // when the rounding direction matches the result sign and
        // +/- max-finite otherwise. Round-to-nearest modes always go to
        // +/- Inf. ``directed_overflow_saturates_to_inf`` centralises the
        // rule (bug class 1, per PR #49).
        if directed_overflow_saturates_to_inf(rounding_mode, result_sign) {
            result = float32_infinity(result_sign);
        } else {
            result = float32_max_finite(result_sign);
        }
    }
    if a_is_zero & b_is_zero {
        // IEEE 754-2019 sec 6.3 (signedness of zero results from sums):
        // for two operand zeros (the early short-circuit path), the sum
        // shares the sign of both operands when they agree
        // (``+0 + +0 = +0``, ``-0 + -0 = -0``); for opposite signs the
        // sum is ``+0`` under every rounding-direction attribute except
        // ``roundTowardNegative``, under which it is ``-0``.
        let signs_match = a.sign == b.sign;
        let zero_sign: u1 = if signs_match {
            a.sign
        } else if rounding_mode == ROUNDING_MODE_TOWARD_NEGATIVE {
            1
        } else {
            0
        };
        result = float32_zero(zero_sign);
    } else if a_is_zero {
        result = b;
    } else if b_is_zero {
        result = a;
    }
    if a_is_inf & !b_is_inf {
        result = a;
    } else if b_is_inf & !a_is_inf {
        result = b;
    } else if a_is_inf & b_is_inf {
        if a.sign == b.sign {
            result = a;
        } else {
            result = float32_nan();
        }
    }
    if a_is_nan | b_is_nan {
        result = float32_nan();
    }

    result
}

// IEEE 754 compliant addition for 32-bit floats (default rounding mode)
// Backward-compatible wrapper that uses round-to-nearest-ties-to-even
pub fn add_float32(a: IEEE754Float32, b: IEEE754Float32) -> IEEE754Float32 {
    add_float32_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN)
}
