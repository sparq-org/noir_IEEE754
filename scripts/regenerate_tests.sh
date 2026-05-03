#!/bin/bash
# Regenerate IEEE 754 test suite for Noir
#
# Sources test vectors from two upstream corpora:
#
# - **IBM FPgen** (.fptest format) -- handcrafted adversarial vectors,
#   downloaded on demand from sergev/ieee754-test-suite into the
#   ``.ieee754_test_cache/`` directory.
# - **Berkeley TestFloat** (testfloat_gen output) -- systematic level-based
#   coverage built from upstream sources. Skipped when the
#   ``.testfloat_cache/`` directory is absent; populate it by running
#   ``./scripts/regenerate_testfloat_corpus.sh`` first.
#
# Usage:
#   ./scripts/regenerate_tests.sh              # Generate all tests as packages
#   ./scripts/regenerate_tests.sh --operation add  # Generate only addition tests
#
# To enable the TestFloat corpus locally:
#   ./scripts/regenerate_testfloat_corpus.sh   # Build + capture (one-time, ~3 GB cache)
#   ./scripts/regenerate_tests.sh              # Generator picks it up automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Regenerating IEEE 754 test suite..."
echo "Project root: $PROJECT_ROOT"
echo ""

# Default arguments - use packages mode for separate test packages
ARGS=(
    --all
    --packages
    --output-dir test_packages
    --ci-matrix .github/test-matrix.json
    --testfloat-max-per-function 2000
)

# Auto-discover the TestFloat capture cache.
if [[ -d "$PROJECT_ROOT/.testfloat_cache" ]]; then
    ARGS+=(--testfloat-cache "$PROJECT_ROOT/.testfloat_cache")
fi

# Append any additional arguments passed to this script
ARGS+=("$@")

echo "Running: python3 scripts/generate_tests.py ${ARGS[*]}"
echo ""

python3 scripts/generate_tests.py "${ARGS[@]}"

echo ""
echo "Done! Generated test packages are in test_packages/"
echo "CI matrix is at .github/test-matrix.json"
