import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_doctor.dart';

void main() {
  test('missing optional Brave configuration is healthy with built-in search', () {
    final report = CapabilityDoctorReport(
      depth: CapabilityDoctorDepth.quick,
      checks: const <CapabilityDoctorCheck>[
        CapabilityDoctorCheck(
          id: 'search',
          title: 'Web search',
          status: CapabilityDoctorStatus.warning,
          message:
              'Web research is enabled, but no Brave Search secret reference is configured.',
          required: false,
          action: CapabilityDoctorAction.openSettings,
          details: <String, Object?>{'configuredReferenceCount': 0},
        ),
      ],
    );

    final search = report.byId('search')!;
    expect(search.status, CapabilityDoctorStatus.ready);
    expect(search.action, CapabilityDoctorAction.none);
    expect(search.message, contains('Built-in web search is available'));
    expect(search.message, isNot(contains('must configure Brave')));
  });

  test('local-only search warning remains fail-closed and actionable', () {
    final report = CapabilityDoctorReport(
      depth: CapabilityDoctorDepth.quick,
      checks: const <CapabilityDoctorCheck>[
        CapabilityDoctorCheck(
          id: 'search',
          title: 'Web search',
          status: CapabilityDoctorStatus.warning,
          message:
              'Web research is disabled by local-only settings. Runs that require current web information will fail closed before execution.',
          required: false,
          action: CapabilityDoctorAction.openSettings,
        ),
      ],
    );

    final search = report.byId('search')!;
    expect(search.status, CapabilityDoctorStatus.warning);
    expect(search.action, CapabilityDoctorAction.openSettings);
    expect(search.message, contains('local-only'));
  });
}
