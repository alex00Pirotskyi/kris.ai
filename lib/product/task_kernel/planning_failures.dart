// Typed planning failures.
//
// The predecessor change (PR #288) wrapped the entire model-planning,
// persistence and compile pipeline in a single `catch (_)` and answered
// every possible error with "here is the conservative plan". That is
// wrong in a specific, dangerous way: it converts user cancellation,
// a missing provider, a denied permission, a corrupted database and an
// ordinary programming defect into the same cheerful fallback, and the
// user is told a safety-net plan is ready when in fact their data store
// is broken or they pressed Cancel.
//
// A conservative fallback plan is a legitimate answer to exactly one
// question -- "the planning model could not produce a valid task graph"
// -- and to nothing else. This file makes that distinction explicit and
// checkable.
import '../storage_security.dart';

/// What kind of thing went wrong while producing a plan.
///
/// Only [recoverablePlanning] may degrade to the deterministic
/// conservative planner. Every other kind has its own honest outcome.
enum PlanningFailureKind {
  /// The planning model did not produce a valid task graph, even after
  /// the planner's own bounded repair attempt; or it violated the
  /// planning protocol in a documented, recognized way. The request
  /// itself is fine and a conservative plan is a real answer to it.
  ///
  /// This is the ONLY kind for which fallback is permitted.
  recoverablePlanning,

  /// The user cancelled. Not a failure of anything, and emphatically not
  /// a reason to hand them a plan they did not ask for.
  cancelled,

  /// The selected model or provider is unavailable, unreachable, or not
  /// configured. Kristin is blocked and must say so; a fallback plan
  /// would imply planning succeeded when no model ever ran.
  providerUnavailable,

  /// Authority or permission refused the operation. This is a governance
  /// outcome that the user must see as a governance outcome.
  permissionDenied,

  /// Storage, repository, audit or event-journal failure. The system is
  /// in a degraded state; producing a plan on top of it would be
  /// building on sand.
  persistenceFailure,

  /// Anything not recognized: a programming defect, an unexpected
  /// runtime error, an invariant violation. Reported as a real failure
  /// with evidence, never laundered into a plan.
  unexpected,
}

extension PlanningFailureKindX on PlanningFailureKind {
  /// Whether a deterministic conservative plan is an honest answer to
  /// this failure. True for exactly one kind, by design.
  bool get allowsConservativeFallback =>
      this == PlanningFailureKind.recoverablePlanning;
}

/// A classified planning failure, carrying enough evidence to explain
/// itself without re-throwing raw internals at the user.
class PlanningFailure implements Exception {
  const PlanningFailure({
    required this.kind,
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
    this.cause,
  });

  final PlanningFailureKind kind;

  /// The originating error code where one existed (`task_plan_invalid`,
  /// `cancelled`, ...), or a kernel-assigned code otherwise.
  final String code;
  final String message;
  final Map<String, dynamic> details;
  final Object? cause;

  bool get allowsConservativeFallback => kind.allowsConservativeFallback;

  Map<String, dynamic> toEvidence() => <String, dynamic>{
        'kind': kind.name,
        'code': code,
        'message': message,
        'fallbackAllowed': allowsConservativeFallback,
        if (details.isNotEmpty) 'details': details,
      };

  @override
  String toString() => '${kind.name}/$code: $message';
}

/// Error codes that mean "the planning model could not produce a valid
/// task graph" -- the documented, recoverable planning protocol failures.
///
/// This list is deliberately explicit and short. Adding a code here is a
/// decision to let that failure degrade into a conservative plan, and
/// should be made deliberately rather than by a catch-all.
const Set<String> kRecoverablePlanningCodes = <String>{
  // The generated task plan failed schema/dependency/hierarchy validation
  // after generation and one bounded repair (PromptPlanningService).
  'task_plan_invalid',
  'task_dependency_missing',
  'task_parent_missing',
  // The compiled contract or execution plan failed structural validation.
  'contract_invalid',
  'plan_invalid',
  // The model proposed a task requiring a governed mutation tool it was
  // not given, i.e. a plan-shape failure rather than a system failure.
  'task_mutation_tools_missing',
  // The generated plan selected no runnable task, or left a manual task
  // unresolved: both are plan-shape problems, not system problems.
  'task_plan_empty',
  'manual_task_unresolved',
  // The planning model broke the response protocol in a documented way:
  // unreadable JSON, an empty completion, an over-long response, or a
  // structurally invalid completion. The model ran; it answered badly.
  'model_response_invalid',
  'model_response_empty',
  'model_response_too_large',
  'model_json_invalid',
  'model_completion_invalid',
  'model_action_invalid',
  'model_protocol_exhausted',
};

/// Error codes meaning the user (or the caller) cancelled.
const Set<String> kCancellationCodes = <String>{
  'cancelled',
  'generation_cancelled',
  'run_cancelled',
};

