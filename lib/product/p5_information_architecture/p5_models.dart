import 'package:flutter/foundation.dart';

import '../access_profile_v2.dart';

enum P5ExperienceLevel { simple, advanced, developer }

enum P5WorkspaceId {
  homeChat,
  projects,
  runsActivity,
  verificationCenter,
  evidence,
  ownerMode,
  modelsProviders,
  capabilitiesIntegrations,
  settingsDiagnostics,
  webStudio,
  searchResearch,
  nativeAutomation,
  devices,
}

enum P5WorkspaceState {
  empty,
  loading,
  ready,
  running,
  paused,
  blocked,
  error,
  completed,
  unavailable,
}

enum P5CapabilityPresentationState {
  notImplemented,
  sourceFoundation,
  blockedByDependency,
  unsupported,
  unavailable,
  experimental,
  behaviorSupported,
  platformSupported,
  releaseSupported,
}

enum P5RunPresentationState {
  planReady,
  planOnly,
  ready,
  running,
  paused,
  stopping,
  completed,
  interrupted,
  blocked,
  error,
}

enum P5VerificationResultState {
  pass,
  fail,
  error,
  skipped,
  blocked,
  unknown,
  flaky,
  notImplemented,
}

enum P5CertificationPresentationState {
  notEvaluated,
  partial,
  pass,
  fail,
  stale,
  revoked,
}

enum P5OwnerModePresentationState {
  unavailable,
  disabled,
  availableNotEnabled,
  enabled,
  running,
  paused,
  stopping,
  blockedByEnvironment,
  error,
}

enum P5ComposerProfile { project, owner, ownerUnattended, isolatedUntrusted }

enum P5ComposerModel { automatic, localFast, localDeep }

enum P5ComposerAccess { profileDefault, readOnly, requestAdditional }

enum P5ComposerLaunchTiming { runNow, laterToday, tomorrowMorning }

enum P5ComposerBudget { focused, balanced, thorough }

enum P5TimelineCategory {
  model,
  policy,
  file,
  terminal,
  browser,
  web,
  evidence,
  verification,
  retry,
  rollback,
}

extension P5TimelineCategoryLabel on P5TimelineCategory {
  String get label => switch (this) {
        P5TimelineCategory.model => 'Model',
        P5TimelineCategory.policy => 'Policy',
        P5TimelineCategory.file => 'File',
        P5TimelineCategory.terminal => 'Terminal',
        P5TimelineCategory.browser => 'Browser',
        P5TimelineCategory.web => 'Web',
        P5TimelineCategory.evidence => 'Evidence',
        P5TimelineCategory.verification => 'Verification',
        P5TimelineCategory.retry => 'Retry',
        P5TimelineCategory.rollback => 'Rollback',
      };
}

@immutable
class P5TimelineEvent {
  const P5TimelineEvent({
    required this.runId,
    required this.sequence,
    required this.category,
    required this.timestampLabel,
    required this.title,
    required this.detail,
  });

  final String runId;
  final int sequence;
  final P5TimelineCategory category;
  final String timestampLabel;
  final String title;
  final String detail;
}

enum P5EvidenceKind {
  textMetadata,
  binaryMetadata,
  image,
  markdown,
  json,
  table,
  diff,
  citation,
  receipt,
}

extension P5EvidenceKindLabel on P5EvidenceKind {
  String get label => switch (this) {
        P5EvidenceKind.textMetadata => 'Text metadata',
        P5EvidenceKind.binaryMetadata => 'Binary metadata',
        P5EvidenceKind.image => 'Image',
        P5EvidenceKind.markdown => 'Markdown',
        P5EvidenceKind.json => 'JSON',
        P5EvidenceKind.table => 'Table',
        P5EvidenceKind.diff => 'Diff',
        P5EvidenceKind.citation => 'Citation',
        P5EvidenceKind.receipt => 'Receipt',
      };
}

@immutable
class P5EvidenceFixture {
  const P5EvidenceFixture({
    required this.id,
    required this.runId,
    required this.kind,
    required this.title,
    required this.mediaType,
    required this.byteLength,
    required this.summary,
    required this.content,
  });

  final String id;
  final String runId;
  final P5EvidenceKind kind;
  final String title;
  final String mediaType;
  final int byteLength;
  final String summary;
  final String content;
}

extension P5ComposerProfileLabel on P5ComposerProfile {
  String get label => switch (this) {
        P5ComposerProfile.project => 'Project',
        P5ComposerProfile.owner => 'Owner',
        P5ComposerProfile.ownerUnattended => 'Owner unattended',
        P5ComposerProfile.isolatedUntrusted => 'Isolated untrusted',
      };

