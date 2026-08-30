import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';

void main() {
  test('real model deltas update one provisional assistant transcript message', () {
    final session = KristinConversationSession();
    session.addUserMessage('hello');
    session.beginAssistantResponse();

    session.recordAssistantResponseDelta('{"answer":"Hel');
    expect(session.assistantResponseStreaming, isTrue);
    expect(session.messages.map((message) => message.text), <String>['hello', 'Hel']);

    session.recordAssistantResponseDelta('lo there"}');
    expect(session.messages.map((message) => message.text), <String>['hello', 'Hello there']);

    session.finishAssistantResponse('Hello there');
    expect(session.assistantResponseStreaming, isFalse);
    expect(session.messages.map((message) => message.text), <String>['hello', 'Hello there']);
  });

  test('failed streaming response removes the incomplete provisional message', () {
    final session = KristinConversationSession();
    session.addUserMessage('hello');
    session.beginAssistantResponse();
    session.recordAssistantResponseDelta('{"answer":"Partial');

    session.cancelAssistantResponse();

    expect(session.assistantResponseStreaming, isFalse);
    expect(session.messages.map((message) => message.text), <String>['hello']);
  });
}
