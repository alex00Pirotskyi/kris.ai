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
import 'task_kernel/task_understanding.dart';
import 'task_kernel/universal_task_plan.dart';

/// Who produced a visible message in the one Kristin conversation.
enum KristinConversationSpeaker { user, assistant, system }

/// How the current plan came to be. This belongs to the canonical
/// conversation session rather than a particular Chat surface.
enum ChatPlanningPath {
  deterministic,
  model,
  fallback,
}

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

class KristinConversationSessionException implements Exception {
  const KristinConversationSessionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Canonical owner of one Kristin conversation.
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
  final List<String> _clarificationEvidence = <String>[];

  String? _selectedProjectId;
  String? _selectedModelId;
  String _composerDraft = '';

  ChatInteractionDecision? _pendingDecision;
  UnderstandingHistory? _understandingHistory;
  TaskSpecification? _taskSpecification;
  UnderstandingPath _understandingPath = UnderstandingPath.deterministic;
  List<String> _understandingRejections = const <String>[];
  RoutingDecision? _routingDecision;
  UniversalTaskPlan? _canonicalPlan;
  PlanningFailure? _planningFailure;
  ChatPlanningPath _planningPath = ChatPlanningPath.deterministic;
  List<CompletedTaskRecord> _completedTasks = const <CompletedTaskRecord>[];
  PlanReconciliationResult? _lastReconciliation;
  PreparedCommand? _prepared;
  RunRecord? _currentRun;
  AgentDeferredInteraction? _deferredInteraction;
  bool _awaitingPermission = false;
  String _activeRequest = '';
  ProjectProcessStatus? _projectProcessStatus;
  ChatConversationState _state = const ChatIdle();

  String _liveAssistantProtocolText = '';
  String _liveAssistantText = '';
  String _liveProgressText = '';
  String _liveToolName = '';
  String _liveToolOutput = '';

  bool _assistantResponseActive = false;
  String _assistantResponseProtocolText = '';
  String? _streamingAssistantMessageId;

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
  UnderstandingPath get understandingPath => _understandingPath;
  List<String> get understandingRejections =>
      List<String>.unmodifiable(_understandingRejections);
  List<String> get clarificationEvidence =>
      List<String>.unmodifiable(_clarificationEvidence);
  String get clarificationEvidenceText => _clarificationEvidence.join('\n\n');
  RoutingDecision? get routingDecision => _routingDecision;
  UniversalTaskPlan? get canonicalPlan => _canonicalPlan;
  PlanningFailure? get planningFailure => _planningFailure;
  ChatPlanningPath get planningPath => _planningPath;
  List<CompletedTaskRecord> get completedTasks => _completedTasks;
  PlanReconciliationResult? get lastReconciliation => _lastReconciliation;
  PreparedCommand? get prepared => _prepared;
  RunRecord? get currentRun => _currentRun;
  AgentDeferredInteraction? get deferredInteraction => _deferredInteraction;
  bool get awaitingPermission => _awaitingPermission;
  String get activeRequest => _activeRequest;
  ProjectProcessStatus? get projectProcessStatus => _projectProcessStatus;

  String get liveAssistantProtocolText => _liveAssistantProtocolText;
  String get liveAssistantText => _liveAssistantText;
  String get liveProgressText => _liveProgressText;
  String get liveToolName => _liveToolName;
  String get liveToolOutput => _liveToolOutput;
  bool get assistantResponseStreaming => _assistantResponseActive;

