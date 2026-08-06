// P6-001 model registry v2 public contract.
import 'dart:convert';

import '../domain.dart';
import 'model_registry.dart' as legacy;

export 'model_registry.dart' hide ModelDefinitionRegistry;

/// Public fail-closed registry facade.
///
/// The underlying declarative records remain immutable. A model discovered by
/// canonical ID or alias may reuse a registered record only when every
/// applicable artifact identity field matches exactly. Identity drift is
/// returned as a non-persistent evaluation-only descriptor with a deterministic
/// quarantine ID, so it cannot be passed to [requireApproved].
class ModelDefinitionRegistry {
  ModelDefinitionRegistry({
    required Iterable<legacy.ModelProviderDescriptor> providers,
    required Iterable<legacy.ModelDefinition> models,
  }) : _delegate = legacy.ModelDefinitionRegistry(
          providers: providers,
          models: models,
        );

  ModelDefinitionRegistry._(this._delegate);

  factory ModelDefinitionRegistry.fromJson(Map<String, Object?> json) =>
      ModelDefinitionRegistry._(
        legacy.ModelDefinitionRegistry.fromJson(json),
      );

  final legacy.ModelDefinitionRegistry _delegate;

  List<legacy.ModelProviderDescriptor> get providers => _delegate.providers;

  List<legacy.ModelDefinition> get models => _delegate.models;

  legacy.ModelProviderDescriptor? provider(String providerId) =>
      _delegate.provider(providerId);

  legacy.ModelDefinition? lookup(String providerId, String modelIdOrAlias) =>
      _delegate.lookup(providerId, modelIdOrAlias);

  legacy.ModelDefinition resolveDiscovered(ModelIdentity identity) {
    final existing = _delegate.lookup(identity.providerId, identity.name);
    if (existing == null) {
      return _delegate.resolveDiscovered(identity);
    }

    final discoveredDigest = _normalized(identity.digest);
    final discoveredParameterSize = _normalized(identity.parameterSize);
    final discoveredQuantization = _normalized(identity.quantization);
    final mismatches = <String>[];

    void compare(String field, String? registered, String? discovered) {
      if (registered != discovered) {
        mismatches.add(field);
      }
    }

    compare('digest', existing.digest, discoveredDigest);
    compare(
      'parameterSize',
      existing.parameterSize,
      discoveredParameterSize,
    );
    compare(
      'quantization',
      existing.quantization,
      discoveredQuantization,
    );

    if (mismatches.isEmpty) {
      return existing;
    }

    final quarantineModelId =
        '${identity.name}:identity-mismatch:${_identityFingerprint(identity)}';
    if (_delegate.lookup(identity.providerId, quarantineModelId) != null) {
      throw legacy.ModelRegistryValidationException(
        'discovered model ${identity.exactId} identity quarantine collides '
        'with a registered model',
      );
    }

    return legacy.ModelDefinition.evaluationOnly(
      providerId: identity.providerId,
      modelId: quarantineModelId,
      displayName: identity.name,
      digest: discoveredDigest,
      parameterSize: discoveredParameterSize,
      quantization: discoveredQuantization,
      limits: legacy.ModelLimits.unknown(),
      toolProfile: legacy.ModelToolProfile.unknown(),
      dataBoundary: existing.dataBoundary,
      cost: legacy.ModelCostProfile.unknown(),
      evaluationReasons: <String>[
        'discovered identity does not match registered '
            '${existing.registryKey}: ${mismatches.join(', ')}',
        'approval is blocked until the exact artifact identity is registered '
            'and measured',
      ],
    );
  }

  legacy.ModelDefinition requireApproved({
    required String providerId,
    required String modelIdOrAlias,
    required String taskClassId,
  }) =>
      _delegate.requireApproved(
        providerId: providerId,
        modelIdOrAlias: modelIdOrAlias,
        taskClassId: taskClassId,
      );

  Map<String, Object?> toJson() => _delegate.toJson();
}

String? _normalized(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _identityFingerprint(ModelIdentity identity) {
  final canonical = jsonEncode(<String, Object?>{
    'digest': _normalized(identity.digest),
    'name': identity.name.trim(),
    'parameterSize': _normalized(identity.parameterSize),
    'providerId': identity.providerId.trim(),
    'quantization': _normalized(identity.quantization),
  });
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
