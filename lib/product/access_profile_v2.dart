import 'dart:convert';

enum AccessProfileId {
  chat,
  project,
  owner,
  ownerUnattended,
  isolatedUntrusted,
}

enum ApprovalPolicy { always, highRiskOnly, never }

class AccessProfileValidationException implements Exception {
  const AccessProfileValidationException(this.message);

  final String message;

  @override
  String toString() => 'AccessProfileValidationException: $message';
}

AccessProfileId _parseProfileId(Object? value) {
  switch (value) {
    case 'chat':
      return AccessProfileId.chat;
    case 'project':
      return AccessProfileId.project;
    case 'owner':
      return AccessProfileId.owner;
    case 'owner_unattended':
      return AccessProfileId.ownerUnattended;
    case 'isolated_untrusted':
      return AccessProfileId.isolatedUntrusted;
    default:
      throw AccessProfileValidationException('unknown profileId: $value');
  }
}

String _profileIdToWire(AccessProfileId value) {
  switch (value) {
    case AccessProfileId.chat:
      return 'chat';
    case AccessProfileId.project:
      return 'project';
    case AccessProfileId.owner:
      return 'owner';
    case AccessProfileId.ownerUnattended:
      return 'owner_unattended';
    case AccessProfileId.isolatedUntrusted:
      return 'isolated_untrusted';
  }
}

ApprovalPolicy _parseApprovalPolicy(Object? value) {
  switch (value) {
    case 'always':
      return ApprovalPolicy.always;
    case 'high_risk_only':
      return ApprovalPolicy.highRiskOnly;
    case 'never':
      return ApprovalPolicy.never;
    default:
      throw AccessProfileValidationException('invalid approvalPolicy: $value');
  }
}

