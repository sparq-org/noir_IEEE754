#!/bin/bash
# Regenerate the Berkeley TestFloat capture corpus.
#
# Builds Berkeley SoftFloat-3 + TestFloat-3 from upstream sources and runs
# ``testfloat_gen`` once per (function, rounding) pair declared by
# ``noir_ieee754_inputs.sources.OPERATION_SOURCES`` as ``TESTFLOAT``-sourced.
# Captures output to ``.testfloat_cache/<function>_<rounding>.tfgen`` at
# the repo root, where ``generate_tests.py`` picks it up.
#
# Usage:
#   ./scripts/regenerate_testfloat_corpus.sh [--seed N] [--level 1|2]
#       [--max-per-function N] [--force]
#
# Environment overrides:
#   SOFTFLOAT_DIR  -- pre-existing Berkeley SoftFloat-3 source tree
#   TESTFLOAT_DIR  -- pre-existing Berkeley TestFloat-3 source tree
#   TESTFLOAT_GEN  -- pre-built ``testfloat_gen`` binary (skips clone+build)
#   TESTFLOAT_CACHE_DIR  -- override the cache directory (defaults to
#                            ``<repo>/.testfloat_cache``)
#
# Reproducibility: upstream Berkeley SoftFloat-3 / TestFloat-3 are pinned
# to known-good commits via ``SOFTFLOAT_PIN`` / ``TESTFLOAT_PIN`` below.
# Bump them deliberately (and re-run CI) when picking up an upstream fix.

set -euo pipefail

# Pinned upstream revisions. These keep the generated test corpus
# reproducible -- without them an upstream rebase or a force-push to
# master would silently change CI inputs and make failures look like
# regressions in this repo. Update + commit when you intend to roll.
SOFTFLOAT_PIN="${SOFTFLOAT_PIN:-a0c6494cdc11865811dec815d5c0049fba9d82a8}"
TESTFLOAT_PIN="${TESTFLOAT_PIN:-a9c849f1b0eb0264b626d9686ffae167d996e3be}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${TESTFLOAT_CACHE_DIR:-$REPO_ROOT/.testfloat_cache}"

SEED=1
LEVEL=1
MAX_PER_FUNCTION=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seed) SEED="$2"; shift 2 ;;
        --level) LEVEL="$2"; shift 2 ;;
        --max-per-function) MAX_PER_FUNCTION="$2"; shift 2 ;;
        --force) FORCE=1; shift 1 ;;
        -h|--help)
            sed -n '2,30p' "$0"
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

    # Clone-and-checkout-pin pattern: clone with full history (so the
    # pinned commit is reachable) then check out the exact revision. We
    # avoid ``--depth=1`` here because that would only give us the tip of
    # ``master``; the pin would be unreachable without unshallowing.
    if [[ ! -d "$SOFTFLOAT_DIR" ]]; then
        echo "Cloning Berkeley SoftFloat-3 to $SOFTFLOAT_DIR (pin=$SOFTFLOAT_PIN)..."
        git clone https://github.com/ucb-bar/berkeley-softfloat-3 "$SOFTFLOAT_DIR"
        (cd "$SOFTFLOAT_DIR" && git checkout --detach "$SOFTFLOAT_PIN")
    fi
    if [[ ! -d "$TESTFLOAT_DIR" ]]; then
        echo "Cloning Berkeley TestFloat-3 to $TESTFLOAT_DIR (pin=$TESTFLOAT_PIN)..."
        git clone https://github.com/ucb-bar/berkeley-testfloat-3 "$TESTFLOAT_DIR"
        (cd "$TESTFLOAT_DIR" && git checkout --detach "$TESTFLOAT_PIN")
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
# Cache validity: a sidecar manifest captures the inputs that determine
# the corpus contents (seed, level, max-per-function, upstream pins). If
# any of them differ from what produced the captures on disk, the cache
# is stale and the per-file existence check below would otherwise return
# the wrong corpus -- so we wipe it. ``--force`` always wipes.

mkdir -p "$CACHE_DIR"
MANIFEST="$CACHE_DIR/manifest.txt"
EXPECTED_MANIFEST="seed=$SEED
level=$LEVEL
max_per_function=${MAX_PER_FUNCTION:-unlimited}
softfloat_pin=$SOFTFLOAT_PIN
testfloat_pin=$TESTFLOAT_PIN"

if [[ "$FORCE" == "1" ]]; then
    echo "--force: wiping cache at $CACHE_DIR"
    rm -f "$CACHE_DIR"/*.tfgen "$MANIFEST"
elif [[ -f "$MANIFEST" ]]; then
    if [[ "$(cat "$MANIFEST")" != "$EXPECTED_MANIFEST" ]]; then
        echo "Cache parameters changed; invalidating $CACHE_DIR" >&2
        echo "  on disk: $(cat "$MANIFEST" | tr '\n' ' ')" >&2
        echo "  expected: $(echo "$EXPECTED_MANIFEST" | tr '\n' ' ')" >&2
        rm -f "$CACHE_DIR"/*.tfgen "$MANIFEST"
    fi
fi

# ---------------------------------------------------------------------------
# Generate captures. The Python helper enumerates exactly the (function,
# rounding) pairs declared in ``OPERATION_SOURCES`` -- single source of truth.

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
max_per_function_str = "$MAX_PER_FUNCTION"
max_per_function = int(max_per_function_str) if max_per_function_str else None

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
    if max_per_function is not None:
        # Truncate at source. ``testfloat_gen`` for ``mulAdd`` at level 1
        # emits ~6.1M cases per rounding mode; the downstream loader caps
        # per-function output anyway, so writing the full stream wastes
        # significant CI minutes and disk I/O.
        cmd = "{} | head -n {}".format(
            " ".join(args),
            int(max_per_function),
        )
        print(f"  + {cmd} > {out.name}")
        with open(out, "w") as fh:
            subprocess.run(cmd, shell=True, stdout=fh, check=True)
    else:
        print(f"  + {' '.join(args)} > {out.name}")
        with open(out, "w") as fh:
            subprocess.run(args, stdout=fh, check=True)

print("Done.")
EOF

cat > "$MANIFEST" <<MANIFEST_EOF
$EXPECTED_MANIFEST
MANIFEST_EOF

echo "Captures live under: $CACHE_DIR"
echo "Manifest: $MANIFEST"