  /// Authoritative conversation state.
  ChatConversationState get state => _state;

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
    final normalized = _normalizedOptional(projectId);
    if (_selectedProjectId != normalized) {
      _projectProcessStatus = null;
    }
    _selectedProjectId = normalized;
  }

  void selectModel(String? modelId) {
    _selectedModelId = _normalizedOptional(modelId);
  }

  void setComposerDraft(String value) {
    _composerDraft = value;
  }

  void setPendingDecision(ChatInteractionDecision? decision) {
    _pendingDecision = decision;
    _synchronizeConversationState();
  }

  void setUnderstandingHistory(UnderstandingHistory? history) {
    _understandingHistory = history;
  }

  void setUnderstandingMetadata({
    required UnderstandingPath path,
    required Iterable<String> rejections,
  }) {
    _understandingPath = path;
    _understandingRejections = List<String>.unmodifiable(rejections);
  }

  void recordClarificationAnswer({
    required String question,
    required String answer,
  }) {
    final normalizedQuestion = question.trim();
    final normalizedAnswer = answer.trim();
    if (normalizedQuestion.isEmpty || normalizedAnswer.isEmpty) {
      throw const KristinConversationSessionException(
        'conversation_clarification_empty',
        'A clarification question and answer must both be non-empty.',
      );
    }
    _clarificationEvidence.add(
      'Question: $normalizedQuestion\nUser answer: $normalizedAnswer',
    );
    if (_clarificationEvidence.length > 12) {
      _clarificationEvidence.removeRange(
        0,
        _clarificationEvidence.length - 12,
      );
    }
  }

  void setPlanningPath(ChatPlanningPath path) {
    _planningPath = path;
  }

  void setProjectProcessStatus(ProjectProcessStatus? status) {
    if (status != null &&
        _selectedProjectId != null &&
        status.projectId != _selectedProjectId) {
      throw KristinConversationSessionException(
        'conversation_project_process_mismatch',
        'Process status for ${status.projectId} does not belong to selected project $_selectedProjectId.',
      );
    }
    _projectProcessStatus = status;
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

  /// Starts a provisional assistant transcript message backed by actual model
  /// deltas. Until a visible delta arrives no placeholder is inserted; the UI
  /// may truthfully show its ordinary busy/Thinking state instead.
  void beginAssistantResponse() {
    cancelAssistantResponse();
    _assistantResponseActive = true;
  }

  /// Appends a real provider delta and updates the same visible transcript
  /// message. JSON protocol envelopes are projected incrementally through the
  /// same projector used for Runner model output.
  void recordAssistantResponseDelta(String delta) {
    if (delta.isEmpty) return;
    if (!_assistantResponseActive) beginAssistantResponse();
    _assistantResponseProtocolText = '$_assistantResponseProtocolText$delta';
    if (_assistantResponseProtocolText.length > maxProtocolCharacters) {
      _assistantResponseProtocolText = _assistantResponseProtocolText.substring(
        _assistantResponseProtocolText.length - maxProtocolCharacters,
      );
    }
    final visible = ConversationStreamProjector.visibleText(
      _assistantResponseProtocolText,
    ).trim();
    if (visible.isEmpty) return;
    final messageId = _streamingAssistantMessageId;
    if (messageId == null) {
      final message = _addMessage(
        KristinConversationSpeaker.assistant,
        visible,
      );
      _streamingAssistantMessageId = message.id;
      return;
    }
    _replaceMessageText(messageId, visible);
  }

  /// Seals the provisional response as one ordinary assistant transcript
  /// message. A non-streaming provider reaches this method with no provisional
  /// message, so it simply appends the final answer once.
  void finishAssistantResponse(String visibleText) {
    final normalized = visibleText.trim();
    final messageId = _streamingAssistantMessageId;
    if (normalized.isNotEmpty) {
      if (messageId == null) {
        _addMessage(KristinConversationSpeaker.assistant, normalized);
      } else {
        _replaceMessageText(messageId, normalized);
      }
    } else if (messageId != null) {
      _messages.removeWhere((message) => message.id == messageId);
    }
    _assistantResponseActive = false;
    _assistantResponseProtocolText = '';
    _streamingAssistantMessageId = null;
  }

  /// Removes an incomplete provisional answer after a failed/cancelled model
  /// call rather than leaving partial JSON or a half sentence as final truth.
  void cancelAssistantResponse() {
    final messageId = _streamingAssistantMessageId;
    if (messageId != null) {
      _messages.removeWhere((message) => message.id == messageId);
    }
    _assistantResponseActive = false;
    _assistantResponseProtocolText = '';
    _streamingAssistantMessageId = null;
  }

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
    cancelAssistantResponse();
    _activeRequest = normalized;
    _pendingDecision = null;
    _understandingHistory = null;
    _taskSpecification = null;
    _understandingPath = UnderstandingPath.deterministic;
    _understandingRejections = const <String>[];
    _clarificationEvidence.clear();
    _routingDecision = null;
    _canonicalPlan = null;
    _planningFailure = null;
    _planningPath = ChatPlanningPath.deterministic;
    _completedTasks = const <CompletedTaskRecord>[];
    _lastReconciliation = null;
    _prepared = null;
    _currentRun = null;
    _deferredInteraction = null;
    _awaitingPermission = false;
    _state = const ChatInterpreting();
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
    _state = decision.ambiguous
        ? const ChatClarificationNeeded()
        : const ChatUnderstanding();
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
      selectProject(command.contract.projectId);
      _selectedModelId = command.model.exactId;
      _awaitingPermission =
          awaitingPermission ?? command.contract.requiredPermissions.isNotEmpty;
    } else {
      _awaitingPermission = awaitingPermission ?? false;
    }
    _synchronizeConversationState();
  }

  void restoreRun(RunRecord run) {
    _attachRun(run, restoring: true);
  }

  void updateRun(RunRecord run) {
    _attachRun(run, restoring: false);
  }

  bool detachFinishedRun() {
    if (hasNonterminalRun) return false;
    cancelAssistantResponse();
    _composerDraft = '';
    _pendingDecision = null;
    _understandingHistory = null;
    _taskSpecification = null;
    _understandingPath = UnderstandingPath.deterministic;
    _understandingRejections = const <String>[];
    _clarificationEvidence.clear();
    _routingDecision = null;
    _canonicalPlan = null;
    _planningFailure = null;
    _planningPath = ChatPlanningPath.deterministic;
    _completedTasks = const <CompletedTaskRecord>[];
    _lastReconciliation = null;
    _prepared = null;
    _currentRun = null;
    _deferredInteraction = null;
    _awaitingPermission = false;
    _activeRequest = '';
    _state = const ChatIdle();
    clearLiveExecution();
    return true;
  }

  void setAwaitingPermission(bool value) {
    _awaitingPermission = value;
    _synchronizeConversationState();
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

  void beginLiveExecution() {
    clearLiveExecution();
    _liveProgressText = 'Starting the first safe step.';
  }

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

  void _replaceMessageText(String messageId, String text) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) {
      final replacement = _addMessage(
        KristinConversationSpeaker.assistant,
        text,
      );
      _streamingAssistantMessageId = replacement.id;
      return;
    }
    final current = _messages[index];
    _messages[index] = KristinConversationMessage(
      id: current.id,
      speaker: current.speaker,
      text: text.trim(),
      createdAt: current.createdAt,
    );
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
    selectProject(run.command.contract.projectId);
    _selectedModelId = run.command.model.exactId;
    _awaitingPermission = run.state == RunState.awaitingApproval;
    final replacingRun = existing == null || existing.id != run.id;
    if (runTerminal || replacingRun) {
      _deferredInteraction = null;
    }
    if (replacingRun) {
      clearLiveExecution();
    }
    _synchronizeConversationState();
  }

  void _synchronizeConversationState() {
    _state = chatConversationSnapshot(
      hasPendingDecision: _pendingDecision != null,
      ambiguous: _pendingDecision?.ambiguous ?? false,
      hasPreparedCommand: _prepared != null,
      awaitingPermission: _awaitingPermission,
      currentRunState: _currentRun?.state,
    );
  }

  String? _normalizedOptional(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
