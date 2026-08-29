from pathlib import Path


session = Path('lib/product/kristin_conversation_session.dart')
text = session.read_text()

if "import 'agent_deferred_interaction.dart';" not in text:
    marker = "import 'chat_control_plane.dart';\n"
    if text.count(marker) != 1:
        raise SystemExit('session import marker mismatch')
    text = text.replace(
        marker,
        "import 'agent_deferred_interaction.dart';\n" + marker,
        1,
    )

marker = "  RunRecord? _currentRun;\n  bool _awaitingPermission = false;\n"
replacement = (
    "  RunRecord? _currentRun;\n"
    "  AgentDeferredInteraction? _deferredInteraction;\n"
    "  bool _awaitingPermission = false;\n"
)
if marker in text:
    text = text.replace(marker, replacement, 1)
elif 'AgentDeferredInteraction? _deferredInteraction;' not in text:
    raise SystemExit('session field marker mismatch')

marker = "  RunRecord? get currentRun => _currentRun;\n  bool get awaitingPermission => _awaitingPermission;\n"
replacement = (
    "  RunRecord? get currentRun => _currentRun;\n"
    "  AgentDeferredInteraction? get deferredInteraction => _deferredInteraction;\n"
    "  bool get awaitingPermission => _awaitingPermission;\n"
)
if marker in text:
    text = text.replace(marker, replacement, 1)
elif 'AgentDeferredInteraction? get deferredInteraction' not in text:
    raise SystemExit('session getter marker mismatch')

marker = "  bool get runAwaitingApproval =>\n      _currentRun?.state == RunState.awaitingApproval;\n\n"
if 'bool get awaitingUserInput =>' not in text:
    addition = marker + """  bool get awaitingUserInput =>
      _deferredInteraction?.awaitingUserResponse ?? false;

  String? get deferredUserPrompt {
    final interaction = _deferredInteraction;
    if (interaction == null || !interaction.awaitingUserResponse) return null;
    final question = interaction.decision.question?.trim() ?? '';
    if (question.isNotEmpty) return question;
    final reason = interaction.decision.reason.trim();
    return reason.isEmpty
        ? 'Kristin needs your input before continuing.'
        : reason;
  }

"""
    if text.count(marker) != 1:
        raise SystemExit('runAwaitingApproval marker mismatch')
    text = text.replace(marker, addition, 1)

marker = "  void setAwaitingPermission(bool value) {\n    _awaitingPermission = value;\n  }\n\n"
if 'void setDeferredInteraction(' not in text:
    addition = marker + """  void setDeferredInteraction(AgentDeferredInteraction? interaction) {
    if (interaction == null) {
      _deferredInteraction = null;
      return;
    }
    final run = _currentRun;
    if (run == null) {
      throw const KristinConversationSessionException(
        'conversation_deferred_run_missing',
        'A deferred interaction requires an attached durable run.',
      );
    }
    if (interaction.runId != run.id) {
      throw KristinConversationSessionException(
        'conversation_deferred_run_mismatch',
        'Deferred interaction ${interaction.id} belongs to run ${interaction.runId}, not ${run.id}.',
      );
    }
    if (!run.items.any(
      (progress) => progress.item.id == interaction.workItemId,
    )) {
      throw KristinConversationSessionException(
        'conversation_deferred_work_item_mismatch',
        'Deferred interaction ${interaction.id} references work item ${interaction.workItemId} outside run ${run.id}.',
      );
    }
    if (interaction.pending && runTerminal) {
      throw const KristinConversationSessionException(
        'conversation_deferred_run_terminal',
        'A terminal run cannot await a deferred interaction.',
      );
    }
    _deferredInteraction = interaction;
  }

"""
    if text.count(marker) != 1:
        raise SystemExit('setAwaitingPermission marker mismatch')
    text = text.replace(marker, addition, 1)

marker = "    _currentRun = null;\n    _awaitingPermission = false;\n    clearLiveExecution();\n"
replacement = (
    "    _currentRun = null;\n"
    "    _deferredInteraction = null;\n"
    "    _awaitingPermission = false;\n"
    "    clearLiveExecution();\n"
)
if marker in text:
    text = text.replace(marker, replacement, 1)
