from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'anchor mismatch {path}: expected 1 got {count}: {old[:100]!r}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/product/conversation_orchestrator.dart',
    "import 'domain.dart';\n",
    "import 'dart:convert';\n\nimport 'domain.dart';\n",
)

replace_once(
    'lib/product/conversation_orchestrator.dart',
    '''class ConversationOrchestrator {\n''',
    r'''class ConversationStreamProjector {
  const ConversationStreamProjector._();

  static const List<String> _userTextKeys = <String>[
    'summary',
    'answer',
    'message',
    'response',
  ];

  static String visibleText(String streamedProtocolText) {
    final text = streamedProtocolText.trimLeft();
    if (text.isEmpty) return '';
    if (!text.startsWith('{') && !text.startsWith('[')) return text;

    try {
      final decoded = jsonDecode(text);
      final complete = _findCompleteUserText(decoded);
      if (complete != null) return complete;
    } on FormatException {
      // A streaming JSON envelope is normally incomplete until the final token.
    }

    for (final key in _userTextKeys) {
      final value = _partialJsonString(text, key);
      if (value != null) return value;
    }
    return '';
  }

  static String? _findCompleteUserText(Object? value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      for (final key in _userTextKeys) {
        final candidate = map[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate;
        }
      }
      for (final nested in map.values) {
        final candidate = _findCompleteUserText(nested);
        if (candidate != null) return candidate;
      }
    } else if (value is List) {
      for (final nested in value) {
        final candidate = _findCompleteUserText(nested);
        if (candidate != null) return candidate;
      }
    }
    return null;
  }

  static String? _partialJsonString(String text, String key) {
    final marker = '"$key"';
    final markerIndex = text.indexOf(marker);
    if (markerIndex < 0) return null;
    var index = markerIndex + marker.length;
    while (index < text.length && _isWhitespace(text.codeUnitAt(index))) {
      index += 1;
    }
    if (index >= text.length || text[index] != ':') return null;
    index += 1;
    while (index < text.length && _isWhitespace(text.codeUnitAt(index))) {
      index += 1;
    }
    if (index >= text.length || text[index] != '"') return null;
    index += 1;

    final output = StringBuffer();
    while (index < text.length) {
      final current = text[index];
      if (current == '"') return output.toString();
      if (current != r'\') {
        output.write(current);
        index += 1;
        continue;
      }
      index += 1;
      if (index >= text.length) break;
      final escaped = text[index];
      switch (escaped) {
        case '"':
          output.write('"');
        case r'\':
          output.write(r'\');
        case '/':
          output.write('/');
        case 'b':
          output.write('\b');
        case 'f':
          output.write('\f');
        case 'n':
          output.write('\n');
        case 'r':
          output.write('\r');
        case 't':
          output.write('\t');
        case 'u':
          if (index + 4 >= text.length) return output.toString();
          final hex = text.substring(index + 1, index + 5);
          final codePoint = int.tryParse(hex, radix: 16);
          if (codePoint == null) return output.toString();
          output.writeCharCode(codePoint);
          index += 4;
        default:
          output.write(escaped);
      }
      index += 1;
    }
    return output.toString();
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0a || codeUnit == 0x0d;
}

class ConversationOrchestrator {
''',
)

replace_once(
    'lib/product/chat_studio.dart',
    '''  String liveAssistantText = '';\n  String liveAssistantStage = '';\n''',
    '''  String liveAssistantText = '';\n  String liveAssistantProtocolText = '';\n  String liveAssistantStage = '';\n''',
)

replace_once(
    'lib/product/chat_studio.dart',
    '''      liveAssistantText = '';\n      liveAssistantStage = '';\n      liveAssistantMessage = '';\n''',
    '''      liveAssistantText = '';\n      liveAssistantProtocolText = '';\n      liveAssistantStage = '';\n      liveAssistantMessage = '';\n''',
)

replace_once(
    'lib/product/chat_studio.dart',
    '''          case LiveRunSignalKind.modelTextDelta:\n            final delta = signal.data['delta']?.toString() ?? '';\n            final combined = '$liveAssistantText$delta';\n            liveAssistantText = combined.length <= 12000\n                ? combined\n                : combined.substring(combined.length - 12000);\n            liveAssistantStage = 'streaming';\n''',
    '''          case LiveRunSignalKind.modelTextDelta:\n            final delta = signal.data['delta']?.toString() ?? '';\n            final rawCombined = '$liveAssistantProtocolText$delta';\n            liveAssistantProtocolText = rawCombined.length <= 16000\n                ? rawCombined\n                : rawCombined.substring(rawCombined.length - 16000);\n            final conversational = currentRun?.command.contract.mode ==\n                    CommandMode.ask &&\n                isConversationalRequest(\n                  conversationUserRequest ??\n                      currentRun?.command.contract.request ??\n                      '',\n                );\n            liveAssistantText = conversational\n                ? ConversationStreamProjector.visibleText(\n                    liveAssistantProtocolText,\n                  )\n                : liveAssistantProtocolText;\n            liveAssistantStage = 'streaming';\n''',
)

