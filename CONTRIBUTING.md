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
├── Nargo.toml              # Noir project configuration
├── src/
│   ├── lib.nr              # Module exports and basic tests
│   ├── float.nr            # IEEE 754 implementation
│   └── ieee754_tests/      # Auto-generated test suite (~18k tests)
│       ├── mod.nr          # Module declarations
│       └── test_*/         # Test modules by source file
├── scripts/
│   └── generate_tests.py   # Test generation script
└── .ieee754_test_cache/    # Downloaded test files (gitignored)
```

## Test Infrastructure

This project uses the [IBM FPgen IEEE 754 test suite](https://github.com/sergev/ieee754-test-suite) to validate the implementation against comprehensive edge cases.

### How Tests Are Generated

The `scripts/generate_tests.py` script performs the following:

1. **Downloads and caches** `.fptest` files from the [IBM FPgen test suite](https://github.com/sergev/ieee754-test-suite)
2. **Parses test cases** extracting operands, operations, and precision from each line
3. **Converts operands to IEEE 754 bit patterns** handling normal, denormal, zero, infinity, and NaN values
4. **Computes expected results using Python's IEEE 754 hardware** via the `struct` module — this ensures tests verify against actual IEEE 754 behavior rather than potentially inaccurate values in the test files
5. **Generates Noir test functions** that call the implementation and assert against expected bit patterns
6. **Organizes tests into chunks** of 25 tests per file for faster parallel compilation

### Test File Structure

Tests are organized hierarchically by source file, with each module split into 25-test chunks:

```
src/ieee754_tests/
├── mod.nr                           # Top-level module declarations
├── test_add_shift/
│   ├── mod.nr                       # Chunk module declarations
│   ├── chunk_0000.nr                # Tests 0-24
│   ├── chunk_0001.nr                # Tests 25-49
│   └── chunk_0002.nr                # Tests 50-56
├── test_add_cancellation/
│   └── chunk_0000.nr                # Tests 0-17
├── test_add_cancellation_and_subnorm_result/
│   ├── chunk_0000.nr - chunk_0012.nr  # ~313 tests
│   └── ...
└── ...
```

This chunking strategy enables faster compilation and allows running targeted subsets of the ~18,000 total tests.

### Generating Tests

The `generate_tests.py` script automatically downloads test files and generates Noir test code:

```bash
# Generate tests from Add-Shift.fptest (default)
python3 scripts/generate_tests.py -o src/ieee754_tests.nr

# Use specific test files
python3 scripts/generate_tests.py --files Add-Shift.fptest Rounding.fptest -o src/ieee754_tests.nr

# Generate tests from all available test files
python3 scripts/generate_tests.py --all -o src/ieee754_tests.nr

# List available test files
python3 scripts/generate_tests.py --list

# Filter by operation type
python3 scripts/generate_tests.py --operation add --precision f32 -o src/ieee754_tests.nr

# Clear cache and re-download
python3 scripts/generate_tests.py --clear-cache -o src/ieee754_tests.nr
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

> ⚠️ **Warning**: Running `nargo test` without filters executes ~18k tests and takes several hours. Always run individual chunks or modules during development.

```bash
# Run all tests from a specific test module (recommended)
nargo test ieee754_tests::test_add_shift::

# Run a specific chunk of tests (~25 tests, fastest iteration)
nargo test ieee754_tests::test_add_shift::chunk_0000::

# Run a single specific test
nargo test ieee754_tests::test_add_shift::chunk_0000::test_f32_add_0

# Run the manual unit tests only
nargo test test_float32
nargo test test_float64

# Run all tests (takes several hours)
nargo test
```

### Test Modules

Tests are split into separate modules by source file, with each module further divided into chunks of 25 tests:

| Module | Source File | Test Count | Chunks |
|--------|-------------|------------|--------|
| `test_add_shift` | Add-Shift.fptest | 57 | 3 |
| `test_add_cancellation` | Add-Cancellation.fptest | 18 | 1 |
| `test_add_cancellation_and_subnorm_result` | Add-Cancellation-And-Subnorm-Result.fptest | 313 | 13 |
| `test_add_shift_and_special_significands` | Add-Shift-And-Special-Significands.fptest | ~16k | ~640 |
| `test_basic_types_inputs` | Basic-Types-Inputs.fptest | 882 | 36 |
| `test_basic_types_intermediate` | Basic-Types-Intermediate.fptest | 40 | 2 |
| `test_hamming_distance` | Hamming-Distance.fptest | 55 | 3 |
| `test_overflow` | Overflow.fptest | 62 | 3 |
| `test_rounding` | Rounding.fptest | 16 | 1 |
| `test_underflow` | Underflow.fptest | 20 | 1 |
| `test_vicinity_of_rounding_boundaries` | Vicinity-Of-Rounding-Boundaries.fptest | 31 | 2 |

## Submitting Changes

Please ensure all tests pass before submitting PRs:

```bash
# Generate full test suite
python3 scripts/generate_tests.py --all -o src/ieee754_tests.nr

# Run all tests
nargo test
```

## References

- [IBM FPgen Test Suite](https://github.com/sergev/ieee754-test-suite) — Source of ~18k test cases
- [What Every Computer Scientist Should Know About Floating-Point Arithmetic](https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html) — Essential IEEE 754 background
- [IEEE 754-2019 Standard](https://ieeexplore.ieee.org/document/8766229)
