// IEEE 754 reference implementations -- companion to the optimised
// `ieee754` crate. Existence-of-purpose: equivalence proofs.
//
// Conventions:
//   * Each operation lives in its own module and is named `<op>_reference`
//     (e.g. `add_f32_reference`).
//   * The reference must be the most literal expression of the IEEE 754
//     standard we can write -- proofs read it as the ground-truth side of
//     the equivalence claim.
//   * Performance is deliberately *not* a concern; clarity is.
//   * Where the optimised crate baked an SI optimisation (binary-search
//     CLZ, sticky-bit shift, etc.) we re-derive the same value from the
//     definitional formula, even if it takes more gates.

pub mod add_f32;

pub use crate::add_f32::add_f32_reference;
