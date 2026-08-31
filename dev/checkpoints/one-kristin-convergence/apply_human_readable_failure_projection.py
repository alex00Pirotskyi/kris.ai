#!/usr/bin/env python3
"""Project friendly errors separately from inspectable redacted technical detail."""
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
  test('Chat separates friendly failure summary from redacted technical detail', () {
    final studio = File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    final view = File('lib/product/chat_control_plane_studio_view.dart').readAsStringSync();
    final actions = File('lib/product/chat_control_plane_studio_actions.dart').readAsStringSync();

    expect(studio, contains('String? technicalError;'));
    expect(studio, contains('ProductErrorNormalizer.userMessage(failure)'));
    expect(studio, contains("runtime.redactor.redact('$failure')"));
    expect(studio, contains('technicalError = null;'));
    expect(studio, contains('errorDetailsExpanded = false;'));
    expect(view, contains("tooltip: 'Error details'"));
    expect(view, contains('technicalError != null && errorDetailsExpanded'));
    expect(view, contains('SelectableText('));
    expect(actions, contains('technicalError = null'));
  });
}
'''


def transform_studio(src: str) -> str:
    src = rep(
        src,
        "  bool detailsExpanded = false;\n  String status = 'Kristin is ready';\n  String? error;\n",
        "  bool detailsExpanded = false;\n  bool errorDetailsExpanded = false;\n  String status = 'Kristin is ready';\n  String? error;\n  String? technicalError;\n",
        "technical error state",
    )
    src = rep(
        src,
        "        busy = true;\n        status = activity;\n        error = null;\n",
        "        busy = true;\n        status = activity;\n        error = null;\n        technicalError = null;\n        errorDetailsExpanded = false;\n",
        "new operation clears previous technical error",
    )
    old = r'''    } catch (failure) {
      _mutate(() {
        error = runtime.redactor.redact(
          ProductErrorNormalizer.userMessage(failure),
        );
        status = 'Kristin needs your help';
      });
      return null;
'''
    new = r'''    } catch (failure) {
      final friendly = runtime.redactor.redact(
        ProductErrorNormalizer.userMessage(failure),
      );
      final technical = runtime.redactor.redact('$failure').trim();
      _mutate(() {
        error = friendly;
        technicalError = technical.isEmpty || technical == friendly.trim()
            ? null
            : technical;
        errorDetailsExpanded = false;
        status = 'Kristin needs your help';
      });
      return null;
'''
    return rep(src, old, new, "perform failure detail split")


def transform_actions(src: str) -> str:
    src = rep(
        src,
        "      error = null;\n      status = 'New chat ready';\n",
        "      error = null;\n      technicalError = null;\n      errorDetailsExpanded = false;\n      status = 'New chat ready';\n",
        "new chat clears technical error",
    )
    old = r'''  void _showError(String message) {
    _mutate(() {
      error = message;
      status = 'Kristin needs your help';
    });
  }
'''
    new = r'''  void _showError(String message) {
    _mutate(() {
      error = message;
      technicalError = null;
      errorDetailsExpanded = false;
      status = 'Kristin needs your help';
    });
  }
'''
    return rep(src, old, new, "manual error remains friendly only")


def transform_view(src: str) -> str:
    old = r'''    return Material(
      color: failing ? colors.errorContainer : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: <Widget>[
            if ((busy || runExecuting) && !waitingForInput)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(failing ? Icons.error_outline : Icons.info_outline,
                  size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                startup ??
                    error ??
                    (waitingForInput
                        ? conversationSession.deferredUserPrompt ?? status
                        : status),
              ),
            ),
            if (error != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => _mutate(() => error = null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
'''
    new = r'''    return Material(
      color: failing ? colors.errorContainer : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                if ((busy || runExecuting) && !waitingForInput)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(failing ? Icons.error_outline : Icons.info_outline,
                      size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    startup ??
                        error ??
                        (waitingForInput
                            ? conversationSession.deferredUserPrompt ?? status
                            : status),
                  ),
                ),
                if (error != null && technicalError != null)
                  IconButton(
                    tooltip: 'Error details',
                    onPressed: () => _mutate(
                      () => errorDetailsExpanded = !errorDetailsExpanded,
                    ),
                    icon: Icon(
                      errorDetailsExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                if (error != null)
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => _mutate(() {
                      error = null;
                      technicalError = null;
                      errorDetailsExpanded = false;
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (technicalError != null && errorDetailsExpanded) ...<Widget>[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    technicalError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
'''
    return rep(src, old, new, "status strip technical details")


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    transforms = {
        root / 'lib/product/chat_control_plane_studio.dart': transform_studio,
        root / 'lib/product/chat_control_plane_studio_actions.dart': transform_actions,
        root / 'lib/product/chat_control_plane_studio_view.dart': transform_view,
    }
    out: dict[Path, tuple[str, str]] = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f'missing source file: {path}')
        before = path.read_text()
        out[path] = (before, fn(before))
    test = root / 'test/product/chat_failure_projection_contract_test.dart'
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
        print('Applied human-readable failure + inspectable technical detail projection.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
