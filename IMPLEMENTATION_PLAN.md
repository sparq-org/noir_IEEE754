# IEEE 754 Required Operations Implementation Plan

## Executive Summary

This document outlines a comprehensive plan for implementing all IEEE 754 required operations with full rounding mode support for the `noir_IEEE754` library. The plan includes test suite discovery, gap analysis, and phased implementation strategy.

---

## 1. IEEE 754 Required Operations Analysis

### 1.1 Currently Implemented Operations

| Operation | Float32 | Float64 | Test Coverage |
|-----------|---------|---------|---------------|
| **Arithmetic** | | | |
| Addition (+) | ✅ `add_float32` | ✅ `add_float64` | IBM FPgen |
| Subtraction (-) | ✅ `sub_float32` | ✅ `sub_float64` | IBM FPgen |
| Multiplication (*) | ✅ `mul_float32` | ✅ `mul_float64` | IBM FPgen |
| Division (/) | ✅ `div_float32` | ✅ `div_float64` | IBM FPgen |
| Square Root | ✅ `sqrt_float32` | ✅ `sqrt_float64` | Manual |
| Absolute Value | ✅ `abs_float32` | ✅ `abs_float64` | Manual |
| **Comparisons** | | | |
| Equal (==) | ✅ `float32_eq` | ✅ `float64_eq` | Manual |
| Not Equal (!=) | ✅ `float32_ne` | ✅ `float64_ne` | Manual |
| Less Than (<) | ✅ `float32_lt` | ✅ `float64_lt` | Manual |
| Less/Equal (<=) | ✅ `float32_le` | ✅ `float64_le` | Manual |
| Greater Than (>) | ✅ `float32_gt` | ✅ `float64_gt` | Manual |
| Greater/Equal (>=) | ✅ `float32_ge` | ✅ `float64_ge` | Manual |
| Unordered | ✅ `float32_unordered` | ✅ `float64_unordered` | Manual |
| Total Order Compare | ✅ `float32_compare` | ✅ `float64_compare` | Manual |
| **Conversions** | | | |
| To/From Bits | ✅ `float32_to_bits`/`from_bits` | ✅ `float64_to_bits`/`from_bits` | Manual |

### 1.2 Required Operations NOT Yet Implemented

#### 1.2.1 Arithmetic Operations
| Operation | Description | Priority |
|-----------|-------------|----------|
| **FMA** | Fused Multiply-Add: (a × b) + c with single rounding | HIGH |
| **Remainder** | IEEE remainder: x - n×y where n is nearest integer | MEDIUM |
| **Negate** | Sign flip (trivial but should be explicit) | LOW |
| **Copy** | Copy with preserved sign | LOW |
| **CopySign** | Copy magnitude, use sign from second arg | MEDIUM |

#### 1.2.2 Minimum/Maximum Operations (IEEE 754-2019)
| Operation | Description | Priority |
|-----------|-------------|----------|
| **minimum** | Propagates NaN, -0 < +0 | HIGH |
| **maximum** | Propagates NaN, +0 > -0 | HIGH |
| **minimumNumber** | Prefers number over NaN | HIGH |
| **maximumNumber** | Prefers number over NaN | HIGH |
| **minimumMagnitude** | Min by absolute value | MEDIUM |
| **maximumMagnitude** | Max by absolute value | MEDIUM |
| **minimumMagnitudeNumber** | Min magnitude, prefers number | MEDIUM |
| **maximumMagnitudeNumber** | Max magnitude, prefers number | MEDIUM |

#### 1.2.3 Conversion Operations
| Operation | Description | Priority |
|-----------|-------------|----------|
| **roundToIntegral** | Round to nearest integer (stays float) | HIGH |
| **roundToIntegralTiesToEven** | Round ties to even (explicit) | HIGH |
| **roundToIntegralTiesToAway** | Round ties away from zero | HIGH |
| **roundToIntegralTowardZero** | Truncate toward zero | HIGH |
| **roundToIntegralTowardPositive** | Ceiling | HIGH |
| **roundToIntegralTowardNegative** | Floor | HIGH |
| **convertToInteger** | Float → Integer (various rounding) | HIGH |
| **convertFromInteger** | Integer → Float | HIGH |
| **convertFormat** | Float32 ↔ Float64 | MEDIUM |

