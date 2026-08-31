import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String caller;
  late String advanced;

  setUpAll(() {
    caller = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();
    advanced = File('lib/product/chat_studio.dart').readAsStringSync();
  });

  test('canonical Kristin session is passed into Advanced', () {
    expect(caller, contains('conversationSession: conversationSession'));
    expect(advanced,
        contains('final KristinConversationSession? conversationSession;'));
  });

  test(
      'Advanced projects canonical transcript instead of owning a second composer',
      () {
    expect(advanced, contains('Widget _canonicalKristinProjection()'));
    expect(advanced, contains('for (final message in session.messages)'));
    expect(
        advanced,
        contains(
            "if (projectsCanonicalKristin) {\n      return _canonicalKristinProjection();"));
    expect(
        advanced,
        contains(
            "if (projectsCanonicalKristin) {\n      // The canonical Kristin composer is the only normal-user input owner."));
  });

  test('Advanced exposes an explicit Back to Kristin path', () {
    expect(advanced, contains("Key('advanced-back-to-kristin')"));
    expect(advanced, contains("label: const Text('Back to Kristin')"));
  });

  test('project and model selections can flow back into canonical session', () {
    expect(advanced,
        contains('widget.conversationSession?.selectProject(projectId);'));
    expect(advanced,
        contains('widget.conversationSession?.selectModel(result.modelId);'));
  });
}
