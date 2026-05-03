#!/usr/bin/env python3
"""
Gate Count Benchmark Script for noir_IEEE754

This script compiles individual benchmark circuits for each IEEE 754 operation
and records the gate count for before/after optimization comparisons.

Usage:
    python3 scripts/benchmark_gates.py [--output FILE]
    
Output:
    Creates a JSON file with gate counts for each operation
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

# Operations to benchmark
BENCHMARKS = {
    "add_float32": {
        "inputs": "a32: pub u32, b32: pub u32",
        "body": """
    let fa = float32_from_bits(a32);
    let fb = float32_from_bits(b32);
    float32_to_bits(add_float32(fa, fb))
""",
        "return_type": "pub u32",
    },
    "mul_float32": {
        "inputs": "a32: pub u32, b32: pub u32",
        "body": """
    let fa = float32_from_bits(a32);
    let fb = float32_from_bits(b32);
    float32_to_bits(mul_float32(fa, fb))
""",
        "return_type": "pub u32",
    },
    "sub_float32": {
        "inputs": "a32: pub u32, b32: pub u32",
        "body": """
    let fa = float32_from_bits(a32);
    let fb = float32_from_bits(b32);
    float32_to_bits(sub_float32(fa, fb))
""",
        "return_type": "pub u32",
    },
    "div_float32": {
        "inputs": "a32: pub u32, b32: pub u32",
        "body": """
    let fa = float32_from_bits(a32);
    let fb = float32_from_bits(b32);
    float32_to_bits(div_float32(fa, fb))
""",
        "return_type": "pub u32",
    },
    "add_float64": {
        "inputs": "a64: pub u64, b64: pub u64",
        "body": """
    let fa = float64_from_bits(a64);
    let fb = float64_from_bits(b64);
    float64_to_bits(add_float64(fa, fb))
""",
        "return_type": "pub u64",
    },
    "mul_float64": {
        "inputs": "a64: pub u64, b64: pub u64",
        "body": """
    let fa = float64_from_bits(a64);
    let fb = float64_from_bits(b64);
    float64_to_bits(mul_float64(fa, fb))
""",
        "return_type": "pub u64",
    },
    "sub_float64": {
        "inputs": "a64: pub u64, b64: pub u64",
        "body": """
    let fa = float64_from_bits(a64);
    let fb = float64_from_bits(b64);
    float64_to_bits(sub_float64(fa, fb))
""",
        "return_type": "pub u64",
    },
    "div_float64": {
        "inputs": "a64: pub u64, b64: pub u64",
        "body": """
    let fa = float64_from_bits(a64);
    let fb = float64_from_bits(b64);
    float64_to_bits(div_float64(fa, fb))
""",
        "return_type": "pub u64",
    },
}


# ---------------------------------------------------------------------------
# Primitive (isolated and composed) benchmarks for the unconstrained-with-
# verifier pattern. These let us measure individual helpers from
# `ieee754::unconstrained_ops` against the in-tree binary-search baseline
# they aim to replace, without yet swapping any call sites.
#
# Each entry has the same shape as `BENCHMARKS` plus optional `extra_use`
# and `prelude` keys for extra imports and helper functions injected
# above `main`. Measurements are written into a separate
# `primitive_benchmarks` block in the JSON output so they don't pollute
# the headline `benchmarks` table.
# ---------------------------------------------------------------------------

PRIMITIVE_BENCHMARKS = {
    # -- Isolated: the verifier on its own vs. an inlined binary-search
    #    baseline. This matches the "clean room" comparison reported for
    #    `clz_u23` in PR #36; if anything, this number is friendlier to
    #    the baseline because the constant inputs of a one-shot caller
    #    can fold large parts of the binary search away.
    "clz_u64_isolated_verified": {
        "extra_use": "use ieee754::count_leading_zeros_u64_verified;",
        "prelude": "",
        "inputs": "value: pub u64",
        "body": """
    count_leading_zeros_u64_verified(value)
""",
        "return_type": "pub u64",
    },
    # Spike: PR #38 (`spike/clz-bit-decomposition`). Same surface as
    # `clz_u64_isolated_verified` but the verifier asserts an explicit
    # bit-decomposition relation with a one-hot leading-bit indicator and
    # a cumulative `saw_one` prefix flag, in place of the merged
    # dynamic-shift verifier. The point of this entry is to measure
    # whether replacing `value >> top_bit_pos` with a 64-element bit
    # decomposition closes the gap to the binary-search baseline.
    "clz_u64_isolated_verified_bitdecomp": {
        "extra_use": "use ieee754::count_leading_zeros_u64_verified_bitdecomp;",
        "prelude": "",
        "inputs": "value: pub u64",
        "body": """
    count_leading_zeros_u64_verified_bitdecomp(value)
