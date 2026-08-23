import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p5_design_tokens.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';
import 'package:kristin_local_agent/product/ui.dart';

void main() {
  group('P5-014 critical UX regression gate', () {
    testWidgets('workspace history preserves the primary navigation flow',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.light(),
          home: P5InformationArchitecturePrototype(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.state.workspace, P5WorkspaceId.homeChat);
      controller.selectWorkspace(P5WorkspaceId.runsActivity);
      await tester.pumpAndSettle();
      expect(controller.state.workspace, P5WorkspaceId.runsActivity);
      controller.back();
      await tester.pumpAndSettle();
      expect(controller.state.workspace, P5WorkspaceId.homeChat);
      controller.forward();
      await tester.pumpAndSettle();
      expect(controller.state.workspace, P5WorkspaceId.runsActivity);
      controller.back();
      await tester.pumpAndSettle();
      expect(controller.state.workspace, P5WorkspaceId.homeChat);
      expect(controller.sideEffects.isZero, isTrue);
    });

    testWidgets(
        'blocked Owner Mode remains a truthful recoverable failure state',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ownerMode = P2ProductRuntimeOwnerModeHandle.blocked(
        'Bad state: merged_p1a_service_unavailable',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.light(),
          home: KristinMainShell(
            ownerMode: ownerMode,
            chat: const Center(child: Text('Chat surface')),
          ),
        ),
      );
      await tester.tap(find.text('Owner Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Owner Mode is unavailable'), findsOneWidget);
      expect(
        find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
    });

    testWidgets('primary shell semantics survive advanced navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = P5InformationArchitectureController()
        ..changeExperienceLevel(P5ExperienceLevel.advanced);
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.highContrastLight(),
          home: P5InformationArchitecturePrototype(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Home / Chat workspace, shortcut Alt+1'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Owner Mode status: Blocked by environment.'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets(
      'Linux baseline protects the primary Home Chat visual hierarchy',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = P5InformationArchitectureController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: P5DesignSystem.light(reducedMotion: true),
            home: RepaintBoundary(
              key: const Key('p5-critical-golden'),
              child: P5InformationArchitecturePrototype(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(const Key('p5-critical-golden')),
          matchesGoldenFile('goldens/p5_home_chat_linux.png'),
        );
      },
      skip: !Platform.isLinux,
    );
  });
}
