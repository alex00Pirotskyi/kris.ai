import 'p5_models.dart';

class P5PrototypeFixtures {
  const P5PrototypeFixtures._();

  static const String fixedTimestamp = '2026-08-05T18:00:00Z';

  static const List<P5WorkspaceDefinition> workspaces = <P5WorkspaceDefinition>[
    P5WorkspaceDefinition(
      id: P5WorkspaceId.homeChat,
      description: 'Start a task, review a concise plan, and retain context.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.projects,
      description: 'Select, create, and understand local project boundaries.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.runsActivity,
      description: 'Resume recent work and inspect a deterministic timeline.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.verificationCenter,
      description:
          'Inspect tests, evidence, certification, and support as separate facts.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.evidence,
      description: 'Reopen receipts and artifacts without reading raw logs.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.ownerMode,
      description:
          'Inspect the real P2 Owner Mode state without duplicating its controls.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.modelsProviders,
      description: 'Inspect configured providers, models, and recovery needs.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.capabilitiesIntegrations,
      description: 'Inspect capability support and unavailable foundations.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.settingsDiagnostics,
      description: 'Change presentation and inspect recovery guidance.',
      minimumLevel: P5ExperienceLevel.simple,
      primary: true,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.webStudio,
      description:
          'Use the application-owned P3 browser runtime while editor and preview panels land independently.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.searchResearch,
      description: 'Future search and durable research placeholder.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.nativeAutomation,
      description: 'Future native automation placeholder.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
    P5WorkspaceDefinition(
      id: P5WorkspaceId.devices,
      description: 'Future device-control placeholder.',
      minimumLevel: P5ExperienceLevel.advanced,
    ),
  ];

  static const List<P5ProjectFixture> projects = <P5ProjectFixture>[
    P5ProjectFixture(
      id: 'project.kristin-local',
      name: 'Kristin Local Agent',
      pathLabel: 'Projects/Kristin',
    ),
    P5ProjectFixture(
      id: 'project.sample-notes',
      name: 'Local Notes',
      pathLabel: 'Projects/Local Notes',
    ),
  ];

  static const List<P5RunFixture> runs = <P5RunFixture>[
    P5RunFixture(
      id: 'run.p5-existing-001',
      projectId: 'project.kristin-local',
      title: 'Review navigation accessibility',
      state: P5RunPresentationState.interrupted,
      updatedAtLabel: '2026-08-05 18:00 UTC',
    ),
    P5RunFixture(
      id: 'run.p5-complete-001',
      projectId: 'project.kristin-local',
      title: 'Map Verification Center states',
      state: P5RunPresentationState.completed,
      updatedAtLabel: '2026-08-05 17:30 UTC',
    ),
  ];

  static const int timelineEventCount = 10000;

  static int timelineVisibleCount(P5TimelineCategory? filter) {
    if (filter == null) {
      return timelineEventCount;
    }
    final categoryCount = P5TimelineCategory.values.length;
    return ((timelineEventCount - 1 - filter.index) ~/ categoryCount) + 1;
  }

  static P5TimelineEvent timelineEventAt({
    required String runId,
    required int visibleIndex,
    P5TimelineCategory? filter,
  }) {
    if (!runs.any((run) => run.id == runId)) {
      throw ArgumentError.value(
        runId,
        'runId',
        'Timeline events exist only for deterministic saved-run fixtures.',
      );
    }
    final visibleCount = timelineVisibleCount(filter);
    if (visibleIndex < 0 || visibleIndex >= visibleCount) {
      throw RangeError.range(visibleIndex, 0, visibleCount - 1, 'visibleIndex');
    }
    final categoryCount = P5TimelineCategory.values.length;
    final zeroBasedSequence = filter == null
        ? visibleIndex
        : (visibleIndex * categoryCount) + filter.index;
    final category =
        filter ?? P5TimelineCategory.values[zeroBasedSequence % categoryCount];
    final sequence = zeroBasedSequence + 1;
    final title = switch (category) {
      P5TimelineCategory.model => 'Model proposal recorded',
      P5TimelineCategory.policy => 'Policy decision recorded',
      P5TimelineCategory.file => 'File observation recorded',
      P5TimelineCategory.terminal => 'Terminal receipt recorded',
      P5TimelineCategory.browser => 'Browser action recorded',
      P5TimelineCategory.web => 'Web research step recorded',
      P5TimelineCategory.evidence => 'Evidence reference recorded',
      P5TimelineCategory.verification => 'Verification result recorded',
      P5TimelineCategory.retry => 'Retry decision recorded',
      P5TimelineCategory.rollback => 'Rollback checkpoint recorded',
    };
    final detail = switch (category) {
      P5TimelineCategory.model =>
        'Deterministic saved-run fixture model event; no live model call is claimed.',
      P5TimelineCategory.policy =>
        'Deterministic saved-run fixture policy event; no new authority is granted.',
      P5TimelineCategory.file =>
        'Deterministic saved-run fixture file event; no filesystem mutation occurred.',
      P5TimelineCategory.terminal =>
        'Deterministic saved-run fixture terminal event; no process was started.',
      P5TimelineCategory.browser =>
        'Deterministic saved-run fixture browser event; no browser action was executed.',
      P5TimelineCategory.web =>
        'Deterministic saved-run fixture web event; no network request was executed.',
      P5TimelineCategory.evidence =>
        'Deterministic saved-run fixture evidence event; not a live evidence-store receipt.',
      P5TimelineCategory.verification =>
        'Deterministic saved-run fixture verification event; not a certification claim.',
      P5TimelineCategory.retry =>
        'Deterministic saved-run fixture retry event; no operation was repeated.',
      P5TimelineCategory.rollback =>
        'Deterministic saved-run fixture rollback event; no rollback was executed.',
    };
    return P5TimelineEvent(
      runId: runId,
      sequence: sequence,
      category: category,
      timestampLabel: 'T+${zeroBasedSequence}s',
      title: title,
      detail: detail,
    );
  }

  static List<P5EvidenceArtifactFixture> evidenceArtifactsForRun(
    String runId,
  ) {
    if (!runs.any((run) => run.id == runId)) {
      return const <P5EvidenceArtifactFixture>[];
    }
    const fixtureOrigin = <String, String>{
      'origin': 'deterministic saved-run fixture',
      'authority': 'presentation only',
    };
    return <P5EvidenceArtifactFixture>[
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.text',
        runId: runId,
        kind: P5EvidenceViewKind.text,
        title: 'Planner notes',
        mediaType: 'text/plain',
        content:
            'Deterministic saved-run text fixture. No live file or evidence store is read.',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.binary-metadata',
        runId: runId,
        kind: P5EvidenceViewKind.binaryMetadata,
        title: 'Binary attachment metadata',
        mediaType: 'application/octet-stream',
        content:
            'Binary payload is intentionally not embedded in this presentation fixture.',
        metadata: <String, String>{
          ...fixtureOrigin,
          'size': '4096 bytes (fixture)',
          'content': 'metadata only',
        },
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.image',
        runId: runId,
        kind: P5EvidenceViewKind.image,
        title: 'Screenshot fixture',
        mediaType: 'image/png',
        content:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.markdown',
        runId: runId,
        kind: P5EvidenceViewKind.markdown,
        title: 'Markdown summary',
        mediaType: 'text/markdown',
        content:
            '# Saved run evidence\n\n- deterministic fixture\n- no live side effect\n- no production claim',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.json',
        runId: runId,
        kind: P5EvidenceViewKind.json,
        title: 'Structured result',
        mediaType: 'application/json',
        content:
            '{"runId":"$runId","fixture":true,"state":"NOT_PRODUCTION_EVIDENCE"}',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.table',
        runId: runId,
        kind: P5EvidenceViewKind.table,
        title: 'Verification table',
        mediaType: 'application/vnd.kristin.table+json',
        content:
            '[["Check","State"],["Navigation","PASS"],["Certification","NOT_EVALUATED"]]',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.diff',
        runId: runId,
        kind: P5EvidenceViewKind.diff,
        title: 'Fixture diff',
        mediaType: 'text/x-diff',
        content: '@@ -1 +1 @@\n-old fixture label\n+new fixture label',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.citation',
        runId: runId,
        kind: P5EvidenceViewKind.citation,
        title: 'Citation fixture',
        mediaType: 'application/vnd.kristin.citation+json',
        content:
            '{"title":"Fixture source","locator":"fixture://source/p5-009","span":"deterministic citation span"}',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.receipt',
        runId: runId,
        kind: P5EvidenceViewKind.receipt,
        title: 'Effect receipt fixture',
        mediaType: 'application/vnd.kristin.receipt+json',
        content:
            '{"runId":"$runId","effectId":"fixture-effect-001","status":"SIMULATED","authority":"none"}',
        metadata: fixtureOrigin,
      ),
    ];
  }

