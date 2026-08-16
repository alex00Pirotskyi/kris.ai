import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_design_tokens.dart';

void main() {
  group('P5-002 design token system', () {
    test('all theme variants expose the complete semantic contract', () {
      final themes = <ThemeData>[
        P5DesignSystem.light(),
        P5DesignSystem.dark(),
        P5DesignSystem.highContrastLight(),
        P5DesignSystem.highContrastDark(),
      ];

      for (final theme in themes) {
        final tokens = theme.extension<P5DesignTokens>();
        expect(tokens, isNotNull);
        expect(theme.useMaterial3, isTrue);
        expect(theme.scaffoldBackgroundColor, tokens!.canvas);
        expect(theme.colorScheme.surface, tokens.surface);
        expect(theme.colorScheme.onSurface, tokens.onSurface);
        expect(theme.colorScheme.error, tokens.danger);
        expect(tokens.spaceXs, lessThan(tokens.spaceSm));
        expect(tokens.spaceSm, lessThan(tokens.spaceMd));
        expect(tokens.spaceMd, lessThan(tokens.spaceLg));
        expect(tokens.spaceLg, lessThan(tokens.spaceXl));
        expect(tokens.radiusSm, lessThan(tokens.radiusMd));
        expect(tokens.radiusMd, lessThan(tokens.radiusLg));
        expect(
          <Color>{
            tokens.focusRing,
            tokens.success,
            tokens.warning,
            tokens.danger,
            tokens.info,
            tokens.ownerMode,
          },
          hasLength(6),
          reason: 'status, focus, and Owner Mode colors must remain distinct',
        );
      }
    });

    test('high-contrast themes meet the deterministic 7:1 text target', () {
      for (final theme in <ThemeData>[
        P5DesignSystem.highContrastLight(),
        P5DesignSystem.highContrastDark(),
      ]) {
        final tokens = theme.extension<P5DesignTokens>()!;
        expect(tokens.highContrast, isTrue);
        expect(_contrast(tokens.onSurface, tokens.canvas),
            greaterThanOrEqualTo(7));
        expect(
          _contrast(tokens.onSurfaceMuted, tokens.canvas),
          greaterThanOrEqualTo(7),
        );
        expect(
          _contrast(tokens.onSurface, tokens.surfaceRaised),
          greaterThanOrEqualTo(7),
        );
      }
    });

    test('typography and controls use readable minimum sizes', () {
      for (final theme in <ThemeData>[
        P5DesignSystem.light(),
        P5DesignSystem.dark(),
        P5DesignSystem.highContrastLight(),
        P5DesignSystem.highContrastDark(),
      ]) {
        final tokens = theme.extension<P5DesignTokens>()!;
        expect(tokens.bodyFontSize, greaterThanOrEqualTo(16));
        expect(tokens.labelFontSize, greaterThanOrEqualTo(14));
        expect(tokens.navigationFontSize, greaterThanOrEqualTo(15));
        expect(tokens.buttonFontSize, greaterThanOrEqualTo(15));
        expect(
          theme.textTheme.bodyMedium!.fontSize,
          greaterThanOrEqualTo(tokens.bodyFontSize),
        );
        expect(
          theme.textTheme.labelLarge!.fontSize,
          greaterThanOrEqualTo(tokens.buttonFontSize),
        );
        expect(
          theme.navigationRailTheme.selectedLabelTextStyle!.fontSize,
          greaterThanOrEqualTo(tokens.navigationFontSize),
        );
        final selectedNavigationStyle = theme.navigationBarTheme.labelTextStyle!
            .resolve(<WidgetState>{WidgetState.selected});
        expect(
          selectedNavigationStyle!.fontSize,
          greaterThanOrEqualTo(tokens.navigationFontSize),
        );
      }
    });

    test('reduced motion removes semantic and theme transitions', () {
      final reduced = P5DesignSystem.dark(reducedMotion: true);
      final tokens = reduced.extension<P5DesignTokens>()!;

      expect(tokens.reducedMotion, isTrue);
      expect(tokens.motionFast, Duration.zero);
      expect(tokens.motionStandard, Duration.zero);
      expect(tokens.motionSlow, Duration.zero);
      expect(P5DesignSystem.themeTransitionDuration(true), Duration.zero);
      expect(
        P5DesignSystem.themeTransitionDuration(false),
        greaterThan(Duration.zero),
      );
      expect(
        reduced.pageTransitionsTheme.builders.keys,
        containsAll(<TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        ]),
      );
    });

    testWidgets('semantic tokens are available to ordinary widgets', (
      WidgetTester tester,
    ) async {
      P5DesignTokens? observed;
      await tester.pumpWidget(
        MaterialApp(
          theme: P5DesignSystem.light(),
          home: Builder(
            builder: (context) {
              observed = P5DesignTokens.of(context);
              return const Scaffold(body: Text('Readable Kristin surface'));
            },
          ),
        ),
      );

      expect(observed, isNotNull);
      expect(observed!.ownerMode, isNot(observed!.danger));
      expect(find.text('Readable Kristin surface'), findsOneWidget);
    });
  });
}

double _contrast(Color first, Color second) {
  final high = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final low = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (high + 0.05) / (low + 0.05);
}
