import 'dart:convert';

import 'dart:async';

import 'capability_grant_v2.dart';

Object? _p2BoundaryCanonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value
        .map<Object?>(_p2BoundaryCanonicalValue)
        .toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _p2BoundaryCanonicalValue(value[key]),
    };
  }
  throw StateError('p2_boundary_non_json_value');
}

String p2BoundaryCanonicalJson(Object? value) =>
    jsonEncode(_p2BoundaryCanonicalValue(value));

class P2AuthorizationException implements Exception {
  const P2AuthorizationException(this.code);

  final String code;

  @override
  String toString() => 'P2AuthorizationException($code)';
}

class P2EffectBinding {
  const P2EffectBinding({
    required this.runId,
    required this.taskId,
    required this.actorId,
    required this.toolId,
    required this.accessProfileId,
    required this.capabilityId,
    required this.operation,
  });

  final String runId;
  final String taskId;
  final String actorId;
  final String toolId;
  final String accessProfileId;
  final String capabilityId;
  final String operation;
}

class P2GrantConsumption {
  const P2GrantConsumption({
    required this.grantId,
    required this.requestId,
    required this.useNumber,
    required this.previousUseNumber,
    required this.stateVersion,
    required this.revocationEpoch,
    required this.consumedAt,
    required this.auth,
  });

  final String grantId;
  final String requestId;
  final int useNumber;
  final int previousUseNumber;
  final int stateVersion;
  final int revocationEpoch;
  final DateTime consumedAt;
  final Map<String, String> auth;

  factory P2GrantConsumption.fromJson(Map<String, Object?> value) {
    if (value['schemaVersion'] != '1.0.0') {
      throw const FormatException('consumption_receipt_version_invalid');
    }
    final grantId = value['grantId'];
    final requestId = value['requestId'];
    final useNumber = value['useNumber'];
    final previousUseNumber = value['previousUseNumber'];
    final stateVersion = value['stateVersion'];
    final revocationEpoch = value['revocationEpoch'];
    final consumedAtValue = value['consumedAt'];
    final rawAuth = value['auth'];
    if (grantId is! String ||
        grantId.isEmpty ||
        requestId is! String ||
        requestId.isEmpty ||
        useNumber is! int ||
        useNumber < 1 ||
        previousUseNumber is! int ||
        previousUseNumber != useNumber - 1 ||
        stateVersion is! int ||
        stateVersion < useNumber ||
        revocationEpoch is! int ||
        revocationEpoch < 0 ||
        consumedAtValue is! String ||
        rawAuth is! Map) {
      throw const FormatException('consumption_receipt_shape_invalid');
    }
    final consumedAt = DateTime.tryParse(consumedAtValue)?.toUtc();
    if (consumedAt == null) {
      throw const FormatException('consumption_receipt_time_invalid');
    }
    final auth = <String, String>{};
    for (final entry in rawAuth.entries) {
      final key = entry.key;
      final item = entry.value;
      if (key is! String || item is! String) {
        throw const FormatException('consumption_receipt_auth_invalid');
      }
      auth[key] = item;
    }
    if (auth['algorithm'] != 'hmac-sha256' ||
        (auth['keyId'] ?? '').isEmpty ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(auth['mac'] ?? '')) {
      throw const FormatException('consumption_receipt_auth_invalid');
    }
    return P2GrantConsumption(
      grantId: grantId,
      requestId: requestId,
      useNumber: useNumber,
      previousUseNumber: previousUseNumber,
      stateVersion: stateVersion,
      revocationEpoch: revocationEpoch,
      consumedAt: consumedAt,
      auth: Map<String, String>.unmodifiable(auth),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '1.0.0',
        'grantId': grantId,
        'requestId': requestId,
        'useNumber': useNumber,
        'previousUseNumber': previousUseNumber,
        'stateVersion': stateVersion,
        'revocationEpoch': revocationEpoch,
        'consumedAt': consumedAt.toUtc().toIso8601String(),
        'auth': auth,
      };
}

abstract interface class P2GrantUseLedger {
  Future<P2GrantConsumption> consumeBeforeEffect({
    required String grantId,
    required String requestId,
    required int maxUses,
  });

  Future<bool> isRevoked(String grantId);
}

class P2EffectBoundary {
  const P2EffectBoundary(this.ledger, {this.clock = DateTime.now});

  final P2GrantUseLedger ledger;
  final DateTime Function() clock;

  Future<Map<String, Object?>> authorize({
    required String requestId,
    required Map<String, Object?> policyDecision,
    required CapabilityGrantV2 grant,
    required P2EffectBinding expected,
  }) async {
    if (policyDecision['status'] != 'allow') {
      throw const P2AuthorizationException('policy_not_allow');
    }

    final binding = grant.binding;
    final exact = <String, String>{
      'runId': expected.runId,
      'taskId': expected.taskId,
      'actorId': expected.actorId,
      'toolId': expected.toolId,
      'accessProfileId': expected.accessProfileId,
    };
    for (final entry in exact.entries) {
      if (binding[entry.key] != entry.value) {
        throw P2AuthorizationException('grant_${entry.key}_mismatch');
      }
    }

    final decisionBinding = Map<String, Object?>.from(
      policyDecision['binding']! as Map,
    );
    for (final entry in exact.entries) {
      if (decisionBinding[entry.key] != entry.value) {
        throw P2AuthorizationException('decision_${entry.key}_mismatch');
      }
    }
    if (decisionBinding['capabilityId'] != expected.capabilityId) {
      throw const P2AuthorizationException('capability_mismatch');
    }
    if (expected.accessProfileId != 'owner' &&
        expected.accessProfileId != 'owner_unattended') {
      throw const P2AuthorizationException('owner_profile_required');
    }

    final decisionEffect = policyDecision['effect'];
    final effectiveScope = policyDecision['effectiveScope'];
    if (binding['operation'] != null &&
        binding['operation'] != expected.operation) {
      throw const P2AuthorizationException('operation_mismatch');
    }
    if (decisionEffect is Map &&
        (decisionEffect['p2Operation'] ?? decisionEffect['action']) !=
            expected.operation) {
      throw const P2AuthorizationException('operation_mismatch');
    }
    final grantScope = grant.toJson()['scope'];
    if (effectiveScope is Map &&
        grantScope is Map &&
        p2BoundaryCanonicalJson(effectiveScope) !=
            p2BoundaryCanonicalJson(grantScope)) {
      throw const P2AuthorizationException('scope_mismatch');
    }
    if (await ledger.isRevoked(grant.grantId)) {
      throw const P2AuthorizationException('grant_revoked');
    }

    final validity = grant.validity;
    final now = clock().toUtc();
    final notBefore = DateTime.parse(validity['notBefore']! as String).toUtc();
    final expiresAt = DateTime.parse(validity['expiresAt']! as String).toUtc();
    if (now.isBefore(notBefore)) {
      throw const P2AuthorizationException('grant_not_yet_valid');
    }
    if (!now.isBefore(expiresAt)) {
      throw const P2AuthorizationException('grant_expired');
    }

    final consumption = await ledger.consumeBeforeEffect(
      grantId: grant.grantId,
      requestId: requestId,
      maxUses: validity['maxUses']! as int,
    );
    if (consumption.grantId != grant.grantId ||
        consumption.requestId != requestId) {
      throw const P2AuthorizationException('consumption_binding_mismatch');
    }
    return <String, Object?>{
      'grantId': grant.grantId,
      'useNumber': consumption.useNumber,
      'authorizedAt': now.toIso8601String(),
      'consumptionReceipt': consumption.toJson(),
    };
  }
}
