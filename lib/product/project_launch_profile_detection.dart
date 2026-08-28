import 'domain.dart';

/// Maps `ProjectDiagnosticsService`'s already-detected
/// `ProjectExecutionProfile.type` (e.g. `'Flutter'`, `'Node.js / JavaScript'`)
/// onto a [ProjectLaunchKind], so a durable [ProjectLaunchProfile] can be
/// recorded without re-implementing toolchain detection. Conservative by
/// design: anything not confidently desktop or web falls back to
/// [ProjectLaunchKind.command], never guessed as a server/web target from
/// weak evidence.
ProjectLaunchKind detectProjectLaunchKind(String executionProfileType) {
  switch (executionProfileType) {
    case 'Flutter':
      return ProjectLaunchKind.desktop;
    case 'Node.js / JavaScript':
    case 'Static website':
      return ProjectLaunchKind.web;
    default:
      return ProjectLaunchKind.command;
  }
}

/// What the Project Manager should do once a launch profile of [kind] is
/// observed running/healthy.
ProjectLaunchOpenBehavior openBehaviorForLaunchKind(ProjectLaunchKind kind) {
  switch (kind) {
    case ProjectLaunchKind.desktop:
      return ProjectLaunchOpenBehavior.focusNativeApp;
    case ProjectLaunchKind.web:
    case ProjectLaunchKind.server:
      return ProjectLaunchOpenBehavior.openWebStudio;
    case ProjectLaunchKind.command:
    case ProjectLaunchKind.other:
      return ProjectLaunchOpenBehavior.none;
  }
}
