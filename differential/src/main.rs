//! [SONNET-4.6] IEEE 754 differential harness -- PROOF M1 (sq-3x7dl.14.1).
//! [FABLE-5] sq-dtmg9: extended with abs, from_field, and to_field coverage.
//!
//! Generates a Noir test file asserting bit-equality between sparq_ieee754 circuit
//! primitives and a TRUSTED INDEPENDENT oracle:
//!   - f32/f64: native Rust hardware floats -- IEEE 754-2008 round-to-nearest-even
//!     on any conformant processor (the universal hardware reference).
//!   - f16: `half::f16` -- IEEE 754 half-precision via f32-widening arithmetic
//!     (correctly-rounded: f32 has 13 extra mantissa bits over f16, avoiding double-rounding).
//!   - f128: DEFERRED -- Rust `f128` is unstable (nightly only) and no stable
//!     soft-float binding with verified IEEE 754 conformance is available; follow-up
//!     bead sq-3x7dl.14.2. Generated file contains a doc comment noting the deferral.
//!
//! HONEST TCB STATEMENT:
//!   This harness is VERIFICATION, not proof.  It samples a corpus (corner cases +
//!   seeded pseudorandom) and checks the Noir circuit output at the `nargo test`
//!   witness-generation level -- it does NOT cover the ACIR->Barretenberg->proof
//!   lowering.  Sample coverage is stated honestly; it is NOT exhaustive.
//!   The trusted chain tested here: Noir source -> ACIR -> witness-gen (nargo).
//!
//! SEEDED PRNG: xorshift64 with fixed seed 0x4F52_4143_4C45_F754 (ASCII "ORACLE" +
//!   IEEE 754 hex).  Never use time-based seeds.
//!
//! INJECT-FAULT mode (--inject-fault PATH): writes the same file but with one
//!   expected value bit-flipped -- used by run_differential_harness.sh to prove the
//!   harness is non-vacuous (nargo test MUST fail on this file).
//!
//! Usage:
//!   `sparq-ieee754-differential --output PATH`           -- generate correct oracle file
//!   `sparq-ieee754-differential --inject-fault PATH`     -- generate fault-injected file

use half::f16 as HalfF16;
use std::fmt::Write as FmtWrite;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fixed seed for the xorshift64 PRNG.  Chosen to be memorable and constant
/// across runs -- a different seed would produce different random pairs but the
/// same corner-case coverage.  NEVER use a time-based seed.
const SEED: u64 = 0x4F52_4143_4C45_F754;

/// Canonical quiet NaN bit patterns for each format.
/// Matches sparq_ieee754's `canonical_nan` function:
///   sign=0, all exponent bits set, quiet-bit (MSB of mantissa) set, rest zero.
const CANONICAL_NAN_F16: u16 = 0x7E00;
const CANONICAL_NAN_F32: u32 = 0x7FC00000;
const CANONICAL_NAN_F64: u64 = 0x7FF8000000000000;

/// Random pairs generated per (type, operation) for arithmetic and comparisons.
/// Capped to keep CI nargo test time reasonable.
const RANDOM_ARITH_PER_OP: usize = 32;
const RANDOM_CMP_PER_OP: usize = 20;

// ---------------------------------------------------------------------------
// Seeded PRNG (xorshift64)
// ---------------------------------------------------------------------------

/// xorshift64 PRNG -- minimal, no external dep, deterministic.
struct Xorshift64 {
    state: u64,
}

impl Xorshift64 {
    const fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state = x;
        x
    }

    fn next_u16(&mut self) -> u16 {
        self.next() as u16
    }

    fn next_u32(&mut self) -> u32 {
        self.next() as u32
    }

    fn next_u64(&mut self) -> u64 {
        self.next()
    }
}

// ---------------------------------------------------------------------------
// Type aliases for function pointer tables (avoids clippy::type_complexity)
// ---------------------------------------------------------------------------

type ArithF32Op = fn(u32, u32) -> u32;
type ArithF64Op = fn(u64, u64) -> u64;
type ArithF16Op = fn(u16, u16) -> u16;
type CmpF32Op = fn(u32, u32) -> bool;
type CmpF64Op = fn(u64, u64) -> bool;
type CmpF16Op = fn(u16, u16) -> bool;

// ---------------------------------------------------------------------------
// NaN canonicalization
// ---------------------------------------------------------------------------

/// Map any NaN to sparq_ieee754's canonical quiet NaN.  Non-NaN values pass through.
///
/// This is necessary because hardware NaN payloads are implementation-defined:
/// e.g. x86 SSE produces 0xFFC00000 (QNaN indefinite, sign=1) while sparq_ieee754
/// produces 0x7FC00000 (canonical quiet NaN, sign=0).  Both are valid IEEE 754 NaNs.
#[inline]
fn canon_f16(x: HalfF16) -> u16 {
    if x.is_nan() {
        CANONICAL_NAN_F16
    } else {
        x.to_bits()
    }
}

#[inline]
fn canon_f32(x: f32) -> u32 {
    if x.is_nan() {
        CANONICAL_NAN_F32
    } else {
        x.to_bits()
    }
}

#[inline]
fn canon_f64(x: f64) -> u64 {
    if x.is_nan() {
        CANONICAL_NAN_F64
    } else {
        x.to_bits()
    }
}

// ---------------------------------------------------------------------------
// Oracle: f32 arithmetic (+, -, *, /, sqrt) and comparisons (eq, lt, le)
// ---------------------------------------------------------------------------

fn oracle_f32_add(a: u32, b: u32) -> u32 {
    canon_f32(f32::from_bits(a) + f32::from_bits(b))
}
fn oracle_f32_sub(a: u32, b: u32) -> u32 {
    canon_f32(f32::from_bits(a) - f32::from_bits(b))
}
fn oracle_f32_mul(a: u32, b: u32) -> u32 {
    canon_f32(f32::from_bits(a) * f32::from_bits(b))
}
fn oracle_f32_div(a: u32, b: u32) -> u32 {
    canon_f32(f32::from_bits(a) / f32::from_bits(b))
}
fn oracle_f32_sqrt(a: u32) -> u32 {
    canon_f32(f32::from_bits(a).sqrt())
}
fn oracle_f32_eq(a: u32, b: u32) -> bool {
    f32::from_bits(a) == f32::from_bits(b)
}
fn oracle_f32_lt(a: u32, b: u32) -> bool {
    f32::from_bits(a) < f32::from_bits(b)
}
fn oracle_f32_le(a: u32, b: u32) -> bool {
    f32::from_bits(a) <= f32::from_bits(b)
}

// ---------------------------------------------------------------------------
// Oracle: f64 arithmetic and comparisons
// ---------------------------------------------------------------------------

fn oracle_f64_add(a: u64, b: u64) -> u64 {
    canon_f64(f64::from_bits(a) + f64::from_bits(b))
}
fn oracle_f64_sub(a: u64, b: u64) -> u64 {
    canon_f64(f64::from_bits(a) - f64::from_bits(b))
}
fn oracle_f64_mul(a: u64, b: u64) -> u64 {
    canon_f64(f64::from_bits(a) * f64::from_bits(b))
}
fn oracle_f64_div(a: u64, b: u64) -> u64 {
    canon_f64(f64::from_bits(a) / f64::from_bits(b))
}
fn oracle_f64_sqrt(a: u64) -> u64 {
    canon_f64(f64::from_bits(a).sqrt())
}
fn oracle_f64_eq(a: u64, b: u64) -> bool {
    f64::from_bits(a) == f64::from_bits(b)
}
fn oracle_f64_lt(a: u64, b: u64) -> bool {
    f64::from_bits(a) < f64::from_bits(b)
}
fn oracle_f64_le(a: u64, b: u64) -> bool {
    f64::from_bits(a) <= f64::from_bits(b)
}

// ---------------------------------------------------------------------------
// Oracle: f16 via half::f16 (IEEE 754 half-precision, f32-widening semantics)
// ---------------------------------------------------------------------------

