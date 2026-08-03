import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_host_operations.dart';

void main() {
  test('host-operation support uses typed honest states', () {
    const unsupported = P2OperationSupport(
      P2SupportStatus.unsupported,
      'platform_backend_unavailable',
    );
    const approval = P2OperationSupport(
      P2SupportStatus.approvalRequired,
      'visible_owner_interaction_required',
      requiresElevation: true,
    );

    expect(unsupported.status, P2SupportStatus.unsupported);
    expect(unsupported.requiresElevation, isFalse);
    expect(approval.status, P2SupportStatus.approvalRequired);
    expect(approval.requiresElevation, isTrue);
  });

  test('production host contracts expose no implicit direct implementation',
      () {
    expect(P2SupportStatus.values, contains(P2SupportStatus.blocked));
    expect(P2SupportStatus.values, contains(P2SupportStatus.unknown));
  });
}
