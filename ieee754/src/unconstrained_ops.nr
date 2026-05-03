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

// ============================================================================
// count_leading_zeros_u64
// ============================================================================

/// Brillig hint: count the number of leading zeros in `value`, treating it
/// as a 64-bit-wide register.
///
/// Returns `count: u64` such that:
///
/// - if `value == 0`: `count == 64`;
/// - otherwise: `count` is the number of zero bits between bit 63 (the top
///   of the register) and the most significant set bit, exclusive of the
///   set bit itself. Equivalently `count == 63 - msb_position`, where
///   `msb_position` is the index of the highest set bit of `value`.
///
/// This matches the IEEE 754 double-precision normalisation use case where
/// a 64-bit accumulator must be left-shifted until its top bit lines up with
/// the implicit leading bit of the result.
///
/// This function is `unconstrained` and contributes no ACIR gates. Its output
/// MUST be validated by `count_leading_zeros_u64_verified` before being
/// trusted.
///
/// Crate-private deliberately: a downstream caller must not be able to bypass
/// the verifier by importing the raw hint. The only sanctioned consumer is
/// `count_leading_zeros_u64_verified` immediately below.
unconstrained fn count_leading_zeros_u64_unconstrained(value: u64) -> u64 {
    if value == 0_u64 {
        // No bits set => 64 leading zeros by convention.
        64_u64
    } else {
        // Walk from the top of the register downward, returning as soon as
        // we hit the first set bit. Unconstrained code is free to use early
        // exits so the procedural shape mirrors a software CLZ.
        let mut count: u64 = 0_u64;
        for i in 0..64 {
            let probe_pos: u64 = 63_u64 - (i as u64);
            let probe_bit: u64 = (value >> probe_pos) & 1_u64;
            if probe_bit == 1_u64 {
                count = i as u64;
                break;
            }
        }
        count
    }
}

/// Constrained verifier: returns `count`, asserting the relation that pins it
/// uniquely to the leading-zero count of `value` interpreted as a 64-bit
/// register.
///
/// # Public-input contract
/// - Input: `value: u64`. All 64 bits are inspected.
/// - Output: `count: u64` in the range `0..=64`.
///
/// # SAFETY PROOF (sketch -- not mechanised)
///
/// The verifier asserts the relation `R(value, count)`:
///
/// 1. `count <= 64`.
/// 2. **Zero case**: if `count == 64` then `value == 0`.
/// 3. **Non-zero case**: if `count <= 63` then there exists `top_bit_pos`
///    with `top_bit_pos == 63 - count` and:
///      a. bit `top_bit_pos` of `value` is set, i.e.
///         `(value >> top_bit_pos) & 1 == 1`; and
///      b. no bits of `value` above `top_bit_pos` are set, i.e.
///         `value >> (top_bit_pos + 1) == 0`, equivalently
///         `value < 2^(top_bit_pos + 1) = 2^(64 - count)`.
///
/// The boundary `count == 0` is handled inline: clause (3b) becomes a shift
/// by 64, which we replace with the trivially-true bound (no bits exist
/// above bit 63 in a 64-bit word). Concretely we branch on `count == 0` and
/// only check (3a) in that subcase.
///
/// **Uniqueness** (no second `count'` satisfies `R(value, count')`):
///
/// - If `value == 0` then clause (3a) cannot hold for any `count <= 63`
///   (no bit is set), so only `count == 64` (clause 2) satisfies `R`.
/// - If `value != 0` then `count == 64` is excluded by clause (2). Among
///   the remaining `count <= 63`, clause (3b) bounds `value` strictly below
///   `2^(64 - count)`; equivalently, the most significant set bit has
///   index strictly less than `64 - count`, i.e. at most `63 - count`.
///   Clause (3a) forces equality at exactly bit `63 - count`. The most
///   significant set bit of a fixed non-zero `value` is unique (standard
///   binary-representation theorem), so `count` is uniquely determined.
///
/// Therefore exactly one `count` satisfies `R` for any input `value`.
///
/// **Correctness** (the unique `count` matches the spec): by definition of
/// `count_leading_zeros` on a 64-bit register, the spec is `64` for the
/// zero case and `63 - msb_position(value)` otherwise. Clauses (2) and (3)
/// implement exactly this definition, matching the Lean spec
/// `Spec.cluz_u64` in
/// `proofs/Ieee754/.../UnconstrainedOps.lean`.
///
/// This sketch is a reading aid; the soundness has not been mechanised
/// (the `clz_u64_unique` and `clz_u64_correct` Lean obligations remain
/// `sorry`-stubbed).
pub fn count_leading_zeros_u64_verified(value: u64) -> u64 {
    // Safety: `verify_clz_u64_relation` enforces the relation that uniquely
    // pins `count` to the leading-zero count of `value`; see the SAFETY
    // PROOF block above.
    let count: u64 = unsafe { count_leading_zeros_u64_unconstrained(value) };
    verify_clz_u64_relation(value, count)
}

