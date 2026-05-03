# `noir_IEEE754` scripts

## Python dependencies

The test-generation pipeline uses [`gmpy2`](https://gmpy2.readthedocs.io/)
(MPFR-backed arbitrary-precision floats) as the reference oracle for
non-default IEEE 754 rounding modes. `gmpy2` requires native libraries
(GMP / MPFR / MPC) that have to be installed before `pip install`:

| Platform | Native deps install |
|----------|---------------------|
| macOS (Homebrew) | `brew install gmp mpfr libmpc` |
| Debian / Ubuntu | `sudo apt install libgmp-dev libmpfr-dev libmpc-dev` |
| Fedora | `sudo dnf install gmp-devel mpfr-devel libmpc-devel` |
| Windows | Non-trivial; prefer WSL or rely on a binary wheel from PyPI (`pip install gmpy2` may use a prebuilt wheel; falling back to a source build needs the GMP / MPFR / MPC headers on `INCLUDE` / `LIB`). |

Once the native deps are present:

```sh
pip install -r scripts/requirements.txt
```

The `scripts/test_reference.py` cross-check (run as part of CI) confirms the
MPFR route and the legacy `float.fromhex` + `struct.pack` route produce
byte-identical results under round-to-nearest-even, which is what the
shipping test corpus uses today. When non-default rounding modes are
unblocked in the test suite, the MPFR route automatically takes over for
those cases (see `scripts/noir_ieee754_inputs/reference.py`).

## `benchmark_gates.py`

Measures ACIR / Brillig opcode counts for the eight float arithmetic
operations (`{add,sub,mul,div}_float{32,64}`) by generating a temporary
single-call binary for each, running `nargo info`, and parsing the table.

Usage:

```sh
python3 scripts/benchmark_gates.py            # run all benchmarks, append to gate_counts.json
python3 scripts/benchmark_gates.py --summary  # just print the latest line of gate_counts.json
```

Confirmed working on `main` (commit `f009a1c`) against
`nargo 1.0.0-beta.17`. The summary prints something like:

```
add_float32                      610                 34
add_float64                      714                 34
...
```

The harness only knows about the eight float operations. For lower-level
primitives (e.g. the unconstrained-with-verification helpers in
`ieee754::unconstrained_ops`), use ad-hoc binary projects outside the
workspace, e.g. under `/tmp/clz_bench/<name>/`, with `Nargo.toml`
declaring `ieee754 = { path = "<absolute path to ieee754 crate>" }`.

Future rounds may extend `benchmark_gates.py` with a second `BENCHMARKS`
dict for primitive-level measurements; for Round 1 we keep the Python
harness untouched and document the manual invocation here.

## Round-1 benchmark: `count_leading_zeros_u23`

Two ad-hoc bin projects measure the impact of the new
`count_leading_zeros_u23_verified` primitive against a fully-constrained
baseline that mirrors the existing 23-iteration leading-zero walk used
by `ieee754::float32::convert::float32_from_u32`.

Skeleton (run from anywhere outside the worktree):

```sh
mkdir -p /tmp/clz_bench/clz_u23_baseline/src /tmp/clz_bench/clz_u23_verified/src
# baseline: copy the running-counter loop directly
# verified: `use ieee754::count_leading_zeros_u23_verified;` and call it
# (see commit log for the exact source -- under 30 lines each)

cd /tmp/clz_bench/clz_u23_baseline && nargo info | tail -10
cd /tmp/clz_bench/clz_u23_verified && nargo info | tail -10
```

Round-1 verdict (commit `66b3123`):

| Variant   | Expression Width | ACIR Opcodes |
|-----------|------------------|--------------|
| baseline  | 489              | 17           |
| verified  | 104              | 100          |

The verified pattern wins on expression width but loses on ACIR opcode
count for the `count_leading_zeros_u23` operation in isolation: the
dynamic right-shifts in the verifier (`low23 >> top_bit_pos`,
`low23 >> (top_bit_pos + 1)`) cost more opcodes than Noir's
constant-folding of the baseline's 23-iteration loop with all
constant probe positions saves. **Call-site swap deferred.** The
primitive remains in the public API so it can compose with downstream
primitives (e.g. `shift_right_sticky_u64`) and so the Lampe extraction
pipeline has a stable target.
