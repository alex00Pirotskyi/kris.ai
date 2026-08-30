import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_conversation_state.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';

void main() {
  test('session can be interpreting before loose semantic fields exist', () {
    final session = KristinConversationSession();

    session.beginGovernedRequest('Build a small clock app.');

    expect(session.pendingDecision, isNull);
    expect(session.prepared, isNull);
    expect(session.currentRun, isNull);
    expect(session.state, isA<ChatInterpreting>());
  });

  test('reset returns the stored state to idle', () {
    final session = KristinConversationSession();
    session.beginGovernedRequest('Build a small clock app.');

    expect(session.detachFinishedRun(), isTrue);
    expect(session.state, isA<ChatIdle>());
  });
}
