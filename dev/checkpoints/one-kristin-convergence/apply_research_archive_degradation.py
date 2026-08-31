#!/usr/bin/env python3
"""Make optional Research archiving fail-open for the answer, with audit evidence.

Network retrieval/fetch/synthesis remain authoritative for Research success.
Project knowledge archiving is optional enrichment and must not retroactively
invalidate grounded results when the archive store is unavailable.
"""
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
  test('optional Research archive failure does not invalidate grounded results', () {
    final dispatcher = File('lib/product/chat_action_dispatcher.dart').readAsStringSync();
    final executor = File(
      'lib/product/task_kernel/research_task_family_executor.dart',
    ).readAsStringSync();

    expect(dispatcher, contains("'research.optional_archive_failed'"));
    expect(dispatcher, contains("'answerPreserved': true"));
    expect(dispatcher, contains('runtime.redactor.redact'));

    expect(executor, contains("'task_family.research_archive_failed'"));
    expect(executor, contains("'warning': 'optional_archive_failed'"));
    expect(executor, contains("'answerPreserved': true"));
    expect(executor, isNot(contains("evidence.add(warning)")));
  });
}
'''


def transform_dispatcher(src: str) -> str:
    src = rep(
        src,
        "import 'capability_doctor.dart';\n",
        "import 'capability_doctor.dart';\nimport 'crypto_utils.dart';\n",
        "dispatcher crypto import",
    )
    old = r'''    await runtime.knowledge.addResearchSearch(
      projectId: project.id,
      query: query,
      results: results,
      provider: 'duckduckgo',
    );
'''
    new = r'''    try {
      await runtime.knowledge.addResearchSearch(
        projectId: project.id,
        query: query,
        results: results,
        provider: 'duckduckgo',
      );
    } catch (failure) {
      // Archiving is optional enrichment. Preserve the grounded web result and
      // record the storage failure for inspection instead of turning Research
      // itself into a failure.
      await runtime.audit.append(
        'research.optional_archive_failed',
        project.id,
        <String, dynamic>{
          'projectId': project.id,
          'queryHash': Sha256.text(query),
          'resultCount': results.length,
          'error': runtime.redactor.redact('$failure'),
          'answerPreserved': true,
        },
      );
    }
'''
    return rep(src, old, new, "direct research archive degradation")


def transform_executor(src: str) -> str:
    src = rep(
        src,
        "import '../domain.dart';\n",
        "import '../crypto_utils.dart';\nimport '../domain.dart';\n",
        "research executor crypto import",
    )
    old = r'''        if (archive != null) {
          await archive(subject.isEmpty ? request : subject, results);
        }
'''
    new = r'''        if (archive != null) {
          final archiveQuery = subject.isEmpty ? request : subject;
          try {
            await archive(archiveQuery, results);
          } catch (failure) {
            // Optional project knowledge enrichment must never erase valid
            // network evidence. Persist a warning on the task-family execution
            // and audit only redaction-safe structural diagnostics.
            await audit.append(
              'task_family.research_archive_failed',
              execution.id,
              <String, dynamic>{
                'executionId': execution.id,
                'projectId': execution.projectId,
                'queryHash': Sha256.text(archiveQuery),
                'resultCount': results.length,
                'failureType': failure.runtimeType.toString(),
                'warning': 'optional_archive_failed',
                'answerPreserved': true,
              },
            );
            await events.publish(
              'task_family.research_archive_failed',
              execution.id,
              <String, dynamic>{
                'executionId': execution.id,
                'projectId': execution.projectId,
                'queryHash': Sha256.text(archiveQuery),
                'warning': 'optional_archive_failed',
                'answerPreserved': true,
              },
            );
          }
        }
'''
    return rep(src, old, new, "graph research archive degradation")


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    transforms = {
        root / 'lib/product/chat_action_dispatcher.dart': transform_dispatcher,
        root / 'lib/product/task_kernel/research_task_family_executor.dart': transform_executor,
    }
    out: dict[Path, tuple[str, str]] = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f'missing source file: {path}')
        before = path.read_text()
        out[path] = (before, fn(before))
    test = root / 'test/product/research_archive_degradation_contract_test.dart'
    before = test.read_text() if test.exists() else ''
    out[test] = (before, TEST)
    return out


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
        print('Applied optional Research archive degradation slice.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
