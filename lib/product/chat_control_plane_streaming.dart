part of 'chat_control_plane_studio.dart';

extension _ChatControlPlaneStreaming on _ChatControlPlaneStudioState {
  /// Answers ordinary informational turns through the provider's real text
  /// delta callback. The deterministic self-awareness recognizer remains a
  /// fast path, but correctness no longer depends on it: every model answer
  /// receives the same bounded cognitive substrate first.
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
    final cognitive = await dispatcher.cognitiveContext(
      objective: decision.parsed.originalText,
      selectedProject: selectedProject,
      selectedModel: activeModel,
      // The transcript already remains in the user prompt above. Do not also
      // convert it into cognitive working memory, which would reserve context
      // budget for a duplicate user assertion and alter snapshot identity.
      maxCharacters: 6800,
    );

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
              systemPrompt: cognitive.wrapSystemPrompt(
                'Answer as Kristin, the persistent application-level AI identity. '
                'This turn is informational only: do not claim to execute tools, '
                'change files, start processes, enter Owner Mode, or grant permissions. '
                'Use the authoritative cognitive context for product/self facts. '
                'If it marks something unknown, stale, conflicting, blocked, or not observed, '
                'say so rather than inventing a facility. Be concise and useful. '
                'Return one JSON object with exactly one string field named "answer" and no markdown fence.',
              ),
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
    // Shorthand spellings remain an optimization. Unmatched languages still
    // fall through to model generation with the cognitive substrate above.
    final asksCapabilities = RegExp(
      r'\bwhat can (?:you|u) do\b|\bwhat are (?:you|u) able to do\b|'
      r'\b(?:your|ur|available|current) capabilities\b|'
      r'\bwhat capabilities do (?:you|u) have\b|'
      r'\b(?:show|list)(?: me)? (?:your|ur) capabilities\b|'
      r'\bwhat can (?:you|u) help me with\b',
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
      final since = DateTime.now().toUtc().subtract(
            const Duration(minutes: 15),
          );
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
          parts.add('application: ${change.applicationFieldsChanged.join(', ')}');
        }
        if (change.capabilitiesAdded.isNotEmpty) {
          parts.add('added: ${change.capabilitiesAdded.join(', ')}');
        }
        if (change.capabilitiesRemoved.isNotEmpty) {
          parts.add('removed: ${change.capabilitiesRemoved.join(', ')}');
        }
        if (change.capabilitiesChanged.isNotEmpty) {
          parts.add('changed: ${change.capabilitiesChanged.join(', ')}');
        }
        lines.add(
          '${change.observedAt.toLocal().toIso8601String()}: ${parts.join('; ')}',
        );
      }
      return 'Recent self-model changes:\n${lines.join('\n')}';
    }

    if (asksIntegrity) {
      final violations = await dispatcher.selfIntegrity(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );
      final probes = await dispatcher.runSelfConsistencyProbes(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );
      final failing = probes
          .where((item) =>
              item.status == ProbeStatus.degraded ||
              item.status == ProbeStatus.failing)
          .toList();
      if (violations.isEmpty && failing.isEmpty) {
        return 'My current self-model passes its invariants and active consistency probes. This means my observed application state is internally consistent; it does not grant any new authority.';
      }
      final issues = <String>[
        ...violations.take(5).map((item) => '${item.code}: ${item.message}'),
        ...failing.take(5).map((item) => '${item.id}: ${item.detail}'),
      ];
      return 'I found self-model consistency issues:\n- ${issues.join('\n- ')}';
    }

    final capabilities = await dispatcher.capabilitiesForObjective(
      original,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    if (capabilities.isEmpty) {
      return 'I do not have a current capability descriptor that matches that request. I will not infer one from the language model itself.';
    }

    if (asksRequirements) {
      final reports = <CapabilityRequirementReport>[];
      for (final capability in capabilities.take(3)) {
        reports.add(await dispatcher.capabilityRequirements(
          capability.descriptor.id,
          selectedProject: selectedProject,
          selectedModel: selectedModel,
        ));
      }
      return reports.map((item) => item.explanation).join('\n\n');
    }

    final lines = capabilities.take(8).map((item) {
      final state = item.availability.state.name;
      final health = item.health?.state.name ?? 'unknown';
      final authority = item.availability.authorityObservation.name;
      final reason = <String>[
        ...item.availability.reasons,
        ...?item.health?.reasons,
      ].firstOrNull;
      return '- ${item.descriptor.name} (${item.descriptor.id}): availability=$state, health=$health, authority=$authority${reason == null ? '' : ' — $reason'}';
    }).join('\n');
    return 'Here is the relevant portion of my current capability model:\n$lines\n\nAvailability, health, authority and an executable Runner tool are separate facts; knowing about a capability does not grant it.';
  }

  Future<String?> _tryLocalAnswer(
    ChatInteractionDecision decision,
  ) async {
    final text = decision.parsed.originalText.trim();
    final lower = text.toLowerCase();
    final asksCurrentRun = RegExp(
      r'\b(?:what|which) (?:task|run|job) (?:are you|are u|r u) (?:doing|working on|running)\b|'
      r'\b(?:what|which) (?:are you|are u|r u) (?:doing|working on)\b|'
      r'\bcurrent (?:task|run|job)\b|'
      r'\bwhat(?:\'s| is) (?:the )?(?:current )?(?:task|run|job)\b',
    ).hasMatch(lower);
    if (asksCurrentRun) {
      final run = currentRun;
      if (run == null) {
        return 'I do not have an active run right now.';
      }
      final activeItem = run.plan.items.firstWhereOrNull(
        (item) =>
            run.progressFor(item.id).state == WorkItemState.running ||
            run.progressFor(item.id).state == WorkItemState.awaitingPermission ||
            run.progressFor(item.id).state == WorkItemState.awaitingUserInput,
      );
      if (activeItem == null) {
        return 'Run ${run.id} is ${run.state.name}. I do not currently observe a work item in an active step.';
      }
      return 'Run ${run.id} is ${run.state.name}. I am on “${activeItem.title}” (${activeItem.id}), which is ${run.progressFor(activeItem.id).state.name}.';
    }

    final asksSelectedProject = RegExp(
      r'\b(?:what|which) project (?:is selected|am i in|are we in|are you using)\b|'
      r'\bselected project\b|\bcurrent project\b',
    ).hasMatch(lower);
    if (asksSelectedProject) {
      final project = selectedProject;
      if (project == null) {
        return 'No project is selected.';
      }
      return 'The selected project is ${project.name} (${project.id}).';
    }

    final asksSelectedModel = RegExp(
      r'\b(?:what|which) (?:ai )?model (?:is selected|are you using|am i using)\b|'
      r'\bselected model\b|\bcurrent model\b',
    ).hasMatch(lower);
    if (asksSelectedModel) {
      final model = selectedModel;
      if (model == null) {
        return 'No reasoning model is selected.';
      }
      return 'I am currently using ${model.exactId} as my reasoning provider. The provider is not my identity.';
    }

    return null;
  }
}