/// Error codes meaning the model or provider could not be used at all.
const Set<String> kProviderUnavailableCodes = <String>{
  // The provider is not configured, not installed, or not routable.
  'model_provider_unavailable',
  'model_provider_mismatch',
  'model_route_unavailable',
  'model_not_installed',
  'model_not_selected',
  'model_discovery_failed',
  'model_secret_missing',
  'model_fallback_approval_required',
  // The model could not be loaded or did not respond in time. Nothing
  // was planned because nothing ran.
  'model_load_failed',
  'model_load_timeout',
  'model_load_response_invalid',
  'ollama_load_timeout_invalid',
  'model_connection_timeout',
  'model_first_token_timeout',
  'model_timeout',
  'model_generation_failed',
  'model_declared_failure',
  // The model identity changed under us: a governance stop, not a plan.
  'model_digest_changed',
};

/// Error codes meaning authority/permission refused.
const Set<String> kPermissionDeniedCodes = <String>{
  'permission_required',
  'permission_scope_missing',
  'permission_scope_unrequested',
  'permission_read_required',
  'tool_spawn_permission_denied',
  'capability_not_granted',
  // Boundary refusals: the effect was outside what Kristin may touch.
  'self_project_target_rejected',
  'path_outside_project',
  'path_absolute_rejected',
  'path_traversal_rejected',
  'path_scheme_rejected',
  'path_nul_rejected',
  'process_path_outside_project',
};

/// Error codes meaning storage/persistence is broken.
const Set<String> kPersistenceFailureCodes = <String>{
  'storage_corrupt',
  'transaction_journal_corrupt',
  'checkpoint_missing',
  'command_missing',
  'run_missing',
  'prompt_current_missing',
  'secret_reference_missing',
  'secret_unavailable',
};

/// Classifies an arbitrary thrown object into the planning taxonomy.
///
/// The default is deliberately [PlanningFailureKind.unexpected], not
/// [PlanningFailureKind.recoverablePlanning]: an unrecognized error is a
/// real failure until proven otherwise. Getting this default backwards is
/// exactly the bug this file exists to prevent.
PlanningFailure classifyPlanningFailure(
  Object error, {
  StackTrace? stackTrace,
}) {
  if (error is PlanningFailure) {
    return error;
  }
  if (error is ProductException) {
    final code = error.code;
    if (kCancellationCodes.contains(code)) {
      return PlanningFailure(
        kind: PlanningFailureKind.cancelled,
        code: code,
        message: error.message,
        details: error.details,
        cause: error,
      );
    }
    if (kProviderUnavailableCodes.contains(code)) {
      return PlanningFailure(
        kind: PlanningFailureKind.providerUnavailable,
        code: code,
        message: error.message,
        details: error.details,
        cause: error,
      );
    }
    if (kPermissionDeniedCodes.contains(code)) {
      return PlanningFailure(
        kind: PlanningFailureKind.permissionDenied,
        code: code,
        message: error.message,
        details: error.details,
        cause: error,
      );
    }
    if (kPersistenceFailureCodes.contains(code)) {
      return PlanningFailure(
        kind: PlanningFailureKind.persistenceFailure,
        code: code,
        message: error.message,
        details: error.details,
        cause: error,
      );
    }
    if (kRecoverablePlanningCodes.contains(code)) {
      return PlanningFailure(
        kind: PlanningFailureKind.recoverablePlanning,
        code: code,
        message: error.message,
        details: error.details,
        cause: error,
      );
    }
    // A ProductException with an unlisted code is still a real, typed
    // product error -- but it is not a known recoverable *planning*
    // failure, so it must not degrade into a conservative plan.
    return PlanningFailure(
      kind: PlanningFailureKind.unexpected,
      code: code,
      message: error.message,
      details: error.details,
      cause: error,
    );
  }
  // Cancellation can also surface as a plain async cancellation rather
  // than a coded ProductException.
  if (error is _CancelledMarker) {
    return PlanningFailure(
      kind: PlanningFailureKind.cancelled,
      code: 'cancelled',
      message: 'Planning was cancelled.',
      cause: error,
    );
  }
  // A file-system/database error surfacing as a raw exception is a
  // persistence failure, not a planning failure.
  final text = error.toString();
  if (error is StateError ||
      error is RangeError ||
      error is TypeError ||
      error is NoSuchMethodError) {
    return PlanningFailure(
      kind: PlanningFailureKind.unexpected,
      code: 'planning_defect',
      message: 'An unexpected internal error occurred while planning.',
      details: <String, dynamic>{
        'error': text,
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      },
      cause: error,
    );
  }
  return PlanningFailure(
    kind: PlanningFailureKind.unexpected,
    code: 'planning_failed',
    message: 'Planning failed with an unrecognized error.',
    details: <String, dynamic>{
      'error': text,
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    },
    cause: error,
  );
}

/// Sentinel used by callers that cancel without a coded exception.
class _CancelledMarker implements Exception {
  const _CancelledMarker();
}

/// A cancellation signal any kernel caller may throw to opt into
/// [PlanningFailureKind.cancelled] without depending on a code string.
const Object kPlanningCancelled = _CancelledMarker();
