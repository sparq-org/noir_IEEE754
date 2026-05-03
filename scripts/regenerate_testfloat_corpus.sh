#!/bin/bash
# Regenerate the Berkeley TestFloat capture corpus.
#
# Builds Berkeley SoftFloat-3 + TestFloat-3 from upstream sources and runs
# ``testfloat_gen`` once per (function, rounding) pair declared by
# ``noir_ieee754_inputs.sources.OPERATION_SOURCES`` as ``TESTFLOAT``-sourced.
# Captures the raw output to ``.testfloat_cache/<function>_<rounding>.tfgen``
# at the repo root, where ``generate_tests.py`` picks it up.
#
# Usage:
#   ./scripts/regenerate_testfloat_corpus.sh [--seed N] [--level 1|2]
#
# Environment overrides:
#   SOFTFLOAT_DIR  -- pre-existing Berkeley SoftFloat-3 source tree
#   TESTFLOAT_DIR  -- pre-existing Berkeley TestFloat-3 source tree
#   TESTFLOAT_GEN  -- pre-built ``testfloat_gen`` binary (skips clone+build)
#   TESTFLOAT_CACHE_DIR  -- override the cache directory (defaults to
#                            ``<repo>/.testfloat_cache``)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${TESTFLOAT_CACHE_DIR:-$REPO_ROOT/.testfloat_cache}"

SEED=1
LEVEL=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seed) SEED="$2"; shift 2 ;;
        --level) LEVEL="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve / build testfloat_gen.

if [[ -z "${TESTFLOAT_GEN:-}" ]]; then
    BUILD_DIR="${BUILD_DIR:-$(mktemp -d)}"
    SOFTFLOAT_DIR="${SOFTFLOAT_DIR:-$BUILD_DIR/berkeley-softfloat-3}"
    TESTFLOAT_DIR="${TESTFLOAT_DIR:-$BUILD_DIR/berkeley-testfloat-3}"

    if [[ ! -d "$SOFTFLOAT_DIR" ]]; then
        echo "Cloning Berkeley SoftFloat-3 to $SOFTFLOAT_DIR..."
        git clone --depth=1 https://github.com/ucb-bar/berkeley-softfloat-3 "$SOFTFLOAT_DIR"
    fi
    if [[ ! -d "$TESTFLOAT_DIR" ]]; then
        echo "Cloning Berkeley TestFloat-3 to $TESTFLOAT_DIR..."
        git clone --depth=1 https://github.com/ucb-bar/berkeley-testfloat-3 "$TESTFLOAT_DIR"
    fi

    # Pick a build template based on host platform. The Linux-x86_64-GCC
    # template is the closest match for both Linux/GCC and macOS/clang;
    # we patch the compiler name and architecture flags as needed.
    HOST_OS="$(uname -s)"
    HOST_ARCH="$(uname -m)"
    case "$HOST_OS" in
        Linux)
            SF_PLATFORM="Linux-x86_64-GCC"
            CC="gcc"
            EXTRA_FLAGS=""
            ;;
        Darwin)
            SF_PLATFORM="macOS-aarch64-clang"
            CC="clang"
            EXTRA_FLAGS=""
            ;;
        *)
            echo "Unsupported host OS: $HOST_OS" >&2
            exit 1
            ;;
    esac

    SF_BUILD_DIR="$SOFTFLOAT_DIR/build/$SF_PLATFORM"
    if [[ ! -d "$SF_BUILD_DIR" ]]; then
        echo "Provisioning SoftFloat build dir $SF_BUILD_DIR..."
        cp -r "$SOFTFLOAT_DIR/build/Linux-x86_64-GCC" "$SF_BUILD_DIR"
        sed -i.bak \
            -e "s/gcc/$CC/g" \
            -e 's/-m64//g' \
            "$SF_BUILD_DIR/Makefile"
    fi

    TF_BUILD_DIR="$TESTFLOAT_DIR/build/$SF_PLATFORM"
    if [[ ! -d "$TF_BUILD_DIR" ]]; then
        echo "Provisioning TestFloat build dir $TF_BUILD_DIR..."
        cp -r "$TESTFLOAT_DIR/build/Linux-x86_64-GCC" "$TF_BUILD_DIR"
        sed -i.bak \
            -e "s/gcc/$CC/g" \
            -e 's/-m64//g' \
            -e "s|SOFTFLOAT_DIR ?= ../../../berkeley-softfloat-3|SOFTFLOAT_DIR ?= $SOFTFLOAT_DIR|" \
            -e "s/PLATFORM ?= Linux-x86_64-GCC/PLATFORM ?= $SF_PLATFORM/" \
            "$TF_BUILD_DIR/Makefile"
    fi

    echo "Building Berkeley SoftFloat-3..."
    (cd "$SF_BUILD_DIR" && make -s -j"$(getconf _NPROCESSORS_ONLN || echo 2)")

    echo "Building Berkeley TestFloat-3..."
    (cd "$TF_BUILD_DIR" && make -s -j"$(getconf _NPROCESSORS_ONLN || echo 2)" testfloat_gen)

    TESTFLOAT_GEN="$TF_BUILD_DIR/testfloat_gen"
