part of 'chat_control_plane_studio.dart';

extension _ChatControlPlaneStreaming on _ChatControlPlaneStudioState {
  /// Answers ordinary informational turns through the provider's real text
  /// delta callback. Self-awareness questions are resolved deterministically
  /// before model generation so Kristin reports current application truth
  /// rather than asking a model to infer its own capabilities.
  Future<void> _answerInformationalStreaming(
    ChatInteractionDecision decision,
  ) async {
    final selfAware = await _trySelfAwarenessAnswer(decision);
    if (selfAware != null) {
      _mutate(() {
        conversationSession.addAssistantMessage(selfAware);
        status = 'Kristin is ready';
      });
      return;
    }

    final local = await _tryLocalAnswer(decision);
    if (local != null) {
      _mutate(() {
        conversationSession.addAssistantMessage(local);
        status = 'Kristin is ready';
      });
      return;
    }

    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    if (model == null) {
      _showError('Connect an AI model so Kristin can answer this question.');
      return;
    }

    final recentContext = _looksOperational(decision.parsed.originalText)
        ? _informationalContext()
        : '';
    final recentConversation = _recentConversation();
    final promptSections = <String>[
      if (recentConversation.isNotEmpty)
        'Recent conversation:\n$recentConversation',
      if (recentContext.isNotEmpty)
        'Available local status context:\n$recentContext',
    ];
    final userPrompt = promptSections.isEmpty
        ? decision.parsed.originalText
        : '${promptSections.join('\n\n')}\n\nUser: ${decision.parsed.originalText}';
    final activeModel = model;

    _mutate(() {
      conversationSession.beginAssistantResponse();
      status = 'Thinking';
    });
    final result = await _perform<ModelGenerationResult>(
      'Thinking',
      () => runtime.models.providerFor(activeModel).generate(
            ModelGenerationRequest(
              identity: activeModel,
              commandId: newId('chat_info'),
              systemPrompt:
                  'You are Kristin. Answer the user as a normal conversational assistant. '
                  'This request is informational only: do not claim to execute tools, '
                  'change files, start processes, or grant permissions. Only use the '
                  'recent conversation and status context if the current message is '
                  'actually about them. Be concise and useful. Return one JSON object '
                  'with exactly one string field named "answer" and no markdown fence.',
              userPrompt: userPrompt,
              temperature: 0.2,
              maxOutputTokens: 1600,
              firstTokenTimeout: const Duration(minutes: 2),
              totalTimeout: const Duration(minutes: 4),
              onTextDelta: (delta) {
                if (!mounted || delta.isEmpty) return;
                _mutate(() {
                  conversationSession.recordAssistantResponseDelta(delta);
                  status = 'Kristin is responding';
                });
              },
            ),
          ),
    );
    if (result == null || !mounted) {
      _mutate(conversationSession.cancelAssistantResponse);
      return;
    }

    var visible = ConversationStreamProjector.visibleText(result.text).trim();
    if (visible.isEmpty) {
      try {
        final decoded = jsonDecode(result.text);
        if (decoded is Map && decoded['answer'] is String) {
          visible = decoded['answer'].toString().trim();
        }
      } catch (_) {
        visible = result.text.trim();
      }
    }
    if (visible.isEmpty) visible = 'The model returned an empty answer.';
    _mutate(() {
      conversationSession.finishAssistantResponse(visible);
      status = 'Kristin is ready';
    });
  }

