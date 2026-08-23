import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_doctor.dart';

void main() {
  CapabilityDoctorCheck check(
    String id, {
    CapabilityDoctorStatus status = CapabilityDoctorStatus.ready,
    bool required = false,
    CapabilityDoctorAction action = CapabilityDoctorAction.none,
  }) =>
      CapabilityDoctorCheck(
        id: id,
        title: id,
        status: status,
        message: '$id status',
        required: required,
        action: action,
      );

  test('P5-011 core readiness requires storage and model only', () {
    final report = CapabilityDoctorReport(
      depth: CapabilityDoctorDepth.quick,
      checkedAt: DateTime.utc(2026, 8, 23),
      checks: <CapabilityDoctorCheck>[
        check('storage', required: true),
        check('model', required: true),
        check(
          'owner-mode',
          status: CapabilityDoctorStatus.warning,
          action: CapabilityDoctorAction.openSettings,
        ),
        check(
          'browser',
          status: CapabilityDoctorStatus.warning,
          action: CapabilityDoctorAction.retryDoctor,
        ),
      ],
    );

    expect(report.coreReady, isTrue);
    expect(report.allReady, isFalse);
    expect(report.readyCount, 2);
    expect(report.warningCount, 2);
    expect(report.blockedCount, 0);
  });

  test('P5-011 missing required model blocks core readiness', () {
    final report = CapabilityDoctorReport(
      depth: CapabilityDoctorDepth.full,
      checks: <CapabilityDoctorCheck>[
        check('storage', required: true),
        check(
          'model',
          status: CapabilityDoctorStatus.blocked,
          required: true,
          action: CapabilityDoctorAction.connectModel,
        ),
        check('project', status: CapabilityDoctorStatus.warning),
      ],
    );

    expect(report.coreReady, isFalse);
    expect(report.blockedCount, 1);
    expect(report.byId('model')?.action, CapabilityDoctorAction.connectModel);
  });

  test('P5-011 actionable checks preserve deterministic report order', () {
    final report = CapabilityDoctorReport(
      depth: CapabilityDoctorDepth.quick,
      checks: <CapabilityDoctorCheck>[
        check('storage', required: true),
        check(
          'model',
          status: CapabilityDoctorStatus.blocked,
          required: true,
          action: CapabilityDoctorAction.connectModel,
        ),
        check(
          'search',
          status: CapabilityDoctorStatus.warning,
          action: CapabilityDoctorAction.openSettings,
        ),
        check('project'),
      ],
    );

    expect(
      report.actionable.map((item) => item.id).toList(),
      <String>['model', 'search'],
    );
  });

  test('P5-011 rejects duplicate capability identities', () {
    expect(
      () => CapabilityDoctorReport(
        depth: CapabilityDoctorDepth.quick,
        checks: <CapabilityDoctorCheck>[
          check('model'),
          check('model'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('P5-011 runtime and Chat wiring preserve task preflight', () async {
    final runtime =
        await File('lib/product/product_runtime.dart').readAsString();
    final chat = await File('lib/product/chat_studio.dart').readAsString();

    expect(runtime, contains('inspectCapabilities({'));
    expect(runtime, contains('p3BrowserRuntime.probe('));
    expect(runtime, contains('Task-specific preflight'));
    expect(chat, contains('_runCapabilityDoctor()'));
    expect(chat, contains('_runProjectDoctor()'));
    expect(chat, contains('_capabilityDoctorCard('));
    expect(
      chat,
      matches(
        RegExp(
          r'capabilityDoctorReport\?\.depth\s*==\s*CapabilityDoctorDepth\.full',
        ),
      ),
    );
    expect(
      chat,
      contains(
        'Exact task capabilities are rechecked by the mandatory run preflight',
      ),
    );
  });
}
