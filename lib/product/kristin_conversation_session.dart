import 'agent_deferred_interaction.dart';
import 'chat_control_plane.dart';
import 'chat_conversation_state.dart';
import 'conversation_orchestrator.dart';
import 'domain.dart';
import 'run_live_signals.dart';
import 'task_kernel/complexity_router.dart';
import 'task_kernel/plan_reconciliation.dart';
import 'task_kernel/planning_failures.dart';
import 'task_kernel/task_specification.dart';
import 'task_kernel/universal_task_plan.dart';

/// Who produced a visible message in the one Kristin conversation.
enum KristinConversationSpeaker { user, assistant, system }

/// A visible conversation message owned by [KristinConversationSession].
///
/// This deliberately contains only user-visible content. Model protocol JSON,
/// hidden planning state, tool traces, and evidence remain separate typed state
/// on the session instead of being smuggled into the transcript.
class KristinConversationMessage {
  const KristinConversationMessage({
    required this.id,
    required this.speaker,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final KristinConversationSpeaker speaker;
  final String text;
  final DateTime createdAt;

  bool get assistant => speaker == KristinConversationSpeaker.assistant;
}

/// Stable, machine-readable failure for conversation ownership invariants.
class KristinConversationSessionException implements Exception {
  const KristinConversationSessionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// The canonical owner of one Kristin conversation.
///
/// Before this type existed, ChatControlPlaneStudio held transcript, selected
/// context, understanding, plan, prepared command, run, and live execution
/// projection as unrelated widget fields. That makes it too easy for a second
/// surface to accidentally create a second truth, or for a new message to
/// orphan a durable run.
///
/// This class is intentionally plain Dart rather than a Widget/ChangeNotifier.
/// UI surfaces may project it however they want, but semantic ownership stays
/// here. ProductRuntime remains the authority for durable execution; this
/// session only owns the conversation-level association with that execution.
class KristinConversationSession {
  KristinConversationSession({
    this.maxMessages = 400,
    this.maxLiveSignals = 600,
    this.maxProtocolCharacters = 18000,
    this.maxToolOutputCharacters = 12000,
  })  : assert(maxMessages > 0),
        assert(maxLiveSignals > 0),
        assert(maxProtocolCharacters > 0),
        assert(maxToolOutputCharacters > 0);

  final int maxMessages;
  final int maxLiveSignals;
  final int maxProtocolCharacters;
  final int maxToolOutputCharacters;

  final List<KristinConversationMessage> _messages =
      <KristinConversationMessage>[];
  final List<LiveRunSignal> _liveSignals = <LiveRunSignal>[];

  String? _selectedProjectId;
  String? _selectedModelId;
  String _composerDraft = '';

  ChatInteractionDecision? _pendingDecision;
  UnderstandingHistory? _understandingHistory;
  TaskSpecification? _taskSpecification;
  RoutingDecision? _routingDecision;
  UniversalTaskPlan? _canonicalPlan;
  PlanningFailure? _planningFailure;
  List<CompletedTaskRecord> _completedTasks = const <CompletedTaskRecord>[];
  PlanReconciliationResult? _lastReconciliation;
  PreparedCommand? _prepared;
  RunRecord? _currentRun;
  AgentDeferredInteraction? _deferredInteraction;
  bool _awaitingPermission = false;
  String _activeRequest = '';

  String _liveAssistantProtocolText = '';
  String _liveAssistantText = '';
  String _liveProgressText = '';
  String _liveToolName = '';
  String _liveToolOutput = '';

  List<KristinConversationMessage> get messages =>
      List<KristinConversationMessage>.unmodifiable(_messages);
  List<LiveRunSignal> get liveSignals =>
      List<LiveRunSignal>.unmodifiable(_liveSignals);

  String? get selectedProjectId => _selectedProjectId;
  String? get selectedModelId => _selectedModelId;
  String get composerDraft => _composerDraft;

  ChatInteractionDecision? get pendingDecision => _pendingDecision;
  UnderstandingHistory? get understandingHistory => _understandingHistory;
  TaskSpecification? get taskSpecification => _taskSpecification;
  RoutingDecision? get routingDecision => _routingDecision;
  UniversalTaskPlan? get canonicalPlan => _canonicalPlan;
  PlanningFailure? get planningFailure => _planningFailure;
  List<CompletedTaskRecord> get completedTasks => _completedTasks;
  PlanReconciliationResult? get lastReconciliation => _lastReconciliation;
  PreparedCommand? get prepared => _prepared;
  RunRecord? get currentRun => _currentRun;
  AgentDeferredInteraction? get deferredInteraction => _deferredInteraction;
  bool get awaitingPermission => _awaitingPermission;
  String get activeRequest => _activeRequest;

  String get liveAssistantProtocolText => _liveAssistantProtocolText;
  String get liveAssistantText => _liveAssistantText;
  String get liveProgressText => _liveProgressText;
  String get liveToolName => _liveToolName;
  String get liveToolOutput => _liveToolOutput;

  ChatConversationState get state => chatConversationSnapshot(
        hasPendingDecision: _pendingDecision != null,
        ambiguous: _pendingDecision?.ambiguous ?? false,
        hasPreparedCommand: _prepared != null,
        awaitingPermission: _awaitingPermission,
        currentRunState: _currentRun?.state,
      );

  bool get runAwaitingApproval =>
      _currentRun?.state == RunState.awaitingApproval;

  bool get awaitingUserInput =>
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

  bool get runExecuting =>
      _currentRun != null &&
      const <RunState>{
        RunState.running,
        RunState.paused,
        RunState.cancelling,
      }.contains(_currentRun!.state);

  bool get hasNonterminalRun => _currentRun != null && !runTerminal;

  bool get runTerminal =>
      _currentRun != null &&
      const <RunState>{
        RunState.succeeded,
        RunState.failed,
        RunState.cancelled,
      }.contains(_currentRun!.state);

  void selectProject(String? projectId) {
    _selectedProjectId = _normalizedOptional(projectId);
  }

  void selectModel(String? modelId) {
    _selectedModelId = _normalizedOptional(modelId);
  }

  void setComposerDraft(String value) {
    _composerDraft = value;
  }

  void setPendingDecision(ChatInteractionDecision? decision) {
    _pendingDecision = decision;
  }

  void setUnderstandingHistory(UnderstandingHistory? history) {
    _understandingHistory = history;
  }

  void setPlanningFailure(PlanningFailure? failure) {
    _planningFailure = failure;
  }

  void setLastReconciliation(PlanReconciliationResult? reconciliation) {
    _lastReconciliation = reconciliation;
  }

  void setActiveRequest(String request) {
    _activeRequest = request.trim();
  }

  KristinConversationMessage addUserMessage(
    String text, {
    DateTime? createdAt,
  }) =>
      _addMessage(KristinConversationSpeaker.user, text, createdAt: createdAt);

  KristinConversationMessage addAssistantMessage(
    String text, {
    DateTime? createdAt,
  }) =>
      _addMessage(
        KristinConversationSpeaker.assistant,
        text,
        createdAt: createdAt,
      );

  KristinConversationMessage addSystemMessage(
    String text, {
    DateTime? createdAt,
  }) =>
      _addMessage(
        KristinConversationSpeaker.system,
        text,
        createdAt: createdAt,
      );

  /// Begins a new governed objective in this conversation.
  ///
  /// Informational side-conversation may still append visible messages while a
  /// run is active, but starting a second governed objective would orphan the
  /// first run's approvals/evidence association. That is rejected here.
  void beginGovernedRequest(String request) {
    if (hasNonterminalRun) {
      throw const KristinConversationSessionException(
        'conversation_run_active',
        'Resolve, stop, or finish the current governed run before starting a different governed request.',
      );
    }
    final normalized = request.trim();
    if (normalized.isEmpty) {
      throw const KristinConversationSessionException(
        'conversation_request_empty',
        'A governed request must not be empty.',
      );
    }
    _activeRequest = normalized;
    _pendingDecision = null;
    _understandingHistory = null;
    _taskSpecification = null;
    _routingDecision = null;
    _canonicalPlan = null;
    _planningFailure = null;
    _completedTasks = const <CompletedTaskRecord>[];
    _lastReconciliation = null;
    _prepared = null;
    _currentRun = null;
    _deferredInteraction = null;
    _awaitingPermission = false;
    clearLiveExecution();
  }

  void setUnderstanding({
    required ChatInteractionDecision decision,
    required UnderstandingHistory history,
    TaskSpecification? specification,
  }) {
    _pendingDecision = decision;
    _understandingHistory = history;
    _taskSpecification = specification;
  }

  void setTaskSpecification(TaskSpecification? specification) {
    _taskSpecification = specification;
  }

  void setRoutingDecision(RoutingDecision? routing) {
    _routingDecision = routing;
  }

  void setCanonicalPlan(
    UniversalTaskPlan? plan, {
    PlanningFailure? failure,
    PlanReconciliationResult? reconciliation,
  }) {
    _canonicalPlan = plan;
    _planningFailure = failure;
    _lastReconciliation = reconciliation;
  }

  void setCompletedTasks(Iterable<CompletedTaskRecord> completed) {
    _completedTasks = List<CompletedTaskRecord>.unmodifiable(completed);
  }

  void setPrepared(PreparedCommand? command, {bool? awaitingPermission}) {
    _prepared = command;
    if (command != null) {
      if (_activeRequest.isEmpty) {
        _activeRequest = command.contract.request;
      }
      _selectedProjectId = command.contract.projectId;
      _selectedModelId = command.model.exactId;
      _awaitingPermission =
          awaitingPermission ?? command.contract.requiredPermissions.isNotEmpty;
    } else {
      _awaitingPermission = awaitingPermission ?? false;
    }
  }

  /// Restores the durable run association after startup/navigation.
  ///
  /// A different non-terminal run cannot silently replace the one already
  /// attached to this conversation. That protects permission prompts,
  /// steering, and evidence from becoming associated with the wrong task.
  void restoreRun(RunRecord run) {
    _attachRun(run, restoring: true);
  }

  /// Applies a refreshed record for the currently attached durable run.
  void updateRun(RunRecord run) {
    _attachRun(run, restoring: false);
  }

  /// Detaches a finished/no-run governed turn without erasing conversation
  /// history or the user's selected project/model context.
  ///
  /// This is the compatibility boundary for legacy Chat `currentRun = null`
  /// assignments. It fails closed while unfinished durable work is attached.
  bool detachFinishedRun() {
    if (hasNonterminalRun) return false;
    _composerDraft = '';
    _pendingDecision = null;
    _understandingHistory = null;
    _taskSpecification = null;
    _routingDecision = null;
    _canonicalPlan = null;
    _planningFailure = null;
    _completedTasks = const <CompletedTaskRecord>[];
    _lastReconciliation = null;
    _prepared = null;
    _currentRun = null;
    _deferredInteraction = null;
    _awaitingPermission = false;
    _activeRequest = '';
    clearLiveExecution();
    return true;
  }

  void setAwaitingPermission(bool value) {
    _awaitingPermission = value;
  }

  void setDeferredInteraction(AgentDeferredInteraction? interaction) {
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

  /// Records one live execution signal and updates the compact live
  /// projection used by Chat. Returns false for signals belonging to a
  /// different run, preventing cross-run UI contamination.
  bool recordLiveSignal(LiveRunSignal signal) {
    final run = _currentRun;
    if (run == null || signal.runId != run.id) return false;

    _liveSignals.add(signal);
    if (_liveSignals.length > maxLiveSignals) {
      _liveSignals.removeRange(0, _liveSignals.length - maxLiveSignals);
    }

    switch (signal.kind) {
      case LiveRunSignalKind.modelTextDelta:
        final delta = signal.data['delta']?.toString() ?? '';
        _liveAssistantProtocolText = '$_liveAssistantProtocolText$delta';
        if (_liveAssistantProtocolText.length > maxProtocolCharacters) {
          _liveAssistantProtocolText = _liveAssistantProtocolText.substring(
            _liveAssistantProtocolText.length - maxProtocolCharacters,
          );
        }
        _liveAssistantText = ConversationStreamProjector.visibleText(
          _liveAssistantProtocolText,
        );
        break;
      case LiveRunSignalKind.modelProgress:
      case LiveRunSignalKind.phase:
      case LiveRunSignalKind.preflight:
        _liveProgressText = signal.data['message']?.toString() ?? '';
        break;
      case LiveRunSignalKind.toolStarted:
        _liveToolName = signal.data['tool']?.toString() ?? 'tool';
        _liveToolOutput = '';
        break;
      case LiveRunSignalKind.toolOutput:
        _liveToolName = signal.data['tool']?.toString() ?? _liveToolName;
        final delta = signal.data['delta']?.toString() ?? '';
        _liveToolOutput = '$_liveToolOutput$delta';
        if (_liveToolOutput.length > maxToolOutputCharacters) {
          _liveToolOutput = _liveToolOutput.substring(
            _liveToolOutput.length - maxToolOutputCharacters,
          );
        }
        break;
      case LiveRunSignalKind.toolCompleted:
        _liveToolName = signal.data['tool']?.toString() ?? _liveToolName;
        final output = signal.data['output']?.toString() ?? '';
        if (output.isNotEmpty) {
          _liveToolOutput = output.length <= maxToolOutputCharacters
              ? output
              : output.substring(output.length - maxToolOutputCharacters);
        }
        break;
      case LiveRunSignalKind.toolFailed:
        _liveToolName = signal.data['tool']?.toString() ?? _liveToolName;
        final detail = signal.data['detail']?.toString() ?? '';
        _liveToolOutput = detail.length <= maxToolOutputCharacters
            ? detail
            : detail.substring(detail.length - maxToolOutputCharacters);
        break;
      case LiveRunSignalKind.steeringQueued:
        _liveProgressText =
            'Your new direction is queued for the next safe step.';
        break;
      case LiveRunSignalKind.steeringApplied:
        _liveProgressText = 'Your new direction was applied.';
        break;
      case LiveRunSignalKind.heartbeat:
        break;
    }
    return true;
  }

  /// Starts a fresh UI projection for the currently attached execution.
  ///
  /// This is projection state only: it grants no execution authority and does
  /// not change the durable run. Incoming [LiveRunSignal] values remain the
  /// source of truth once execution begins emitting them.
  void beginLiveExecution() {
    clearLiveExecution();
    _liveProgressText = 'Starting the first safe step.';
  }

  /// Updates an optimistic user-visible execution message without changing
  /// durable run state or execution authority. Live signals may subsequently
  /// replace this projection with runtime-reported progress.
  void showLiveProgress(String message) {
    _liveProgressText = message;
  }

  void clearLiveExecution() {
    _liveSignals.clear();
    _liveAssistantProtocolText = '';
    _liveAssistantText = '';
    _liveProgressText = '';
    _liveToolName = '';
    _liveToolOutput = '';
  }

  /// Starts a genuinely new conversation while preserving the user's selected
  /// project/model context. A non-terminal durable run must be resolved first.
  void resetForNewConversation() {
    if (!detachFinishedRun()) {
      throw const KristinConversationSessionException(
        'conversation_run_active',
        'A new conversation cannot orphan an unfinished governed run.',
      );
    }
    _messages.clear();
  }

  KristinConversationMessage _addMessage(
    KristinConversationSpeaker speaker,
    String text, {
    DateTime? createdAt,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw const KristinConversationSessionException(
        'conversation_message_empty',
        'A visible conversation message must not be empty.',
      );
    }
    final message = KristinConversationMessage(
      id: newId('chat_message'),
      speaker: speaker,
      text: normalized,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
    );
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    return message;
  }

  void _attachRun(RunRecord run, {required bool restoring}) {
    final existing = _currentRun;
    if (existing != null && existing.id != run.id && hasNonterminalRun) {
      throw KristinConversationSessionException(
        'conversation_run_mismatch',
        'Run ${run.id} cannot replace unfinished run ${existing.id} in the same conversation.',
      );
    }
    if (!restoring && existing != null && existing.id != run.id) {
      throw KristinConversationSessionException(
        'conversation_run_mismatch',
        'A run refresh must keep the current run identity (${existing.id}).',
      );
    }
    _currentRun = run;
    _prepared = run.command;
    _activeRequest = run.command.contract.request;
    _selectedProjectId = run.command.contract.projectId;
    _selectedModelId = run.command.model.exactId;
    _awaitingPermission = run.state == RunState.awaitingApproval;
    final replacingRun = existing == null || existing.id != run.id;
    if (runTerminal || replacingRun) {
      _deferredInteraction = null;
    }
    if (replacingRun) {
      clearLiveExecution();
    }
  }

  String? _normalizedOptional(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