/// Constrained relation check shared by `count_leading_zeros_u64_verified`
/// and the adversarial tests. Asserts clauses (1), (2), (3a), (3b) of the
/// SAFETY PROOF and returns `count` unchanged on success.
///
/// Private to this module so the assertion error strings remain
/// implementation details. Sharing the helper between production and tests
/// means an adversarial-test failure also flags a regression in the
/// production verifier path.
fn verify_clz_u64_relation(value: u64, count: u64) -> u64 {
    // Clause (1): count <= 64.
    assert(count <= 64_u64, "count_leading_zeros_u64: count above 64");

    if count == 64_u64 {
        // Clause (2): zero case.
        assert(value == 0_u64, "count_leading_zeros_u64: count==64 but value nonzero");
    } else {
        // Clause (3): non-zero case. We have count <= 63 here.
        //
        // top_bit_pos in 0..=63.
        let top_bit_pos: u64 = 63_u64 - count;

        // Clause (3a): bit `top_bit_pos` of value is set.
        // `(value >> top_bit_pos) & 1 == 1`. Both sides are u64.
        let probe: u64 = (value >> top_bit_pos) & 1_u64;
        assert(probe == 1_u64, "count_leading_zeros_u64: leading bit not set");

        // Clause (3b): no bits of value are set above `top_bit_pos`.
        //
        // Expressed as a single right-shift comparison: shifting value
        // right by `top_bit_pos + 1` must yield zero. The boundary
        // `count == 0` would make this a shift by 64, which is
        // outside the well-defined range for u64 right shifts in Noir;
        // in that subcase there are no bits above bit 63 by definition,
        // so clause (3b) holds trivially and we skip the shift.
        if count != 0_u64 {
            let above_shift: u64 = top_bit_pos + 1_u64;
            let above: u64 = value >> above_shift;
            assert(above == 0_u64, "count_leading_zeros_u64: bit set above leading position");
        }
    }

    count
}

// ============================================================================
// count_leading_zeros_u64 -- bit-decomposition spike
// ============================================================================
//
// SPIKE (PR #38, branch `spike/clz-bit-decomposition`): the merged
// `count_leading_zeros_u64_verified` above uses a witness-driven dynamic
// shift `value >> top_bit_pos` to verify the relation. Benchmarks on
// PR #37 showed both Width and ACIR regress vs. the binary-search
// baseline, principally because the dynamic shift is more expensive than
// six static shifts.
//
// This spike replaces the dynamic shift with an explicit bit-decomposition
// relation: witness the 64 bits and a one-hot encoding of the leading-bit
// position, then check the relation algebraically. The "no bits above the
// leading position" clause uses a cumulative `saw_one` prefix flag so the
// constraint count stays linear (O(N)) rather than the naive quadratic
// O(N^2) "for each pair (i, j) with j > i" form.
//
// The plain `_verified` variant above is left untouched during the
// implementation and benchmark phases. The verdict step (after the
// numbers are in) decides whether to keep the spike, swap the merged
// implementation, or revert.

/// Brillig hint: emit the unconstrained witnesses for the bit-decomposition
/// CLZ verifier.
///
/// Returns the tuple `(count, bits, is_leading, is_nonzero)`:
///
/// - `count: u64` -- the leading-zero count, matching
///   `count_leading_zeros_u64_unconstrained` above (`64` when `value == 0`,
///   otherwise `63 - msb_position`).
/// - `bits: [Field; 64]` -- the little-endian bit decomposition of `value`,
///   `bits[i]` being the value of bit `i` of `value`.
/// - `is_leading: [Field; 64]` -- a one-hot indicator of the most
///   significant set bit. `is_leading[msb] == 1` for the unique MSB; all
///   other entries are 0. The all-zeros vector signals `value == 0`.
/// - `is_nonzero: Field` -- 1 when `value != 0`, 0 when `value == 0`.
///
/// The verifier `verify_clz_u64_relation_bitdecomp` checks the relation
/// pinning all four witnesses uniquely against `value`. This function is
/// crate-private deliberately, mirroring the merged `_unconstrained`
/// helper: only the matching `_verified_bitdecomp` consumer is sanctioned.
unconstrained fn count_leading_zeros_u64_unconstrained_bitdecomp(
    value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    let mut bits: [Field; 64] = [0 as Field; 64];
    let mut is_leading: [Field; 64] = [0 as Field; 64];

    // Decompose into little-endian bits.
    for i in 0..64 {
        let probe: u64 = (value >> (i as u64)) & 1_u64;
        bits[i] = probe as Field;
    }

    let is_nonzero_bool: bool = value != 0_u64;
    let is_nonzero: Field = if is_nonzero_bool { 1 as Field } else { 0 as Field };

    let count: u64 = if !is_nonzero_bool {
        // No bits set => 64 leading zeros by convention; one-hot stays
        // all zero.
        64_u64
    } else {
        // Walk from the top of the register down to find the most
        // significant set bit.
        let mut found_count: u64 = 0_u64;
        for i in 0..64 {
            let probe_pos: u64 = 63_u64 - (i as u64);
            let probe_bit: u64 = (value >> probe_pos) & 1_u64;
            if probe_bit == 1_u64 {
                found_count = i as u64;
                is_leading[probe_pos as u32] = 1 as Field;
                break;
            }
        }
        found_count
    };

    (count, bits, is_leading, is_nonzero)
}

