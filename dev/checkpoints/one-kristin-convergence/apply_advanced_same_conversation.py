#!/usr/bin/env python3
"""Make Advanced, when opened from Kristin, project the same canonical session.

The advanced workspace keeps its project/runs/prompts/knowledge/logs tooling, but
its Chat area no longer becomes a second normal-user conversation owner. The
standalone ChatStudio construction remains compatible for any legacy entrypoint.
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
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def caller(src: str) -> str:
    src = rep(
        src,
        """        builder: (context) => ChatStudio(\n          runtime: runtime,\n          api: widget.api,\n          startupError: widget.startupError,\n          initialProjectId: selectedProjectId,\n          initialModelId: selectedModelId,\n        ),\n""",
        """        builder: (context) => ChatStudio(\n          runtime: runtime,\n          api: widget.api,\n          startupError: widget.startupError,\n          conversationSession: conversationSession,\n          initialProjectId: selectedProjectId,\n          initialModelId: selectedModelId,\n        ),\n""",
        "pass canonical session to Advanced",
    )
    return src


def studio(src: str) -> str:
    src = rep(
        src,
        """import 'models_research.dart';\nimport 'product_runtime.dart';\n""",
        """import 'models_research.dart';\nimport 'kristin_conversation_session.dart';\nimport 'product_runtime.dart';\n""",
        "session import",
    )
    src = rep(
        src,
        """    this.startupError,\n    this.initialProjectId,\n    this.initialModelId,\n  });\n""",
        """    this.startupError,\n    this.conversationSession,\n    this.initialProjectId,\n    this.initialModelId,\n  });\n""",
        "constructor session argument",
    )
    src = rep(
        src,
        """  final ProductRuntime runtime;\n  final GovernedApiServer api;\n  final String? startupError;\n\n  /// Project/model selected in the canonical Kristin chat at the moment\n""",
        """  final ProductRuntime runtime;\n  final GovernedApiServer api;\n  final String? startupError;\n\n  /// When Advanced is opened from the canonical Kristin surface this is\n  /// the SAME semantic conversation owner. Advanced may inspect and operate\n  /// project/run tooling, but it must not create a second normal-user Chat\n  /// transcript, task association, permission projection, or pending-question\n  /// owner. A null value preserves the legacy standalone Studio entrypoint.\n  final KristinConversationSession? conversationSession;\n\n  /// Project/model selected in the canonical Kristin chat at the moment\n""",
        "session field",
    )
    src = rep(
        src,
        """  ProductRuntime get runtime => widget.runtime;\n\n  bool get promptGenerationActive => promptGenerationCancellation != null;\n""",
        """  ProductRuntime get runtime => widget.runtime;\n  bool get projectsCanonicalKristin => widget.conversationSession != null;\n\n  bool get promptGenerationActive => promptGenerationCancellation != null;\n""",
        "projection mode getter",
    )
    src = rep(
        src,
        """    selectedProjectId = widget.initialProjectId;\n    selectedModelId = widget.initialModelId;\n""",
        """    selectedProjectId =\n        widget.conversationSession?.selectedProjectId ?? widget.initialProjectId;\n    selectedModelId =\n        widget.conversationSession?.selectedModelId ?? widget.initialModelId;\n""",
        "initial canonical selections",
    )
    src = rep(
        src,
        """  Future<void> _selectProject(String? projectId) async {\n    if (projectId == selectedProjectId) {\n      return;\n    }\n    setState(() {\n      selectedProjectId = projectId;\n""",
        """  Future<void> _selectProject(String? projectId) async {\n    if (projectId == selectedProjectId) {\n      return;\n    }\n    widget.conversationSession?.selectProject(projectId);\n    setState(() {\n      selectedProjectId = projectId;\n""",
        "project selection sync",
    )
    src = rep(
        src,
        """  Future<void> _selectRun(RunRecord run, {bool openChat = false}) async {\n    final projectId = run.command.contract.projectId;\n    setState(() {\n""",
        """  Future<void> _selectRun(RunRecord run, {bool openChat = false}) async {\n    final projectId = run.command.contract.projectId;\n    widget.conversationSession?.selectProject(projectId);\n    setState(() {\n""",
        "run project selection sync",
    )
    src = rep(
        src,
        """  void _newChat() {\n    setState(() {\n""",
        """  void _newChat() {\n    if (projectsCanonicalKristin) {\n      Navigator.of(context).pop();\n      return;\n    }\n    setState(() {\n""",
        "shared new-chat ownership",
    )
    src = rep(
        src,
        """  Future<void> _submitComposer() async {\n    final request = composerController.text.trim();\n""",
        """  Future<void> _submitComposer() async {\n    if (projectsCanonicalKristin) {\n      // The canonical Kristin composer is the only normal-user input owner.\n      Navigator.of(context).pop();\n      return;\n    }\n    final request = composerController.text.trim();\n""",
        "shared composer fails closed",
    )
    src = rep(
        src,
        """    if (result != null) {\n      if (projects.any((project) => project.id == result.projectId)) {\n        selectedProjectId = result.projectId;\n      }\n      if (models.any((model) => model.exactId == result.modelId)) {\n        selectedModelId = result.modelId;\n      }\n    }\n""",
        """    if (result != null) {\n      if (projects.any((project) => project.id == result.projectId)) {\n        selectedProjectId = result.projectId;\n        widget.conversationSession?.selectProject(result.projectId);\n      }\n      if (models.any((model) => model.exactId == result.modelId)) {\n        selectedModelId = result.modelId;\n        widget.conversationSession?.selectModel(result.modelId);\n      }\n    }\n""",
        "settings selection sync",
    )

    # Replace the advanced Chat page with a read/projection surface whenever
    # this Studio was opened from the canonical Kristin conversation.
    chat_anchor = """  Widget _chatPage() {\n    return Column(\n"""
    projection = """  Widget _canonicalKristinProjection() {\n    final session = widget.conversationSession!;\n    final run = session.currentRun;\n    return Column(\n      children: <Widget>[\n        Material(\n          color: Theme.of(context).colorScheme.surface,\n          child: Padding(\n            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),\n            child: Row(\n              children: <Widget>[\n                Expanded(\n                  child: Wrap(\n                    spacing: 8,\n                    runSpacing: 8,\n                    crossAxisAlignment: WrapCrossAlignment.center,\n                    children: <Widget>[\n                      _selectorChip(\n                        icon: Icons.folder_outlined,\n                        label: selectedProject?.name ?? 'Choose project',\n                        onTap: () => setState(() => area = _StudioArea.projects),\n                      ),\n                      _selectorChip(\n                        icon: Icons.memory_outlined,\n                        label: selectedModel?.name ?? 'Connect model',\n                        onTap: () => _openSettings(initialSection: 1),\n                      ),\n                    ],\n                  ),\n                ),\n                FilledButton.tonalIcon(\n                  key: const Key('advanced-back-to-kristin'),\n                  onPressed: () => Navigator.of(context).pop(),\n                  icon: const Icon(Icons.arrow_back),\n                  label: const Text('Back to Kristin'),\n                ),\n              ],\n            ),\n          ),\n        ),\n        const Divider(height: 1),\n        Expanded(\n          child: SelectionArea(\n            child: ListView(\n              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),\n              children: <Widget>[\n                Center(\n                  child: ConstrainedBox(\n                    constraints: const BoxConstraints(maxWidth: 900),\n                    child: Column(\n                      crossAxisAlignment: CrossAxisAlignment.stretch,\n                      children: <Widget>[\n                        if (session.messages.isEmpty)\n                          const Center(\n                            child: Text(\n                              'This is the same Kristin conversation. Return to Kristin to send a message.',\n                            ),\n                          ),\n                        for (final message in session.messages) ...<Widget>[\n                          _messageBubble(\n                            assistant: message.speaker !=\n                                KristinConversationSpeaker.user,\n                            child: Text(message.text),\n                          ),\n                          const SizedBox(height: 14),\n                        ],\n                        if (run != null)\n                          Card(\n                            child: ListTile(\n                              leading: _runStateIcon(run.state),\n                              title: Text(friendlyRunState(run.state)),\n                              subtitle: Text(run.command.contract.request),\n                              trailing: TextButton(\n                                onPressed: () {\n                                  setState(() {\n                                    selectedRunId = run.id;\n                                    currentRun = run;\n                                    prepared = run.command;\n                                    area = _StudioArea.runs;\n                                  });\n                                },\n                                child: const Text('Open run'),\n                              ),\n                            ),\n                          ),\n                        if (session.awaitingUserInput)\n                          Card(\n                            child: ListTile(\n                              leading: const Icon(Icons.question_answer_outlined),\n                              title: Text(\n                                session.deferredUserPrompt ??\n                                    'Kristin needs your input.',\n                              ),\n                              subtitle: const Text(\n                                'Return to Kristin to answer in the canonical conversation.',\n                              ),\n                            ),\n                          ),\n                      ],\n                    ),\n                  ),\n                ),\n              ],\n            ),\n          ),\n        ),\n      ],\n    );\n  }\n\n  Widget _chatPage() {\n    if (projectsCanonicalKristin) {\n      return _canonicalKristinProjection();\n    }\n    return Column(\n"""
    src = rep(src, chat_anchor, projection, "canonical advanced projection")

    # The navigation's primary CTA and floating CTA return to the canonical
    # Chat instead of creating/resetting a second conversation.
    src = rep(
        src,
        """            FilledButton.icon(\n              onPressed: () {\n                if (compact) {\n                  Navigator.of(context).pop();\n                }\n                _newChat();\n              },\n              icon: const Icon(Icons.add),\n              label: const Text('New chat'),\n            ),\n""",
        """            FilledButton.icon(\n              onPressed: () {\n                if (projectsCanonicalKristin) {\n                  Navigator.of(context).pop();\n                  return;\n                }\n                if (compact) {\n                  Navigator.of(context).pop();\n                }\n                _newChat();\n              },\n              icon: Icon(projectsCanonicalKristin ? Icons.arrow_back : Icons.add),\n              label: Text(projectsCanonicalKristin ? 'Back to Kristin' : 'New chat'),\n            ),\n""",
        "navigation canonical CTA",
    )
    src = rep(
        src,
        """      floatingActionButton: area == _StudioArea.chat\n          ? null\n          : FloatingActionButton.extended(\n              onPressed: _newChat,\n              icon: const Icon(Icons.add_comment_outlined),\n              label: const Text('New chat'),\n            ),\n""",
        """      floatingActionButton: area == _StudioArea.chat\n          ? null\n          : FloatingActionButton.extended(\n              onPressed: projectsCanonicalKristin\n                  ? () => Navigator.of(context).pop()\n                  : _newChat,\n              icon: Icon(projectsCanonicalKristin\n                  ? Icons.arrow_back\n                  : Icons.add_comment_outlined),\n              label: Text(projectsCanonicalKristin\n                  ? 'Back to Kristin'\n                  : 'New chat'),\n            ),\n""",
        "floating canonical CTA",
    )
    return src


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String caller;
  late String advanced;

  setUpAll(() {
    caller = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    advanced = File('lib/product/chat_studio.dart').readAsStringSync();
  });

  test('canonical Kristin session is passed into Advanced', () {
    expect(caller, contains('conversationSession: conversationSession'));
    expect(advanced, contains('final KristinConversationSession? conversationSession;'));
  });

  test('Advanced projects canonical transcript instead of owning a second composer', () {
    expect(advanced, contains('Widget _canonicalKristinProjection()'));
    expect(advanced, contains('for (final message in session.messages)'));
    expect(advanced, contains("if (projectsCanonicalKristin) {\n      return _canonicalKristinProjection();"));
    expect(advanced, contains("if (projectsCanonicalKristin) {\n      // The canonical Kristin composer is the only normal-user input owner."));
  });

  test('Advanced exposes an explicit Back to Kristin path', () {
    expect(advanced, contains("Key('advanced-back-to-kristin')"));
    expect(advanced, contains("label: const Text('Back to Kristin')"));
  });

  test('project and model selections can flow back into canonical session', () {
    expect(advanced, contains('widget.conversationSession?.selectProject(projectId);'));
    expect(advanced, contains('widget.conversationSession?.selectModel(result.modelId);'));
  });
}
'''


def compute(root: Path):
    mapping = {
        root / 'lib/product/chat_control_plane_studio_actions.dart': caller,
        root / 'lib/product/chat_studio.dart': studio,
    }
    out = {}
    for path, fn in mapping.items():
        if not path.exists():
            raise RuntimeError(f"missing {path}")
        before = path.read_text()
        out[path] = (before, fn(before))
    test_path = root / 'test/product/advanced_same_conversation_contract_test.dart'
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
        raise SystemExit(f"refusing HEAD {current}; expected {EXPECTED_HEAD}")
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