#### 1.2.4 NextUp/NextDown Operations
| Operation | Description | Priority |
|-----------|-------------|----------|
| **nextUp** | Next representable value toward +∞ | MEDIUM |
| **nextDown** | Next representable value toward -∞ | MEDIUM |
| **nextAfter** | Next representable toward specified direction | LOW |

#### 1.2.5 Classification Operations
| Operation | Description | Priority |
|-----------|-------------|----------|
| **isNaN** | ✅ Already exists | - |
| **isInfinite** | ✅ Already exists | - |
| **isZero** | ✅ Already exists | - |
| **isDenormal/isSubnormal** | ✅ Already exists | - |
| **isNormal** | Check if normalized | LOW |
| **isFinite** | Not NaN and not Infinity | LOW |
| **isSignMinus** | True if sign bit is 1 | LOW |
| **isCanonical** | Always true for binary formats | LOW |
| **class** | Return classification enum | MEDIUM |

#### 1.2.6 Sign Manipulation Operations
| Operation | Description | Priority |
|-----------|-------------|----------|
| **abs** | ✅ Already exists | - |
| **negate** | Flip sign bit | LOW |
| **copySign** | Copy sign from second operand | MEDIUM |

---

## 2. Rounding Mode Support

### 2.1 IEEE 754 Rounding Modes

| Mode | Symbol | Description | Status |
|------|--------|-------------|--------|
| Round to Nearest, Ties to Even | `=0` | Default mode | ✅ Implemented |
| Round to Nearest, Ties Away | `=^` | Required for decimal | ❌ Not Implemented |
| Round toward +∞ (Ceiling) | `>` | Directed rounding | ❌ Not Implemented |
| Round toward -∞ (Floor) | `<` | Directed rounding | ❌ Not Implemented |
| Round toward Zero (Truncate) | `0` | Directed rounding | ❌ Not Implemented |

### 2.2 Rounding Mode Implementation Strategy

Based on the reference implementation from `noir_XPath`, we need to:

1. **Add a `RoundingMode` enum**:
```noir
pub struct RoundingMode {
    mode: u8,  // 0=TiesToEven, 1=TiesToAway, 2=TowardPositive, 3=TowardNegative, 4=TowardZero
}

impl RoundingMode {
    pub fn ties_to_even() -> Self { RoundingMode { mode: 0 } }
    pub fn ties_to_away() -> Self { RoundingMode { mode: 1 } }
    pub fn toward_positive() -> Self { RoundingMode { mode: 2 } }
    pub fn toward_negative() -> Self { RoundingMode { mode: 3 } }
    pub fn toward_zero() -> Self { RoundingMode { mode: 4 } }
}
```

2. **Create rounding-aware versions of arithmetic operations**:
```noir
pub fn add_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn mul_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
// etc.
```

3. **Refactor existing operations** to call the rounding-aware versions with default `TiesToEven`.

### 2.3 Rounding Logic Reference (from noir_XPath)

The key rounding decision points are:
- **Guard bit (G)**: First bit beyond precision
- **Round bit (R)**: Second bit beyond precision  
- **Sticky bit (S)**: OR of all remaining bits

| Mode | Round Up When |
|------|---------------|
| Ties to Even | (G=1 AND R≠0) OR (G=1 AND R=0 AND S=0 AND LSB=1) |
| Ties Away | G=1 |
| Toward +∞ | (G=1 OR R=1 OR S=1) AND sign=positive |
| Toward -∞ | (G=1 OR R=1 OR S=1) AND sign=negative |
| Toward Zero | Never round up |

---

## 3. Test Suites Discovery

### 3.1 Currently Used Test Suite

