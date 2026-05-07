/-! # Equivalence theorem: `mul_u64_to_u128`

The optimised partial-product hand-port and the `Nat`-level spec
both compute `a.toNat * b.toNat` split into 64-bit halves, but
the proof of that equality requires a chain of carry-arithmetic
lemmas. Sorry-stubbed pending mechanical `Nat`-arithmetic work
(see `mul_u64_to_u128_preamble.lean` for the methodology).

## Closure attempt log (Tier-6 round, 2026-05-07)

A direct manual closure was attempted via the route sketched in
the preamble:

1. Set abbreviations for `aLo, aHi, bLo, bHi, p0..p3, midSum,
   midCarry, midLoShifted, low, lowCarry, midHi,
   midCarryShifted, high` matching the optimised body.
2. Establish `< 2 ^ 32` bounds for each 32-bit half via
   `BitVec.toNat_and` plus `Nat.and_pow_two_sub_one_eq_mod`.
3. Show `pᵢ.toNat = aⱼ.toNat * bₖ.toNat` exactly (no truncation)
   using `Nat.mul_lt_mul''` to bound each partial product below
   `2 ^ 64`.
4. Derive a single carry-arithmetic identity
   `high.toNat * 2 ^ 64 + low.toNat = a.toNat * b.toNat` by:
   * `midCarry.toNat * 2 ^ 64 + midSum.toNat = p1.toNat + p2.toNat`
     (case split on `midSum.toNat < p1.toNat`);
   * `lowCarry.toNat * 2 ^ 64 + low.toNat = p0.toNat
       + midLoShifted.toNat` (similar);
   * `midLoShifted.toNat = (midSum.toNat % 2 ^ 32) * 2 ^ 32` and
     `midSum.toNat = midHi.toNat * 2 ^ 32 + midSum.toNat % 2 ^ 32`;
   * Algebraic combine: `(aHi*2^32 + aLo)*(bHi*2^32 + bLo)
       = aHi*bHi*2^64 + (aHi*bLo + aLo*bHi)*2^32 + aLo*bLo`,
     which `ring` + `omega` handle once the carry chain is
     resolved.
5. Project `low.toNat` and `high.toNat` from the combine identity
   via `Nat.div_add_mod` and the `< 2 ^ 64` bound on each side.

The chain spans ~250 lines of dense `BitVec.toNat`-level
rewriting. The brittle steps are the chained-modulus reduction
in `hhigh_eq` (where `BitVec.toNat_add` for a four-term sum
produces `(((x + y) % 2^64 + z) % 2^64 + w) % 2^64`) and the
final ring manipulation that aligns the partial-product
expansion with the optimised body's high/low decomposition.
Without a live lake build to iterate against (lampe-literate's
cold-cache build is prohibitive on the prover's hardware), the
proof was deemed too risky to land speculatively.

## Recommended next-attempt path

Use a `bv_decide`-friendly intermediate. Concretely:

1. Prove
   `high.toNat * 2 ^ 64 + low.toNat
     = (BitVec.setWidth 128 a * BitVec.setWidth 128 b).toNat`
   in pure-BitVec form. The 128-bit goal sits within bitwuzla's
   QF_BV fragment (the bitblasted form has ~30k clauses) and
   `bv_decide` should close it directly.
2. Bridge to the `Nat`-level spec using `BitVec.toNat_setWidth`
   plus `Nat.div_add_mod`. This bridge is short — both sides
   reduce to `a.toNat * b.toNat` in a few `simp` rewrites.

The Tier-6 budget for this single lift is one focused
afternoon-session by a Lean specialist with a hot lake-build
cache.
-/

theorem mul_u64_to_u128_equivalence (a b : BitVec 64) :
    mulU64ToU128Optimised a b = mulU64ToU128Spec a b := by
  -- Partial-product reconstruction matches the Nat-level spec.
  -- Closure exceeded the 200-LOC manual budget; deferred for a
  -- Lean specialist with a hot lake-build cache. See the
  -- closure-attempt log above for the strategy and the brittle
  -- steps encountered.
  sorry

end ZkpSparql.Ieee754.Equivalence
