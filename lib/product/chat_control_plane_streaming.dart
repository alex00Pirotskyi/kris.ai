part of 'chat_control_plane_studio.dart';

extension _ChatControlPlaneStreaming on _ChatControlPlaneStudioState {
  /// Answers ordinary informational turns through the provider's real text
  /// delta callback. A provider that streams updates the canonical transcript
  /// incrementally; a provider that does not stream shows the normal truthful
  /// busy/Thinking state and appends only the final answer.
  Future<void> _answerInformationalStreaming(
    ChatInteractionDecision decision,
  ) async {
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
}
