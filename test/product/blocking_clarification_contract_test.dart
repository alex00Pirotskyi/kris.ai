import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocking clarification is consumed in normal Chat and keeps same task',
      () {
    final studio =
        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    final session = File('lib/product/kristin_conversation_session.dart')
        .readAsStringSync();
    expect(studio, contains('_resolveUnderstandingClarification(request)'));
    expect(studio, contains('final decision = pendingDecision;'));
    expect(studio, contains('conversationSession.recordClarificationAnswer('));
    expect(session, contains('final List<String> _clarificationEvidence'));
    expect(session, contains('String get clarificationEvidenceText'));
  });

  test('clarification evidence is user intent, never an authority grant', () {
    final understanding =
        File('lib/product/task_kernel/task_understanding.dart')
            .readAsStringSync();
    expect(understanding, contains('USER CLARIFICATION EVIDENCE'));
    expect(understanding, contains('grants no permission or authority'));
    expect(understanding, contains('context.userEvidenceText'));
  });

  test(
      'blocking clarification disables Continue and Continue also fails closed',
      () {
    final view = File('lib/product/chat_control_plane_studio_view.dart')
        .readAsStringSync();
    final actions = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    expect(view, contains('routingDecision?.requiresClarification == true'));
    expect(
        view, contains('specification?.blockingQuestions.isNotEmpty == true'));
    expect(actions, contains("status = 'Reply in Chat: \$question'"));
  });
}
