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
