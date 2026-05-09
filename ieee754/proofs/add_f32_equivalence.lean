/-! ## Inlined-RNE divergence: definitionally equal -/

/-- The optimised path's inlined round-to-nearest-even computation
is the body of `shouldRoundUp` for `mode = 0`. -/
theorem shouldRoundUp_inline_eq
    (guardBits : BitVec 64) (resultMant : BitVec 64)
    (resultSign : BitVec 1) :
    shouldRoundUp guardBits resultMant resultSign 0
      = (decide (guardBits.toNat > 4)
          || (decide (guardBits = 4) && decide (resultMant &&& 1 = 1))) := by
  -- Both sides unfold to the same boolean expression.
  unfold shouldRoundUp
  simp [modeNearestEven]

/-! ## Diverging-parameter equalities -/

/-- The optimised `clz` parameter equals the reference's: `clzBinary
= clzLoop` pointwise. Round-5 `Subterms.clz_eq`, taken symmetrically
and lifted to a function-level equality. -/
private theorem clz_param_eq : clzBinary = clzLoop := by
  funext v; exact (clz_eq v).symm

/-- The optimised `rneDecision` parameter (inline-RNE wrapper) equals
the reference's (`shouldRoundUp`). For `mode = modeNearestEven` both
sides reduce to the same boolean expression by
`shouldRoundUp_inline_eq`; for `mode ≠ modeNearestEven` the wrapper
falls through to `shouldRoundUp` directly. -/
private theorem rne_param_eq :
    (fun (gb : BitVec 64) (rm : BitVec 64) (rs : BitVec 1) (m : BitVec 8) =>
      if m = 0 then
        decide (gb.toNat > 4) ||
          (decide (gb = 4) && decide (rm &&& 1 = 1))
      else
        shouldRoundUp gb rm rs m) = shouldRoundUp := by
  funext gb rm rs m
  by_cases hmode : m = 0
  · subst hmode
    rw [if_pos rfl]
    exact (shouldRoundUp_inline_eq gb rm rs).symm
  · rw [if_neg hmode]

/-! ## Alignment-triple equality

The two alignment functions produce the same `(mantAShift,
mantBShift, resultExpInit)` triple for every input. The round-6
3-way trichotomy on `expA.toNat`/`expB.toNat` reduces each branch to
a `BitVec 64` equality discharged by `shr_sticky_eq` (unequal
exponents) or `shrStickyHelper_zero` (equal exponents).

Crucially the trichotomy is *contained* in this lemma — it does not
rewrite under the long `addF32Skeleton` body. The lemma's goal is a
ground equality of two triples in `BitVec 64`; `rfl` (after the
`simp only` rewrite chain has folded the alignment) holds without
depending on the heartbeat-fragile definitional equality at the
skeleton level. -/

private theorem align_eq (a b : Float32Bits) :
    alignF32Optimised a b = alignF32Reference a b := by
  unfold alignF32Optimised alignF32Reference
  -- Short-hand for the effective exponents.
  set expA : BitVec 64 := effectiveExp a with hExpA
  set expB : BitVec 64 := effectiveExp b with hExpB
  rcases lt_trichotomy expA.toNat expB.toNat with hlt | heq | hgt
  · -- expA < expB: optimised takes the `expB > expA` branch
    -- (`mantA := shrStickyInline mantA (expB - expA)`); reference
    -- selects `shrStickyHelper mantAAligned (expB - expA)`.
    have hngeA : ¬ expA.toNat ≥ expB.toNat := by omega
    have hngtA : ¬ expA.toNat > expB.toNat := by omega
    have hgtB : expB.toNat > expA.toNat := hlt
    have hshift_ne : (expB - expA).toNat ≠ 0 := by
      rw [BitVec.toNat_sub]
      have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
      have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
      omega
    simp only [Id.run, hngeA, hngtA, hgtB, if_true, if_false,
               ge_iff_le, Nat.not_le_of_lt, shr_sticky_eq _ _ hshift_ne]
    rfl
  · -- expA = expB: both alignments leave the mantissas un-shifted
    -- (optimised: neither `if`-branch fires; reference:
    -- `shrStickyHelper _ 0 = id` via `shrStickyHelper_zero`).
    have hsub : expA - expB = 0 := by
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toNat_sub, heq]
      have hbound : expB.toNat ≤ 18446744073709551616 :=
        Nat.le_of_lt (BitVec.isLt _)
      change _ = (0 : BitVec 64).toNat
      simp; omega
    have hsub' : expB - expA = 0 := by
      apply BitVec.eq_of_toNat_eq
      rw [BitVec.toNat_sub, ← heq]
      have hbound : expA.toNat ≤ 18446744073709551616 :=
        Nat.le_of_lt (BitVec.isLt _)
      change _ = (0 : BitVec 64).toNat
      simp; omega
    have hge : expA.toNat ≥ expB.toNat := Nat.le_of_eq heq.symm
    have hngtA : ¬ expA.toNat > expB.toNat := by omega
    have hngtB : ¬ expB.toNat > expA.toNat := by omega
    have hexp_eq : expA = expB := by
      apply BitVec.eq_of_toNat_eq; exact heq
    simp only [Id.run, hngtA, hngtB, hge, ge_iff_le, hsub, hsub',
               shrStickyHelper_zero, if_true, if_false]
    rfl
  · -- expA > expB: optimised takes the `expA > expB` branch
    -- (`mantB := shrStickyInline mantB (expA - expB)`); reference
    -- selects `shrStickyHelper mantBAligned (expA - expB)`.
    have hge : expA.toNat ≥ expB.toNat := Nat.le_of_lt hgt
    have hngtB : ¬ expB.toNat > expA.toNat := by omega
    have hshift_ne : (expA - expB).toNat ≠ 0 := by
      rw [BitVec.toNat_sub]
      have hb_lt : expB.toNat < 18446744073709551616 := BitVec.isLt _
      have ha_lt : expA.toNat < 18446744073709551616 := BitVec.isLt _
      omega
    simp only [Id.run, hgt, hngtB, hge, ge_iff_le, if_true, if_false,
               shr_sticky_eq _ _ hshift_ne]
    rfl

/-! ## Main theorem

The optimised f32 add is bit-identical to the literal-IEEE-754
reference f32 add, for every input and every rounding mode.

The proof unfolds both wrappers, rewrites the alignment triple
(folding the optimised `Id.run`-style alignment into the reference
form via `align_eq`), and rewrites the two diverging-subterm
parameters (`clz_param_eq`, `rne_param_eq`); `rfl` then sees both
sides as the same `addF32Skeleton`-application. -/

theorem add_f32_equivalence
    (a b : Float32Bits) (mode : BitVec 8) :
    addF32Optimised a b mode = addF32Reference a b mode := by
  unfold addF32Optimised addF32Reference
  rw [align_eq a b, clz_param_eq, rne_param_eq]

end ZkpSparql.Ieee754.Equivalence