fi

if [[ ! -x "$TESTFLOAT_GEN" ]]; then
    echo "testfloat_gen not executable: $TESTFLOAT_GEN" >&2
    exit 1
fi

echo "Using testfloat_gen: $TESTFLOAT_GEN"

# ---------------------------------------------------------------------------
# Generate captures. The Python helper enumerates exactly the (function,
# rounding) pairs declared in ``OPERATION_SOURCES`` -- single source of truth.

mkdir -p "$CACHE_DIR"

PYTHONPATH="$SCRIPT_DIR" python3 - <<EOF
from pathlib import Path
import os
import subprocess
import sys

sys.path.insert(0, "$SCRIPT_DIR")

from noir_ieee754_inputs.sources import OPERATION_SOURCES, SourceCorpus
from noir_ieee754_inputs.testfloat import (
    SUPPORTED_FUNCTIONS,
    ROUNDING_FLAGS,
)

cache_dir = Path("$CACHE_DIR")
cache_dir.mkdir(parents=True, exist_ok=True)
binary = "$TESTFLOAT_GEN"
seed = int("$SEED")
level = int("$LEVEL")

# Reverse-index: ``(operation, precision) -> testfloat function``.
fn_by_op = {(fn.operation, fn.precision): fn for fn in SUPPORTED_FUNCTIONS.values()}

pair_set = set()
pairs = []
for key, srcs in OPERATION_SOURCES.items():
    if SourceCorpus.TESTFLOAT not in srcs:
        continue
    fn = fn_by_op.get((key.operation, key.precision))
    if fn is None:
        continue
    # Deduplicate -- ``OPERATION_SOURCES`` is keyed on ``(operation,
    # precision, rounding)``; the same ``(function_name, rounding)`` pair
    # can never legitimately appear twice (function uniquely determines
    # the (operation, precision) pair via SUPPORTED_FUNCTIONS), but a
    # future table edit that maps two entries to the same testfloat_gen
    # invocation would otherwise emit duplicate captures.
    dedup_key = (fn.name, key.rounding)
    if dedup_key in pair_set:
        continue
    pair_set.add(dedup_key)
    pairs.append((fn, key.rounding))

print(f"Generating {len(pairs)} TestFloat captures into {cache_dir} (seed={seed}, level={level})")

for fn, rnd in pairs:
    out = cache_dir / f"{fn.name}_{rnd.name.lower()}.tfgen"
    if out.exists() and out.stat().st_size > 0:
        print(f"  cached {out.name}")
        continue
    args = [
        binary,
        "-seed", str(seed),
        "-level", str(level),
        ROUNDING_FLAGS[rnd],
        fn.name,
    ]
    print(f"  + {' '.join(args)} > {out.name}")
    with open(out, "w") as fh:
        subprocess.run(args, stdout=fh, check=True)

print("Done.")
EOF

echo "Captures live under: $CACHE_DIR"
