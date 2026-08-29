from pathlib import Path

studio = Path('lib/product/chat_control_plane_studio.dart')
text = studio.read_text(encoding='utf-8')
text = text.replace(
    '  final List<LiveRunSignal> liveSignals = <LiveRunSignal>[];\n',
    '  List<LiveRunSignal> get liveSignals => conversationSession.liveSignals;\n',
)
old_live_fields = """  String liveAssistantProtocolText = '';\n  String liveAssistantText = '';\n  String liveProgressText = '';\n  String liveToolName = '';\n  String liveToolOutput = '';\n"""
new_live_fields = """  String get liveAssistantProtocolText =>\n      conversationSession.liveAssistantProtocolText;\n  String get liveAssistantText => conversationSession.liveAssistantText;\n  String get liveProgressText => conversationSession.liveProgressText;\n  String get liveToolName => conversationSession.liveToolName;\n  String get liveToolOutput => conversationSession.liveToolOutput;\n"""
if text.count(old_live_fields) != 1:
    raise SystemExit('unexpected Chat live field source shape')
text = text.replace(old_live_fields, new_live_fields)
start = text.index('  void _onLiveSignal(LiveRunSignal signal) {')
end = text.index('\n\n  /// Adding a future target type', start)
new_handler = """  void _onLiveSignal(LiveRunSignal signal) {\n    if (!mounted || signal.runId != currentRun?.id) return;\n    _mutate(() {\n      conversationSession.recordLiveSignal(signal);\n    });\n  }"""
text = text[:start] + new_handler + text[end:]
text = text.replace(
    "          liveProgressText = 'Continuing with your answer.';\n",
    "          conversationSession.showLiveProgress(\n            'Continuing with your answer.',\n          );\n",
)
old_steering_progress = """            liveProgressText =\n                'Your new direction is queued for the next safe step.';\n"""
new_steering_progress = """            conversationSession.showLiveProgress(\n              'Your new direction is queued for the next safe step.',\n            );\n"""
if text.count(old_steering_progress) != 1:
    raise SystemExit('unexpected optimistic steering progress source shape')
text = text.replace(old_steering_progress, new_steering_progress)
old_archive_projection = """    liveSignals.clear();\n    liveAssistantProtocolText = '';\n    liveAssistantText = '';\n    liveProgressText = '';\n    liveToolName = '';\n    liveToolOutput = '';\n"""
if text.count(old_archive_projection) != 1:
    raise SystemExit('unexpected archived live projection source shape')
text = text.replace(
    old_archive_projection,
    '    conversationSession.clearLiveExecution();\n',
)
studio.write_text(text, encoding='utf-8', newline='\n')

actions = Path('lib/product/chat_control_plane_studio_actions.dart')
text = actions.read_text(encoding='utf-8')
old_start_projection = """      liveSignals.clear();\n      liveAssistantProtocolText = '';\n      liveAssistantText = '';\n      liveProgressText = 'Starting the first safe step.';\n      liveToolName = '';\n      liveToolOutput = '';\n"""
new_start_projection = """      conversationSession.beginLiveExecution();\n"""
if text.count(old_start_projection) != 1:
    raise SystemExit('unexpected startPrepared live projection source shape')
text = text.replace(old_start_projection, new_start_projection)
old_new_chat_projection = """      liveSignals.clear();\n      liveAssistantProtocolText = '';\n      liveAssistantText = '';\n      liveProgressText = '';\n      liveToolName = '';\n      liveToolOutput = '';\n"""
if text.count(old_new_chat_projection) != 1:
    raise SystemExit('unexpected newChat live projection source shape')
text = text.replace(
    old_new_chat_projection,
    '      conversationSession.clearLiveExecution();\n',
)
actions.write_text(text, encoding='utf-8', newline='\n')