String _approvalPolicyToWire(ApprovalPolicy value) {
  switch (value) {
    case ApprovalPolicy.always:
      return 'always';
    case ApprovalPolicy.highRiskOnly:
      return 'high_risk_only';
    case ApprovalPolicy.never:
      return 'never';
  }
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map) {
    throw AccessProfileValidationException('$label must be an object');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

bool _boolean(Object? value, String label) {
  if (value is! bool) {
    throw AccessProfileValidationException('$label must be boolean');
  }
  return value;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> value) {
  return jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

class AccessProfileV2 {
  AccessProfileV2._({
    required this.schemaVersion,
    required this.profileRevision,
    required this.profileId,
    required this.displayName,
    required this.authorityClass,
    required this.sandboxed,
    required this.interactive,
    required this.unattendedAllowed,
    required this.approvalPolicy,
    required this.filesystem,
    required this.process,
    required this.network,
    required this.browser,
    required this.credentials,
    required this.dataBoundary,
  });

  factory AccessProfileV2.fromJson(Map<String, dynamic> json) {
    final profile = AccessProfileV2._(
      schemaVersion: json['schemaVersion']?.toString() ?? '',
      profileRevision:
          json['profileRevision'] is int ? json['profileRevision'] as int : 0,
      profileId: _parseProfileId(json['profileId']),
      displayName: json['displayName']?.toString() ?? '',
      authorityClass: json['authorityClass']?.toString() ?? '',
      sandboxed: _boolean(json['sandboxed'], 'sandboxed'),
      interactive: _boolean(json['interactive'], 'interactive'),
      unattendedAllowed:
          _boolean(json['unattendedAllowed'], 'unattendedAllowed'),
      approvalPolicy: _parseApprovalPolicy(json['approvalPolicy']),
      filesystem: _map(json['filesystem'], 'filesystem'),
      process: _map(json['process'], 'process'),
      network: _map(json['network'], 'network'),
      browser: _map(json['browser'], 'browser'),
      credentials: _map(json['credentials'], 'credentials'),
      dataBoundary: _map(json['dataBoundary'], 'dataBoundary'),
    );
    profile.validate();
    return profile;
  }

  final String schemaVersion;
  final int profileRevision;
  final AccessProfileId profileId;
  final String displayName;
  final String authorityClass;
  final bool sandboxed;
  final bool interactive;
  final bool unattendedAllowed;
  final ApprovalPolicy approvalPolicy;
  final Map<String, dynamic> filesystem;
  final Map<String, dynamic> process;
  final Map<String, dynamic> network;
  final Map<String, dynamic> browser;
  final Map<String, dynamic> credentials;
  final Map<String, dynamic> dataBoundary;

  void validate() {
    if (schemaVersion != '2.0.0') {
      throw const AccessProfileValidationException(
          'schemaVersion must be 2.0.0');
    }
    if (profileRevision < 1) {
      throw const AccessProfileValidationException(
          'profileRevision must be positive');
    }
    if (displayName.isEmpty || authorityClass.isEmpty) {
      throw const AccessProfileValidationException(
          'profile identity fields are required');
    }
    if (dataBoundary['contentMayBecomeAuthority'] != false) {
      throw const AccessProfileValidationException(
          'content cannot become authority');
    }
    switch (profileId) {
      case AccessProfileId.chat:
        final hasEffect = filesystem['read'] == true ||
            filesystem['write'] == true ||
            filesystem['delete'] == true ||
            process['finiteCommands'] == true ||
            process['interactivePty'] == true ||
            network['scope'] != 'none' ||
            browser['scope'] != 'none' ||
            credentials['mode'] != 'none';
        if (hasEffect) {
          throw const AccessProfileValidationException(
              'chat profile cannot authorize effects');
        }
        break;
      case AccessProfileId.project:
        final roots = filesystem['roots'];
        if (filesystem['scope'] != 'project' ||
            roots is! List ||
            roots.isEmpty) {
          throw const AccessProfileValidationException(
              'project profile requires project roots');
        }
        if (filesystem['absolutePaths'] != false) {
          throw const AccessProfileValidationException(
              'project profile cannot authorize arbitrary absolute paths');
        }
        if (process['elevation'] != 'none' || process['services'] != false) {
          throw const AccessProfileValidationException(
              'project profile cannot elevate or control services');
        }
        break;
      case AccessProfileId.owner:
        if (sandboxed || filesystem['scope'] != 'current_account') {
          throw const AccessProfileValidationException(
              'owner must be explicit non-sandbox authority');
        }
        if (!interactive || unattendedAllowed) {
          throw const AccessProfileValidationException(
              'owner profile must remain interactive');
        }
        break;
      case AccessProfileId.ownerUnattended:
        if (sandboxed || filesystem['scope'] != 'current_account') {
          throw const AccessProfileValidationException(
              'owner_unattended must be explicit non-sandbox authority');
        }
        if (interactive || !unattendedAllowed) {
          throw const AccessProfileValidationException(
              'owner_unattended lifecycle is invalid');
        }
        if (process['elevation'] != 'none') {
          throw const AccessProfileValidationException(
              'owner_unattended cannot request elevation');
        }
        if (credentials['rawReveal'] != 'never') {
          throw const AccessProfileValidationException(
              'unattended raw secret reveal is forbidden');
        }
        if (credentials['mode'] != 'brokered_leases' ||
            credentials['unattendedUse'] != true) {
          throw const AccessProfileValidationException(
              'owner_unattended requires brokered unattended leases');
        }
        break;
      case AccessProfileId.isolatedUntrusted:
        if (!sandboxed) {
          throw const AccessProfileValidationException(
              'isolated_untrusted must be sandboxed');
        }
        if (filesystem['scope'] != 'sandbox' ||
            filesystem['absolutePaths'] != false) {
          throw const AccessProfileValidationException(
              'isolated_untrusted filesystem must remain sandbox-only');
        }
        if (process['scope'] != 'sandbox' || process['elevation'] != 'none') {
          throw const AccessProfileValidationException(
              'isolated_untrusted process scope is invalid');
        }
        if (credentials['mode'] != 'none' ||
            credentials['rawReveal'] != 'never') {
          throw const AccessProfileValidationException(
              'isolated_untrusted credentials must be none');
        }
        if (network['privateAddresses'] != false ||
            network['listen'] != false) {
          throw const AccessProfileValidationException(
              'isolated_untrusted network must reject private/listening access');
        }
        if (browser['authenticatedProfiles'] != false) {
          throw const AccessProfileValidationException(
              'isolated_untrusted cannot use authenticated browser profiles');
        }
        break;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'profileRevision': profileRevision,
        'profileId': _profileIdToWire(profileId),
        'displayName': displayName,
        'authorityClass': authorityClass,
        'sandboxed': sandboxed,
        'interactive': interactive,
        'unattendedAllowed': unattendedAllowed,
        'approvalPolicy': _approvalPolicyToWire(approvalPolicy),
        'filesystem': _deepCopy(filesystem),
        'process': _deepCopy(process),
        'network': _deepCopy(network),
        'browser': _deepCopy(browser),
        'credentials': _deepCopy(credentials),
        'dataBoundary': _deepCopy(dataBoundary),
      };
}
