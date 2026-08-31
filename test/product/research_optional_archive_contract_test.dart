import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct Research treats project archiving as optional enrichment', () {
    final source =
        File('lib/product/chat_action_dispatcher.dart').readAsStringSync();
    expect(source,
        contains('final project = await runtime.getProject(projectId);'));
    expect(source, contains('if (project == null) return;'));
    expect(source, contains('projectId: project.id'));
  });
}
