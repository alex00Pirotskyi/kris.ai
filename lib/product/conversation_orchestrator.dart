import 'dart:convert';

import 'chat_control_plane.dart';
import 'domain.dart';

enum ConversationIntentKind {
  conversation,
  buildNewProject,
  modifyProject,
  analyzeProject,
  investigateRun,
  research,
  other,
}

class ConversationIntent {
  const ConversationIntent({
    required this.kind,
    required this.needsClarification,
    required this.projectMayBeProvisioned,
    required this.suggestedProjectName,
  });

  final ConversationIntentKind kind;
  final bool needsClarification;
  final bool projectMayBeProvisioned;
  final String suggestedProjectName;
}

class ConversationStreamProjector {
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
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d;
}

class ConversationOrchestrator {
  const ConversationOrchestrator({
    this.intentCompiler = const ChatIntentCompiler(),
  });

  final ChatIntentCompiler intentCompiler;

  ConversationIntent classify(String request, CommandMode mode) {
    final normalized = request.trim();
    final decision = intentCompiler.compile(
      normalized,
      inferredMode: mode,
    );

    if (decision.isInformational) {
      return const ConversationIntent(
        kind: ConversationIntentKind.conversation,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
      );
    }

    if (!decision.isAction && isFailureInvestigationRequest(normalized)) {
      return const ConversationIntent(
        kind: ConversationIntentKind.investigateRun,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
      );
    }

    final capability = decision.capability;
    switch (capability?.id) {
      case 'search':
        return ConversationIntent(
          kind: ConversationIntentKind.research,
          needsClarification: decision.ambiguous,
          projectMayBeProvisioned: false,
          suggestedProjectName: '',
        );
      case 'analyze':
      case 'test':
      case 'verify':
      case 'diagnose':
        return ConversationIntent(
          kind: ConversationIntentKind.analyzeProject,
          needsClarification: decision.ambiguous,
          projectMayBeProvisioned: false,
          suggestedProjectName: '',
        );
      case 'build':
        return ConversationIntent(
          kind: ConversationIntentKind.buildNewProject,
          needsClarification: decision.ambiguous,
          projectMayBeProvisioned: true,
          suggestedProjectName: suggestProjectName(normalized),
        );
      case 'fix':
        return ConversationIntent(
          kind: ConversationIntentKind.modifyProject,
          needsClarification: decision.ambiguous,
          projectMayBeProvisioned: false,
          suggestedProjectName: suggestProjectName(normalized),
        );
      case 'run':
      case 'stop':
      case 'restart':
      case 'open':
      case 'connect':
      case 'use':
      case 'owner':
        return ConversationIntent(
          kind: ConversationIntentKind.other,
          needsClarification: decision.ambiguous,
          projectMayBeProvisioned: false,
          suggestedProjectName: suggestProjectName(normalized),
        );
    }

    if (isFailureInvestigationRequest(normalized)) {
      return const ConversationIntent(
        kind: ConversationIntentKind.investigateRun,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
      );
    }

    return ConversationIntent(
      kind: mode == CommandMode.analyze || mode == CommandMode.review
          ? ConversationIntentKind.analyzeProject
          : ConversationIntentKind.modifyProject,
      needsClarification: decision.ambiguous,
      projectMayBeProvisioned: false,
      suggestedProjectName: suggestProjectName(normalized),
    );
  }

  String suggestProjectName(String request) {
    var value = request
        .replaceAll(
            RegExp(r'\b(please|hey|kristin|can you|could you|i want you to)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'\b(build|create|make|develop|implement|me|a|an|the)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.isEmpty) return 'Kristin Project';
    final words = value.split(' ').take(5).toList();
    value = words.map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
    return value.length <= 54 ? value : value.substring(0, 54).trim();
  }
}
