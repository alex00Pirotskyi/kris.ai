#!/usr/bin/env python3
"""Make @target resolution collision-safe and capability-aware.

The existing compiler resolves the first matching target. That makes provider
ordering semantic and can route a command to the wrong entity when project,
model, provider, or workspace aliases collide. This patch gathers every match,
filters by an explicit command's accepted target types, and resolves only when
exactly one candidate remains.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = 'dd2f46ba6df3fb25adc2c8c927e807147b8f16f2'


def rep(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f'{label}: expected 1 anchor, found {n}')
    return text.replace(old, new, 1)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def compiler(src: str) -> str:
    old = """    final parsed = parser.parse(input);\n    final targets = <ChatTarget>[];\n    final unresolved = <String>[];\n    for (final mention in parsed.mentions) {\n      ChatTarget? resolved;\n      for (final target in knownTargets) {\n        if (target.matches(mention)) {\n          resolved = target;\n          break;\n        }\n      }\n      if (resolved != null) {\n        targets.add(resolved);\n      } else if (registry.byMention(mention) == null) {\n        unresolved.add(mention);\n      }\n    }\n\n    if (parsed.hasExplicitCommand) {\n      final capability = registry.bySlash(parsed.commandToken);\n"""
    new = """    final parsed = parser.parse(input);\n    final explicitCapability = parsed.hasExplicitCommand\n        ? registry.bySlash(parsed.commandToken)\n        : null;\n    final targets = <ChatTarget>[];\n    final unresolved = <String>[];\n    for (final mention in parsed.mentions) {\n      final matches = knownTargets.where((target) {\n        if (!target.matches(mention)) return false;\n        // An explicit slash command already fixed the capability. A matching\n        // target of a type that capability cannot consume is not a valid\n        // resolution candidate. This is filtering, not authority.\n        if (explicitCapability != null &&\n            !explicitCapability.acceptsTarget(target.type)) {\n          return false;\n        }\n        return true;\n      }).toList(growable: false);\n      if (matches.length == 1) {\n        targets.add(matches.single);\n      } else if (matches.length > 1) {\n        // Never let provider ordering choose meaning. The normal structured\n        // ambiguity path asks the user to disambiguate instead.\n        unresolved.add(mention);\n      } else if (registry.byMention(mention) == null) {\n        unresolved.add(mention);\n      }\n    }\n\n    if (parsed.hasExplicitCommand) {\n      final capability = explicitCapability;\n"""
    return rep(src, old, new, 'collision-safe mention resolution')


TEST = r'''import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';

void main() {
  const compiler = ChatIntentCompiler();
  const project = ChatTarget(
    id: 'project-alpha',
    type: ChatTargetType.project,
    displayName: 'Alpha',
    aliases: <String>['alpha'],
  );
  const model = ChatTarget(
    id: 'provider/alpha',
    type: ChatTargetType.model,
    displayName: 'Alpha',
    aliases: <String>['alpha'],
  );

  test('bare colliding alias is ambiguous instead of first-provider-wins', () {
    final result = compiler.compile(
      '@alpha',
      knownTargets: const <ChatTarget>[project, model],
    );
    expect(result.targets, isEmpty);
    expect(result.unresolvedMentions, contains('alpha'));
    expect(result.ambiguous, isTrue);
  });

  test('/run filters collision candidates to project targets', () {
    final result = compiler.compile(
      '/run @alpha',
      knownTargets: const <ChatTarget>[model, project],
    );
    expect(result.capability?.id, 'project.run');
    expect(result.targets.single.id, project.id);
    expect(result.unresolvedMentions, isEmpty);
  });

  test('/use filters collision candidates to model/provider targets', () {
    final result = compiler.compile(
      '/use @alpha',
      knownTargets: const <ChatTarget>[project, model],
    );
    expect(result.capability?.id, 'model.select');
    expect(result.targets.single.id, model.id);
    expect(result.unresolvedMentions, isEmpty);
  });

  test('same-type collisions still require clarification', () {
    const otherProject = ChatTarget(
      id: 'project-alpha-2',
      type: ChatTargetType.project,
      displayName: 'Alpha Two',
      aliases: <String>['alpha'],
    );
    final result = compiler.compile(
      '/run @alpha',
      knownTargets: const <ChatTarget>[project, otherProject],
    );
    expect(result.targets, isEmpty);
    expect(result.unresolvedMentions, contains('alpha'));
    expect(result.ambiguous, isTrue);
  });
}
'''


def compute(root: Path):
    path = root / 'lib/product/chat_control_plane.dart'
    if not path.exists():
        raise RuntimeError(f'missing {path}')
    before = path.read_text()
    test = root / 'test/product/chat_target_collision_test.dart'
    return {
        path: (before, compiler(before)),
        test: (test.read_text() if test.exists() else '', TEST),
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('repo')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--diff', action='store_true')
    p.add_argument('--allow-head-drift', action='store_true')
    a = p.parse_args()
    root = Path(a.repo).resolve()
    current = head(root)
    if current and current != EXPECTED_HEAD and not a.allow_head_drift:
        raise SystemExit(f'refusing HEAD {current}; expected {EXPECTED_HEAD}')
    changes = compute(root)
    if a.diff or not a.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f'a/{rel}', tofile=f'b/{rel}',
            )), end='')
    if a.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
