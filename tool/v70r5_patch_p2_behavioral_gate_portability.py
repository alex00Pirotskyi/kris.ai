#!/usr/bin/env python3
from __future__ import annotations

import argparse
import builtins
import json
import pathlib
import subprocess
import sys
import types

OLD_IMPORT = (
    "import argparse, hashlib, json, os, pathlib, pty, select, shutil, signal, "
    "struct, subprocess, sys, tempfile, termios, time, traceback"
)
NEW_IMPORT = (
    "import argparse, hashlib, json, os, pathlib, select, shutil, signal, "
    "struct, subprocess, sys, tempfile, time, traceback\n\n"
    "if os.name != 'nt':\n"
    "    import pty\n"
    "    import termios\n"
    "else:\n"
    "    pty = None\n"
    "    termios = None"
)
OLD_PTY_GUARD = (
    "    if os.name=='nt': return [result('PTY Linux fixture','unsupported',"
    "'Windows runs ConPTY fixture in CI')]"
)
NEW_PTY_GUARD = (
    "    if os.name=='nt' or pty is None or termios is None:\n"
    "        return [result('PTY Linux fixture','unsupported',"
    "'Windows runs ConPTY fixture in CI')]"
)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def patch(project: pathlib.Path) -> list[str]:
    target = project / "tool/p2_behavioral_gate.py"
    if not target.is_file():
        fail(f"P2 behavioral gate missing: {target}")
    text = target.read_text(encoding="utf-8")
    changed = False
    if NEW_IMPORT not in text:
        if OLD_IMPORT not in text:
            fail("unsupported P2 behavioral-gate import surface")
        text = text.replace(OLD_IMPORT, NEW_IMPORT, 1)
        changed = True
    if NEW_PTY_GUARD not in text:
        if OLD_PTY_GUARD not in text:
            fail("unsupported P2 behavioral-gate PTY guard")
        text = text.replace(OLD_PTY_GUARD, NEW_PTY_GUARD, 1)
        changed = True
    if changed:
        target.write_text(text, encoding="utf-8", newline="\n")
        return ["tool/p2_behavioral_gate.py"]
    return []


def verify_source(text: str) -> None:
    compile(text, "p2_behavioral_gate.py", "exec")
    required = (
        "if os.name != 'nt':",
        "import pty",
        "import termios",
        "pty = None",
        "termios = None",
        "if os.name=='nt' or pty is None or termios is None:",
        "p2_technology_spike.py",
    )
    for marker in required:
        if marker not in text:
            fail(f"behavioral-gate portability marker missing: {marker}")
    first_line = next((line for line in text.splitlines() if line.startswith("import argparse")), "")
    if "pty" in first_line or "termios" in first_line:
        fail("Unix-only modules remain in the unconditional import list")


def simulate_windows_import(text: str) -> None:
    fake_os = types.ModuleType("os")
    fake_os.name = "nt"  # type: ignore[attr-defined]
    runtime = types.ModuleType("p2_reference_runtime")
    original_import = builtins.__import__
    imported_unix_only: list[str] = []

    def guarded_import(name: str, globals=None, locals=None, fromlist=(), level=0):
        if name == "os":
            return fake_os
        if name == "p2_reference_runtime":
            return runtime
        if name in {"pty", "termios"}:
            imported_unix_only.append(name)
            raise ModuleNotFoundError(f"blocked Windows-only probe import: {name}")
        return original_import(name, globals, locals, fromlist, level)

    custom_builtins = dict(vars(builtins))
    custom_builtins["__import__"] = guarded_import
    namespace = {
        "__name__": "v70r5_windows_import_probe",
        "__file__": "p2_behavioral_gate.py",
        "__builtins__": custom_builtins,
    }
    exec(compile(text, "p2_behavioral_gate.py", "exec"), namespace, namespace)
    if imported_unix_only:
        fail(f"Windows import probe attempted Unix-only modules: {imported_unix_only}")
    if namespace.get("pty") is not None or namespace.get("termios") is not None:
        fail("Windows import probe did not bind PTY modules to None")


def run_gate(project: pathlib.Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(project / "tool/p2_behavioral_gate.py"),
            "--project",
            str(project),
            "--fast-source-only",
        ],
        cwd=str(project),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode:
        fail(
            "portable fast-source behavioral gate failed\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--test", action="store_true")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    changed = patch(project)
    target = project / "tool/p2_behavioral_gate.py"
    text = target.read_text(encoding="utf-8")
    verify_source(text)
    simulate_windows_import(text)
    if args.test:
        run_gate(project)
    output = {
        "schemaVersion": "1.0.0",
        "resultType": "v70r5-p2-behavioral-gate-portability-patch-v1",
        "status": "passed",
        "changedFileCount": len(changed),
        "changedFiles": changed,
        "unconditionalUnixImportsRemoved": True,
        "windowsFastSourceImportCompatible": True,
        "posixPtyBehaviorRetained": True,
        "fastSourceGateExecuted": bool(args.test),
        "behavioralTestsSuppressed": False,
        "completionClaim": False,
    }
    payload = json.dumps(output, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        pathlib.Path(args.json_output).write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
