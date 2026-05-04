"""Regression tests for ``run_testfloat_gen`` capture-then-truncate semantics.

Roborev #448 medium #3: the previous regen pipeline did
``testfloat_gen | head`` via ``shell=True`` which silently swallowed
``testfloat_gen`` failures (only ``head``'s exit status reached the
caller). These tests use a stub ``testfloat_gen`` shell script to
exercise three scenarios:

1. The stub emits more lines than ``max_tests``, so ``run_testfloat_gen``
   closes the pipe early and the stub dies of SIGPIPE -- this must
   *not* raise. The truncated capture file contains exactly
   ``max_tests`` lines.
2. The stub exits non-zero before reaching ``max_tests`` -- this must
   raise ``TestFloatGenError`` and delete the partial capture.
3. The stub exits zero with fewer than ``max_tests`` lines -- this is
   accepted and the capture file holds exactly the lines emitted.

Run via ``python -m pytest scripts/test_run_testfloat_gen.py``.
"""
from __future__ import annotations

import os
import stat
import sys
import textwrap
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from noir_ieee754_inputs.fptest import RoundingMode  # noqa: E402
from noir_ieee754_inputs.testfloat import (  # noqa: E402
    SUPPORTED_FUNCTIONS,
    TestFloatGenError,
    run_testfloat_gen,
)


def _make_stub(tmp_path: Path, body: str) -> Path:
    """Materialise a shell stub that mimics testfloat_gen output."""
    stub = tmp_path / "stub_gen"
    stub.write_text("#!/bin/bash\n" + body)
    stub.chmod(stub.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return stub


@pytest.fixture
def f64_add_function():
    """Pick any supported function; the stub doesn't actually parse args."""
    for fn in SUPPORTED_FUNCTIONS.values():
        if fn.name == "f64_add":
            return fn
    raise AssertionError("f64_add not registered in SUPPORTED_FUNCTIONS")


def test_max_tests_truncates_long_stream_without_raising(tmp_path, f64_add_function):
    """Stub emits 1000 lines; we cap at 5; the stub dies of SIGPIPE on
    the next write. Must *not* raise; capture file holds exactly 5
    lines. This is the canonical happy-path for the bounded regen."""
    stub = _make_stub(
        tmp_path,
        textwrap.dedent(
            """\
            for i in $(seq 1 1000); do
                printf 'line %d\\n' "$i"
            done
            """
        ),
    )
    out = tmp_path / "f64_add_rne.tfgen"
    result = run_testfloat_gen(
        stub,
        function=f64_add_function,
        rounding=RoundingMode.NEAREST_EVEN,
        max_tests=5,
        output_path=out,
    )
    assert result == out
    assert out.exists()
    lines = out.read_text().splitlines()
    assert lines == [f"line {i}" for i in range(1, 6)]


def test_failing_stub_raises_and_deletes_partial_capture(tmp_path, f64_add_function):
    """Stub exits 1 after 2 lines (well below max_tests). Roborev #448
    medium #3 regression: the previous shell-pipe pipeline reported
    only ``head``'s exit, so a real ``testfloat_gen`` segfault would
    look successful. ``run_testfloat_gen`` must raise here."""
    stub = _make_stub(
        tmp_path,
        textwrap.dedent(
            """\
            printf 'line 1\\n'
            printf 'line 2\\n'
            exit 7
            """
        ),
    )
    out = tmp_path / "f64_add_rne.tfgen"
    with pytest.raises(TestFloatGenError) as exc:
        run_testfloat_gen(
            stub,
            function=f64_add_function,
            rounding=RoundingMode.NEAREST_EVEN,
            max_tests=100,
            output_path=out,
        )
    assert "rc=7" in str(exc.value)
    assert not out.exists(), "partial capture must be wiped"


def test_short_stream_succeeds_when_under_max_tests(tmp_path, f64_add_function):
    """Stub emits 3 lines and exits 0; max_tests=100. We accept the
    short stream rather than insisting on exactly max_tests."""
    stub = _make_stub(
        tmp_path,
        textwrap.dedent(
            """\
            printf 'line 1\\nline 2\\nline 3\\n'
            """
        ),
    )
    out = tmp_path / "f64_add_rne.tfgen"
    run_testfloat_gen(
        stub,
        function=f64_add_function,
        rounding=RoundingMode.NEAREST_EVEN,
        max_tests=100,
        output_path=out,
    )
    assert out.read_text() == "line 1\nline 2\nline 3\n"


def test_unbounded_capture_paths_still_propagate_failures(tmp_path, f64_add_function):
    """When ``max_tests`` is None we use ``subprocess.run(..., check=True)``;
    a failing stub must still raise (CalledProcessError, not TestFloatGenError --
    this is the unmodified path)."""
    import subprocess
    stub = _make_stub(
        tmp_path,
        "exit 9\n",
    )
    out = tmp_path / "f64_add_rne.tfgen"
    with pytest.raises(subprocess.CalledProcessError):
        run_testfloat_gen(
            stub,
            function=f64_add_function,
            rounding=RoundingMode.NEAREST_EVEN,
            max_tests=None,
            output_path=out,
        )
