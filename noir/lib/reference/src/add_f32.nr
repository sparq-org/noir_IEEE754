// ============================================================================
// IEEE 754 binary32 ADD -- reference implementation
// ============================================================================
//
// This is the *reference* side of the round-1 equivalence proof. The goal is
// IEEE 754-2019 transparency, not gate efficiency. Every step cites the
// section of the standard it implements.
//
// Inputs / outputs and the rounding-mode encoding are kept identical to
// `ieee754::float32::add::add_float32_with_rounding` so the equivalence
// statement is a single function-level Lean equation rather than a
// representation-shuffling exercise.
//
// Layering (in evaluation order, ``last_override_wins`` so special values
// always trump the normal-path arithmetic):
//   1. Compute a normal-path candidate via signed-magnitude alignment +
//      rounding (sec 5.4.1, sec 4.3, sec 7.4).
//   2. Override for exact-zero cancellation                  (sec 6.3)
//   3. Override for overflow saturation                     (sec 7.4)
//   4. Override for either operand being zero               (sec 6.3)
//   5. Override for either operand being infinity           (sec 6.1)
//   6. Override for either operand being NaN                (sec 6.2)
//
// Noir does not support early `return`, so we follow the same "compute then
// override" structure used by `add_float32_with_rounding`. The order matters:
// NaN > Inf > Zero > overflow > cancellation > normal-path.

use ieee754::float32::{
    float32_infinity, float32_is_denormal, float32_is_infinity, float32_is_nan, float32_is_zero,
    float32_max_finite, float32_nan, float32_zero,
};
use ieee754::types::{
    FLOAT32_EXPONENT_MAX, FLOAT32_IMPLICIT_BIT, IEEE754Float32, ROUNDING_MODE_NEAREST_EVEN,
    ROUNDING_MODE_TOWARD_NEGATIVE,
};
use ieee754::utils::{directed_overflow_saturates_to_inf, should_round_up};

/// Right shift `value` by `shift` bits, OR-ing in a sticky `1` whenever any
/// nonzero bit is shifted out. Definitional, no fast paths.
///
/// IEEE 754 sec 5.4.1 (alignment of significands): the round / sticky bits
/// must be preserved across alignment so that the subsequent rounding step
/// sees the correct guard / round / sticky configuration.
fn shr_sticky(value: u64, shift: u64) -> u64 {
    if shift == 0 {
        value
    } else if shift >= 64 {
        if value != 0 { 1 } else { 0 }
    } else {
        let mask: u64 = (1 << shift) - 1;
        let dropped = value & mask;
        let shifted = value >> shift;
        if dropped != 0 { shifted | 1 } else { shifted }
    }
}

/// Pure-loop count of the leading zeros in a 64-bit word -- used in place of
/// the optimised crate's binary-search version. Slow on the prover side, but
/// every step is a one-line bitwise check that maps cleanly to mathlib's
/// `Nat.log2` / `BitVec.testBit`.
fn count_leading_zeros_u64_loop(value: u64) -> u64 {
    if value == 0 {
        64
    } else {
        let mut count: u64 = 0;
        let mut v = value;
        // Bounded `for` so Noir unrolls it at compile time. The loop body
        // is a literal "if the top bit is 0, count one and shift left".
        for _i in 0..64 {
            if (v & 0x8000000000000000) == 0 {
                count += 1;
                v <<= 1;
            }
        }
        count
    }
}