fn oracle_f16_add(a: u16, b: u16) -> u16 {
    canon_f16(HalfF16::from_bits(a) + HalfF16::from_bits(b))
}
fn oracle_f16_sub(a: u16, b: u16) -> u16 {
    canon_f16(HalfF16::from_bits(a) - HalfF16::from_bits(b))
}
fn oracle_f16_mul(a: u16, b: u16) -> u16 {
    canon_f16(HalfF16::from_bits(a) * HalfF16::from_bits(b))
}
fn oracle_f16_div(a: u16, b: u16) -> u16 {
    canon_f16(HalfF16::from_bits(a) / HalfF16::from_bits(b))
}
/// f16 sqrt: compute via f32 (f32 has 13 extra mantissa bits over f16 -- no double-rounding
/// hazard for sqrt since true sqrt of a normal f16 is not a midpoint in f32 space).
fn oracle_f16_sqrt(a: u16) -> u16 {
    let a_f32 = HalfF16::from_bits(a).to_f32();
    let result_f32 = a_f32.sqrt();
    canon_f16(HalfF16::from_f32(result_f32))
}
fn oracle_f16_eq(a: u16, b: u16) -> bool {
    HalfF16::from_bits(a) == HalfF16::from_bits(b)
}
fn oracle_f16_lt(a: u16, b: u16) -> bool {
    HalfF16::from_bits(a) < HalfF16::from_bits(b)
}
fn oracle_f16_le(a: u16, b: u16) -> bool {
    HalfF16::from_bits(a) <= HalfF16::from_bits(b)
}

// ---------------------------------------------------------------------------
// Oracle: abs (sq-dtmg9).
//
// IEEE 754-2019 5.5.1 DEFINES abs(x) as the bit-level copy with the sign bit
// set to 0 (quiet, payload-preserving, no exceptions), so the oracle IS the
// spec formula.  The unit tests cross-check it against hardware f32::abs /
// f64::abs on non-NaN values.  What the differential rows then verify is the
// circuit's decode -> sign-clear -> re-encode path, including NaN payloads.
// ---------------------------------------------------------------------------

fn oracle_f16_abs(a: u16) -> u16 {
    a & 0x7FFF
}
fn oracle_f32_abs(a: u32) -> u32 {
    a & 0x7FFF_FFFF
}
fn oracle_f64_abs(a: u64) -> u64 {
    a & 0x7FFF_FFFF_FFFF_FFFF
}

// ---------------------------------------------------------------------------
// Oracle: from_field / to_field (sq-dtmg9).
//
// from_field interprets the field element as an unsigned integer < 2^128 and
// rounds to nearest-even -- Rust guarantees correctly-rounded (RNE) integer ->
// float casts, so `v as f32` / `v as f64` is a conformant hardware oracle.
// to_field truncates toward zero via the to_u64 kernel; the oracle mirrors its
// domain (None = the circuit must reject: NaN, inf, >= 2^64, <= -1).
// ---------------------------------------------------------------------------

fn oracle_f32_from_field(v: u128) -> u32 {
    (v as f32).to_bits()
}
fn oracle_f64_from_field(v: u128) -> u64 {
    (v as f64).to_bits()
}

fn oracle_f64_to_field(a: u64) -> Option<u64> {
    let x = f64::from_bits(a);
    if x.is_nan() || x.is_infinite() {
        return None;
    }
    let t = x.trunc();
    if t <= -1.0 || t >= 18446744073709551616.0 {
        return None;
    }
    // (-1, 0) truncates to -0.0; the saturating float->int cast maps it to 0,
    // matching the circuit's truncate-toward-zero window.
    Some(t as u64)
}

fn oracle_f32_to_field(a: u32) -> Option<u64> {
    oracle_f64_to_field((f64::from(f32::from_bits(a))).to_bits())
}

// ---------------------------------------------------------------------------
// Corner-case input sets (per type)
// ---------------------------------------------------------------------------

/// Well-known f16 corner-case bit patterns (sign, exponent, mantissa extremes).
fn f16_corners() -> Vec<u16> {
    vec![
        0x0000, // +0
        0x8000, // -0
        0x7C00, // +inf
        0xFC00, // -inf
        0x7E00, // canonical quiet NaN
        0x0001, // min positive subnormal
        0x03FF, // max subnormal
        0x0400, // min positive normal
        0x7BFF, // max finite normal
        0x3C00, // 1.0
        0x4000, // 2.0
        0xBC00, // -1.0
        0x3800, // 0.5
        0x3E00, // 1.5
        0x2400, // 2^-9 (exponent-range midpoint)
    ]
}

/// Well-known f32 corner-case bit patterns.
fn f32_corners() -> Vec<u32> {
    vec![
        0x00000000, // +0
        0x80000000, // -0
        0x7F800000, // +inf
        0xFF800000, // -inf
        0x7FC00000, // canonical quiet NaN
        0x7F800001, // signaling NaN (x86: any nonzero mantissa, quiet=0)
        0x00000001, // min positive subnormal
        0x007FFFFF, // max subnormal
        0x00800000, // min positive normal
        0x7F7FFFFF, // max finite normal
        0x3F800000, // 1.0
        0x40000000, // 2.0
        0xBF800000, // -1.0
        0x3F000000, // 0.5
        0x3FC00000, // 1.5
        0x33800000, // 2^-24 (ties-to-even boundary when added to 1.0)
    ]
}

/// Well-known f64 corner-case bit patterns.
fn f64_corners() -> Vec<u64> {
    vec![
        0x0000000000000000, // +0
        0x8000000000000000, // -0
        0x7FF0000000000000, // +inf
        0xFFF0000000000000, // -inf
        0x7FF8000000000000, // canonical quiet NaN
        0x7FF0000000000001, // signaling NaN (quiet=0, nonzero payload)
        0x0000000000000001, // min positive subnormal
        0x000FFFFFFFFFFFFF, // max subnormal
        0x0010000000000000, // min positive normal
        0x7FEFFFFFFFFFFFFF, // max finite normal
        0x3FF0000000000000, // 1.0
        0x4000000000000000, // 2.0
        0xBFF0000000000000, // -1.0
        0x3FE0000000000000, // 0.5
        0x3FF8000000000000, // 1.5
        0x3CA0000000000000, // 2^-53 (ties-to-even boundary when added to 1.0)
    ]
}

/// f16 bit patterns for comparison tests (NaN included).
/// IEEE 754: any ordered comparison (eq/lt/le) with NaN is deterministically false;
/// the output is a bool so NaN payload is irrelevant to the result.
fn f16_cmp_corners() -> Vec<u16> {
    vec![
        0x0000, // +0
        0x8000, // -0
        0x7C00, // +inf
        0xFC00, // -inf
        0x0001, // min subnormal
        0x03FF, // max subnormal
        0x0400, // min normal
        0x7BFF, // max normal
        0x3C00, // 1.0
        0xBC00, // -1.0
        0x7E00, // quiet NaN (canonical) -- eq/lt/le with NaN always false
        0x7C01, // signaling NaN -- same IEEE 754 ordered-comparison rule
    ]
}

fn f32_cmp_corners() -> Vec<u32> {
    vec![
        0x00000000, // +0
        0x80000000, // -0
        0x7F800000, // +inf
        0xFF800000, // -inf
        0x00000001, // min subnormal
        0x007FFFFF, // max subnormal
        0x00800000, // min normal
        0x7F7FFFFF, // max normal
        0x3F800000, // 1.0
        0xBF800000, // -1.0
        0x7FC00000, // quiet NaN (canonical) -- eq/lt/le with NaN always false
        0x7F800001, // signaling NaN -- same IEEE 754 ordered-comparison rule
    ]
}

