import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chat;
  late String actions;
  late String view;
  late String runtime;

  setUpAll(() {
    chat =
        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    actions = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    view = File('lib/product/chat_control_plane_studio_view.dart')
        .readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
  });

  test('Chat run and permission projection are owned by the canonical session',
      () {
    expect(chat, contains("import 'kristin_conversation_session.dart';"));
    expect(chat,
        contains('final KristinConversationSession conversationSession ='));
    expect(chat, isNot(contains('RunRecord? currentRun;')));
    expect(chat, isNot(contains('bool awaitingPermission = false;')));
    expect(
        chat,
        contains(
            'RunRecord? get currentRun => conversationSession.currentRun;'));
    expect(
        chat,
        contains(
            'bool get awaitingPermission => conversationSession.awaitingPermission;'));
    expect(
        chat,
        contains(
            'bool get hasNonterminalRun => conversationSession.hasNonterminalRun;'));
    expect(chat, isNot(contains('String? selectedProjectId;')));
    expect(chat, isNot(contains('String? selectedModelId;')));
    expect(
      chat,
      contains(
        'String? get selectedProjectId => conversationSession.selectedProjectId;',
      ),
    );
    expect(
      chat,
      contains(
        'String? get selectedModelId => conversationSession.selectedModelId;',
      ),
    );
    expect(chat, contains('conversationSession.selectProject(value);'));
    expect(chat, contains('conversationSession.selectModel(value);'));
  });

  test('Chat live execution projection is owned by the canonical session', () {
    expect(chat, isNot(contains('final List<LiveRunSignal> liveSignals')));
    expect(chat, isNot(contains("String liveAssistantProtocolText = '';")));
    expect(chat, isNot(contains("String liveAssistantText = '';")));
    expect(chat, isNot(contains("String liveProgressText = '';")));
    expect(chat, isNot(contains("String liveToolName = '';")));
    expect(chat, isNot(contains("String liveToolOutput = '';")));
    expect(chat, isNot(contains('liveSignals.clear();')));
    expect(
      chat.split('\n').any(
            (line) => line.trimLeft().startsWith('liveProgressText ='),
          ),
      isFalse,
    );
    expect(actions, isNot(contains('liveSignals.clear();')));
    expect(
      actions.split('\n').any(
            (line) => line.trimLeft().startsWith('liveProgressText ='),
          ),
      isFalse,
    );
    expect(
      chat,
      contains(
        'List<LiveRunSignal> get liveSignals => conversationSession.liveSignals;',
      ),
    );
    expect(
      chat,
      contains('conversationSession.recordLiveSignal(signal);'),
    );
    expect(chat, contains('conversationSession.showLiveProgress('));
    expect(chat, contains('conversationSession.clearLiveExecution();'));
    expect(actions, contains('conversationSession.beginLiveExecution();'));
    expect(actions, contains('conversationSession.clearLiveExecution();'));
  });

  test('startup and refresh restore the durable deferred interaction', () {
    expect(
      RegExp(r'latestDeferredInteraction\(').allMatches(chat).length,
      greaterThanOrEqualTo(2),
    );
    expect(chat, contains('conversationSession.setDeferredInteraction('));
    expect(chat, contains('return !const <RunState>{'));
    expect(chat, contains('RunState.succeeded,'));
    expect(chat, contains('RunState.failed,'));
    expect(chat, contains('RunState.cancelled,'));
  });

  test('takeover answer is recorded and resumed before ordinary steering', () {
    final takeover =
        chat.indexOf('if (conversationSession.awaitingUserInput) {');
    final record = chat.indexOf('runtime.recordDeferredUserResponse(');
    final resume = chat.indexOf('() => runtime.resume(run.id)');
    final steering = chat.indexOf('runtime.steerRun(currentRun!.id, request)');
    expect(takeover, greaterThanOrEqualTo(0));
    expect(record, greaterThan(takeover));
    expect(resume, greaterThan(record));
    expect(steering, greaterThan(resume));
    expect(chat,
        contains('conversationSession.setDeferredInteraction(resolved);'));
  });

  test('ProductRuntime exposes only durable deferred interaction operations',
      () {
    expect(runtime, contains("import 'agent_deferred_interaction.dart';"));
    expect(
        runtime,
        contains(
            'Future<AgentDeferredInteraction?> latestDeferredInteraction('));
    expect(
        runtime,
        contains(
            'Future<AgentDeferredInteraction?> pendingDeferredInteraction('));
    expect(
        runtime,
        contains(
            'Future<AgentDeferredInteraction> recordDeferredUserResponse({'));
    expect(runtime,
        contains('AgentDeferredInteractionStore(repositories.workflow)'));
  });

  test('takeover prompt is visible and manual resume is hidden while pending',
      () {
    expect(view, contains('conversationSession.deferredUserPrompt'));
    expect(
        view,
        contains(
            'Your answer supplies intent context only and does not grant new permissions or authority.'));
    expect(view, contains('!conversationSession.awaitingUserInput'));
    expect(
        view,
        contains(
            'final waitingForInput = conversationSession.awaitingUserInput;'));
  });
}
