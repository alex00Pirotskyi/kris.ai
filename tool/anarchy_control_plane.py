#!/usr/bin/env python3
"""Load the reviewable P24-001 control-plane implementation parts."""
from pathlib import Path

_PARTS = Path(__file__).with_name("anarchy_control_plane_parts")
_SOURCE = "".join(path.read_text(encoding="utf-8") for path in sorted(_PARTS.glob("part*.inc")))
exec(compile(_SOURCE, __file__, "exec"), globals(), globals())
