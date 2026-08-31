import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  const compiler = ChatIntentCompiler();

  test('natural local-time question routes to deterministic utility.time', () {
    final decision = compiler.compile(
      'what is the time in New York?',
      inferredMode: CommandMode.ask,
      knownTargets: const <ChatTarget>[],
    );
    expect(decision.capability?.id, 'utility.time');
    expect(decision.needsPlan, isFalse);
    expect(decision.needsUnderstanding, isFalse);
    expect(decision.riskClass, ChatRiskClass.none);
  });

  test('/time is structurally deterministic', () {
    final decision = compiler.compile(
      '/time America/New_York',
      inferredMode: CommandMode.ask,
      knownTargets: const <ChatTarget>[],
    );
    expect(decision.capability?.id, 'utility.time');
    expect(decision.parsed.arguments, 'America/New_York');
    expect(decision.needsPlan, isFalse);
  });
}