  static const List<P5VerificationFixture> verificationResults =
      <P5VerificationFixture>[
    P5VerificationFixture(
      testId: 'tc.p5-001.navigation.primary-workspaces',
      title: 'Primary workspaces are reachable',
      state: P5VerificationResultState.pass,
      evidenceLabel: 'Widget result fixture',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.flow.simple-task',
      title: 'Simple task flow',
      state: P5VerificationResultState.pass,
      evidenceLabel: 'Deterministic scenario fixture',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.flow.existing-run',
      title: 'Existing run continuity',
      state: P5VerificationResultState.flaky,
      evidenceLabel: 'Retry required before certification',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.flow.owner-mode',
      title: 'Owner Mode presentation boundary',
      state: P5VerificationResultState.blocked,
      evidenceLabel: 'Controlled behavior remains BLOCKED_EXTERNAL',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.flow.verification-center',
      title: 'Verification domain separation',
      state: P5VerificationResultState.pass,
      evidenceLabel: 'Presentation contract fixture',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.state.transitions',
      title: 'State-transition contract',
      state: P5VerificationResultState.error,
      evidenceLabel: 'Representative infrastructure error fixture',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.mode.progressive-disclosure',
      title: 'Progressive disclosure',
      state: P5VerificationResultState.skipped,
      evidenceLabel: 'Representative skipped result fixture',
    ),
    P5VerificationFixture(
      testId: 'tc.p5-001.capability.honest-unavailable',
      title: 'Unavailable capability honest',
      state: P5VerificationResultState.notImplemented,
      evidenceLabel: 'Future capability is not implemented',
    ),
  ];

