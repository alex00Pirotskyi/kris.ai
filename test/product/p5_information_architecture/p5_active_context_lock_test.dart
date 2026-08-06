import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('active run locks task, project, saved-run, and deep-link context', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    final originalTask = controller.state.taskDraft;
    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.canEditTaskDraft, isFalse);
    expect(controller.canChangeProjectContext, isFalse);
    expect(controller.canSelectSavedRun, isFalse);

    controller.updateTaskDraft('Replace active task context');
    expect(controller.state.taskDraft, originalTask);
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.recoveryMessage, contains('Task context cannot change'));

    controller.selectProject('project.sample-notes');
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.recoveryMessage, contains('Project context cannot change'));

    controller.selectRun('run.p5-existing-001');
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.recoveryMessage, contains('Run context cannot change'));

    controller.deepLink(
      workspace: P5WorkspaceId.runsActivity,
      projectId: 'project.sample-notes',
    );
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.recoveryMessage, contains('Deep link context cannot replace'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('paused and stopping runs keep context locked until completion', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.pauseRun);

    expect(controller.state.runState, P5RunPresentationState.paused);
    expect(controller.canEditTaskDraft, isFalse);
    controller.selectProject(null);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');

    controller.apply(P5PrototypeAction.stopRun);
    expect(controller.state.runState, P5RunPresentationState.stopping);
    controller.selectRun(null);
    expect(controller.state.selectedRunId, 'run.p5-simulated-current');

    controller.apply(P5PrototypeAction.completeRun);
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.canEditTaskDraft, isTrue);
    expect(controller.canChangeProjectContext, isTrue);
    expect(controller.canSelectSavedRun, isTrue);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('interrupted saved run remains browsable but not startable as a new task', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-existing-001');
    expect(controller.state.runState, P5RunPresentationState.interrupted);
    expect(controller.canEditTaskDraft, isTrue);
    expect(controller.canChangeProjectContext, isTrue);
    expect(controller.canSelectSavedRun, isTrue);
    expect(controller.canReviewPlan, isFalse);
    expect(controller.canStartRun, isFalse);

    controller.selectRun('run.p5-complete-001');
    expect(controller.state.selectedRunId, 'run.p5-complete-001');
    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
