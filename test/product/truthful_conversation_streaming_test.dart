import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';

void main() {
  test('ordinary conversation projects real protocol deltas then commits once',
      () {
    final session = KristinConversationSession();
    session.beginConversationResponse();
    session.appendConversationAssistantDelta('{"answer":"Hel');
    session.appendConversationAssistantDelta('lo"}');
    expect(session.conversationAssistantText, 'Hello');
    expect(session.messages, isEmpty);

    session.completeConversationResponse('Hello');
    expect(session.conversationAssistantText, isEmpty);
    expect(session.conversationAssistantProtocolText, isEmpty);
    expect(session.messages.single.text, 'Hello');
  });

  test(
      'Chat passes provider deltas directly and contains no character animation loop',
      () {
    final actions = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    expect(actions, contains('onTextDelta: (delta)'));
    expect(actions, contains('appendConversationAssistantDelta(delta)'));
    expect(actions,
        isNot(contains('Future.delayed(const Duration(milliseconds:')));
  });

  test('non-streaming provider is represented as thinking until completion',
      () {
    final actions = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    expect(actions, contains("status = 'Kristin is thinking'"));
    expect(actions, contains('completeConversationResponse(visible)'));
  });
}
