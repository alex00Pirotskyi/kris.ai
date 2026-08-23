import 'package:flutter/foundation.dart';

@immutable
class P5ShellLayoutState {
  const P5ShellLayoutState({
    required this.leftRailWidth,
    required this.inspectorWidth,
    required this.activityDrawerHeight,
    required this.inspectorOpen,
    required this.activityDrawerOpen,
  });

  static const double minimumThreePaneWidth = 1180;
  static const double minimumLeftRailWidth = 220;
  static const double maximumLeftRailWidth = 360;
  static const double minimumInspectorWidth = 260;
  static const double maximumInspectorWidth = 420;
  static const double minimumActivityHeight = 140;
  static const double maximumActivityHeight = 360;

  static const P5ShellLayoutState defaults = P5ShellLayoutState(
    leftRailWidth: 276,
    inspectorWidth: 320,
    activityDrawerHeight: 220,
    inspectorOpen: false,
    activityDrawerOpen: false,
  );

  final double leftRailWidth;
  final double inspectorWidth;
  final double activityDrawerHeight;
  final bool inspectorOpen;
  final bool activityDrawerOpen;

  P5ShellLayoutState copyWith({
    double? leftRailWidth,
    double? inspectorWidth,
    double? activityDrawerHeight,
    bool? inspectorOpen,
    bool? activityDrawerOpen,
  }) {
    return P5ShellLayoutState(
      leftRailWidth: leftRailWidth ?? this.leftRailWidth,
      inspectorWidth: inspectorWidth ?? this.inspectorWidth,
      activityDrawerHeight: activityDrawerHeight ?? this.activityDrawerHeight,
      inspectorOpen: inspectorOpen ?? this.inspectorOpen,
      activityDrawerOpen: activityDrawerOpen ?? this.activityDrawerOpen,
    ).normalized();
  }

  P5ShellLayoutState normalized() {
    return P5ShellLayoutState(
      leftRailWidth: leftRailWidth
          .clamp(minimumLeftRailWidth, maximumLeftRailWidth)
          .toDouble(),
      inspectorWidth: inspectorWidth
          .clamp(minimumInspectorWidth, maximumInspectorWidth)
          .toDouble(),
      activityDrawerHeight: activityDrawerHeight
          .clamp(minimumActivityHeight, maximumActivityHeight)
          .toDouble(),
      inspectorOpen: inspectorOpen,
      activityDrawerOpen: activityDrawerOpen,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'leftRailWidth': leftRailWidth,
    'inspectorWidth': inspectorWidth,
    'activityDrawerHeight': activityDrawerHeight,
    'inspectorOpen': inspectorOpen,
    'activityDrawerOpen': activityDrawerOpen,
  };

  static P5ShellLayoutState fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('P5 shell layout must be an object.');
    }
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported P5 shell layout schema.');
    }
    double finiteNumber(String key) {
      final raw = json[key];
      if (raw is! num || !raw.isFinite) {
        throw FormatException('P5 shell layout $key must be finite.');
      }
      return raw.toDouble();
    }

    bool boolean(String key) {
      final raw = json[key];
      if (raw is! bool) {
        throw FormatException('P5 shell layout $key must be boolean.');
      }
      return raw;
    }

    return P5ShellLayoutState(
      leftRailWidth: finiteNumber('leftRailWidth'),
      inspectorWidth: finiteNumber('inspectorWidth'),
      activityDrawerHeight: finiteNumber('activityDrawerHeight'),
      inspectorOpen: boolean('inspectorOpen'),
      activityDrawerOpen: boolean('activityDrawerOpen'),
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is P5ShellLayoutState &&
      other.leftRailWidth == leftRailWidth &&
      other.inspectorWidth == inspectorWidth &&
      other.activityDrawerHeight == activityDrawerHeight &&
      other.inspectorOpen == inspectorOpen &&
      other.activityDrawerOpen == activityDrawerOpen;

  @override
  int get hashCode => Object.hash(
    leftRailWidth,
    inspectorWidth,
    activityDrawerHeight,
    inspectorOpen,
    activityDrawerOpen,
  );
}

abstract interface class P5ShellLayoutPersistence {
  Future<P5ShellLayoutState?> load();
  Future<void> save(P5ShellLayoutState state);
}
