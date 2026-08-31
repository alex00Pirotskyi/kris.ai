#!/usr/bin/env python3
"""Keep direct Research project-free when optional archive context disappears."""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


TEST = r'''import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct Research treats project archiving as optional enrichment', () {
    final source = File('lib/product/chat_action_dispatcher.dart').readAsStringSync();
    expect(source, contains('final project = await runtime.getProject(projectId);'));
    expect(source, contains('if (project == null) return;'));
    expect(source, contains('projectId: project.id'));
  });
}
'''


def transform(src: str) -> str:
    old = r'''  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    if (projectId == null) return;
    await runtime.knowledge.addResearchSearch(
      projectId: projectId,
      query: query,
      results: results,
      provider: 'duckduckgo',
    );
  }
'''
    new = r'''  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    if (projectId == null) return;
    // A project is archive/enrichment context only. It may disappear while
    // the network request is in flight; that must not retroactively make the
    // project-free Research result invalid or pretend the project still exists.
    final project = await runtime.getProject(projectId);
    if (project == null) return;
    await runtime.knowledge.addResearchSearch(
      projectId: project.id,
      query: query,
      results: results,
      provider: 'duckduckgo',
    );
  }
'''
    return rep(src, old, new, "direct research optional archive guard")


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    path = root / 'lib/product/chat_action_dispatcher.dart'
    if not path.exists():
        raise RuntimeError(f'missing source file: {path}')
    before = path.read_text()
    result = {path: (before, transform(before))}
    test = root / 'test/product/research_optional_archive_contract_test.dart'
    prior = test.read_text() if test.exists() else ''
    result[test] = (prior, TEST)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('repo')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--diff', action='store_true')
    ap.add_argument('--allow-head-drift', action='store_true')
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    current = head(root)
    if current != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(f'refusing HEAD {current}; expected {EXPECTED_HEAD}; review drift first')
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            if before == after: continue
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=str(path.relative_to(root)),
                tofile=str(path.relative_to(root)),
            )))
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
        print('Applied project-free direct Research optional archive guard.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
