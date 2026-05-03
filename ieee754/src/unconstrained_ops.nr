//! Unconstrained-hint + verified-relation optimisations for IEEE 754 helpers.
//!
//! Pattern: when a function has an expensive in-circuit implementation but a
//! cheap functional spec, compute the answer in an `unconstrained` (Brillig)
//! hint and verify it inside the constraint system with a relation that
//! uniquely characterises the output. The hint contributes zero ACIR gates;
//! only the verifier costs gates.
//!
//! References:
//! - <https://noir-lang.org/docs/noir/concepts/unconstrained>
//! - The companion `noir_XPath` crate's `unconstrained_ops.nr` (the canonical
//!   template for this pattern across Jesse's ZKP-SPARQL workspace).
//!
//! British English is used throughout the documentation.
//!
//! # Bit-width discipline
//!
//! Every shift, mask, and arithmetic operation in this module is annotated
//! with explicit `u<N>` types so that `nargo 1.0.0-beta.17` infers the
//! intended widths without surprise widening or narrowing. In particular,
//! we never write `value & mask` where `value` and `mask` have different
//! `u<N>` types.

use crate::utils::U128;

// ============================================================================
// count_leading_zeros_u23
// ============================================================================

/// Brillig hint: count the number of leading zeros in the low 23 bits of
/// `value`, treating those bits as a 23-bit-wide register.
///
/// Returns `count: u32` such that:
///
/// - if `value & 0x007F_FFFF == 0`: `count == 23`;
/// - otherwise: `count` is the number of zero bits between bit 22 (the top
///   of the 23-bit field) and the most significant set bit, exclusive of
///   the set bit itself. Equivalently `count == 22 - msb_position` where
///   `msb_position` is the index of the highest bit set in `value & 0x007F_FFFF`.
///
/// `value`'s upper bits (bits 23..32) are ignored; the function only looks
/// at the low 23 bits. This matches the IEEE 754 single-precision mantissa
/// subnormal-normalisation use case where the implicit leading bit is not
/// part of the stored mantissa.
///
/// This function is `unconstrained` and contributes no ACIR gates. Its output
/// MUST be validated by `count_leading_zeros_u23_verified` before being
/// trusted.
///
/// Crate-private deliberately: a downstream caller must not be able to bypass
/// the verifier by importing the raw hint. The only sanctioned consumer is
/// `count_leading_zeros_u23_verified` immediately below.
unconstrained fn count_leading_zeros_u23_unconstrained(value: u32) -> u32 {
    // Mask to the low 23 bits we care about.
    let masked: u32 = value & 0x007F_FFFF_u32;

    if masked == 0 {
        // No bits set in the 23-bit field => 23 leading zeros by convention.
        23_u32
    } else {
        // Walk from the top of the 23-bit field downward, returning as
        // soon as we hit the first set bit. `unconstrained` code is free
        // to use early exits and bit-level reasoning, so the procedural
        // shape mirrors a software CLZ implementation directly.
        let mut count: u32 = 0;
        for i in 0..23 {
            let probe_pos: u32 = 22_u32 - (i as u32);
            let probe_bit: u32 = (masked >> probe_pos) & 1_u32;
            if probe_bit == 1_u32 {
                count = i as u32;
                break;
            }
        }
        count
    }
}

/// Constrained verifier: returns `count`, asserting the relation that pins it
/// uniquely to the leading-zero count of the low 23 bits of `value`.
///
/// # Public-input contract
/// - Input: `value: u32`. Only the low 23 bits are inspected.
/// - Output: `count: u32` in the range `0..=23`.
///
/// # SAFETY PROOF (sketch -- not mechanised)
///
/// Let `low23 := value & 0x007F_FFFF`. The verifier asserts the relation
/// `R(value, count)`:
///
/// 1. `count <= 23`.
/// 2. **Zero case**: if `count == 23` then `low23 == 0`.
/// 3. **Non-zero case**: if `count <= 22` then there exists `top_bit_pos`
///    with `top_bit_pos == 22 - count` and:
///      a. bit `top_bit_pos` of `low23` is set, i.e.
///         `(low23 >> top_bit_pos) & 1 == 1`; and
///      b. no bits of `low23` above `top_bit_pos` are set, i.e.
///         `low23 >> (top_bit_pos + 1) == 0`, equivalently
///         `low23 < 2^(top_bit_pos + 1) = 2^(23 - count)`.
///
/// **Uniqueness** (no second `count'` satisfies `R(value, count')`):
///
/// - If `low23 == 0` then clause (3a) cannot hold for any `count <= 22`
///   (no bit is set), so only `count == 23` (clause 2) satisfies `R`.
/// - If `low23 != 0` then `count == 23` is excluded by clause (2). Among
///   the remaining `count <= 22`, clause (3b) bounds `low23` strictly
///   below `2^(23 - count)`; equivalently, the most significant set bit
///   has index strictly less than `23 - count`, i.e. at most `22 - count`.
///   Clause (3a) forces equality at exactly bit `22 - count`. The most
///   significant set bit of a fixed non-zero `low23` is unique (standard
///   binary-representation theorem), so `count` is uniquely determined.
///
/// Therefore exactly one `count` satisfies `R` for any input `value`.
///
/// **Correctness** (the unique `count` matches the spec): by definition of
/// `count_leading_zeros` on a 23-bit register, the spec is `23` for the
/// zero case and `22 - msb_position(low23)` otherwise. Clauses (2) and (3)
/// implement exactly this definition.
///
/// This sketch is a reading aid; the soundness has not been mechanised
/// (the `*_unique` and `*_correct` Lean obligations in
/// `proofs/Ieee754/.../UnconstrainedOps.lean` remain `sorry`-stubbed).
pub fn count_leading_zeros_u23_verified(value: u32) -> u32 {
    // Safety: `verify_clz_u23_relation` enforces the relation that uniquely
    // pins `count` to the leading-zero count of `value & 0x007F_FFFF`; see
    // the SAFETY PROOF block above.
    let count: u32 = unsafe { count_leading_zeros_u23_unconstrained(value) };
    verify_clz_u23_relation(value, count)
}

/// Constrained relation check shared by `count_leading_zeros_u23_verified`
/// and the adversarial tests. Asserts clauses (1), (2), (3a), (3b) of the
/// SAFETY PROOF and returns `count` unchanged on success.
///
/// Private to this module so the assertion error strings remain
/// implementation details. Sharing the helper between production and tests
/// means an adversarial-test failure also flags a regression in the
/// production verifier path.
fn verify_clz_u23_relation(value: u32, count: u32) -> u32 {
    let low23: u32 = value & 0x007F_FFFF_u32;

    // Clause (1): count <= 23.
    assert(count <= 23_u32, "count_leading_zeros_u23: count above 23");

    if count == 23_u32 {
        // Clause (2): zero case.
        assert(low23 == 0_u32, "count_leading_zeros_u23: count==23 but low23 nonzero");
    } else {
        // Clause (3): non-zero case. We have count <= 22 here.
        //
        // top_bit_pos in 0..=22.
        let top_bit_pos: u32 = 22_u32 - count;

        // Clause (3a): bit `top_bit_pos` of low23 is set.
        // `(low23 >> top_bit_pos) & 1 == 1`. Both sides are u32.
        let probe: u32 = (low23 >> top_bit_pos) & 1_u32;
        assert(probe == 1_u32, "count_leading_zeros_u23: leading bit not set");

        // Clause (3b): no bits of low23 are set above `top_bit_pos`.
        // Expressed as a single right-shift comparison: shifting low23
        // right by `top_bit_pos + 1` must yield zero. This avoids
        // constructing `1 << (23 - count)` as a dynamic left-shift,
        // which is expensive in ACIR. The shift amount `top_bit_pos + 1`
        // is in 1..=23, so it stays within u32's 32-bit range.
        let above_shift: u32 = top_bit_pos + 1_u32;
        let above: u32 = low23 >> above_shift;
        assert(above == 0_u32, "count_leading_zeros_u23: bit set above leading position");
    }

    count
}