session = Path('lib/product/kristin_conversation_session.dart')
text = session.read_text(encoding='utf-8')
marker = """  void clearLiveExecution() {\n    _liveSignals.clear();\n"""
insertion = """  /// Starts a fresh UI projection for the currently attached execution.\n  ///\n  /// This is projection state only: it grants no execution authority and does\n  /// not change the durable run. Incoming [LiveRunSignal] values remain the\n  /// source of truth once execution begins emitting them.\n  void beginLiveExecution() {\n    clearLiveExecution();\n    _liveProgressText = 'Starting the first safe step.';\n  }\n\n  /// Updates an optimistic user-visible execution message without changing\n  /// durable run state or execution authority. Live signals may subsequently\n  /// replace this projection with runtime-reported progress.\n  void showLiveProgress(String message) {\n    _liveProgressText = message;\n  }\n\n  void clearLiveExecution() {\n    _liveSignals.clear();\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected session clearLiveExecution source shape')
text = text.replace(marker, insertion)
session.write_text(text, encoding='utf-8', newline='\n')

session_test = Path('test/product/kristin_conversation_session_test.dart')
text = session_test.read_text(encoding='utf-8')
marker = """    expect(session.liveSignals.last.sequence, 3);\n  });\n\n  test('visible transcript is bounded and never accepts blank messages', () {\n"""
insertion = """    expect(session.liveSignals.last.sequence, 3);\n  });\n\n  test('beginning live execution resets and primes the canonical projection', () {\n    final session = KristinConversationSession();\n    session.restoreRun(_run(id: 'run-a', state: RunState.running));\n    session.recordLiveSignal(\n      _signal('run-a', 1, LiveRunSignalKind.modelProgress),\n    );\n\n    expect(session.liveSignals, isNotEmpty);\n    expect(session.liveProgressText, 'progress');\n\n    session.beginLiveExecution();\n\n    expect(session.liveSignals, isEmpty);\n    expect(session.liveAssistantProtocolText, isEmpty);\n    expect(session.liveAssistantText, isEmpty);\n    expect(session.liveProgressText, 'Starting the first safe step.');\n    expect(session.liveToolName, isEmpty);\n    expect(session.liveToolOutput, isEmpty);\n\n    session.showLiveProgress('Continuing with your answer.');\n    expect(session.liveProgressText, 'Continuing with your answer.');\n  });\n\n  test('visible transcript is bounded and never accepts blank messages', () {\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected session test source shape')
text = text.replace(marker, insertion)
session_test.write_text(text, encoding='utf-8', newline='\n')

chat_test = Path('test/product/chat_deferred_takeover_bridge_test.dart')
text = chat_test.read_text(encoding='utf-8')
text = text.replace(
    '  late String chat;\n  late String view;\n',
    '  late String chat;\n  late String actions;\n  late String view;\n',
)
text = text.replace(
    "    chat =\n        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();\n",
    "    chat =\n        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();\n    actions = File('lib/product/chat_control_plane_studio_actions.dart')\n        .readAsStringSync();\n",
)
marker = """    expect(chat, contains('conversationSession.selectProject(value);'));\n    expect(chat, contains('conversationSession.selectModel(value);'));\n  });\n\n  test('startup and refresh restore the durable deferred interaction', () {\n"""
insertion = """    expect(chat, contains('conversationSession.selectProject(value);'));\n    expect(chat, contains('conversationSession.selectModel(value);'));\n  });\n\n  test('Chat live execution projection is owned by the canonical session', () {\n    expect(chat, isNot(contains('final List<LiveRunSignal> liveSignals')));\n    expect(chat, isNot(contains("String liveAssistantProtocolText = '';")));\n    expect(chat, isNot(contains("String liveAssistantText = '';")));\n    expect(chat, isNot(contains("String liveProgressText = '';")));\n    expect(chat, isNot(contains("String liveToolName = '';")));\n    expect(chat, isNot(contains("String liveToolOutput = '';")));\n    expect(chat, isNot(contains('liveSignals.clear();')));\n    expect(chat, isNot(contains('liveProgressText =')));\n    expect(actions, isNot(contains('liveSignals.clear();')));\n    expect(actions, isNot(contains('liveProgressText =')));\n    expect(\n      chat,\n      contains(\n        'List<LiveRunSignal> get liveSignals => conversationSession.liveSignals;',\n      ),\n    );\n    expect(\n      chat,\n      contains('conversationSession.recordLiveSignal(signal);'),\n    );\n    expect(chat, contains('conversationSession.showLiveProgress('));\n    expect(chat, contains('conversationSession.clearLiveExecution();'));
    expect(actions, contains('conversationSession.beginLiveExecution();'));
    expect(actions, contains('conversationSession.clearLiveExecution();'));
  });\n\n  test('startup and refresh restore the durable deferred interaction', () {\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected Chat bridge test source shape')
text = text.replace(marker, insertion)
chat_test.write_text(text, encoding='utf-8', newline='\n')
