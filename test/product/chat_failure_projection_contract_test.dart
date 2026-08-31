import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chat separates friendly failure summary from redacted technical detail',
      () {
    final studio =
        File('lib/product/chat_control_plane_studio.dart').readAsStringSync();
    final view = File('lib/product/chat_control_plane_studio_view.dart')
        .readAsStringSync();
    final actions = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();

    expect(studio, contains('String? technicalError;'));
    expect(studio, contains('ProductErrorNormalizer.userMessage(failure)'));
    expect(studio, contains("runtime.redactor.redact('\$failure')"));
    expect(studio, contains('technicalError = null;'));
    expect(studio, contains('errorDetailsExpanded = false;'));
    expect(view, contains("tooltip: 'Error details'"));
    expect(view, contains('technicalError != null && errorDetailsExpanded'));
    expect(view, contains('SelectableText('));
    expect(actions, contains('technicalError = null'));
  });
}
