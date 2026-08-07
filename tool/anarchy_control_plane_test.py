#!/usr/bin/env python3
"""Load the P24-001 regression-suite parts through the production fail-closed loader."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RUNTIME = Path(__file__).with_name("anarchy_control_plane.py")
_SPEC = importlib.util.spec_from_file_location("_p24_secure_part_loader", _RUNTIME)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError(f"cannot load secure P24 part loader from {_RUNTIME}")
_LOADER = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = _LOADER
_SPEC.loader.exec_module(_LOADER)

_EXPECTED_PARTS = (
    "part01.inc",
    "part02.inc",
    "part03.inc",
    "part04.inc",
    "part05.inc",
    "part06.inc",
    "part07.inc",
    "part08.inc",
)
_SOURCE = _LOADER._load_tracked_parts(
    __file__,
    "anarchy_control_plane_test_parts",
    _EXPECTED_PARTS,
)
exec(compile(_SOURCE, __file__, "exec"), globals(), globals())
