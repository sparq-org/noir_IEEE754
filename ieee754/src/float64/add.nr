// ============================================================================
// IEEE 754 Float64 Addition
// ============================================================================

use crate::float64::helpers::{
    float64_infinity, float64_is_denormal, float64_is_infinity, float64_is_nan, float64_is_zero,
    float64_max_finite, float64_nan, float64_zero,
};
use crate::types::{
    FLOAT64_EXPONENT_MAX, FLOAT64_IMPLICIT_BIT, IEEE754Float64, ROUNDING_MODE_NEAREST_EVEN,
    ROUNDING_MODE_TOWARD_NEGATIVE,
};
use crate::utils::{
    assert_valid_rounding_mode, directed_overflow_saturates_to_inf, should_round_up_8bit,
};

// IEEE 754 compliant addition for 64-bit doubles with rounding mode.
//
// `rounding_mode` must be one of the `ROUNDING_MODE_*` constants in
// `crate::types` (i.e. `0..=4`). Any other value triggers an assertion
// failure -- silently treating an unknown mode as round-to-nearest-even is
// a footgun that masks calling-side bugs.
//
// ----------------------------------------------------------------------------
// Lean equivalence proof (round 7b). See `circuits/lampe-literate` for the
// build tool that resolves the LAMPE-LITERATE directives below, splices the
// referenced proof file into a generated Lean module, and runs `lake build`
// against the workspace's shared `ModelsF64.lean` / `SubtermsF64.lean`.
// Generated `.lean` files land in a gitignored scratch dir; only this Noir
// source plus the standalone `.lean` proof files are version-controlled.
// Method: skeleton-and-specialisations -- the f64 path uses *explicit*
// sticky flags, so there is no `shr_sticky` divergence to reconcile and
// only two diverging-subterm parameters (`clz`, `rneDecision`) appear.
// ----------------------------------------------------------------------------
//
// LAMPE-LITERATE preamble: ../../proofs/add_f64_preamble.lean
// LAMPE-LITERATE proof:    ../../proofs/add_f64_equivalence.lean fn=add_float64_with_rounding name=add_f64_equivalence
pub fn add_float64_with_rounding(
    a: IEEE754Float64,
    b: IEEE754Float64,
    rounding_mode: u8,
) -> IEEE754Float64 {
    assert_valid_rounding_mode(rounding_mode);
    let a_is_nan = float64_is_nan(a);
    let b_is_nan = float64_is_nan(b);
    let a_is_inf = float64_is_infinity(a);
    let b_is_inf = float64_is_infinity(b);
    let a_is_zero = float64_is_zero(a);
    let b_is_zero = float64_is_zero(b);
    let a_is_denormal = float64_is_denormal(a);
    let b_is_denormal = float64_is_denormal(b);

    let mant_a_raw: u64 = if a_is_denormal {
        a.mantissa
    } else {
        a.mantissa | FLOAT64_IMPLICIT_BIT
    };
    let mant_b_raw: u64 = if b_is_denormal {
        b.mantissa
    } else {
        b.mantissa | FLOAT64_IMPLICIT_BIT
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

    let mut mant_a: u64 = mant_a_raw << 8;
    let mut mant_b: u64 = mant_b_raw << 8;
    let mut sticky_a: u64 = 0;
    let mut sticky_b: u64 = 0;
    let mut result_exp: u64 = exp_a_eff;

    if exp_a_eff > exp_b_eff {
        let shift_amount = exp_a_eff - exp_b_eff;
        result_exp = exp_a_eff;
        if shift_amount >= 64 {
            sticky_b = if mant_b != 0 { 1 } else { 0 };
            mant_b = 0;
        } else {
            let mask = (1 << shift_amount) - 1;
            let shifted_out = mant_b & mask;
            mant_b = mant_b >> shift_amount;
            if shifted_out != 0 {
                sticky_b = 1;
            }
        }
    } else if exp_b_eff > exp_a_eff {
        let shift_amount = exp_b_eff - exp_a_eff;
        result_exp = exp_b_eff;
        if shift_amount >= 64 {
            sticky_a = if mant_a != 0 { 1 } else { 0 };
            mant_a = 0;
        } else {
            let mask = (1 << shift_amount) - 1;
            let shifted_out = mant_a & mask;
            mant_a = mant_a >> shift_amount;
            if shifted_out != 0 {
                sticky_a = 1;
            }
        }
    }

    let mut result_mant: u64 = 0;
    let mut result_sticky: u64 = 0;
    let mut result_sign: u1 = 0;

    if a.sign == b.sign {
        result_mant = mant_a + mant_b;
        result_sticky = sticky_a | sticky_b;
        result_sign = a.sign;
        if result_mant < mant_a {
            result_sticky = result_sticky | (result_mant & 1);
            result_mant = (result_mant >> 1) | 0x8000000000000000;
            result_exp = result_exp + 1;
        }
    } else {
        if mant_a > mant_b {
            result_mant = mant_a - mant_b;
            if sticky_b != 0 {
                result_mant = result_mant - 1;
                result_sticky = 1;
            }
            result_sign = a.sign;
        } else if mant_b > mant_a {
            result_mant = mant_b - mant_a;
            if sticky_a != 0 {
                result_mant = result_mant - 1;
                result_sticky = 1;
            }
            result_sign = b.sign;
        } else {
            if sticky_a > sticky_b {
                result_mant = 0;
                result_sticky = 1;
                result_sign = a.sign;
            } else if sticky_b > sticky_a {
                result_mant = 0;
                result_sticky = 1;
                result_sign = b.sign;
            } else {
                result_mant = 0;
                result_sticky = 0;
            }
        }
    }

    // Overflow normalization
    let overflow_threshold: u64 = FLOAT64_IMPLICIT_BIT << 9;
    if result_mant >= overflow_threshold {
        result_sticky = result_sticky | (result_mant & 1);
        result_mant = result_mant >> 1;
        result_exp = result_exp + 1;
    }

    // Underflow normalization using binary search for leading zeros
    let normal_position: u64 = FLOAT64_IMPLICIT_BIT << 8;
    if (result_mant != 0) & (result_mant < normal_position) {
        let target_bit: u64 = 60; // Position of implicit bit after shift by 8
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

    // Denormal result.
    //
    // ``result_mant`` carries the working layout
    // ``[guard:8 | mantissa+implicit:53 | _]`` whose value at biased
    // exponent ``result_exp`` matches the IEEE 754 value
    // ``result_mant * 2^(result_exp - bias - 60)``. When the underflow
    // normaliser exits with ``result_exp == 1 & result_mant <
    // normal_position`` the value cannot be expressed as a normal at exp 1
    // and must be re-encoded as a denormal at exp 0. IEEE 754-2019 sec 6.2
    // (denormalisation) requires only the exponent change -- the mantissa
    // bits stay in their fixed-point slots, because at exp 0 the (omitted)
    // implicit bit weighs the same as it did at exp 1 (both subtract one
    // bias offset of 1023 from the value). The float32 sibling
    // (`ieee754/src/float32/add.nr`) already encodes this correctly. The
    // pre-fix circuit applied a stray ``result_mant >> 1`` here, which
    // halved every denormal-output sum -- e.g. ``MIN_DENORMAL +
    // MIN_DENORMAL`` returned ``0x1`` instead of ``0x2``. The Berkeley
    // TestFloat corpus surfaces the bug across every directed-rounding
    // mode and across f64-add/f64-sub (sub composes through add).
    let mut is_denormal_result = false;
    if (result_exp == 0) | ((result_exp == 1) & (result_mant < normal_position)) {
        result_exp = 0;
        is_denormal_result = true;
    }

    // Rounding
    let guard_bits = result_mant & 0xFF;
    result_mant = result_mant >> 8;
    let round_bits = guard_bits | result_sticky;
    let should_round = if rounding_mode == 0 {
        // NEAREST_EVEN (optimized inline)
        let halfway: u64 = 0x80;
        (round_bits > halfway) | ((round_bits == halfway) & ((result_mant & 1) == 1))
    } else {
        should_round_up_8bit(round_bits, result_mant, result_sign, rounding_mode)
    };
    if should_round {
        result_mant = result_mant + 1;
        if result_mant >= (FLOAT64_IMPLICIT_BIT << 1) {
            result_mant = result_mant >> 1;
            result_exp = result_exp + 1;
        } else if is_denormal_result & (result_mant >= FLOAT64_IMPLICIT_BIT) {
            result_exp = 1;
        }
    }

    let overflows_to_inf = result_exp >= (FLOAT64_EXPONENT_MAX as u64);
    let final_mantissa = if is_denormal_result & (result_exp == 0) {
        result_mant & 0xFFFFFFFFFFFFF
    } else {
        result_mant & (FLOAT64_IMPLICIT_BIT - 1)
    };
    let normal_result =
        IEEE754Float64 { sign: result_sign, exponent: result_exp as u16, mantissa: final_mantissa };

    let mut result = normal_result;
    if (result_mant == 0) & (result_sticky == 0) {
        // IEEE 754-2019 sec 6.3 (signedness of zero results from sums):
        // when the sum of two opposite-signed operands of equal magnitude
        // (or the difference of two like-signed operands of equal magnitude)
        // is exactly zero, the sign of that exact-zero sum is `+` under
        // every rounding-direction attribute except roundTowardNegative,
        // under which it is `-`. The pre-fix circuit hard-coded `+0`, which
        // is wrong for RNDD. NB: only opposite-sign cancellation reaches
        // this branch -- like-sign sums of zero come from the
        // ``a_is_zero & b_is_zero`` clause below, which already implements
        // 6.3 (`a.sign & b.sign`).
        let cancellation_sign: u1 = if rounding_mode == ROUNDING_MODE_TOWARD_NEGATIVE {
            1
        } else {
            0
        };
        result = float64_zero(cancellation_sign);
    }
    if overflows_to_inf {
        // IEEE 754-2019 sec 7.4: directed rounding may clamp overflow to
        // +/-max-finite instead of +/-Inf. Bug class 1 (per PR #49).
        if directed_overflow_saturates_to_inf(rounding_mode, result_sign) {
            result = float64_infinity(result_sign);
        } else {
            result = float64_max_finite(result_sign);
        }
    }
    if a_is_zero & b_is_zero {
        // IEEE 754-2019 sec 6.3 (signedness of zero results from sums):
        // matching signs propagate; opposite-sign zero operands sum to
        // ``+0`` under every rounding-direction attribute except
        // ``roundTowardNegative``, which yields ``-0``.
        let signs_match = a.sign == b.sign;
        let zero_sign: u1 = if signs_match {
            a.sign
        } else if rounding_mode == ROUNDING_MODE_TOWARD_NEGATIVE {
            1
        } else {
            0
        };
        result = float64_zero(zero_sign);
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
            result = float64_nan();
        }
    }
    if a_is_nan | b_is_nan {
        result = float64_nan();
    }

    result
}

// IEEE 754 compliant addition for 64-bit doubles (default rounding mode)
// Backward-compatible wrapper that uses round-to-nearest-ties-to-even
pub fn add_float64(a: IEEE754Float64, b: IEEE754Float64) -> IEEE754Float64 {
    add_float64_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN)
}