fn f64_cmp_corners() -> Vec<u64> {
    vec![
        0x0000000000000000, // +0
        0x8000000000000000, // -0
        0x7FF0000000000000, // +inf
        0xFFF0000000000000, // -inf
        0x0000000000000001, // min subnormal
        0x000FFFFFFFFFFFFF, // max subnormal
        0x0010000000000000, // min normal
        0x7FEFFFFFFFFFFFFF, // max normal
        0x3FF0000000000000, // 1.0
        0xBFF0000000000000, // -1.0
        0x7FF8000000000000, // quiet NaN (canonical) -- eq/lt/le with NaN always false
        0x7FF0000000000001, // signaling NaN -- same IEEE 754 ordered-comparison rule
    ]
}

// ---------------------------------------------------------------------------
// Inject-fault target tracking
// ---------------------------------------------------------------------------

/// A token for a single arithmetic vector that can have its expected value
/// bit-flipped to prove non-vacuity.  Captured from the first non-NaN, non-zero
/// f32 add result that gets emitted.
#[derive(Clone)]
struct FaultSite {
    /// Byte offset into the generated content where the expected hex literal starts
    /// (the substring after the last ", " and before " as u32);" pattern).
    /// Rather than byte-offsetting, we use a replacement approach: record the original
    /// text fragment and the faulty replacement.
    original: String,
    faulty: String,
}

// ---------------------------------------------------------------------------
// Code generation helpers
// ---------------------------------------------------------------------------

fn write_header(out: &mut String, inject_fault: bool) {
    writeln!(out, "// [SONNET-4.6] Generated by zk/ieee754/differential/src/main.rs.").unwrap();
    writeln!(out, "// oracle: native Rust f32/f64, half::f16 for f16; f128 deferred (sq-3x7dl.14.2)").unwrap();
    writeln!(out, "// seed: 0x4F52_4143_4C45_F754  (ASCII ORACLE + ieee754 hex; FIXED -- never time-based)").unwrap();
    if inject_fault {
        writeln!(out, "// INJECT-FAULT: one expected value has been bit-flipped for self-test.").unwrap();
        writeln!(out, "// nargo test on this file MUST fail -- that is the point.").unwrap();
    }
    writeln!(out, "// DO NOT EDIT BY HAND.  Regenerate: cd zk/ieee754 && bash scripts/run_differential_harness.sh --update-committed").unwrap();
    writeln!(out, "//").unwrap();
    writeln!(out, "// TCB: oracle is INDEPENDENT of sparq_ieee754 (native CPU hardware / half crate).").unwrap();
    writeln!(out, "// Sample coverage: {} random pairs per arithmetic op, {} per comparison op.", RANDOM_ARITH_PER_OP, RANDOM_CMP_PER_OP).unwrap();
    writeln!(out, "// This is VERIFICATION not proof: ACIR->Barretenberg lowering is NOT covered here.").unwrap();
    writeln!(out).unwrap();
    writeln!(out, "use sparq_ieee754::{{f16, f32, f64}};").unwrap();
    writeln!(out).unwrap();
}

/// Format an f16 arithmetic assert_eq line.
fn f16_arith_line(a: u16, b: u16, expected: u16, op_sym: &str) -> String {
    format!(
        "    assert_eq((f16::new(0x{:04x} as u16) {} f16::new(0x{:04x} as u16)).bits(), 0x{:04x} as u16);",
        a, op_sym, b, expected
    )
}

/// Format an f16 sqrt assert_eq line.
fn f16_sqrt_line(a: u16, expected: u16) -> String {
    format!(
        "    assert_eq(f16::new(0x{:04x} as u16).sqrt().bits(), 0x{:04x} as u16);",
        a, expected
    )
}

/// Format an f32 arithmetic assert_eq line.
fn f32_arith_line(a: u32, b: u32, expected: u32, op_sym: &str) -> String {
    format!(
        "    assert_eq((f32::new(0x{:08x} as u32) {} f32::new(0x{:08x} as u32)).bits(), 0x{:08x} as u32);",
        a, op_sym, b, expected
    )
}

fn f32_sqrt_line(a: u32, expected: u32) -> String {
    format!(
        "    assert_eq(f32::new(0x{:08x} as u32).sqrt().bits(), 0x{:08x} as u32);",
        a, expected
    )
}

fn f64_arith_line(a: u64, b: u64, expected: u64, op_sym: &str) -> String {
    format!(
        "    assert_eq((f64::new(0x{:016x} as u64) {} f64::new(0x{:016x} as u64)).bits(), 0x{:016x} as u64);",
        a, op_sym, b, expected
    )
}

fn f64_sqrt_line(a: u64, expected: u64) -> String {
    format!(
        "    assert_eq(f64::new(0x{:016x} as u64).sqrt().bits(), 0x{:016x} as u64);",
        a, expected
    )
}

/// Format an f32 comparison assert_eq line.
fn f32_cmp_line(a: u32, b: u32, expected: bool, method: &str) -> String {
    format!(
        "    assert_eq(f32::new(0x{:08x} as u32).{}(f32::new(0x{:08x} as u32)), {});",
        a, method, b, expected
    )
}

fn f64_cmp_line(a: u64, b: u64, expected: bool, method: &str) -> String {
    format!(
        "    assert_eq(f64::new(0x{:016x} as u64).{}(f64::new(0x{:016x} as u64)), {});",
        a, method, b, expected
    )
}

fn f16_cmp_line(a: u16, b: u16, expected: bool, method: &str) -> String {
    format!(
        "    assert_eq(f16::new(0x{:04x} as u16).{}(f16::new(0x{:04x} as u16)), {});",
        a, method, b, expected
    )
}

/// Format an abs assert_eq line for each width (sq-dtmg9).
fn f16_abs_line(a: u16, expected: u16) -> String {
    format!(
        "    assert_eq(f16::new(0x{:04x} as u16).abs().bits(), 0x{:04x} as u16);",
        a, expected
    )
}

fn f32_abs_line(a: u32, expected: u32) -> String {
    format!(
        "    assert_eq(f32::new(0x{:08x} as u32).abs().bits(), 0x{:08x} as u32);",
        a, expected
    )
}

fn f64_abs_line(a: u64, expected: u64) -> String {
    format!(
        "    assert_eq(f64::new(0x{:016x} as u64).abs().bits(), 0x{:016x} as u64);",
        a, expected
    )
}

/// Format a from_field assert_eq line (sq-dtmg9).
fn f32_from_field_line(v: u128, expected: u32) -> String {
    format!(
        "    assert_eq(f32::from_field({} as Field).bits(), 0x{:08x} as u32);",
        v, expected
    )
}

fn f64_from_field_line(v: u128, expected: u64) -> String {
    format!(
        "    assert_eq(f64::from_field({} as Field).bits(), 0x{:016x} as u64);",
        v, expected
    )
}

/// Format a to_field assert_eq line (sq-dtmg9).
fn f32_to_field_line(a: u32, expected: u64) -> String {
    format!(
        "    assert_eq(f32::new(0x{:08x} as u32).to_field(), {} as Field);",
        a, expected
    )
}

fn f64_to_field_line(a: u64, expected: u64) -> String {
    format!(
        "    assert_eq(f64::new(0x{:016x} as u64).to_field(), {} as Field);",
        a, expected
    )
}

// ---------------------------------------------------------------------------
// f32 arithmetic tests
// ---------------------------------------------------------------------------

