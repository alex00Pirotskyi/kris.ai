#!/usr/bin/env python3
"""Apply the semantic slash-command Understanding slice locally.

No remote Git operations are performed. The transformation is intentionally
anchored to source shapes present at recovered head dd2f46ba6df3fb25adc2c8c927e807147b8f16f2.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def git_head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return None


def transform_understanding(source: str) -> str:
    source = replace_once(
        source,
        """  const UnderstandingContext({\n    this.availableCapabilities = const <KristinCapability>[],\n    this.knownTargets = const <ChatTarget>[],\n    this.hasSelectedProject = false,\n  });\n\n  final List<KristinCapability> availableCapabilities;\n  final List<ChatTarget> knownTargets;\n  final bool hasSelectedProject;\n""",
        """  const UnderstandingContext({\n    this.availableCapabilities = const <KristinCapability>[],\n    this.knownTargets = const <ChatTarget>[],\n    this.hasSelectedProject = false,\n    this.semanticRequest,\n    this.lockedCapabilityId,\n  });\n\n  final List<KristinCapability> availableCapabilities;\n  final List<ChatTarget> knownTargets;\n  final bool hasSelectedProject;\n\n  /// Natural-language payload that still needs semantic interpretation after\n  /// deterministic command parsing. The slash command itself is not handed\n  /// to the model as something it may reinterpret.\n  final String? semanticRequest;\n\n  /// Capability fixed by an explicit slash command. A model may add semantic\n  /// structure beneath this capability, but can never replace it.\n  final String? lockedCapabilityId;\n""",
        "understanding context",
    )

    source = replace_once(
        source,
        """    final user = '''\nUSER REQUEST\n$normalized\n\nAVAILABLE CAPABILITIES\n${context.describeCapabilities()}\n\nKNOWN TARGETS\n${context.describeTargets()}\n\nA project is ${context.hasSelectedProject ? 'currently selected' : 'NOT currently selected'}.\n''';\n""",
        """    final semanticRequest = context.semanticRequest?.trim() ?? '';\n    final lockedCapabilityId = context.lockedCapabilityId?.trim() ?? '';\n    final user = '''\nORIGINAL USER REQUEST\n$normalized\n\n${semanticRequest.isEmpty ? '' : 'SEMANTIC PAYLOAD TO INTERPRET\\n$semanticRequest\\n'}\n${lockedCapabilityId.isEmpty ? '' : 'LOCKED COMMAND CAPABILITY\\n$lockedCapabilityId\\nThe explicit slash command already selected this top-level capability. Do not replace it with another capability.\\n'}\nAVAILABLE CAPABILITIES\n${context.describeCapabilities()}\n\nKNOWN TARGETS\n${context.describeTargets()}\n\nA project is ${context.hasSelectedProject ? 'currently selected' : 'NOT currently selected'}.\n''';\n""",
        "semantic model prompt",
    )

    source = replace_once(
        source,
        """    final capabilityHints = <String>[];\n    for (final id\n        in cleanList(proposal['capabilityHints'], 'capabilityHints')) {\n      final capability = context.capabilityById(id);\n      if (capability == null) {\n        rejections.add('capabilityHints: unknown capability \\\"$id\\\" ignored.');\n        continue;\n      }\n      capabilityHints.add(capability.id);\n    }\n\n    // Targets: a model asserting a target exists never makes it exist.\n""",
        """    final capabilityHints = <String>[];\n    final lockedCapabilityId = context.lockedCapabilityId?.trim() ?? '';\n    for (final id\n        in cleanList(proposal['capabilityHints'], 'capabilityHints')) {\n      final capability = context.capabilityById(id);\n      if (capability == null) {\n        rejections.add('capabilityHints: unknown capability \\\"$id\\\" ignored.');\n        continue;\n      }\n      if (lockedCapabilityId.isNotEmpty && id != lockedCapabilityId) {\n        rejections.add(\n          'capabilityHints: explicit command locks capability '\n          '\\\"$lockedCapabilityId\\\"; model hint \\\"$id\\\" ignored.',\n        );\n        continue;\n      }\n      capabilityHints.add(capability.id);\n    }\n    if (lockedCapabilityId.isNotEmpty) {\n      final locked = context.capabilityById(lockedCapabilityId);\n      if (locked == null) {\n        throw ProductException(\n          'understanding_locked_capability_missing',\n          'The explicit command capability is not present in the governed registry.',\n          details: <String, dynamic>{\n            'capabilityId': lockedCapabilityId,\n          },\n        );\n      }\n      if (!capabilityHints.contains(locked.id)) capabilityHints.add(locked.id);\n    }\n\n    // Targets: a model asserting a target exists never makes it exist.\n""",
        "locked capability validation",
    )

    source = replace_once(
        source,
        """        UnresolvedQuestion(question: item),\n""",
        """        UnresolvedQuestion(question: item, blocking: true),\n""",
        "model ambiguity blocking",
    )

    source = replace_once(
        source,
        """  bool warrantsModelUnderstanding(ChatInteractionDecision decision) {\n    if (model == null) return false;\n    if (decision.parsed.hasExplicitCommand) return false;\n    if (decision.kind == ChatInteractionKind.reference) return false;\n    if (decision.kind == ChatInteractionKind.informational) return false;\n    final capability = decision.capability;\n    if (capability == null) return false;\n    if (capability.understandingPolicy == ChatUnderstandingPolicy.never) {\n      return false;\n    }\n    return true;\n  }\n""",
        """  bool warrantsModelUnderstanding(ChatInteractionDecision decision) {\n    if (model == null) return false;\n    if (decision.kind == ChatInteractionKind.reference) return false;\n    if (decision.kind == ChatInteractionKind.informational) return false;\n    final capability = decision.capability;\n    if (capability == null) return false;\n    if (capability.understandingPolicy == ChatUnderstandingPolicy.never) {\n      return false;\n    }\n    if (decision.parsed.hasExplicitCommand) {\n      final semanticPayload = decision.parsed.arguments\n          .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')\n          .replaceAll(RegExp(r'\\s+'), ' ')\n          .trim();\n      if (semanticPayload.isEmpty) return false;\n\n      // Explicit commands lock the top-level capability deterministically.\n      // Only commands whose payload genuinely benefits from semantic\n      // structure spend a model call; `/run @project` stays deterministic.\n      return const <ChatExecutionRoute>{\n        ChatExecutionRoute.createProject,\n        ChatExecutionRoute.modifyProject,\n        ChatExecutionRoute.fixProject,\n        ChatExecutionRoute.researchSearch,\n      }.contains(capability.route);\n    }\n    return true;\n  }\n""",
        "semantic slash routing",
    )
    return source


