import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Advanced opened from Kristin shares canonical session and has Back path',
    () {
      final advanced = File('lib/product/chat_studio.dart').readAsStringSync();
      final caller = File(
        'lib/product/chat_control_plane_studio_actions.dart',
      ).readAsStringSync();

      expect(
        advanced,
        contains('final KristinConversationSession? conversationSession;'),
      );
      expect(advanced, contains("ValueKey<String>('back-to-kristin')"));
      expect(advanced, contains('same Kristin session'));
      expect(
        advanced,
        contains('canonical == null ? _chatPage() : _canonicalKristinPage()'),
      );
      expect(caller, contains('conversationSession: conversationSession'));
    },
  );
}