replace_once(
    'lib/product/chat_studio.dart',
    '''      liveAssistantText = '';\n      liveAssistantStage = 'preflight';\n      liveAssistantMessage = 'Checking required capabilities before execution.';\n''',
    '''      liveAssistantText = '';\n      liveAssistantProtocolText = '';\n      liveAssistantStage = 'preflight';\n      liveAssistantMessage = 'Checking required capabilities before execution.';\n''',
)

replace_once(
    'lib/product/chat_studio.dart',
    '''        final fresh = await runtime.retryRun(run.id);\n        await runtime.approve(\n          runId: fresh.id,\n          scopes: Set<PermissionScope>.from(\n            fresh.command.contract.requiredPermissions,\n          ),\n        );\n        unawaited(runtime.execute(fresh.id));\n''',
    '''        final fresh = await runtime.retryRun(run.id);\n        await runtime.approve(\n          runId: fresh.id,\n          scopes: Set<PermissionScope>.from(\n            fresh.command.contract.requiredPermissions,\n          ),\n        );\n        currentRun = fresh;\n        selectedRunId = fresh.id;\n        selectedWorkItemId = fresh.items.firstOrNull?.item.id;\n        liveAssistantText = '';\n        liveAssistantProtocolText = '';\n        liveAssistantStage = 'preflight';\n        liveAssistantMessage = 'Checking required capabilities before execution.';\n        liveToolLabel = '';\n        liveToolOutput = '';\n        selectedRunLiveSignals = <LiveRunSignal>[];\n        selectedRunEvents = <EventEnvelope>[];\n        unawaited(runtime.execute(fresh.id));\n''',
)

replace_once(
    'lib/product/product_runtime.dart',
    '''          final provider = models.providerFor(model);\n          final result = await provider.generate(\n            ModelGenerationRequest(\n              identity: model,\n              systemPrompt:\n                  'You are a readiness probe. Return exactly {\\\\"status\\\\":\\\\"ready\\\\"}.',\n              userPrompt: 'Return readiness JSON now.',\n              commandId: newId('preflight_model'),\n              temperature: 0,\n              maxOutputTokens: 32,\n              firstTokenTimeout: const Duration(seconds: 45),\n              totalTimeout: const Duration(seconds: 90),\n            ),\n          );\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: result.text.trim().isNotEmpty,\n            required: requirement.required,\n            message: result.text.trim().isNotEmpty\n                ? '${model.name} is loaded and responding.'\n                : '${model.name} returned an empty readiness response.',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n            details: <String, dynamic>{\n              'model': model.toJson(),\n              'firstTokenLatencyMs': result.firstTokenLatency.inMilliseconds,\n            },\n          );\n''',
    '''          final provider = models.providerFor(model);\n          if (model.providerId == 'ollama') {\n            final discovered = await provider.discover().timeout(\n                  const Duration(seconds: 12),\n                );\n            final exact = discovered.where((candidate) {\n              if (candidate.name != model.name) return false;\n              if (model.digest.isEmpty || candidate.digest.isEmpty) return true;\n              return candidate.digest == model.digest;\n            }).firstOrNull;\n            stopwatch.stop();\n            return RunCapabilityProbeResult(\n              key: requirement.key,\n              label: requirement.label,\n              ok: exact != null,\n              required: requirement.required,\n              message: exact != null\n                  ? '${model.name} is installed and the Ollama service is reachable.'\n                  : '${model.name} is not available with the selected identity.',\n              durationMilliseconds: stopwatch.elapsedMilliseconds,\n              details: <String, dynamic>{\n                'model': model.toJson(),\n                'probe': 'discovery',\n              },\n            );\n          }\n          final result = await provider.generate(\n            ModelGenerationRequest(\n              identity: model,\n              systemPrompt:\n                  'You are a readiness probe. Return exactly {\\\\"status\\\\":\\\\"ready\\\\"}.',\n              userPrompt: 'Return readiness JSON now.',\n              commandId: newId('preflight_model'),\n              temperature: 0,\n              maxOutputTokens: 32,\n              firstTokenTimeout: const Duration(seconds: 45),\n              totalTimeout: const Duration(seconds: 90),\n            ),\n          );\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: result.text.trim().isNotEmpty,\n            required: requirement.required,\n            message: result.text.trim().isNotEmpty\n                ? '${model.name} is loaded and responding.'\n                : '${model.name} returned an empty readiness response.',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n            details: <String, dynamic>{\n              'model': model.toJson(),\n              'firstTokenLatencyMs': result.firstTokenLatency.inMilliseconds,\n            },\n          );\n''',
)

replace_once(
    'test/product/hf_runner_chat_convergence_test.dart',
    '''  test('underspecified build naturally requests clarification', () {\n''',
    r'''  test('conversation stream projector hides protocol JSON while streaming', () {
    expect(
      ConversationStreamProjector.visibleText(
        '{"protocolVersion":"1.0.0","action":"complete","summary":"Hel',
      ),
      'Hel',
    );
    expect(
      ConversationStreamProjector.visibleText(
        '{"action":"complete","summary":"Hello\\nthere"}',
      ),
      'Hello\nthere',
    );
    expect(
      ConversationStreamProjector.visibleText('Hello directly'),
      'Hello directly',
    );
  });

  test('underspecified build naturally requests clarification', () {
''',
)
