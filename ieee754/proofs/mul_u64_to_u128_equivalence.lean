/-! # Equivalence theorem: `mul_u64_to_u128`

The optimised partial-product hand-port and the `Nat`-level spec
both compute `a.toNat * b.toNat` split into 64-bit halves, but the
proof of that equality requires a chain of carry-arithmetic
lemmas. Sorry-stubbed pending mechanical `Nat`-arithmetic work
(see `mul_u64_to_u128_preamble.lean` for the methodology). -/

theorem mul_u64_to_u128_equivalence (a b : BitVec 64) :
    mulU64ToU128Optimised a b = mulU64ToU128Spec a b := by
  -- Partial-product reconstruction matches the Nat-level spec.
  -- The chain is mechanical but spans several hundred lines of
  -- bit-arithmetic; deferred per the Tier-6 methodology comment
  -- in the preamble.
  sorry

end ZkpSparql.Ieee754.Equivalence
