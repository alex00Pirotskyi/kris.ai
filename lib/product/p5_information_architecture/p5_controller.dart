import 'package:flutter/foundation.dart';

import 'p5_fixtures.dart';
import 'p5_models.dart';

class P5InformationArchitectureController extends ChangeNotifier {
  P5InformationArchitectureController({P5PresentationState? initialState})
      : _state = initialState ?? P5PrototypeFixtures.initialState();

  P5PresentationState _state;
  P5PresentationState get state => _state;

  P5SideEffectLedger get sideEffects => P5SideEffectLedger.zero;

  bool get canGoBack => _state.navigationIndex > 0;
  bool get canGoForward =>
      _state.navigationIndex < _state.navigationHistory.length - 1;

  List<P5WorkspaceDefinition> get visibleWorkspaces {
    return P5PrototypeFixtures.workspaces.where((definition) {
      if (definition.id.isFutureCapability) {
        return false;
      }
      return definition.minimumLevel.index <= _state.experienceLevel.index;
    }).toList(growable: false);
  }

  void changeExperienceLevel(P5ExperienceLevel level) {
    if (level == _state.experienceLevel) {
      return;
    }
    _state = _state.copyWith(experienceLevel: level);
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
    if (projectId == _state.selectedProjectId) {
      return;
    }
    _state = _state.copyWith(
      selectedProjectId: projectId,
      selectedRunId: null,
      runState: projectId == null
          ? P5RunPresentationState.blocked
          : P5RunPresentationState.planReady,
      planReviewed: false,
      verificationRequested: false,
      recoveryMessage: projectId == null
          ? 'Choose a project to continue.'
          : 'Project context retained across workspaces.',
    );
    notifyListeners();
  }

  void selectRun(String? runId) {
    if (runId == _state.selectedRunId) {
      return;
    }
    final fixture =
        P5PrototypeFixtures.runs.where((run) => run.id == runId).firstOrNull;
    _state = _state.copyWith(
      selectedRunId: runId,
      selectedProjectId: fixture?.projectId ?? _state.selectedProjectId,
      runState: fixture?.state ?? _state.runState,
      recoveryMessage:
          runId == null ? null : 'Run context restored without losing project.',
    );
    notifyListeners();
  }

  void selectWorkspace(P5WorkspaceId workspace) {
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
    if (!canGoBack) {
      return;
    }
    final nextIndex = _state.navigationIndex - 1;
    _state = _state.copyWith(
      workspace: _state.navigationHistory[nextIndex],
      navigationIndex: nextIndex,
      reopenWorkspace: _state.navigationHistory[nextIndex],
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void forward() {
    if (!canGoForward) {
      return;
    }
    final nextIndex = _state.navigationIndex + 1;
    _state = _state.copyWith(
      workspace: _state.navigationHistory[nextIndex],
      navigationIndex: nextIndex,
      reopenWorkspace: _state.navigationHistory[nextIndex],
      recoveryMessage: null,
    );
    notifyListeners();
  }

  void reopen() {
    final workspace = _state.reopenWorkspace;
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
    if (projectId != null) {
      selectProject(projectId);
    }
    if (runId != null) {
      selectRun(runId);
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
        _state = _state.copyWith(
          planOnly: !_state.planOnly,
          runState: !_state.planOnly
              ? P5RunPresentationState.planOnly
              : P5RunPresentationState.ready,
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
        _state = _state.copyWith(
          runState: P5RunPresentationState.running,
          recoveryMessage: 'Interrupted run restored from the saved fixture.',
        );
        notifyListeners();
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
