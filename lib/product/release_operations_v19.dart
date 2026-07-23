const String releaseOperationsV19Version = '1.9.0+190';

class PolicyProfileV19 {
  const PolicyProfileV19({
    required this.id,
    required this.name,
    required this.dataBoundary,
    required this.networkPolicy,
    required this.allowA2ADelegation,
    required this.allowRemoteMcp,
    required this.allowedUpdateChannels,
  });

  final String id;
  final String name;
  final String dataBoundary;
  final String networkPolicy;
  final bool allowA2ADelegation;
  final bool allowRemoteMcp;
  final List<String> allowedUpdateChannels;
}

class SupportLifecyclePolicyV19 {
  const SupportLifecyclePolicyV19({
    required this.currentVersion,
    required this.minimumSupportedUpgradeFrom,
    required this.minimumSupportedRollbackTo,
  });

  final String currentVersion;
  final String minimumSupportedUpgradeFrom;
  final String minimumSupportedRollbackTo;
}

class AuditVerificationResultV19 {
  const AuditVerificationResultV19({
    required this.verified,
    required this.recordCount,
    this.failure,
  });

  final bool verified;
  final int recordCount;
  final String? failure;
}
