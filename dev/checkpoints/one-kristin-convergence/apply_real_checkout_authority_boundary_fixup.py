#!/usr/bin/env python3
"""Reconcile the overlapping continuation/authority source contracts.

The dedicated authority-convergence contract intentionally requires ordinary
run approval to retain its explicit, exact-scope PermissionService.grant()
path.  The steering continuation contract must therefore prove that *the
continuation materialization path* does not mint authority, rather than banning
that unrelated explicit approval path from the entire ProductRuntime source.

This compatibility fixup narrows only that source assertion.  It does not
weaken the continuation invariant and does not modify production authority
behavior.
"""
from __future__ import annotations

import argparse
import difflib
from pathlib import Path


TARGET = Path("test/product/steering_scope_continuation_contract_test.dart")


def _replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    marker = "    final continuationStart = runtime.indexOf(\n"
    if marker in text:
        return text
    old = """  test('continuation never inherits authority implicitly', () {
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('requiredPermissions'));
    expect(runtime, isNot(contains('permissions.grant(')));
    expect(steering, contains('continuationRunId'));
  });
"""
    new = """  test('continuation never inherits authority implicitly', () {
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('requiredPermissions'));
    final continuationStart = runtime.indexOf(
      'Future<void> _materializePendingSteeringContinuation(RunRecord source) async {',
    );
    final continuationEnd = runtime.indexOf(
      '\\n  Future<PromptStudioDraft> generatePromptDraft({',
      continuationStart,
    );
    expect(continuationStart, greaterThanOrEqualTo(0));
    expect(continuationEnd, greaterThan(continuationStart));
    final continuationSource = runtime.substring(
      continuationStart,
      continuationEnd,
    );
    expect(continuationSource, isNot(contains('permissions.grant(')));
    expect(steering, contains('continuationRunId'));
  });
"""
    return _replace_once(text, old, new, "continuation authority assertion")


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
    path = root / TARGET
    if not path.is_file():
        raise RuntimeError(f"required generated contract test is missing: {TARGET}")
    before = path.read_text(encoding="utf-8")
    after = transform(before)
    changed = after != before
    if changed:
        if args.apply:
            path.write_text(after, encoding="utf-8")
        else:
            print(_render_diff(TARGET, before, after), end="")
    mode = "applied" if args.apply else "planned"
    print(f"continuation authority contract reconciliation {mode}; changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
