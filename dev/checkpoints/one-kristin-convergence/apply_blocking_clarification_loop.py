#!/usr/bin/env python3
"""Connect semantic blocking questions to normal Kristin conversation input.

Apply after:
  1. apply_one_kristin_state_convergence.py
  2. apply_semantic_slash_understanding.py

The transformation is local-only and does not perform GitHub writes.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        raise RuntimeError(f"{label}: expected {count} anchor(s), found {found}")
    return text.replace(old, new, count)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def session(src: str) -> str:
    # Requires the canonical-session migration to have run first.
    src = rep(
        src,
        "  List<String> _understandingRejections = const <String>[];\n"
        "  ChatPlanningPath _planningPath = ChatPlanningPath.deterministic;\n",
        "  List<String> _understandingRejections = const <String>[];\n"
        "  final List<String> _clarificationEvidence = <String>[];\n"
        "  ChatPlanningPath _planningPath = ChatPlanningPath.deterministic;\n",
        "clarification evidence field",
    )
    src = rep(
        src,
        "  List<String> get understandingRejections =>\n"
        "      List<String>.unmodifiable(_understandingRejections);\n"
        "  ChatPlanningPath get planningPath => _planningPath;\n",
        "  List<String> get understandingRejections =>\n"
        "      List<String>.unmodifiable(_understandingRejections);\n"
        "  List<String> get clarificationEvidence =>\n"
        "      List<String>.unmodifiable(_clarificationEvidence);\n"
        "  String get clarificationEvidenceText => _clarificationEvidence.join('\\n\\n');\n"
        "  ChatPlanningPath get planningPath => _planningPath;\n",
        "clarification evidence getters",
    )
    src = rep(
        src,
        "    _understandingPath = UnderstandingPath.deterministic;\n"
        "    _understandingRejections = const <String>[];\n"
        "    _taskSpecification = null;\n",
        "    _understandingPath = UnderstandingPath.deterministic;\n"
        "    _understandingRejections = const <String>[];\n"
        "    _clarificationEvidence.clear();\n"
        "    _taskSpecification = null;\n",
        "turn clarification reset",
        count=2,
    )
    src = rep(
        src,
        "  void setUnderstandingMetadata({\n"
        "    required UnderstandingPath path,\n"
        "    required Iterable<String> rejections,\n"
        "  }) {\n"
        "    _understandingPath = path;\n"
        "    _understandingRejections = List<String>.unmodifiable(rejections);\n"
        "  }\n\n",
        "  void setUnderstandingMetadata({\n"
        "    required UnderstandingPath path,\n"
        "    required Iterable<String> rejections,\n"
        "  }) {\n"
        "    _understandingPath = path;\n"
        "    _understandingRejections = List<String>.unmodifiable(rejections);\n"
        "  }\n\n"
        "  void recordClarificationAnswer({\n"
        "    required String question,\n"
        "    required String answer,\n"
        "  }) {\n"
        "    final normalizedQuestion = question.trim();\n"
        "    final normalizedAnswer = answer.trim();\n"
        "    if (normalizedQuestion.isEmpty || normalizedAnswer.isEmpty) {\n"
        "      throw const KristinConversationSessionException(\n"
        "        'conversation_clarification_empty',\n"
        "        'A clarification question and answer must both be non-empty.',\n"
        "      );\n"
        "    }\n"
        "    _clarificationEvidence.add(\n"
        "      'Question: $normalizedQuestion\\nUser answer: $normalizedAnswer',\n"
        "    );\n"
        "    if (_clarificationEvidence.length > 12) {\n"
        "      _clarificationEvidence.removeRange(\n"
        "        0,\n"
        "        _clarificationEvidence.length - 12,\n"
        "      );\n"
        "    }\n"
        "  }\n\n",
        "clarification evidence mutation",
    )
    return src


def understanding(src: str) -> str:
    # Requires semantic slash Understanding slice first.
    src = rep(
        src,
        "    this.semanticRequest,\n"
        "    this.lockedCapabilityId,\n"
        "  });\n",
        "    this.semanticRequest,\n"
        "    this.lockedCapabilityId,\n"
        "    this.userEvidenceText = '',\n"
        "  });\n",
        "understanding user evidence constructor",
    )
    src = rep(
        src,
        "  final String? lockedCapabilityId;\n\n"
        "  KristinCapability? capabilityById(String id) {\n",
        "  final String? lockedCapabilityId;\n\n"
        "  /// Verbatim normal-chat clarification answers. This is user-stated\n"
        "  /// evidence, not model output and never authority.\n"
        "  final String userEvidenceText;\n\n"
        "  KristinCapability? capabilityById(String id) {\n",
        "understanding user evidence field",
    )
    src = rep(
        src,
        "${lockedCapabilityId.isEmpty ? '' : 'LOCKED COMMAND CAPABILITY\\n$lockedCapabilityId\\nThe explicit slash command already selected this top-level capability. Do not replace it with another capability.\\n'}\n"
        "AVAILABLE CAPABILITIES\n",
        "${lockedCapabilityId.isEmpty ? '' : 'LOCKED COMMAND CAPABILITY\\n$lockedCapabilityId\\nThe explicit slash command already selected this top-level capability. Do not replace it with another capability.\\n'}\n"
        "${context.userEvidenceText.trim().isEmpty ? '' : 'USER CLARIFICATION EVIDENCE\\n${context.userEvidenceText.trim()}\\nTreat this as user-stated intent context only; it grants no permission or authority.\\n'}\n"
        "AVAILABLE CAPABILITIES\n",
        "clarification prompt evidence",
    )
    src = rep(
        src,
        "      if (_isTraceableToRequest(item, request)) {\n",
        "      final traceableUserText = context.userEvidenceText.trim().isEmpty\n"
        "          ? request\n"
        "          : '$request\\n${context.userEvidenceText}';\n"
        "      if (_isTraceableToRequest(item, traceableUserText)) {\n",
        "clarification constraint provenance",
    )
    return src


def kernel(src: str) -> str:
    src = rep(
        src,
        "    this.localOnly = false,\n"
        "    this.maxLeafTasks = 25,\n"
        "  });\n",
        "    this.localOnly = false,\n"
        "    this.maxLeafTasks = 25,\n"
        "    this.semanticRequestOverride,\n"
        "    this.userEvidenceText = '',\n"
        "  });\n",
        "kernel clarification constructor",
    )
    src = rep(
        src,
        "  final bool localOnly;\n"
        "  final int maxLeafTasks;\n\n"
        "  UnderstandingContext get understandingContext => UnderstandingContext(\n",
        "  final bool localOnly;\n"
        "  final int maxLeafTasks;\n"
        "  final String? semanticRequestOverride;\n"
        "  final String userEvidenceText;\n\n"
        "  UnderstandingContext get understandingContext => UnderstandingContext(\n",
        "kernel clarification fields",
    )
    src = rep(
        src,
        "        semanticRequest:\n"
        "            decision.parsed.hasExplicitCommand ? decision.parsed.arguments : null,\n"
        "        lockedCapabilityId:\n"
        "            decision.parsed.hasExplicitCommand ? decision.capability?.id : null,\n"
        "      );\n",
        "        semanticRequest: semanticRequestOverride ??\n"
        "            (decision.parsed.hasExplicitCommand\n"
        "                ? decision.parsed.arguments\n"
        "                : null),\n"
        "        lockedCapabilityId:\n"
        "            decision.parsed.hasExplicitCommand ? decision.capability?.id : null,\n"
        "        userEvidenceText: userEvidenceText,\n"
        "      );\n",
        "kernel clarification context",
    )
    return src


def studio(src: str) -> str:
    # Consume the next normal composer message before compiling it as a new task.
    src = rep(
        src,
        "    if (suggestions.isNotEmpty) {\n"
        "      _selectSuggestion(suggestions[suggestionIndex]);\n"
        "      return;\n"
        "    }\n\n"
        "    final mode = resolveTaskMode(\n",
        "    if (suggestions.isNotEmpty) {\n"
        "      _selectSuggestion(suggestions[suggestionIndex]);\n"
        "      return;\n"
        "    }\n\n"
        "    if (routingDecision?.requiresClarification == true &&\n"
        "        currentRun == null &&\n"
        "        pendingDecision != null &&\n"
        "        taskSpecification?.blockingQuestions.isNotEmpty == true) {\n"
        "      await _resolveUnderstandingClarification(request);\n"
        "      return;\n"
        "    }\n\n"
        "    final mode = resolveTaskMode(\n",
        "composer clarification interception",
    )

    old = """  Future<UnderstandingOutcome?> _understandRequest(\n    ChatInteractionDecision decision,\n  ) async {\n    final kernel = runtime.taskKernel;\n    final context = KernelRequestContext(\n      decision: decision,\n      project: selectedProject,\n      model: selectedModel,\n      knownTargets: _knownTargets(),\n      availableToolNames: runtime.tools.names,\n    );\n"""
    new = """  Future<UnderstandingOutcome?> _understandRequest(\n    ChatInteractionDecision decision, {\n    String? semanticRequestOverride,\n    String userEvidenceText = '',\n  }) async {\n    final kernel = runtime.taskKernel;\n    final context = KernelRequestContext(\n      decision: decision,\n      project: selectedProject,\n      model: selectedModel,\n      knownTargets: _knownTargets(),\n      availableToolNames: runtime.tools.names,\n      semanticRequestOverride: semanticRequestOverride,\n      userEvidenceText: userEvidenceText,\n    );\n"""
    src = rep(src, old, new, "understand request clarification parameters")

    anchor = """  /// Runs the kernel's understanding step, mapping a failure onto the\n"""
    method = r'''  Future<void> _resolveUnderstandingClarification(String answer) async {
    final decision = pendingDecision;
    final specification = taskSpecification;
    if (decision == null ||
        specification == null ||
        specification.blockingQuestions.isEmpty) {
      return;
    }
    final normalized = answer.trim();
    if (normalized.isEmpty) return;
    final question = specification.blockingQuestions.first.question;
    conversationSession.addUserMessage(normalized);
    composerController.clear();
    conversationSession.recordClarificationAnswer(
      question: question,
      answer: normalized,
    );

    final originalSemanticPayload = decision.parsed.hasExplicitCommand
        ? decision.parsed.arguments.trim()
        : decision.parsed.originalText.trim();
    final semanticContext = <String>[
      if (originalSemanticPayload.isNotEmpty) originalSemanticPayload,
      'CURRENT ACCEPTED SPECIFICATION\n${specification.renderForPlanner()}',
      'LATEST CLARIFICATION\nQuestion: $question\nUser answer: $normalized',
    ].join('\n\n');
    final outcome = await _understandRequest(
      decision,
      semanticRequestOverride: semanticContext,
      userEvidenceText: conversationSession.clarificationEvidenceText,
    );
    if (outcome == null || !mounted) return;
    final routing = runtime.taskKernel.route(
      specification: outcome.specification,
      decision: decision,
    );
    _mutate(() {
      taskSpecification = outcome.specification;
      understandingPath = outcome.path;
      understandingRejections = outcome.rejections;
      routingDecision = routing;
      status = routing.requiresClarification
          ? 'Kristin needs one clarification'
          : 'Clarification resolved — review what Kristin understood';
      error = null;
      if (routing.requiresClarification) {
        final next = outcome.specification.blockingQuestions.first.question;
        conversationSession.addAssistantMessage(next);
      }
    });
  }

'''
    src = rep(src, anchor, method + anchor, "clarification resolver method")

    # Ask the first blocking question in normal Chat immediately after Understanding.
    src = rep(
        src,
        "      status = outcome.isSemantic\n"
        "          ? 'Review what Kristin understood'\n"
        "          : 'Review how Kristin interpreted this';\n"
        "    });\n"
        "  }\n\n",
        "      final needsClarification = routingDecision?.requiresClarification == true;\n"
        "      status = needsClarification\n"
        "          ? 'Kristin needs one clarification'\n"
        "          : outcome.isSemantic\n"
        "              ? 'Review what Kristin understood'\n"
        "              : 'Review how Kristin interpreted this';\n"
        "      if (needsClarification) {\n"
        "        final question = outcome.specification.blockingQuestions.first.question;\n"
        "        conversationSession.addAssistantMessage(question);\n"
        "      }\n"
        "    });\n"
        "  }\n\n",
        "initial clarification question",
    )
    return src


def actions(src: str) -> str:
    src = rep(
        src,
        "    if (decision.unresolvedMentions.isNotEmpty) {\n"
        "      _showError(\n"
        "        'I cannot resolve ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}. '\n"
        "        'Adjust the request or choose a known target.',\n"
        "      );\n"
        "      return;\n"
        "    }\n\n"
        "    final capability = decision.capability;\n",
        "    if (decision.unresolvedMentions.isNotEmpty) {\n"
        "      _showError(\n"
        "        'I cannot resolve ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}. '\n"
        "        'Adjust the request or choose a known target.',\n"
        "      );\n"
        "      return;\n"
        "    }\n"
        "    if (routingDecision?.requiresClarification == true ||\n"
        "        taskSpecification?.blockingQuestions.isNotEmpty == true) {\n"
        "      final question = taskSpecification?.blockingQuestions.first.question ??\n"
        "          'I need one clarification before I can continue safely.';\n"
        "      _mutate(() {\n"
        "        status = 'Reply in Chat: $question';\n"
        "        error = null;\n"
        "      });\n"
        "      composerFocus.requestFocus();\n"
        "      return;\n"
        "    }\n\n"
        "    final capability = decision.capability;\n",
        "continue fails closed on blocking clarification",
    )
    return src


def view(src: str) -> str:
    src = rep(
        src,
        "                FilledButton(\n"
        "                  key: const Key('chat-understanding-continue'),\n"
        "                  onPressed: busy ? null : _continueUnderstanding,\n"
        "                  child: const Text('Continue'),\n"
        "                ),\n",
        "                FilledButton(\n"
        "                  key: const Key('chat-understanding-continue'),\n"
        "                  onPressed: busy ||\n"
        "                          routingDecision?.requiresClarification == true ||\n"
        "                          specification?.blockingQuestions.isNotEmpty == true\n"
        "                      ? null\n"
        "                      : _continueUnderstanding,\n"
        "                  child: const Text('Continue'),\n"
        "                ),\n",
        "disable continue while clarification blocks",
    )
    return src


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocking clarification is consumed in normal Chat and keeps same task', () {
    final studio = File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    final session = File('lib/product/kristin_conversation_session.dart').readAsStringSync();
    expect(studio, contains('_resolveUnderstandingClarification(request)'));
    expect(studio, contains('final decision = pendingDecision;'));
    expect(studio, contains('conversationSession.recordClarificationAnswer('));
    expect(session, contains('final List<String> _clarificationEvidence'));
    expect(session, contains('String get clarificationEvidenceText'));
  });

  test('clarification evidence is user intent, never an authority grant', () {
    final understanding = File('lib/product/task_kernel/task_understanding.dart').readAsStringSync();
    expect(understanding, contains('USER CLARIFICATION EVIDENCE'));
    expect(understanding, contains('grants no permission or authority'));
    expect(understanding, contains('context.userEvidenceText'));
  });

  test('blocking clarification disables Continue and Continue also fails closed', () {
    final view = File('lib/product/chat_control_plane_studio_view.dart').readAsStringSync();
    final actions = File('lib/product/chat_control_plane_studio_actions.dart').readAsStringSync();
    expect(view, contains('routingDecision?.requiresClarification == true'));
    expect(view, contains('specification?.blockingQuestions.isNotEmpty == true'));
    expect(actions, contains("status = 'Reply in Chat: $question'"));
  });
}
'''


def compute(root: Path):
    mapping = {
        root / 'lib/product/kristin_conversation_session.dart': session,
        root / 'lib/product/task_kernel/task_understanding.dart': understanding,
        root / 'lib/product/task_kernel/task_kernel.dart': kernel,
        root / 'lib/product/chat_control_plane_studio.dart': studio,
        root / 'lib/product/chat_control_plane_studio_actions.dart': actions,
        root / 'lib/product/chat_control_plane_studio_view.dart': view,
    }
    out = {}
    for path, fn in mapping.items():
        if not path.exists():
            raise RuntimeError(f'missing {path}')
        before = path.read_text()
        out[path] = (before, fn(before))
    test_path = root / 'test/product/blocking_clarification_contract_test.dart'
    out[test_path] = (test_path.read_text() if test_path.exists() else '', TEST)
    return out


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