/// Constrained verifier (bit-decomposition variant): returns `count`,
/// asserting the relation that pins it uniquely to the leading-zero count
/// of `value` interpreted as a 64-bit register.
///
/// # Public-input contract
/// - Input: `value: u64`. All 64 bits are inspected.
/// - Output: `count: u64` in the range `0..=64`.
///
/// # SAFETY PROOF (sketch -- not mechanised)
///
/// Witness: `bits: [Field; 64]`, `is_leading: [Field; 64]`,
/// `is_nonzero: Field`, plus `count: u64`. The verifier asserts:
///
/// (B) **Bit validity**: each `bits[i] in {0, 1}`.
/// (D) **Decomposition**: `sum_{i=0..63} bits[i] * 2^i == value`. With
///     (B) this pins `bits` to the canonical little-endian bit
///     decomposition of `value` (a fixed `Field` value below
///     `2^64 < 2^254` admits a unique such decomposition).
/// (L) **One-hot validity**: each `is_leading[i] in {0, 1}`.
/// (E) **One-hot exclusivity**: `sum_{i=0..63} is_leading[i] == is_nonzero`,
///     with `is_nonzero in {0, 1}` and `is_nonzero == 0 iff value == 0`,
///     enforced by `is_nonzero * value == value` and
///     `(1 - is_nonzero) * value == 0`. Combined with (L) this forces at
///     most one entry of `is_leading` to be 1, and exactly that many ones
///     iff `value` is non-zero.
/// (S) **Leading-bit set**: for each `i`,
///     `is_leading[i] * bits[i] == is_leading[i]`. Equivalently the
///     entry of `bits` indicated by the one-hot is itself 1.
/// (P) **No bits above leading** (prefix encoding): a witness
///     `saw_one: [Field; 64]` is constructed inline as
///     `saw_one[i] = sum_{j >= i} is_leading[j]`. Under (E) and (L),
///     `saw_one[i] in {0, 1}` and `saw_one[i] == 1 iff i <= msb`.
///     The constraint `bits[i] * (1 - saw_one[i]) == 0` for each `i`
///     forces `bits[i] == 0` whenever `i > msb`. This is the load-bearing
///     clause that costs O(N) rather than the naive O(N^2) pairwise
///     "is_leading[i] * bits[j] == 0 for j > i".
/// (C) **Count consistency**:
///     `count == 64 - is_nonzero - sum_{i} i * is_leading[i]`.
///     - When `value == 0`: `is_nonzero == 0`, `is_leading == 0`, so
///       `count == 64`.
///     - When `value != 0`: `is_nonzero == 1`, exactly one
///       `is_leading[msb] == 1`, so `count == 64 - 1 - msb == 63 - msb`,
///       matching the spec.
///
/// **Uniqueness**: clauses (B)+(D) uniquely determine `bits`. Clauses
/// (L)+(E)+(S)+(P) uniquely determine `is_leading` to be the one-hot of
/// the MSB (or the all-zeros vector when `value == 0`), because the MSB
/// of a fixed binary representation is unique. Clause (C) then pins
/// `count`. So exactly one valid witness tuple exists per `value`.
///
/// **Correctness**: the unique `count` is by construction `64` for
/// `value == 0` and `63 - msb` otherwise, which matches the
/// `count_leading_zeros_u64` spec used in the original verifier.
pub fn count_leading_zeros_u64_verified_bitdecomp(value: u64) -> u64 {
    // Safety: `verify_clz_u64_relation_bitdecomp` enforces the relation
    // that uniquely pins the witness tuple to `value`; see the SAFETY
    // PROOF block above.
    let (count, bits, is_leading, is_nonzero): (u64, [Field; 64], [Field; 64], Field) =
        unsafe { count_leading_zeros_u64_unconstrained_bitdecomp(value) };
    verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero)
}