  static const List<P5CapabilityFixture> capabilities = <P5CapabilityFixture>[
    P5CapabilityFixture(
      workspace: P5WorkspaceId.webStudio,
      state: P5CapabilityPresentationState.experimental,
      reason:
          'P3-002 through P3-006B browser sessions, observations, actions, downloads, and uploads are landed and consumable from Experience.',
      nextRequirement:
          'Complete P3-007/P3-009/P3-011 and land the independently owned editor, preview, and inspector slices before claiming the full roadmap Web Studio.',
    ),
    P5CapabilityFixture(
      workspace: P5WorkspaceId.searchResearch,
      state: P5CapabilityPresentationState.sourceFoundation,
      reason: 'P4-001 exposes source contracts, not usable product behavior.',
      nextRequirement:
          'Integrate provider behavior only after the P3 dependency is satisfied.',
    ),
    P5CapabilityFixture(
      workspace: P5WorkspaceId.nativeAutomation,
      state: P5CapabilityPresentationState.notImplemented,
      reason: 'No three-platform native behavioral evidence exists.',
      nextRequirement:
          'Complete the P11 dependency decision and native conformance evidence.',
    ),
    P5CapabilityFixture(
      workspace: P5WorkspaceId.devices,
      state: P5CapabilityPresentationState.unavailable,
      reason: 'No device runtime is connected to this prototype.',
      nextRequirement: 'Implement governed device contracts in a later phase.',
    ),
  ];

