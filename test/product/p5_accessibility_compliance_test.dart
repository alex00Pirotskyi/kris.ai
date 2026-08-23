import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_design_tokens.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

void main() {
  group('P5-012 WCAG 2.2 AA automated compliance', () {
    testWidgets('primary Experience workspace survives 200 percent text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1280, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: P5InformationArchitecturePrototype(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('workspace-title')), findsOneWidget);
      expect(find.text('Home / Chat'), findsWidgets);
    });

    testWidgets('compact workspace remains usable at 200 percent text scaling',
        (tester) async {
      tester.view.physicalSize = const Size(720, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = P5InformationArchitectureController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.highContrastLight(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(720, 720),
              textScaler: TextScaler.linear(2),
              highContrast: true,
              disableAnimations: true,
            ),
            child: P5InformationArchitecturePrototype(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('workspace-title')), findsOneWidget);
    });

    testWidgets('theme-level interactive controls meet 44 CSS pixel target floor',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.light(),
          home: Scaffold(
            body: Wrap(
              children: <Widget>[
                FilledButton(
                  key: const Key('filled'),
                  onPressed: () {},
                  child: const Text('Filled'),
                ),
                OutlinedButton(
                  key: const Key('outlined'),
                  onPressed: () {},
                  child: const Text('Outlined'),
                ),
                TextButton(
                  key: const Key('text'),
                  onPressed: () {},
                  child: const Text('Text'),
                ),
                IconButton(
                  key: const Key('icon'),
                  tooltip: 'Refresh',
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
      );

      for (final key in const <String>['filled', 'outlined', 'text', 'icon']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }
    });

    test('high contrast and reduced motion remain explicit product modes', () {
      for (final theme in <ThemeData>[
        P5DesignSystem.highContrastLight(reducedMotion: true),
        P5DesignSystem.highContrastDark(reducedMotion: true),
      ]) {
        final tokens = theme.extension<P5DesignTokens>()!;
        expect(tokens.highContrast, isTrue);
        expect(tokens.reducedMotion, isTrue);
        expect(tokens.motionFast, Duration.zero);
        expect(tokens.motionStandard, Duration.zero);
        expect(tokens.motionSlow, Duration.zero);
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      }
    });
  });
}
