import 'dart:convert';

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
  const ConversationOrchestrator();

  ConversationIntent classify(String request, CommandMode mode) {
    final normalized = request.trim();
    final lower = normalized.toLowerCase();
    if (isConversationalRequest(normalized)) {
      return const ConversationIntent(
        kind: ConversationIntentKind.conversation,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
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
    if (mode == CommandMode.analyze || mode == CommandMode.review) {
      return const ConversationIntent(
        kind: ConversationIntentKind.analyzeProject,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
      );
    }
    if (RegExp(r'\b(research|latest|current|look up|search the web)\b')
        .hasMatch(lower)) {
      return const ConversationIntent(
        kind: ConversationIntentKind.research,
        needsClarification: false,
        projectMayBeProvisioned: false,
        suggestedProjectName: '',
      );
    }
    final buildLike = mode == CommandMode.build ||
        RegExp(r'\b(build|create|make|develop|implement)\b').hasMatch(lower);
    if (buildLike) {
      final platformSignal = RegExp(
        r'\b(flutter|web|website|desktop|windows|macos|linux|android|ios|python|node|react|html|javascript|typescript)\b',
      ).hasMatch(lower);
      final outcomeSignal = RegExp(
        r'\b(app|application|tool|dashboard|site|website|service|converter|editor|viewer|manager|game|api|bot)\b',
      ).hasMatch(lower);
      final scopeSignal = RegExp(
        r'\b(local|backend|account|login|database|offline|online|simple|prototype|production|polished|responsive)\b',
      ).hasMatch(lower);
      final needsClarification = normalized.length < 90 ||
          !outcomeSignal ||
          (!platformSignal && !scopeSignal);
      return ConversationIntent(
        kind: ConversationIntentKind.buildNewProject,
        needsClarification: needsClarification,
        projectMayBeProvisioned: true,
        suggestedProjectName: suggestProjectName(normalized),
      );
    }
    return ConversationIntent(
      kind: ConversationIntentKind.modifyProject,
      needsClarification: false,
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
