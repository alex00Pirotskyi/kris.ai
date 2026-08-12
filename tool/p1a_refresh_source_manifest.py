#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import subprocess
import sys


def canonical_source_bytes(data: bytes) -> bytes:
    """Match the cross-platform source identity enforced by the exact gate."""
    if b"\0" in data:
        return data
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    return data.replace(b"\r\n", b"\n")


root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
policy_path = root / "tool/source_tree_policy.py"
if not policy_path.is_file():
    raise SystemExit("source_tree_policy.py required from final P1")
spec = importlib.util.spec_from_file_location("p1a_source_policy", policy_path)
if spec is None or spec.loader is None:
    raise SystemExit("cannot load source-tree policy")
policy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = policy
spec.loader.exec_module(policy)
raw = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
)
paths = sorted(
    {
        value.decode("utf-8", errors="surrogateescape").replace("\\", "/")
        for value in raw.split(b"\0")
        if value
    }
)
lines: list[str] = []
for relative in paths:
    if relative == "SOURCE_MANIFEST.sha256" or policy.is_generated_path(relative):
        continue
    path = root / relative
    if path.is_file():
        digest = hashlib.sha256(canonical_source_bytes(path.read_bytes())).hexdigest()
        lines.append(f"{digest}  {relative}")
(root / "SOURCE_MANIFEST.sha256").write_text(
    "\n".join(lines) + "\n", encoding="utf-8", newline="\n"
)
print(f"P1A source manifest entries: {len(lines)}")
