from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: unexpected {label} source shape: {count} matches')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


runtime = Path('lib/product/product_runtime.dart')
replace_once(
    runtime,
    "import 'browser/browser_runtime.dart';\nimport 'capability_doctor.dart';\n",
    "import 'browser/browser_runtime.dart';\nimport 'agent_deferred_interaction.dart';\nimport 'capability_doctor.dart';\n",
    'deferred interaction import',
)
replace_once(
    runtime,
    """  Future<RunRecord> execute(String runId) => runs.execute(runId);
  Future<void> pause(String runId) => runs.pause(runId);
  Future<void> resume(String runId) => runs.resume(runId);
  Future<void> cancel(String runId) => runs.cancel(runId);

""",
    """  Future<RunRecord> execute(String runId) => runs.execute(runId);
  Future<void> pause(String runId) => runs.pause(runId);
  Future<void> resume(String runId) => runs.resume(runId);
  Future<void> cancel(String runId) => runs.cancel(runId);

  Future<AgentDeferredInteraction?> latestDeferredInteraction(String runId) =>
      AgentDeferredInteractionStore(repositories.workflow).latestForRun(runId);

  Future<AgentDeferredInteraction?> pendingDeferredInteraction(String runId) =>
      AgentDeferredInteractionStore(repositories.workflow).pendingForRun(runId);

  Future<AgentDeferredInteraction> recordDeferredUserResponse({
    required String runId,
    required String response,
  }) =>
      AgentDeferredInteractionStore(repositories.workflow).recordUserResponse(
        runId: runId,
        response: response,
      );

""",
    'runtime deferred APIs',
)

