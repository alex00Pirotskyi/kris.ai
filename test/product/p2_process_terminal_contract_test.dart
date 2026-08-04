import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_process_tree.dart';
import 'package:kristin_local_agent/product/p2_terminal_model.dart';

void main() {
  test('process identity resists pid-only reuse', () {
    const first = P2ProcessIdentity(
      pid: 4,
      startToken: 'one',
      supervisorToken: 'supervisor',
      platformGroupId: '4',
    );
    const second = P2ProcessIdentity(
      pid: 4,
      startToken: 'two',
      supervisorToken: 'supervisor',
      platformGroupId: '4',
    );
    expect(first.startToken, isNot(second.startToken));
  });

  test('terminal model exposes keyboard and emergency workflows', () {
    final model = P2TerminalModel();
    expect(model.shortcuts[P2TerminalAction.sendInterrupt], 'Ctrl+C');
    expect(model.shortcuts.containsKey(P2TerminalAction.attach), isTrue);
    expect(model.shortcuts.containsKey(P2TerminalAction.emergencyKill), isTrue);
  });
}
