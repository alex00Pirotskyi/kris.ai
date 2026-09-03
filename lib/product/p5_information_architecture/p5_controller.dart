import 'package:flutter/foundation.dart';

import 'p5_fixtures.dart';
import 'p5_models.dart';
import 'p5_shell_layout.dart';

class P5InformationArchitectureController extends ChangeNotifier {
  P5InformationArchitectureController({
    P5PresentationState? initialState,
    P5ShellLayoutState? initialShellLayout,
  }) : _state = initialState ?? P5PrototypeFixtures.initialState(),
       _shellLayout = initialShellLayout ?? P5ShellLayoutState.defaults;

  P5PresentationState _state;
  P5ShellLayoutState _shellLayout;
  P5PresentationState get state => _state;
  P5ShellLayoutState get shellLayout => _shellLayout;

  void updateShellLayout(P5ShellLayoutState next) {
    final normalized = next.normalized();
    if (_shellLayout == normalized) {
      return;
    }
    _shellLayout = normalized;
    notifyListeners();
  }

  P5SideEffectLedger get sideEffects => P5SideEffectLedger.zero;

  bool get canGoBack => _findEligibleHistoryIndex(-1) != null;
  bool get canGoForward => _findEligibleHistoryIndex(1) != null;

  bool get canChangePlanOnly =>
      _state.selectedRunId == null &&
      const <P5RunPresentationState>{
        P5RunPresentationState.planReady,
        P5RunPresentationState.planOnly,
        P5RunPresentationState.ready,
        P5RunPresentationState.blocked,
      }.contains(_state.runState);

  bool get canReviewPlan => !_runLifecycleLocked;
  bool get canStartRun => !_runLifecycleLocked && _state.selectedRunId == null;
  bool get canEditTaskDraft => !_runContextLocked;
  bool get canChangeProjectContext => !_runContextLocked;
  bool get canSelectSavedRun => !_runContextLocked;
  bool get canEditComposerContext => !_runContextLocked;
  bool get canLaunchComposer =>
      !_runLifecycleLocked && _state.selectedRunId == null;

  bool get _runLifecycleLocked => const <P5RunPresentationState>{
    P5RunPresentationState.running,
    P5RunPresentationState.paused,
    P5RunPresentationState.stopping,
    P5RunPresentationState.interrupted,
  }.contains(_state.runState);

  bool get _runContextLocked => const <P5RunPresentationState>{
    P5RunPresentationState.running,
    P5RunPresentationState.paused,
    P5RunPresentationState.stopping,
  }.contains(_state.runState);

  List<P5WorkspaceDefinition> get visibleWorkspaces {
    return P5PrototypeFixtures.workspaces
        .where((definition) {
          if (definition.id.isFutureCapability) {
            return false;
          }
          return _isWorkspaceEligibleAt(definition.id, _state.experienceLevel);
        })
        .toList(growable: false);
  }

  void changeExperienceLevel(P5ExperienceLevel level) {
    if (level == _state.experienceLevel) {
      return;
    }

    final currentWorkspace = _state.workspace;
    final currentRemainsEligible = _isWorkspaceEligibleAt(
      currentWorkspace,
      level,
    );

    if (!currentRemainsEligible) {
      _state = _state.copyWith(
        experienceLevel: level,
        workspace: P5WorkspaceId.homeChat,
        navigationHistory: const <P5WorkspaceId>[P5WorkspaceId.homeChat],
        navigationIndex: 0,
        reopenWorkspace: P5WorkspaceId.homeChat,
        recoveryMessage:
            '${currentWorkspace.label} requires ${_minimumLevel(currentWorkspace).label} mode. Returned to Home / Chat.',
      );
      notifyListeners();
      return;
    }

    final sanitizedHistory = _state.navigationHistory
        .take(_state.navigationIndex + 1)
        .where((workspace) => _isWorkspaceEligibleAt(workspace, level))
        .toList(growable: true);
    if (sanitizedHistory.isEmpty || sanitizedHistory.last != currentWorkspace) {
      sanitizedHistory.add(currentWorkspace);
    }

    final recoveryMessage = _state.recoveryMessage;
    final clearsResolvedExperienceWarning = _isResolvedExperienceWarning(
      recoveryMessage,
      level,
    );

    _state = _state.copyWith(
      experienceLevel: level,
      navigationHistory: List<P5WorkspaceId>.unmodifiable(sanitizedHistory),
      navigationIndex: sanitizedHistory.length - 1,
      reopenWorkspace: currentWorkspace,
      recoveryMessage: clearsResolvedExperienceWarning ? null : recoveryMessage,
    );
    notifyListeners();
  }

