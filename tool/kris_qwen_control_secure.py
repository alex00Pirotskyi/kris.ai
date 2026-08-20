#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys

COMPAT = pathlib.Path(__file__).with_name("kris_qwen_control.py.compat.py")
TARGET_CONTROL_VERSION = "2.2.1"


def load_compat():
    spec = importlib.util.spec_from_file_location("kris_qwen_control_compat_secure_base", COMPAT)
    if spec is None or spec.loader is None:
        raise SystemExit("KRIS_QWEN_CONTROL_SECURE_ERROR: cannot load controller 2.2 compatibility entry")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


compat = load_compat()
compat.TARGET_CONTROL_VERSION = TARGET_CONTROL_VERSION
compat.base.CONTROL_VERSION = TARGET_CONTROL_VERSION
compat.base.ControlHandler.server_version = "KrisQwenControl/2.2.1"
_ORIGINAL_PRINT = print


def safe_controller_print(*args, **kwargs):
    # Base controller 2.1 historically printed the bearer value in phone mode.
    # Never let that secret cross stdout/stderr where systemd/journald captures it.
    first = str(args[0]) if args else ""
    if "PHONE CONTROL TOKEN" in first:
        file_value = kwargs.get("file")
        return _ORIGINAL_PRINT(
            "Phone control token value omitted from logs; read it from the configured token file.",
            file=file_value,
            flush=kwargs.get("flush", False),
        )
    return _ORIGINAL_PRINT(*args, **kwargs)


compat.base.print = safe_controller_print


def main() -> int:
    return compat.main()


if __name__ == "__main__":
    raise SystemExit(main())
