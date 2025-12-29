# noir_IEEE754

IEEE 754 compliant floating-point arithmetic library for [Noir](https://noir-lang.org/), a domain-specific language for zero-knowledge proofs.

> [!CAUTION]
> **Security Warning**: This library has **not been security reviewed** and should not be used in production systems without a thorough audit.

> [!WARNING]
> **AI-Generated Code**: This library is **largely AI-generated**. While it has been tested against the IBM FPgen test suite, there may be edge cases or subtle bugs that have not been discovered.

> [!NOTE]
> **Test Coverage Limitations**: The following IEEE 754 test cases are currently skipped:
> - **Non-default rounding modes**: While all rounding modes are now implemented, the test suite currently only tests "round to nearest, ties to even" (`=0`). Tests for other modes (round toward +Infinity (`>`), -Infinity (`<`), zero (`0`), or nearest away (`=^`)) will be added in the future.
> - **Non-binary operations**: FMA (`*+`) and remainder (`%`) operations are not implemented.
> - **Comparison and square root operations**: Not tested with the IBM FPgen suite (only unit tests).
> - **Known bad tests in IBM FPgen suite**: The test `b32/ =0 +1.2CEE1BP-64 +1.50EFBDP-30` from `Divide-Divide-By-Zero-Exception.fptest` is skipped due to an incorrect expected result in the test suite.
> - **Underflow edge cases**: Tests where operands underflow to zero during conversion are skipped.

## Overview

This library provides IEEE 754 standard floating-point operations in Noir, enabling verified floating-point computations in zero-knowledge circuits. The implementation supports both single-precision (binary32/float) and double-precision (binary64/double) formats.

### Features

- **IEEE 754 Float32** (single-precision): 1 sign bit, 8 exponent bits (bias 127), 23 mantissa bits
- **IEEE 754 Float64** (double-precision): 1 sign bit, 11 exponent bits (bias 1023), 52 mantissa bits
- Special value handling: ±Infinity, ±Zero, NaN, denormalized numbers
- **Multiple rounding modes**: Round to nearest (ties to even), round toward +Infinity, round toward -Infinity, round toward zero, round to nearest (ties away from zero)
- Bit-level conversion functions (`from_bits`, `to_bits`)

### Current Operations

| Operation | Float32 | Float64 | Rounding Mode Support |
|-----------|---------|---------|----------------------|
| Addition  | ✅       | ✅       | ✅ |
| Subtraction | ✅     | ✅      | ✅ |
| Multiplication | ✅  | ✅      | ✅ |
| Division | ✅       | ✅      | ✅ |
| Square Root | ✅     | ✅      | ✅ |
| Absolute Value | ✅   | ✅      | N/A (no rounding) |
| Comparison (eq, ne, lt, le, gt, ge) | ✅ | ✅ | N/A (no rounding) |
| Integer to Float (from_u32, from_u64) | ✅ | ✅ | Nearest Even |
| Float to Integer (to_u32, to_u64) | ✅ | ✅ | Truncate (toward zero) |
| Field to Float (from_field) | ✅ | ✅ | Nearest Even |
| Float to Field (to_field) | ✅ | ✅ | Truncate (toward zero) |

## Installation

Add to your `Nargo.toml`:

```toml
[dependencies]
ieee754 = { git = "https://github.com/jeswr/noir_IEEE754", tag = "v0.1.0", directory = "ieee754" }
```

## Usage

### Converting Decimal Values to Bit Representations

The library uses IEEE 754 bit representations. To convert decimal values to the hex format needed by `float32_from_bits` / `float64_from_bits`:

**Python:**
```python
import struct

# Float32 (single precision)
def float32_to_hex(f):
    return hex(struct.unpack('>I', struct.pack('>f', f))[0])

# Float64 (double precision)  
def float64_to_hex(f):
    return hex(struct.unpack('>Q', struct.pack('>d', f))[0])

print(float32_to_hex(3.0))   # 0x40400000
print(float32_to_hex(2.0))   # 0x40000000
print(float64_to_hex(3.14))  # 0x40091eb851eb851f
```

**JavaScript:**
```javascript
// Float32
function float32ToHex(f) {
    const buf = new ArrayBuffer(4);
    new Float32Array(buf)[0] = f;
    return '0x' + new Uint32Array(buf)[0].toString(16).padStart(8, '0');
}

// Float64
function float64ToHex(f) {
    const buf = new ArrayBuffer(8);
    new Float64Array(buf)[0] = f;
    const view = new DataView(buf);
    const high = view.getUint32(0, true);
    const low = view.getUint32(4, true);
    return '0x' + (BigInt(low) << 32n | BigInt(high)).toString(16).padStart(16, '0');
}
```

**Common Float32 Values:**
| Decimal | Hex | Description |
|---------|-----|-------------|
| 0.0 | `0x00000000` | Positive zero |
| -0.0 | `0x80000000` | Negative zero |
| 1.0 | `0x3F800000` | One |
| 2.0 | `0x40000000` | Two |
| 3.0 | `0x40400000` | Three |
| 0.5 | `0x3F000000` | Half |
| -1.0 | `0xBF800000` | Negative one |
| +∞ | `0x7F800000` | Positive infinity |
| -∞ | `0xFF800000` | Negative infinity |
| NaN | `0x7FC00000` | Quiet NaN |

**Common Float64 Values:**
| Decimal | Hex | Description |
|---------|-----|-------------|
| 0.0 | `0x0000000000000000` | Positive zero |
| -0.0 | `0x8000000000000000` | Negative zero |
| 1.0 | `0x3FF0000000000000` | One |
| 2.0 | `0x4000000000000000` | Two |
| 3.0 | `0x4008000000000000` | Three |
| 0.5 | `0x3FE0000000000000` | Half |
| -1.0 | `0xBFF0000000000000` | Negative one |
| +∞ | `0x7FF0000000000000` | Positive infinity |
| -∞ | `0xFFF0000000000000` | Negative infinity |
| NaN | `0x7FF8000000000000` | Quiet NaN |

### Basic Usage

```noir
use ieee754::float::{
    IEEE754Float32, IEEE754Float64,
    float32_from_bits, float32_to_bits,
    float64_from_bits, float64_to_bits,
    add_float32, add_float64,
    sub_float32, sub_float64,
    mul_float32, mul_float64,
    div_float32, div_float64,
    sqrt_float32, sqrt_float64,
    abs_float32, abs_float64,
    // Special value constants
    FLOAT32_ZERO, FLOAT32_ONE, FLOAT32_NEG_ONE, FLOAT32_INFINITY, FLOAT32_NAN,
    FLOAT64_ZERO, FLOAT64_ONE, FLOAT64_NEG_ONE, FLOAT64_INFINITY, FLOAT64_NAN,
    // Comparison operations
    float32_eq, float32_ne, float32_lt, float32_le, float32_gt, float32_ge,
    float64_eq, float64_ne, float64_lt, float64_le, float64_gt, float64_ge
};

fn main() {
    // Create floats from bit representation (use conversion methods above)
    let a = float32_from_bits(0x40400000); // 3.0f
    let b = float32_from_bits(0x40000000); // 2.0f
    
    // Or use predefined constants
    let one = float32_from_bits(FLOAT32_ONE);
    let zero = float32_from_bits(FLOAT32_ZERO);
    
    // Perform arithmetic operations
    let sum = add_float32(a, b);        // 3.0 + 2.0 = 5.0
    let diff = sub_float32(a, b);       // 3.0 - 2.0 = 1.0
    let product = mul_float32(a, b);    // 3.0 * 2.0 = 6.0
    let quotient = div_float32(a, b);   // 3.0 / 2.0 = 1.5
    let root = sqrt_float32(a);         // sqrt(3.0) ≈ 1.732
    let magnitude = abs_float32(float32_from_bits(0xBF800000)); // abs(-1.0) = 1.0
    
    // Convert back to bits
    let sum_bits = float32_to_bits(sum);         // 0x40A00000 = 5.0f
    let diff_bits = float32_to_bits(diff);       // 0x3F800000 = 1.0f
    let product_bits = float32_to_bits(product); // 0x40C00000 = 6.0f
    let quotient_bits = float32_to_bits(quotient); // 0x3FC00000 = 1.5f
}
```

### Rounding Modes

All arithmetic operations (addition, subtraction, multiplication, division, square root) support multiple IEEE 754 rounding modes:

```noir
use ieee754::float::{
    float32_from_bits, float32_to_bits,
    add_float32_with_rounding, mul_float32_with_rounding,
    // Rounding mode constants
    ROUNDING_MODE_NEAREST_EVEN,     // Round to nearest, ties to even (default)
    ROUNDING_MODE_NEAREST_AWAY,     // Round to nearest, ties away from zero
    ROUNDING_MODE_TOWARD_POSITIVE,  // Round toward +Infinity (ceiling)
    ROUNDING_MODE_TOWARD_NEGATIVE,  // Round toward -Infinity (floor)
    ROUNDING_MODE_TOWARD_ZERO       // Round toward zero (truncate)
};

fn main() {
    let a = float32_from_bits(0x3F800000); // 1.0
    let b = float32_from_bits(0x3EAAAAAB); // 0.333...
    
    // Default rounding (round to nearest, ties to even)
    let result_default = add_float32(a, b);
    
    // Explicit rounding modes
    let result_nearest = add_float32_with_rounding(a, b, ROUNDING_MODE_NEAREST_EVEN);
    let result_ceiling = add_float32_with_rounding(a, b, ROUNDING_MODE_TOWARD_POSITIVE);
    let result_floor = add_float32_with_rounding(a, b, ROUNDING_MODE_TOWARD_NEGATIVE);
    let result_truncate = add_float32_with_rounding(a, b, ROUNDING_MODE_TOWARD_ZERO);
    
    // All operations have _with_rounding variants:
    // add_float32_with_rounding, sub_float32_with_rounding,
    // mul_float32_with_rounding, div_float32_with_rounding,
    // sqrt_float32_with_rounding
    // (and same for float64)
}
```

**Note**: The default functions (`add_float32`, `mul_float32`, etc.) use `ROUNDING_MODE_NEAREST_EVEN` for backward compatibility.

### Helper Functions

```noir
// Special value checks
float32_is_nan(x)       // Check if NaN
float32_is_infinity(x)  // Check if ±Infinity
float32_is_zero(x)      // Check if ±0
float32_is_denormal(x)  // Check if denormalized

// Create special values
float32_nan()           // Returns NaN
float32_infinity(sign)  // Returns ±Infinity
float32_zero(sign)      // Returns ±0

// Square root (IEEE 754 compliant)
sqrt_float32(x)         // sqrt(x), returns NaN for negative inputs (except -0)

// Absolute value (IEEE 754 compliant)
abs_float32(x)          // |x|, returns magnitude with sign bit cleared

// Comparison functions (IEEE 754 compliant)
float32_eq(a, b)        // a == b (NaN != NaN, +0 == -0)
float32_ne(a, b)        // a != b
float32_lt(a, b)        // a < b (false if either is NaN)
float32_le(a, b)        // a <= b (false if either is NaN)
float32_gt(a, b)        // a > b (false if either is NaN)
float32_ge(a, b)        // a >= b (false if either is NaN)
float32_unordered(a, b) // true if either is NaN
float32_compare(a, b)   // -1, 0, or 1 (total ordering including NaN)

// Same functions available for float64 with float64_ prefix (except sqrt uses sqrt_float64)
```

### Integer Conversions

The library provides functions to convert between integers and floating-point numbers:

```noir
use ieee754::float::{
    // Integer to float conversions
    float32_from_u32, float32_from_u64,
    float64_from_u32, float64_from_u64,
    // Float to integer conversions (truncate toward zero)
    float32_to_u32, float32_to_u64,
    float64_to_u32, float64_to_u64,
};

fn main() {
    // Convert unsigned integers to floats
    let a = float32_from_u32(42);        // 42u32 -> 42.0f32
    let b = float32_from_u64(1000000);   // 1000000u64 -> 1000000.0f32
    let c = float64_from_u32(42);        // 42u32 -> 42.0f64 (exact)
    let d = float64_from_u64(1000000);   // 1000000u64 -> 1000000.0f64
    
    // Convert floats to unsigned integers (truncate toward zero)
    let x = float32_to_u32(float32_from_bits(0x40400000)); // 3.0f -> 3u32
    let y = float32_to_u32(float32_from_bits(0x402CCCCD)); // 2.7f -> 2u32 (truncated)
    let z = float32_to_u64(float32_from_bits(0x447A0000)); // 1000.0f -> 1000u64
    
    // Special cases:
    // - NaN converts to 0
    // - Negative values convert to 0 for unsigned types
    // - Overflow returns maximum value (0xFFFFFFFF for u32, 0xFFFFFFFFFFFFFFFF for u64)
    // - Fractional parts are truncated (round toward zero)
}
```

> **⚠️ Warning**: All integer and Field conversion functions have not been extensively tested or reviewed. Use with caution in production systems.

### Field Conversions

The library provides functions to convert between Noir's native Field type and floating-point numbers:

```noir
use ieee754::float::{
    // Field to float conversions
    float32_from_field, float64_from_field,
    // Float to Field conversions (truncate toward zero)
    float32_to_field, float64_to_field,
};

fn main() {
    // Convert Field to floats
    let field_val: Field = 42;
    let f32 = float32_from_field(field_val);  // Field -> float32
    let f64 = float64_from_field(field_val);  // Field -> float64
    
    // Convert floats to Field (truncate toward zero)
    let result: Field = float32_to_field(f32);
    
    // Note: Field elements can be very large (typically 254 bits)
    // Conversion to float will lose significant precision for large values
    // Only the lower 64 bits are used in the conversion
}
```

**Field Conversion Notes:**
- Field elements are converted by taking the value modulo 2^64 before converting to float
- This means only the lower 64 bits of the Field are preserved in the conversion
- Float-to-Field conversions truncate toward zero, similar to float-to-integer conversions
- NaN and negative float values convert to Field(0)
- Very large Field values will lose precision when converting to float

## Development Status

**Precision Notes:**
- `float32_from_u32`: All u32 values up to and including 2^24 (16777216) are exactly representable; values above 2^24 may require rounding
- `float32_from_u64`: May lose precision for values > 2^24
- `float64_from_u32`: All u32 values are exactly representable (float64 has 53 mantissa bits)
- `float64_from_u64`: All u64 values up to and including 2^53 (9007199254740992) are exactly representable; values above 2^53 may require rounding

**Truncation Behavior:**
- All float-to-integer conversions truncate toward zero (same as C/Rust casting)
- Values less than 1.0 truncate to 0
- Negative values truncate to 0 for unsigned types
- Overflow returns the maximum value for the target type
- NaN converts to 0

## Development Status

### Current State

The library implements IEEE 754 arithmetic for both float32 and float64 with full support for:

- ✅ **All basic operations**: Addition, subtraction, multiplication, division, square root
- ✅ **Comparison operations**: eq, ne, lt, le, gt, ge, unordered, compare
- ✅ **Normalized numbers**: Standard floating-point values
- ✅ **Denormalized (subnormal) numbers**: Gradual underflow handling
- ✅ **Special values**: ±Zero, ±Infinity, NaN (quiet and signaling)
- ✅ **Multiple rounding modes**: Round to nearest (ties to even/away), toward +Infinity, toward -Infinity, toward zero
- ✅ **Guard, round, and sticky bits**: For correct rounding during alignment shifts

### Next Steps

1. ✅ **Support Multiple Rounding Modes**: Round toward +Infinity, -Infinity, zero _(Completed in Phase 1)_
2. **Optimize Performance**: Reduce constraint count for ZK circuits
3. **Add FMA operation**: `fma_float32`/`fma_float64`
4. **Generate tests for all rounding modes**: Extend test generation script to cover all rounding modes

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for test infrastructure details, development workflow, and commit message conventions.

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automated versioning and release management. Please follow the commit message format described in CONTRIBUTING.md.

## Releases

This project uses [semantic-release](https://github.com/semantic-release/semantic-release) for automated versioning and releases. Releases are automatically created when changes are merged to the main branch, based on the commit messages:

- `feat:` commits trigger a minor version bump (e.g., 0.4.0 → 0.5.0)
- `fix:` commits trigger a patch version bump (e.g., 0.4.0 → 0.4.1)
- `feat!:` or commits with `BREAKING CHANGE:` trigger a major version bump (e.g., 0.4.0 → 1.0.0)

The changelog is automatically generated and included in each GitHub release. For more details, see [SEMANTIC_RELEASE.md](SEMANTIC_RELEASE.md).

## License

[MIT License](LICENSE)

## References

- [IEEE 754-2019 Standard](https://ieeexplore.ieee.org/document/8766229)
- [Noir Language Documentation](https://noir-lang.org/docs)