""",
        "return_type": "pub u64",
    },
    "clz_u64_isolated_binsearch_baseline": {
        "extra_use": "",
        "prelude": """
fn clz_u64_binsearch(value: u64) -> u64 {
    // The 6-step binary-search count-leading-zeros baseline returns 63
    // for `value == 0` (only the last conditional fires). To make this
    // an apples-to-apples comparison against
    // `count_leading_zeros_u64_verified` -- which specifies 64 for the
    // zero case -- we add an explicit zero short-circuit. Without this
    // the two circuits agree on every nonzero input but diverge at
    // zero, which would invalidate the benchmark.
    if value == 0 {
        64
    } else {
        let mut leading_zeros: u64 = 0;
        let mut v = value;
        if v & 0xFFFFFFFF00000000 == 0 {
            leading_zeros += 32;
            v <<= 32;
        }
        if v & 0xFFFF000000000000 == 0 {
            leading_zeros += 16;
            v <<= 16;
        }
        if v & 0xFF00000000000000 == 0 {
            leading_zeros += 8;
            v <<= 8;
        }
        if v & 0xF000000000000000 == 0 {
            leading_zeros += 4;
            v <<= 4;
        }
        if v & 0xC000000000000000 == 0 {
            leading_zeros += 2;
            v <<= 2;
        }
        if v & 0x8000000000000000 == 0 {
            leading_zeros += 1;
        }
        leading_zeros
    }
}
""",
        "inputs": "value: pub u64",
        "body": """
    clz_u64_binsearch(value)
""",
        "return_type": "pub u64",
    },
    # -- Composed: emulate the leading-zero subnormal-normalisation step
    #    that `add_float64` performs (binary-search CLZ followed by a
    #    bounded left shift driven by the count). The baseline copies the
    #    in-tree code verbatim from `ieee754/src/float64/add.nr`; the
    #    candidate replaces the binary search with the verified primitive.
    #    This is the measurement that actually answers
    #    "should we swap call sites?".
    "clz_u64_composed_verified": {
        "extra_use": "use ieee754::count_leading_zeros_u64_verified;",
        "prelude": """
fn normalise_with_verified(result_mant: u64, result_exp: u64) -> (u64, u64) {
    let target_bit: u64 = 60;
    let leading_zeros: u64 = count_leading_zeros_u64_verified(result_mant);
    let shift_needed = leading_zeros - (64 - target_bit - 1);
    let max_shift = if result_exp > 1 { result_exp - 1 } else { 0 };
    let actual_shift = if shift_needed <= max_shift {
        shift_needed
    } else {
        max_shift
    };
    let new_mant = result_mant << actual_shift;
    let new_exp = result_exp - actual_shift;
    (new_mant, new_exp)
}
""",
        "inputs": "result_mant: pub u64, result_exp: pub u64",
        "body": """
    let (m, e) = normalise_with_verified(result_mant, result_exp);
    m + e
""",
        "return_type": "pub u64",
    },
    # Spike (PR #38): the same composed normalisation block but driven
    # by the bit-decomposition verifier. Compared head-to-head against
    # `clz_u64_composed_verified` (merged dynamic-shift) and
    # `clz_u64_composed_binsearch_baseline` (in-tree binary search).
    "clz_u64_composed_verified_bitdecomp": {
        "extra_use": "use ieee754::count_leading_zeros_u64_verified_bitdecomp;",
        "prelude": """
fn normalise_with_verified_bd(result_mant: u64, result_exp: u64) -> (u64, u64) {
    let target_bit: u64 = 60;
    let leading_zeros: u64 = count_leading_zeros_u64_verified_bitdecomp(result_mant);
    let shift_needed = leading_zeros - (64 - target_bit - 1);
    let max_shift = if result_exp > 1 { result_exp - 1 } else { 0 };
    let actual_shift = if shift_needed <= max_shift {
        shift_needed
    } else {
        max_shift
    };
    let new_mant = result_mant << actual_shift;
    let new_exp = result_exp - actual_shift;
    (new_mant, new_exp)
}
""",
        "inputs": "result_mant: pub u64, result_exp: pub u64",
        "body": """
    let (m, e) = normalise_with_verified_bd(result_mant, result_exp);
    m + e
""",
        "return_type": "pub u64",
    },
    "clz_u64_composed_binsearch_baseline": {
        "extra_use": "",
        "prelude": """