  Future<String?> _trySelfAwarenessAnswer(
    ChatInteractionDecision decision,
  ) async {
    final original = decision.parsed.originalText.trim();
    final text = original.toLowerCase();
    final asksChanges = RegExp(
      r'\bwhat (?:has )?changed\b|\bchanges? recently\b|\bwhat changed since\b',
    ).hasMatch(text);
    final asksIntegrity = RegExp(
      r'\bself[- ]?awareness\b|\bself[- ]?integrity\b|'
      r'\b(?:check|verify|probe) yourself\b|\bare you healthy\b',
    ).hasMatch(text);
    final asksCapabilities = RegExp(
      r'\bwhat can you do\b|\bwhat are you able to do\b|'
      r'\b(?:your|available|current) capabilities\b|'
      r'\bwhat can you do right now\b',
    ).hasMatch(text);
    final asksRequirements = RegExp(
      r"\bwhy can(?:'|’)t you\b|\bwhy cannot you\b|"
      r'\bwhat do you need to\b|\brequirements? for\b|'
      r'\bwhat would make .* possible\b|\bhow could you\b|'
      r'\bwhy is .* (?:blocked|unavailable)\b',
    ).hasMatch(text);

    if (!asksChanges &&
        !asksIntegrity &&
        !asksCapabilities &&
        !asksRequirements) {
      return null;
    }

    if (asksChanges) {
      final since = DateTime.now().toUtc().subtract(const Duration(minutes: 15));
      final changes = await dispatcher.selfChangesSince(
        since,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );
      if (changes.isEmpty) {
        return 'I have not observed a material self-model change in the last 15 minutes. Re-observation timestamps by themselves do not count as state changes.';
      }
      final lines = <String>[];
      for (final change in changes.reversed.take(6)) {
        final parts = <String>[];
        if (change.applicationFieldsChanged.isNotEmpty) {
          parts.add(
            'application: ${change.applicationFieldsChanged.join(', ')}',
          );
        }
        if (change.capabilityChanges.isNotEmpty) {
          parts.add(change.capabilityChanges.map((item) {
            final availability =
                '${item.previousAvailability?.name ?? 'unknown'}→${item.nextAvailability.name}';
            final health =
                '${item.previousHealth?.name ?? 'unknown'}→${item.nextHealth.name}';
            return '${item.capabilityId} availability $availability, health $health';
          }).join('; '));
        }
        lines.add(
          '${change.observedAt.toLocal().toIso8601String()}: ${parts.join(' | ')}',
        );
      }
      return 'Material changes I observed recently:\n${lines.join('\n')}';
    }

    if (asksIntegrity) {
      if (RegExp(r'\bcheck\b|\bverify\b|\bprobe\b').hasMatch(text)) {
        await dispatcher.runSelfConsistencyProbes(
          selectedProject: selectedProject,
          selectedModel: selectedModel,
        );
      }
      final snapshot = await dispatcher.selfAwareness(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: true,
      );
      final violations = await dispatcher.selfIntegrity(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );
      final available = snapshot.available.length;
      final blocked = snapshot.blocked.length;
      if (violations.isEmpty) {
        return 'My current self-model reports $available operational capabilities and $blocked blocked or unhealthy capabilities. The configured self-integrity invariants currently pass. This describes observed application state; it does not grant me any additional authority.';
      }
      final details = violations
          .take(8)
          .map(
            (item) => '- ${item.severity.name}: ${item.invariantId}: ${item.message}',
          )
          .join('\n');
      return 'My self-model currently has $available operational capabilities and $blocked blocked or unhealthy capabilities. I also see these integrity findings:\n$details';
    }

    if (asksCapabilities) {
      final snapshot = await dispatcher.selfAwareness(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: true,
      );
      final operational = snapshot.available
          .take(18)
          .map((item) => '${item.descriptor.name} (${item.descriptor.id})')
          .join(', ');
      final blockers = snapshot.blocked.take(6).map((item) {
        final reasons = <String>[
          ...item.availability.reasons,
          ...?item.health?.reasons,
        ];
        return '- ${item.descriptor.id}: ${reasons.isEmpty ? item.availability.state.name : reasons.first}';
      }).join('\n');
      return 'Right now I report ${snapshot.available.length} operational capabilities. '
          '${operational.isEmpty ? 'None are currently operational.' : operational}. '
          'I also know ${snapshot.blocked.length} capabilities that are currently blocked or unhealthy.'
          '${blockers.isEmpty ? '' : '\nKey blockers:\n$blockers'}\n'
          'Capability availability is separate from execution authority; governed permissions are still evaluated for the concrete action.';
    }

    final candidates = await dispatcher.capabilitiesForObjective(
      original,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    if (candidates.isEmpty) return null;
    final target = candidates.first;
    final report = await dispatcher.capabilityRequirements(
      target.descriptor.id,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final details = <String>[
      '${target.descriptor.name} (${target.descriptor.id}) is ${report.usableNow ? 'operationally usable' : 'not operationally usable'} right now.',
      report.explanation,
      if (report.missingPrerequisites.isNotEmpty)
        'Missing prerequisites: ${report.missingPrerequisites.join(', ')}.',
      if (report.requiredAuthority.isNotEmpty)
        report.authorityObservation.name == 'notEvaluated'
            ? 'Required authority (${report.requiredAuthority.join(', ')}) has not been evaluated for a concrete operation yet.'
            : 'Authority state is ${report.authorityObservation.name}; unresolved authority: ${report.missingAuthority.join(', ')}.',
      if (report.satisfactionPath.isNotEmpty)
        'Minimum path to satisfy it:\n${report.satisfactionPath.map((step) => '- ${step.description}').join('\n')}',
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    return details.join('\n');
  }
}
