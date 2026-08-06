import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<void> _pressChord(
  WidgetTester tester, {
  required LogicalKeyboardKey modifier,
  LogicalKeyboardKey? secondModifier,
  required LogicalKeyboardKey key,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (secondModifier != null) {
    await tester.sendKeyDownEvent(secondModifier);
  }
  await tester.sendKeyEvent(key);
  if (secondModifier != null) {
    await tester.sendKeyUpEvent(secondModifier);
  }
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _focusWithTab(
  WidgetTester tester,
  Finder target, {
  int maximumTabs = 120,
}) async {
  for (var index = 0; index < maximumTabs; index++) {
    if (target.evaluate().isNotEmpty) {
      final targetElement = tester.element(target);
      final focusContext = FocusManager.instance.primaryFocus?.context;
      var containsPrimaryFocus = focusContext == targetElement;
      focusContext?.visitAncestorElements((ancestor) {
        if (ancestor == targetElement) {
          containsPrimaryFocus = true;
          return false;
        }
        return true;
      });
      if (containsPrimaryFocus) {
        return;
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Target did not receive focus after $maximumTabs Tab presses.');
}

void main() {
  testWidgets('keyboard-only primary and verification flows', (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final reviewButton = find.byKey(const Key('review-plan-button'));
    await _focusWithTab(tester, reviewButton);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('concise-plan-card')), findsOneWidget);

    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.controlLeft,
      secondModifier: LogicalKeyboardKey.shiftLeft,
      key: LogicalKeyboardKey.keyV,
    );
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(find.text('Verification Center'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);

    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.altLeft,
      key: LogicalKeyboardKey.digit3,
    );
    expect(controller.state.workspace, P5WorkspaceId.runsActivity);
    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.altLeft,
      key: LogicalKeyboardKey.digit4,
    );
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('primary navigation and state semantics are announced',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    await _pump(tester, controller);

    expect(
      find.bySemanticsLabel('Home / Chat workspace, shortcut Alt+1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Owner Mode status: Blocked by environment. Presentation only.',
      ),
      findsOneWidget,
    );

    controller.selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    await tester.pumpAndSettle();
    final webCapability = find.byKey(const Key('capability-webStudio'));
    await tester.ensureVisible(webCapability);
    await tester.tap(webCapability);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'Web Studio is BLOCKED_BY_DEPENDENCY. P3-001 browser runtime is not implemented.',
      ),
      findsOneWidget,
    );
    expect(controller.sideEffects, P5SideEffectLedger.zero);
    semantics.dispose();
  });
}
