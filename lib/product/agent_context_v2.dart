import 'dart:convert';

import 'crypto_utils.dart';

enum AgentContextSource {
  system,
  coordinator,
  user,
  project,
  web,
  memory,
  terminal,
  mcp,
  a2a,
  tool,
}

enum AgentContextTrust {
  systemPolicy,
  coordinatorGuidance,
  userIntent,
  untrustedData,
}

extension AgentContextSourceWire on AgentContextSource {
  String get wireName => name;
}

extension AgentContextTrustWire on AgentContextTrust {
  String get wireName => switch (this) {
        AgentContextTrust.systemPolicy => 'system_policy',
        AgentContextTrust.coordinatorGuidance => 'coordinator_guidance',
        AgentContextTrust.userIntent => 'user_intent',
        AgentContextTrust.untrustedData => 'untrusted_data',
      };
}

class AgentContextEnvelope {
  AgentContextEnvelope({
    required this.source,
    required this.trust,
    required String content,
    this.metadata = const <String, Object?>{},
  })  : content = content,
        contentSha256 = Sha256.text(content) {
    if (!_trustAllowedForSource(source, trust)) {
      throw StateError('agent_context_trust_source_mismatch');
    }
  }

  final AgentContextSource source;
  final AgentContextTrust trust;
  final String content;
  final String contentSha256;
  final Map<String, Object?> metadata;

  bool get canDefineAuthority => trust == AgentContextTrust.systemPolicy;
  bool get isUntrusted => trust == AgentContextTrust.untrustedData;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source.wireName,
        'trust': trust.wireName,
        'contentSha256': contentSha256,
        'content': content,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  String render() => const JsonEncoder.withIndent('  ').convert(toJson());

  static bool _trustAllowedForSource(
    AgentContextSource source,
    AgentContextTrust trust,
  ) {
    return switch (source) {
      AgentContextSource.system => trust == AgentContextTrust.systemPolicy,
      AgentContextSource.coordinator =>
        trust == AgentContextTrust.coordinatorGuidance,
      AgentContextSource.user => trust == AgentContextTrust.userIntent,
      AgentContextSource.project ||
      AgentContextSource.web ||
      AgentContextSource.memory ||
      AgentContextSource.terminal ||
      AgentContextSource.mcp ||
      AgentContextSource.a2a ||
      AgentContextSource.tool => trust == AgentContextTrust.untrustedData,
    };
  }
}

class AgentInjectionAssessment {
  const AgentInjectionAssessment({
    required this.suspicious,
    required this.signals,
  });

  final bool suspicious;
  final List<String> signals;
}

class AgentPromptInjectionGuard {
  const AgentPromptInjectionGuard();

  static final List<MapEntry<String, RegExp>> _signals =
      <MapEntry<String, RegExp>>[
    MapEntry(
      'authority_impersonation',
      RegExp(
        r'\b(?:system|developer|administrator|root)\s+(?:message|instruction|policy|override)\b',
        caseSensitive: false,
      ),
    ),
    MapEntry(
      'instruction_override',
      RegExp(
        r'\b(?:ignore|disregard|override|replace)\b.{0,48}\b(?:instructions?|rules?|policy|system)\b',
        caseSensitive: false,
      ),
    ),
    MapEntry(
      'credential_exfiltration',
      RegExp(
        r'\b(?:send|upload|post|exfiltrate|reveal|print)\b.{0,64}\b(?:secret|token|password|credential|private key|api key)\b',
        caseSensitive: false,
      ),
    ),
    MapEntry(
      'tool_authority_request',
      RegExp(
        r'\b(?:call|invoke|run|execute)\b.{0,40}\b(?:tool|shell|terminal|command)\b.{0,80}\b(?:without approval|ignore policy|bypass)\b',
        caseSensitive: false,
      ),
    ),
  ];

  AgentInjectionAssessment assess(AgentContextEnvelope envelope) {
    if (!envelope.isUntrusted) {
      return const AgentInjectionAssessment(
        suspicious: false,
        signals: <String>[],
      );
    }
    final signals = <String>[
      for (final entry in _signals)
        if (entry.value.hasMatch(envelope.content)) entry.key,
    ]..sort();
    return AgentInjectionAssessment(
      suspicious: signals.isNotEmpty,
      signals: List<String>.unmodifiable(signals),
    );
  }

  AgentContextEnvelope wrapUntrusted({
    required AgentContextSource source,
    required String content,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (const <AgentContextSource>{
      AgentContextSource.system,
      AgentContextSource.coordinator,
      AgentContextSource.user,
    }.contains(source)) {
      throw StateError('agent_context_untrusted_source_required');
    }
    final envelope = AgentContextEnvelope(
      source: source,
      trust: AgentContextTrust.untrustedData,
      content: content,
      metadata: metadata,
    );
    final assessment = assess(envelope);
    return AgentContextEnvelope(
      source: source,
      trust: AgentContextTrust.untrustedData,
      content: content,
      metadata: <String, Object?>{
        ...metadata,
        'injectionSuspicious': assessment.suspicious,
        if (assessment.signals.isNotEmpty)
          'injectionSignals': assessment.signals,
        'authorityBearing': false,
      },
    );
  }
}

class AgentDestinationGuard {
  const AgentDestinationGuard();

  void requireAuthorized({
    required AgentContextEnvelope proposedBy,
    required String destination,
    required Set<String> authorizedDestinations,
  }) {
    final normalized = destination.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw StateError('agent_destination_required');
    }
    if (proposedBy.isUntrusted) {
      throw StateError('agent_destination_untrusted_source_denied');
    }
    final authorized = authorizedDestinations
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!authorized.contains(normalized)) {
      throw StateError('agent_destination_not_authorized');
    }
  }
}
