// Architectural Improvement #6: an explicit conversation state machine.
//
// This module has two parts:
//
// - [ChatConversationState]: a sealed hierarchy of every state a Chat
//   conversation turn can be in, and [chatConversationTransition]: a
//   pure function proving which transitions between them are legal.
//   Impossible combinations (e.g. "awaiting permission" while also
//   "cancelled") are structurally prevented -- a caller can only reach
//   them by asking [chatConversationTransition] for an event that
//   isn't valid from the current state, which returns null rather than
//   producing a nonsensical state.
// - [chatConversationSnapshot]: projects the *current* set of loose
//   fields ChatControlPlaneStudio already keeps (pendingDecision,
//   prepared, awaitingPermission, currentRun, ...) onto one
//   [ChatConversationState] for rendering. The Studio's mutation call
//   sites still set those individual fields directly rather than
//   routing every mutation through [chatConversationTransition] --
//   doing that everywhere is a larger, riskier mechanical rewrite this
//   wave intentionally does not attempt without the ability to visually
//   verify the widget. The projection is the real, tested, authoritative
//   *type* for "what state is this conversation in"; adopting
//   [chatConversationTransition] at each mutation site is future work
//   this module already makes cheap, not a rewrite of the state model.
import 'domain.dart';

sealed class ChatConversationState {
  const ChatConversationState();
}

class ChatIdle extends ChatConversationState {
  const ChatIdle();
}

class ChatInterpreting extends ChatConversationState {
  const ChatInterpreting();
}

class ChatClarificationNeeded extends ChatConversationState {
  const ChatClarificationNeeded();
}

class ChatUnderstanding extends ChatConversationState {
  const ChatUnderstanding();
}

class ChatPlanning extends ChatConversationState {
  const ChatPlanning();
}

class ChatAwaitingPermission extends ChatConversationState {
  const ChatAwaitingPermission();
}

class ChatExecuting extends ChatConversationState {
  const ChatExecuting();
}

/// Not yet distinguishable from [ChatExecuting] in this wave: the
/// product's Run convergence does not currently expose a separate
/// "verifying" signal to Chat (see project.verify's own module docs in
/// chat_control_plane.dart). Kept in the sealed hierarchy so the target
/// model is complete and so a future signal can adopt it without
/// widening this type.
class ChatVerifying extends ChatConversationState {
  const ChatVerifying();
}

class ChatCompleted extends ChatConversationState {
  const ChatCompleted();
}

class ChatDenied extends ChatConversationState {
  const ChatDenied();
}

class ChatCancelled extends ChatConversationState {
  const ChatCancelled();
}

class ChatFailed extends ChatConversationState {
  const ChatFailed();
}

enum ChatConversationEvent {
  submit,
  compiled,
  compiledAmbiguous,
  understandingAccepted,
  planNotNeeded,
  planAccepted,
  permissionNotNeeded,
  permissionApproved,
  permissionDeclined,
  runStarted,
  runSucceeded,
  runFailed,
  cancel,
  reset,
}

/// Returns the next [ChatConversationState] for [event] fired from
/// [current], or null when that transition is not legal. Every legal
/// edge in Architectural Improvement #6's diagram is represented
/// exactly once here -- there is no default/fallback branch, so a new
/// state added to the sealed hierarchy without matching transition arms
/// is a compile error, not a silent gap.
ChatConversationState? chatConversationTransition(
  ChatConversationState current,
  ChatConversationEvent event,
) {
  switch (current) {
    case ChatIdle():
      return event == ChatConversationEvent.submit
          ? const ChatInterpreting()
          : null;
    case ChatInterpreting():
      switch (event) {
        case ChatConversationEvent.compiledAmbiguous:
          return const ChatClarificationNeeded();
        case ChatConversationEvent.compiled:
          return const ChatUnderstanding();
        default:
          return null;
      }
    case ChatClarificationNeeded():
      switch (event) {
        case ChatConversationEvent.understandingAccepted:
          return const ChatUnderstanding();
        case ChatConversationEvent.reset:
          return const ChatIdle();
        default:
          return null;
      }
    case ChatUnderstanding():
      switch (event) {
        case ChatConversationEvent.understandingAccepted:
          return const ChatPlanning();
        case ChatConversationEvent.reset:
          return const ChatIdle();
        default:
          return null;
      }
    case ChatPlanning():
      switch (event) {
        case ChatConversationEvent.planAccepted:
        case ChatConversationEvent.planNotNeeded:
          return const ChatAwaitingPermission();
        case ChatConversationEvent.permissionNotNeeded:
          return const ChatExecuting();
        case ChatConversationEvent.reset:
          return const ChatIdle();
        default:
          return null;
      }
    case ChatAwaitingPermission():
      switch (event) {
        case ChatConversationEvent.permissionApproved:
          return const ChatExecuting();
        case ChatConversationEvent.permissionDeclined:
          return const ChatDenied();
        default:
          return null;
      }
    case ChatExecuting():
      switch (event) {
        case ChatConversationEvent.cancel:
          return const ChatCancelled();
        case ChatConversationEvent.runSucceeded:
          return const ChatCompleted();
        case ChatConversationEvent.runFailed:
          return const ChatFailed();
        default:
          return null;
      }
    case ChatVerifying():
      switch (event) {
        case ChatConversationEvent.runSucceeded:
          return const ChatCompleted();
        case ChatConversationEvent.runFailed:
          return const ChatFailed();
        case ChatConversationEvent.cancel:
          return const ChatCancelled();
        default:
          return null;
      }
    case ChatCompleted():
    case ChatDenied():
    case ChatCancelled():
    case ChatFailed():
      // Terminal: only a fresh submit (a new conversation turn) leaves
      // a terminal state. None of them can be reopened into
      // AwaitingPermission/Executing -- see Architectural Improvement
      // #15's "a terminal run cannot accidentally be resumed".
      return event == ChatConversationEvent.submit
          ? const ChatInterpreting()
          : null;
  }
}

/// Projects the Studio's existing loose fields onto one
/// [ChatConversationState] for rendering -- see this module's docs for
/// why call sites are not yet routed through
/// [chatConversationTransition] directly.
ChatConversationState chatConversationSnapshot({
  required bool hasPendingDecision,
  required bool ambiguous,
  required bool hasPreparedCommand,
  required bool awaitingPermission,
  required RunState? currentRunState,
}) {
  if (currentRunState != null) {
    switch (currentRunState) {
      case RunState.succeeded:
        return const ChatCompleted();
      case RunState.failed:
        return const ChatFailed();
      case RunState.cancelled:
        return const ChatCancelled();
      case RunState.prepared:
      case RunState.queued:
      case RunState.running:
      case RunState.paused:
      case RunState.cancelling:
      case RunState.interrupted:
        return const ChatExecuting();
      case RunState.awaitingApproval:
        return const ChatAwaitingPermission();
    }
  }
  if (awaitingPermission) return const ChatAwaitingPermission();
  if (hasPreparedCommand) return const ChatPlanning();
  if (hasPendingDecision) {
    return ambiguous
        ? const ChatClarificationNeeded()
        : const ChatUnderstanding();
  }
  return const ChatIdle();
}