/// Constrained relation check shared by `count_leading_zeros_u64_verified_bitdecomp`
/// and the adversarial bit-decomposition tests.
///
/// Sharing the helper between production and tests means an
/// adversarial-test failure also flags a regression in the production
/// verifier path (mirrors the `_clz_u64` round-1 fix in PR #37 and the
/// `_clz_u23` round-1 fix in PR #36).
fn verify_clz_u64_relation_bitdecomp(
    value: u64,
    count: u64,
    bits: [Field; 64],
    is_leading: [Field; 64],
    is_nonzero: Field,
) -> u64 {
    // (B) Bit validity: each bits[i] in {0, 1}.
    for i in 0..64 {
        let b: Field = bits[i];
        assert(b * (b - 1) == 0 as Field, "clz_u64_bd: bits not boolean");
    }

    // (L) One-hot validity: each is_leading[i] in {0, 1}.
    for i in 0..64 {
        let l: Field = is_leading[i];
        assert(l * (l - 1) == 0 as Field, "clz_u64_bd: is_leading not boolean");
    }

    // (D) Decomposition: sum_i bits[i] * 2^i == value.
    //
    // We accumulate the dot-product into a Field and compare against
    // `value as Field`. The factor `2^i` is built up by repeated doubling
    // so we don't pay for a `pow` per iteration.
    let mut acc_decomp: Field = 0 as Field;
    let mut weight: Field = 1 as Field;
    for i in 0..64 {
        acc_decomp = acc_decomp + bits[i] * weight;
        // Last iteration's doubling is wasted but harmless.
        weight = weight * (2 as Field);
        // Keep the loop body shape stable; the compiler unrolls cleanly
        // when `i` is the index variable.
        let _ = i;
    }
    assert(acc_decomp == value as Field, "clz_u64_bd: decomposition mismatch");

    // (E) Non-zero indicator: is_nonzero in {0, 1}, and
    // is_nonzero == 0 iff value == 0.
    assert(
        is_nonzero * (is_nonzero - 1) == 0 as Field,
        "clz_u64_bd: is_nonzero not boolean",
    );
    let value_f: Field = value as Field;
    assert(is_nonzero * value_f == value_f, "clz_u64_bd: is_nonzero=0 but value!=0");
    assert(
        (1 as Field - is_nonzero) * value_f == 0 as Field,
        "clz_u64_bd: is_nonzero=1 but value=0",
    );

    // (E') One-hot exclusivity: sum is_leading[i] == is_nonzero.
    let mut acc_onehot: Field = 0 as Field;
    for i in 0..64 {
        acc_onehot = acc_onehot + is_leading[i];
    }
    assert(
        acc_onehot == is_nonzero,
        "clz_u64_bd: one-hot sum mismatch",
    );

    // (S) Leading bit is set: is_leading[i] * bits[i] == is_leading[i].
    for i in 0..64 {
        assert(
            is_leading[i] * bits[i] == is_leading[i],
            "clz_u64_bd: leading bit not set",
        );
    }

    // (P) No bits above the leading position, via a cumulative prefix
    // flag. We build `saw_one[i] = sum_{j >= i} is_leading[j]` from the
    // top down: this is monotone (becomes 1 at and below the MSB) and
    // costs O(N), not O(N^2).
    //
    // The constraint `bits[i] * (1 - saw_one[i]) == 0` forces bits above
    // the MSB to zero. Note this is "bits at or above i must be zero
    // when no leading-one has been seen at or above i" -- exactly the
    // relation we want when iterating top-down.
    let mut saw_one: Field = 0 as Field;
    for i in 0..64 {
        let idx: u32 = 63 - (i as u32);
        saw_one = saw_one + is_leading[idx];
        // saw_one is in {0, 1} because at most one is_leading[j] is 1
        // (one-hot exclusivity (E')) and the prefix is non-decreasing.
        // Constrain bits[idx] * (1 - saw_one) == 0:
        //   - if idx > msb, saw_one is still 0, so bits[idx] must be 0;
        //   - at idx == msb saw_one becomes 1, allowing bits[msb] = 1
        //     (forced 1 by clause (S));
        //   - below msb saw_one == 1, no constraint on bits[idx].
        assert(
            bits[idx] * (1 as Field - saw_one) == 0 as Field,
            "clz_u64_bd: bit set above leading position",
        );
    }

    // (C) Count consistency: count == 64 - is_nonzero - sum_i i * is_leading[i].
    //
    // - value == 0: is_nonzero = 0, is_leading == 0 vector, count == 64.
    // - value != 0: is_nonzero = 1, sum i * is_leading[i] == msb,
    //   count == 64 - 1 - msb == 63 - msb. Matches the spec.
    let mut acc_pos: Field = 0 as Field;
    for i in 0..64 {
        acc_pos = acc_pos + (i as Field) * is_leading[i];
    }
    let count_f: Field = count as Field;
    assert(
        count_f + is_nonzero + acc_pos == 64 as Field,
        "clz_u64_bd: count mismatch",
    );

    // Defence in depth: bound count to u64 range. Witness `count: u64`
    // already gives this for free at the host-language level; the assert
    // below is redundant but documents the invariant.
    assert(count <= 64_u64, "clz_u64_bd: count above 64");

    count
}

