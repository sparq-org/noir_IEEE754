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
// Lean equivalence proof — see `circuits/lampe-literate` for the build tool
// that extracts the comment blocks below and runs `lake build` against the
// workspace's shared `Models.lean` / `Subterms.lean` / `Spec.lean`. Generated
// `.lean` files land in a gitignored scratch dir; only this Noir source is
// version-controlled. Method: skeleton-and-specialisations (round 7;
// `proofs/Ieee754/equivalence-spike-2026-05-04.md`).
// ----------------------------------------------------------------------------
//
// ===== LAMPE-LITERATE BEGIN preamble =====
// import ZkpSparql.Ieee754.Equivalence.Models
// import ZkpSparql.Ieee754.Equivalence.Subterms
//
// namespace ZkpSparql.Ieee754.Equivalence
//
// open ZkpSparql.Ieee754.Equivalence.Models
// open ZkpSparql.Ieee754.Equivalence.Subterms
// ===== LAMPE-LITERATE END =====
//
// ===== LAMPE-LITERATE BEGIN proof fn=add_float32_with_rounding name=add_f32_equivalence =====
// /-! ## Inlined-RNE divergence: definitionally equal -/
//
// /-- The optimised path's inlined round-to-nearest-even computation
// is the body of `shouldRoundUp` for `mode = 0`. -/
// theorem shouldRoundUp_inline_eq
//     (guardBits : BitVec 64) (resultMant : BitVec 64)
//     (resultSign : BitVec 1) :
//     shouldRoundUp guardBits resultMant resultSign 0
//       = (decide (guardBits.toNat > 4)
//           || (decide (guardBits = 4) && decide (resultMant &&& 1 = 1))) := by
//   -- Both sides unfold to the same boolean expression.
//   unfold shouldRoundUp
//   simp [modeNearestEven]
//
// /-! ## Diverging-parameter equalities -/
//
// /-- The optimised `clz` parameter equals the reference's: `clzBinary
// = clzLoop` pointwise. Round-5 `Subterms.clz_eq`, taken symmetrically
// and lifted to a function-level equality. -/
// private theorem clz_param_eq : clzBinary = clzLoop := by
//   funext v; exact (clz_eq v).symm
//
// /-- The optimised `rneDecision` parameter (inline-RNE wrapper) equals
// the reference's (`shouldRoundUp`). For `mode = modeNearestEven` both
// sides reduce to the same boolean expression by
// `shouldRoundUp_inline_eq`; for `mode ≠ modeNearestEven` the wrapper
// falls through to `shouldRoundUp` directly. -/
// private theorem rne_param_eq :
//     (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
//       if m = 0 then
//         decide (gb.toNat > 4) ||
//           (decide (gb = 4) && decide (rm &&& 1 = 1))
//       else
//         shouldRoundUp gb rm rs m) = shouldRoundUp := by
//   funext gb rm rs m
//   by_cases hmode : m = 0
//   · subst hmode
//     rw [if_pos rfl]
//     exact (shouldRoundUp_inline_eq gb rm rs).symm
//   · rw [if_neg hmode]
//
// /-! ## Alignment-triple equality
//
// The two alignment functions produce the same `(mantAShift,
// mantBShift, resultExpInit)` triple for every input. The round-6
// 3-way trichotomy on `expA.toNat`/`expB.toNat` reduces each branch to
// a `BitVec 64` equality discharged by `shr_sticky_eq` (unequal
// exponents) or `shrStickyHelper_zero` (equal exponents).
//
// Crucially the trichotomy is *contained* in this lemma — it does not
// rewrite under the long `addF32Skeleton` body. The lemma's goal is a
// ground equality of two triples in `BitVec 64`; `rfl` (after the
// `simp only` rewrite chain has folded the alignment) holds without
// depending on the heartbeat-fragile definitional equality at the
// skeleton level. -/
//
// private theorem align_eq (a b : Float32Bits) :
//     alignF32Optimised a b = alignF32Reference a b := by
//   unfold alignF32Optimised alignF32Reference
//   -- Short-hand for the effective exponents.
//   set expA : BitVec 64 := effectiveExp a with hExpA
//   set expB : BitVec 64 := effectiveExp b with hExpB
//   rcases lt_trichotomy expA.toNat expB.toNat with hlt | heq | hgt
//   · -- expA < expB: optimised takes the `expB > expA` branch
//     -- (`mantA := shrStickyInline mantA (expB - expA)`); reference
//     -- selects `shrStickyHelper mantAAligned (expB - expA)`.
//     have hngeA : ¬ expA.toNat ≥ expB.toNat := by omega
//     have hngtA : ¬ expA.toNat > expB.toNat := by omega
//     have hgtB : expB.toNat > expA.toNat := hlt
//     have hshift_ne : (expB - expA).toNat ≠ 0 := by
//       rw [BitVec.toNat_sub]
//       have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
//       have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
//       omega
//     simp only [Id.run, hngeA, hngtA, hgtB, if_true, if_false,
//                ge_iff_le, Nat.not_le_of_lt, shr_sticky_eq _ _ hshift_ne]
//     rfl
//   · -- expA = expB: both alignments leave the mantissas un-shifted
//     -- (optimised: neither `if`-branch fires; reference:
//     -- `shrStickyHelper _ 0 = id` via `shrStickyHelper_zero`).
//     have hsub : expA - expB = 0 := by
//       apply BitVec.eq_of_toNat_eq
//       rw [BitVec.toNat_sub, heq]
//       have hbound : expB.toNat ≤ 18446744073709551616 :=
//         Nat.le_of_lt (BitVec.isLt _)
//       change _ = (0 : BitVec 64).toNat
//       simp; omega
//     have hsub' : expB - expA = 0 := by
//       apply BitVec.eq_of_toNat_eq
//       rw [BitVec.toNat_sub, ← heq]
//       have hbound : expA.toNat ≤ 18446744073709551616 :=
//         Nat.le_of_lt (BitVec.isLt _)
//       change _ = (0 : BitVec 64).toNat
//       simp; omega
//     have hge : expA.toNat ≥ expB.toNat := Nat.le_of_eq heq.symm
//     have hngtA : ¬ expA.toNat > expB.toNat := by omega
//     have hngtB : ¬ expB.toNat > expA.toNat := by omega
//     have hexp_eq : expA = expB := by
//       apply BitVec.eq_of_toNat_eq; exact heq
//     simp only [Id.run, hngtA, hngtB, hge, ge_iff_le, hsub, hsub',
//                shrStickyHelper_zero, if_true, if_false]
//     rfl
//   · -- expA > expB: optimised takes the `expA > expB` branch
//     -- (`mantB := shrStickyInline mantB (expA - expB)`); reference
//     -- selects `shrStickyHelper mantBAligned (expA - expB)`.
//     have hge : expA.toNat ≥ expB.toNat := Nat.le_of_lt hgt
//     have hngtB : ¬ expB.toNat > expA.toNat := by omega
//     have hshift_ne : (expA - expB).toNat ≠ 0 := by
//       rw [BitVec.toNat_sub]
//       have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
//       have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
//       omega
//     simp only [Id.run, hgt, hngtB, hge, ge_iff_le, if_true, if_false,
//                shr_sticky_eq _ _ hshift_ne]
//     rfl
//
// /-! ## Main theorem
//
// The optimised f32 add is bit-identical to the literal-IEEE-754
// reference f32 add, for every input and every rounding mode.
//
// The proof unfolds both wrappers, rewrites the alignment triple
// (folding the optimised `Id.run`-style alignment into the reference
// form via `align_eq`), and rewrites the two diverging-subterm
// parameters (`clz_param_eq`, `rne_param_eq`); `rfl` then sees both
// sides as the same `addF32Skeleton`-application. -/
//
// theorem add_f32_equivalence
//     (a b : Float32Bits) (mode : BitVec 8) :
//     addF32Optimised a b mode = addF32Reference a b mode := by
//   unfold addF32Optimised addF32Reference
//   rw [align_eq a b, clz_param_eq, rne_param_eq]
//
// end ZkpSparql.Ieee754.Equivalence
// ===== LAMPE-LITERATE END =====
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
