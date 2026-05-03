"""Per-operation test-vector corpus dispatch.

The noir_IEEE754 test generator sources its vectors from two corpora:

- **IBM FPgen** (`.fptest` format, parsed by :mod:`noir_ieee754_inputs.fptest`).
  Hand-crafted adversarial vectors -- cancellation, sticky-bit, vicinity-of-
  rounding-boundary, special significands. Covers binary32 only.
  Snapshot mirror: <https://github.com/sergev/ieee754-test-suite>.
- **Berkeley TestFloat** (parsed by :mod:`noir_ieee754_inputs.testfloat`).
  John Hauser's systematic level-based coverage for binary16/32/64/80/128,
  all five IEEE 754 rounding modes (plus round-to-odd), and the operations
  IBM FPgen omits (``f64_*``, ``rem``, sqrt at non-default rounding).
  Source: <https://github.com/ucb-bar/berkeley-testfloat-3>.

The two corpora are *complementary*. The C.4 spike (docs/ieee754-input-prep-
redesign.md) found that:

- TestFloat covers every operation FPgen covers, plus everything FPgen
  does not (native f64, ``rem``, full rounding-mode coverage for every
  op).
- FPgen carries vectors TestFloat's level-1 random walk does not hit
  (the IBM Haifa team handcrafted them to surface specific corner cases
  in real implementations).

Hence the spike's "both-needed" verdict. This module declares the per-
operation dispatch:

- For each ``(Operation, Precision, RoundingMode)`` tuple, ``sources_for``
  returns the list of source corpora to draw test vectors from.
- ``OPERATION_SOURCES`` is the canonical declarative table. Edit it to
  flip a corpus on or off for a given operation.

The generator imports this table; consumers wishing to override (e.g.
local experimentation, debugging a specific operation) can monkey-patch
``OPERATION_SOURCES`` before invoking ``main()``.
"""

from __future__ import annotations

import dataclasses
from enum import Enum
from typing import Sequence

from .fptest import Operation, Precision, RoundingMode


class SourceCorpus(Enum):
    """The two test-vector corpora the generator can draw from."""

    FPGEN = "fpgen"
    TESTFLOAT = "testfloat"


@dataclasses.dataclass(frozen=True)
class _OpKey:
    """Hashable triple keyed against in :data:`OPERATION_SOURCES`."""

    operation: Operation
    precision: Precision
    rounding: RoundingMode


# ---------------------------------------------------------------------------
# Dispatch table.
#
# Per the C.4 spike (docs/ieee754-input-prep-redesign.md, sec 4):
#
# - For operations TestFloat has but FPgen doesn't (every f64 op, ``rem`` at
#   any precision, ``sqrt`` at non-default rounding), source from TestFloat.
# - For operations both have, use *both*: FPgen vectors light up the
#   corner cases the IBM team handcrafted, TestFloat vectors broaden the
#   structural coverage.
# - For operations FPgen has that TestFloat doesn't: empty set (verified
#   by the spike).
#
# Coverage rules (canonical):
#
# - ADD / SUB / MUL / DIV at NEAREST_EVEN, BINARY32: both corpora.
# - ADD / SUB / MUL / DIV at non-default rounding, BINARY32: both
#   (FPgen has small counts at TOWARD_*; TestFloat has full level-1).
# - ADD / SUB / MUL / DIV at any rounding, BINARY64: TestFloat only
#   (FPgen has no f64 vectors at all).
# - SQRT, FMA at any rounding, BINARY32: both for NEAREST_EVEN; TestFloat
#   only for non-default rounding (FPgen sqrt at non-default has 5 cases
#   each, retained alongside).
# - SQRT, FMA at any rounding, BINARY64: TestFloat only.
# - REM: TestFloat only at every (precision, rounding) -- FPgen has zero
#   ``rem`` vectors.
#
# The generator's filtering layer (``--operation``, ``--precision``,
# ``RoundingMode != NEAREST_EVEN`` skip) further narrows what is emitted;
# this table sets the upper bound.

_BOTH = (SourceCorpus.FPGEN, SourceCorpus.TESTFLOAT)
_TESTFLOAT_ONLY = (SourceCorpus.TESTFLOAT,)
_FPGEN_ONLY = (SourceCorpus.FPGEN,)

_BIN32_ARITH_OPS = (Operation.ADD, Operation.SUBTRACT, Operation.MULTIPLY, Operation.DIVIDE)
_ALL_ROUNDINGS = tuple(RoundingMode)


def _populate() -> dict[_OpKey, tuple[SourceCorpus, ...]]:
    table: dict[_OpKey, tuple[SourceCorpus, ...]] = {}

    # binary32 add/sub/mul/div: both corpora at every rounding mode.
    for op in _BIN32_ARITH_OPS:
        for rnd in _ALL_ROUNDINGS:
            table[_OpKey(op, Precision.BINARY32, rnd)] = _BOTH

    # binary64 add/sub/mul/div: TestFloat only.
    for op in _BIN32_ARITH_OPS:
        for rnd in _ALL_ROUNDINGS:
            table[_OpKey(op, Precision.BINARY64, rnd)] = _TESTFLOAT_ONLY

    # sqrt: f32 default-rounding has FPgen vectors; everything else is
    # TestFloat-only.
    table[_OpKey(Operation.SQRT, Precision.BINARY32, RoundingMode.NEAREST_EVEN)] = _BOTH
    for rnd in _ALL_ROUNDINGS:
        if rnd != RoundingMode.NEAREST_EVEN:
            table[_OpKey(Operation.SQRT, Precision.BINARY32, rnd)] = _BOTH
        table[_OpKey(Operation.SQRT, Precision.BINARY64, rnd)] = _TESTFLOAT_ONLY

    # fma: same shape as sqrt -- both at f32 default, TestFloat-only for
    # f64 across the board.
    for rnd in _ALL_ROUNDINGS:
        table[_OpKey(Operation.FMA, Precision.BINARY32, rnd)] = _BOTH
        table[_OpKey(Operation.FMA, Precision.BINARY64, rnd)] = _TESTFLOAT_ONLY

    # rem: TestFloat-only at every (precision, rounding) -- FPgen has none.
    for prec in (Precision.BINARY32, Precision.BINARY64):
        for rnd in _ALL_ROUNDINGS:
            table[_OpKey(Operation.REM, prec, rnd)] = _TESTFLOAT_ONLY

    return table


OPERATION_SOURCES: dict[_OpKey, tuple[SourceCorpus, ...]] = _populate()


def sources_for(
    operation: Operation,
    precision: Precision,
    rounding: RoundingMode = RoundingMode.NEAREST_EVEN,
) -> Sequence[SourceCorpus]:
    """Return the corpora that source vectors for the given (op, prec, rnd) tuple.

    Defaults to an empty tuple if the entry is absent -- callers should
    treat that as "operation not covered" and skip emission.
    """
    return OPERATION_SOURCES.get(_OpKey(operation, precision, rounding), ())
