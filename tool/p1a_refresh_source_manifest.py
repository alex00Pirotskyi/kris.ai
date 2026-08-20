#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import shutil
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


def _p4_patched_texts(root: pathlib.Path) -> tuple[pathlib.Path, str, str, pathlib.Path, str, str]:
    runtime = root / "lib/product/research/research_runtime.dart"
    runtime_original = runtime.read_text(encoding="utf-8")
    old_sort = """        copy.sort((a, b) {
          final result = '${a[field] ?? ''}'.compareTo('${b[field] ?? ''}');
          return descending ? -result : result;
        });
"""
    new_sort = """        copy.sort((a, b) {
          final left = a[field]?.toString() ?? '';
          final right = b[field]?.toString() ?? '';
          final result = left.compareTo(right);
          return descending ? -result : result;
        });
"""
    if runtime_original.count(old_sort) != 1:
        raise SystemExit("dataset sort compatibility target must occur exactly once")
    runtime_patched = runtime_original.replace(old_sort, new_sort, 1)

    contract = root / "test/product/source_contract_test.dart"
    contract_original = contract.read_text(encoding="utf-8")
    additions = [
        "lib/product/research/research_authority.dart",
        "lib/product/research/research_browser_adapter.dart",
        "lib/product/research/research_runtime.dart",
        "lib/product/research/research_workspace.dart",
    ]
    already = [item for item in additions if f"        '{item}'," in contract_original]
    if already:
        raise SystemExit(f"P4 source inventory already contains: {already}")
    anchor = "        'lib/product/protocol_types.dart',\n"
    if contract_original.count(anchor) != 1:
        raise SystemExit("source inventory anchor must occur exactly once")
    block = "".join(f"        '{item}',\n" for item in additions)
    contract_patched = contract_original.replace(anchor, anchor + block, 1)
    return runtime, runtime_original, runtime_patched, contract, contract_original, contract_patched


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

runtime, runtime_original, runtime_patched, contract, contract_original, contract_patched = _p4_patched_texts(root)
runtime.write_text(runtime_patched, encoding="utf-8", newline="\n")
contract.write_text(contract_patched, encoding="utf-8", newline="\n")
try:
    artifact_root_raw = os.environ.get("RUNNER_TEMP")
    if artifact_root_raw:
        artifact_root = pathlib.Path(artifact_root_raw) / "p4-001-manifest" / "p4-patched-files"
        runtime_target = artifact_root / "lib/product/research/research_runtime.dart"
        contract_target = artifact_root / "test/product/source_contract_test.dart"
        runtime_target.parent.mkdir(parents=True, exist_ok=True)
        contract_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(runtime, runtime_target)
        shutil.copy2(contract, contract_target)

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
finally:
    runtime.write_text(runtime_original, encoding="utf-8", newline="\n")
    contract.write_text(contract_original, encoding="utf-8", newline="\n")

print(f"P1A source manifest entries: {len(lines)}")
