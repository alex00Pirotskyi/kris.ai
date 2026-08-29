from pathlib import Path

session = Path('lib/product/kristin_conversation_session.dart')
text = session.read_text(encoding='utf-8')
marker = """  /// Applies a refreshed record for the currently attached durable run.\n  void updateRun(RunRecord run) {\n    _attachRun(run, restoring: false);\n  }\n\n  void setAwaitingPermission(bool value) {\n"""
insertion = """  /// Applies a refreshed record for the currently attached durable run.\n  void updateRun(RunRecord run) {\n    _attachRun(run, restoring: false);\n  }\n\n  /// Detaches a finished/no-run governed turn without erasing conversation\n  /// history or the user's selected project/model context.\n  ///\n  /// This is the compatibility boundary for legacy Chat `currentRun = null`\n  /// assignments. It fails closed while unfinished durable work is attached.\n  bool detachFinishedRun() {\n    if (hasNonterminalRun) return false;\n    _composerDraft = '';\n    _pendingDecision = null;\n    _understandingHistory = null;\n    _taskSpecification = null;\n    _routingDecision = null;\n    _canonicalPlan = null;\n    _planningFailure = null;\n    _completedTasks = const <CompletedTaskRecord>[];\n    _lastReconciliation = null;\n    _prepared = null;\n    _currentRun = null;\n    _deferredInteraction = null;\n    _awaitingPermission = false;\n    _activeRequest = '';\n    clearLiveExecution();\n    return true;\n  }\n\n  void setAwaitingPermission(bool value) {\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected session updateRun source shape')
text = text.replace(marker, insertion)
old_reset = """  /// Starts a genuinely new conversation while preserving the user's selected\n  /// project/model context. A non-terminal durable run must be resolved first.\n  void resetForNewConversation() {\n    if (hasNonterminalRun) {\n      throw const KristinConversationSessionException(\n        'conversation_run_active',\n        'A new conversation cannot orphan an unfinished governed run.',\n      );\n    }\n    _messages.clear();\n    _composerDraft = '';\n    _pendingDecision = null;\n    _understandingHistory = null;\n    _taskSpecification = null;\n    _routingDecision = null;\n    _canonicalPlan = null;\n    _planningFailure = null;\n    _completedTasks = const <CompletedTaskRecord>[];\n    _lastReconciliation = null;\n    _prepared = null;\n    _currentRun = null;\n    _deferredInteraction = null;\n    _awaitingPermission = false;\n    _activeRequest = '';\n    clearLiveExecution();\n  }\n"""
new_reset = """  /// Starts a genuinely new conversation while preserving the user's selected\n  /// project/model context. A non-terminal durable run must be resolved first.\n  void resetForNewConversation() {\n    if (!detachFinishedRun()) {\n      throw const KristinConversationSessionException(\n        'conversation_run_active',\n        'A new conversation cannot orphan an unfinished governed run.',\n      );\n    }\n    _messages.clear();\n  }\n"""
if text.count(old_reset) != 1:
    raise SystemExit('unexpected session reset source shape')
text = text.replace(old_reset, new_reset)
session.write_text(text, encoding='utf-8', newline='\n')

studio = Path('lib/product/chat_control_plane_studio.dart')
text = studio.read_text(encoding='utf-8')
old_null_setter = """    if (value == null) {\n      // Transitional compatibility for the remaining Chat fields: a legacy\n      // null assignment may clear a finished/no-run association, but it can\n      // never orphan unfinished durable work.\n      if (!conversationSession.hasNonterminalRun) {\n        conversationSession.resetForNewConversation();\n      }\n      return;\n    }\n"""
new_null_setter = """    if (value == null) {\n      // Transitional compatibility for the remaining Chat fields: a legacy\n      // null assignment may detach a finished/no-run association, but the\n      // canonical session fails closed if unfinished durable work exists.\n      conversationSession.detachFinishedRun();\n      return;\n    }\n"""
if text.count(old_null_setter) != 1:
    raise SystemExit('unexpected Chat currentRun null setter source shape')
text = text.replace(old_null_setter, new_null_setter)
studio.write_text(text, encoding='utf-8', newline='\n')