elif '_deferredInteraction = null;' not in text:
    raise SystemExit('begin request reset marker mismatch')

marker = "    _prepared = null;\n    _currentRun = null;\n    _awaitingPermission = false;\n    _activeRequest = '';\n"
replacement = (
    "    _prepared = null;\n"
    "    _currentRun = null;\n"
    "    _deferredInteraction = null;\n"
    "    _awaitingPermission = false;\n"
    "    _activeRequest = '';\n"
)
if marker in text:
    text = text.replace(marker, replacement, 1)
elif text.count('_deferredInteraction = null;') < 2:
    raise SystemExit('new conversation reset marker mismatch')

marker = "    if (existing == null || existing.id != run.id) {\n      clearLiveExecution();\n    }\n"
replacement = (
    "    if (existing == null || existing.id != run.id) {\n"
    "      _deferredInteraction = null;\n"
    "      clearLiveExecution();\n"
    "    }\n"
)
if marker in text:
    text = text.replace(marker, replacement, 1)
elif "      _deferredInteraction = null;\n      clearLiveExecution();" not in text:
    raise SystemExit('run attach marker mismatch')

session.write_text(text)


test = Path('test/product/kristin_conversation_session_test.dart')
text = test.read_text()
if "agent_deferred_interaction.dart" not in text:
    marker = "import 'package:flutter_test/flutter_test.dart';\n"
    replacement = marker + (
        "import 'package:kristin_local_agent/product/agent_decision_v3.dart';\n"
        "import 'package:kristin_local_agent/product/agent_deferred_interaction.dart';\n"
    )
    if text.count(marker) != 1:
        raise SystemExit('test import marker mismatch')
    text = text.replace(marker, replacement, 1)

marker = "  test('awaiting approval run projects to the permission state', () {\n"
if 'pending user takeover is projected through the canonical session' not in text:
    addition = """  test('pending user takeover is projected through the canonical session', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));
    session.setDeferredInteraction(
      _interaction(
        runId: 'run-a',
        status: AgentDeferredInteractionStatus.pending,
      ),
    );

    expect(session.awaitingUserInput, isTrue);
    expect(session.deferredUserPrompt, 'Which target should I use?');
    expect(session.deferredInteraction?.userResponseGrantsAuthority, isFalse);
  });

  test('deferred interaction cannot cross durable run identity', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));

    expect(
      () => session.setDeferredInteraction(
        _interaction(
          runId: 'run-b',
          status: AgentDeferredInteractionStatus.pending,
        ),
      ),
      throwsA(
        isA<KristinConversationSessionException>().having(
          (error) => error.code,
          'code',
          'conversation_deferred_run_mismatch',
        ),
      ),
    );
  });

  test('resolved takeover no longer projects as awaiting user input', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));
    session.setDeferredInteraction(
      _interaction(
        runId: 'run-a',
        status: AgentDeferredInteractionStatus.resolved,
        userResponse: 'Use staging.',
      ),
    );

    expect(session.awaitingUserInput, isFalse);
    expect(session.deferredUserPrompt, isNull);
  });

"""
    if text.count(marker) != 1:
        raise SystemExit('session test marker mismatch')
    text = text.replace(marker, addition + marker, 1)

marker = "LiveRunSignal _signal(String runId, int sequence, LiveRunSignalKind kind) =>\n"
if 'AgentDeferredInteraction _interaction({' not in text:
    helper = """AgentDeferredInteraction _interaction({
  required String runId,
  required AgentDeferredInteractionStatus status,
  String? userResponse,
}) =>
    AgentDeferredInteraction(
      id: 'interaction-a',
      runId: runId,
      workItemId: 'work-a',
      decision: AgentDecisionV3(
        kind: AgentDecisionV3Kind.userTakeover,
        question: 'Which target should I use?',
        reason: 'The target is ambiguous.',
      ),
      status: status,
      createdAt: DateTime.utc(2026, 8, 29),
      updatedAt: DateTime.utc(2026, 8, 29),
      checkpointId: 'checkpoint-a',
      userResponse: userResponse,
    );

"""
    if text.count(marker) != 1:
        raise SystemExit('session helper marker mismatch')
    text = text.replace(marker, helper + marker, 1)

test.write_text(text)