// ============================================================================
// Tests -- happy paths (u64)
// ============================================================================

#[test]
fn test_clz_u64_all_zero() {
    let count: u64 = count_leading_zeros_u64_verified(0_u64);
    assert(count == 64_u64);
}

#[test]
fn test_clz_u64_lsb_only() {
    // Only bit 0 set: 63 leading zeros.
    let count: u64 = count_leading_zeros_u64_verified(1_u64);
    assert(count == 63_u64);
}

#[test]
fn test_clz_u64_msb_only() {
    // Only bit 63 set: 0 leading zeros.
    let value: u64 = 1_u64 << 63_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 0_u64);
}

#[test]
fn test_clz_u64_full_value() {
    // All 64 bits set: 0 leading zeros (bit 63 is set).
    let count: u64 = count_leading_zeros_u64_verified(0xFFFF_FFFF_FFFF_FFFF_u64);
    assert(count == 0_u64);
}

#[test]
fn test_clz_u64_bit_32() {
    // Only bit 32 set: leading zeros = 63 - 32 = 31.
    let value: u64 = 1_u64 << 32_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 31_u64);
}

#[test]
fn test_clz_u64_bit_31() {
    // Only bit 31 set: leading zeros = 63 - 31 = 32.
    let value: u64 = 1_u64 << 31_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 32_u64);
}

#[test]
fn test_clz_u64_bit_52() {
    // Bit 52 = position of float64 implicit leading bit; the dominant call
    // site for this primitive in normalisation paths.
    let value: u64 = 1_u64 << 52_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 11_u64);
}

#[test]
fn test_clz_u64_bit_pattern() {
    // Bits 5, 17 and 40 set => msb position = 40 => count = 63 - 40 = 23.
    let value: u64 = (1_u64 << 40_u64) | (1_u64 << 17_u64) | (1_u64 << 5_u64);
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 23_u64);
}

#[test]
fn test_clz_u64_bit_62() {
    // Only bit 62 set: count = 63 - 62 = 1.
    let value: u64 = 1_u64 << 62_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 1_u64);
}

#[test]
fn test_clz_u64_low_half_only() {
    // Pattern entirely in the low half: bits 0..32 set => msb is bit 31.
    let value: u64 = 0x0000_0000_FFFF_FFFF_u64;
    let count: u64 = count_leading_zeros_u64_verified(value);
    assert(count == 32_u64);
}

// ============================================================================
// Tests -- adversarial: each isolates one verifier clause (u64)
// ============================================================================
//
// Each `hint_clz_u64_*` generator produces a deliberately corrupt
// unconstrained witness for a single tampering mode; the matching test
// feeds it through `verify_clz_u64_relation` and asserts that the
// expected error string fires. Sharing `verify_clz_u64_relation` between
// production and tests means a regression in the production verifier
// path would be caught here too (mirrors the clz_u23 round-1 fix).

/// Always-64 hint: claims `count = 64` regardless of input.
unconstrained fn hint_clz_u64_always_64(_value: u64) -> u64 {
    64_u64
}

/// Out-of-range hint: returns 65 (above the 64 ceiling).
unconstrained fn hint_clz_u64_out_of_range(_value: u64) -> u64 {
    65_u64
}

/// Off-by-one-too-small hint: for `value == 1` the correct count is 63;
/// returning 62 fails clause (3a) -- bit `(63 - 62) = 1` is not set in
/// `0x1`.
unconstrained fn hint_clz_u64_too_small(_value: u64) -> u64 {
    62_u64
}

/// Off-by-one-too-large hint: for `value == 1` the correct count is 63;
/// returning 64 falsely claims the all-zero case and triggers clause (2).
unconstrained fn hint_clz_u64_falsely_zero(_value: u64) -> u64 {
    64_u64
}