  AccessProfileId get accessProfileId => switch (this) {
        P5ComposerProfile.project => AccessProfileId.project,
        P5ComposerProfile.owner => AccessProfileId.owner,
        P5ComposerProfile.ownerUnattended => AccessProfileId.ownerUnattended,
        P5ComposerProfile.isolatedUntrusted =>
          AccessProfileId.isolatedUntrusted,
      };

  ApprovalPolicy get approvalPolicy => switch (this) {
        P5ComposerProfile.project => ApprovalPolicy.highRiskOnly,
        P5ComposerProfile.owner => ApprovalPolicy.highRiskOnly,
        P5ComposerProfile.ownerUnattended => ApprovalPolicy.never,
        P5ComposerProfile.isolatedUntrusted => ApprovalPolicy.always,
      };

  String get approvalPolicyLabel => switch (approvalPolicy) {
        ApprovalPolicy.always => 'ALWAYS',
        ApprovalPolicy.highRiskOnly => 'HIGH_RISK_ONLY',
        ApprovalPolicy.never => 'NEVER',
      };

  String get approvalPolicyExplanation => switch (approvalPolicy) {
        ApprovalPolicy.always =>
          'Approval prompts are required by this profile before governed effects proceed.',
        ApprovalPolicy.highRiskOnly =>
          'High-risk effects require approval. Lower-risk effects still require deterministic policy authorization.',
        ApprovalPolicy.never =>
          'No approval prompts are required by this profile. This does not grant capabilities, widen the profile ceiling, or bypass deterministic policy and overlay denials.',
      };
}

extension P5ComposerModelLabel on P5ComposerModel {
  String get label => switch (this) {
        P5ComposerModel.automatic => 'Automatic',
        P5ComposerModel.localFast => 'Local fast',
        P5ComposerModel.localDeep => 'Local deep',
      };
}

extension P5ComposerAccessLabel on P5ComposerAccess {
  String get label => switch (this) {
        P5ComposerAccess.profileDefault => 'Profile default',
        P5ComposerAccess.readOnly => 'Read only',
        P5ComposerAccess.requestAdditional => 'Request additional',
      };
}

extension P5ComposerLaunchTimingLabel on P5ComposerLaunchTiming {
  String get label => switch (this) {
        P5ComposerLaunchTiming.runNow => 'Run now',
        P5ComposerLaunchTiming.laterToday => 'Later today',
        P5ComposerLaunchTiming.tomorrowMorning => 'Tomorrow morning',
      };
}

extension P5ComposerBudgetLabel on P5ComposerBudget {
  String get label => switch (this) {
        P5ComposerBudget.focused => 'Focused',
        P5ComposerBudget.balanced => 'Balanced',
        P5ComposerBudget.thorough => 'Thorough',
      };
}

enum P5PrototypeAction {
  createSampleProject,
  clearProject,
  reviewPlan,
  choosePlanOnly,
  startRun,
  pauseRun,
  resumeRun,
  stopRun,
  completeRun,
  openEvidence,
  runVerification,
  retryInterruptedRun,
  restoreModelFixture,
  acknowledgeOfflineFixture,
}

extension P5ExperienceLevelLabel on P5ExperienceLevel {
  String get label => switch (this) {
        P5ExperienceLevel.simple => 'Simple',
        P5ExperienceLevel.advanced => 'Advanced',
        P5ExperienceLevel.developer => 'Developer',
      };
}

extension P5WorkspaceIdLabel on P5WorkspaceId {
  String get label => switch (this) {
        P5WorkspaceId.homeChat => 'Home / Chat',
        P5WorkspaceId.projects => 'Projects',
        P5WorkspaceId.runsActivity => 'Runs / Activity',
        P5WorkspaceId.verificationCenter => 'Verification Center',
        P5WorkspaceId.evidence => 'Evidence',
        P5WorkspaceId.ownerMode => 'Owner Mode',
        P5WorkspaceId.modelsProviders => 'Models and Providers',
        P5WorkspaceId.capabilitiesIntegrations =>
          'Capabilities and Integrations',
        P5WorkspaceId.settingsDiagnostics => 'Settings and Diagnostics',
        P5WorkspaceId.webStudio => 'Web Studio',
        P5WorkspaceId.searchResearch => 'Search and Research',
        P5WorkspaceId.nativeAutomation => 'Native Automation',
        P5WorkspaceId.devices => 'Devices',
      };

  bool get isFutureCapability => const <P5WorkspaceId>{
        P5WorkspaceId.searchResearch,
        P5WorkspaceId.nativeAutomation,
        P5WorkspaceId.devices,
      }.contains(this);
}

