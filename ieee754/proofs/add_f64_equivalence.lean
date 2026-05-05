/-! ## Diverging-parameter equalities -/

/-- The optimised `clz` parameter equals the reference's (i.e. the
binary-search and linear-loop CLZ are pointwise equal). -/
private theorem clz_param_eq :
    Subterms.clzBinary = Subterms.clzLoop := by
  funext v; exact (Subterms.clz_eq v).symm

/-- The optimised `rneDecision` parameter (inline-RNE wrapper) equals
the reference's (`shouldRoundUp8Bit`). For `mode = 0` both sides
reduce to the same boolean expression by
`shouldRoundUp8Bit_inline_eq`; for `mode ≠ 0` the wrapper falls
through to `shouldRoundUp8Bit` directly. -/
private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 0x80) ||
          (decide (gb = 0x80) && decide (rm &&& 1 = 1))
      else
        shouldRoundUp8Bit gb rm rs m) = shouldRoundUp8Bit := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp8Bit_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

/-! ## Main theorem -/

/-- The optimised f64 add is bit-identical to the round-7 IEEE 754
reference f64 add, for every input and every rounding mode. The
proof rewrites both diverging-subterm parameters of the shared
skeleton and lets `rfl` finish. -/
theorem add_f64_equivalence
    (a b : Float64Bits) (mode : BitVec 8) :
    addF64Optimised a b mode = addF64Reference a b mode := by
  unfold addF64Optimised addF64Reference
  rw [clz_param_eq, rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