def transform_kernel(source: str) -> str:
    return replace_once(
        source,
        """  UnderstandingContext get understandingContext => UnderstandingContext(\n        availableCapabilities: availableCapabilities,\n        knownTargets: knownTargets,\n        hasSelectedProject: project != null,\n      );\n""",
        """  UnderstandingContext get understandingContext => UnderstandingContext(\n        availableCapabilities: availableCapabilities,\n        knownTargets: knownTargets,\n        hasSelectedProject: project != null,\n        semanticRequest:\n            decision.parsed.hasExplicitCommand ? decision.parsed.arguments : null,\n        lockedCapabilityId:\n            decision.parsed.hasExplicitCommand ? decision.capability?.id : null,\n      );\n""",
        "kernel understanding context",
    )


TEST_SOURCE = r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/task_kernel/task_kernel.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';

void main() {
  final model = ModelIdentity(
    providerId: 'fixture',
    name: 'semantic-slash',
    digest: 'sha256:semantic-slash',
    discoveredAt: DateTime.utc(2026, 8, 30),
  );
  const compiler = ChatIntentCompiler();
  final targets = <ChatTarget>[
    const ChatTarget(
      id: 'project-a',
      displayName: 'project-a',
      type: ChatTargetType.project,
      aliases: <String>['project-a'],
    ),
  ];

  ModelBackedUnderstanding fixture(
    Map<String, dynamic> payload, {
    void Function(ModelGenerationRequest request)? capture,
  }) =>
      ModelBackedUnderstanding(
        generate: (request) async {
          capture?.call(request);
          final now = DateTime.now().toUtc();
          return ModelGenerationResult(
            text: jsonEncode(payload),
            identity: model,
            startedAt: now,
            firstTokenAt: now,
            completedAt: now,
          );
        },
      );

  test('free-text /fix payload gets semantic understanding while /run stays deterministic', () {
    final service = UnderstandingService(model: fixture(<String, dynamic>{}));
    final fix = compiler.compile(
      '/fix @project-a login crashes when the access token expires',
      knownTargets: targets,
    );
    final run = compiler.compile('/run @project-a', knownTargets: targets);

    expect(fix.capability?.id, 'agent.fix_project');
    expect(service.warrantsModelUnderstanding(fix), isTrue);
    expect(service.warrantsModelUnderstanding(run), isFalse);
  });

  test('explicit slash capability is locked against model replacement', () async {
    final decision = compiler.compile(
      '/fix @project-a login crashes when the access token expires',
      knownTargets: targets,
    );
    ModelGenerationRequest? captured;
    final service = UnderstandingService(
      model: fixture(
        <String, dynamic>{
          'objective': 'Repair login after token expiry',
          'capabilityHints': <String>['research.search'],
          'targets': <String>['project-a'],
          'successCriteria': <String>['Login recovers after token expiry'],
          'unresolvedQuestions': <String>['Should an expired token sign out or refresh automatically?'],
          'confidence': 0.86,
        },
        capture: (request) => captured = request,
      ),
    );
    final kernelContext = KernelRequestContext(
      decision: decision,
      project: ProjectRecord(
        id: 'project-a',
        name: 'project-a',
        rootPath: '/tmp/project-a',
        createdAt: DateTime.utc(2026, 8, 30),
        updatedAt: DateTime.utc(2026, 8, 30),
      ),
      model: model,
      knownTargets: targets,
    );

    final outcome = await service.understand(
      decision: decision,
      context: kernelContext.understandingContext,
      modelIdentity: model,
    );

    expect(outcome.path, UnderstandingPath.model);
    expect(outcome.specification.originalRequest, decision.parsed.originalText);
    expect(outcome.specification.capabilityHints, contains('agent.fix_project'));
    expect(outcome.specification.capabilityHints, isNot(contains('research.search')));
    expect(outcome.rejections.join(' '), contains('explicit command locks capability'));
    expect(outcome.specification.blockingQuestions, hasLength(1));
    expect(captured?.userPrompt, contains('LOCKED COMMAND CAPABILITY'));
    expect(captured?.userPrompt, contains('agent.fix_project'));
    expect(captured?.userPrompt, contains('login crashes when the access token expires'));
  });

  test('/create and /search with payloads warrant semantic understanding', () {
    final service = UnderstandingService(model: fixture(<String, dynamic>{}));
    expect(
      service.warrantsModelUnderstanding(
        compiler.compile('/create a small Flutter habit tracker with offline sync'),
      ),
      isTrue,
    );
    expect(
      service.warrantsModelUnderstanding(
        compiler.compile('/search current Flutter desktop packaging changes'),
      ),
      isTrue,
    );
  });
}
'''


def compute(root: Path):
    files = {
        root / "lib/product/task_kernel/task_understanding.dart": transform_understanding,
        root / "lib/product/task_kernel/task_kernel.dart": transform_kernel,
    }
    result = {}
    for path, fn in files.items():
        if not path.exists():
            raise RuntimeError(f"missing source file: {path}")
        before = path.read_text()
        after = fn(before)
        result[path] = (before, after)
    test_path = root / "test/product/task_kernel/semantic_slash_understanding_test.dart"
    before_test = test_path.read_text() if test_path.exists() else ""
    result[test_path] = (before_test, TEST_SOURCE)
    return result


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("repo")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--diff", action="store_true")
    p.add_argument("--allow-head-drift", action="store_true")
    args = p.parse_args()
    root = Path(args.repo).resolve()
    head = git_head(root)
    if head and head != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(f"refusing HEAD {head}; expected {EXPECTED_HEAD}")
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print("".join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f"a/{rel}", tofile=f"b/{rel}",
            )), end="")
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