extension P5WorkspaceStateLabel on P5WorkspaceState {
  String get label => name.toUpperCase();
}

extension P5CapabilityStateLabel on P5CapabilityPresentationState {
  String get label => switch (this) {
        P5CapabilityPresentationState.notImplemented => 'NOT_IMPLEMENTED',
        P5CapabilityPresentationState.sourceFoundation => 'SOURCE_FOUNDATION',
        P5CapabilityPresentationState.blockedByDependency =>
          'BLOCKED_BY_DEPENDENCY',
        P5CapabilityPresentationState.unsupported => 'UNSUPPORTED',
        P5CapabilityPresentationState.unavailable => 'UNAVAILABLE',
        P5CapabilityPresentationState.experimental => 'EXPERIMENTAL',
        P5CapabilityPresentationState.behaviorSupported => 'BEHAVIOR_SUPPORTED',
        P5CapabilityPresentationState.platformSupported => 'PLATFORM_SUPPORTED',
        P5CapabilityPresentationState.releaseSupported => 'RELEASE_SUPPORTED',
      };
}

extension P5RunStateLabel on P5RunPresentationState {
  String get label => switch (this) {
        P5RunPresentationState.planReady => 'Plan ready',
        P5RunPresentationState.planOnly => 'Plan only',
        P5RunPresentationState.ready => 'Ready to start',
        P5RunPresentationState.running => 'Running',
        P5RunPresentationState.paused => 'Paused',
        P5RunPresentationState.stopping => 'Stopping safely',
        P5RunPresentationState.completed => 'Completed',
        P5RunPresentationState.interrupted => 'Interrupted',
        P5RunPresentationState.blocked => 'Blocked',
        P5RunPresentationState.error => 'Error',
      };
}

extension P5VerificationStateLabel on P5VerificationResultState {
  String get label => switch (this) {
        P5VerificationResultState.pass => 'PASS',
        P5VerificationResultState.fail => 'FAIL',
        P5VerificationResultState.error => 'ERROR',
        P5VerificationResultState.skipped => 'SKIPPED',
        P5VerificationResultState.blocked => 'BLOCKED',
        P5VerificationResultState.unknown => 'UNKNOWN',
        P5VerificationResultState.flaky => 'FLAKY',
        P5VerificationResultState.notImplemented => 'NOT_IMPLEMENTED',
      };
}

extension P5CertificationStateLabel on P5CertificationPresentationState {
  String get label => switch (this) {
        P5CertificationPresentationState.notEvaluated => 'NOT_EVALUATED',
        P5CertificationPresentationState.partial => 'PARTIAL',
        P5CertificationPresentationState.pass => 'PASS',
        P5CertificationPresentationState.fail => 'FAIL',
        P5CertificationPresentationState.stale => 'STALE',
        P5CertificationPresentationState.revoked => 'REVOKED',
      };
}

extension P5OwnerModeStateLabel on P5OwnerModePresentationState {
  String get label => switch (this) {
        P5OwnerModePresentationState.unavailable => 'Unavailable',
        P5OwnerModePresentationState.disabled => 'Disabled',
        P5OwnerModePresentationState.availableNotEnabled =>
          'Available, not enabled',
        P5OwnerModePresentationState.enabled => 'Enabled',
        P5OwnerModePresentationState.running => 'Running',
        P5OwnerModePresentationState.paused => 'Paused',
        P5OwnerModePresentationState.stopping => 'Stopping',
        P5OwnerModePresentationState.blockedByEnvironment =>
          'Blocked by environment',
        P5OwnerModePresentationState.error => 'Error',
      };
}

@immutable
class P5WorkspaceDefinition {
  const P5WorkspaceDefinition({
    required this.id,
    required this.description,
    required this.minimumLevel,
    this.primary = false,
  });

  final P5WorkspaceId id;
  final String description;
  final P5ExperienceLevel minimumLevel;
  final bool primary;
}

@immutable
class P5ProjectFixture {
  const P5ProjectFixture({
    required this.id,
    required this.name,
    required this.pathLabel,
  });

  final String id;
  final String name;
  final String pathLabel;
}

@immutable
class P5RunFixture {
  const P5RunFixture({
    required this.id,
    required this.projectId,
    required this.title,
    required this.state,
    required this.updatedAtLabel,
  });

  final String id;
  final String projectId;
  final String title;
  final P5RunPresentationState state;
  final String updatedAtLabel;
}

@immutable
class P5VerificationFixture {
  const P5VerificationFixture({
    required this.testId,
    required this.title,
    required this.state,
    required this.evidenceLabel,
  });