// ============================================================================
// Tests -- happy paths
// ============================================================================

#[test]
fn test_clz_u23_all_zero() {
    let count: u32 = count_leading_zeros_u23_verified(0_u32);
    assert(count == 23_u32);
}

#[test]
fn test_clz_u23_upper_bits_ignored() {
    // Bits above position 22 are not part of the 23-bit field; the count
    // is determined solely by the low 23 bits.
    let value: u32 = 0xFF80_0000_u32; // bits 23..31 set, low 23 bits zero.
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 23_u32);
}

#[test]
fn test_clz_u23_lsb_only() {
    // Only bit 0 set in the 23-bit field: 22 leading zeros.
    let count: u32 = count_leading_zeros_u23_verified(1_u32);
    assert(count == 22_u32);
}

#[test]
fn test_clz_u23_msb_only() {
    // Only bit 22 (top of the 23-bit field) set: 0 leading zeros.
    let value: u32 = 1_u32 << 22_u32;
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 0_u32);
}

#[test]
fn test_clz_u23_full_low23() {
    // All 23 low bits set: 0 leading zeros (bit 22 is set).
    let count: u32 = count_leading_zeros_u23_verified(0x007F_FFFF_u32);
    assert(count == 0_u32);
}

#[test]
fn test_clz_u23_middle_bit() {
    // Only bit 10 set: leading zeros = 22 - 10 = 12.
    let value: u32 = 1_u32 << 10_u32;
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 12_u32);
}

#[test]
fn test_clz_u23_bit_pattern() {
    // Bits 5 and 17 set => msb position = 17 => count = 22 - 17 = 5.
    let value: u32 = (1_u32 << 17_u32) | (1_u32 << 5_u32);
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 5_u32);
}

#[test]
fn test_clz_u23_bit_21() {
    // Only bit 21 set: count = 22 - 21 = 1.
    let value: u32 = 1_u32 << 21_u32;
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 1_u32);
}

#[test]
fn test_clz_u23_high_bits_plus_low23() {
    // Upper bits set together with a low-23 pattern: count is determined
    // only by the low 23 bits. Set bits 30 (ignored) and 7 (counted).
    let value: u32 = (1_u32 << 30_u32) | (1_u32 << 7_u32);
    let count: u32 = count_leading_zeros_u23_verified(value);
    assert(count == 22_u32 - 7_u32); // 15
}

// ============================================================================
// Tests -- adversarial: each isolates one verifier clause
// ============================================================================
//
// Each `hint_clz_u23_*` generator produces a deliberately corrupt
// unconstrained witness for a single tampering mode; the matching test
// feeds it through `verify_clz_u23_relation` and asserts that the
// expected error string fires. Sharing `verify_clz_u23_relation` between
// production and tests means a regression in the production verifier
// path would be caught here too.

/// Always-23 hint: claims `count = 23` regardless of input.
unconstrained fn hint_clz_u23_always_23(_value: u32) -> u32 {
    23_u32
}

/// Out-of-range hint: returns 24 (above the 23 ceiling).
unconstrained fn hint_clz_u23_out_of_range(_value: u32) -> u32 {
    24_u32
}

/// Off-by-one-too-small hint: returns `correct - 1` for a non-zero input.
/// For `value == 1` the correct count is 22; we return 21, which fails
/// clause (3a) -- bit `(22 - 21) = 1` is not set in `0x1`.
unconstrained fn hint_clz_u23_too_small(_value: u32) -> u32 {
    21_u32
}

/// Off-by-one-too-large hint: returns `correct + 1` for a non-zero input.
/// For `value == 1` the correct count is 22; returning 23 falsely claims
/// the all-zero case and triggers clause (2).
unconstrained fn hint_clz_u23_falsely_zero(_value: u32) -> u32 {
    23_u32
}

#[test]
fn test_clz_u23_hint_always_23_passes_for_zero() {
    // The always-23 hint *happens* to be correct when low23 == 0, so the
    // verifier should accept it. Sanity check that the harness works.
    // Safety: adversarial test path; we accept this only because
    // `value == 0` is the canonical zero case and the verifier confirms it.
    let count: u32 = unsafe { hint_clz_u23_always_23(0_u32) };
    let returned: u32 = verify_clz_u23_relation(0_u32, count);
    assert(returned == 23_u32);
}

#[test(should_fail_with = "count above 23")]
fn test_clz_u23_hint_out_of_range_fails() {
    // Clause (1): count must be <= 23.
    // Safety: adversarial path; the verifier is expected to reject.
    let count: u32 = unsafe { hint_clz_u23_out_of_range(0_u32) };
    let _ = verify_clz_u23_relation(0_u32, count);
}

#[test(should_fail_with = "count==23 but low23 nonzero")]
fn test_clz_u23_hint_falsely_zero_fails() {
    // Clause (2): if count == 23 then low23 must be zero. Feeding a
    // non-zero input with count == 23 should trip this clause.
    // Safety: adversarial path.
    let count: u32 = unsafe { hint_clz_u23_falsely_zero(1_u32) };
    let _ = verify_clz_u23_relation(1_u32, count);
}

#[test(should_fail_with = "leading bit not set")]
fn test_clz_u23_hint_too_small_fails() {
    // For value == 1 the correct count is 22; hint_clz_u23_too_small
    // returns 21. Then top_bit_pos = 22 - 21 = 1, but bit 1 of 0x1 is 0,
    // so clause (3a) fires.
    // Safety: adversarial path.
    let count: u32 = unsafe { hint_clz_u23_too_small(1_u32) };
    let _ = verify_clz_u23_relation(1_u32, count);
}

#[test(should_fail_with = "bit set above leading position")]
fn test_clz_u23_hint_bit_above_fails() {
    // Manually craft a (value, count) pair that satisfies clauses (1),
    // (2), and (3a) but violates clause (3b): a bit set above the
    // leading position.
    //
    // Take low23 with bits 5 and 10 set. The true count is 22 - 10 = 12.
    // Feeding the verifier `count = 17` would put `top_bit_pos = 5`:
    //   - clause (3a) holds: bit 5 is set;
    //   - clause (3b) requires low23 < 2^(23 - 17) = 2^6 = 64, but
    //     low23 = (1 << 10) | (1 << 5) = 1056 >= 64, so (3b) fires.
    // Safety: adversarial path; the wrong-count witness is intentional.
    let value: u32 = (1_u32 << 10_u32) | (1_u32 << 5_u32);
    let count: u32 = 17_u32;
    let _ = verify_clz_u23_relation(value, count);
}
// ============================================================================
// shift_right_sticky_u64
// ============================================================================

