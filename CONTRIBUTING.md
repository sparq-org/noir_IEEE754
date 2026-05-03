# Contributing to noir_IEEE754

Contributions are welcome! This guide covers the project structure, test infrastructure, and development workflow.

## Commit Message Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated versioning and changelog generation. Please follow these guidelines when writing commit messages:

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Types

- **feat**: A new feature (triggers minor version bump)
- **fix**: A bug fix (triggers patch version bump)
- **docs**: Documentation only changes
- **style**: Code style changes (formatting, missing semicolons, etc.)
- **refactor**: Code refactoring without changing functionality
- **perf**: Performance improvements
- **test**: Adding or updating tests
- **chore**: Maintenance tasks, dependency updates, etc.
- **ci**: Changes to CI configuration files and scripts

### Breaking Changes

To indicate a breaking change (triggers major version bump), add `BREAKING CHANGE:` in the commit footer or add `!` after the type/scope:

```
feat!: change float32_add signature

BREAKING CHANGE: The function now requires a rounding mode parameter
```

### Examples

```
feat(float): add fused multiply-add operation
fix(div): correct division by zero handling for denormals
docs: update README with Field conversion examples
test: add tests for edge cases in sqrt operation
chore: update dependencies
```

### Scope (Optional)

Common scopes in this project:
- `float`: Core floating-point operations
- `conversion`: Integer/Field conversion functions
- `test`: Test infrastructure
- `ci`: CI/CD workflows
- `docs`: Documentation

## Project Structure

```
noir_IEEE754/
├── Nargo.toml              # Workspace manifest
├── ieee754/                # Core IEEE 754 implementation crate
│   ├── Nargo.toml
│   └── src/
│       ├── lib.nr          # Module exports
│       └── float.nr        # IEEE 754 implementation
├── ieee754_unit_tests/     # Hand-written unit tests
├── test_packages/          # Auto-generated test packages (gitignored, ~18k tests)
│   └── ieee754_test_*/     # One Noir bin package per source .fptest file
├── scripts/
│   ├── generate_tests.py   # Test generation script
│   ├── regenerate_tests.sh # Regenerate the full test suite
│   └── run_tests.py        # Run packages with optional filtering
└── .ieee754_test_cache/    # Downloaded test files (gitignored)
```

## Test Infrastructure