/// IEEE 754-2019 binary32 ADD, reference implementation.
///
/// Equivalence claim (round 1 spike target):
///   forall a, b, mode: well-formed binary32 inputs ->
///     add_f32_reference(a, b, mode) == add_float32_with_rounding(a, b, mode)
pub fn add_f32_reference(
    a: IEEE754Float32,
    b: IEEE754Float32,
    rounding_mode: u8,
) -> IEEE754Float32 {
    // Operand classification (sec 6.x).
    let a_is_nan = float32_is_nan(a);
    let b_is_nan = float32_is_nan(b);
    let a_is_inf = float32_is_infinity(a);
    let b_is_inf = float32_is_infinity(b);
    let a_is_zero = float32_is_zero(a);
    let b_is_zero = float32_is_zero(b);
    let a_is_denormal = float32_is_denormal(a);
    let b_is_denormal = float32_is_denormal(b);

    // ------------------------------------------------------------------
    // Normal-path arithmetic (sec 5.4.1). We compute this even when one of
    // the special-value overrides below will replace it; the wasted work
    // costs a few hundred gates but keeps the control-flow shape provable
    // by structural recursion against the optimised path.
    // ------------------------------------------------------------------

    // 1. Materialise the implicit leading 1 for normals; denormals carry
    //    only the explicit fraction. Effective biased exponent for a
    //    denormal is 1 (per sec 3.4 the value is 2^(1-bias) * frac/2^23).
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
    // Note: when `a_is_zero` is true the operand-zero override at the end
    // discards every value computed from `mant_a_raw` / `exp_a_eff`; same
    // for `b_is_zero`. We still pin `exp_*_eff = 1` for those operands so
    // the alignment math doesn't panic on `a.exponent == 0`.
    let exp_a_eff: u64 = if a_is_denormal | a_is_zero { 1 } else { a.exponent as u64 };
    let exp_b_eff: u64 = if b_is_denormal | b_is_zero { 1 } else { b.exponent as u64 };

    // 2. Align to the larger exponent. Reserve 3 trailing bits for guard /
    //    round / sticky during alignment.
    let mant_a_aligned: u64 = mant_a_raw << 3;
    let mant_b_aligned: u64 = mant_b_raw << 3;
    let mant_a_shifted: u64 = if exp_a_eff >= exp_b_eff {
        mant_a_aligned
    } else {
        shr_sticky(mant_a_aligned, exp_b_eff - exp_a_eff)
    };
    let mant_b_shifted: u64 = if exp_b_eff > exp_a_eff {
        mant_b_aligned
    } else {
        shr_sticky(mant_b_aligned, exp_a_eff - exp_b_eff)
    };
    let mut result_exp: u64 = if exp_a_eff >= exp_b_eff { exp_a_eff } else { exp_b_eff };

    // 3. Combine significands (signed-magnitude).
    let mut result_mant: u64 = 0;
    let mut result_sign: u1 = 0;
    if a.sign == b.sign {
        result_mant = mant_a_shifted + mant_b_shifted;
        result_sign = a.sign;
    } else if mant_a_shifted >= mant_b_shifted {
        result_mant = mant_a_shifted - mant_b_shifted;
        result_sign = a.sign;
    } else {
        result_mant = mant_b_shifted - mant_a_shifted;
        result_sign = b.sign;
    }

    // 4. Overflow normalisation: if a carry pushed the significand into
    //    bit 27, shift right by 1 with sticky preservation and bump the
    //    exponent.
    let overflow_threshold: u64 = (FLOAT32_IMPLICIT_BIT as u64) << 4;
    if result_mant >= overflow_threshold {
        let sticky = result_mant & 1;
        result_mant = (result_mant >> 1) | sticky;
        result_exp = result_exp + 1;
    }

    // 5. Underflow / cancellation normalisation: if the leading 1 is below
    //    bit 26, shift left until we hit the normal position or run out of
    //    exponent.
    let normal_position: u64 = (FLOAT32_IMPLICIT_BIT as u64) << 3;
    if (result_mant != 0) & (result_mant < normal_position) {
        let leading_zeros = count_leading_zeros_u64_loop(result_mant);
        let target_bit: u64 = 26;
        let shift_needed = leading_zeros - (64 - target_bit - 1);
        let max_shift = if result_exp > 1 { result_exp - 1 } else { 0 };
        let actual_shift = if shift_needed <= max_shift { shift_needed } else { max_shift };
        result_mant = result_mant << actual_shift;
        result_exp = result_exp - actual_shift;
    }

    // 6. Detect a subnormal result (sec 3.4: biased exponent 0).
    let mut is_denormal_result = false;
    if (result_exp == 0) | ((result_exp == 1) & (result_mant < normal_position)) {
        result_exp = 0;
        is_denormal_result = true;
    }

    // 7. Round (sec 4.3).
    let guard_bits = result_mant & 0x7;
    result_mant = result_mant >> 3;
    let should_round = should_round_up(guard_bits, result_mant, result_sign, rounding_mode);
    if should_round {
        result_mant = result_mant + 1;
        if result_mant >= ((FLOAT32_IMPLICIT_BIT as u64) << 1) {
            result_mant = result_mant >> 1;
            result_exp = result_exp + 1;
        } else if is_denormal_result & (result_mant >= (FLOAT32_IMPLICIT_BIT as u64)) {
            result_exp = 1;
        }
    }

    // 8. Pack the would-be normal result.
    let result_is_zero = result_mant == 0;
    let final_mantissa: u32 = if is_denormal_result & (result_exp == 0) {
        (result_mant & 0x7FFFFF) as u32
    } else {
        (result_mant & ((FLOAT32_IMPLICIT_BIT - 1) as u64)) as u32
    };
    let mut result = IEEE754Float32 {
        sign: result_sign,
        exponent: result_exp as u8,
        mantissa: final_mantissa,
    };

    // ------------------------------------------------------------------
    // Special-value overrides (last-write-wins, applied in sec 6.x order).
    // ------------------------------------------------------------------

    // sec 6.3 (cancellation-to-zero): magnitudes cancelled; the encoded
    // sign of an exact-zero sum follows the rounding mode.
    if result_is_zero {
        let cancellation_sign: u1 =
            if rounding_mode == ROUNDING_MODE_TOWARD_NEGATIVE { 1 } else { 0 };
        result = float32_zero(cancellation_sign);
    }

    // sec 7.4 (overflow): if rounding pushed `result_exp` past the largest
    // finite, saturate to +/-Inf or +/-max-finite per the directed-rounding
    // matrix.
    let overflows_to_inf = result_exp >= (FLOAT32_EXPONENT_MAX as u64);
    if overflows_to_inf {
        if directed_overflow_saturates_to_inf(rounding_mode, result_sign) {
            result = float32_infinity(result_sign);
        } else {
            result = float32_max_finite(result_sign);
        }
    }

    // sec 6.3 (operand zero): the standard's rule is that if exactly one
    // operand is a zero the sum is the *other* operand, and if both are
    // zeros the sum follows the matching-sign / negative-rounding rule.
    if a_is_zero & b_is_zero {
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

    // sec 6.1 (infinities): inf + finite = inf; same-sign inf + inf = that
    // inf; opposite-sign inf + inf = NaN.
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

    // sec 6.2 (NaN propagation): any NaN input -> canonical quiet NaN.
    if a_is_nan | b_is_nan {
        result = float32_nan();
    }

    result
}

/// Convenience wrapper: round-to-nearest-ties-to-even, the IEEE 754 default.
pub fn add_f32_reference_default(
    a: IEEE754Float32,
    b: IEEE754Float32,
) -> IEEE754Float32 {
    add_f32_reference(a, b, ROUNDING_MODE_NEAREST_EVEN)
}