#[test]
fn test_clz_u64_hint_always_64_passes_for_zero() {
    // The always-64 hint *happens* to be correct when value == 0, so the
    // verifier should accept it. Sanity check that the harness works.
    // Safety: adversarial test path; we accept this only because
    // `value == 0` is the canonical zero case and the verifier confirms it.
    let count: u64 = unsafe { hint_clz_u64_always_64(0_u64) };
    let returned: u64 = verify_clz_u64_relation(0_u64, count);
    assert(returned == 64_u64);
}

#[test(should_fail_with = "count above 64")]
fn test_clz_u64_hint_out_of_range_fails() {
    // Clause (1): count must be <= 64.
    // Safety: adversarial path; the verifier is expected to reject.
    let count: u64 = unsafe { hint_clz_u64_out_of_range(0_u64) };
    let _ = verify_clz_u64_relation(0_u64, count);
}

#[test(should_fail_with = "count==64 but value nonzero")]
fn test_clz_u64_hint_falsely_zero_fails() {
    // Clause (2): if count == 64 then value must be zero. Feeding a
    // non-zero input with count == 64 should trip this clause.
    // Safety: adversarial path.
    let count: u64 = unsafe { hint_clz_u64_falsely_zero(1_u64) };
    let _ = verify_clz_u64_relation(1_u64, count);
}

#[test(should_fail_with = "leading bit not set")]
fn test_clz_u64_hint_too_small_fails() {
    // For value == 1 the correct count is 63; hint_clz_u64_too_small
    // returns 62. Then top_bit_pos = 63 - 62 = 1, but bit 1 of 0x1 is 0,
    // so clause (3a) fires.
    // Safety: adversarial path.
    let count: u64 = unsafe { hint_clz_u64_too_small(1_u64) };
    let _ = verify_clz_u64_relation(1_u64, count);
}

#[test(should_fail_with = "bit set above leading position")]
fn test_clz_u64_hint_bit_above_fails() {
    // Manually craft a (value, count) pair that satisfies clauses (1),
    // (2), and (3a) but violates clause (3b): a bit set above the
    // leading position.
    //
    // Take value with bits 5 and 40 set. The true count is 63 - 40 = 23.
    // Feeding the verifier `count = 58` would put `top_bit_pos = 5`:
    //   - clause (3a) holds: bit 5 is set;
    //   - clause (3b) requires value < 2^(64 - 58) = 2^6 = 64, but
    //     value = (1 << 40) | (1 << 5) >= 2^40, so (3b) fires.
    // Safety: adversarial path; the wrong-count witness is intentional.
    let value: u64 = (1_u64 << 40_u64) | (1_u64 << 5_u64);
    let count: u64 = 58_u64;
    let _ = verify_clz_u64_relation(value, count);
}

// ============================================================================
// Tests -- happy paths (u64 bit-decomposition spike)
// ============================================================================
//
// Mirror the same 10 cases that exercise `count_leading_zeros_u64_verified`
// so the spike has the same coverage as the merged version.

#[test]
fn test_clz_u64_bd_all_zero() {
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(0_u64);
    assert(count == 64_u64);
}

#[test]
fn test_clz_u64_bd_lsb_only() {
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(1_u64);
    assert(count == 63_u64);
}

#[test]
fn test_clz_u64_bd_msb_only() {
    let value: u64 = 1_u64 << 63_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 0_u64);
}

#[test]
fn test_clz_u64_bd_full_value() {
    let count: u64 =
        count_leading_zeros_u64_verified_bitdecomp(0xFFFF_FFFF_FFFF_FFFF_u64);
    assert(count == 0_u64);
}

#[test]
fn test_clz_u64_bd_bit_32() {
    let value: u64 = 1_u64 << 32_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 31_u64);
}

#[test]
fn test_clz_u64_bd_bit_31() {
    let value: u64 = 1_u64 << 31_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 32_u64);
}

#[test]
fn test_clz_u64_bd_bit_52() {
    // Bit 52 = position of float64 implicit leading bit; the dominant call
    // site for this primitive in normalisation paths.
    let value: u64 = 1_u64 << 52_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 11_u64);
}

#[test]
fn test_clz_u64_bd_bit_pattern() {
    let value: u64 = (1_u64 << 40_u64) | (1_u64 << 17_u64) | (1_u64 << 5_u64);
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 23_u64);
}

#[test]
fn test_clz_u64_bd_bit_62() {
    let value: u64 = 1_u64 << 62_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 1_u64);
}

#[test]
fn test_clz_u64_bd_low_half_only() {
    let value: u64 = 0x0000_0000_FFFF_FFFF_u64;
    let count: u64 = count_leading_zeros_u64_verified_bitdecomp(value);
    assert(count == 32_u64);
}

