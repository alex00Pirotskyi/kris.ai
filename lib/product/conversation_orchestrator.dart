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
