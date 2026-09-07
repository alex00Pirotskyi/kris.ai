import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/access_profile_v2.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: P5InformationArchitecturePrototype(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('P5-007 profile approval mapping matches governed P1 catalog', () {
    final catalog =
        jsonDecode(File('config/access_profiles.v2.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      catalog['authoritySemantics'],
      'maximum_ceiling_not_capability_grant',
    );
    final profiles = <String, String>{};
    for (final raw in catalog['profiles'] as List<dynamic>) {
      final item = raw as Map<String, dynamic>;
      profiles[item['profileId'] as String] = item['approvalPolicy'] as String;
    }

    const expectedIds = <P5ComposerProfile, String>{
      P5ComposerProfile.project: 'project',
      P5ComposerProfile.owner: 'owner',
      P5ComposerProfile.ownerUnattended: 'owner_unattended',
      P5ComposerProfile.isolatedUntrusted: 'isolated_untrusted',
    };
    const expectedPolicies = <ApprovalPolicy, String>{
      ApprovalPolicy.always: 'always',
      ApprovalPolicy.highRiskOnly: 'high_risk_only',
      ApprovalPolicy.never: 'never',
    };

    for (final profile in P5ComposerProfile.values) {
      expect(
        profiles[expectedIds[profile]],
        expectedPolicies[profile.approvalPolicy],
      );
    }
    expect(
      P5ComposerProfile.ownerUnattended.approvalPolicy,
      ApprovalPolicy.never,
    );
  });

  testWidgets('P5-007 plan review exposes every governed review field', (
    tester,
  ) async {
    final controller = P5InformationArchitectureController()
      ..updateComposerAttachments(const <String>['lib/example.dart'])
      ..updateAcceptanceCriteria(const <String>[
        'Requested behavior is verified by tests.',
        'No unexpected side effect is reported.',
      ])
      ..apply(P5PrototypeAction.reviewPlan);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    for (final key in const <String>[
      'p5-plan-goal',
      'p5-plan-files',
      'p5-plan-commands',
      'p5-plan-sites',
      'p5-plan-side-effects',
      'p5-plan-verification',
      'p5-plan-risk',
      'p5-plan-profile',
      'p5-plan-approval-policy',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.textContaining('NOT_EVALUATED'), findsOneWidget);
    expect(find.textContaining('0 filesystem'), findsOneWidget);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets(
    'P5-007 Owner unattended never policy is represented accurately',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..updateComposerProfile(P5ComposerProfile.ownerUnattended)
        ..apply(P5PrototypeAction.reviewPlan);
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      expect(find.text('Approval policy: NEVER'), findsOneWidget);
      expect(
        find.textContaining('No approval prompts are required by this profile'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not grant capabilities'),
        findsOneWidget,
      );
      expect(find.textContaining('maximum authority ceilings'), findsOneWidget);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  testWidgets(
    'P5-007 plan review never fabricates commands sites or low risk',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..apply(P5PrototypeAction.reviewPlan);
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      expect(
        find.textContaining('None compiled in P5 presentation mode'),
        findsOneWidget,
      );
      expect(
        find.textContaining('None declared in this composer'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Do not interpret presentation mode as low risk'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No command authority is implied'),
        findsOneWidget,
      );
    },
  );
}