fn gen_f32_arith(out: &mut String, rng: &mut Xorshift64, fault: &mut Option<FaultSite>) {
    let ops: &[(&str, &str, ArithF32Op)] = &[
        ("add", "+", oracle_f32_add as ArithF32Op),
        ("sub", "-", oracle_f32_sub as ArithF32Op),
        ("mul", "*", oracle_f32_mul as ArithF32Op),
        ("div", "/", oracle_f32_div as ArithF32Op),
    ];

    for (op_name, op_sym, oracle_fn) in ops {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f32_{}() {{", op_name).unwrap();

        let corners = f32_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                let line = f32_arith_line(a, b, expected, op_sym);

                // Capture first non-NaN, non-zero ADD result as fault target.
                if *op_name == "add" && fault.is_none() && expected != CANONICAL_NAN_F32 && expected != 0 {
                    let faulty_expected = expected ^ 1;
                    let faulty_line = f32_arith_line(a, b, faulty_expected, op_sym);
                    *fault = Some(FaultSite {
                        original: line.clone(),
                        faulty: faulty_line,
                    });
                }

                writeln!(out, "    // corner:{}:{}", idx, op_name).unwrap();
                writeln!(out, "{}", line).unwrap();
                idx += 1;
            }
        }

        for i in 0..RANDOM_ARITH_PER_OP {
            let a = rng.next_u32();
            let b = rng.next_u32();
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f32_arith_line(a, b, expected, op_sym)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

fn gen_f32_sqrt(out: &mut String, rng: &mut Xorshift64) {
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f32_sqrt() {{").unwrap();

    let sqrt_inputs: &[u32] = &[
        0x00000000, // sqrt(+0) = +0
        0x80000000, // sqrt(-0) = -0
        0x7F800000, // sqrt(+inf) = +inf
        0xFF800001, // sqrt(NaN) = NaN (signaling NaN input)
        0x7FC00000, // sqrt(qNaN) = qNaN
        0x3F800000, // sqrt(1.0) = 1.0
        0x40000000, // sqrt(2.0) ~ 1.41421...
        0x40800000, // sqrt(4.0) = 2.0
        0x41800000, // sqrt(16.0) = 4.0
        0x00000001, // sqrt(min subnormal)
        0x00800000, // sqrt(min normal)
        0x7F7FFFFF, // sqrt(max normal)
        // Negative real inputs: sparq_ieee754 codegen.nr:237 contract -- sqrt(x<0) = canonical NaN.
        0xBF800000, // sqrt(-1.0) = canonical NaN
        0x80800000, // sqrt(-min_normal) = canonical NaN
        0xFF7FFFFF, // sqrt(-max_normal) = canonical NaN
    ];

    for (i, &a) in sqrt_inputs.iter().enumerate() {
        let expected = oracle_f32_sqrt(a);
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f32_sqrt_line(a, expected)).unwrap();
    }

    // Random non-negative inputs for sqrt.
    for i in 0..RANDOM_ARITH_PER_OP {
        // Clear sign bit to get non-negative inputs (avoids NaN from sqrt(-x)).
        let a = rng.next_u32() & 0x7FFFFFFF;
        let expected = oracle_f32_sqrt(a);
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f32_sqrt_line(a, expected)).unwrap();
    }

    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

// ---------------------------------------------------------------------------
// Comparison tests (f32, f64, f16).
// IEEE 754: any ordered comparison (eq/lt/le) with NaN is deterministically false;
// comparison outputs are bools so NaN payload is irrelevant.  NaN corners included.
// ---------------------------------------------------------------------------

fn gen_f32_cmps(out: &mut String, rng: &mut Xorshift64) {
    let cmps: &[(&str, CmpF32Op)] = &[
        ("eq", oracle_f32_eq as CmpF32Op),
        ("lt", oracle_f32_lt as CmpF32Op),
        ("le", oracle_f32_le as CmpF32Op),
    ];

    for (method, oracle_fn) in cmps {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f32_{}() {{", method).unwrap();

        let corners = f32_cmp_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                writeln!(out, "    // corner:{}", idx).unwrap();
                writeln!(out, "{}", f32_cmp_line(a, b, expected, method)).unwrap();
                idx += 1;
            }
        }

        // Random non-NaN inputs.
        for i in 0..RANDOM_CMP_PER_OP {
            // Avoid NaN by keeping exponent < 0xFF (i.e. < 0x7F800000 absolute).
            let a = rng.next_u32() & 0xFF7FFFFF;
            let b = rng.next_u32() & 0xFF7FFFFF;
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f32_cmp_line(a, b, expected, method)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

// ---------------------------------------------------------------------------
// f64 arithmetic tests
// ---------------------------------------------------------------------------

fn gen_f64_arith(out: &mut String, rng: &mut Xorshift64) {
    let ops: &[(&str, &str, ArithF64Op)] = &[
        ("add", "+", oracle_f64_add as ArithF64Op),
        ("sub", "-", oracle_f64_sub as ArithF64Op),
        ("mul", "*", oracle_f64_mul as ArithF64Op),
        ("div", "/", oracle_f64_div as ArithF64Op),
    ];

    for (op_name, op_sym, oracle_fn) in ops {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f64_{}() {{", op_name).unwrap();

        let corners = f64_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                writeln!(out, "    // corner:{}:{}", idx, op_name).unwrap();
                writeln!(out, "{}", f64_arith_line(a, b, expected, op_sym)).unwrap();
                idx += 1;
            }
        }

        for i in 0..RANDOM_ARITH_PER_OP {
            let a = rng.next_u64();
            let b = rng.next_u64();
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f64_arith_line(a, b, expected, op_sym)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

fn gen_f64_sqrt(out: &mut String, rng: &mut Xorshift64) {
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f64_sqrt() {{").unwrap();

    let sqrt_inputs: &[u64] = &[
        0x0000000000000000, // sqrt(+0) = +0
        0x8000000000000000, // sqrt(-0) = -0
        0x7FF0000000000000, // sqrt(+inf) = +inf
        0x7FF0000000000001, // sqrt(sNaN) = qNaN
        0x7FF8000000000000, // sqrt(qNaN) = qNaN
        0x3FF0000000000000, // sqrt(1.0) = 1.0
        0x4000000000000000, // sqrt(2.0) ~ 1.41421...
        0x4010000000000000, // sqrt(4.0) = 2.0
        0x4030000000000000, // sqrt(16.0) = 4.0
        0x0000000000000001, // sqrt(min subnormal)
        0x0010000000000000, // sqrt(min normal)
        0x7FEFFFFFFFFFFFFF, // sqrt(max normal)
        // Negative real inputs: sparq_ieee754 codegen.nr:237 contract -- sqrt(x<0) = canonical NaN.
        0xBFF0000000000000, // sqrt(-1.0) = canonical NaN
        0x8010000000000000, // sqrt(-min_normal) = canonical NaN
        0xFFEFFFFFFFFFFFFF, // sqrt(-max_normal) = canonical NaN
    ];

    for (i, &a) in sqrt_inputs.iter().enumerate() {
        let expected = oracle_f64_sqrt(a);
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f64_sqrt_line(a, expected)).unwrap();
    }

    for i in 0..RANDOM_ARITH_PER_OP {
        let a = rng.next_u64() & 0x7FFFFFFFFFFFFFFF;
        let expected = oracle_f64_sqrt(a);
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f64_sqrt_line(a, expected)).unwrap();
    }

    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

fn gen_f64_cmps(out: &mut String, rng: &mut Xorshift64) {
    let cmps: &[(&str, CmpF64Op)] = &[
        ("eq", oracle_f64_eq as CmpF64Op),
        ("lt", oracle_f64_lt as CmpF64Op),
        ("le", oracle_f64_le as CmpF64Op),
    ];

    for (method, oracle_fn) in cmps {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f64_{}() {{", method).unwrap();

        let corners = f64_cmp_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                writeln!(out, "    // corner:{}", idx).unwrap();
                writeln!(out, "{}", f64_cmp_line(a, b, expected, method)).unwrap();
                idx += 1;
            }
        }

        for i in 0..RANDOM_CMP_PER_OP {
            let a = rng.next_u64() & 0xFFEFFFFFFFFFFFFF;
            let b = rng.next_u64() & 0xFFEFFFFFFFFFFFFF;
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f64_cmp_line(a, b, expected, method)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

// ---------------------------------------------------------------------------
// f16 arithmetic tests
// ---------------------------------------------------------------------------

fn gen_f16_arith(out: &mut String, rng: &mut Xorshift64) {
    let ops: &[(&str, &str, ArithF16Op)] = &[
        ("add", "+", oracle_f16_add as ArithF16Op),
        ("sub", "-", oracle_f16_sub as ArithF16Op),
        ("mul", "*", oracle_f16_mul as ArithF16Op),
        ("div", "/", oracle_f16_div as ArithF16Op),
    ];

    for (op_name, op_sym, oracle_fn) in ops {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f16_{}() {{", op_name).unwrap();

        let corners = f16_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                writeln!(out, "    // corner:{}:{}", idx, op_name).unwrap();
                writeln!(out, "{}", f16_arith_line(a, b, expected, op_sym)).unwrap();
                idx += 1;
            }
        }

        for i in 0..RANDOM_ARITH_PER_OP {
            let a = rng.next_u16();
            let b = rng.next_u16();
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f16_arith_line(a, b, expected, op_sym)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

fn gen_f16_sqrt(out: &mut String, rng: &mut Xorshift64) {
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f16_sqrt() {{").unwrap();

    let sqrt_inputs: &[u16] = &[
        0x0000, // sqrt(+0) = +0
        0x8000, // sqrt(-0) = -0
        0x7C00, // sqrt(+inf) = +inf
        0x7E00, // sqrt(qNaN) = qNaN
        0x3C00, // sqrt(1.0) = 1.0
        0x4000, // sqrt(2.0) ~ 1.41421...
        0x4400, // sqrt(4.0) = 2.0
        0x4C00, // sqrt(16.0) = 4.0
        0x0001, // sqrt(min subnormal)
        0x0400, // sqrt(min normal)
        0x7BFF, // sqrt(max normal)
        // Negative real inputs: sparq_ieee754 codegen.nr:237 contract -- sqrt(x<0) = canonical NaN.
        0xBC00, // sqrt(-1.0_f16) = canonical NaN
        0x8400, // sqrt(-min_normal_f16) = canonical NaN
        0xFBFF, // sqrt(-max_normal_f16) = canonical NaN
    ];

    for (i, &a) in sqrt_inputs.iter().enumerate() {
        let expected = oracle_f16_sqrt(a);
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f16_sqrt_line(a, expected)).unwrap();
    }

    for i in 0..RANDOM_ARITH_PER_OP {
        let a = rng.next_u16() & 0x7FFF;
        let expected = oracle_f16_sqrt(a);
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f16_sqrt_line(a, expected)).unwrap();
    }

    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

fn gen_f16_cmps(out: &mut String, rng: &mut Xorshift64) {
    let cmps: &[(&str, CmpF16Op)] = &[
        ("eq", oracle_f16_eq as CmpF16Op),
        ("lt", oracle_f16_lt as CmpF16Op),
        ("le", oracle_f16_le as CmpF16Op),
    ];

    for (method, oracle_fn) in cmps {
        writeln!(out, "#[test]").unwrap();
        writeln!(out, "fn differential_oracle_f16_{}() {{", method).unwrap();

        let corners = f16_cmp_corners();
        let mut idx = 0usize;
        for &a in &corners {
            for &b in &corners {
                let expected = oracle_fn(a, b);
                writeln!(out, "    // corner:{}", idx).unwrap();
                writeln!(out, "{}", f16_cmp_line(a, b, expected, method)).unwrap();
                idx += 1;
            }
        }

        // Random inputs: mask clears exponent-LSB (bit 10) to avoid inf/NaN;
        // sign bit (bit 15) is preserved so negative values are included.
        for i in 0..RANDOM_CMP_PER_OP {
            let a = rng.next_u16() & 0xFBFF;
            let b = rng.next_u16() & 0xFBFF;
            let expected = oracle_fn(a, b);
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f16_cmp_line(a, b, expected, method)).unwrap();
        }

        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }
}

// ---------------------------------------------------------------------------
// abs tests (sq-dtmg9): all three oracle-covered widths, with NaN-payload and
// negative-sNaN probes (abs must preserve payloads and only clear the sign).
// ---------------------------------------------------------------------------

fn gen_abs(out: &mut String, rng: &mut Xorshift64) {
    // f16 -----------------------------------------------------------------
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f16_abs() {{").unwrap();
    let mut f16_inputs = f16_corners();
    f16_inputs.extend_from_slice(&[
        0x7E01, // qNaN with payload
        0xFE01, // negative qNaN with payload
        0xFD00, // negative sNaN pattern
        0x8001, // -min_subnormal
    ]);
    for (i, &a) in f16_inputs.iter().enumerate() {
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f16_abs_line(a, oracle_f16_abs(a))).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        let a = rng.next_u16();
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f16_abs_line(a, oracle_f16_abs(a))).unwrap();
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();

    // f32 -----------------------------------------------------------------
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f32_abs() {{").unwrap();
    let mut f32_inputs = f32_corners();
    f32_inputs.extend_from_slice(&[
        0x7FC00001, // qNaN with payload
        0xFFC00001, // negative qNaN with payload
        0xFFA00000, // negative sNaN pattern
        0x80000001, // -min_subnormal
    ]);
    for (i, &a) in f32_inputs.iter().enumerate() {
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f32_abs_line(a, oracle_f32_abs(a))).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        let a = rng.next_u32();
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f32_abs_line(a, oracle_f32_abs(a))).unwrap();
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();

    // f64 -----------------------------------------------------------------
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f64_abs() {{").unwrap();
    let mut f64_inputs = f64_corners();
    f64_inputs.extend_from_slice(&[
        0x7FF8000000000001, // qNaN with payload
        0xFFF8000000000001, // negative qNaN with payload
        0xFFF4000000000000, // negative sNaN pattern
        0x8000000000000001, // -min_subnormal
    ]);
    for (i, &a) in f64_inputs.iter().enumerate() {
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f64_abs_line(a, oracle_f64_abs(a))).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        let a = rng.next_u64();
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f64_abs_line(a, oracle_f64_abs(a))).unwrap();
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

// ---------------------------------------------------------------------------
// from_field / to_field tests (sq-dtmg9).
//
// from_field corpus: rounding boundaries at 2^24 / 2^53 (first inexact
// integers for f32/f64), the u64/u128 extremes, and random 64/128-bit values.
// Rust int->float casts are correctly rounded (RNE), so the hardware cast is
// the oracle.  f16/f128 from_field is covered by the exact-rational generated
// vectors instead (no conformant hardware oracle for those widths here).
// ---------------------------------------------------------------------------

fn from_field_corners() -> Vec<u128> {
    vec![
        0,
        1,
        2,
        3,
        (1 << 24) - 1,
        (1 << 24) + 1,
        (1 << 24) + 3,
        (1 << 53) - 1,
        (1 << 53) + 1,
        (1 << 53) + 3,
        1 << 63,
        u64::MAX as u128,
        (u64::MAX as u128) + 1,
        1 << 127,
        u128::MAX,
    ]
}

fn gen_from_field(out: &mut String, rng: &mut Xorshift64) {
    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f32_from_field() {{").unwrap();
    for (i, &v) in from_field_corners().iter().enumerate() {
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f32_from_field_line(v, oracle_f32_from_field(v))).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        // Alternate 64-bit and 128-bit magnitudes.
        let v = if i % 2 == 0 {
            rng.next_u64() as u128
        } else {
            ((rng.next_u64() as u128) << 64) | rng.next_u64() as u128
        };
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f32_from_field_line(v, oracle_f32_from_field(v))).unwrap();
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();

    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f64_from_field() {{").unwrap();
    for (i, &v) in from_field_corners().iter().enumerate() {
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f64_from_field_line(v, oracle_f64_from_field(v))).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        let v = if i % 2 == 0 {
            rng.next_u64() as u128
        } else {
            ((rng.next_u64() as u128) << 64) | rng.next_u64() as u128
        };
        writeln!(out, "    // random:{}", i).unwrap();
        writeln!(out, "{}", f64_from_field_line(v, oracle_f64_from_field(v))).unwrap();
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

fn gen_to_field(out: &mut String, rng: &mut Xorshift64) {
    // Curated in-range f64 inputs (bit patterns).
    let f64_inputs: &[u64] = &[
        0x0000000000000000, // +0
        0x8000000000000000, // -0
        0x3FF0000000000000, // 1.0
        0x400E000000000000, // 3.75 -> 3
        0x3FE0000000000000, // 0.5 -> 0
        0xBFE0000000000000, // -0.5 -> 0 (negative truncation window)
        0x43E0000000000000, // 2^63
        0x43EFFFFFFFFFFFFF, // largest f64 below 2^64
        0x4340000000000000, // 2^53
    ];

    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f64_to_field() {{").unwrap();
    for (i, &a) in f64_inputs.iter().enumerate() {
        let expected = oracle_f64_to_field(a)
            .expect("curated f64 to_field corner must be in the valid domain");
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f64_to_field_line(a, expected)).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        // Compose an in-range value: a variable-magnitude integer part plus a
        // fractional part, so truncation is exercised across magnitudes.
        let int_part = rng.next_u64() >> (i % 33);
        let frac = (rng.next_u64() % 1000) as f64 / 1000.0;
        let bits = (int_part as f64 + frac).to_bits();
        if let Some(expected) = oracle_f64_to_field(bits) {
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f64_to_field_line(bits, expected)).unwrap();
        }
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();

    let f32_inputs: &[u32] = &[
        0x00000000, // +0
        0x80000000, // -0
        0x3F800000, // 1.0
        0x40700000, // 3.75 -> 3
        0xBF000000, // -0.5 -> 0
        0x5F000000, // 2^63
        0x5F7FFFFF, // largest f32 below 2^64
    ];

    writeln!(out, "#[test]").unwrap();
    writeln!(out, "fn differential_oracle_f32_to_field() {{").unwrap();
    for (i, &a) in f32_inputs.iter().enumerate() {
        let expected = oracle_f32_to_field(a)
            .expect("curated f32 to_field corner must be in the valid domain");
        writeln!(out, "    // corner:{}", i).unwrap();
        writeln!(out, "{}", f32_to_field_line(a, expected)).unwrap();
    }
    for i in 0..RANDOM_ARITH_PER_OP {
        let int_part = (rng.next_u32() >> (i % 17)) as f32;
        let frac = (rng.next_u32() % 1000) as f32 / 1000.0;
        let bits = (int_part + frac).to_bits();
        if let Some(expected) = oracle_f32_to_field(bits) {
            writeln!(out, "    // random:{}", i).unwrap();
            writeln!(out, "{}", f32_to_field_line(bits, expected)).unwrap();
        }
    }
    writeln!(out, "}}").unwrap();
    writeln!(out).unwrap();
}

// ---------------------------------------------------------------------------
// f128 deferral note
// ---------------------------------------------------------------------------

fn gen_f128_deferral(out: &mut String) {
    writeln!(out, "// f128 differential oracle: DEFERRED to sq-3x7dl.14.2.").unwrap();
    writeln!(out, "// Reason: Rust `f128` is nightly-only (unstable) and no stable soft-float").unwrap();
    writeln!(out, "// binding with verified IEEE 754 quad-precision conformance is available").unwrap();
    writeln!(out, "// without heavy external deps (MPFR C bindings, etc.).  The sparq_ieee754").unwrap();
    writeln!(out, "// f128 type uses a `u128`/Field 'wide kernel' that is tested by the Noir").unwrap();
    writeln!(out, "// unit tests in src/lib.nr; a proper differential oracle will be added when").unwrap();
    writeln!(out, "// a stable Rust f128 type or a suitable pure-Rust soft-float crate is available.").unwrap();
    writeln!(out).unwrap();
}

// ---------------------------------------------------------------------------
// Top-level generator
// ---------------------------------------------------------------------------

/// Generate the complete Noir test file content.
///
/// If `inject_fault` is true, one expected value is bit-flipped so that
/// `nargo test` on this file MUST fail (proving non-vacuity).
pub fn generate_noir_file(inject_fault: bool) -> String {
    let mut out = String::with_capacity(128 * 1024);
    let mut rng = Xorshift64::new(SEED);
    let mut fault: Option<FaultSite> = None;

    write_header(&mut out, inject_fault);

    // Generate all test functions.
    gen_f32_arith(&mut out, &mut rng, &mut fault);
    gen_f32_sqrt(&mut out, &mut rng);
    gen_f32_cmps(&mut out, &mut rng);

    gen_f64_arith(&mut out, &mut rng);
    gen_f64_sqrt(&mut out, &mut rng);
    gen_f64_cmps(&mut out, &mut rng);

    gen_f16_arith(&mut out, &mut rng);
    gen_f16_sqrt(&mut out, &mut rng);
    gen_f16_cmps(&mut out, &mut rng);

    // sq-dtmg9 additions: abs, from_field, to_field.
    gen_abs(&mut out, &mut rng);
    gen_from_field(&mut out, &mut rng);
    gen_to_field(&mut out, &mut rng);

    gen_f128_deferral(&mut out);

    if inject_fault {
        // Apply the fault: replace the captured line with the bit-flipped version.
        if let Some(site) = fault {
            out = out.replacen(&site.original, &site.faulty, 1);
            eprintln!(
                "inject-fault: flipped expected bits in line:\n  was: {}\n  now: {}",
                site.original.trim(),
                site.faulty.trim()
            );
        } else {
            eprintln!("WARNING: no fault site found -- inject-fault has no effect");
        }
    }

    out
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut output_path: Option<String> = None;
    let mut inject_fault = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--output" | "-o" => {
                i += 1;
                if let Some(p) = args.get(i) {
                    output_path = Some(p.clone());
                }
            }
            "--inject-fault" => {
                inject_fault = true;
                i += 1;
                if let Some(p) = args.get(i) {
                    output_path = Some(p.clone());
                }
            }
            _ => {}
        }
        i += 1;
    }

    let path = output_path.unwrap_or_else(|| {
        eprintln!("Usage:");
        eprintln!("  sparq-ieee754-differential --output <path>");
        eprintln!("  sparq-ieee754-differential --inject-fault <path>");
        std::process::exit(1);
    });

    let content = generate_noir_file(inject_fault);

    // Ensure parent directory exists.
    if let Some(parent) = std::path::Path::new(&path).parent() {
        std::fs::create_dir_all(parent).expect("failed to create output directory");
    }

    std::fs::write(&path, content.as_bytes()).expect("failed to write output file");
    eprintln!("Written {} bytes to {}", content.len(), path);
}

// ---------------------------------------------------------------------------
// Unit tests (required: one per public fn for coverage-ratchet gate)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// canon_f32: NaN -> canonical NaN, non-NaN passes through.
    #[test]
    fn test_canon_f32_nan() {
        assert_eq!(canon_f32(f32::NAN), CANONICAL_NAN_F32);
        assert_eq!(canon_f32(f32::INFINITY), f32::INFINITY.to_bits());
        assert_eq!(canon_f32(1.0_f32), 1.0_f32.to_bits());
        assert_eq!(canon_f32(-1.0_f32), (-1.0_f32).to_bits());
    }

    /// canon_f64: NaN -> canonical NaN, non-NaN passes through.
    #[test]
    fn test_canon_f64_nan() {
        assert_eq!(canon_f64(f64::NAN), CANONICAL_NAN_F64);
        assert_eq!(canon_f64(f64::INFINITY), f64::INFINITY.to_bits());
        assert_eq!(canon_f64(1.0_f64), 1.0_f64.to_bits());
    }

    /// canon_f16: NaN -> canonical NaN, non-NaN passes through.
    #[test]
    fn test_canon_f16_nan() {
        assert_eq!(canon_f16(HalfF16::NAN), CANONICAL_NAN_F16);
        assert_eq!(canon_f16(HalfF16::INFINITY), HalfF16::INFINITY.to_bits());
        assert_eq!(canon_f16(HalfF16::from_f32(1.0)), HalfF16::from_f32(1.0).to_bits());
    }

    /// oracle_f32_add: spot check a few well-known results.
    #[test]
    fn test_oracle_f32_add_known() {
        // 1.0 + 1.0 = 2.0
        assert_eq!(oracle_f32_add(0x3F800000, 0x3F800000), 0x40000000);
        // +inf + -inf = NaN (canonical)
        assert_eq!(oracle_f32_add(0x7F800000, 0xFF800000), CANONICAL_NAN_F32);
        // +0 + -0 = +0
        assert_eq!(oracle_f32_add(0x00000000, 0x80000000), 0x00000000);
    }

    /// oracle_f64_mul: spot check.
    #[test]
    fn test_oracle_f64_mul_known() {
        // 2.0 * 2.0 = 4.0
        assert_eq!(oracle_f64_mul(0x4000000000000000, 0x4000000000000000), 0x4010000000000000);
        // 0.0 * inf = NaN
        assert_eq!(oracle_f64_mul(0x0000000000000000, 0x7FF0000000000000), CANONICAL_NAN_F64);
    }

    /// oracle_f16_add: spot check with known half-precision values.
    #[test]
    fn test_oracle_f16_add_known() {
        // 1.0 + 1.0 = 2.0 in f16: 0x3C00 + 0x3C00 = 0x4000
        assert_eq!(oracle_f16_add(0x3C00, 0x3C00), 0x4000);
        // +inf + -inf = canonical NaN
        assert_eq!(oracle_f16_add(0x7C00, 0xFC00), CANONICAL_NAN_F16);
    }

    /// oracle_f32_sqrt: well-known cases.
    #[test]
    fn test_oracle_f32_sqrt_known() {
        // sqrt(1.0) = 1.0
        assert_eq!(oracle_f32_sqrt(0x3F800000), 0x3F800000);
        // sqrt(4.0) = 2.0
        assert_eq!(oracle_f32_sqrt(0x40800000), 0x40000000);
        // sqrt(-1.0) = NaN
        assert_eq!(oracle_f32_sqrt(0xBF800000), CANONICAL_NAN_F32);
    }

    /// oracle_f32_eq: IEEE -0 == +0.
    #[test]
    fn test_oracle_f32_eq_zero_sign() {
        // IEEE 754: -0 == +0
        assert!(oracle_f32_eq(0x00000000, 0x80000000));
        assert!(oracle_f32_eq(0x80000000, 0x00000000));
        // 1.0 != 2.0
        assert!(!oracle_f32_eq(0x3F800000, 0x40000000));
    }

    /// oracle_f32_lt: some ordered pairs.
    #[test]
    fn test_oracle_f32_lt_ordered() {
        // 1.0 < 2.0
        assert!(oracle_f32_lt(0x3F800000, 0x40000000));
        // 2.0 is not < 1.0
        assert!(!oracle_f32_lt(0x40000000, 0x3F800000));
        // -inf < +inf
        assert!(oracle_f32_lt(0xFF800000, 0x7F800000));
    }

    /// Xorshift64 is deterministic from the fixed seed.
    #[test]
    fn test_xorshift64_deterministic() {
        let mut rng = Xorshift64::new(SEED);
        let first = rng.next();
        let second = rng.next();
        // Values must be non-zero and different from each other and the seed.
        assert_ne!(first, 0);
        assert_ne!(first, second);
        assert_ne!(first, SEED);
        // Reset and confirm same sequence.
        let mut rng2 = Xorshift64::new(SEED);
        assert_eq!(rng2.next(), first);
        assert_eq!(rng2.next(), second);
    }

    /// generate_noir_file: output is non-empty, pure-ASCII, contains expected markers.
    #[test]
    fn test_generate_noir_file_structure() {
        let content = generate_noir_file(false);
        assert!(!content.is_empty());
        // Must be pure ASCII (no unicode chars in generated Noir source).
        assert!(content.is_ascii(), "generated Noir file contains non-ASCII characters");
        // Must contain required header markers.
        assert!(content.contains("[SONNET-4.6]"));
        assert!(content.contains("0x4F52_4143_4C45_F754"));
        // Must have test functions for each type/op.
        assert!(content.contains("fn differential_oracle_f32_add()"));
        assert!(content.contains("fn differential_oracle_f64_sqrt()"));
        assert!(content.contains("fn differential_oracle_f16_eq()"));
        // sq-dtmg9 additions.
        assert!(content.contains("fn differential_oracle_f16_abs()"));
        assert!(content.contains("fn differential_oracle_f32_abs()"));
        assert!(content.contains("fn differential_oracle_f64_abs()"));
        assert!(content.contains("fn differential_oracle_f32_from_field()"));
        assert!(content.contains("fn differential_oracle_f64_from_field()"));
        assert!(content.contains("fn differential_oracle_f32_to_field()"));
        assert!(content.contains("fn differential_oracle_f64_to_field()"));
        // Must NOT import f128 (we do not test it -- see deferral comment).
        assert!(!content.contains("use sparq_ieee754::{f16, f32, f64, f128}"));
        // f128 deferral comment must be present.
        assert!(content.contains("f128 differential oracle: DEFERRED"));
    }

    /// generate_noir_file inject_fault: fault-injected file differs from clean file.
    #[test]
    fn test_inject_fault_changes_file() {
        let clean = generate_noir_file(false);
        let faulty = generate_noir_file(true);
        assert_ne!(clean, faulty, "inject-fault should change at least one expected value");
        // Faulty file must still be ASCII.
        assert!(faulty.is_ascii());
    }

    /// oracle_f16_sqrt: sqrt(1.0_f16) = 1.0_f16.
    #[test]
    fn test_oracle_f16_sqrt_known() {
        // sqrt(1.0) = 1.0 -- f16 1.0 = 0x3C00
        assert_eq!(oracle_f16_sqrt(0x3C00), 0x3C00);
        // sqrt(4.0) = 2.0 -- f16 4.0 = 0x4400, f16 2.0 = 0x4000
        assert_eq!(oracle_f16_sqrt(0x4400), 0x4000);
    }

    /// oracle_f64_sqrt: sqrt(-1.0) = canonical NaN.
    #[test]
    fn test_oracle_f64_sqrt_neg() {
        assert_eq!(oracle_f64_sqrt(0xBFF0000000000000), CANONICAL_NAN_F64);
    }

    // ---- Fix 1: f16 cmp random mask allows negative values ----

    /// Verify the f16 cmp random mask 0xFBFF only clears the exponent-LSB (bit 10)
    /// and preserves the sign bit (bit 15), so the corpus can include negative values.
    /// The old (incorrect) mask 0x7BFF also cleared the sign bit -- positive-only corpus.
    #[test]
    fn test_f16_cmp_mask_preserves_sign() {
        // 0xFBFF must preserve bit 15 (sign).
        assert_eq!(0xFBFF_u16 & 0x8000, 0x8000, "mask 0xFBFF must preserve sign bit");
        // 0xFBFF must clear bit 10 (exponent LSB -- prevents inf/NaN when all exp bits set).
        assert_eq!(0xFBFF_u16 & 0x0400, 0x0000, "mask 0xFBFF must clear exponent LSB (bit 10)");
        // Mirrors f32 mask 0xFF7FFFFF (clears f32 exponent LSB, bit 23).
        assert_eq!(0xFF7FFFFF_u32 & 0x00800000, 0x0000_0000, "f32 mask clears bit 23");
        // Mirrors f64 mask 0xFFEFFFFFFFFFFFFF (clears f64 exponent LSB, bit 52).
        assert_eq!(0xFFEFFFFFFFFFFFFF_u64 & 0x0010000000000000, 0_u64, "f64 mask clears bit 52");
        // Old mask would have cleared sign bit.
        assert_eq!(0x7BFF_u16 & 0x8000, 0x0000, "old mask 0x7BFF incorrectly cleared sign bit");
    }

    // ---- Fix 2: cmp corners include NaN vectors ----

    /// Comparison corner sets for all widths must include qNaN and sNaN.
    /// IEEE 754: ordered comparisons (eq/lt/le) with NaN are deterministically false.
    #[test]
    fn test_cmp_corners_include_nan() {
        let f16_c = f16_cmp_corners();
        assert!(f16_c.contains(&0x7E00), "f16 cmp corners must include qNaN (0x7E00)");
        assert!(f16_c.contains(&0x7C01), "f16 cmp corners must include sNaN (0x7C01)");

        let f32_c = f32_cmp_corners();
        assert!(f32_c.contains(&0x7FC00000_u32), "f32 cmp corners must include qNaN (0x7FC00000)");
        assert!(f32_c.contains(&0x7F800001_u32), "f32 cmp corners must include sNaN (0x7F800001)");

        let f64_c = f64_cmp_corners();
        assert!(f64_c.contains(&0x7FF8000000000000_u64), "f64 cmp corners must include qNaN");
        assert!(f64_c.contains(&0x7FF0000000000001_u64), "f64 cmp corners must include sNaN");
    }

    /// NaN comparisons (all ops) must return false per IEEE 754.
    #[test]
    fn test_nan_cmp_always_false() {
        // f32 qNaN
        assert!(!oracle_f32_eq(0x7FC00000, 0x3F800000), "qNaN eq normal must be false");
        assert!(!oracle_f32_eq(0x3F800000, 0x7FC00000), "normal eq qNaN must be false");
        assert!(!oracle_f32_eq(0x7FC00000, 0x7FC00000), "qNaN eq qNaN must be false");
        assert!(!oracle_f32_lt(0x7FC00000, 0x3F800000), "qNaN lt normal must be false");
        assert!(!oracle_f32_le(0x7FC00000, 0x3F800000), "qNaN le normal must be false");
        // f32 sNaN
        assert!(!oracle_f32_eq(0x7F800001, 0x3F800000), "sNaN eq normal must be false");
        assert!(!oracle_f32_lt(0x7F800001, 0x7F800001), "sNaN lt sNaN must be false");
        // f64 qNaN
        assert!(!oracle_f64_eq(0x7FF8000000000000, 0x3FF0000000000000), "f64 qNaN eq normal must be false");
        assert!(!oracle_f64_le(0x7FF8000000000000, 0x7FF8000000000000), "f64 qNaN le qNaN must be false");
        // f16 qNaN via oracle
        assert!(!oracle_f16_eq(0x7E00, 0x3C00), "f16 qNaN eq 1.0 must be false");
        assert!(!oracle_f16_lt(0x7E00, 0x7E00), "f16 qNaN lt qNaN must be false");
    }

    // ---- Fix 3: sqrt corners include negative real inputs ----

    /// Sqrt of negative real numbers must yield canonical NaN per the codegen.nr:237 contract.
    #[test]
    fn test_f32_sqrt_neg_corners() {
        assert_eq!(oracle_f32_sqrt(0xBF800000), CANONICAL_NAN_F32, "sqrt(-1.0_f32) must be canonical NaN");
        assert_eq!(oracle_f32_sqrt(0x80800000), CANONICAL_NAN_F32, "sqrt(-min_normal_f32) must be canonical NaN");
        assert_eq!(oracle_f32_sqrt(0xFF7FFFFF), CANONICAL_NAN_F32, "sqrt(-max_normal_f32) must be canonical NaN");
    }

    #[test]
    fn test_f64_sqrt_neg_corners() {
        assert_eq!(oracle_f64_sqrt(0xBFF0000000000000), CANONICAL_NAN_F64, "sqrt(-1.0_f64) must be canonical NaN");
        assert_eq!(oracle_f64_sqrt(0x8010000000000000), CANONICAL_NAN_F64, "sqrt(-min_normal_f64) must be canonical NaN");
        assert_eq!(oracle_f64_sqrt(0xFFEFFFFFFFFFFFFF), CANONICAL_NAN_F64, "sqrt(-max_normal_f64) must be canonical NaN");
    }

    #[test]
    fn test_f16_sqrt_neg_corners() {
        assert_eq!(oracle_f16_sqrt(0xBC00), CANONICAL_NAN_F16, "sqrt(-1.0_f16) must be canonical NaN");
        assert_eq!(oracle_f16_sqrt(0x8400), CANONICAL_NAN_F16, "sqrt(-min_normal_f16) must be canonical NaN");
        assert_eq!(oracle_f16_sqrt(0xFBFF), CANONICAL_NAN_F16, "sqrt(-max_normal_f16) must be canonical NaN");
    }

    // ---- sq-dtmg9: abs / from_field / to_field oracles ----

    /// The bit-level abs oracle must agree with hardware f32::abs / f64::abs on
    /// non-NaN values, and must preserve NaN payloads while clearing the sign.
    #[test]
    fn test_oracle_abs_matches_hardware_and_preserves_payloads() {
        for bits in [0x3F800000_u32, 0xBF800000, 0x80000000, 0x7F800000, 0xFF800000, 0x80000001] {
            assert_eq!(
                oracle_f32_abs(bits),
                f32::from_bits(bits).abs().to_bits(),
                "f32 abs oracle diverges from hardware for 0x{bits:08x}"
            );
        }
        for bits in [0x3FF0000000000000_u64, 0xBFF0000000000000, 0x8000000000000000] {
            assert_eq!(oracle_f64_abs(bits), f64::from_bits(bits).abs().to_bits());
        }
        // NaN payload preserved, sign cleared (IEEE 754-2019 5.5.1).
        assert_eq!(oracle_f32_abs(0xFFC00001), 0x7FC00001);
        assert_eq!(oracle_f64_abs(0xFFF8000000000001), 0x7FF8000000000001);
        assert_eq!(oracle_f16_abs(0xFE01), 0x7E01);
        assert_eq!(oracle_f16_abs(0x8001), 0x0001);
    }

    /// from_field oracle: RNE at the first inexact integers and the extremes.
    #[test]
    fn test_oracle_from_field_rne() {
        // 2^53 + 1 is the first u64 not representable in f64: ties to 2^53.
        assert_eq!(oracle_f64_from_field((1 << 53) + 1), 0x4340000000000000);
        assert_eq!(oracle_f64_from_field((1 << 53) + 3), 0x4340000000000002);
        // 2^24 + 1 is the first integer not representable in f32.
        assert_eq!(oracle_f32_from_field((1 << 24) + 1), 0x4B800000);
        // u128::MAX rounds above f32's max finite -> +inf.
        assert_eq!(oracle_f32_from_field(u128::MAX), 0x7F800000);
        // u128::MAX in f64: rounds to 2^128.
        assert_eq!(oracle_f64_from_field(u128::MAX), (340282366920938463463374607431768211455_u128 as f64).to_bits());
        assert_eq!(oracle_f64_from_field(0), 0);
        assert_eq!(oracle_f64_from_field(1), 0x3FF0000000000000);
    }

    /// to_field oracle: truncation toward zero, and the rejection domain.
    #[test]
    fn test_oracle_to_field_domain() {
        assert_eq!(oracle_f64_to_field(0x400E000000000000), Some(3)); // 3.75
        assert_eq!(oracle_f64_to_field(0xBFE0000000000000), Some(0)); // -0.5
        assert_eq!(oracle_f64_to_field(0x8000000000000000), Some(0)); // -0
        assert_eq!(oracle_f64_to_field(0x43E0000000000000), Some(1 << 63)); // 2^63
        assert_eq!(oracle_f64_to_field(0x7FF8000000000000), None); // NaN
        assert_eq!(oracle_f64_to_field(0x7FF0000000000000), None); // +inf
        assert_eq!(oracle_f64_to_field(0xBFF0000000000000), None); // -1.0
        assert_eq!(oracle_f64_to_field(0x43F0000000000000), None); // 2^64
        assert_eq!(oracle_f32_to_field(0x40700000), Some(3)); // 3.75
        assert_eq!(oracle_f32_to_field(0xFF800000), None); // -inf
    }

    /// The curated to_field corners must all be in the valid domain (the
    /// generator .expect()s on them).
    #[test]
    fn test_to_field_curated_corners_valid() {
        let content = generate_noir_file(false);
        assert!(content.contains("fn differential_oracle_f64_to_field()"));
        // Sanity: the -0.5 truncation row must appear with expected 0.
        assert!(content.contains("assert_eq(f64::new(0xbfe0000000000000 as u64).to_field(), 0 as Field);"));
    }
}
