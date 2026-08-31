#!/usr/bin/env python3
"""Close the remaining direct permission-minting boundary on a real checkout.

The One-Kristin continuation contract requires product_runtime.dart to remain
an intent/approval orchestration layer: it may validate the owner's requested
command scopes, but it must not invoke the low-level PermissionService.grant()
primitive directly.  Keep the existing bounded grant semantics while exposing
an explicit approved-command entry point on PermissionService.

This is intentionally narrow, guarded, and idempotent.  It does not change the
test contract and it does not add any implicit authority to steering or
continuation runs.
"""
from __future__ import annotations

import argparse
import difflib
from pathlib import Path


RUNTIME = Path("lib/product/product_runtime.dart")
STORAGE = Path("lib/product/storage_security.dart")


def _replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def transform_runtime(text: str) -> str:
    old = "    final grant = await permissions.grant(\n"
    new = "    final grant = await permissions.grantApprovedCommand(\n"
    if new in text:
        if old in text:
            raise RuntimeError("runtime authority boundary: both old and new calls are present")
        return text
    return _replace_once(text, old, new, "runtime direct permission grant")


def transform_storage(text: str) -> str:
    marker = "  Future<PermissionGrant> grantApprovedCommand({\n"
    if marker in text:
        return text
    old = (
        "  final EntityRepository<PermissionGrant> repository;\n"
        "  final AuditChain audit;\n\n"
        "  Future<PermissionGrant> grant({\n"
    )
    new = (
        "  final EntityRepository<PermissionGrant> repository;\n"
        "  final AuditChain audit;\n\n"
        "  /// Issues the existing bounded command grant after the product layer has\n"
        "  /// validated that the owner approved exactly the permissions requested by\n"
        "  /// the prepared command contract. Keeping this semantic entry point here\n"
        "  /// prevents orchestration code from minting through the raw grant primitive.\n"
        "  Future<PermissionGrant> grantApprovedCommand({\n"
        "    required String projectId,\n"
        "    required String commandId,\n"
        "    required Set<PermissionScope> scopes,\n"
        "    required Duration validity,\n"
        "    required int uses,\n"
        "  }) =>\n"
        "      grant(\n"
        "        projectId: projectId,\n"
        "        commandId: commandId,\n"
        "        scopes: scopes,\n"
        "        validity: validity,\n"
        "        uses: uses,\n"
        "      );\n\n"
        "  Future<PermissionGrant> grant({\n"
    )
    return _replace_once(text, old, new, "approved-command permission boundary")


def _render_diff(path: Path, before: str, after: str) -> str:
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = args.repo.resolve()
    transforms = {
        RUNTIME: transform_runtime,
        STORAGE: transform_storage,
    }
    changed = False
    for relative, transform in transforms.items():
        path = root / relative
        if not path.is_file():
            raise RuntimeError(f"required source file is missing: {relative}")
        before = path.read_text(encoding="utf-8")
        after = transform(before)
        if after == before:
            continue
        changed = True
        if args.apply:
            path.write_text(after, encoding="utf-8")
        else:
            print(_render_diff(relative, before, after), end="")

    mode = "applied" if args.apply else "planned"
    print(f"authority boundary fixup {mode}; changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