fn normalise_with_binsearch(result_mant: u64, result_exp: u64) -> (u64, u64) {
    let target_bit: u64 = 60;
    let mut leading_zeros: u64 = 0;
    let mut v = result_mant;
    if v & 0xFFFFFFFF00000000 == 0 {
        leading_zeros += 32;
        v <<= 32;
    }
    if v & 0xFFFF000000000000 == 0 {
        leading_zeros += 16;
        v <<= 16;
    }
    if v & 0xFF00000000000000 == 0 {
        leading_zeros += 8;
        v <<= 8;
    }
    if v & 0xF000000000000000 == 0 {
        leading_zeros += 4;
        v <<= 4;
    }
    if v & 0xC000000000000000 == 0 {
        leading_zeros += 2;
        v <<= 2;
    }
    if v & 0x8000000000000000 == 0 {
        leading_zeros += 1;
    }
    let shift_needed = leading_zeros - (64 - target_bit - 1);
    let max_shift = if result_exp > 1 { result_exp - 1 } else { 0 };
    let actual_shift = if shift_needed <= max_shift {
        shift_needed
    } else {
        max_shift
    };
    let new_mant = result_mant << actual_shift;
    let new_exp = result_exp - actual_shift;
    (new_mant, new_exp)
}
""",
        "inputs": "result_mant: pub u64, result_exp: pub u64",
        "body": """
    let (m, e) = normalise_with_binsearch(result_mant, result_exp);
    m + e
""",
        "return_type": "pub u64",
    },
}


def create_primitive_benchmark_project(tmpdir: Path, name: str, benchmark: dict) -> Path:
    """Create a temporary Noir project for a primitive (isolated or composed)
    benchmark. Differs from `create_benchmark_project` only in that the
    `main` body may pull in additional `use` lines and helper functions
    via the `extra_use` and `prelude` keys.
    """
    project_dir = tmpdir / name
    project_dir.mkdir(parents=True)
    src_dir = project_dir / "src"
    src_dir.mkdir()

    nargo_toml = f"""[package]
name = "{name}"
type = "bin"
authors = ["benchmark"]

[dependencies]
ieee754 = {{ path = "{get_project_root() / 'ieee754'}" }}
"""
    (project_dir / "Nargo.toml").write_text(nargo_toml)

    extra_use = benchmark.get("extra_use", "")
    prelude = benchmark.get("prelude", "")

    main_nr = f"""{extra_use}
{prelude}
fn main({benchmark['inputs']}) -> {benchmark['return_type']} {{{benchmark['body']}}}
"""
    (src_dir / "main.nr").write_text(main_nr)

    return project_dir


def get_project_root():
    """Get the project root directory."""
    script_dir = Path(__file__).parent
    return script_dir.parent


def create_benchmark_project(tmpdir: Path, name: str, benchmark: dict) -> Path:
    """Create a temporary Noir project for a single benchmark."""
    project_dir = tmpdir / name
    project_dir.mkdir(parents=True)
    src_dir = project_dir / "src"
    src_dir.mkdir()

    # Create Nargo.toml
    nargo_toml = f"""[package]
name = "{name}"
type = "bin"
authors = ["benchmark"]

[dependencies]
ieee754 = {{ path = "{get_project_root() / 'ieee754'}" }}
"""
    (project_dir / "Nargo.toml").write_text(nargo_toml)

    # Create main.nr
    main_nr = f"""use ieee754::{{
    float32_from_bits, float32_to_bits,
    float64_from_bits, float64_to_bits,
    add_float32, sub_float32, mul_float32, div_float32,
    add_float64, sub_float64, mul_float64, div_float64
}};

