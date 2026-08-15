#!/usr/bin/env python3
"""Compatibility facade for durable mission-delivery validation.

Historical v1 records used uppercase hexadecimal entropy in otherwise valid
work execution IDs. Generation remains canonical lowercase; validation accepts
either hexadecimal case without broadening the identifier shape.
"""
from __future__ import annotations

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import mission_delivery_lib_v1 as _impl

_impl.WORK_ID_RE = re.compile(r"^WRK-\d{8}T\d{6}Z-[0-9A-Fa-f]{8}$")

from mission_delivery_lib_v1 import *  # noqa: E402,F401,F403

WORK_ID_RE = _impl.WORK_ID_RE