**IBM FPgen Test Suite** ([sergev/ieee754-test-suite](https://github.com/sergev/ieee754-test-suite))

Available test files for binary floating-point:
- `Add-Cancellation-And-Subnorm-Result.fptest` - Addition edge cases
- `Add-Cancellation.fptest` - Catastrophic cancellation tests
- `Add-Shift-And-Special-Significands.fptest` - Large test suite (~18k tests)
- `Add-Shift.fptest` - Alignment shift tests
- `Basic-Types-Inputs.fptest` - Various input patterns
- `Basic-Types-Intermediate.fptest` - Intermediate value tests
- `Compare-Different-Input-Field-Relations.fptest` - **Comparison tests** ⭐
- `Corner-Rounding.fptest` - Critical rounding boundaries
- `Divide-Divide-By-Zero-Exception.fptest` - Division special cases
- `Divide-Trailing-Zeros.fptest` - Division exactness tests
- `Hamming-Distance.fptest` - ULP-distance tests
- `Input-Special-Significand.fptest` - Special significand patterns
- `Overflow.fptest` - Overflow behavior
- `Rounding.fptest` - **All rounding modes** ⭐
- `Sticky-Bit-Calculation.fptest` - Sticky bit edge cases
- `Underflow.fptest` - Underflow behavior
- `Vicinity-Of-Rounding-Boundaries.fptest` - Near-boundary values

**FMA Test Files** (also available):
- `MultiplyAdd-Cancellation-And-Subnorm-Result.fptest`
- `MultiplyAdd-Cancellation.fptest`
- `MultiplyAdd-Shift-And-Special-Significands.fptest`
- `MultiplyAdd-Shift.fptest`
- `MultiplyAdd-Special-Events-Inexact.fptest`
- `MultiplyAdd-Special-Events-Overflow.fptest`
- `MultiplyAdd-Special-Events-Underflow.fptest`

### 3.2 Additional Test Suites to Integrate

#### 3.2.1 Berkeley TestFloat
- **URL**: https://www.jhauser.us/arithmetic/TestFloat.html
- **Operations tested**: All basic operations + FMA, integer conversions
- **Formats**: 16-bit, 32-bit, 64-bit, 80-bit, 128-bit
- **Rounding modes**: All 5 modes + "round to odd"
- **Integration**: Generate test vectors using `testfloat_gen`

#### 3.2.2 UCBTEST Suite (NetLib)
- **URL**: https://www.netlib.org/fp/
- **Focus**: Elementary transcendental functions, rounding tests
- **Use for**: Square root validation, rounding boundary tests

#### 3.2.3 Fred Tydeman's C11/C99 FPCE Test Suite
- **URL**: http://www.tybor.com/
- **Focus**: C99/C11 floating-point compliance
- **Includes**: nextafter, nexttoward, copysign, fmin, fmax tests

### 3.3 Test Suite Integration Plan

1. **Extend `generate_tests.py`** to support:
   - All 5 rounding modes from IBM FPgen format
   - FMA operations (`*+` in the test files)
   - Comparison operations (from `Compare-*.fptest`)
   - Generate tests grouped by rounding mode

2. **Create Berkeley TestFloat adapter**:
   - Build TestFloat and generate test vectors
   - Convert to `.fptest` format or direct Noir test generation
   - Focus on `nextUp`, `nextDown`, integer conversion tests

3. **Add synthetic test generation** for:
   - `minimum`/`maximum` operations
   - `roundToIntegral*` operations
   - `convertFormat` (float32 ↔ float64)

---

## 4. Implementation Phases

### Phase 1: Rounding Mode Infrastructure (Priority: HIGH)

**Duration**: 1-2 weeks

**Tasks**:
1. Add `RoundingMode` struct and constants to `types.nr`
2. Create `rounding.nr` module with shared rounding logic
3. Refactor `add_float32`/`add_float64` to accept rounding mode
4. Refactor `sub_float32`/`sub_float64` to use addition with rounding
5. Refactor `mul_float32`/`mul_float64` to accept rounding mode
6. Refactor `div_float32`/`div_float64` to accept rounding mode
7. Refactor `sqrt_float32`/`sqrt_float64` to accept rounding mode
8. Maintain backward-compatible wrappers (default to TiesToEven)

**Tests**:
- Enable `Rounding.fptest` test generation
- Enable `Vicinity-Of-Rounding-Boundaries.fptest` test generation
- Add unit tests for each rounding mode

**Files to modify**:
- `ieee754/src/types.nr` - Add RoundingMode
- `ieee754/src/rounding.nr` - NEW: Shared rounding utilities
- `ieee754/src/float32/add.nr` - Add rounding parameter
- `ieee754/src/float32/mul.nr` - Add rounding parameter
- `ieee754/src/float32/div.nr` - Add rounding parameter
- `ieee754/src/float32/sqrt.nr` - Add rounding parameter
- `ieee754/src/float64/add.nr` - Add rounding parameter
- `ieee754/src/float64/mul.nr` - Add rounding parameter
- `ieee754/src/float64/div.nr` - Add rounding parameter
- `ieee754/src/float64/sqrt.nr` - Add rounding parameter
- `scripts/generate_tests.py` - Parse rounding modes

### Phase 2: FMA Implementation (Priority: HIGH)

**Duration**: 1-2 weeks

**Tasks**:
1. Implement `fma_float32(a, b, c, rm)` - Fused Multiply-Add
2. Implement `fma_float64(a, b, c, rm)` - Fused Multiply-Add
3. Add backward-compatible `fma_float32`/`fma_float64` wrappers

**Algorithm**:
```
FMA(a, b, c):
1. If any operand is NaN → return NaN
2. If (±∞ × 0) or (0 × ±∞) → return NaN (invalid operation)
3. If a × b would overflow to ±∞:
   - If c is opposite ±∞ → return NaN
   - Otherwise → return ±∞
4. Compute exact product: a × b (without rounding)
   - Product mantissa needs 2×precision bits
   - Product exponent = exp_a + exp_b - bias
5. Align c's mantissa to product's exponent
6. Add aligned mantissas with correct signs
7. Normalize result
8. Round according to rounding mode
```

**Tests**:
- Enable `MultiplyAdd-*.fptest` test generation
- Add unit tests for edge cases

**Files to create**:
- `ieee754/src/float32/fma.nr`
- `ieee754/src/float64/fma.nr`

### Phase 3: Min/Max Operations (Priority: HIGH)

**Duration**: 1 week

**Tasks**:
1. Implement `minimum_float32`/`minimum_float64` (propagates NaN)
2. Implement `maximum_float32`/`maximum_float64` (propagates NaN)
3. Implement `minimumNumber_float32`/`minimumNumber_float64` (prefers number)
4. Implement `maximumNumber_float32`/`maximumNumber_float64` (prefers number)
5. Implement magnitude variants for all above

**Semantics** (IEEE 754-2019):
```
minimum(x, y):
  - If x or y is sNaN → return qNaN, signal invalid
  - If x or y is qNaN → return qNaN
  - If x < y → return x
  - If y < x → return y
  - If x == y → return x if x is negative, else y (−0 < +0)

minimumNumber(x, y):
  - If x is NaN and y is not → return y
  - If y is NaN and x is not → return x
  - Otherwise same as minimum
```

**Tests**:
- Generate synthetic min/max tests
- Edge cases: NaN, signed zeros, infinity

**Files to create**:
- `ieee754/src/float32/minmax.nr`
- `ieee754/src/float64/minmax.nr`

### Phase 4: Round-to-Integral Operations (Priority: HIGH)

**Duration**: 1 week

**Tasks**:
1. Implement `roundToIntegralTiesToEven_float32`/`float64`
2. Implement `roundToIntegralTiesToAway_float32`/`float64`
3. Implement `roundToIntegralTowardZero_float32`/`float64` (trunc)
4. Implement `roundToIntegralTowardPositive_float32`/`float64` (ceil)
5. Implement `roundToIntegralTowardNegative_float32`/`float64` (floor)
6. Add generic `roundToIntegral_float32(x, rm)` wrapper

**Algorithm**:
```
roundToIntegral(x, rm):
1. If x is NaN → return NaN
2. If x is ±∞ → return x
3. If x is ±0 → return x
4. If |x| >= 2^precision → return x (already integral)
5. Extract integer and fractional parts
6. Apply rounding mode to determine if we round up
7. Reconstruct float with rounded integer value
```

**Reference**: The `noir_XPath` implementation provides `round_float`, `ceil_float`, `floor_float` which can be adapted.

**Tests**:
- Use Berkeley TestFloat's `roundToInt` test vectors
- Edge cases: exact halves, large values, denormals

**Files to create**:
- `ieee754/src/float32/round.nr`
- `ieee754/src/float64/round.nr`

### Phase 5: Integer Conversions (Priority: HIGH)

**Duration**: 1-2 weeks

**Tasks**:
1. Implement `convertToInteger32_float32(x, rm)` → i32/u32
2. Implement `convertToInteger64_float32(x, rm)` → i64/u64
3. Implement `convertToInteger32_float64(x, rm)` → i32/u32
4. Implement `convertToInteger64_float64(x, rm)` → i64/u64
5. Implement `convertFromInteger32_float32(n)` → Float32
6. Implement `convertFromInteger64_float32(n)` → Float32
7. Implement `convertFromInteger32_float64(n)` → Float64
8. Implement `convertFromInteger64_float64(n)` → Float64

**Edge cases**:
- NaN → invalid operation exception, return 0 or max int
- Overflow → return max/min int
- Inexact → signal inexact, round per mode

**Tests**:
- Berkeley TestFloat `*_to_i32`/`*_to_i64` tests
- Edge cases: near INT_MAX, near INT_MIN

**Files to create**:
- `ieee754/src/float32/convert.nr`
- `ieee754/src/float64/convert.nr`

### Phase 6: NextUp/NextDown Operations (Priority: MEDIUM)

**Duration**: 1 week

**Tasks**:
1. Implement `nextUp_float32`/`nextUp_float64`
2. Implement `nextDown_float32`/`nextDown_float64`
3. Implement `nextAfter_float32(x, y)`/`nextAfter_float64(x, y)`

**Algorithm**:
```
nextUp(x):
  - If x is NaN → return x (or qNaN)
  - If x is -∞ → return -MAX_FLOAT
  - If x is +∞ → return +∞
  - If x is -0 → return MIN_DENORMAL
  - If x is +0 → return MIN_DENORMAL
  - If x > 0 → return bits(x) + 1 as float
  - If x < 0 → return bits(x) - 1 as float

nextDown(x) = -nextUp(-x)
```

**Tests**:
- Fred Tydeman's `nextafter`/`nexttoward` tests
- Berkeley TestFloat (if available)

**Files to create**:
- `ieee754/src/float32/next.nr`
- `ieee754/src/float64/next.nr`

### Phase 7: Format Conversion (Priority: MEDIUM)

**Duration**: 1 week

**Tasks**:
1. Implement `convertFloat32ToFloat64(x)` (exact, no rounding needed)
2. Implement `convertFloat64ToFloat32(x, rm)` (may need rounding)

**Algorithm for Float64→Float32**:
```
convertFloat64ToFloat32(x, rm):
1. If x is NaN → return Float32 NaN
2. If x is ±∞ → return Float32 ±∞
3. If x is ±0 → return Float32 ±0
4. Extract sign, exponent, mantissa
5. Rebias exponent: new_exp = exp64 - 1023 + 127
6. If new_exp >= 255 → overflow, return ±∞ or MAX per rm
7. If new_exp <= 0 → underflow to denormal or zero
8. Truncate mantissa from 52 bits to 23 bits
9. Apply rounding using guard/round/sticky bits
10. Return Float32
```

**Reference**: `noir_XPath` has `cast_double_to_float` and `XsdDouble::from_float`.

**Tests**:
- Synthetic tests for precision loss cases
- Overflow/underflow boundary tests

**Files to create**:
- `ieee754/src/convert.nr`

### Phase 8: Remainder Operation (Priority: MEDIUM)

**Duration**: 1-2 weeks

**Tasks**:
1. Implement `remainder_float32(x, y)`
2. Implement `remainder_float64(x, y)`

**IEEE Remainder Definition**:
```
remainder(x, y) = x - n × y
where n = roundToIntegralTiesToEven(x/y)
```

**Algorithm**:
```
remainder(x, y):
1. Handle special cases (NaN, ∞, 0)
2. If |x| < |y|/2 → return x
3. Compute n = round(x/y) to nearest integer (ties to even)
4. Compute r = x - n × y using FMA if available
5. If |r| == |y|/2 and n was odd → adjust sign
6. Return r
```

**Tests**:
- Generate synthetic remainder tests
- Boundary cases where |r| = |y|/2 exactly

**Files to create**:
- `ieee754/src/float32/rem.nr`
- `ieee754/src/float64/rem.nr`

### Phase 9: Classification and Sign Operations (Priority: LOW)

**Duration**: 1 week

**Tasks**:
1. Implement `isNormal_float32`/`float64`
2. Implement `isFinite_float32`/`float64`
3. Implement `isSignMinus_float32`/`float64`
4. Implement `class_float32`/`float64` → returns classification enum
5. Implement `negate_float32`/`float64`
6. Implement `copySign_float32`/`float64`

**Classification Enum**:
```noir
pub struct FloatClass {
    class_id: u8,
}

impl FloatClass {
    pub fn signalingNaN() -> Self { FloatClass { class_id: 0 } }
    pub fn quietNaN() -> Self { FloatClass { class_id: 1 } }
    pub fn negativeInfinity() -> Self { FloatClass { class_id: 2 } }
    pub fn negativeNormal() -> Self { FloatClass { class_id: 3 } }
    pub fn negativeSubnormal() -> Self { FloatClass { class_id: 4 } }
    pub fn negativeZero() -> Self { FloatClass { class_id: 5 } }
    pub fn positiveZero() -> Self { FloatClass { class_id: 6 } }
    pub fn positiveSubnormal() -> Self { FloatClass { class_id: 7 } }
    pub fn positiveNormal() -> Self { FloatClass { class_id: 8 } }
    pub fn positiveInfinity() -> Self { FloatClass { class_id: 9 } }
}
```

**Files to create**:
- `ieee754/src/float32/class.nr`
- `ieee754/src/float64/class.nr`
- `ieee754/src/float32/sign.nr`
- `ieee754/src/float64/sign.nr`

---

## 5. Test Generation Updates

### 5.1 Update `generate_tests.py`

Extend the test generator to support:

```python
# Add rounding mode support
ROUNDING_MODES = {
    '=0': 'RoundingMode::ties_to_even()',
    '=^': 'RoundingMode::ties_to_away()',
    '>': 'RoundingMode::toward_positive()',
    '<': 'RoundingMode::toward_negative()',
    '0': 'RoundingMode::toward_zero()',
}

# Add FMA operation support
OPERATIONS = {
    '+': ('add', 2),
    '-': ('sub', 2),
    '*': ('mul', 2),
    '/': ('div', 2),
    'V': ('sqrt', 1),
    '*+': ('fma', 3),  # NEW: Fused multiply-add
    '%': ('rem', 2),   # NEW: Remainder
}

# Add comparison operation support (from Compare-*.fptest)
COMPARISON_OPS = {
    '=?': 'eq',
    '<?': 'lt',
    '<=?': 'le',
    '>?': 'gt',
    '>=?': 'ge',
    '<>?': 'ne',
}
```

### 5.2 New Test Files to Enable

| Test File | Operations | Rounding Modes |
|-----------|------------|----------------|
| `Rounding.fptest` | +, -, *, / | All 5 modes |
| `Vicinity-Of-Rounding-Boundaries.fptest` | +, -, *, / | All 5 modes |
| `Compare-Different-Input-Field-Relations.fptest` | Comparisons | N/A |
| `MultiplyAdd-*.fptest` | FMA | All 5 modes |

---

## 6. API Design

### 6.1 Rounding Mode API

```noir
// New rounding-aware functions (append _rm suffix)
pub fn add_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn sub_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn mul_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn div_float32_rm(a: IEEE754Float32, b: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn sqrt_float32_rm(a: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32
pub fn fma_float32_rm(a: IEEE754Float32, b: IEEE754Float32, c: IEEE754Float32, rm: RoundingMode) -> IEEE754Float32

// Backward-compatible wrappers (default to TiesToEven)
pub fn add_float32(a: IEEE754Float32, b: IEEE754Float32) -> IEEE754Float32 {
    add_float32_rm(a, b, RoundingMode::ties_to_even())
}
```

### 6.2 Complete Public API

```noir
// Re-exports in ieee754/src/float.nr

// Types
pub use crate::types::{IEEE754Float32, IEEE754Float64, RoundingMode, FloatClass};

// Float32 Operations (all have Float64 equivalents)
pub use crate::float32::{
    // Arithmetic (default rounding)
    add_float32, sub_float32, mul_float32, div_float32, sqrt_float32, fma_float32, remainder_float32,
    // Arithmetic (explicit rounding)
    add_float32_rm, sub_float32_rm, mul_float32_rm, div_float32_rm, sqrt_float32_rm, fma_float32_rm,
    // Comparisons
    float32_eq, float32_ne, float32_lt, float32_le, float32_gt, float32_ge,
    float32_unordered, float32_compare,
    // Min/Max
    minimum_float32, maximum_float32, minimumNumber_float32, maximumNumber_float32,
    // Round to integral
    roundToIntegral_float32, trunc_float32, ceil_float32, floor_float32, round_float32,
    // Next
    nextUp_float32, nextDown_float32, nextAfter_float32,
    // Classification
    float32_is_nan, float32_is_infinity, float32_is_zero, float32_is_denormal,
    float32_is_normal, float32_is_finite, float32_is_sign_minus, float32_class,
    // Sign manipulation
    abs_float32, negate_float32, copySign_float32,
    // Conversion
    float32_from_bits, float32_to_bits,
};

// Format conversion
pub use crate::convert::{
    convertFloat32ToFloat64, convertFloat64ToFloat32,
    convertToInteger32_float32, convertToInteger64_float32,
    convertFromInteger32_float32, convertFromInteger64_float32,
    // ... and Float64 versions
};
```

---

## 7. Testing Strategy

### 7.1 Test Categories

| Category | Source | Count (Est.) |
|----------|--------|--------------|
| Addition | IBM FPgen | ~20,000 |
| Subtraction | IBM FPgen | ~20,000 |
| Multiplication | IBM FPgen | ~20,000 |
| Division | IBM FPgen | ~5,000 |
| FMA | IBM FPgen | ~30,000 |
| Rounding Modes | IBM FPgen | ~5,000 |
| Comparisons | IBM FPgen | ~2,000 |
| Round to Integral | Synthetic | ~1,000 |
| Integer Conversion | Synthetic/Berkeley | ~2,000 |
| Min/Max | Synthetic | ~500 |
| NextUp/Down | Synthetic | ~500 |
| Format Conversion | Synthetic | ~500 |
| **Total** | | **~106,000** |

### 7.2 Recommended Test Execution

```bash
# Run by category during development
python3 scripts/run_tests.py add --rounding-mode ties_to_even
python3 scripts/run_tests.py mul --rounding-mode toward_positive
python3 scripts/run_tests.py fma

# Run all tests (CI/full validation)
python3 scripts/run_tests.py --all
```

---

## 8. Timeline Summary

| Phase | Duration | Priority | Dependencies |
|-------|----------|----------|--------------|
| Phase 1: Rounding Modes | 1-2 weeks | HIGH | None |
| Phase 2: FMA | 1-2 weeks | HIGH | Phase 1 |
| Phase 3: Min/Max | 1 week | HIGH | None |
| Phase 4: Round to Integral | 1 week | HIGH | Phase 1 |
| Phase 5: Integer Conversions | 1-2 weeks | HIGH | Phase 1, 4 |
| Phase 6: NextUp/Down | 1 week | MEDIUM | None |
| Phase 7: Format Conversion | 1 week | MEDIUM | Phase 1 |
| Phase 8: Remainder | 1-2 weeks | MEDIUM | Phase 2, 4 |
| Phase 9: Classification/Sign | 1 week | LOW | None |

**Total Estimated Duration**: 8-12 weeks

---

## 9. References

1. **IEEE 754-2019 Standard**: https://standards.ieee.org/standard/754-2019.html
2. **IBM FPgen Test Suite**: https://github.com/sergev/ieee754-test-suite
3. **Berkeley TestFloat**: https://www.jhauser.us/arithmetic/TestFloat.html
4. **Berkeley SoftFloat**: https://www.jhauser.us/arithmetic/SoftFloat.html
5. **noir_XPath Reference Implementation**: https://github.com/jeswr/noir_XPath
6. **Wikipedia IEEE 754**: https://en.wikipedia.org/wiki/IEEE_754

---

## 10. Appendix: Test File Format Reference

### IBM FPgen `.fptest` Format

```
<precision><op> <rounding> [flags] <operand1> [operand2] [operand3] -> <result> [result-flags]
```

**Examples**:
```
b32+ =0 +1.000000P+0 +1.000000P+0 -> +1.000000P+1        # Add, TiesToEven
b32* >  +1.000001P+0 +1.000001P+0 -> +1.000003P+0        # Mul, TowardPositive
b64*+ =0 +1.0P+0 +1.0P+0 +1.0P+0 -> +1.0P+1              # FMA, TiesToEven
b32=? +1.0P+0 +1.0P+0 -> 1                               # Compare equal
```

**Rounding Mode Symbols**:
- `=0` : Round to nearest, ties to even (default)
- `=^` : Round to nearest, ties away from zero
- `>`  : Round toward +∞ (ceiling)
- `<`  : Round toward -∞ (floor)
- `0`  : Round toward zero (truncation)

---

## 11. Optimisation Backlog: Field-Element Migration Investigation

Surfaced 2026-05-03 in the parent `zkp-sparql-workspace` repo
(`notes/inbox/optimisation.md`, since processed); audited 2026-05-04 as
part of the noir_IEEE754 production-quality sweep. Tracked workspace-side
in `zkp-sparql-workspace`'s `STABILISATION-TODOS.md` § Optimisation backlog.
Both files live in the parent workspace at
`https://github.com/jeswr/zkp-sparql-workspace`, not in this repo.

### 11.1 Hypothesis

> Many circuits operate on `(i|u)(8|16|32|64)` where the underlying
> field arithmetic might be cheaper if the operands stayed as `Field`
> elements (BN254). Range-bound integer types compile to range-checks
> + bit-decomposition every time they are touched; Field-native
> arithmetic skips that.

### 11.2 Audit findings

Surveyed `ieee754/src/{float32,float64}/{add,sub,mul,div,sqrt}.nr` for
hot-path locals where the integer type is incidental.

| Concern | Finding |
| --- | --- |
| Bitwise operations dominate hot paths | `add.nr`, `mul.nr`, `div.nr`, `sqrt.nr` rely on `<<`, `>>`, `&`, `|` for mantissa alignment, sticky-bit accumulation, normalisation, and round-bit extraction. Field-native arithmetic does not expose any of these; rebuilding them on top of `Field` requires the same bit-decomposition the integer types already encode. |
| "Incidental counters" are rare | Almost every `u64` in `add.nr` (12) and `mul.nr` (5 in float64) is fed straight back into a shift or mask. The "loop counter that never overflows the field" archetype the hypothesis targets is not a meaningful share of the hot path. |
| Existing optimisation pattern is healthier | `unconstrained fn` + per-clause verifier (PRs #37, #43, #48) gives O(constant) constraints in the verifier and gives the prover the full power of unconstrained Noir / native Rust-like control flow. The recent `count_leading_zeros_u23/52_verified` and `shift_right_sticky_u64/u128_verified` primitives are landing material gate reductions through this pattern, not through type changes. |
| Range-check amortisation already happens | Where the same `u64` is used for many shifts in sequence (e.g. mantissa held across alignment + rounding + normalisation), `nargo` only emits the range check at the type boundary, not on every operation. The marginal saving from skipping a single boundary check does not warrant the rewrite cost. |

### 11.3 Coordination constraint

The f32 add equivalence proof (`#104`, Lean round-3 via Lampe) is in
flight against `add_float32_with_rounding` and its dependencies in
`add.nr`. Any rewrite of those types changes the Lampe extraction
shape and re-opens the proof. **Field-element migration must not
land before the equivalence proof closes.**

### 11.4 Disposition

- **Defer.** Investigation logged here; no code changes scheduled.
- Re-evaluate **post-paper-submission**, after the Lampe round-3 proof
  is closed and after the `unconstrained` + verifier pattern has been
  rolled across all five binary ops -- only then is it meaningful to
  measure whether residual integer-typed hot spots are worth a Field
  port.
- A Field-port spike, if attempted, should target one isolated
  primitive (e.g. an alignment-shift counter that survives the verifier
  refactor) and benchmark gate count via `gate_counts.json`. Anything
  larger than one primitive is post-stabilisation work.

### 11.5 References

- Parent-workspace `STABILISATION-TODOS.md` § Optimisation backlog
  (`https://github.com/jeswr/zkp-sparql-workspace`).
- PR #37, #38, #40 (`count_leading_zeros_u23/52/64`).
- PR #43, #47, #48 (`shift_right_sticky_u64/u128`).
- PR #53 (Lampe extraction spike, depends on stable `add.nr` shape).
- PR #104 (workspace-side Lean f32 ADD equivalence proof — the
  coordination constraint in §11.3).
