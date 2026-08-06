import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    P5InformationArchitectureApp(controller: controller),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'verification center separates result certification and support',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..selectWorkspace(P5WorkspaceId.verificationCenter);
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      expect(
        find.descendant(
          of: find.byKey(const Key('domain-test-execution')),
          matching: find.text('PASS'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('domain-certification')),
          matching: find.text('NOT_EVALUATED'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('domain-capability-support')),
          matching: find.text('SOURCE_FOUNDATION'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('domain-platform-support')),
          matching: find.text('UNSUPPORTED'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('domain-release-support')),
          matching: find.text('UNSUPPORTED'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('green test result'), findsOneWidget);
      expect(controller.sideEffects.isZero, isTrue);
    },
  );

  testWidgets(
    'experience levels progressively disclose verification detail',
    (tester) async {
      final controller = P5InformationArchitectureController()
        ..selectWorkspace(P5WorkspaceId.verificationCenter);
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      const testId = 'tc.p5-001.navigation.primary-workspaces';
      expect(find.textContaining(testId), findsNothing);
      expect(find.text('Widget result fixture'), findsNothing);

      controller.changeExperienceLevel(P5ExperienceLevel.advanced);
      await tester.pumpAndSettle();
      expect(find.text('Widget result fixture'), findsOneWidget);
      expect(find.textContaining(testId), findsNothing);

      controller.changeExperienceLevel(P5ExperienceLevel.developer);
      await tester.pumpAndSettle();
      expect(find.textContaining(testId), findsOneWidget);
      final developerRecord = find.byKey(
        const Key('developer-verification-record'),
      );
      await tester.scrollUntilVisible(
        developerRecord,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(developerRecord, findsOneWidget);
    },
  );

  testWidgets('verification request selects affected tests without execution',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..apply(P5PrototypeAction.reviewPlan)
      ..apply(P5PrototypeAction.startRun)
      ..apply(P5PrototypeAction.completeRun)
      ..apply(P5PrototypeAction.runVerification);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(
      find.byKey(const Key('affected-tests-selected')),
      findsOneWidget,
    );
    expect(find.textContaining('selected deterministically'), findsOneWidget);
    expect(controller.sideEffects, P5SideEffectLedger.zero);
  });
}
