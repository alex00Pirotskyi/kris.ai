import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class P5DesignTokens extends ThemeExtension<P5DesignTokens> {
  const P5DesignTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.focusRing,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.ownerMode,
    required this.spaceXs,
    required this.spaceSm,
    required this.spaceMd,
    required this.spaceLg,
    required this.spaceXl,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.elevationLow,
    required this.elevationHigh,
    required this.bodyFontSize,
    required this.labelFontSize,
    required this.navigationFontSize,
    required this.buttonFontSize,
    required this.motionFast,
    required this.motionStandard,
    required this.motionSlow,
    required this.reducedMotion,
    required this.highContrast,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color ownerMode;

  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceLg;
  final double spaceXl;

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  final double elevationLow;
  final double elevationHigh;

  final double bodyFontSize;
  final double labelFontSize;
  final double navigationFontSize;
  final double buttonFontSize;

  final Duration motionFast;
  final Duration motionStandard;
  final Duration motionSlow;

  final bool reducedMotion;
  final bool highContrast;

  static P5DesignTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<P5DesignTokens>();
    if (tokens == null) {
      throw StateError('P5DesignTokens are missing from the active ThemeData.');
    }
    return tokens;
  }

  @override
  P5DesignTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? focusRing,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? ownerMode,
    double? spaceXs,
    double? spaceSm,
    double? spaceMd,
    double? spaceLg,
    double? spaceXl,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? elevationLow,
    double? elevationHigh,
    double? bodyFontSize,
    double? labelFontSize,
    double? navigationFontSize,
    double? buttonFontSize,
    Duration? motionFast,
    Duration? motionStandard,
    Duration? motionSlow,
    bool? reducedMotion,
    bool? highContrast,
  }) {
    return P5DesignTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      ownerMode: ownerMode ?? this.ownerMode,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      elevationLow: elevationLow ?? this.elevationLow,
      elevationHigh: elevationHigh ?? this.elevationHigh,
      bodyFontSize: bodyFontSize ?? this.bodyFontSize,
      labelFontSize: labelFontSize ?? this.labelFontSize,
      navigationFontSize: navigationFontSize ?? this.navigationFontSize,
      buttonFontSize: buttonFontSize ?? this.buttonFontSize,
      motionFast: motionFast ?? this.motionFast,
      motionStandard: motionStandard ?? this.motionStandard,
      motionSlow: motionSlow ?? this.motionSlow,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  P5DesignTokens lerp(covariant P5DesignTokens? other, double t) {
    if (other == null) return this;
    return P5DesignTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      ownerMode: Color.lerp(ownerMode, other.ownerMode, t)!,
      spaceXs: lerpDouble(spaceXs, other.spaceXs, t)!,
      spaceSm: lerpDouble(spaceSm, other.spaceSm, t)!,
      spaceMd: lerpDouble(spaceMd, other.spaceMd, t)!,
      spaceLg: lerpDouble(spaceLg, other.spaceLg, t)!,
      spaceXl: lerpDouble(spaceXl, other.spaceXl, t)!,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      elevationLow: lerpDouble(elevationLow, other.elevationLow, t)!,
      elevationHigh: lerpDouble(elevationHigh, other.elevationHigh, t)!,
      bodyFontSize: lerpDouble(bodyFontSize, other.bodyFontSize, t)!,
      labelFontSize: lerpDouble(labelFontSize, other.labelFontSize, t)!,
      navigationFontSize:
          lerpDouble(navigationFontSize, other.navigationFontSize, t)!,
      buttonFontSize: lerpDouble(buttonFontSize, other.buttonFontSize, t)!,
      motionFast: _lerpDuration(motionFast, other.motionFast, t),
      motionStandard: _lerpDuration(motionStandard, other.motionStandard, t),
      motionSlow: _lerpDuration(motionSlow, other.motionSlow, t),
      reducedMotion: t < 0.5 ? reducedMotion : other.reducedMotion,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }
}

abstract final class P5DesignSystem {
  static const Color seed = Color(0xff6558d3);
  static const Duration normalThemeTransition = Duration(milliseconds: 180);

  static ThemeData light({bool reducedMotion = false}) {
    return theme(
      brightness: Brightness.light,
      reducedMotion: reducedMotion,
    );
  }

  static ThemeData dark({bool reducedMotion = false}) {
    return theme(
      brightness: Brightness.dark,
      reducedMotion: reducedMotion,
    );
  }

  static ThemeData highContrastLight({bool reducedMotion = false}) {
    return theme(
      brightness: Brightness.light,
      highContrast: true,
      reducedMotion: reducedMotion,
    );
  }

  static ThemeData highContrastDark({bool reducedMotion = false}) {
    return theme(
      brightness: Brightness.dark,
      highContrast: true,
      reducedMotion: reducedMotion,
    );
  }

  static Duration themeTransitionDuration(bool reducedMotion) {
    return reducedMotion ? Duration.zero : normalThemeTransition;
  }