  void updateTaskDraft(String value) {
    if (value == _state.taskDraft) {
      return;
    }
    if (_runContextLocked) {
      _state = _state.copyWith(
        recoveryMessage:
            'Task context cannot change while a simulated run is active. Use the run controls first.',
      );
      notifyListeners();
      return;
    }
    _state = _state.copyWith(taskDraft: value, planReviewed: false);
    notifyListeners();
  }

  void updateComposerProfile(P5ComposerProfile value) {
    if (_composerMutationBlocked() || value == _state.composerProfile) {
      return;
    }
    _commitComposerMutation(_state.copyWith(composerProfile: value));
  }

  void updateComposerModel(P5ComposerModel value) {
    if (_composerMutationBlocked() || value == _state.composerModel) {
      return;
    }
    _commitComposerMutation(_state.copyWith(composerModel: value));
  }

  void updateComposerAccess(P5ComposerAccess value) {
    if (_composerMutationBlocked() || value == _state.composerAccess) {
      return;
    }
    _commitComposerMutation(_state.copyWith(composerAccess: value));
  }

  void updateComposerLaunchTiming(P5ComposerLaunchTiming value) {
    if (_composerMutationBlocked() || value == _state.composerLaunchTiming) {
      return;
    }
    _commitComposerMutation(_state.copyWith(composerLaunchTiming: value));
  }

  void updateComposerBudget(P5ComposerBudget value) {
    if (_composerMutationBlocked() || value == _state.composerBudget) {
      return;
    }
    _commitComposerMutation(_state.copyWith(composerBudget: value));
  }

  void updateComposerAttachments(Iterable<String> values) {
    if (_composerMutationBlocked()) {
      return;
    }
    final normalized = _boundedComposerValues(
      values,
      maxItems: 8,
      maxCharacters: 160,
    );
    if (listEquals(normalized, _state.attachments)) {
      return;
    }
    _commitComposerMutation(_state.copyWith(attachments: normalized));
  }

  void updateAcceptanceCriteria(Iterable<String> values) {
    if (_composerMutationBlocked()) {
      return;
    }
    final normalized = _boundedComposerValues(
      values,
      maxItems: 8,
      maxCharacters: 240,
    );
    if (listEquals(normalized, _state.acceptanceCriteria)) {
      return;
    }
    _commitComposerMutation(_state.copyWith(acceptanceCriteria: normalized));
  }

  void launchComposer() {
    if (!canLaunchComposer) {
      _state = _state.copyWith(
        recoveryMessage:
            'Composer launch cannot replace an active or resumable run. Use the run controls first.',
      );
      notifyListeners();
      return;
    }
    if (_state.selectedProjectId == null || _state.taskDraft.trim().isEmpty) {
      _state = _state.copyWith(
        recoveryMessage: 'Choose a project and enter a task before launch.',
      );
      notifyListeners();
      return;
    }
    if (_state.composerLaunchTiming != P5ComposerLaunchTiming.runNow) {
      _state = _state.copyWith(
        recoveryMessage:
            'Scheduling is not bound to a runtime yet. No task was started or scheduled.',
      );
      notifyListeners();
      return;
    }
    if (!_state.planReviewed || _state.selectedRunId != null) {
      apply(P5PrototypeAction.reviewPlan);
    }
    if (!_state.planReviewed) {
      return;
    }
    if (_state.planOnly) {
      _state = _state.copyWith(
        runState: P5RunPresentationState.planOnly,
        recoveryMessage:
            'Plan-only launch completed review without starting execution.',
      );
      notifyListeners();
      return;
    }
    apply(P5PrototypeAction.startRun);
  }