chat = Path('lib/product/chat_control_plane_studio.dart')
replace_once(
    chat,
    "import 'domain.dart';\nimport 'models_research.dart';\n",
    "import 'domain.dart';\nimport 'kristin_conversation_session.dart';\nimport 'models_research.dart';\n",
    'session import',
)
replace_once(
    chat,
    """  final FocusNode composerFocus = FocusNode();

  final List<_ChatLine> transcript = <_ChatLine>[];
""",
    """  final FocusNode composerFocus = FocusNode();
  final KristinConversationSession conversationSession =
      KristinConversationSession();

  final List<_ChatLine> transcript = <_ChatLine>[];
""",
    'session owner field',
)
replace_once(
    chat,
    """  bool understandingAdjusting = false;
  bool planAdjusting = false;
  bool awaitingPermission = false;
  bool detailsExpanded = false;
""",
    """  bool understandingAdjusting = false;
  bool planAdjusting = false;
  bool detailsExpanded = false;
""",
    'remove permission duplicate',
)
replace_once(
    chat,
    """  PlanReconciliationResult? lastReconciliation;
  RunRecord? currentRun;
  String activeRequest = '';
""",
    """  PlanReconciliationResult? lastReconciliation;
  String activeRequest = '';
""",
    'remove run duplicate',
)
replace_once(
    chat,
    """  ProductRuntime get runtime => widget.runtime;

  ChatActionDispatcher get dispatcher =>
""",
    """  ProductRuntime get runtime => widget.runtime;

  RunRecord? get currentRun => conversationSession.currentRun;
  set currentRun(RunRecord? value) {
    final existing = conversationSession.currentRun;
    if (value == null) {
      // Transitional compatibility for the remaining Chat fields: a legacy
      // null assignment may clear a finished/no-run association, but it can
      // never orphan unfinished durable work.
      if (!conversationSession.hasNonterminalRun) {
        conversationSession.resetForNewConversation();
      }
      return;
    }
    if (existing != null && existing.id == value.id) {
      conversationSession.updateRun(value);
    } else {
      conversationSession.restoreRun(value);
    }
  }

  bool get awaitingPermission => conversationSession.awaitingPermission;
  set awaitingPermission(bool value) =>
      conversationSession.setAwaitingPermission(value);

  ChatActionDispatcher get dispatcher =>
""",
    'session run compatibility projection',
)
replace_once(
    chat,
    """  bool get runAwaitingApproval =>
      currentRun?.state == RunState.awaitingApproval;
""",
    """  bool get runAwaitingApproval => conversationSession.runAwaitingApproval;
""",
    'approval projection',
)
replace_once(
    chat,
    """  bool get runExecuting =>
      currentRun != null &&
      const <RunState>{
        RunState.running,
        RunState.paused,
        RunState.cancelling,
      }.contains(currentRun!.state);
""",
    """  bool get runExecuting => conversationSession.runExecuting;
""",
    'executing projection',
)
replace_once(
    chat,
    """  bool get hasNonterminalRun =>
      currentRun != null &&
      const <RunState>{
        RunState.awaitingApproval,
        RunState.running,
        RunState.paused,
        RunState.cancelling,
        RunState.interrupted,
      }.contains(currentRun!.state);

  bool get runTerminal =>
      currentRun != null &&
      const <RunState>{
        RunState.succeeded,
        RunState.failed,
        RunState.cancelled,
      }.contains(currentRun!.state);
""",
    """  bool get hasNonterminalRun => conversationSession.hasNonterminalRun;

  bool get runTerminal => conversationSession.runTerminal;
""",
    'nonterminal projections',
)
replace_once(
    chat,
    """      final durable = runs.where((run) {
        return const <RunState>{
          RunState.awaitingApproval,
          RunState.running,
          RunState.paused,
          RunState.interrupted,
        }.contains(run.state);
      }).firstOrNull;
      if (durable != null) {
        currentRun = durable;
        prepared = durable.command;
""",
    """      final durable = runs.where((run) {
        return !const <RunState>{
          RunState.succeeded,
          RunState.failed,
          RunState.cancelled,
        }.contains(run.state);
      }).firstOrNull;
      if (durable != null) {
        currentRun = durable;
        conversationSession.setDeferredInteraction(
          await runtime.latestDeferredInteraction(durable.id),
        );
        prepared = durable.command;
""",
    'durable restore',
)
replace_once(
    chat,
    """    _mutate(() {
      loading = false;
      status = runAwaitingApproval
          ? 'Permission review required'
          : runExecuting
              ? 'Continuing active work'
              : 'Kristin is ready';
    });
""",
    """    _mutate(() {
      loading = false;
      status = conversationSession.awaitingUserInput
          ? conversationSession.deferredUserPrompt ??
              'Kristin needs your input before continuing.'
          : runAwaitingApproval
              ? 'Permission review required'
              : runExecuting
                  ? 'Continuing active work'
                  : 'Kristin is ready';
    });
""",
    'load status',
)
replace_once(
    chat,
    """    final loadedEvidence =
        newTerminal ? await runtime.evidenceForRun(refreshed.id) : evidence;
    _mutate(() {
      currentRun = refreshed;
      evidence = loadedEvidence;
""",
    """    final loadedEvidence =
        newTerminal ? await runtime.evidenceForRun(refreshed.id) : evidence;
    final deferred = newTerminal
        ? null
        : await runtime.latestDeferredInteraction(refreshed.id);
    _mutate(() {
      currentRun = refreshed;
      conversationSession.setDeferredInteraction(deferred);
      evidence = loadedEvidence;
""",
    'refresh deferred restore',
)
replace_once(
    chat,
    """      awaitingPermission = refreshed.state == RunState.awaitingApproval;
      if (newTerminal) {
        status = refreshed.state == RunState.succeeded
            ? 'Finished and verified'
            : 'Execution stopped safely';
      }
""",
    """      awaitingPermission = refreshed.state == RunState.awaitingApproval;
      if (conversationSession.awaitingUserInput) {
        status = conversationSession.deferredUserPrompt ??
            'Kristin needs your input before continuing.';
      } else if (newTerminal) {
        status = refreshed.state == RunState.succeeded
            ? 'Finished and verified'
            : 'Execution stopped safely';
      }
""",
    'refresh status',
)
replace_once(
    chat,
    """    final decision = intentCompiler.compile(
      request,
      inferredMode: mode,
      knownTargets: _knownTargets(),
    );

    if (runExecuting) {
""",
    """    final decision = intentCompiler.compile(
      request,
      inferredMode: mode,
      knownTargets: _knownTargets(),
    );

    if (conversationSession.awaitingUserInput) {
      final run = currentRun;
      if (run == null) {
        conversationSession.setDeferredInteraction(null);
      } else if (_isActiveRunCancellation(request, decision)) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        await _controlRun('cancel');
        return;
      } else {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        final resolved = await _perform(
          'Recording your answer',
          () => runtime.recordDeferredUserResponse(
            runId: run.id,
            response: request,
          ),
        );
        if (resolved == null || !mounted) return;
        _mutate(() {
          conversationSession.setDeferredInteraction(resolved);
          liveProgressText = 'Continuing with your answer.';
          status = 'Continuing with your answer';
        });
        await _perform<void>(
          'Continuing with your answer',
          () => runtime.resume(run.id),
        );
        await _refreshCurrentRun();
        return;
      }
    }

    if (runExecuting) {
""",
    'takeover submit branch',
)