  static const List<P5FailureRecoveryFixture> failures =
      <P5FailureRecoveryFixture>[
    P5FailureRecoveryFixture(
      id: 'failure.no-project',
      title: 'No project',
      state: 'EMPTY',
      message: 'Select or create a local project before starting a task.',
      recoveryAction: 'Choose a sample project',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.no-model',
      title: 'No model',
      state: 'BLOCKED',
      message: 'No model is configured. Planning cannot begin.',
      recoveryAction: 'Open Models and Providers',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.offline',
      title: 'Offline',
      state: 'BLOCKED',
      message:
          'External providers are unavailable; local work remains visible.',
      recoveryAction: 'Use local-only fixtures',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.permission-denied',
      title: 'Permission denied',
      state: 'ERROR',
      message: 'The requested effect was not authorized.',
      recoveryAction: 'Review the requested access',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.capability-blocked',
      title: 'Capability blocked',
      state: 'BLOCKED',
      message: 'The capability dependency is not complete.',
      recoveryAction: 'Open capability requirements',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.interrupted-run',
      title: 'Interrupted run',
      state: 'PAUSED',
      message: 'A saved run can be reopened without losing context.',
      recoveryAction: 'Resume the saved run',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.test-fail',
      title: 'Test failed',
      state: 'FAIL',
      message: 'An assertion failed; certification remains not evaluated.',
      recoveryAction: 'Open failing evidence',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.test-error',
      title: 'Test error',
      state: 'ERROR',
      message: 'The runner failed before a valid assertion result.',
      recoveryAction: 'Inspect runner diagnostics',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.test-skipped',
      title: 'Test skipped',
      state: 'SKIPPED',
      message: 'A skipped test is not a pass.',
      recoveryAction: 'Inspect skip reason',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.test-blocked',
      title: 'Test blocked',
      state: 'BLOCKED',
      message: 'A declared dependency prevented execution.',
      recoveryAction: 'Open dependency details',
    ),
    P5FailureRecoveryFixture(
      id: 'failure.test-not-implemented',
      title: 'Test not implemented',
      state: 'NOT_IMPLEMENTED',
      message: 'No executable check exists for this future behavior.',
      recoveryAction: 'Open required next work',
    ),
  ];

  static P5PresentationState initialState() {
    const states = <P5WorkspaceId, P5WorkspaceState>{
      P5WorkspaceId.homeChat: P5WorkspaceState.ready,
      P5WorkspaceId.projects: P5WorkspaceState.ready,
      P5WorkspaceId.runsActivity: P5WorkspaceState.ready,
      P5WorkspaceId.verificationCenter: P5WorkspaceState.ready,
      P5WorkspaceId.evidence: P5WorkspaceState.ready,
      P5WorkspaceId.ownerMode: P5WorkspaceState.blocked,
      P5WorkspaceId.modelsProviders: P5WorkspaceState.ready,
      P5WorkspaceId.capabilitiesIntegrations: P5WorkspaceState.ready,
      P5WorkspaceId.settingsDiagnostics: P5WorkspaceState.ready,
      P5WorkspaceId.webStudio: P5WorkspaceState.ready,
      P5WorkspaceId.searchResearch: P5WorkspaceState.unavailable,
      P5WorkspaceId.nativeAutomation: P5WorkspaceState.unavailable,
      P5WorkspaceId.devices: P5WorkspaceState.unavailable,
    };
    return const P5PresentationState(
      experienceLevel: P5ExperienceLevel.simple,
      workspace: P5WorkspaceId.homeChat,
      workspaceStates: states,
      selectedProjectId: 'project.kristin-local',
      selectedRunId: null,
      runState: P5RunPresentationState.planReady,
      ownerModeState: P5OwnerModePresentationState.blockedByEnvironment,
      navigationHistory: <P5WorkspaceId>[P5WorkspaceId.homeChat],
      navigationIndex: 0,
      reopenWorkspace: P5WorkspaceId.homeChat,
      planReviewed: false,
      planOnly: false,
      taskDraft: 'Review the current navigation and verification experience.',
      composerProfile: P5ComposerProfile.project,
      composerModel: P5ComposerModel.automatic,
      composerAccess: P5ComposerAccess.profileDefault,
      composerLaunchTiming: P5ComposerLaunchTiming.runNow,
      composerBudget: P5ComposerBudget.balanced,
      attachments: <String>[],
      acceptanceCriteria: <String>[
        'Requested outcome is explicit and independently verifiable.',
      ],
      recoveryMessage: null,
      verificationRequested: false,
    );
  }
}