fn main({benchmark['inputs']}) -> {benchmark['return_type']} {{{benchmark['body']}}}
"""
    (src_dir / "main.nr").write_text(main_nr)

    return project_dir


def run_nargo_info(project_dir: Path) -> dict:
    """Run nargo info and parse the output."""
    result = subprocess.run(
        ["nargo", "info"],
        cwd=project_dir,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"Error running nargo info: {result.stderr}", file=sys.stderr)
        return {"error": result.stderr}

    # Parse table output
    output = result.stdout
    info = {}

    # Parse the table format:
    # | Package | Function | Expression Width | ACIR Opcodes | Brillig Opcodes |
    lines = output.strip().split('\n')
    
    for line in lines:
        # Look for the main function row
        if '| main' in line or '|main' in line:
            parts = [p.strip() for p in line.split('|') if p.strip()]
            if len(parts) >= 4:
                # parts: [Package, Function, Expression Width, ACIR Opcodes, Brillig Opcodes]
                try:
                    width_str = parts[2].strip()
                    if width_str != 'N/A':
                        # Width comes through as e.g. "Bounded { width: 4 }"
                        # or just an integer. Extract the trailing integer.
                        m = re.search(r'(\d+)', width_str)
                        if m:
                            info["expression_width"] = int(m.group(1))
                except (ValueError, IndexError):
                    pass
                try:
                    acir_str = parts[3].strip()
                    if acir_str != 'N/A':
                        info["acir_opcodes"] = int(acir_str)
                except (ValueError, IndexError):
                    pass
                try:
                    brillig_str = parts[4].strip() if len(parts) > 4 else "N/A"
                    if brillig_str != 'N/A':
                        info["brillig_opcodes"] = int(brillig_str)
                except (ValueError, IndexError):
                    pass

    return info


def run_nargo_compile_and_info(project_dir: Path) -> dict:
    """Compile the project and get info."""
    # First compile
    compile_result = subprocess.run(
        ["nargo", "compile"],
        cwd=project_dir,
        capture_output=True,
        text=True,
    )

    if compile_result.returncode != 0:
        print(f"Compilation error: {compile_result.stderr}", file=sys.stderr)
        return {"error": compile_result.stderr, "compile_output": compile_result.stdout}

    # Then get info
    return run_nargo_info(project_dir)


def benchmark_all(output_file: Path = None, primitives: bool = True):
    """Run all benchmarks and collect gate counts.

    Also runs the `PRIMITIVE_BENCHMARKS` (verifier vs. binary-search baseline,
    isolated and composed) and writes them under the `primitive_benchmarks`
    key when `primitives` is true.
    """
    results = {
        "timestamp": datetime.now().isoformat(),
        "git_commit": get_git_commit(),
        "benchmarks": {},
    }
    if primitives:
        results["primitive_benchmarks"] = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        for name, benchmark in BENCHMARKS.items():
            print(f"Benchmarking {name}...", end=" ", flush=True)

            try:
                project_dir = create_benchmark_project(tmpdir, name, benchmark)
                info = run_nargo_compile_and_info(project_dir)
                results["benchmarks"][name] = info

                # Print summary
                if "error" in info:
                    print(f"ERROR: {info['error'][:50]}...")
                elif "acir_opcodes" in info:
                    print(f"ACIR: {info['acir_opcodes']}", end="")
                    if "brillig_opcodes" in info:
                        print(f", Brillig: {info['brillig_opcodes']}", end="")
                    print()
                else:
                    print(f"OK (parsing failed - check raw output)")

            except Exception as e:
                print(f"ERROR: {e}")
                results["benchmarks"][name] = {"error": str(e)}

        if primitives:
            print()
            for name, benchmark in PRIMITIVE_BENCHMARKS.items():
                print(f"Benchmarking primitive {name}...", end=" ", flush=True)
                try:
                    project_dir = create_primitive_benchmark_project(
                        tmpdir, name, benchmark
                    )
                    info = run_nargo_compile_and_info(project_dir)
                    results["primitive_benchmarks"][name] = info

                    if "error" in info:
                        print(f"ERROR: {info['error'][:50]}...")
                    elif "acir_opcodes" in info:
                        print(f"ACIR: {info['acir_opcodes']}", end="")
                        if "expression_width" in info:
                            print(f", Width: {info['expression_width']}", end="")
                        if "brillig_opcodes" in info:
                            print(f", Brillig: {info['brillig_opcodes']}", end="")
                        print()
                    else:
                        print(f"OK (parsing failed - check raw output)")
                except Exception as e:
                    print(f"ERROR: {e}")
                    results["primitive_benchmarks"][name] = {"error": str(e)}

    # Save results
    if output_file is None:
        output_file = get_project_root() / "gate_counts.json"

    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Load existing results if any (for comparison)
    existing_results = []
    if output_file.exists():
        try:
            with open(output_file) as f:
                data = json.load(f)
                if isinstance(data, list):
                    existing_results = data
                else:
                    existing_results = [data]
        except (json.JSONDecodeError, IOError):
            pass

    # Append new results
    existing_results.append(results)

    with open(output_file, "w") as f:
        json.dump(existing_results, f, indent=2)

    print(f"\nResults saved to {output_file}")

    # Print comparison if we have previous results
    if len(existing_results) > 1:
        print_comparison(existing_results[-2], existing_results[-1])

    return results


def get_git_commit():
    """Get the current git commit hash."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=get_project_root(),
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return result.stdout.strip()[:8]
    except Exception:
        pass
    return "unknown"