actions = Path('lib/product/chat_control_plane_studio_actions.dart')
text = actions.read_text(encoding='utf-8')
old_new_chat = """    _mutate(() {\n      transcript.clear();\n      pendingDecision = null;\n      understandingHistory = null;\n      prepared = null;\n      currentRun = null;\n      awaitingPermission = false;\n      activeRequest = '';\n      conversationSession.clearLiveExecution();\n      suggestions = const <ChatAutocompleteSuggestion>[];\n"""
new_new_chat = """    _mutate(() {\n      transcript.clear();\n      conversationSession.resetForNewConversation();\n      pendingDecision = null;\n      understandingHistory = null;\n      prepared = null;\n      awaitingPermission = false;\n      activeRequest = '';\n      suggestions = const <ChatAutocompleteSuggestion>[];\n"""
if text.count(old_new_chat) != 1:
    raise SystemExit('unexpected newChat reset source shape')
text = text.replace(old_new_chat, new_new_chat)
actions.write_text(text, encoding='utf-8', newline='\n')

session_test = Path('test/product/kristin_conversation_session_test.dart')
text = session_test.read_text(encoding='utf-8')
marker = """  test('new governed request cannot orphan a non-terminal run', () {\n"""
insertion = """  test('finished run detach preserves transcript and selected context', () {\n    final session = KristinConversationSession();\n    session.addUserMessage('hello');\n    session.addAssistantMessage('done');\n    session.restoreRun(_run(id: 'run-a', state: RunState.running));\n    session.recordLiveSignal(\n      _signal('run-a', 1, LiveRunSignalKind.modelProgress),\n    );\n    session.updateRun(_run(id: 'run-a', state: RunState.succeeded));\n    session.selectProject('project-after');\n    session.selectModel('model-after');\n    session.setComposerDraft('draft');\n\n    expect(session.state, isA<ChatCompleted>());\n    expect(session.detachFinishedRun(), isTrue);\n\n    expect(session.messages.map((message) => message.text), <String>['hello', 'done']);\n    expect(session.selectedProjectId, 'project-after');\n    expect(session.selectedModelId, 'model-after');\n    expect(session.composerDraft, isEmpty);\n    expect(session.currentRun, isNull);\n    expect(session.prepared, isNull);\n    expect(session.deferredInteraction, isNull);\n    expect(session.awaitingPermission, isFalse);\n    expect(session.activeRequest, isEmpty);\n    expect(session.liveSignals, isEmpty);\n    expect(session.liveProgressText, isEmpty);\n    expect(session.state, isA<ChatIdle>());\n  });\n\n  test('unfinished run detach fails closed without partial clearing', () {\n    final session = KristinConversationSession();\n    session.addUserMessage('keep this');\n    session.restoreRun(_run(id: 'run-a', state: RunState.running));\n    session.setComposerDraft('keep draft');\n    session.recordLiveSignal(\n      _signal('run-a', 1, LiveRunSignalKind.modelProgress),\n    );\n\n    expect(session.detachFinishedRun(), isFalse);\n\n    expect(session.currentRun?.id, 'run-a');\n    expect(session.messages.single.text, 'keep this');\n    expect(session.composerDraft, 'keep draft');\n    expect(session.prepared, isNotNull);\n    expect(session.liveSignals, isNotEmpty);\n    expect(session.state, isA<ChatExecuting>());\n  });\n\n  test('new governed request cannot orphan a non-terminal run', () {\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected session test insertion point')
text = text.replace(marker, insertion)
session_test.write_text(text, encoding='utf-8', newline='\n')

bridge_test = Path('test/product/chat_deferred_takeover_bridge_test.dart')
text = bridge_test.read_text(encoding='utf-8')
marker = """  test('Chat live execution projection is owned by the canonical session', () {\n"""
insertion = """  test('Chat detaches finished runs without resetting conversation history', () {\n    expect(chat, contains('conversationSession.detachFinishedRun();'));\n    expect(\n      chat,\n      isNot(contains('conversationSession.resetForNewConversation();')),\n    );\n    expect(\n      actions,\n      contains('conversationSession.resetForNewConversation();'),\n    );\n  });\n\n  test('Chat live execution projection is owned by the canonical session', () {\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected Chat bridge test insertion point')
text = text.replace(marker, insertion)
bridge_test.write_text(text, encoding='utf-8', newline='\n')
