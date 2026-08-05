#!/usr/bin/env python3
"""Load the bounded P24-001 exact-head CI driver parts."""
from pathlib import Path

_PARTS = Path(__file__).with_name("p24_ci_driver_parts")
_SOURCE = "".join(path.read_text(encoding="utf-8") for path in sorted(_PARTS.glob("part*.inc")))
exec(compile(_SOURCE, __file__, "exec"), globals(), globals())
