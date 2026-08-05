import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_owner_mode.dart';

void main() {
  test('Owner Mode is persistently and honestly labelled', () {
    final settings = P2OwnerModeSettings(
      state: P2OwnerModeState.enabledInteractive,
      approvalPolicy: P2OwnerApprovalPolicy.destructiveOnly,
      enabledAt: DateTime.utc(2026),
      dataBoundaryAcknowledged: true,
    );
    expect(settings.accessProfileId, 'owner');
    expect(
      settings.persistentIndicator,
      contains('full current-account access'),
    );
    expect(settings.safetyLabel.toLowerCase(), contains('not a sandbox'));
  });
}