// ============================================================================
// Tests -- adversarial: each isolates one bit-decomposition verifier clause
// ============================================================================
//
// Each `hint_clz_u64_bd_*` generator produces a deliberately corrupt
// witness tuple targeting a single clause. Tests share
// `verify_clz_u64_relation_bitdecomp` with the production path so that a
// regression in the production verifier flags here too.

/// Build the canonical bit decomposition of `value` (little-endian) inside
/// an unconstrained context. Used as a starting point that adversarial
/// hints then mutate.
unconstrained fn canonical_bits_u64(value: u64) -> [Field; 64] {
    let mut bits: [Field; 64] = [0 as Field; 64];
    for i in 0..64 {
        let probe: u64 = (value >> (i as u64)) & 1_u64;
        bits[i] = probe as Field;
    }
    bits
}

/// Adversarial: flip a single bit in the decomposition so it no longer
/// matches `value`. Targets clause (D) "decomposition mismatch".
unconstrained fn hint_clz_u64_bd_decomp_corrupt(
    value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    let mut bits: [Field; 64] = canonical_bits_u64(value);
    // Flip bit 0: changes the low bit of the reconstructed value, so
    // the decomposition assert must fire (regardless of what `value` is,
    // since the canonical decomp differs in bit 0 after the flip).
    bits[0] = 1 as Field - bits[0];
    let mut is_leading: [Field; 64] = [0 as Field; 64];
    if value != 0_u64 {
        // Place the one-hot at the true MSB; the bit at the MSB is still
        // set (we only mutated bit 0), so clause (S) still passes.
        for i in 0..64 {
            let probe_pos: u64 = 63_u64 - (i as u64);
            let probe_bit: u64 = (value >> probe_pos) & 1_u64;
            if probe_bit == 1_u64 {
                is_leading[probe_pos as u32] = 1 as Field;
                break;
            }
        }
    }
    let is_nonzero: Field = if value != 0_u64 { 1 as Field } else { 0 as Field };
    // Count is the truthful one-hot-derived count; only the bits array
    // disagrees, so clause (D) fires before the count clause is reached.
    let count: u64 = if value == 0_u64 {
        64_u64
    } else {
        let mut c: u64 = 0_u64;
        for i in 0..64 {
            let probe_pos: u64 = 63_u64 - (i as u64);
            let probe_bit: u64 = (value >> probe_pos) & 1_u64;
            if probe_bit == 1_u64 {
                c = i as u64;
                break;
            }
        }
        c
    };
    (count, bits, is_leading, is_nonzero)
}

/// Adversarial: claim a non-boolean bit value (2). Targets clause (B)
/// "bits not boolean".
unconstrained fn hint_clz_u64_bd_bits_not_boolean(
    value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    let mut bits: [Field; 64] = canonical_bits_u64(value);
    // Replace bit 0 with the value 2 -- not in {0, 1}.
    bits[0] = 2 as Field;
    let is_leading: [Field; 64] = [0 as Field; 64];
    let is_nonzero: Field = 0 as Field;
    let count: u64 = 64_u64;
    (count, bits, is_leading, is_nonzero)
}

/// Adversarial: claim two bits in the one-hot vector. Targets clause (E)
/// "one-hot sum mismatch" (sum exceeds is_nonzero).
unconstrained fn hint_clz_u64_bd_two_hot(
    value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    let bits: [Field; 64] = canonical_bits_u64(value);
    // Mark bits 0 and 1 as both leading; sum becomes 2, but is_nonzero
    // is at most 1.
    let mut is_leading: [Field; 64] = [0 as Field; 64];
    is_leading[0] = 1 as Field;
    is_leading[1] = 1 as Field;
    let is_nonzero: Field = 1 as Field;
    let count: u64 = 0_u64;
    (count, bits, is_leading, is_nonzero)
}

/// Adversarial: place the one-hot at a position whose bit is 0. Targets
/// clause (S) "leading bit not set".
unconstrained fn hint_clz_u64_bd_leading_at_zero_bit(
    _value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    // value = 1 (only bit 0 set). Decomposition is canonical, but we
    // place the one-hot at bit 5 (which is zero in `value = 1`).
    let mut bits: [Field; 64] = [0 as Field; 64];
    bits[0] = 1 as Field;
    let mut is_leading: [Field; 64] = [0 as Field; 64];
    is_leading[5] = 1 as Field;
    let is_nonzero: Field = 1 as Field;
    let count: u64 = 58_u64; // 63 - 5; matches the (false) leading position
    (count, bits, is_leading, is_nonzero)
}

