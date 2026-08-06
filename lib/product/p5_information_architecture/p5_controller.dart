import 'package:flutter/foundation.dart';

import 'p5_fixtures.dart';
import 'p5_models.dart';

class P5InformationArchitectureController extends ChangeNotifier {
  P5InformationArchitectureController({P5PresentationState? initialState})
      : _state = initialState ?? P5PrototypeFixtures.initialState();

  P5PresentationState _state;
  P5PresentationState get state => _state;

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

  List<P5WorkspaceDefinition> get visibleWorkspaces {
    return P5PrototypeFixtures.workspaces.where((definition) {
      if (definition.id.isFutureCapability) {
        return false;
      }
      return _isWorkspaceEligibleAt(
        definition.id,
        _state.experienceLevel,
      );
    }).toList(growable: false);
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
        navigationHistory: const <P5WorkspaceId>[
          P5WorkspaceId.homeChat,
        ],
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
    if (sanitizedHistory.isEmpty ||
        sanitizedHistory.last != currentWorkspace) {
      sanitizedHistory.add(currentWorkspace);
    }

    _state = _state.copyWith(
      experienceLevel: level,
      navigationHistory:
          List<P5WorkspaceId>.unmodifiable(sanitizedHistory),
      navigationIndex: sanitizedHistory.length - 1,
      reopenWorkspace: currentWorkspace,
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void updateTaskDraft(String value) {
    if (value == _state.taskDraft) {
      return;
    }
    _state = _state.copyWith(taskDraft: value, planReviewed: false);
    notifyListeners();
  }

  void selectProject(String? projectId) {
    if (projectId == null) {
      if (_state.selectedProjectId == null && _state.selectedRunId == null) {
        return;
      }
      _state = _state.copyWith(
        selectedProjectId: null,
        selectedRunId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
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
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        verificationRequested: false,
        recoveryMessage:
            'Project "$projectId" was not found. Choose an available project.',
      );
      notifyListeners();
      return;
    }

    if (fixture.id == _state.selectedProjectId &&
        _state.selectedRunId == null &&
        _state.runState == P5RunPresentationState.planReady) {
      return;
    }

    _state = _state.copyWith(
      selectedProjectId: fixture.id,
      selectedRunId: null,
      runState: P5RunPresentationState.planReady,
      planReviewed: false,
      verificationRequested: false,
      recoveryMessage: 'Project context retained across workspaces.',
    );
    notifyListeners();
  }

  void selectRun(String? runId) {
    if (runId == null) {
      if (_state.selectedRunId == null) {
        return;
      }
      final projectId = _knownProjectIdOrNull(_state.selectedProjectId);
      _state = _state.copyWith(
        selectedProjectId: projectId,
        selectedRunId: null,
        runState: projectId == null
            ? P5RunPresentationState.blocked
            : P5RunPresentationState.planReady,
        planReviewed: false,
        recoveryMessage:
            projectId == null ? 'Choose a project to continue.' : null,
      );
      notifyListeners();
      return;
    }

    final fixture = _runFixture(runId);
    if (fixture == null) {
      _state = _state.copyWith(
        selectedProjectId: _knownProjectIdOrNull(_state.selectedProjectId),
        selectedRunId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
        verificationRequested: false,
        recoveryMessage:
            'Run "$runId" was not found. Choose an available saved run.',
      );
      notifyListeners();
      return;
    }

    if (fixture.id == _state.selectedRunId &&
        fixture.projectId == _state.selectedProjectId) {
      return;
    }

    _state = _state.copyWith(
      selectedRunId: fixture.id,
      selectedProjectId: fixture.projectId,
      runState: fixture.state,
      recoveryMessage: 'Run context restored without losing project.',
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
    final history = _state.navigationHistory
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
    final project =
        projectId == null ? null : _projectFixture(projectId);
    if (projectId != null && project == null) {
      _state = _state.copyWith(
        selectedProjectId: null,
        selectedRunId: null,
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
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
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
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
        runState: P5RunPresentationState.blocked,
        planReviewed: false,
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
        recoveryMessage: null,
      );
    } else if (project != null) {
      _state = _state.copyWith(
        selectedProjectId: project.id,
        selectedRunId: null,
        runState: P5RunPresentationState.planReady,
        planReviewed: false,
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
      workspaceStates:
          Map<P5WorkspaceId, P5WorkspaceState>.unmodifiable(states),
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

  void apply(P5PrototypeAction action) {
    switch (action) {
      case P5PrototypeAction.createSampleProject:
        selectProject(P5PrototypeFixtures.projects.first.id);
        return;
      case P5PrototypeAction.clearProject:
        selectProject(null);
        return;
      case P5PrototypeAction.reviewPlan:
        if (_state.selectedProjectId == null ||
            _state.taskDraft.trim().isEmpty) {
          _state = _state.copyWith(
            runState: P5RunPresentationState.blocked,
            recoveryMessage: 'Choose a project and enter a task first.',
          );
        } else {
          _state = _state.copyWith(
            planReviewed: true,
            runState: P5RunPresentationState.ready,
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

extension P5IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