view = Path('lib/product/chat_control_plane_studio_view.dart')
replace_once(
    view,
    """  Widget _statusStrip() {
    final startup = widget.startupError;
    if (startup == null && error == null && !busy && !runExecuting) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final failing = startup != null || error != null;
""",
    """  Widget _statusStrip() {
    final startup = widget.startupError;
    final waitingForInput = conversationSession.awaitingUserInput;
    if (startup == null &&
        error == null &&
        !busy &&
        !runExecuting &&
        !waitingForInput) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final failing = startup != null || error != null;
""",
    'status waiting state',
)
replace_once(
    view,
    """            if (busy || runExecuting)
              const SizedBox.square(
""",
    """            if ((busy || runExecuting) && !waitingForInput)
              const SizedBox.square(
""",
    'status spinner',
)
replace_once(
    view,
    """            Expanded(child: Text(startup ?? error ?? status)),
""",
    """            Expanded(
              child: Text(
                startup ??
                    error ??
                    (waitingForInput
                        ? conversationSession.deferredUserPrompt ?? status
                        : status),
              ),
            ),
""",
    'status prompt',
)
replace_once(
    view,
    """          const SizedBox(height: 12),
          if (showModelAnswer)
            SelectableText(liveAssistantText)
          else ...<Widget>[
""",
    """          const SizedBox(height: 12),
          if (conversationSession.awaitingUserInput) ...<Widget>[
            Text(
              conversationSession.deferredUserPrompt ??
                  'Kristin needs your input before continuing.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Reply in the composer. Your answer supplies intent context only and does not grant new permissions or authority.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
          ],
          if (showModelAnswer)
            SelectableText(liveAssistantText)
          else ...<Widget>[
""",
    'run card takeover prompt',
)
replace_once(
    view,
    """              if (run.state == RunState.paused ||
                  run.state == RunState.interrupted)
                FilledButton.icon(
""",
    """              if ((run.state == RunState.paused ||
                      run.state == RunState.interrupted) &&
                  !conversationSession.awaitingUserInput)
                FilledButton.icon(
""",
    'disable resume while awaiting response',
)

test = Path('test/product/chat_deferred_takeover_bridge_test.dart')
test.write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chat;
  late String view;
  late String runtime;

  setUpAll(() {
    chat = File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    view = File('lib/product/chat_control_plane_studio_view.dart').readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
  });

  test('Chat run and permission projection are owned by the canonical session', () {
    expect(chat, contains("import 'kristin_conversation_session.dart';"));
    expect(chat, contains('final KristinConversationSession conversationSession ='));
    expect(chat, isNot(contains('RunRecord? currentRun;')));
    expect(chat, isNot(contains('bool awaitingPermission = false;')));
    expect(chat, contains('RunRecord? get currentRun => conversationSession.currentRun;'));
    expect(chat, contains('bool get awaitingPermission => conversationSession.awaitingPermission;'));
    expect(chat, contains('bool get hasNonterminalRun => conversationSession.hasNonterminalRun;'));
  });

  test('startup and refresh restore the durable deferred interaction', () {
    expect(
      RegExp(r'latestDeferredInteraction\\(').allMatches(chat).length,
      greaterThanOrEqualTo(2),
    );
    expect(chat, contains('conversationSession.setDeferredInteraction('));
    expect(chat, contains('RunState.prepared'));
    expect(chat, contains('RunState.queued'));
    expect(chat, contains('RunState.cancelling'));
  });

  test('takeover answer is recorded and resumed before ordinary steering', () {
    final takeover = chat.indexOf('if (conversationSession.awaitingUserInput) {');
    final record = chat.indexOf('runtime.recordDeferredUserResponse(');
    final resume = chat.indexOf('() => runtime.resume(run.id)');
    final steering = chat.indexOf('runtime.steerRun(currentRun!.id, request)');
    expect(takeover, greaterThanOrEqualTo(0));
    expect(record, greaterThan(takeover));
    expect(resume, greaterThan(record));
    expect(steering, greaterThan(resume));
    expect(chat, contains('conversationSession.setDeferredInteraction(resolved);'));
  });

  test('ProductRuntime exposes only durable deferred interaction operations', () {
    expect(runtime, contains("import 'agent_deferred_interaction.dart';"));
    expect(runtime, contains('Future<AgentDeferredInteraction?> latestDeferredInteraction('));
    expect(runtime, contains('Future<AgentDeferredInteraction?> pendingDeferredInteraction('));
    expect(runtime, contains('Future<AgentDeferredInteraction> recordDeferredUserResponse({'));
    expect(runtime, contains('AgentDeferredInteractionStore(repositories.workflow)'));
  });

  test('takeover prompt is visible and manual resume is hidden while pending', () {
    expect(view, contains('conversationSession.deferredUserPrompt'));
    expect(view, contains('Your answer supplies intent context only and does not grant new permissions or authority.'));
    expect(view, contains('!conversationSession.awaitingUserInput'));
    expect(view, contains('final waitingForInput = conversationSession.awaitingUserInput;'));
  });
}
""",
    encoding='utf-8',
    newline='\n',
)