  void selectProject(String? projectId) {
    if (_runContextLocked && projectId != _state.selectedProjectId) {
      _state = _state.copyWith(
        recoveryMessage:
            'Project context cannot change while a simulated run is active. Use the run controls first.',
      );
      notifyListeners();
      return;
    }

    if (projectId == null) {
      if (_state.selectedProjectId == null && _state.selectedRunId == null) {
        return;
      }
      _state = _state.copyWith(
        selectedProjectId: null,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage: 'Choose a project to continue.',
      );
      notifyListeners();
      return;
    }

    final fixture = _projectFixture(projectId);
    if (fixture == null) {
      _state = _state.copyWith(
        selectedProjectId: null,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage:
            'Project "$projectId" was not found. Choose an available project.',
      );
      notifyListeners();
      return;
    }

    if (fixture.id == _state.selectedProjectId) {
      final recoverableBlockedState =
          _state.selectedRunId == null &&
          const <P5RunPresentationState>{
            P5RunPresentationState.blocked,
            P5RunPresentationState.error,
          }.contains(_state.runState);
      if (!recoverableBlockedState) {
        return;
      }
    }

    _state = _state.copyWith(
      selectedProjectId: fixture.id,
      selectedRunId: null,
      selectedEvidenceId: null,
      runState: P5RunPresentationState.planReady,
      planReviewed: false,
      planOnly: false,
      verificationRequested: false,
      recoveryMessage: 'Project context retained across workspaces.',
    );
    notifyListeners();
  }

  void selectRun(String? runId) {
    if (_runContextLocked && runId != _state.selectedRunId) {
      _state = _state.copyWith(
        recoveryMessage:
            'Run context cannot change while a simulated run is active. Use the run controls first.',
      );
      notifyListeners();
      return;
    }

    if (runId == null) {
      if (_state.selectedRunId == null) {
        return;
      }
      final projectId = _knownProjectIdOrNull(_state.selectedProjectId);
      _state = _state.copyWith(
        selectedProjectId: projectId,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: projectId == null
            ? P5RunPresentationState.blocked
            : P5RunPresentationState.planReady,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage: projectId == null
            ? 'Choose a project to continue.'
            : null,
      );
      notifyListeners();
      return;
    }

    final fixture = _runFixture(runId);
    if (fixture == null) {
      _state = _state.copyWith(
        selectedProjectId: _knownProjectIdOrNull(_state.selectedProjectId),
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage:
            'Run "$runId" was not found. Choose an available saved run.',
      );
      notifyListeners();
      return;
    }

    if (fixture.id == _state.selectedRunId &&
        fixture.projectId == _state.selectedProjectId &&
        !_state.planReviewed &&
        !_state.planOnly &&
        !_state.verificationRequested) {
      return;
    }

    _state = _state.copyWith(
      selectedRunId: fixture.id,
      selectedProjectId: fixture.projectId,
      selectedEvidenceId: null,
      runState: fixture.state,
      planReviewed: false,
      planOnly: false,
      verificationRequested: false,
      recoveryMessage: 'Run context restored without losing project.',
    );
    notifyListeners();
  }

