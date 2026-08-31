import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional Research archive failure does not invalidate grounded results',
      () {
    final dispatcher =
        File('lib/product/chat_action_dispatcher.dart').readAsStringSync();
    final executor = File(
      'lib/product/task_kernel/research_task_family_executor.dart',
    ).readAsStringSync();

    expect(dispatcher, contains("'research.optional_archive_failed'"));
    expect(dispatcher, contains("'answerPreserved': true"));
    expect(dispatcher, contains('runtime.redactor.redact'));

    expect(executor, contains("'task_family.research_archive_failed'"));
    expect(executor, contains("'warning': 'optional_archive_failed'"));
    expect(executor, contains("'answerPreserved': true"));
    expect(executor, isNot(contains("evidence.add(warning)")));
  });
}