def print_comparison(old_results: dict, new_results: dict):
    """Print a comparison between two benchmark runs."""
    print("\n" + "=" * 60)
    print("COMPARISON WITH PREVIOUS RUN")
    print("=" * 60)
    print(f"Old: {old_results.get('timestamp', 'unknown')} ({old_results.get('git_commit', 'unknown')})")
    print(f"New: {new_results.get('timestamp', 'unknown')} ({new_results.get('git_commit', 'unknown')})")
    print("-" * 60)
    print(f"{'Operation':<20} {'Old ACIR':>12} {'New ACIR':>12} {'Change':>12}")
    print("-" * 60)

    old_benchmarks = old_results.get("benchmarks", {})
    new_benchmarks = new_results.get("benchmarks", {})

    total_old = 0
    total_new = 0

    for name in sorted(set(old_benchmarks.keys()) | set(new_benchmarks.keys())):
        old_info = old_benchmarks.get(name, {})
        new_info = new_benchmarks.get(name, {})

        old_acir = old_info.get("acir_opcodes", "N/A")
        new_acir = new_info.get("acir_opcodes", "N/A")

        if isinstance(old_acir, int) and isinstance(new_acir, int):
            diff = new_acir - old_acir
            pct = (diff / old_acir * 100) if old_acir > 0 else 0
            change = f"{diff:+d} ({pct:+.1f}%)"
            total_old += old_acir
            total_new += new_acir
        else:
            change = "N/A"

        print(f"{name:<20} {str(old_acir):>12} {str(new_acir):>12} {change:>12}")

    print("-" * 60)
    if total_old > 0 and total_new > 0:
        total_diff = total_new - total_old
        total_pct = (total_diff / total_old * 100)
        print(f"{'TOTAL':<20} {total_old:>12} {total_new:>12} {total_diff:+d} ({total_pct:+.1f}%)")
    print("=" * 60)


def print_summary(results: dict):
    """Print a summary table of the latest benchmark results."""
    print("\n" + "=" * 70)
    print("IEEE 754 GATE COUNT SUMMARY")
    print("=" * 70)
    print(f"Timestamp: {results.get('timestamp', 'unknown')}")
    print(f"Git commit: {results.get('git_commit', 'unknown')}")
    print("-" * 70)
    print(f"{'Operation':<20} {'ACIR Opcodes':>15} {'Brillig Opcodes':>18}")
    print("-" * 70)

    benchmarks = results.get("benchmarks", {})
    total_acir = 0
    total_brillig = 0

    for name in sorted(benchmarks.keys()):
        info = benchmarks[name]
        acir = info.get("acir_opcodes", "N/A")
        brillig = info.get("brillig_opcodes", "N/A")

        if isinstance(acir, int):
            total_acir += acir
        if isinstance(brillig, int):
            total_brillig += brillig

        print(f"{name:<20} {str(acir):>15} {str(brillig):>18}")

    print("-" * 70)
    print(f"{'TOTAL':<20} {total_acir:>15} {total_brillig:>18}")
    print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark gate counts for IEEE 754 operations"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output file for benchmark results (default: benchmarks/gate_counts.json)",
    )
    parser.add_argument(
        "--compare",
        type=Path,
        default=None,
        help="Compare with a previous benchmark file",
    )
    parser.add_argument(
        "--summary", "-s",
        action="store_true",
        help="Print summary of latest benchmark results without running new benchmarks",
    )

    args = parser.parse_args()

    output_file = args.output or get_project_root() / "gate_counts.json"

    if args.summary:
        # Just print summary of existing results
        if not output_file.exists():
            print(f"No benchmark results found at {output_file}")
            print("Run without --summary to generate benchmarks first.")
            sys.exit(1)
        with open(output_file) as f:
            data = json.load(f)
            if isinstance(data, list) and len(data) > 0:
                print_summary(data[-1])
            else:
                print("No benchmark data found")
        return

    if args.compare:
        # Just compare two files
        with open(args.compare) as f:
            data = json.load(f)
            if isinstance(data, list) and len(data) >= 2:
                print_comparison(data[-2], data[-1])
            else:
                print("Need at least 2 benchmark runs to compare")
        return

    # Check nargo is available
    if shutil.which("nargo") is None:
        print("Error: 'nargo' command not found. Please install Noir.", file=sys.stderr)
        sys.exit(1)

    benchmark_all(args.output)


if __name__ == "__main__":
    main()
