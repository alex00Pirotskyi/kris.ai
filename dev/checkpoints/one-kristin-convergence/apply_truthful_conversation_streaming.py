#!/usr/bin/env python3
"""Route real provider deltas into the canonical Kristin conversation UI.

Ollama already emits actual generation fragments through ModelGenerationRequest
.onTextDelta. This slice makes ordinary Chat consume those fragments instead of
waiting for completion and animating afterwards. Providers that only report a
full response remain truthful: Chat shows a thinking state until their one final
delta/result arrives.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = 'dd2f46ba6df3fb25adc2c8c927e807147b8f16f2'


def rep(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        raise RuntimeError(f'{label}: expected {count} anchor(s), found {found}')
    return text.replace(old, new, count)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


def session(src: str) -> str:
    src = rep(
        src,
        "  String _liveAssistantProtocolText = '';\n"
        "  String _liveAssistantText = '';\n",
        "  // Transient projection for an ordinary, non-Runner assistant turn.\n"
        "  // The protocol buffer is only used to derive user-visible text; the\n"
        "  // completed transcript message remains the durable visible owner.\n"
        "  String _conversationAssistantProtocolText = '';\n"
        "  String _conversationAssistantText = '';\n\n"
        "  String _liveAssistantProtocolText = '';\n"
        "  String _liveAssistantText = '';\n",
        'conversation stream fields',
    )
    src = rep(
        src,
        "  String get liveAssistantProtocolText => _liveAssistantProtocolText;\n"
        "  String get liveAssistantText => _liveAssistantText;\n",
        "  String get conversationAssistantProtocolText =>\n"
        "      _conversationAssistantProtocolText;\n"
        "  String get conversationAssistantText => _conversationAssistantText;\n"
        "  bool get conversationResponseStreaming =>\n"
        "      _conversationAssistantProtocolText.isNotEmpty;\n\n"
        "  String get liveAssistantProtocolText => _liveAssistantProtocolText;\n"
        "  String get liveAssistantText => _liveAssistantText;\n",
        'conversation stream getters',
    )
    anchor = """  /// Begins a new governed objective in this conversation.\n"""
    methods = r'''  /// Starts a transient ordinary-Chat model response projection.
  ///
  /// This is not a Run and grants no execution authority. Real provider deltas
  /// may update it; a provider that does not stream simply leaves it empty
  /// while the UI truthfully says Kristin is thinking.
  void beginConversationResponse() {
    _conversationAssistantProtocolText = '';
    _conversationAssistantText = '';
  }

  void appendConversationAssistantDelta(String delta) {
    if (delta.isEmpty) return;
    _conversationAssistantProtocolText =
        '$_conversationAssistantProtocolText$delta';
    if (_conversationAssistantProtocolText.length > maxProtocolCharacters) {
      _conversationAssistantProtocolText = _conversationAssistantProtocolText
          .substring(_conversationAssistantProtocolText.length -
              maxProtocolCharacters);
    }
    _conversationAssistantText = ConversationStreamProjector.visibleText(
      _conversationAssistantProtocolText,
    );
  }

  KristinConversationMessage completeConversationResponse(String visibleText) {
    final message = addAssistantMessage(visibleText);
    clearConversationResponse();
    return message;
  }

  void clearConversationResponse() {
    _conversationAssistantProtocolText = '';
    _conversationAssistantText = '';
  }

'''
    src = rep(src, anchor, methods + anchor, 'conversation stream methods')

    src = rep(
        src,
        "    _awaitingPermission = false;\n"
        "    clearLiveExecution();\n",
        "    _awaitingPermission = false;\n"
        "    clearConversationResponse();\n"
        "    clearLiveExecution();\n",
        'turn stream reset',
        count=2,
    )
    return src


