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
    # -- Isolated: the verifier on its own vs. the in-tree baseline copied
    #    from `ieee754/src/utils.rs::shift_right_sticky_u64`. The shift is
    #    a `pub u64` witness so constant-folding cannot collapse the
    #    runtime branch.
    "shr_sticky_u64_isolated_verified": {
        "extra_use": "use ieee754::shift_right_sticky_u64_verified;",
        "prelude": "",
        "inputs": "value: pub u64, shift: pub u64",
        "body": """
    shift_right_sticky_u64_verified(value, shift)
""",
        "return_type": "pub u64",
    },
    "shr_sticky_u64_isolated_baseline": {
        "extra_use": "",
        "prelude": """
fn shr_sticky_u64_baseline(value: u64, shift: u64) -> u64 {
    if shift == 0 {
        value
    } else if shift >= 64 {
        if value != 0 {
            1
        } else {
            0
        }
    } else {
        let mask = (1 << shift) - 1;
        let shifted_out = value & mask;
        let result = value >> shift;
        if shifted_out != 0 {
            result | 1
        } else {
            result
        }
    }
}
""",
        "inputs": "value: pub u64, shift: pub u64",
        "body": """
    shr_sticky_u64_baseline(value, shift)
""",
        "return_type": "pub u64",
    },
    # -- Composed: emulate the denormal-mantissa shift step that
    #    `float64/mul.nr` performs (a `shift_right_sticky_u64` driven by a
    #    witness-dependent `denorm_shift = 1 - result_exp`, with a
    #    `denorm_shift < 56` short-circuit copied verbatim from line 303 of
    #    `ieee754/src/float64/mul.nr`). The baseline copies the in-tree code;
    #    the candidate replaces the inner primitive with the verified one.
    #    Other call sites use different short-circuit thresholds (27/28 in
    #    float32, 57 in float64/{div,sqrt}); the verifier branches dynamically
    #    on `shift` so the threshold does not affect the per-call cost shape,
    #    but the surrounding straight-line code does, so this benchmark is the
    #    apples-to-apples measurement only for the float64/mul.nr call site.
    #    See `bench/SPIKES.md` for the verdict and §3.2 of the
    #    `noir-optimisation` skill for the cost model.
    "shr_sticky_u64_composed_verified": {
        "extra_use": "use ieee754::shift_right_sticky_u64_verified;",
        "prelude": """
fn denorm_shift_verified(result_mant: u64, result_exp: i64) -> (u64, u64) {
    let mut new_mant: u64 = result_mant;
    let mut new_exp: u64 = 0;
    if result_exp <= 0 {
        let denorm_shift = (1 - result_exp) as u64;
        if denorm_shift < 56 {
            new_mant = shift_right_sticky_u64_verified(result_mant, denorm_shift);
        } else {
            new_mant = 0;
        }
    } else {
        new_exp = result_exp as u64;
    }
    (new_mant, new_exp)
}
""",
        "inputs": "result_mant: pub u64, result_exp: pub i64",
        "body": """
    let (m, e) = denorm_shift_verified(result_mant, result_exp);
    m + e
""",
        "return_type": "pub u64",
    },
    "shr_sticky_u64_composed_baseline": {
        "extra_use": "",
        "prelude": """
fn shr_sticky_u64_baseline(value: u64, shift: u64) -> u64 {
    if shift == 0 {
        value
    } else if shift >= 64 {
        if value != 0 {
            1
        } else {
            0
        }
    } else {
        let mask = (1 << shift) - 1;
        let shifted_out = value & mask;
        let result = value >> shift;
        if shifted_out != 0 {
            result | 1
        } else {
            result
        }
    }
}
fn denorm_shift_baseline(result_mant: u64, result_exp: i64) -> (u64, u64) {
    let mut new_mant: u64 = result_mant;
    let mut new_exp: u64 = 0;
    if result_exp <= 0 {
        let denorm_shift = (1 - result_exp) as u64;
        if denorm_shift < 56 {
            new_mant = shr_sticky_u64_baseline(result_mant, denorm_shift);
        } else {
            new_mant = 0;
        }
    } else {
        new_exp = result_exp as u64;
    }
    (new_mant, new_exp)
}
""",
        "inputs": "result_mant: pub u64, result_exp: pub i64",
        "body": """
    let (m, e) = denorm_shift_baseline(result_mant, result_exp);
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

    # Also surface PRIMITIVE_BENCHMARKS deltas if either side has them.
    old_primitives = old_results.get("primitive_benchmarks", {})
    new_primitives = new_results.get("primitive_benchmarks", {})
    if old_primitives or new_primitives:
        print("\n" + "-" * 60)
        print("PRIMITIVE BENCHMARKS")
        print("-" * 60)
        print(f"{'Variant':<40} {'Old W/A':>10} {'New W/A':>10}")
        print("-" * 60)
        for name in sorted(set(old_primitives.keys()) | set(new_primitives.keys())):
            old_info = old_primitives.get(name, {})
            new_info = new_primitives.get(name, {})
            old_w = old_info.get("expression_width", "N/A")
            old_a = old_info.get("acir_opcodes", "N/A")
            new_w = new_info.get("expression_width", "N/A")
            new_a = new_info.get("acir_opcodes", "N/A")
            old_cell = f"{old_w}/{old_a}"
            new_cell = f"{new_w}/{new_a}"
            print(f"{name:<40} {old_cell:>10} {new_cell:>10}")
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
