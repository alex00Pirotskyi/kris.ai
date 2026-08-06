import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_fixtures.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';

void main() {
  test('invalid state transition is rejected', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    expect(
      () => controller.transitionWorkspaceState(
        P5WorkspaceId.webStudio,
        P5WorkspaceState.running,
      ),
      throwsA(isA<P5InvalidTransition>()),
    );

    controller.transitionWorkspaceState(
      P5WorkspaceId.homeChat,
      P5WorkspaceState.running,
    );
    controller.transitionWorkspaceState(
      P5WorkspaceId.homeChat,
      P5WorkspaceState.completed,
    );
    expect(
      () => controller.transitionWorkspaceState(
        P5WorkspaceId.homeChat,
        P5WorkspaceState.running,
      ),
      throwsA(isA<P5InvalidTransition>()),
    );
  });

  test(
    'experience levels use progressive disclosure without authority changes',
    () {
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);

      final project = controller.state.selectedProjectId;
      final run = controller.state.selectedRunId;
      final owner = controller.state.ownerModeState;
      final sideEffects = controller.sideEffects;
      final simpleIds =
          controller.visibleWorkspaces.map((item) => item.id).toSet();

      controller.changeExperienceLevel(P5ExperienceLevel.advanced);
      final advancedIds =
          controller.visibleWorkspaces.map((item) => item.id).toSet();
      controller.changeExperienceLevel(P5ExperienceLevel.developer);

      expect(advancedIds.length, greaterThan(simpleIds.length));
      expect(advancedIds, contains(P5WorkspaceId.evidence));
      expect(advancedIds, contains(P5WorkspaceId.modelsProviders));
      expect(controller.state.selectedProjectId, project);
      expect(controller.state.selectedRunId, run);
      expect(controller.state.ownerModeState, owner);
      expect(controller.sideEffects, sideEffects);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  test('satisfying a workspace level requirement clears its stale warning', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectWorkspace(P5WorkspaceId.evidence);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);

    expect(controller.state.experienceLevel, P5ExperienceLevel.advanced);
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, isNull);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('experience level changes preserve unrelated recovery errors', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectProject(null);
    expect(controller.state.recoveryMessage, 'Choose a project to continue.');

    controller.changeExperienceLevel(P5ExperienceLevel.advanced);
    expect(controller.state.recoveryMessage, 'Choose a project to continue.');

    controller.selectProject('project.kristin-local');
    controller.selectRun('run.missing');
    final missingRunMessage = controller.state.recoveryMessage;
    expect(missingRunMessage, contains('was not found'));

    controller.changeExperienceLevel(P5ExperienceLevel.developer);
    expect(controller.state.recoveryMessage, missingRunMessage);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('advanced workspace selection and deep links fail closed in Simple mode',
      () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectWorkspace(P5WorkspaceId.evidence);

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.navigationHistory, <P5WorkspaceId>[
      P5WorkspaceId.homeChat,
    ]);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    controller.deepLink(
      workspace: P5WorkspaceId.modelsProviders,
      projectId: 'project.kristin-local',
      runId: 'run.p5-existing-001',
    );

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-existing-001');
    expect(controller.state.recoveryMessage, contains('Advanced mode'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('downgrade sanitizes advanced workspace history and reopen target', () {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.evidence)
      ..selectWorkspace(P5WorkspaceId.modelsProviders);
    addTearDown(controller.dispose);

    controller.changeExperienceLevel(P5ExperienceLevel.simple);

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.navigationHistory, <P5WorkspaceId>[
      P5WorkspaceId.homeChat,
    ]);
    expect(controller.state.navigationIndex, 0);
    expect(controller.state.reopenWorkspace, P5WorkspaceId.homeChat);
    expect(controller.canGoBack, isFalse);
    expect(controller.canGoForward, isFalse);

    controller.reopen();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('downgrade removes hidden entries from back and forward navigation', () {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.evidence)
      ..selectWorkspace(P5WorkspaceId.verificationCenter);
    addTearDown(controller.dispose);

    controller.changeExperienceLevel(P5ExperienceLevel.simple);

    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(
      controller.state.navigationHistory,
      <P5WorkspaceId>[
        P5WorkspaceId.homeChat,
        P5WorkspaceId.verificationCenter,
      ],
    );
    expect(controller.canGoBack, isTrue);

    controller.back();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.canGoForward, isTrue);

    controller.forward();
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('stale hidden history and reopen cannot bypass Simple mode', () {
    final initial = P5PrototypeFixtures.initialState().copyWith(
      navigationHistory: const <P5WorkspaceId>[
        P5WorkspaceId.homeChat,
        P5WorkspaceId.evidence,
        P5WorkspaceId.verificationCenter,
      ],
      navigationIndex: 0,
      reopenWorkspace: P5WorkspaceId.evidence,
    );
    final controller = P5InformationArchitectureController(
      initialState: initial,
    );
    addTearDown(controller.dispose);

    controller.reopen();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.recoveryMessage, contains('Advanced mode'));

    expect(controller.canGoForward, isTrue);
    controller.forward();
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.canGoBack, isTrue);

    controller.back();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('unknown project and run identities fail closed', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectProject('project.missing');

    expect(controller.state.selectedProjectId, isNull);
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.blocked);
    expect(controller.state.recoveryMessage, contains('was not found'));

    controller.selectProject('project.kristin-local');
    controller.selectRun('run.missing');

    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.blocked);
    expect(controller.state.recoveryMessage, contains('was not found'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('mismatched project and run deep link clears incompatible run context',
      () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.deepLink(
      workspace: P5WorkspaceId.runsActivity,
      projectId: 'project.sample-notes',
      runId: 'run.p5-existing-001',
    );

    expect(controller.state.workspace, P5WorkspaceId.homeChat);
    expect(controller.state.selectedProjectId, 'project.sample-notes');
    expect(controller.state.selectedRunId, isNull);
    expect(controller.state.runState, P5RunPresentationState.blocked);
    expect(controller.state.recoveryMessage, contains('does not belong'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('valid saved-run deep link restores deterministic fixture context', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.deepLink(
      workspace: P5WorkspaceId.runsActivity,
      projectId: 'project.kristin-local',
      runId: 'run.p5-existing-001',
    );

    expect(controller.state.workspace, P5WorkspaceId.runsActivity);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-existing-001');
    expect(controller.state.runState, P5RunPresentationState.interrupted);
    expect(controller.state.recoveryMessage, isNull);
  });

  test('retry interrupted run is fail-closed for completed saved runs', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-complete-001');
    expect(controller.state.runState, P5RunPresentationState.completed);

    controller.apply(P5PrototypeAction.retryInterruptedRun);

    expect(controller.state.runState, P5RunPresentationState.completed);
    expect(controller.state.recoveryMessage, contains('not valid'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('retry interrupted run resumes only an interrupted saved fixture', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-existing-001');
    expect(controller.state.runState, P5RunPresentationState.interrupted);

    controller.apply(P5PrototypeAction.retryInterruptedRun);

    expect(controller.state.runState, P5RunPresentationState.running);
    expect(
      controller.state.recoveryMessage,
      'Interrupted run restored from the saved fixture.',
    );
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('plan-only changes are fail-closed once a run exists', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    expect(controller.canChangePlanOnly, isTrue);
    expect(controller.state.runState, P5RunPresentationState.planReady);

    controller.apply(P5PrototypeAction.choosePlanOnly);
    expect(controller.state.planOnly, isTrue);
    expect(controller.state.runState, P5RunPresentationState.planOnly);

    controller.apply(P5PrototypeAction.choosePlanOnly);
    expect(controller.state.planOnly, isFalse);
    expect(controller.state.runState, P5RunPresentationState.planReady);

    controller.apply(P5PrototypeAction.reviewPlan);
    expect(controller.state.runState, P5RunPresentationState.ready);
    controller.apply(P5PrototypeAction.startRun);

    expect(controller.state.selectedRunId, 'run.p5-simulated-current');
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.canChangePlanOnly, isFalse);

    controller.apply(P5PrototypeAction.choosePlanOnly);

    expect(controller.state.planOnly, isFalse);
    expect(controller.state.runState, P5RunPresentationState.running);
    expect(controller.state.recoveryMessage,
        contains('before a simulated run starts'));
    expect(controller.sideEffects.isZero, isTrue);
  });

  test('selected project and run persist across eligible navigation and reopen',
      () {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced);
    addTearDown(controller.dispose);

    controller.selectRun('run.p5-existing-001');
    controller.selectWorkspace(P5WorkspaceId.verificationCenter);
    controller.selectWorkspace(P5WorkspaceId.evidence);

    expect(controller.state.selectedProjectId, 'project.kristin-local');
    expect(controller.state.selectedRunId, 'run.p5-existing-001');
    expect(controller.state.workspace, P5WorkspaceId.evidence);

    controller.back();
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.state.selectedRunId, 'run.p5-existing-001');

    controller.forward();
    expect(controller.state.workspace, P5WorkspaceId.evidence);
    expect(controller.state.selectedProjectId, 'project.kristin-local');
  });

  test('prototype controller has no runtime side effects', () {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    controller.apply(P5PrototypeAction.reviewPlan);
    controller.apply(P5PrototypeAction.startRun);
    controller.apply(P5PrototypeAction.pauseRun);
    controller.apply(P5PrototypeAction.resumeRun);
    controller.apply(P5PrototypeAction.stopRun);
    controller.apply(P5PrototypeAction.completeRun);
    controller.setOwnerModePresentation(
      P5OwnerModePresentationState.running,
    );
    controller.selectWorkspace(P5WorkspaceId.webStudio);

    expect(controller.sideEffects, P5SideEffectLedger.zero);
    expect(controller.sideEffects.isZero, isTrue);
  });
}
