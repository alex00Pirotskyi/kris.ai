enum CapabilityDoctorDepth { quick, full }

enum CapabilityDoctorStatus { ready, warning, blocked }

enum CapabilityDoctorAction {
  none,
  connectModel,
  openProjects,
  openSettings,
  retryDoctor,
}

final class CapabilityDoctorCheck {
  const CapabilityDoctorCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.message,
    required this.required,
    this.action = CapabilityDoctorAction.none,
    this.durationMilliseconds = 0,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String title;
  final CapabilityDoctorStatus status;
  final String message;
  final bool required;
  final CapabilityDoctorAction action;
  final int durationMilliseconds;
  final Map<String, Object?> details;

  bool get ready => status == CapabilityDoctorStatus.ready;
}

final class CapabilityDoctorReport {
  CapabilityDoctorReport({
    required this.depth,
    required List<CapabilityDoctorCheck> checks,
    DateTime? checkedAt,
  }) : checks = List<CapabilityDoctorCheck>.unmodifiable(
         _validatedChecks(checks),
       ),
       checkedAt = checkedAt ?? DateTime.now().toUtc();

  final CapabilityDoctorDepth depth;
  final List<CapabilityDoctorCheck> checks;
  final DateTime checkedAt;

  int get readyCount => checks.where((item) => item.ready).length;
  int get warningCount => checks
      .where((item) => item.status == CapabilityDoctorStatus.warning)
      .length;
  int get blockedCount => checks
      .where((item) => item.status == CapabilityDoctorStatus.blocked)
      .length;

  bool get coreReady =>
      checks.where((item) => item.required).every((item) => item.ready);

  bool get allReady => checks.every((item) => item.ready);

  List<CapabilityDoctorCheck> get actionable =>
      List<CapabilityDoctorCheck>.unmodifiable(
        checks.where(
          (item) => !item.ready && item.action != CapabilityDoctorAction.none,
        ),
      );

  CapabilityDoctorCheck? byId(String id) {
    for (final check in checks) {
      if (check.id == id) return check;
    }
    return null;
  }

  static List<CapabilityDoctorCheck> _validatedChecks(
    List<CapabilityDoctorCheck> input,
  ) {
    final ids = <String>{};
    for (final check in input) {
      if (check.id.trim().isEmpty) {
        throw ArgumentError.value(
          check.id,
          'id',
          'Capability check id is empty.',
        );
      }
      if (!ids.add(check.id)) {
        throw ArgumentError.value(
          check.id,
          'id',
          'Capability check ids must be unique.',
        );
      }
    }
    return List<CapabilityDoctorCheck>.from(input);
  }
}
