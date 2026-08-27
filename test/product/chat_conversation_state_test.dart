import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_conversation_state.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  group('chatConversationTransition: valid transitions', () {
    test('Idle -> Interpreting -> Understanding -> Planning', () {
      ChatConversationState state = const ChatIdle();
      state = chatConversationTransition(state, ChatConversationEvent.submit)!;
      expect(state, isA<ChatInterpreting>());
      state =
          chatConversationTransition(state, ChatConversationEvent.compiled)!;
      expect(state, isA<ChatUnderstanding>());
      state = chatConversationTransition(
        state,
        ChatConversationEvent.understandingAccepted,
      )!;
      expect(state, isA<ChatPlanning>());
    });

    test('Interpreting -> ClarificationNeeded -> Understanding', () {
      var state = chatConversationTransition(
        const ChatInterpreting(),
        ChatConversationEvent.compiledAmbiguous,
      )!;
      expect(state, isA<ChatClarificationNeeded>());
      state = chatConversationTransition(
        state,
        ChatConversationEvent.understandingAccepted,
      )!;
      expect(state, isA<ChatUnderstanding>());
    });

    test('Planning -> AwaitingPermission -> Executing -> Completed', () {
      var state = chatConversationTransition(
        const ChatPlanning(),
        ChatConversationEvent.planAccepted,
      )!;
      expect(state, isA<ChatAwaitingPermission>());
      state = chatConversationTransition(
        state,
        ChatConversationEvent.permissionApproved,
      )!;
      expect(state, isA<ChatExecuting>());
      state = chatConversationTransition(
        state,
        ChatConversationEvent.runSucceeded,
      )!;
      expect(state, isA<ChatCompleted>());
    });

    test(
      'Planning -> AwaitingPermission -> Denied on decline',
      () {
        var state = chatConversationTransition(
          const ChatPlanning(),
          ChatConversationEvent.planNotNeeded,
        )!;
        expect(state, isA<ChatAwaitingPermission>());
        state = chatConversationTransition(
          state,
          ChatConversationEvent.permissionDeclined,
        )!;
        expect(state, isA<ChatDenied>());
      },
    );

    test('Planning skips permission entirely when none is required', () {
      final state = chatConversationTransition(
        const ChatPlanning(),
        ChatConversationEvent.permissionNotNeeded,
      )!;
      expect(state, isA<ChatExecuting>());
    });

    test('Executing -> Cancelled', () {
      final state = chatConversationTransition(
        const ChatExecuting(),
        ChatConversationEvent.cancel,
      )!;
      expect(state, isA<ChatCancelled>());
    });

    test('Executing -> Failed', () {
      final state = chatConversationTransition(
        const ChatExecuting(),
        ChatConversationEvent.runFailed,
      )!;
      expect(state, isA<ChatFailed>());
    });

    test('a new submit reopens every terminal state into Interpreting', () {
      for (final terminal in <ChatConversationState>[
        const ChatCompleted(),
        const ChatDenied(),
        const ChatCancelled(),
        const ChatFailed(),
      ]) {
        final state = chatConversationTransition(
          terminal,
          ChatConversationEvent.submit,
        );
        expect(state, isA<ChatInterpreting>(), reason: '$terminal');
      }
    });
  });

  group('chatConversationTransition: illegal transitions return null', () {
    test('a terminal run cannot accidentally be resumed', () {
      for (final terminal in <ChatConversationState>[
        const ChatCompleted(),
        const ChatDenied(),
        const ChatCancelled(),
        const ChatFailed(),
      ]) {
        for (final event in <ChatConversationEvent>[
          ChatConversationEvent.permissionApproved,
          ChatConversationEvent.runSucceeded,
          ChatConversationEvent.cancel,
        ]) {
          expect(
            chatConversationTransition(terminal, event),
            isNull,
            reason: '$terminal + $event must not resume execution',
          );
        }
      }
    });

    test('AwaitingPermission cannot skip straight to Completed', () {
      expect(
        chatConversationTransition(
          const ChatAwaitingPermission(),
          ChatConversationEvent.runSucceeded,
        ),
        isNull,
      );
    });

    test('Idle only accepts submit', () {
      for (final event in ChatConversationEvent.values) {
        if (event == ChatConversationEvent.submit) continue;
        expect(
          chatConversationTransition(const ChatIdle(), event),
          isNull,
          reason: '$event',
        );
      }
    });

    test('Executing cannot be reinterpreted mid-run', () {
      expect(
        chatConversationTransition(
          const ChatExecuting(),
          ChatConversationEvent.compiled,
        ),
        isNull,
      );
    });

    test('Denied cannot be approved after the fact', () {
      expect(
        chatConversationTransition(
          const ChatDenied(),
          ChatConversationEvent.permissionApproved,
        ),
        isNull,
      );
    });
  });

  group('chatConversationSnapshot', () {
    test('no decision, no run: Idle', () {
      final state = chatConversationSnapshot(
        hasPendingDecision: false,
        ambiguous: false,
        hasPreparedCommand: false,
        awaitingPermission: false,
        currentRunState: null,
      );
      expect(state, isA<ChatIdle>());
    });

    test('pending decision, not ambiguous: Understanding', () {
      final state = chatConversationSnapshot(
        hasPendingDecision: true,
        ambiguous: false,
        hasPreparedCommand: false,
        awaitingPermission: false,
        currentRunState: null,
      );
      expect(state, isA<ChatUnderstanding>());
    });

    test('pending decision, ambiguous: ClarificationNeeded', () {
      final state = chatConversationSnapshot(
        hasPendingDecision: true,
        ambiguous: true,
        hasPreparedCommand: false,
        awaitingPermission: false,
        currentRunState: null,
      );
      expect(state, isA<ChatClarificationNeeded>());
    });

    test('prepared command, no permission flag: Planning', () {
      final state = chatConversationSnapshot(
        hasPendingDecision: true,
        ambiguous: false,
        hasPreparedCommand: true,
        awaitingPermission: false,
        currentRunState: null,
      );
      expect(state, isA<ChatPlanning>());
    });

    test('awaiting permission flag set: AwaitingPermission', () {
      final state = chatConversationSnapshot(
        hasPendingDecision: true,
        ambiguous: false,
        hasPreparedCommand: true,
        awaitingPermission: true,
        currentRunState: null,
      );
      expect(state, isA<ChatAwaitingPermission>());
    });

    test('run awaiting approval: AwaitingPermission regardless of the flag',
        () {
      final state = chatConversationSnapshot(
        hasPendingDecision: true,
        ambiguous: false,
        hasPreparedCommand: true,
        awaitingPermission: false,
        currentRunState: RunState.awaitingApproval,
      );
      expect(state, isA<ChatAwaitingPermission>());
    });

    test('run states map to Executing/Completed/Failed/Cancelled', () {
      const executing = <RunState>{
        RunState.prepared,
        RunState.queued,
        RunState.running,
        RunState.paused,
        RunState.cancelling,
        RunState.interrupted,
      };
      for (final runState in executing) {
        final state = chatConversationSnapshot(
          hasPendingDecision: true,
          ambiguous: false,
          hasPreparedCommand: true,
          awaitingPermission: false,
          currentRunState: runState,
        );
        expect(state, isA<ChatExecuting>(), reason: '$runState');
      }
      expect(
        chatConversationSnapshot(
          hasPendingDecision: true,
          ambiguous: false,
          hasPreparedCommand: true,
          awaitingPermission: false,
          currentRunState: RunState.succeeded,
        ),
        isA<ChatCompleted>(),
      );
      expect(
        chatConversationSnapshot(
          hasPendingDecision: true,
          ambiguous: false,
          hasPreparedCommand: true,
          awaitingPermission: false,
          currentRunState: RunState.failed,
        ),
        isA<ChatFailed>(),
      );
      expect(
        chatConversationSnapshot(
          hasPendingDecision: true,
          ambiguous: false,
          hasPreparedCommand: true,
          awaitingPermission: false,
          currentRunState: RunState.cancelled,
        ),
        isA<ChatCancelled>(),
      );
    });
  });
}