/// Brillig hint: compute the quotient, remainder, and sticky bit of the
/// "right shift with sticky" operation on a 64-bit value.
///
/// Given `value: u64` and `shift: u64`, returns `(quotient, remainder, sticky)`
/// such that:
///
/// - if `shift == 0`: `quotient == value`, `remainder == 0`, `sticky == 0`;
/// - if `1 <= shift <= 63`: `quotient == value >> shift`,
///   `remainder == value & ((1 << shift) - 1)`,
///   `sticky == (remainder != 0) as u1`;
/// - if `shift >= 64`: `quotient == 0`, `remainder == value`,
///   `sticky == (value != 0) as u1`.
///
/// The combined return shape mirrors the existing in-circuit
/// `shift_right_sticky_u64(value, shift)` baseline, which encodes the result
/// as `quotient | (sticky as u64)` after the shift. Returning the raw
/// `(quotient, remainder, sticky)` triple from the unconstrained hint lets the
/// verifier check the algebraic relation directly and lets the wrapper
/// recombine the encoded result.
///
/// This function is `unconstrained` and contributes no ACIR gates. Its output
/// MUST be validated by `shift_right_sticky_u64_verified` before being
/// trusted.
///
/// Crate-private deliberately: a downstream caller must not be able to bypass
/// the verifier by importing the raw hint. The only sanctioned consumer is
/// `shift_right_sticky_u64_verified` immediately below.
unconstrained fn shift_right_sticky_u64_unconstrained(value: u64, shift: u64) -> (u64, u64, u1) {
    if shift == 0_u64 {
        (value, 0_u64, 0_u1)
    } else if shift >= 64_u64 {
        let sticky: u1 = if value != 0_u64 { 1_u1 } else { 0_u1 };
        (0_u64, value, sticky)
    } else {
        // 1 <= shift <= 63 here.
        let mask: u64 = (1_u64 << shift) - 1_u64;
        let remainder: u64 = value & mask;
        let quotient: u64 = value >> shift;
        let sticky: u1 = if remainder != 0_u64 { 1_u1 } else { 0_u1 };
        (quotient, remainder, sticky)
    }
}

/// Constrained verifier: returns the right-shifted-with-sticky encoding of
/// `value` by `shift`, asserting the relation that uniquely pins the witnessed
/// quotient, remainder and sticky bit.
///
/// # Public-input contract
/// - Input: `value: u64`, `shift: u64`.
/// - Output: `u64` matching the in-tree `shift_right_sticky_u64(value, shift)`
///   baseline, namely `quotient | (sticky as u64)`.
///
/// # SAFETY PROOF (sketch -- not mechanised)
///
/// The verifier asserts the relation `R(value, shift, quotient, remainder, sticky)`:
///
/// 1. **`shift == 0` case**: `quotient == value`, `remainder == 0`,
///    `sticky == 0`.
/// 2. **`shift >= 64` case** (`shift` interpreted as a u64; we require the
///    caller's high bits of `shift` to be zero, i.e. `shift <= 64` here for
///    the verifier to make sense): `quotient == 0`, `remainder == value`,
///    `sticky == (value != 0)`.
/// 3. **`1 <= shift <= 63` case**, with `pow2 := 1 << shift`:
///      a. **Reconstruction**:
///         `value == quotient * pow2 + remainder` (over `Field`, so no u64
///         wrap).
///      b. **Bound**: `remainder < pow2`.
///      c. **Sticky direction**:
///         - `(1 - sticky) * remainder == 0` (i.e. `sticky == 0 => remainder == 0`);
///         - there exists a witnessed `remainder_inv: Field` with
///           `remainder * remainder_inv == sticky as Field` (i.e.
///           `remainder != 0 => sticky == 1`).
/// 4. `sticky in {0, 1}` (encoded by the `u1` type at the witness boundary).
///
/// We deliberately accept any `shift: u64` (not just `shift <= 64`) to match
/// the in-tree `shift_right_sticky_u64(value, shift)` baseline's
/// drop-in semantics; any `shift >= 64` collapses to the "all bits shifted
/// out" case, which the verifier handles uniformly.
///
/// **Uniqueness** of `(quotient, remainder, sticky)` for a fixed
/// `(value, shift)`:
///
/// - `shift == 0` and `shift >= 64` cases have only one solution by the
///   conditions stated.
/// - `1 <= shift <= 63` case: clauses (3a) + (3b) are the standard Euclidean
///   division of `value` by `pow2`, which uniquely determines `(quotient,
///   remainder)`. Clause (3c) then uniquely determines `sticky`:
///   if `remainder == 0` the inverse witness forces `sticky == 0` via
///   `0 * inv == sticky`, and the `(1 - sticky) * remainder == 0` clause is
///   trivially satisfied; if `remainder != 0` the `(1 - sticky) * remainder
///   == 0` clause forces `sticky == 1`, and the inverse witness must equal
///   `remainder^{-1}` to satisfy the multiplicative clause.
///
/// **Correctness**: by definition of right-shift-with-sticky on a 64-bit
/// register, the spec is the encoding above; clauses (1)/(2)/(3) implement
/// exactly this definition, matching the Lean spec `Spec.shr_sticky_u64` in
/// `proofs/Ieee754/.../UnconstrainedOps.lean`.
///
/// This sketch is a reading aid; the soundness has not been mechanised
/// (the `shr_sticky_u64_unique` and `shr_sticky_u64_correct` Lean obligations
/// remain `sorry`-stubbed).
pub fn shift_right_sticky_u64_verified(value: u64, shift: u64) -> u64 {
    // Safety: `verify_shr_sticky_u64_relation` enforces the relation that
    // uniquely pins `(quotient, remainder, sticky)`; see SAFETY PROOF above.
    let (quotient, remainder, sticky): (u64, u64, u1) =
        unsafe { shift_right_sticky_u64_unconstrained(value, shift) };
    verify_shr_sticky_u64_relation(value, shift, quotient, remainder, sticky);
    quotient | (sticky as u64)
}

/// Constrained relation check shared by `shift_right_sticky_u64_verified`
/// and the adversarial tests. Asserts the SAFETY PROOF clauses and returns
/// nothing (the caller already has `quotient`, `remainder`, `sticky`).
///
/// Private to this module so the assertion error strings remain
/// implementation details. Sharing the helper between production and tests
/// means an adversarial-test failure also flags a regression in the
/// production verifier path.
fn verify_shr_sticky_u64_relation(
    value: u64,
    shift: u64,
    quotient: u64,
    remainder: u64,
    sticky: u1,
) {
    if shift == 0_u64 {
        // Clause (1): no shift -- quotient is value, no bits shifted out.
        assert(quotient == value, "shift_right_sticky_u64: shift==0 quotient mismatch");
        assert(remainder == 0_u64, "shift_right_sticky_u64: shift==0 remainder nonzero");
        assert(sticky == 0_u1, "shift_right_sticky_u64: shift==0 sticky set");
    } else if shift >= 64_u64 {
        // Clause (2): all bits shifted out -- quotient is 0, remainder is the
        // entire value, sticky tracks whether anything was shifted out.
        assert(quotient == 0_u64, "shift_right_sticky_u64: shift>=64 quotient nonzero");
        assert(remainder == value, "shift_right_sticky_u64: shift>=64 remainder mismatch");
        // sticky == (value != 0): use the existence-of-inverse trick.
        let value_f: Field = value as Field;
        let sticky_f: Field = sticky as Field;
        // (1 - sticky) * value == 0  : sticky == 0 => value == 0.
        assert(
            (1_u64 - (sticky as u64)) as Field * value_f == 0,
            "shift_right_sticky_u64: shift>=64 sticky==0 but value nonzero",
        );
        // value * value_inv == sticky : value != 0 => sticky == 1.
        // Witness `value_inv` via the unconstrained inverse hint.
        let value_inv: Field = unsafe { field_inv_or_zero(value_f) };
        assert(
            value_f * value_inv == sticky_f,
            "shift_right_sticky_u64: shift>=64 sticky direction wrong",
        );
    } else {
        // Clause (3): 1 <= shift <= 63.
        //
        // pow2 = 1 << shift, in [2, 2^63]. The shift amount type matches the
        // LHS u64 width per Noir 1.0.0-beta.17 typing rules; the upper bits
        // of `shift` are zero by the case guard.
        let pow2: u64 = 1_u64 << shift;

        // Clause (3a): reconstruction over Field (avoids u64 wrap on the
        // product `quotient * pow2`, which can be up to 2^64 * 2^63 = 2^127).
        let value_f: Field = value as Field;
        let quotient_f: Field = quotient as Field;
        let pow2_f: Field = pow2 as Field;
        let remainder_f: Field = remainder as Field;
        assert(
            value_f == quotient_f * pow2_f + remainder_f,
            "shift_right_sticky_u64: reconstruction failed",
        );

        // Clause (3b): remainder < pow2. Both sides are u64 here.
        assert(remainder < pow2, "shift_right_sticky_u64: remainder above pow2");

        // Clause (3c): sticky direction -- pinned by two constraints plus a
        // witnessed Field inverse hint.
        let sticky_f: Field = sticky as Field;
        // (1 - sticky) * remainder == 0 : sticky == 0 => remainder == 0.
        assert(
            (1_u64 - (sticky as u64)) as Field * remainder_f == 0,
            "shift_right_sticky_u64: sticky==0 but remainder nonzero",
        );
        // remainder * remainder_inv == sticky : remainder != 0 => sticky == 1.
        let remainder_inv: Field = unsafe { field_inv_or_zero(remainder_f) };
        assert(
            remainder_f * remainder_inv == sticky_f,
            "shift_right_sticky_u64: sticky direction wrong",
        );
    }
}