  static ThemeData theme({
    required Brightness brightness,
    bool highContrast = false,
    bool reducedMotion = false,
  }) {
    final tokens = _tokens(
      brightness: brightness,
      highContrast: highContrast,
      reducedMotion: reducedMotion,
    );
    final dark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: tokens.focusRing,
      onPrimary: _foregroundFor(tokens.focusRing),
      secondary: tokens.info,
      onSecondary: _foregroundFor(tokens.info),
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      outline: tokens.outline,
      outlineVariant: highContrast
          ? tokens.outline
          : tokens.outline.withValues(alpha: 0.72),
      error: tokens.danger,
      onError: _foregroundFor(tokens.danger),
    );
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 32,
        height: 1.18,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 27,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 23,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 17,
        height: 1.48,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: tokens.bodyFontSize,
        height: 1.48,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 14,
        height: 1.42,
        color: tokens.onSurfaceMuted,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: tokens.buttonFontSize,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: tokens.labelFontSize,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 13,
        height: 1.25,
      ),
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
      borderSide: BorderSide(
        color: tokens.outline,
        width: highContrast ? 2 : 1,
      ),
    );
    final focusBorder = inputBorder.copyWith(
      borderSide: BorderSide(
        color: tokens.focusRing,
        width: highContrast ? 3 : 2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      focusColor: tokens.focusRing.withValues(alpha: highContrast ? 0.32 : 0.2),
      hoverColor:
          tokens.focusRing.withValues(alpha: highContrast ? 0.18 : 0.08),
      highlightColor:
          tokens.focusRing.withValues(alpha: highContrast ? 0.22 : 0.1),
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: reducedMotion
          ? const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: _P5NoTransitionPageTransitionsBuilder(),
                TargetPlatform.fuchsia: _P5NoTransitionPageTransitionsBuilder(),
                TargetPlatform.iOS: _P5NoTransitionPageTransitionsBuilder(),
                TargetPlatform.linux: _P5NoTransitionPageTransitionsBuilder(),
                TargetPlatform.macOS: _P5NoTransitionPageTransitionsBuilder(),
                TargetPlatform.windows: _P5NoTransitionPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: tokens.onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: tokens.elevationLow,
        surfaceTintColor: Colors.transparent,
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(
            color: tokens.outline,
            width: highContrast ? 2 : 1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceRaised,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusBorder,
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: tokens.danger,
            width: highContrast ? 3 : 2,
          ),
        ),
        focusedErrorBorder: focusBorder.copyWith(
          borderSide: BorderSide(
            color: tokens.danger,
            width: highContrast ? 3 : 2.4,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.spaceMd,
          vertical: tokens.spaceMd - 1,
        ),
        labelStyle: TextStyle(
          fontSize: tokens.labelFontSize,
          color: tokens.onSurfaceMuted,
        ),
        helperStyle: TextStyle(
          fontSize: 14,
          color: tokens.onSurfaceMuted,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        backgroundColor: tokens.surface,
        indicatorColor: tokens.focusRing.withValues(
          alpha: highContrast ? 0.32 : 0.16,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          return TextStyle(
            color: tokens.onSurface,
            fontSize: tokens.navigationFontSize,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.focusRing.withValues(
          alpha: highContrast ? 0.32 : 0.16,
        ),
        selectedIconTheme: IconThemeData(color: tokens.focusRing, size: 26),
        unselectedIconTheme: IconThemeData(
          color: tokens.onSurfaceMuted,
          size: 24,
        ),
        selectedLabelTextStyle: TextStyle(
          color: tokens.onSurface,
          fontSize: tokens.navigationFontSize,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: tokens.onSurfaceMuted,
          fontSize: tokens.navigationFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: TextStyle(
            fontSize: tokens.buttonFontSize,
            fontWeight: FontWeight.w700,
          ),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceLg,
            vertical: tokens.spaceMd - 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.onSurface,
          side: BorderSide(
            color: tokens.outline,
            width: highContrast ? 2 : 1,
          ),
          textStyle: TextStyle(
            fontSize: tokens.buttonFontSize,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceLg,
            vertical: tokens.spaceMd - 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.focusRing,
          textStyle: TextStyle(
            fontSize: tokens.buttonFontSize,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceMd,
            vertical: tokens.spaceSm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.onSurface,
          minimumSize: const Size(48, 48),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.outline,
        thickness: highContrast ? 2 : 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xfff3f0f7) : const Color(0xff202127),
        contentTextStyle: TextStyle(
          color: dark ? const Color(0xff17151b) : Colors.white,
          fontSize: tokens.bodyFontSize,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(
          color: dark ? Colors.black : Colors.white,
          fontSize: tokens.labelFontSize,
        ),
        decoration: BoxDecoration(
          color: dark ? Colors.white : const Color(0xff202127),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        waitDuration:
            reducedMotion ? Duration.zero : const Duration(milliseconds: 450),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.focusRing,
        selectionHandleColor: tokens.focusRing,
        selectionColor: tokens.focusRing.withValues(alpha: 0.28),
      ),
    );
  }

  static P5DesignTokens _tokens({
    required Brightness brightness,
    required bool highContrast,
    required bool reducedMotion,
  }) {
    final dark = brightness == Brightness.dark;
    final fast =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 100);
    final standard =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 180);
    final slow =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 280);

    if (highContrast && dark) {
      return P5DesignTokens(
        canvas: Colors.black,
        surface: const Color(0xff050505),
        surfaceRaised: const Color(0xff141414),
        outline: Colors.white,
        onSurface: Colors.white,
        onSurfaceMuted: const Color(0xffe6e6e6),
        focusRing: const Color(0xffffff00),
        success: const Color(0xff7cff7c),
        warning: const Color(0xffffd27a),
        danger: const Color(0xffff9e9e),
        info: const Color(0xff9dcbff),
        ownerMode: const Color(0xffffb58a),
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        radiusSm: 8,
        radiusMd: 14,
        radiusLg: 20,
        elevationLow: 0,
        elevationHigh: 0,
        bodyFontSize: 16,
        labelFontSize: 14,
        navigationFontSize: 15,
        buttonFontSize: 15,
        motionFast: fast,
        motionStandard: standard,
        motionSlow: slow,
        reducedMotion: reducedMotion,
        highContrast: true,
      );
    }
    if (highContrast) {
      return P5DesignTokens(
        canvas: Colors.white,
        surface: Colors.white,
        surfaceRaised: const Color(0xfff2f2f2),
        outline: Colors.black,
        onSurface: Colors.black,
        onSurfaceMuted: const Color(0xff202020),
        focusRing: const Color(0xff0000ee),
        success: const Color(0xff004d00),
        warning: const Color(0xff5a2d00),
        danger: const Color(0xff7a0000),
        info: const Color(0xff00006b),
        ownerMode: const Color(0xff4a1700),
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        radiusSm: 8,
        radiusMd: 14,
        radiusLg: 20,
        elevationLow: 0,
        elevationHigh: 0,
        bodyFontSize: 16,
        labelFontSize: 14,
        navigationFontSize: 15,
        buttonFontSize: 15,
        motionFast: fast,
        motionStandard: standard,
        motionSlow: slow,
        reducedMotion: reducedMotion,
        highContrast: true,
      );
    }
    if (dark) {
      return P5DesignTokens(
        canvas: const Color(0xff111217),
        surface: const Color(0xff1a1b21),
        surfaceRaised: const Color(0xff24252c),
        outline: const Color(0xff62636e),
        onSurface: const Color(0xfff3f0f7),
        onSurfaceMuted: const Color(0xffc8c4d0),
        focusRing: const Color(0xffc8bfff),
        success: const Color(0xff6dd58c),
        warning: const Color(0xffffc46b),
        danger: const Color(0xffffb4ab),
        info: const Color(0xffa8c7fa),
        ownerMode: const Color(0xffffb68c),
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        radiusSm: 10,
        radiusMd: 14,
        radiusLg: 20,
        elevationLow: 0,
        elevationHigh: 3,
        bodyFontSize: 16,
        labelFontSize: 14,
        navigationFontSize: 15,
        buttonFontSize: 15,
        motionFast: fast,
        motionStandard: standard,
        motionSlow: slow,
        reducedMotion: reducedMotion,
        highContrast: false,
      );
    }
    return P5DesignTokens(
      canvas: const Color(0xfff8f7f4),
      surface: Colors.white,
      surfaceRaised: const Color(0xfff1eff8),
      outline: const Color(0xffc8c6d0),
      onSurface: const Color(0xff1a1b20),
      onSurfaceMuted: const Color(0xff555761),
      focusRing: const Color(0xff4c3bcb),
      success: const Color(0xff137333),
      warning: const Color(0xff7a4300),
      danger: const Color(0xffba1a1a),
      info: const Color(0xff005ac1),
      ownerMode: const Color(0xff8b3a0e),
      spaceXs: 4,
      spaceSm: 8,
      spaceMd: 16,
      spaceLg: 24,
      spaceXl: 32,
      radiusSm: 10,
      radiusMd: 14,
      radiusLg: 20,
      elevationLow: 0,
      elevationHigh: 3,
      bodyFontSize: 16,
      labelFontSize: 14,
      navigationFontSize: 15,
      buttonFontSize: 15,
      motionFast: fast,
      motionStandard: standard,
      motionSlow: slow,
      reducedMotion: reducedMotion,
      highContrast: false,
    );
  }

  static Color _foregroundFor(Color background) {
    return background.computeLuminance() > 0.42 ? Colors.black : Colors.white;
  }
}

class _P5NoTransitionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _P5NoTransitionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

Duration _lerpDuration(Duration start, Duration end, double t) {
  return Duration(
    microseconds: lerpDouble(
      start.inMicroseconds.toDouble(),
      end.inMicroseconds.toDouble(),
      t,
    )!
        .round(),
  );
}