  void selectEvidence(String? evidenceId) {
    final runId = _state.selectedRunId;
    final isSavedRun =
        runId != null && P5PrototypeFixtures.runs.any((run) => run.id == runId);
    if (!isSavedRun) {
      _state = _state.copyWith(
        selectedEvidenceId: null,
        recoveryMessage:
            'Typed evidence can only reopen from a deterministic saved run.',
      );
      notifyListeners();
      return;
    }
    if (evidenceId == null) {
      if (_state.selectedEvidenceId == null) {
        return;
      }
      _state = _state.copyWith(selectedEvidenceId: null, recoveryMessage: null);
      notifyListeners();
      return;
    }
    final evidence = P5PrototypeFixtures.evidenceById(
      runId: runId,
      evidenceId: evidenceId,
    );
    if (evidence == null) {
      _state = _state.copyWith(
        selectedEvidenceId: null,
        recoveryMessage:
            'Evidence "$evidenceId" is not part of saved run "$runId".',
      );
      notifyListeners();
      return;
    }
    if (_state.selectedEvidenceId == evidence.id &&
        _state.recoveryMessage == null) {
      return;
    }
    _state = _state.copyWith(
      selectedEvidenceId: evidence.id,
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void selectWorkspace(P5WorkspaceId workspace) {
    if (!_isWorkspaceEligible(workspace)) {
      _rejectWorkspace(workspace);
      return;
    }
    if (_state.workspace == workspace) {
      return;
    }
    final history =
        _state.navigationHistory
            .take(_state.navigationIndex + 1)
            .toList(growable: true)
          ..add(workspace);
    _state = _state.copyWith(
      workspace: workspace,
      navigationHistory: List<P5WorkspaceId>.unmodifiable(history),
      navigationIndex: history.length - 1,
      reopenWorkspace: workspace,
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void back() {
    final nextIndex = _findEligibleHistoryIndex(-1);
    if (nextIndex == null) {
      return;
    }
    final workspace = _state.navigationHistory[nextIndex];
    _state = _state.copyWith(
      workspace: workspace,
      navigationIndex: nextIndex,
      reopenWorkspace: workspace,
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void forward() {
    final nextIndex = _findEligibleHistoryIndex(1);
    if (nextIndex == null) {
      return;
    }
    final workspace = _state.navigationHistory[nextIndex];
    _state = _state.copyWith(
      workspace: workspace,
      navigationIndex: nextIndex,
      reopenWorkspace: workspace,
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void reopen() {
    final workspace = _state.reopenWorkspace;
    if (!_isWorkspaceEligible(workspace)) {
      _rejectWorkspace(workspace);
      return;
    }
    if (_state.workspace == workspace) {
      return;
    }
    selectWorkspace(workspace);
  }

  void deepLink({
    required P5WorkspaceId workspace,
    String? projectId,
    String? runId,
  }) {
    if (_runContextLocked) {
      final changesContext =
          (projectId != null && projectId != _state.selectedProjectId) ||
          (runId != null && runId != _state.selectedRunId);
      if (changesContext) {
        _state = _state.copyWith(
          recoveryMessage:
              'Deep link context cannot replace an active simulated run. Use the run controls first.',
        );
        notifyListeners();
        return;
      }
      if (projectId != null || runId != null) {
        if (!_isWorkspaceEligible(workspace)) {
          _rejectWorkspace(workspace);
          return;
        }
        selectWorkspace(workspace);
        return;
      }
    }

    final project = projectId == null ? null : _projectFixture(projectId);
    if (projectId != null && project == null) {
      _state = _state.copyWith(
        selectedProjectId: null,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage:
            'Project "$projectId" was not found. Deep link context was not applied.',
      );
      notifyListeners();
      return;
    }

    final run = runId == null ? null : _runFixture(runId);
    if (runId != null && run == null) {
      _state = _state.copyWith(
        selectedProjectId:
            project?.id ?? _knownProjectIdOrNull(_state.selectedProjectId),
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage:
            'Run "$runId" was not found. Deep link context was not applied.',
      );
      notifyListeners();
      return;
    }

    if (project != null && run != null && run.projectId != project.id) {
      _state = _state.copyWith(
        selectedProjectId: project.id,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage:
            'Run "${run.id}" does not belong to project "${project.id}". Deep link context was not applied.',
      );
      notifyListeners();
      return;
    }

    if (run != null) {
      _state = _state.copyWith(
        selectedProjectId: run.projectId,
        selectedRunId: run.id,
        runState: run.state,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage: null,
      );
    } else if (project != null) {
      _state = _state.copyWith(
        selectedProjectId: project.id,
        selectedRunId: null,
        selectedEvidenceId: null,
        runState: P5RunPresentationState.planReady,
        planReviewed: false,
        planOnly: false,
        verificationRequested: false,
        recoveryMessage: null,
      );
    }

    if (!_isWorkspaceEligible(workspace)) {
      _rejectWorkspace(workspace);
      return;
    }
    selectWorkspace(workspace);
  }

  void transitionWorkspaceState(
    P5WorkspaceId workspace,
    P5WorkspaceState next,
  ) {
    final current = _state.workspaceStates[workspace] ?? P5WorkspaceState.ready;
    P5WorkspaceTransitionGraph.validate(current, next);
    final states = Map<P5WorkspaceId, P5WorkspaceState>.of(
      _state.workspaceStates,
    )..[workspace] = next;
    _state = _state.copyWith(
      workspaceStates: Map<P5WorkspaceId, P5WorkspaceState>.unmodifiable(
        states,
      ),
    );
    notifyListeners();
  }

  void setOwnerModePresentation(P5OwnerModePresentationState state) {
    if (_state.ownerModeState == state) {
      return;
    }
    _state = _state.copyWith(
      ownerModeState: state,
      recoveryMessage:
          'Presentation changed only. No Owner Mode runtime action occurred.',
    );
    notifyListeners();
  }

  void showRecoveryMessage(String message) {
    if (message == _state.recoveryMessage) {
      return;
    }
    _state = _state.copyWith(recoveryMessage: message);
    notifyListeners();
  }

  void apply(P5PrototypeAction action) {
    switch (action) {
      case P5PrototypeAction.createSampleProject:
        selectProject(P5PrototypeFixtures.projects.first.id);
        return;
      case P5PrototypeAction.clearProject:
        selectProject(null);
        return;
      case P5PrototypeAction.reviewPlan:
        if (!canReviewPlan) {
          _state = _state.copyWith(
            recoveryMessage:
                'Plan review cannot replace an active or resumable run. Use the run controls first.',
          );
          notifyListeners();
          return;
        }
        if (_state.selectedProjectId == null ||
            _state.taskDraft.trim().isEmpty) {
          _state = _state.copyWith(
            runState: P5RunPresentationState.blocked,
            recoveryMessage: 'Choose a project and enter a task first.',
          );
        } else {
          _state = _state.copyWith(
            selectedRunId: null,
            selectedEvidenceId: null,
            planReviewed: true,
            runState: P5RunPresentationState.ready,
            verificationRequested: false,
            recoveryMessage: 'Concise plan reviewed. No task has executed.',
          );
        }
        notifyListeners();
        return;
      case P5PrototypeAction.choosePlanOnly:
        if (!canChangePlanOnly) {
          _state = _state.copyWith(
            recoveryMessage:
                'Plan-only can only be changed before a simulated run starts.',
          );
          notifyListeners();
          return;
        }
        final nextPlanOnly = !_state.planOnly;
        _state = _state.copyWith(
          planOnly: nextPlanOnly,
          runState: nextPlanOnly
              ? P5RunPresentationState.planOnly
              : (_state.planReviewed
                    ? P5RunPresentationState.ready
                    : P5RunPresentationState.planReady),
          recoveryMessage: 'Plan-only changes presentation, not authority.',
        );
        notifyListeners();
        return;
      case P5PrototypeAction.startRun:
        if (_runLifecycleLocked) {
          _state = _state.copyWith(
            recoveryMessage:
                'Start cannot replace an active or resumable run. Use the run controls first.',
          );
          notifyListeners();
          return;
        }
        if (_state.selectedRunId != null) {
          _state = _state.copyWith(
            recoveryMessage: 'Review a new plan before starting another run.',
          );
          notifyListeners();
          return;
        }
        if (!_state.planReviewed) {
          _state = _state.copyWith(
            runState: P5RunPresentationState.blocked,
            recoveryMessage: 'Review the concise plan before starting.',
          );
        } else if (_state.planOnly) {
          _state = _state.copyWith(
            runState: P5RunPresentationState.planOnly,
            recoveryMessage: 'Plan-only mode keeps execution disabled.',
          );
        } else {
          _state = _state.copyWith(
            selectedRunId: 'run.p5-simulated-current',
            runState: P5RunPresentationState.running,
            recoveryMessage:
                'Simulated run started. No runtime command executed.',
          );
        }
        notifyListeners();
        return;
      case P5PrototypeAction.pauseRun:
        _setRunState(
          expected: const <P5RunPresentationState>{
            P5RunPresentationState.running,
          },
          next: P5RunPresentationState.paused,
          message: 'Simulated run paused with context retained.',
        );
        return;
      case P5PrototypeAction.resumeRun:
        _setRunState(
          expected: const <P5RunPresentationState>{
            P5RunPresentationState.paused,
            P5RunPresentationState.interrupted,
          },
          next: P5RunPresentationState.running,
          message: 'Simulated run resumed from retained context.',
        );
        return;
      case P5PrototypeAction.stopRun:
        _setRunState(
          expected: const <P5RunPresentationState>{
            P5RunPresentationState.running,
            P5RunPresentationState.paused,
          },
          next: P5RunPresentationState.stopping,
          message: 'Simulated run is stopping safely.',
        );
        return;
      case P5PrototypeAction.completeRun:
        _setRunState(
          expected: const <P5RunPresentationState>{
            P5RunPresentationState.running,
            P5RunPresentationState.stopping,
          },
          next: P5RunPresentationState.completed,
          message: 'Simulated run completed. Open evidence to inspect proof.',
        );
        return;
      case P5PrototypeAction.openEvidence:
        selectWorkspace(P5WorkspaceId.evidence);
        return;
      case P5PrototypeAction.runVerification:
        if (_state.runState != P5RunPresentationState.completed) {
          _state = _state.copyWith(
            recoveryMessage:
                'Verification can only be requested after a simulated run completes.',
          );
          notifyListeners();
          return;
        }
        _state = _state.copyWith(
          verificationRequested: true,
          recoveryMessage:
              'Affected tests selected in memory. No external runner started.',
        );
        notifyListeners();
        selectWorkspace(P5WorkspaceId.verificationCenter);
        return;
      case P5PrototypeAction.retryInterruptedRun:
        _setRunState(
          expected: const <P5RunPresentationState>{
            P5RunPresentationState.interrupted,
          },
          next: P5RunPresentationState.running,
          message: 'Interrupted run restored from the saved fixture.',
        );
        return;
      case P5PrototypeAction.restoreModelFixture:
        _state = _state.copyWith(
          recoveryMessage: 'Local fixture model is available for presentation.',
        );
        notifyListeners();
        return;
      case P5PrototypeAction.acknowledgeOfflineFixture:
        _state = _state.copyWith(
          recoveryMessage: 'Local-only work remains available while offline.',
        );
        notifyListeners();
        return;
    }
  }

  bool _composerMutationBlocked() {
    if (!_runContextLocked) {
      return false;
    }
    _state = _state.copyWith(
      recoveryMessage:
          'Composer context cannot change while a simulated run is active. Use the run controls first.',
    );
    notifyListeners();
    return true;
  }

  void _commitComposerMutation(P5PresentationState next) {
    _state = next.copyWith(
      planReviewed: false,
      verificationRequested: false,
      recoveryMessage:
          'Composer context updated. Review the plan before launch.',
    );
    notifyListeners();
  }

  List<String> _boundedComposerValues(
    Iterable<String> values, {
    required int maxItems,
    required int maxCharacters,
  }) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in values) {
      var value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      if (value.length > maxCharacters) {
        value = value.substring(0, maxCharacters).trimRight();
      }
      if (!seen.add(value)) {
        continue;
      }
      result.add(value);
      if (result.length >= maxItems) {
        break;
      }
    }
    return List<String>.unmodifiable(result);
  }

  P5ProjectFixture? _projectFixture(String projectId) {
    return P5PrototypeFixtures.projects
        .where((project) => project.id == projectId)
        .firstOrNull;
  }

  P5RunFixture? _runFixture(String runId) {
    return P5PrototypeFixtures.runs.where((run) => run.id == runId).firstOrNull;
  }

  String? _knownProjectIdOrNull(String? projectId) {
    if (projectId == null) {
      return null;
    }
    return _projectFixture(projectId)?.id;
  }

  P5ExperienceLevel _minimumLevel(P5WorkspaceId workspace) {
    return P5PrototypeFixtures.workspaces
        .where((definition) => definition.id == workspace)
        .firstOrNull!
        .minimumLevel;
  }

  bool _isWorkspaceEligible(P5WorkspaceId workspace) {
    return _isWorkspaceEligibleAt(workspace, _state.experienceLevel);
  }

  bool _isWorkspaceEligibleAt(
    P5WorkspaceId workspace,
    P5ExperienceLevel level,
  ) {
    final definition = P5PrototypeFixtures.workspaces
        .where((candidate) => candidate.id == workspace)
        .firstOrNull;
    return definition != null && definition.minimumLevel.index <= level.index;
  }

  bool _isResolvedExperienceWarning(String? message, P5ExperienceLevel level) {
    if (message == null) {
      return false;
    }
    for (final definition in P5PrototypeFixtures.workspaces) {
      if (definition.minimumLevel.index > level.index) {
        continue;
      }
      final base =
          '${definition.id.label} requires ${definition.minimumLevel.label} mode.';
      if (message == base || message == '$base Returned to Home / Chat.') {
        return true;
      }
    }
    return false;
  }

  int? _findEligibleHistoryIndex(int direction) {
    var index = _state.navigationIndex + direction;
    while (index >= 0 && index < _state.navigationHistory.length) {
      if (_isWorkspaceEligible(_state.navigationHistory[index])) {
        return index;
      }
      index += direction;
    }
    return null;
  }

  void _rejectWorkspace(P5WorkspaceId workspace) {
    _state = _state.copyWith(
      recoveryMessage:
          '${workspace.label} requires ${_minimumLevel(workspace).label} mode.',
    );
    notifyListeners();
  }

  void _setRunState({
    required Set<P5RunPresentationState> expected,
    required P5RunPresentationState next,
    required String message,
  }) {
    if (!expected.contains(_state.runState)) {
      _state = _state.copyWith(
        recoveryMessage:
            'That presentation transition is not valid from ${_state.runState.label}.',
      );
    } else {
      _state = _state.copyWith(runState: next, recoveryMessage: message);
    }
    notifyListeners();
  }
}

extension _P5IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