/// Brillig hint: returns the multiplicative inverse of `x` in the Field, or
/// `0` if `x == 0`. The verifier never trusts this output -- it merely uses
/// it as a witness in the `x * x_inv == indicator` constraint pattern that
/// pins the indicator to `(x != 0)`.
///
/// Crate-private. Sanctioned consumers: the `verify_shr_sticky_u64_relation`
/// verifier above.
unconstrained fn field_inv_or_zero(x: Field) -> Field {
    if x == 0 {
        0
    } else {
        1 / x
    }
}

// ============================================================================
// Tests -- happy paths (shr_sticky_u64)
// ============================================================================

#[test]
fn test_shr_sticky_u64_zero_shift() {
    let result: u64 = shift_right_sticky_u64_verified(0xDEAD_BEEF_u64, 0_u64);
    assert(result == 0xDEAD_BEEF_u64);
}

#[test]
fn test_shr_sticky_u64_zero_value() {
    // Shifting zero by anything is zero with no sticky.
    let result: u64 = shift_right_sticky_u64_verified(0_u64, 5_u64);
    assert(result == 0_u64);
    let result_big: u64 = shift_right_sticky_u64_verified(0_u64, 64_u64);
    assert(result_big == 0_u64);
    let result_huge: u64 = shift_right_sticky_u64_verified(0_u64, 100_u64);
    assert(result_huge == 0_u64);
}