/// Adversarial: place the one-hot below a real set bit. Targets clause
/// (P) "bit set above leading position" via the prefix flag.
unconstrained fn hint_clz_u64_bd_bit_above(
    _value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    // value has bits 5 and 40 set. Pretend the leading bit is 5; bit 40
    // then sits above the alleged MSB and the prefix-flag clause must
    // fire.
    let mut bits: [Field; 64] = [0 as Field; 64];
    bits[5] = 1 as Field;
    bits[40] = 1 as Field;
    let mut is_leading: [Field; 64] = [0 as Field; 64];
    is_leading[5] = 1 as Field;
    let is_nonzero: Field = 1 as Field;
    let count: u64 = 58_u64; // 63 - 5
    (count, bits, is_leading, is_nonzero)
}

/// Adversarial: claim is_nonzero = 1 but supply an all-zero decomposition
/// (matching `value = 0`). Targets the
/// `is_nonzero=1 but value=0` clause via `(1 - is_nonzero) * value == 0`
/// inverted, then the `is_nonzero=1` half via `is_nonzero * value == value`.
/// With value == 0 and is_nonzero == 1, the second clause becomes
/// `1 * 0 == 0` (passes) and the first becomes `0 * 0 == 0` (passes), so
/// we instead use the one-hot exclusivity to detect this.
///
/// The cleaner adversarial against the is_nonzero=0 half: claim
/// is_nonzero = 0 with value != 0 -- the
/// `is_nonzero=0 but value!=0` clause must fire.
unconstrained fn hint_clz_u64_bd_is_nonzero_lies(
    value: u64,
) -> (u64, [Field; 64], [Field; 64], Field) {
    let bits: [Field; 64] = canonical_bits_u64(value);
    let is_leading: [Field; 64] = [0 as Field; 64];
    // value != 0 in the matching test, but we lie: is_nonzero = 0.
    let is_nonzero: Field = 0 as Field;
    let count: u64 = 64_u64;
    (count, bits, is_leading, is_nonzero)
}

#[test]
fn test_clz_u64_bd_hint_round_trip_zero() {
    // Sanity: the canonical witness must still pass the verifier when
    // value == 0. Mirrors `test_clz_u64_hint_always_64_passes_for_zero`.
    // Safety: this is the canonical witness path.
    let witness = unsafe { count_leading_zeros_u64_unconstrained_bitdecomp(0_u64) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let returned: u64 =
        verify_clz_u64_relation_bitdecomp(0_u64, count, bits, is_leading, is_nonzero);
    assert(returned == 64_u64);
}

#[test(should_fail_with = "clz_u64_bd: decomposition mismatch")]
fn test_clz_u64_bd_hint_decomp_corrupt_fails() {
    // Clause (D): bits must reconstruct value.
    let value: u64 = 0xDEAD_BEEF_u64;
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_decomp_corrupt(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}

#[test(should_fail_with = "clz_u64_bd: bits not boolean")]
fn test_clz_u64_bd_hint_bits_not_boolean_fails() {
    // Clause (B): bits[i] must be in {0, 1}.
    let value: u64 = 0_u64;
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_bits_not_boolean(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}

#[test(should_fail_with = "clz_u64_bd: one-hot sum mismatch")]
fn test_clz_u64_bd_hint_two_hot_fails() {
    // Clause (E): sum is_leading[i] == is_nonzero (so at most one entry
    // can be 1).
    let value: u64 = 1_u64;
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_two_hot(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}

#[test(should_fail_with = "clz_u64_bd: leading bit not set")]
fn test_clz_u64_bd_hint_leading_at_zero_bit_fails() {
    // Clause (S): the bit at the leading position must be set.
    let value: u64 = 1_u64;
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_leading_at_zero_bit(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}

#[test(should_fail_with = "clz_u64_bd: bit set above leading position")]
fn test_clz_u64_bd_hint_bit_above_fails() {
    // Clause (P): no bits set above the alleged MSB; the prefix-flag
    // construction catches this.
    let value: u64 = (1_u64 << 40_u64) | (1_u64 << 5_u64);
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_bit_above(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}

#[test(should_fail_with = "clz_u64_bd: is_nonzero=0 but value!=0")]
fn test_clz_u64_bd_hint_is_nonzero_lies_fails() {
    // is_nonzero must equal 0 iff value == 0.
    let value: u64 = 1_u64;
    // Safety: adversarial path.
    let witness = unsafe { hint_clz_u64_bd_is_nonzero_lies(value) };
    let (count, bits, is_leading, is_nonzero) = witness;
    let _ = verify_clz_u64_relation_bitdecomp(value, count, bits, is_leading, is_nonzero);
}