This project uses the [IBM FPgen IEEE 754 test suite](https://github.com/sergev/ieee754-test-suite) to validate the implementation against comprehensive edge cases.

### How Tests Are Generated

The `scripts/generate_tests.py` script performs the following:

1. **Downloads and caches** `.fptest` files from the [IBM FPgen test suite](https://github.com/sergev/ieee754-test-suite)
2. **Parses test cases** extracting operands, operations, precision and rounding mode from each line
3. **Converts operands to IEEE 754 bit patterns** handling normal, denormal, zero, infinity, and NaN values
4. **Computes expected results** using Python's IEEE 754 hardware (`struct.pack`) for round-to-nearest-even, and the MPFR-backed reference oracle (`scripts/noir_ieee754_inputs/reference.py`, `gmpy2`) for the four directed rounding modes -- this ensures tests verify against actual IEEE 754 behaviour rather than potentially inaccurate values in the test files
5. **Generates Noir test functions** that call the implementation and assert against expected bit patterns. Non-default rounding modes are emitted via the `op_floatN_with_rounding` helpers; the `_with_rounding` helpers are imported automatically by `analyze_test_code`
6. **Organises tests into separate Noir packages** (one per source `.fptest` file) with chunks of 25 tests per file for faster parallel compilation
7. **Drops tests in `KNOWN_BAD_TESTS_BY_ROUNDING`** -- a cross-cutting allow-list of cases the existing arithmetic circuits cannot yet pass under non-default rounding modes. The list size is the f64-hardening progress metric (see [`questions/enable-non-default-rounding-modes.md`](https://github.com/jeswr/zkp-sparql-workspace/blob/main/questions/enable-non-default-rounding-modes.md), decision C); future PRs that fix the underlying circuit bugs shrink it. Each entry carries a comment naming the bug class.

### Test Package Structure

Each source `.fptest` file becomes its own Noir bin package under `test_packages/`, with tests sharded into 25-test chunks. Files larger than `--max-tests-per-package` (default 1250) are split across multiple `_partN` packages.

```
test_packages/
├── ieee754_test_add_shift/
│   ├── Nargo.toml                   # Depends on ../../ieee754
│   └── src/
│       ├── main.nr                  # Module index + fn main()
│       ├── chunk_0000.nr            # Tests 0-24
│       ├── chunk_0001.nr            # Tests 25-49
│       └── chunk_0002.nr            # Tests 50-56
├── ieee754_test_add_cancellation/
│   └── src/
│       └── chunk_0000.nr            # Tests 0-17
├── ieee754_test_add_shift_and_special_significands_part0/
│   └── ...                          # Large file, split into multiple packages
└── ...
```

This per-package chunking strategy enables faster compilation and allows running targeted subsets of the ~18,000 total tests.

### Generating Tests

The recommended path is `scripts/regenerate_tests.sh`, which wraps `generate_tests.py --all --packages`:

```bash
# Regenerate the full test suite (all packages + CI matrix)
./scripts/regenerate_tests.sh

# Regenerate only the addition tests
./scripts/regenerate_tests.sh --operation add
```

For finer-grained control you can call `generate_tests.py` directly:

```bash
# Generate all test files as separate Noir packages
python3 scripts/generate_tests.py --all --packages --output-dir test_packages

# Use specific test files
python3 scripts/generate_tests.py --files Add-Shift.fptest Rounding.fptest --packages --output-dir test_packages

# List available test files
python3 scripts/generate_tests.py --list

# Filter by operation type
python3 scripts/generate_tests.py --operation add --precision f32 --packages --output-dir test_packages

# Clear cache and re-download
python3 scripts/generate_tests.py --clear-cache --all --packages --output-dir test_packages
```

### Available Test Files

| File | Description |
|------|-------------|
| `Add-Cancellation-And-Subnorm-Result.fptest` | Cancellation leading to subnormal results |
| `Add-Cancellation.fptest` | Catastrophic cancellation cases |
| `Add-Shift-And-Special-Significands.fptest` | Alignment shift with special significands |
| `Add-Shift.fptest` | Alignment shift edge cases |
| `Basic-Types-Inputs.fptest` | Basic input type testing |
| `Basic-Types-Intermediate.fptest` | Intermediate calculation types |
| `Compare-Different-Input-Field-Relations.fptest` | Comparison operations |
| `Corner-Rounding.fptest` | Corner case rounding scenarios |
| `Divide-Divide-By-Zero-Exception.fptest` | Division by zero handling |
| `Divide-Trailing-Zeros.fptest` | Division with trailing zeros |
| `Hamming-Distance.fptest` | Hamming distance edge cases |
| `Input-Special-Significand.fptest` | Special significand inputs |
| `Overflow.fptest` | Overflow boundary cases |
| `Rounding.fptest` | Rounding mode edge cases |
| `Sticky-Bit-Calculation.fptest` | Sticky bit handling |
| `Underflow.fptest` | Underflow edge cases |
| `Vicinity-Of-Rounding-Boundaries.fptest` | Near rounding boundary cases |

### Running Tests

> ⚠️ **Warning**: Running every package executes ~18k tests and takes several hours. Use `scripts/run_tests.py` with a filter during development.

```bash
# List available packages
python3 scripts/run_tests.py --list

# Run a single package (fastest iteration)
python3 scripts/run_tests.py --package ieee754_test_add_shift

# Run packages whose name matches a substring
python3 scripts/run_tests.py add_shift

# Regenerate test packages, then run them
python3 scripts/run_tests.py --generate

# Run only the hand-written unit tests
nargo test --package ieee754_unit_tests

# Run every package in the workspace (takes several hours)
nargo test --workspace
```

### Test Packages

Tests are split into separate Noir packages by source file, each package further divided into chunks of 25 tests. Source files exceeding `--max-tests-per-package` are split into multiple `_partN` packages.

| Package | Source File | Test Count | Chunks |
|--------|-------------|------------|--------|
| `ieee754_test_add_shift` | Add-Shift.fptest | 57 | 3 |
| `ieee754_test_add_cancellation` | Add-Cancellation.fptest | 18 | 1 |
| `ieee754_test_add_cancellation_and_subnorm_result` | Add-Cancellation-And-Subnorm-Result.fptest | 313 | 13 |
| `ieee754_test_add_shift_and_special_significands_part*` | Add-Shift-And-Special-Significands.fptest | ~16k | ~640 |
| `ieee754_test_basic_types_inputs` | Basic-Types-Inputs.fptest | 882 | 36 |
| `ieee754_test_basic_types_intermediate` | Basic-Types-Intermediate.fptest | 40 | 2 |
| `ieee754_test_hamming_distance` | Hamming-Distance.fptest | 55 | 3 |
| `ieee754_test_overflow` | Overflow.fptest | 62 | 3 |
| `ieee754_test_rounding` | Rounding.fptest | 16 | 1 |
| `ieee754_test_underflow` | Underflow.fptest | 20 | 1 |
| `ieee754_test_vicinity_of_rounding_boundaries` | Vicinity-Of-Rounding-Boundaries.fptest | 31 | 2 |

## Submitting Changes

Please ensure all tests pass before submitting PRs:

```bash
# Regenerate the full test suite (packages + CI matrix)
./scripts/regenerate_tests.sh

# Run every package in the workspace (takes several hours)
nargo test --workspace
```

## References

- [IBM FPgen Test Suite](https://github.com/sergev/ieee754-test-suite) — Source of ~18k test cases
- [What Every Computer Scientist Should Know About Floating-Point Arithmetic](https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html) — Essential IEEE 754 background
- [IEEE 754-2019 Standard](https://ieeexplore.ieee.org/document/8766229)