  final String testId;
  final String title;
  final P5VerificationResultState state;
  final String evidenceLabel;
}

@immutable
class P5CapabilityFixture {
  const P5CapabilityFixture({
    required this.workspace,
    required this.state,
    required this.reason,
    required this.nextRequirement,
  });

  final P5WorkspaceId workspace;
  final P5CapabilityPresentationState state;
  final String reason;
  final String nextRequirement;
}

@immutable
class P5FailureRecoveryFixture {
  const P5FailureRecoveryFixture({
    required this.id,
    required this.title,
    required this.state,
    required this.message,
    required this.recoveryAction,
  });

  final String id;
  final String title;
  final String state;
  final String message;
  final String recoveryAction;
}

@immutable
class P5SideEffectLedger {
  const P5SideEffectLedger({
    required this.filesystemMutations,
    required this.networkRequests,
    required this.runtimeCommands,
    required this.ownerModeActions,
    required this.deviceRequests,
  });

  static const P5SideEffectLedger zero = P5SideEffectLedger(
    filesystemMutations: 0,
    networkRequests: 0,
    runtimeCommands: 0,
    ownerModeActions: 0,
    deviceRequests: 0,
  );

  final int filesystemMutations;
  final int networkRequests;
  final int runtimeCommands;
  final int ownerModeActions;
  final int deviceRequests;

  bool get isZero =>
      filesystemMutations == 0 &&
      networkRequests == 0 &&
      runtimeCommands == 0 &&
      ownerModeActions == 0 &&
      deviceRequests == 0;

  @override
  bool operator ==(Object other) =>
      other is P5SideEffectLedger &&
      other.filesystemMutations == filesystemMutations &&
      other.networkRequests == networkRequests &&
      other.runtimeCommands == runtimeCommands &&
      other.ownerModeActions == ownerModeActions &&
      other.deviceRequests == deviceRequests;

  @override
  int get hashCode => Object.hash(
        filesystemMutations,
        networkRequests,
        runtimeCommands,
        ownerModeActions,
        deviceRequests,
      );
}

@immutable
class P5PresentationState {
  const P5PresentationState({
    required this.experienceLevel,
    required this.workspace,
    required this.workspaceStates,
    required this.selectedProjectId,
    required this.selectedRunId,
    this.selectedEvidenceId,
    required this.runState,
    required this.ownerModeState,
    required this.navigationHistory,
    required this.navigationIndex,
    required this.reopenWorkspace,
    required this.planReviewed,
    required this.planOnly,
    required this.taskDraft,
    required this.composerProfile,
    required this.composerModel,
    required this.composerAccess,
    required this.composerLaunchTiming,
    required this.composerBudget,
    required this.attachments,
    required this.acceptanceCriteria,
    required this.recoveryMessage,
    required this.verificationRequested,
  });

  final P5ExperienceLevel experienceLevel;
  final P5WorkspaceId workspace;
  final Map<P5WorkspaceId, P5WorkspaceState> workspaceStates;
  final String? selectedProjectId;
  final String? selectedRunId;
  final String? selectedEvidenceId;
  final P5RunPresentationState runState;
  final P5OwnerModePresentationState ownerModeState;
  final List<P5WorkspaceId> navigationHistory;
  final int navigationIndex;
  final P5WorkspaceId reopenWorkspace;
  final bool planReviewed;
  final bool planOnly;
  final String taskDraft;
  final P5ComposerProfile composerProfile;
  final P5ComposerModel composerModel;
  final P5ComposerAccess composerAccess;
  final P5ComposerLaunchTiming composerLaunchTiming;
  final P5ComposerBudget composerBudget;
  final List<String> attachments;
  final List<String> acceptanceCriteria;
  final String? recoveryMessage;
  final bool verificationRequested;

  P5WorkspaceState get currentWorkspaceState =>
      workspaceStates[workspace] ?? P5WorkspaceState.ready;