def actions(src: str) -> str:
    old_request = """              firstTokenTimeout: const Duration(minutes: 2),\n              totalTimeout: const Duration(minutes: 4),\n            ),\n"""
    new_request = """              firstTokenTimeout: const Duration(minutes: 2),\n              totalTimeout: const Duration(minutes: 4),\n              onTextDelta: (delta) {\n                if (!mounted) return;\n                _mutate(() {\n                  conversationSession.appendConversationAssistantDelta(delta);\n                  status = conversationSession.conversationAssistantText\n                          .trim()\n                          .isEmpty\n                      ? 'Kristin is thinking'\n                      : 'Kristin is answering';\n                });\n              },\n            ),\n"""
    src = rep(src, old_request, new_request, 'informational provider delta callback')

    src = rep(
        src,
        "    final activeModel = model;\n"
        "    final result = await _perform<ModelGenerationResult>(\n"
        "      'Answering',\n",
        "    final activeModel = model;\n"
        "    _mutate(() {\n"
        "      conversationSession.beginConversationResponse();\n"
        "      status = 'Kristin is thinking';\n"
        "    });\n"
        "    final result = await _perform<ModelGenerationResult>(\n"
        "      'Kristin is thinking',\n",
        'conversation response begin',
    )

    src = rep(
        src,
        "    if (result == null || !mounted) return;\n\n"
        "    var visible = ConversationStreamProjector.visibleText(result.text).trim();\n",
        "    if (result == null || !mounted) {\n"
        "      if (mounted) {\n"
        "        _mutate(conversationSession.clearConversationResponse);\n"
        "      }\n"
        "      return;\n"
        "    }\n\n"
        "    var visible = ConversationStreamProjector.visibleText(result.text).trim();\n",
        'conversation response failure cleanup',
    )

    src = rep(
        src,
        "    _mutate(() {\n"
        "      conversationSession.addAssistantMessage(visible);\n"
        "      status = 'Kristin is ready';\n"
        "    });\n"
        "  }\n\n"
        "  /// Answers a target-only message",
        "    _mutate(() {\n"
        "      conversationSession.completeConversationResponse(visible);\n"
        "      status = 'Kristin is ready';\n"
        "    });\n"
        "  }\n\n"
        "  /// Answers a target-only message",
        'conversation response completion',
    )
    return src


def view(src: str) -> str:
    src = rep(
        src,
        "    for (final line in transcript) {\n"
        "      children.add(_messageBubble(line));\n"
        "      children.add(const SizedBox(height: 14));\n"
        "    }\n"
        "    switch (state) {\n",
        "    for (final line in transcript) {\n"
        "      children.add(_messageBubble(line));\n"
        "      children.add(const SizedBox(height: 14));\n"
        "    }\n"
        "    final streamingText = conversationSession.conversationAssistantText.trim();\n"
        "    if (streamingText.isNotEmpty) {\n"
        "      children.add(_streamingAssistantBubble(streamingText));\n"
        "      children.add(const SizedBox(height: 14));\n"
        "    }\n"
        "    switch (state) {\n",
        'render conversation provider deltas',
    )
    anchor = """  /// Renders the compiled work items grouped by their canonical phase,\n"""
    helper = r'''  Widget _streamingAssistantBubble(String text) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          backgroundColor: colors.primaryContainer,
          child: Icon(
            Icons.auto_awesome,
            size: 16,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: SelectableText(text),
          ),
        ),
      ],
    );
  }

'''
    return rep(src, anchor, helper + anchor, 'streaming assistant bubble')


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';

void main() {
  test('ordinary conversation projects real protocol deltas then commits once', () {
    final session = KristinConversationSession();
    session.beginConversationResponse();
    session.appendConversationAssistantDelta('{"answer":"Hel');
    session.appendConversationAssistantDelta('lo"}');
    expect(session.conversationAssistantText, 'Hello');
    expect(session.messages, isEmpty);

    session.completeConversationResponse('Hello');
    expect(session.conversationAssistantText, isEmpty);
    expect(session.conversationAssistantProtocolText, isEmpty);
    expect(session.messages.single.text, 'Hello');
  });

  test('Chat passes provider deltas directly and contains no character animation loop', () {
    final actions = File('lib/product/chat_control_plane_studio_actions.dart').readAsStringSync();
    expect(actions, contains('onTextDelta: (delta)'));
    expect(actions, contains('appendConversationAssistantDelta(delta)'));
    expect(actions, isNot(contains('Future.delayed(const Duration(milliseconds:')));
  });

  test('non-streaming provider is represented as thinking until completion', () {
    final actions = File('lib/product/chat_control_plane_studio_actions.dart').readAsStringSync();
    expect(actions, contains("status = 'Kristin is thinking'"));
    expect(actions, contains('completeConversationResponse(visible)'));
  });
}
'''


def compute(root: Path):
    mapping = {
        root / 'lib/product/kristin_conversation_session.dart': session,
        root / 'lib/product/chat_control_plane_studio_actions.dart': actions,
        root / 'lib/product/chat_control_plane_studio_view.dart': view,
    }
    out = {}
    for path, fn in mapping.items():
        if not path.exists():
            raise RuntimeError(f'missing {path}')
        before = path.read_text()
        out[path] = (before, fn(before))
    test = root / 'test/product/truthful_conversation_streaming_test.dart'
    out[test] = (test.read_text() if test.exists() else '', TEST)
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
