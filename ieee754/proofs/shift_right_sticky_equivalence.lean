/-! # Equivalence theorems: sticky-shift family

For each helper the optimised hand-port equals the literal
IEEE 754-2019 sec 5.4.1 specification.

* The u64 case is *definitionally* the same operation: the literal
  spec (`Spec.shrSticky`) and the optimised dispatch share the same
  3-branch shape, so `rfl` discharges the goal.
* The u128 case threads the existing round-9 task-iii closure
  (`SubtermsMulF64.shiftRightStickyU128_eq_spec`), which proves the
  optimised 4-case dispatch matches the unified `Nat`-level spec. -/

open ZkpSparql.Ieee754.Equivalence.Spec
open ZkpSparql.Ieee754.Equivalence.MulModelsF64
open ZkpSparql.Ieee754.Equivalence.SubtermsMulF64

theorem shift_right_sticky_u64_equivalence
    (value : BitVec 64) (shift : BitVec 64) :
    shiftRightStickyU64Optimised value shift
      = shiftRightStickyU64Spec value shift := by
  unfold shiftRightStickyU64Optimised shiftRightStickyU64Spec shrSticky
  rfl

theorem shift_right_sticky_u128_equivalence
    (val : U128) (shift : Nat) :
    shiftRightStickyU128Optimised val shift
      = shiftRightStickyU128SpecRef val shift := by
  unfold shiftRightStickyU128Optimised shiftRightStickyU128SpecRef
  exact shiftRightStickyU128_eq_spec val shift

end ZkpSparql.Ieee754.Equivalence