#[test]
fn test_shr_sticky_u64_clean_shift() {
    // 0b1000 >> 3 == 1, no bits shifted out, sticky == 0.
    let result: u64 = shift_right_sticky_u64_verified(8_u64, 3_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_with_sticky() {
    // 0b1011 >> 2 == 0b10 (= 2), bits 1..0 == 0b11 shifted out so sticky == 1.
    // Encoded result: quotient | sticky = 0b10 | 1 = 0b11 = 3.
    let result: u64 = shift_right_sticky_u64_verified(11_u64, 2_u64);
    assert(result == 3_u64);
}

#[test]
fn test_shr_sticky_u64_shift_one_clean() {
    // 0b10 >> 1 == 1, bit 0 == 0, sticky == 0.
    let result: u64 = shift_right_sticky_u64_verified(2_u64, 1_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_shift_one_dirty() {
    // 0b11 >> 1 == 1, bit 0 == 1, sticky == 1; encoded == 1 | 1 == 1.
    let result: u64 = shift_right_sticky_u64_verified(3_u64, 1_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_shift_63() {
    // value = 1 << 63: quotient = 1, remainder = 0, sticky = 0.
    let value: u64 = 1_u64 << 63_u64;
    let result: u64 = shift_right_sticky_u64_verified(value, 63_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_shift_63_with_sticky() {
    // value = (1 << 63) | 1: quotient = 1, remainder = 1, sticky = 1.
    // Encoded = 1 | 1 == 1.
    let value: u64 = (1_u64 << 63_u64) | 1_u64;
    let result: u64 = shift_right_sticky_u64_verified(value, 63_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_shift_64_nonzero() {
    // shift == 64: everything shifted out. Quotient = 0, remainder = value,
    // sticky = (value != 0) = 1; encoded == 0 | 1 == 1.
    let result: u64 = shift_right_sticky_u64_verified(0xDEAD_BEEF_u64, 64_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u64_matches_baseline_clean() {
    // Cross-check against the in-tree baseline on a dirty mid-shift case.
    // value = 0xABCD_EF01_u64, shift = 12: quotient = 0xABCDE, remainder =
    // 0xF01 != 0 so sticky = 1. Encoded = 0xABCDE | 1 = 0xABCDF.
    let value: u64 = 0xABCD_EF01_u64;
    let baseline: u64 = crate::utils::shift_right_sticky_u64(value, 12_u64);
    let verified: u64 = shift_right_sticky_u64_verified(value, 12_u64);
    assert(verified == baseline);
}

#[test]
fn test_shr_sticky_u64_matches_baseline_low_bits_zero() {
    // Bits below the shift are zero, so sticky == 0 even for a dynamic shift.
    let value: u64 = 0xABCD_E000_u64;
    let baseline: u64 = crate::utils::shift_right_sticky_u64(value, 12_u64);
    let verified: u64 = shift_right_sticky_u64_verified(value, 12_u64);
    assert(verified == baseline);
}

// ============================================================================
// Tests -- adversarial (shr_sticky_u64)
// ============================================================================
//
// Each adversarial path exercises one verifier clause. Sharing
// `verify_shr_sticky_u64_relation` between production and tests means a
// regression in the production verifier path would be caught here too.

#[test(should_fail_with = "shift==0 quotient mismatch")]
fn test_shr_sticky_u64_bad_quotient_zero_shift() {
    // shift == 0: any (quotient != value) tampering is caught.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0xABCD_u64, 0_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "shift==0 sticky set")]
fn test_shr_sticky_u64_bad_sticky_zero_shift() {
    // shift == 0 with quotient correct but sticky set is rejected.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0xABCD_u64, 0_u64, 0xABCD_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "reconstruction failed")]
fn test_shr_sticky_u64_bad_reconstruction() {
    // value = 8, shift = 2: true (q, r, s) = (2, 0, 0). Feeding (3, 0, 0)
    // breaks reconstruction: 3 * 4 + 0 == 12 != 8.
    // Safety: adversarial path; we feed a deliberately-wrong quotient.
    verify_shr_sticky_u64_relation(8_u64, 2_u64, 3_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "remainder above pow2")]
fn test_shr_sticky_u64_bad_remainder_above_pow2() {
    // value = 12, shift = 2, pow2 = 4: a malicious witness could try
    // (q, r) = (2, 4). Reconstruction holds (2*4 + 4 == 12), but
    // remainder == pow2 violates the bound. The verifier rejects.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(12_u64, 2_u64, 2_u64, 4_u64, 1_u1);
}

#[test(should_fail_with = "sticky==0 but remainder nonzero")]
fn test_shr_sticky_u64_bad_sticky_zero_with_remainder() {
    // value = 11, shift = 2: true (q, r, s) = (2, 3, 1). Feeding sticky == 0
    // is rejected by the (1 - sticky) * remainder == 0 clause.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(11_u64, 2_u64, 2_u64, 3_u64, 0_u1);
}

#[test(should_fail_with = "sticky direction wrong")]
fn test_shr_sticky_u64_bad_sticky_one_with_zero_remainder() {
    // value = 8, shift = 2: true (q, r, s) = (2, 0, 0). Feeding sticky == 1
    // is rejected by the remainder * remainder_inv == sticky clause:
    // 0 * inv == 0 != 1.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(8_u64, 2_u64, 2_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "shift>=64 quotient nonzero")]
fn test_shr_sticky_u64_bad_quotient_shift_64() {
    // shift == 64: quotient must be 0.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0_u64, 64_u64, 1_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "shift>=64 remainder mismatch")]
fn test_shr_sticky_u64_bad_remainder_shift_64() {
    // shift == 64: remainder must equal value.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0xABCD_u64, 64_u64, 0_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "shift>=64 sticky==0 but value nonzero")]
fn test_shr_sticky_u64_bad_sticky_zero_shift_64() {
    // shift == 64, value != 0, sticky claimed 0 -- rejected.
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0xABCD_u64, 64_u64, 0_u64, 0xABCD_u64, 0_u1);
}

#[test(should_fail_with = "shift>=64 sticky direction wrong")]
fn test_shr_sticky_u64_bad_sticky_one_value_zero_shift_64() {
    // shift == 64, value == 0, sticky claimed 1 -- rejected by the
    // existence-of-inverse clause `value * value_inv == sticky` (0 * inv == 0
    // != 1). This isolates the second sticky-direction constraint in the
    // shift >= 64 branch (mirrors the `< 64` adversarial test
    // `bad_sticky_one_with_zero_remainder`).
    // Safety: adversarial path.
    verify_shr_sticky_u64_relation(0_u64, 64_u64, 0_u64, 0_u64, 1_u1);
}

#[test]
fn test_shr_sticky_u64_shift_far_above_64() {
    // Drop-in compatibility with the baseline: very large shifts collapse to
    // the "all bits shifted out" case. value != 0 so sticky == 1, encoded
    // result == 0 | 1 == 1.
    let result: u64 = shift_right_sticky_u64_verified(0xABCD_u64, 1000_u64);
    assert(result == 1_u64);
}

// ============================================================================
// shift_right_sticky_u128
// ============================================================================
//
// The 128-bit variant mirrors the u64 verifier but operates on a `U128`
// (a pair of u64s) and consumes a `u64` shift amount. The output is `u64` --
// the baseline truncates the shifted value to the low 64 bits and OR-folds
// any non-zero shifted-out bits into a sticky bit. The four cases (shift==0,
// 1<=shift<64, 64<=shift<128, shift>=128) match the in-tree
// `crate::utils::shift_right_sticky_u128` baseline byte-for-byte.

/// Brillig hint: compute `(quotient, remainder, high_top, sticky)` for the
/// "right shift with sticky" operation on a 128-bit value.
///
/// Returns:
/// - `quotient: u64` -- the low-64-bit view of `value >> shift` (matching the
///   baseline's truncation behaviour);
/// - `remainder: u64` -- bits below position `shift` of the operand piece
///   that drives the sticky bit; semantics depend on the branch (see below);
/// - `high_top: u64` -- bits above position `shift+64` of the original
///   128-bit value, captured as a u64 witness for the Field-reconstruction
///   constraint in the `1 <= shift < 64` branch (zero in the other branches);
/// - `sticky: u1` -- 1 iff any bit was shifted out of the result.
///
/// Per branch:
///
/// - `shift == 0`: `quotient == val.low`, `remainder == 0`, `high_top == 0`,
///   `sticky == 0`. Note that `val.high` is silently dropped, matching the
///   baseline's drop-in semantics for the only call sites that pass `shift==0`.
/// - `1 <= shift <= 63`: with `pow2 := 1 << shift`,
///   `value_field := val.high * 2^64 + val.low` and `pow2_top := 2^(64+shift)`,
///   `value_field == high_top * pow2_top + quotient * pow2 + remainder` with
///   `0 <= remainder < pow2` and `0 <= quotient < 2^64`. `sticky == 1`
///   iff `remainder != 0`.
/// - `64 <= shift <= 127`: with `eff := shift - 64` (in `0..=63`) and
///   `pow2_eff := 1 << eff`, `val.high == quotient * pow2_eff + remainder`
///   with `0 <= remainder < pow2_eff`. `high_top == 0`. `sticky == 1`
///   iff `(val.low != 0) | (remainder != 0)`.
/// - `shift >= 128`: `quotient == 0`, `remainder == 0`, `high_top == 0`.
///   `sticky == 1` iff `(val.high != 0) | (val.low != 0)`.
///
/// This function is `unconstrained` and contributes no ACIR gates. Its output
/// MUST be validated by `shift_right_sticky_u128_verified` before being
/// trusted.
///
/// Crate-private deliberately: a downstream caller must not be able to bypass
/// the verifier by importing the raw hint. The only sanctioned consumer is
/// `shift_right_sticky_u128_verified` immediately below.
unconstrained fn shift_right_sticky_u128_unconstrained(
    val: U128,
    shift: u64,
) -> (u64, u64, u64, u1) {
    if shift == 0_u64 {
        // val.high is silently dropped to match the baseline.
        (val.low, 0_u64, 0_u64, 0_u1)
    } else if shift >= 128_u64 {
        let nonzero: u1 = if (val.high != 0_u64) | (val.low != 0_u64) {
            1_u1
        } else {
            0_u1
        };
        (0_u64, 0_u64, 0_u64, nonzero)
    } else if shift >= 64_u64 {
        // 64 <= shift <= 127, so eff := shift - 64 in 0..=63.
        let eff: u64 = shift - 64_u64;
        let pow2_eff: u64 = 1_u64 << eff;
        // When eff == 0, pow2_eff == 1 and the mask is 0 -> remainder == 0,
        // quotient == val.high. The expression below handles this uniformly
        // because `(1_u64 << 0_u64) - 1_u64 == 0_u64`.
        let mask: u64 = pow2_eff - 1_u64;
        let remainder: u64 = val.high & mask;
        let quotient: u64 = val.high >> eff;
        let sticky: u1 = if (val.low != 0_u64) | (remainder != 0_u64) {
            1_u1
        } else {
            0_u1
        };
        (quotient, remainder, 0_u64, sticky)
    } else {
        // 1 <= shift <= 63 here.
        let pow2: u64 = 1_u64 << shift;
        let mask: u64 = pow2 - 1_u64;
        // Bits below position `shift` in val.low drive the sticky bit.
        let remainder: u64 = val.low & mask;
        // Low part of the shifted result: `val.low >> shift`. Width: u64.
        let q_low_part: u64 = val.low >> shift;
        // High part of the shifted result: `val.high << (64 - shift)`,
        // truncated to u64 by the wrapping shift (the dropped bits are
        // accounted for by `high_top` below).
        let inv_shift: u64 = 64_u64 - shift;
        let q_high_part: u64 = val.high << inv_shift;
        let quotient: u64 = q_low_part | q_high_part;
        // `high_top` captures the bits of val.high that were dropped by the
        // u64-truncation in `q_high_part`. The Field reconstruction
        //     V = high_top * 2^(64+shift) + quotient * 2^shift + remainder
        // (with V := val.high * 2^64 + val.low) forces
        // `high_top == val.high >> shift`, which we mirror in the hint.
        // See the SAFETY PROOF on `shift_right_sticky_u128_verified` for the
        // derivation.
        let high_top: u64 = val.high >> shift;
        let sticky: u1 = if remainder != 0_u64 { 1_u1 } else { 0_u1 };
        (quotient, remainder, high_top, sticky)
    }
}

/// Constrained verifier: returns the right-shifted-with-sticky encoding of the
/// 128-bit value `val` by `shift`, asserting the relation that uniquely pins
/// the witnessed `(quotient, remainder, high_top, sticky)`.
///
/// # Public-input contract
/// - Input: `val: U128`, `shift: u64`.
/// - Output: `u64` matching the in-tree `shift_right_sticky_u128(val, shift)`
///   baseline, namely `quotient | (sticky as u64)`.
///
/// # SAFETY PROOF (sketch -- not mechanised)
///
/// The verifier asserts the relation `R(val, shift, quotient, remainder,
/// high_top, sticky)` per branch:
///
/// 1. **`shift == 0` case**: `quotient == val.low`, `remainder == 0`,
///    `high_top == 0`, `sticky == 0`. (`val.high` is silently dropped to
///    match the baseline.)
/// 2. **`shift >= 128` case**: `quotient == 0`, `remainder == 0`,
///    `high_top == 0`, `sticky == ((val.high != 0) | (val.low != 0))`,
///    pinned via `combined := val.high + val.low` (sum < 2^65, no Field wrap)
///    and the existence-of-inverse trick:
///      - `(1 - sticky) * combined == 0`;
///      - `combined * combined_inv == sticky`.
/// 3. **`64 <= shift <= 127` case**, with `eff := shift - 64` (in `0..=63`)
///    and `pow2_eff := 1 << eff`:
///      a. `val.high == quotient * pow2_eff + remainder` (over `Field`);
///      b. `remainder < pow2_eff`;
///      c. `high_top == 0`;
///      d. `sticky == ((val.low != 0) | (remainder != 0))`, pinned via
///         `combined := val.low + remainder` and the same trick as case 2.
/// 4. **`1 <= shift <= 63` case**, with `pow2 := 1 << shift`,
///    `pow2_top := 2^(64+shift)` and
///    `value_field := val.high * 2^64 + val.low`:
///      a. **Reconstruction**:
///         `value_field == high_top * pow2_top + quotient * pow2 + remainder`
///         (over `Field`).
///      b. **Bound on remainder**: `remainder < pow2`.
///      c. **Sticky direction**:
///         - `(1 - sticky) * remainder == 0`;
///         - `remainder * remainder_inv == sticky`.
///      d. `quotient < 2^64` and `high_top < 2^64` are enforced by the
///         witness types (`u64`).
/// 5. `sticky in {0, 1}` (encoded by the `u1` type at the witness boundary).
///
/// **Soundness of the `Field` reconstruction in case 4.** The LHS
/// `value_field` is bounded by `2^128 - 1`; the RHS terms are bounded by
/// `2^64 * 2^(64+63) + 2^64 * 2^63 + 2^63 < 2^192`, well below the BN254
/// modulus (~2^254). Hence no Field-wrap can substitute a different
/// `(quotient, remainder, high_top)` triple for the true Euclidean
/// decomposition.
///
/// **Uniqueness** of `(quotient, remainder, high_top, sticky)` for fixed
/// `(val, shift)`:
///
/// - Case 1 and case 2 each have only one solution by direct equality
///   constraints plus the existence-of-inverse trick.
/// - Case 3: clauses (3a)+(3b) are the standard Euclidean division of
///   `val.high` by `pow2_eff`, which uniquely determines
///   `(quotient, remainder)`. Clauses (3c)+(3d) determine `high_top` and
///   `sticky`.
/// - Case 4: clauses (4a)+(4b)+(4d) form a base-`(2^shift, 2^(64+shift))`
///   Euclidean decomposition with the standard uniqueness theorem applied
///   in two stages -- first decompose `value_field` modulo `pow2_top`
///   (uniquely splitting off `high_top`), then decompose the residue modulo
///   `pow2` (uniquely splitting off `remainder` from `quotient`). Clause (4c)
///   determines `sticky`.
///
/// **Correctness**: by definition of the in-tree
/// `shift_right_sticky_u128(val, shift)` baseline, the spec is the encoding
/// above; the per-branch clauses implement exactly that definition.
///
/// This sketch is a reading aid; the soundness has not been mechanised
/// (no current Lean obligations exist for u128 -- the workspace `proofs/`
/// tree only stubs the u64 variant. Adding `shr_sticky_u128_unique` /
/// `shr_sticky_u128_correct` Lean stubs is a follow-up workspace round if
/// this primitive ships).
pub fn shift_right_sticky_u128_verified(val: U128, shift: u64) -> u64 {
    // Safety: `verify_shr_sticky_u128_relation` enforces the relation that
    // uniquely pins `(quotient, remainder, high_top, sticky)`; see SAFETY
    // PROOF above.
    let (quotient, remainder, high_top, sticky): (u64, u64, u64, u1) =
        unsafe { shift_right_sticky_u128_unconstrained(val, shift) };
    verify_shr_sticky_u128_relation(val, shift, quotient, remainder, high_top, sticky);
    quotient | (sticky as u64)
}

/// Constrained relation check shared by `shift_right_sticky_u128_verified`
/// and the adversarial tests. Asserts the SAFETY PROOF clauses.
///
/// Private to this module so the assertion error strings remain
/// implementation details. Sharing the helper between production and tests
/// means an adversarial-test failure also flags a regression in the
/// production verifier path.
fn verify_shr_sticky_u128_relation(
    val: U128,
    shift: u64,
    quotient: u64,
    remainder: u64,
    high_top: u64,
    sticky: u1,
) {
    if shift == 0_u64 {
        // Clause (1): no shift -- quotient is val.low (val.high silently
        // dropped to match baseline), no bits shifted out.
        assert(quotient == val.low, "shift_right_sticky_u128: shift==0 quotient mismatch");
        assert(remainder == 0_u64, "shift_right_sticky_u128: shift==0 remainder nonzero");
        assert(high_top == 0_u64, "shift_right_sticky_u128: shift==0 high_top nonzero");
        assert(sticky == 0_u1, "shift_right_sticky_u128: shift==0 sticky set");
    } else if shift >= 128_u64 {
        // Clause (2): all bits shifted out.
        assert(quotient == 0_u64, "shift_right_sticky_u128: shift>=128 quotient nonzero");
        assert(remainder == 0_u64, "shift_right_sticky_u128: shift>=128 remainder nonzero");
        assert(high_top == 0_u64, "shift_right_sticky_u128: shift>=128 high_top nonzero");
        // sticky == ((val.high | val.low) != 0). Pinned via combined sum.
        // val.high + val.low fits in 2^65 -- well under the BN254 modulus, so
        // (a+b)==0 over Field iff both u64 summands are zero.
        let high_f: Field = val.high as Field;
        let low_f: Field = val.low as Field;
        let combined_f: Field = high_f + low_f;
        let sticky_f: Field = sticky as Field;
        // (1 - sticky) * combined == 0  : sticky == 0 => val == 0.
        assert(
            (1_u64 - (sticky as u64)) as Field * combined_f == 0,
            "shift_right_sticky_u128: shift>=128 sticky==0 but value nonzero",
        );
        // combined * combined_inv == sticky : val != 0 => sticky == 1.
        let combined_inv: Field = unsafe { field_inv_or_zero(combined_f) };
        assert(
            combined_f * combined_inv == sticky_f,
            "shift_right_sticky_u128: shift>=128 sticky direction wrong",
        );
    } else if shift >= 64_u64 {
        // Clause (3): 64 <= shift <= 127. eff in 0..=63.
        let eff: u64 = shift - 64_u64;
        // pow2_eff in [1, 2^63]. Computed via a dynamic u64 left-shift; the
        // shift amount stays in u64's 6-bit-meaningful range by the case
        // guard.
        let pow2_eff: u64 = 1_u64 << eff;

        // Clause (3a): val.high == quotient * pow2_eff + remainder over Field.
        // Quotient * pow2_eff is at most 2^64 * 2^63 = 2^127 -- below the
        // BN254 modulus.
        let high_f: Field = val.high as Field;
        let quotient_f: Field = quotient as Field;
        let pow2_eff_f: Field = pow2_eff as Field;
        let remainder_f: Field = remainder as Field;
        assert(
            high_f == quotient_f * pow2_eff_f + remainder_f,
            "shift_right_sticky_u128: 64<=shift<128 reconstruction failed",
        );

        // Clause (3b): remainder < pow2_eff. Both u64.
        assert(
            remainder < pow2_eff,
            "shift_right_sticky_u128: 64<=shift<128 remainder above pow2",
        );

        // Clause (3c): high_top must be zero in this branch.
        assert(
            high_top == 0_u64,
            "shift_right_sticky_u128: 64<=shift<128 high_top nonzero",
        );

        // Clause (3d): sticky == ((val.low != 0) | (remainder != 0)). Use the
        // combined-sum + existence-of-inverse trick. val.low + remainder fits
        // in 2^65, no Field wrap.
        let low_f: Field = val.low as Field;
        let combined_f: Field = low_f + remainder_f;
        let sticky_f: Field = sticky as Field;
        assert(
            (1_u64 - (sticky as u64)) as Field * combined_f == 0,
            "shift_right_sticky_u128: 64<=shift<128 sticky==0 but value nonzero",
        );
        let combined_inv: Field = unsafe { field_inv_or_zero(combined_f) };
        assert(
            combined_f * combined_inv == sticky_f,
            "shift_right_sticky_u128: 64<=shift<128 sticky direction wrong",
        );
    } else {
        // Clause (4): 1 <= shift <= 63.
        // pow2 := 1 << shift  in [2, 2^63].
        // pow2_top := 2^(64 + shift) = pow2 * 2^64.
        // value_field := val.high * 2^64 + val.low  in [0, 2^128).
        let pow2: u64 = 1_u64 << shift;

        let high_f: Field = val.high as Field;
        let low_f: Field = val.low as Field;
        // 2^64 as a Field constant. Computed at compile time. We avoid the
        // `1_u128 << 64` literal because `nargo 1.0.0-beta.17` rejects mixed
        // bit widths in shift expressions; this Field-level expression is
        // constant-folded by the compiler.
        let two_32: Field = 0x1_0000_0000;
        let two_64: Field = two_32 * two_32;
        let value_f: Field = high_f * two_64 + low_f;

        let quotient_f: Field = quotient as Field;
        let remainder_f: Field = remainder as Field;
        let high_top_f: Field = high_top as Field;
        let pow2_f: Field = pow2 as Field;
        let pow2_top_f: Field = pow2_f * two_64;

        // Clause (4a): reconstruction over Field. RHS terms are at most
        // 2^64 * 2^127 + 2^64 * 2^63 + 2^63 < 2^192, below the BN254 modulus.
        assert(
            value_f == high_top_f * pow2_top_f + quotient_f * pow2_f + remainder_f,
            "shift_right_sticky_u128: 1<=shift<64 reconstruction failed",
        );

        // Clause (4b): remainder < pow2. Both u64.
        assert(
            remainder < pow2,
            "shift_right_sticky_u128: 1<=shift<64 remainder above pow2",
        );

        // Clause (4c): sticky direction -- pinned by two constraints plus a
        // witnessed Field inverse hint.
        let sticky_f: Field = sticky as Field;
        assert(
            (1_u64 - (sticky as u64)) as Field * remainder_f == 0,
            "shift_right_sticky_u128: 1<=shift<64 sticky==0 but remainder nonzero",
        );
        let remainder_inv: Field = unsafe { field_inv_or_zero(remainder_f) };
        assert(
            remainder_f * remainder_inv == sticky_f,
            "shift_right_sticky_u128: 1<=shift<64 sticky direction wrong",
        );
        // (4d) is enforced by the u64 witness types of `quotient` and
        // `high_top`.
    }
}

// ============================================================================
// Tests -- happy paths (shr_sticky_u128)
// ============================================================================

#[test]
fn test_shr_sticky_u128_zero_shift() {
    // shift == 0: returns val.low; val.high is silently dropped.
    let val: U128 = U128 { high: 0xCAFE_BABE_u64, low: 0xDEAD_BEEF_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 0_u64);
    assert(result == 0xDEAD_BEEF_u64);
}

#[test]
fn test_shr_sticky_u128_zero_value() {
    // Shifting zero by anything is zero with no sticky.
    let zero: U128 = U128 { high: 0_u64, low: 0_u64 };
    assert(shift_right_sticky_u128_verified(zero, 5_u64) == 0_u64);
    assert(shift_right_sticky_u128_verified(zero, 64_u64) == 0_u64);
    assert(shift_right_sticky_u128_verified(zero, 100_u64) == 0_u64);
    assert(shift_right_sticky_u128_verified(zero, 128_u64) == 0_u64);
    assert(shift_right_sticky_u128_verified(zero, 1000_u64) == 0_u64);
}

#[test]
fn test_shr_sticky_u128_clean_shift_low_only() {
    // val == 0b1000, shift == 3 => quotient = 1, remainder = 0, sticky = 0.
    let val: U128 = U128 { high: 0_u64, low: 8_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 3_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u128_with_sticky_low_only() {
    // val == 0b1011, shift == 2 => quotient = 0b10, remainder = 0b11,
    // sticky = 1. Encoded = 0b10 | 1 = 0b11 = 3.
    let val: U128 = U128 { high: 0_u64, low: 11_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 2_u64);
    assert(result == 3_u64);
}

#[test]
fn test_shr_sticky_u128_shift_50_matches_baseline() {
    // Mirrors the float64/mul.nr line 165 call site: shift_right_sticky_u128
    // with shift == 50 against a representative product.
    let val: U128 = U128 { high: 0x0000_0001_2345_6789_u64, low: 0xABCD_EF01_2345_6789_u64 };
    let baseline: u64 = crate::utils::shift_right_sticky_u128(val, 50_u64);
    let verified: u64 = shift_right_sticky_u128_verified(val, 50_u64);
    assert(verified == baseline);
}

#[test]
fn test_shr_sticky_u128_shift_49_matches_baseline() {
    // Mirrors the float64/mul.nr line 175 call site: shift == 49.
    let val: U128 = U128 { high: 0x0000_0000_0AAA_BBBB_u64, low: 0xCCCC_DDDD_EEEE_FFFF_u64 };
    let baseline: u64 = crate::utils::shift_right_sticky_u128(val, 49_u64);
    let verified: u64 = shift_right_sticky_u128_verified(val, 49_u64);
    assert(verified == baseline);
}

#[test]
fn test_shr_sticky_u128_shift_just_below_64() {
    // shift == 63: result spans both halves. val.high contributes
    // (val.high << 1) into result, val.low >> 63 contributes the top bit.
    let val: U128 = U128 { high: 0x1234_5678_u64, low: (1_u64 << 63_u64) | 0xFF_u64 };
    let baseline: u64 = crate::utils::shift_right_sticky_u128(val, 63_u64);
    let verified: u64 = shift_right_sticky_u128_verified(val, 63_u64);
    assert(verified == baseline);
}

#[test]
fn test_shr_sticky_u128_shift_64_clean() {
    // shift == 64: result == val.high, sticky == (val.low != 0).
    let val: U128 = U128 { high: 0xABCD_EF01_u64, low: 0_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 64_u64);
    assert(result == 0xABCD_EF01_u64);
}

#[test]
fn test_shr_sticky_u128_shift_64_with_low_sticky() {
    // shift == 64: result == val.high | sticky. val.low != 0 forces sticky.
    let val: U128 = U128 { high: 0xABCD_EF00_u64, low: 1_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 64_u64);
    assert(result == (0xABCD_EF00_u64 | 1_u64));
}

#[test]
fn test_shr_sticky_u128_shift_in_high_range() {
    // shift == 100, eff == 36. val.high >> 36 is the quotient; remainder
    // captures the low 36 bits of val.high; sticky also picks up val.low.
    let val: U128 = U128 { high: 0xFFFF_FFFF_FFFF_FFFF_u64, low: 0_u64 };
    let baseline: u64 = crate::utils::shift_right_sticky_u128(val, 100_u64);
    let verified: u64 = shift_right_sticky_u128_verified(val, 100_u64);
    assert(verified == baseline);
}

#[test]
fn test_shr_sticky_u128_shift_127() {
    // shift == 127, eff == 63. val.high >> 63 is at most 1; remainder catches
    // every other bit of val.high.
    let val: U128 = U128 { high: 1_u64 << 63_u64, low: 0_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 127_u64);
    assert(result == 1_u64);

    let val_dirty: U128 = U128 { high: (1_u64 << 63_u64) | 1_u64, low: 0_u64 };
    let result_dirty: u64 = shift_right_sticky_u128_verified(val_dirty, 127_u64);
    // quotient = 1, remainder != 0 so sticky = 1, encoded = 1 | 1 = 1.
    assert(result_dirty == 1_u64);
}

#[test]
fn test_shr_sticky_u128_shift_128_nonzero() {
    // shift == 128: everything shifted out. val != 0 so sticky == 1.
    let val: U128 = U128 { high: 0_u64, low: 1_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 128_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u128_shift_far_above_128() {
    // Drop-in compatibility with the baseline: very large shifts collapse to
    // the "all bits shifted out" case.
    let val: U128 = U128 { high: 0xABCD_u64, low: 0xEF01_u64 };
    let result: u64 = shift_right_sticky_u128_verified(val, 1000_u64);
    assert(result == 1_u64);
}

#[test]
fn test_shr_sticky_u128_matches_baseline_low_zero_high_set() {
    // val.low == 0, val.high != 0, shift in 1..63: quotient picks up
    // (val.high << (64 - shift)) truncated to u64, no sticky.
    let val: U128 = U128 { high: 0x1_u64, low: 0_u64 };
    let baseline: u64 = crate::utils::shift_right_sticky_u128(val, 12_u64);
    let verified: u64 = shift_right_sticky_u128_verified(val, 12_u64);
    assert(verified == baseline);
}

// ============================================================================
// Tests -- adversarial (shr_sticky_u128)
// ============================================================================
//
// Each adversarial path exercises one verifier clause. Sharing
// `verify_shr_sticky_u128_relation` between production and tests means a
// regression in the production verifier path would be caught here too.

#[test(should_fail_with = "shift==0 quotient mismatch")]
fn test_shr_sticky_u128_bad_quotient_zero_shift() {
    // shift == 0: quotient must equal val.low.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0xABCD_u64 };
    verify_shr_sticky_u128_relation(val, 0_u64, 0_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "shift==0 sticky set")]
fn test_shr_sticky_u128_bad_sticky_zero_shift() {
    // shift == 0 with quotient correct but sticky set is rejected.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0xABCD_u64 };
    verify_shr_sticky_u128_relation(val, 0_u64, 0xABCD_u64, 0_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "1<=shift<64 reconstruction failed")]
fn test_shr_sticky_u128_bad_reconstruction_low_shift() {
    // val == low=8, shift == 2: true (q, r, h, s) = (2, 0, 0, 0). Feeding
    // (3, 0, 0, 0) breaks reconstruction: 3 * 4 + 0 == 12 != 8.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 8_u64 };
    verify_shr_sticky_u128_relation(val, 2_u64, 3_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "1<=shift<64 remainder above pow2")]
fn test_shr_sticky_u128_bad_remainder_above_pow2_low_shift() {
    // val == low=12, shift == 2, pow2 == 4: a witness could try
    // (q, r, h) = (2, 4, 0). Reconstruction holds (2*4 + 4 == 12), but
    // remainder == pow2 violates the bound. Verifier rejects.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 12_u64 };
    verify_shr_sticky_u128_relation(val, 2_u64, 2_u64, 4_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "1<=shift<64 sticky==0 but remainder nonzero")]
fn test_shr_sticky_u128_bad_sticky_zero_with_remainder_low_shift() {
    // val == low=11, shift == 2: true (q, r, h, s) = (2, 3, 0, 1). Feeding
    // sticky == 0 is rejected by the (1 - sticky) * remainder == 0 clause.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 11_u64 };
    verify_shr_sticky_u128_relation(val, 2_u64, 2_u64, 3_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "1<=shift<64 sticky direction wrong")]
fn test_shr_sticky_u128_bad_sticky_one_with_zero_remainder_low_shift() {
    // val == low=8, shift == 2: true (q, r, h, s) = (2, 0, 0, 0). Feeding
    // sticky == 1 is rejected by remainder * remainder_inv == sticky.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 8_u64 };
    verify_shr_sticky_u128_relation(val, 2_u64, 2_u64, 0_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "64<=shift<128 reconstruction failed")]
fn test_shr_sticky_u128_bad_reconstruction_mid_shift() {
    // val == high=8, low=0, shift == 66 => eff = 2, pow2_eff = 4. True
    // (q, r) = (2, 0). Feeding (3, 0) breaks reconstruction.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 8_u64, low: 0_u64 };
    verify_shr_sticky_u128_relation(val, 66_u64, 3_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "64<=shift<128 remainder above pow2")]
fn test_shr_sticky_u128_bad_remainder_above_pow2_mid_shift() {
    // val == high=12, low=0, shift == 66 => pow2_eff = 4. (q, r) = (2, 4)
    // satisfies reconstruction but remainder == pow2_eff is rejected.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 12_u64, low: 0_u64 };
    verify_shr_sticky_u128_relation(val, 66_u64, 2_u64, 4_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "64<=shift<128 sticky==0 but value nonzero")]
fn test_shr_sticky_u128_bad_sticky_zero_with_low_set_mid_shift() {
    // val == high=8, low=1, shift == 66: remainder==0 but val.low != 0 so
    // sticky should be 1. Feeding sticky == 0 is rejected.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 8_u64, low: 1_u64 };
    verify_shr_sticky_u128_relation(val, 66_u64, 2_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "64<=shift<128 sticky direction wrong")]
fn test_shr_sticky_u128_bad_sticky_one_with_zero_value_mid_shift() {
    // val == 0, shift == 66: sticky claimed 1 is rejected by the
    // existence-of-inverse constraint (combined == 0 forces sticky == 0).
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0_u64 };
    verify_shr_sticky_u128_relation(val, 66_u64, 0_u64, 0_u64, 0_u64, 1_u1);
}

#[test(should_fail_with = "shift>=128 quotient nonzero")]
fn test_shr_sticky_u128_bad_quotient_shift_128() {
    // shift == 128: quotient must be 0.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0_u64 };
    verify_shr_sticky_u128_relation(val, 128_u64, 1_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "shift>=128 sticky==0 but value nonzero")]
fn test_shr_sticky_u128_bad_sticky_zero_shift_128() {
    // shift == 128, val != 0, sticky claimed 0 -- rejected.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0xABCD_u64 };
    verify_shr_sticky_u128_relation(val, 128_u64, 0_u64, 0_u64, 0_u64, 0_u1);
}

#[test(should_fail_with = "shift>=128 sticky direction wrong")]
fn test_shr_sticky_u128_bad_sticky_one_value_zero_shift_128() {
    // shift == 128, val == 0, sticky claimed 1 -- rejected by the
    // existence-of-inverse clause `combined * combined_inv == sticky`.
    // Safety: adversarial path.
    let val: U128 = U128 { high: 0_u64, low: 0_u64 };
    verify_shr_sticky_u128_relation(val, 128_u64, 0_u64, 0_u64, 0_u64, 1_u1);
}