  P5PresentationState copyWith({
    P5ExperienceLevel? experienceLevel,
    P5WorkspaceId? workspace,
    Map<P5WorkspaceId, P5WorkspaceState>? workspaceStates,
    Object? selectedProjectId = _notProvided,
    Object? selectedRunId = _notProvided,
    Object? selectedEvidenceId = _notProvided,
    P5RunPresentationState? runState,
    P5OwnerModePresentationState? ownerModeState,
    List<P5WorkspaceId>? navigationHistory,
    int? navigationIndex,
    P5WorkspaceId? reopenWorkspace,
    bool? planReviewed,
    bool? planOnly,
    String? taskDraft,
    P5ComposerProfile? composerProfile,
    P5ComposerModel? composerModel,
    P5ComposerAccess? composerAccess,
    P5ComposerLaunchTiming? composerLaunchTiming,
    P5ComposerBudget? composerBudget,
    List<String>? attachments,
    List<String>? acceptanceCriteria,
    Object? recoveryMessage = _notProvided,
    bool? verificationRequested,
  }) {
    return P5PresentationState(
      experienceLevel: experienceLevel ?? this.experienceLevel,
      workspace: workspace ?? this.workspace,
      workspaceStates: workspaceStates ?? this.workspaceStates,
      selectedProjectId: identical(selectedProjectId, _notProvided)
          ? this.selectedProjectId
          : selectedProjectId as String?,
      selectedRunId: identical(selectedRunId, _notProvided)
          ? this.selectedRunId
          : selectedRunId as String?,
      selectedEvidenceId: identical(selectedEvidenceId, _notProvided)
          ? this.selectedEvidenceId
          : selectedEvidenceId as String?,
      runState: runState ?? this.runState,
      ownerModeState: ownerModeState ?? this.ownerModeState,
      navigationHistory: navigationHistory ?? this.navigationHistory,
      navigationIndex: navigationIndex ?? this.navigationIndex,
      reopenWorkspace: reopenWorkspace ?? this.reopenWorkspace,
      planReviewed: planReviewed ?? this.planReviewed,
      planOnly: planOnly ?? this.planOnly,
      taskDraft: taskDraft ?? this.taskDraft,
      composerProfile: composerProfile ?? this.composerProfile,
      composerModel: composerModel ?? this.composerModel,
      composerAccess: composerAccess ?? this.composerAccess,
      composerLaunchTiming: composerLaunchTiming ?? this.composerLaunchTiming,
      composerBudget: composerBudget ?? this.composerBudget,
      attachments: attachments ?? this.attachments,
      acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
      recoveryMessage: identical(recoveryMessage, _notProvided)
          ? this.recoveryMessage
          : recoveryMessage as String?,
      verificationRequested:
          verificationRequested ?? this.verificationRequested,
    );
  }
}

const Object _notProvided = Object();

class P5InvalidTransition implements Exception {
  const P5InvalidTransition({
    required this.from,
    required this.to,
  });

  final P5WorkspaceState from;
  final P5WorkspaceState to;

  @override
  String toString() =>
      'P5InvalidTransition: ${from.label} cannot transition to ${to.label}';
}

class P5WorkspaceTransitionGraph {
  const P5WorkspaceTransitionGraph._();

  static const Map<P5WorkspaceState, Set<P5WorkspaceState>> allowed =
      <P5WorkspaceState, Set<P5WorkspaceState>>{
    P5WorkspaceState.empty: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.ready,
      P5WorkspaceState.blocked,
      P5WorkspaceState.error,
      P5WorkspaceState.unavailable,
    },
    P5WorkspaceState.loading: <P5WorkspaceState>{
      P5WorkspaceState.empty,
      P5WorkspaceState.ready,
      P5WorkspaceState.blocked,
      P5WorkspaceState.error,
      P5WorkspaceState.unavailable,
    },
    P5WorkspaceState.ready: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.running,
      P5WorkspaceState.blocked,
      P5WorkspaceState.error,
      P5WorkspaceState.completed,
      P5WorkspaceState.unavailable,
    },
    P5WorkspaceState.running: <P5WorkspaceState>{
      P5WorkspaceState.paused,
      P5WorkspaceState.blocked,
      P5WorkspaceState.error,
      P5WorkspaceState.completed,
    },
    P5WorkspaceState.paused: <P5WorkspaceState>{
      P5WorkspaceState.running,
      P5WorkspaceState.blocked,
      P5WorkspaceState.error,
      P5WorkspaceState.completed,
    },
    P5WorkspaceState.blocked: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.ready,
      P5WorkspaceState.error,
      P5WorkspaceState.unavailable,
    },
    P5WorkspaceState.error: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.ready,
      P5WorkspaceState.blocked,
    },
    P5WorkspaceState.completed: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.ready,
    },
    P5WorkspaceState.unavailable: <P5WorkspaceState>{
      P5WorkspaceState.loading,
      P5WorkspaceState.ready,
    },
  };

  static bool canTransition(
    P5WorkspaceState from,
    P5WorkspaceState to,
  ) =>
      from == to || (allowed[from]?.contains(to) ?? false);

  static void validate(
    P5WorkspaceState from,
    P5WorkspaceState to,
  ) {
    if (!canTransition(from, to)) {
      throw P5InvalidTransition(from: from, to: to);
    }
  }
}
