import 'dart:collection';
import 'dart:convert';

import '../domain.dart';

final RegExp _providerIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
final RegExp _modelIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/+-]*$');
final RegExp _stableIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

/// Validation failure for the declarative P6-001 model registry contract.
class ModelRegistryValidationException implements Exception {
  const ModelRegistryValidationException(this.message);

  final String message;

  @override
  String toString() => 'ModelRegistryValidationException: $message';
}

/// Registry support is deliberately binary until later P6 tasks add measured
/// compatibility and promotion workflows.
enum ModelSupportStatus { evaluationOnly, approved }

/// Where model input leaves the Kristin process boundary.
enum ModelDataBoundary {
  localOnly,
  customerManagedEndpoint,
  thirdPartyService,
}

/// Strength of the evidence behind a declared limit or capability profile.
enum ModelEvidenceLevel { unknown, declared, measured }

/// Direct model invocation cost classification.
enum ModelCostKind { unknown, noDirectCharge, metered }

extension ModelSupportStatusWireName on ModelSupportStatus {
  String get wireName => switch (this) {
        ModelSupportStatus.evaluationOnly => 'evaluation_only',
        ModelSupportStatus.approved => 'approved',
      };
}

extension ModelDataBoundaryWireName on ModelDataBoundary {
  String get wireName => switch (this) {
        ModelDataBoundary.localOnly => 'local_only',
        ModelDataBoundary.customerManagedEndpoint =>
          'customer_managed_endpoint',
        ModelDataBoundary.thirdPartyService => 'third_party_service',
      };
}

extension ModelEvidenceLevelWireName on ModelEvidenceLevel {
  String get wireName => switch (this) {
        ModelEvidenceLevel.unknown => 'unknown',
        ModelEvidenceLevel.declared => 'declared',
        ModelEvidenceLevel.measured => 'measured',
      };
}

extension ModelCostKindWireName on ModelCostKind {
  String get wireName => switch (this) {
        ModelCostKind.unknown => 'unknown',
        ModelCostKind.noDirectCharge => 'no_direct_charge',
        ModelCostKind.metered => 'metered',
      };
}

ModelSupportStatus _parseSupportStatus(Object? raw, String path) {
  return switch (raw) {
    'evaluation_only' => ModelSupportStatus.evaluationOnly,
    'approved' => ModelSupportStatus.approved,
    _ => throw ModelRegistryValidationException(
        '$path must be evaluation_only or approved',
      ),
  };
}

ModelDataBoundary _parseDataBoundary(Object? raw, String path) {
  return switch (raw) {
    'local_only' => ModelDataBoundary.localOnly,
    'customer_managed_endpoint' => ModelDataBoundary.customerManagedEndpoint,
    'third_party_service' => ModelDataBoundary.thirdPartyService,
    _ => throw ModelRegistryValidationException(
        '$path has an unsupported data boundary',
      ),
  };
}

ModelEvidenceLevel _parseEvidenceLevel(Object? raw, String path) {
  return switch (raw) {
    'unknown' => ModelEvidenceLevel.unknown,
    'declared' => ModelEvidenceLevel.declared,
    'measured' => ModelEvidenceLevel.measured,
    _ => throw ModelRegistryValidationException(
        '$path has an unsupported evidence level',
      ),
  };
}

ModelCostKind _parseCostKind(Object? raw, String path) {
  return switch (raw) {
    'unknown' => ModelCostKind.unknown,
    'no_direct_charge' => ModelCostKind.noDirectCharge,
    'metered' => ModelCostKind.metered,
    _ => throw ModelRegistryValidationException(
        '$path has an unsupported cost kind',
      ),
  };
}

Map<String, Object?> _objectMap(Object? raw, String path) {
  if (raw is! Map) {
    throw ModelRegistryValidationException('$path must be an object');
  }
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _objectList(Object? raw, String path) {
  if (raw is! List) {
    throw ModelRegistryValidationException('$path must be an array');
  }
  return List<Object?>.from(raw);
}

String _requiredString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw ModelRegistryValidationException('$path.$key must be non-empty');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw ModelRegistryValidationException(
      '$path.$key must be null or non-empty',
    );
  }
  return value.trim();
}

int? _optionalInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw ModelRegistryValidationException('$path.$key must be an integer');
  }
  return value;
}

double? _optionalDouble(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! num) {
    throw ModelRegistryValidationException('$path.$key must be a number');
  }
  return value.toDouble();
}

void _rejectUnknownKeys(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList()
    ..sort();
  if (unknown.isNotEmpty) {
    throw ModelRegistryValidationException(
      '$path contains unsupported fields: ${unknown.join(', ')}',
    );
  }
}

bool _requiredBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw ModelRegistryValidationException('$path.$key must be a boolean');
  }
  return value;
}

List<String> _canonicalIds(
  Iterable<String> values, {
  required String path,
  RegExp? pattern,
}) {
  final result = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty || (pattern != null && !pattern.hasMatch(value))) {
      throw ModelRegistryValidationException('$path contains invalid id $raw');
    }
    if (!result.add(value)) {
      throw ModelRegistryValidationException('$path contains duplicate $value');
    }
  }
  return List<String>.unmodifiable(result.toList()..sort());
}

List<String> _canonicalStrings(
  Iterable<String> values, {
  required String path,
}) {
  final result = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw ModelRegistryValidationException('$path contains an empty value');
    }
    result.add(value);
  }
  return List<String>.unmodifiable(result.toList()..sort());
}

List<String> _stringList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  return _objectList(json[key] ?? const <Object?>[], '$path.$key').map((value) {
    if (value is! String) {
      throw ModelRegistryValidationException(
        '$path.$key must contain only strings',
      );
    }
    return value;
  }).toList(growable: false);
}

void _validateStableId(String value, String path) {
  if (!_stableIdPattern.hasMatch(value)) {
    throw ModelRegistryValidationException('$path has invalid id $value');
  }
}

String? _nonBlankOrNull(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

void _validateDiscoveredIdentity(ModelIdentity identity) {
  if (identity.providerId != identity.providerId.trim() ||
      !_providerIdPattern.hasMatch(identity.providerId)) {
    throw ModelRegistryValidationException(
      'discovered model has invalid provider id ${identity.providerId}',
    );
  }
  if (identity.name != identity.name.trim() ||
      !_modelIdPattern.hasMatch(identity.name)) {
    throw ModelRegistryValidationException(
      'discovered model has invalid model id ${identity.name}',
    );
  }
}

String _identityFingerprint(ModelIdentity identity) {
  final canonical = jsonEncode(<String, Object?>{
    'digest': _nonBlankOrNull(identity.digest),
    'name': identity.name,
    'parameterSize': _nonBlankOrNull(identity.parameterSize),
    'providerId': identity.providerId,
    'quantization': _nonBlankOrNull(identity.quantization),
  });
  return base64UrlEncode(utf8.encode(canonical)).replaceAll('=', '');
}

List<String> _identityMismatches(
  ModelDefinition registered,
  ModelIdentity discovered,
) {
  final mismatches = <String>[];
  if (registered.digest != _nonBlankOrNull(discovered.digest)) {
    mismatches.add('digest');
  }
  if (registered.parameterSize != _nonBlankOrNull(discovered.parameterSize)) {
    mismatches.add('parameterSize');
  }
  if (registered.quantization != _nonBlankOrNull(discovered.quantization)) {
    mismatches.add('quantization');
  }
  return mismatches;
}

/// Token, concurrency, and streaming limits for one exact model identity.
class ModelLimits {
  ModelLimits({
    required this.evidenceLevel,
    this.contextWindowTokens,
    this.maxOutputTokens,
    this.maxConcurrentRequests,
    this.maxToolCallsPerTurn,
    required this.supportsStreaming,
  }) {
    _validate();
  }

  factory ModelLimits.unknown() => ModelLimits(
        evidenceLevel: ModelEvidenceLevel.unknown,
        supportsStreaming: false,
      );

  factory ModelLimits.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'evidenceLevel',
        'contextWindowTokens',
        'maxOutputTokens',
        'maxConcurrentRequests',
        'maxToolCallsPerTurn',
        'supportsStreaming',
      },
      'limits',
    );
    return ModelLimits(
      evidenceLevel: _parseEvidenceLevel(
        json['evidenceLevel'],
        'limits.evidenceLevel',
      ),
      contextWindowTokens: _optionalInt(
        json,
        'contextWindowTokens',
        'limits',
      ),
      maxOutputTokens: _optionalInt(json, 'maxOutputTokens', 'limits'),
      maxConcurrentRequests: _optionalInt(
        json,
        'maxConcurrentRequests',
        'limits',
      ),
      maxToolCallsPerTurn: _optionalInt(
        json,
        'maxToolCallsPerTurn',
        'limits',
      ),
      supportsStreaming: _requiredBool(
        json,
        'supportsStreaming',
        'limits',
      ),
    );
  }

  final ModelEvidenceLevel evidenceLevel;
  final int? contextWindowTokens;
  final int? maxOutputTokens;
  final int? maxConcurrentRequests;
  final int? maxToolCallsPerTurn;
  final bool supportsStreaming;

  bool get isCompleteForApproval =>
      evidenceLevel == ModelEvidenceLevel.measured &&
      contextWindowTokens != null &&
      maxOutputTokens != null &&
      maxConcurrentRequests != null &&
      maxToolCallsPerTurn != null;

  void _validate() {
    final positive = <String, int?>{
      'contextWindowTokens': contextWindowTokens,
      'maxOutputTokens': maxOutputTokens,
      'maxConcurrentRequests': maxConcurrentRequests,
    };
    for (final entry in positive.entries) {
      if (entry.value != null && entry.value! <= 0) {
        throw ModelRegistryValidationException(
          'limits.${entry.key} must be positive when present',
        );
      }
    }
    if (maxToolCallsPerTurn != null && maxToolCallsPerTurn! < 0) {
      throw const ModelRegistryValidationException(
        'limits.maxToolCallsPerTurn must be non-negative when present',
      );
    }
    if (contextWindowTokens != null &&
        maxOutputTokens != null &&
        maxOutputTokens! > contextWindowTokens!) {
      throw const ModelRegistryValidationException(
        'limits.maxOutputTokens cannot exceed contextWindowTokens',
      );
    }
    if (evidenceLevel == ModelEvidenceLevel.unknown &&
        (positive.values.any((value) => value != null) ||
            maxToolCallsPerTurn != null ||
            supportsStreaming)) {
      throw const ModelRegistryValidationException(
        'unknown limits cannot contain measured numeric values',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'evidenceLevel': evidenceLevel.wireName,
        'contextWindowTokens': contextWindowTokens,
        'maxOutputTokens': maxOutputTokens,
        'maxConcurrentRequests': maxConcurrentRequests,
        'maxToolCallsPerTurn': maxToolCallsPerTurn,
        'supportsStreaming': supportsStreaming,
      };
}

/// Tool-call capability profile. This is capability evidence, not permission to
/// invoke a tool; later policy layers remain authoritative for permissions.
class ModelToolProfile {
  ModelToolProfile({
    required this.evidenceLevel,
    required this.supportsToolCalling,
    required this.supportsStructuredOutput,
    required this.supportsParallelToolCalls,
    Iterable<String> supportedToolClasses = const <String>[],
  }) : supportedToolClasses = _canonicalIds(
          supportedToolClasses,
          path: 'toolProfile.supportedToolClasses',
          pattern: _stableIdPattern,
        ) {
    _validate();
  }

  factory ModelToolProfile.unknown() => ModelToolProfile(
        evidenceLevel: ModelEvidenceLevel.unknown,
        supportsToolCalling: false,
        supportsStructuredOutput: false,
        supportsParallelToolCalls: false,
      );

  factory ModelToolProfile.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'evidenceLevel',
        'supportsToolCalling',
        'supportsStructuredOutput',
        'supportsParallelToolCalls',
        'supportedToolClasses',
      },
      'toolProfile',
    );
    return ModelToolProfile(
      evidenceLevel: _parseEvidenceLevel(
        json['evidenceLevel'],
        'toolProfile.evidenceLevel',
      ),
      supportsToolCalling: _requiredBool(
        json,
        'supportsToolCalling',
        'toolProfile',
      ),
      supportsStructuredOutput: _requiredBool(
        json,
        'supportsStructuredOutput',
        'toolProfile',
      ),
      supportsParallelToolCalls: _requiredBool(
        json,
        'supportsParallelToolCalls',
        'toolProfile',
      ),
      supportedToolClasses: _stringList(
        json,
        'supportedToolClasses',
        'toolProfile',
      ),
    );
  }

  final ModelEvidenceLevel evidenceLevel;
  final bool supportsToolCalling;
  final bool supportsStructuredOutput;
  final bool supportsParallelToolCalls;
  final List<String> supportedToolClasses;

  bool get isMeasured => evidenceLevel == ModelEvidenceLevel.measured;

  void _validate() {
    if (!supportsToolCalling &&
        (supportsParallelToolCalls || supportedToolClasses.isNotEmpty)) {
      throw const ModelRegistryValidationException(
        'toolProfile cannot expose tool classes or parallel calls when '
        'tool calling is unsupported',
      );
    }
    if (evidenceLevel == ModelEvidenceLevel.unknown &&
        (supportsToolCalling ||
            supportsStructuredOutput ||
            supportsParallelToolCalls ||
            supportedToolClasses.isNotEmpty)) {
      throw const ModelRegistryValidationException(
        'unknown tool profile cannot claim capabilities',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'evidenceLevel': evidenceLevel.wireName,
        'supportsToolCalling': supportsToolCalling,
        'supportsStructuredOutput': supportsStructuredOutput,
        'supportsParallelToolCalls': supportsParallelToolCalls,
        'supportedToolClasses': supportedToolClasses,
      };
}

/// Direct invocation price metadata. Hardware, energy, and operational costs
/// remain outside P6-001 and are not inferred from no-direct-charge models.
class ModelCostProfile {
  ModelCostProfile({
    required this.kind,
    String? currencyCode,
    this.inputPerMillionTokens,
    this.outputPerMillionTokens,
    this.perRequest,
    required this.estimated,
  }) : currencyCode = currencyCode?.trim() {
    _validate();
  }

  factory ModelCostProfile.unknown() => ModelCostProfile(
        kind: ModelCostKind.unknown,
        estimated: false,
      );

  factory ModelCostProfile.noDirectCharge({bool estimated = false}) =>
      ModelCostProfile(
        kind: ModelCostKind.noDirectCharge,
        estimated: estimated,
      );

  factory ModelCostProfile.metered({
    required String currencyCode,
    double? inputPerMillionTokens,
    double? outputPerMillionTokens,
    double? perRequest,
    bool estimated = false,
  }) =>
      ModelCostProfile(
        kind: ModelCostKind.metered,
        currencyCode: currencyCode,
        inputPerMillionTokens: inputPerMillionTokens,
        outputPerMillionTokens: outputPerMillionTokens,
        perRequest: perRequest,
        estimated: estimated,
      );

  factory ModelCostProfile.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'kind',
        'currencyCode',
        'inputPerMillionTokens',
        'outputPerMillionTokens',
        'perRequest',
        'estimated',
      },
      'cost',
    );
    return ModelCostProfile(
      kind: _parseCostKind(json['kind'], 'cost.kind'),
      currencyCode: _optionalString(json, 'currencyCode', 'cost'),
      inputPerMillionTokens: _optionalDouble(
        json,
        'inputPerMillionTokens',
        'cost',
      ),
      outputPerMillionTokens: _optionalDouble(
        json,
        'outputPerMillionTokens',
        'cost',
      ),
      perRequest: _optionalDouble(json, 'perRequest', 'cost'),
      estimated: _requiredBool(json, 'estimated', 'cost'),
    );
  }

  final ModelCostKind kind;
  final String? currencyCode;
  final double? inputPerMillionTokens;
  final double? outputPerMillionTokens;
  final double? perRequest;
  final bool estimated;

  bool get isKnown => kind != ModelCostKind.unknown;

  void _validate() {
    final prices = <double?>[
      inputPerMillionTokens,
      outputPerMillionTokens,
      perRequest,
    ];
    if (prices
        .any((price) => price != null && (!price.isFinite || price < 0))) {
      throw const ModelRegistryValidationException(
        'cost values must be finite and non-negative',
      );
    }
    switch (kind) {
      case ModelCostKind.unknown:
      case ModelCostKind.noDirectCharge:
        if (currencyCode != null || prices.any((price) => price != null)) {
          throw ModelRegistryValidationException(
            '${kind.wireName} cost cannot contain currency or prices',
          );
        }
        break;
      case ModelCostKind.metered:
        final currency = currencyCode?.trim();
        if (currency == null || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
          throw const ModelRegistryValidationException(
            'metered cost requires a three-letter uppercase currency code',
          );
        }
        if (prices.every((price) => price == null)) {
          throw const ModelRegistryValidationException(
            'metered cost requires at least one price',
          );
        }
        break;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.wireName,
        'currencyCode': currencyCode,
        'inputPerMillionTokens': inputPerMillionTokens,
        'outputPerMillionTokens': outputPerMillionTokens,
        'perRequest': perRequest,
        'estimated': estimated,
      };
}

/// Repository- or harness-backed measurement for one task class.
class ModelBenchmarkEvidence {
  ModelBenchmarkEvidence({
    required this.benchmarkId,
    required this.taskClassId,
    required this.score,
    required this.scoreUnit,
    required this.higherIsBetter,
    required this.sampleCount,
    required DateTime measuredAt,
    required this.evidenceUri,
  }) : measuredAt = measuredAt.toUtc() {
    _validate();
  }

  factory ModelBenchmarkEvidence.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'benchmarkId',
        'taskClassId',
        'score',
        'scoreUnit',
        'higherIsBetter',
        'sampleCount',
        'measuredAt',
        'evidenceUri',
      },
      'benchmark',
    );
    final measuredAtRaw = _requiredString(json, 'measuredAt', 'benchmark');
    final DateTime measuredAt;
    try {
      measuredAt = DateTime.parse(measuredAtRaw);
    } on FormatException {
      throw const ModelRegistryValidationException(
        'benchmark.measuredAt must be an ISO-8601 timestamp',
      );
    }
    if (!measuredAt.isUtc) {
      throw const ModelRegistryValidationException(
        'benchmark.measuredAt must include a UTC offset',
      );
    }
    final score = _optionalDouble(json, 'score', 'benchmark');
    final sampleCount = _optionalInt(json, 'sampleCount', 'benchmark');
    if (score == null || sampleCount == null) {
      throw const ModelRegistryValidationException(
        'benchmark score and sampleCount are required',
      );
    }
    return ModelBenchmarkEvidence(
      benchmarkId: _requiredString(json, 'benchmarkId', 'benchmark'),
      taskClassId: _requiredString(json, 'taskClassId', 'benchmark'),
      score: score,
      scoreUnit: _requiredString(json, 'scoreUnit', 'benchmark'),
      higherIsBetter: _requiredBool(json, 'higherIsBetter', 'benchmark'),
      sampleCount: sampleCount,
      measuredAt: measuredAt,
      evidenceUri: _requiredString(json, 'evidenceUri', 'benchmark'),
    );
  }

  final String benchmarkId;
  final String taskClassId;
  final double score;
  final String scoreUnit;
  final bool higherIsBetter;
  final int sampleCount;
  final DateTime measuredAt;
  final String evidenceUri;

  void _validate() {
    _validateStableId(benchmarkId, 'benchmark.benchmarkId');
    _validateStableId(taskClassId, 'benchmark.taskClassId');
    if (!score.isFinite) {
      throw const ModelRegistryValidationException(
        'benchmark.score must be finite',
      );
    }
    if (scoreUnit.trim().isEmpty) {
      throw const ModelRegistryValidationException(
        'benchmark.scoreUnit must be non-empty',
      );
    }
    if (sampleCount <= 0) {
      throw const ModelRegistryValidationException(
        'benchmark.sampleCount must be positive',
      );
    }
    if (evidenceUri.trim().isEmpty) {
      throw const ModelRegistryValidationException(
        'benchmark.evidenceUri must be non-empty',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'benchmarkId': benchmarkId,
        'taskClassId': taskClassId,
        'score': score,
        'scoreUnit': scoreUnit,
        'higherIsBetter': higherIsBetter,
        'sampleCount': sampleCount,
        'measuredAt': measuredAt.toIso8601String(),
        'evidenceUri': evidenceUri,
      };
}

/// Non-secret metadata describing which vault reference a provider expects.
class CredentialReferenceRequirement {
  CredentialReferenceRequirement({
    required this.referenceId,
    required this.resolver,
    required this.required,
    required this.purpose,
  }) {
    _validateStableId(referenceId, 'credential.referenceId');
    _validateStableId(resolver, 'credential.resolver');
    if (purpose.trim().isEmpty) {
      throw const ModelRegistryValidationException(
        'credential.purpose must be non-empty',
      );
    }
  }

  factory CredentialReferenceRequirement.fromJson(
    Map<String, Object?> json,
  ) {
    _rejectUnknownKeys(
      json,
      const <String>{'referenceId', 'resolver', 'required', 'purpose'},
      'credential',
    );
    return CredentialReferenceRequirement(
      referenceId: _requiredString(json, 'referenceId', 'credential'),
      resolver: _requiredString(json, 'resolver', 'credential'),
      required: _requiredBool(json, 'required', 'credential'),
      purpose: _requiredString(json, 'purpose', 'credential'),
    );
  }

  final String referenceId;
  final String resolver;
  final bool required;
  final String purpose;

  Map<String, Object?> toJson() => <String, Object?>{
        'referenceId': referenceId,
        'resolver': resolver,
        'required': required,
        'purpose': purpose,
      };
}

/// Registered provider instance. A provider ID represents one concrete data
/// boundary; deployments with different boundaries use different provider IDs.
class ModelProviderDescriptor {
  ModelProviderDescriptor({
    required this.providerId,
    required this.displayName,
    required this.dataBoundary,
    Iterable<CredentialReferenceRequirement> credentialRequirements =
        const <CredentialReferenceRequirement>[],
  }) : credentialRequirements =
            List<CredentialReferenceRequirement>.unmodifiable(
          credentialRequirements.toList()
            ..sort(
                (left, right) => left.referenceId.compareTo(right.referenceId)),
        ) {
    if (!_providerIdPattern.hasMatch(providerId)) {
      throw ModelRegistryValidationException(
        'provider.providerId has invalid id $providerId',
      );
    }
    if (displayName.trim().isEmpty) {
      throw const ModelRegistryValidationException(
        'provider.displayName must be non-empty',
      );
    }
    final seen = <String>{};
    for (final requirement in this.credentialRequirements) {
      if (!seen.add(requirement.referenceId)) {
        throw ModelRegistryValidationException(
          'provider $providerId contains duplicate credential reference '
          '${requirement.referenceId}',
        );
      }
    }
  }

  factory ModelProviderDescriptor.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'providerId',
        'displayName',
        'dataBoundary',
        'credentialRequirements',
      },
      'provider',
    );
    return ModelProviderDescriptor(
      providerId: _requiredString(json, 'providerId', 'provider'),
      displayName: _requiredString(json, 'displayName', 'provider'),
      dataBoundary: _parseDataBoundary(
        json['dataBoundary'],
        'provider.dataBoundary',
      ),
      credentialRequirements: _objectList(
        json['credentialRequirements'] ?? const <Object?>[],
        'provider.credentialRequirements',
      ).map(
        (raw) => CredentialReferenceRequirement.fromJson(
          _objectMap(raw, 'provider.credentialRequirements[]'),
        ),
      ),
    );
  }

  final String providerId;
  final String displayName;
  final ModelDataBoundary dataBoundary;
  final List<CredentialReferenceRequirement> credentialRequirements;

  Map<String, Object?> toJson() => <String, Object?>{
        'providerId': providerId,
        'displayName': displayName,
        'dataBoundary': dataBoundary.wireName,
        'credentialRequirements': credentialRequirements
            .map((requirement) => requirement.toJson())
            .toList(growable: false),
      };
}

/// Immutable v2 model record. Evaluation-only records can carry measurements,
/// but only [approved] can expose approved task classes.
class ModelDefinition {
  ModelDefinition._({
    required this.providerId,
    required this.modelId,
    required this.displayName,
    required this.digest,
    required this.parameterSize,
    required this.quantization,
    required this.aliases,
    required this.limits,
    required this.toolProfile,
    required this.dataBoundary,
    required this.cost,
    required this.benchmarks,
    required this.approvedTaskClasses,
    required this.supportStatus,
    required this.evaluationReasons,
  }) {
    _validateIdentity();
  }

  factory ModelDefinition.evaluationOnly({
    required String providerId,
    required String modelId,
    required String displayName,
    String? digest,
    String? parameterSize,
    String? quantization,
    Iterable<String> aliases = const <String>[],
    required ModelLimits limits,
    required ModelToolProfile toolProfile,
    required ModelDataBoundary dataBoundary,
    required ModelCostProfile cost,
    Iterable<ModelBenchmarkEvidence> benchmarks =
        const <ModelBenchmarkEvidence>[],
    Iterable<String> evaluationReasons = const <String>[],
  }) {
    final canonicalReasons = _canonicalStrings(
      evaluationReasons,
      path: 'model.evaluationReasons',
    );
    final reasons = canonicalReasons.isEmpty
        ? const <String>['model has not been approved for any task class']
        : canonicalReasons;
    return ModelDefinition._(
      providerId: providerId,
      modelId: modelId,
      displayName: displayName,
      digest: _nonBlankOrNull(digest),
      parameterSize: _nonBlankOrNull(parameterSize),
      quantization: _nonBlankOrNull(quantization),
      aliases: _canonicalIds(
        aliases,
        path: 'model.aliases',
        pattern: _modelIdPattern,
      ),
      limits: limits,
      toolProfile: toolProfile,
      dataBoundary: dataBoundary,
      cost: cost,
      benchmarks: _canonicalBenchmarks(benchmarks),
      approvedTaskClasses: const <String>[],
      supportStatus: ModelSupportStatus.evaluationOnly,
      evaluationReasons: reasons,
    );
  }

  factory ModelDefinition.approved({
    required String providerId,
    required String modelId,
    required String displayName,
    String? digest,
    String? parameterSize,
    String? quantization,
    Iterable<String> aliases = const <String>[],
    required ModelLimits limits,
    required ModelToolProfile toolProfile,
    required ModelDataBoundary dataBoundary,
    required ModelCostProfile cost,
    required Iterable<ModelBenchmarkEvidence> benchmarks,
    required Iterable<String> approvedTaskClasses,
  }) {
    final canonicalDigest = _nonBlankOrNull(digest);
    final canonicalBenchmarks = _canonicalBenchmarks(benchmarks);
    final canonicalTaskClasses = _canonicalIds(
      approvedTaskClasses,
      path: 'model.approvedTaskClasses',
      pattern: _stableIdPattern,
    );
    final blockers = <String>[];
    if (canonicalDigest == null) {
      blockers.add('artifact digest is required for approval');
    }
    if (!limits.isCompleteForApproval) {
      blockers.add('limits are not measured and complete');
    }
    if (!toolProfile.isMeasured) {
      blockers.add('tool profile is not measured');
    }
    if (limits.isCompleteForApproval && toolProfile.isMeasured) {
      final maxToolCalls = limits.maxToolCallsPerTurn!;
      if (toolProfile.supportsToolCalling && maxToolCalls == 0) {
        blockers.add('tool calling is enabled but the tool-call limit is zero');
      }
      if (!toolProfile.supportsToolCalling && maxToolCalls != 0) {
        blockers.add(
          'tool calling is disabled but the tool-call limit is non-zero',
        );
      }
    }
    if (!cost.isKnown) {
      blockers.add('cost is unknown');
    }
    if (canonicalTaskClasses.isEmpty) {
      blockers.add('approved task classes are empty');
    }
    final measuredTaskClasses =
        canonicalBenchmarks.map((benchmark) => benchmark.taskClassId).toSet();
    for (final taskClassId in canonicalTaskClasses) {
      if (!measuredTaskClasses.contains(taskClassId)) {
        blockers.add('task class $taskClassId has no benchmark evidence');
      }
    }
    if (blockers.isNotEmpty) {
      throw ModelRegistryValidationException(
        'model $providerId::$modelId cannot be approved: '
        '${blockers.join('; ')}',
      );
    }
    return ModelDefinition._(
      providerId: providerId,
      modelId: modelId,
      displayName: displayName,
      digest: canonicalDigest,
      parameterSize: _nonBlankOrNull(parameterSize),
      quantization: _nonBlankOrNull(quantization),
      aliases: _canonicalIds(
        aliases,
        path: 'model.aliases',
        pattern: _modelIdPattern,
      ),
      limits: limits,
      toolProfile: toolProfile,
      dataBoundary: dataBoundary,
      cost: cost,
      benchmarks: canonicalBenchmarks,
      approvedTaskClasses: canonicalTaskClasses,
      supportStatus: ModelSupportStatus.approved,
      evaluationReasons: const <String>[],
    );
  }

  factory ModelDefinition.fromLegacyIdentity(
    ModelIdentity identity, {
    required ModelDataBoundary dataBoundary,
  }) =>
      ModelDefinition.evaluationOnly(
        providerId: identity.providerId,
        modelId: identity.name,
        displayName: identity.name,
        digest: _nonBlankOrNull(identity.digest),
        parameterSize: _nonBlankOrNull(identity.parameterSize),
        quantization: _nonBlankOrNull(identity.quantization),
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: dataBoundary,
        cost: ModelCostProfile.unknown(),
        evaluationReasons: const <String>[
          'discovered model is not present in the approved registry',
          'limits, tool profile, cost, and benchmark evidence are unknown',
        ],
      );

  factory ModelDefinition.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'providerId',
        'modelId',
        'displayName',
        'digest',
        'parameterSize',
        'quantization',
        'aliases',
        'limits',
        'toolProfile',
        'dataBoundary',
        'cost',
        'benchmarks',
        'approvedTaskClasses',
        'supportStatus',
        'evaluationReasons',
      },
      'model',
    );
    final supportStatus = _parseSupportStatus(
      json['supportStatus'],
      'model.supportStatus',
    );
    final benchmarks = _objectList(
      json['benchmarks'] ?? const <Object?>[],
      'model.benchmarks',
    ).map(
      (raw) => ModelBenchmarkEvidence.fromJson(
        _objectMap(raw, 'model.benchmarks[]'),
      ),
    );
    final common = (
      providerId: _requiredString(json, 'providerId', 'model'),
      modelId: _requiredString(json, 'modelId', 'model'),
      displayName: _requiredString(json, 'displayName', 'model'),
      digest: _optionalString(json, 'digest', 'model'),
      parameterSize: _optionalString(json, 'parameterSize', 'model'),
      quantization: _optionalString(json, 'quantization', 'model'),
      aliases: _stringList(json, 'aliases', 'model'),
      limits: ModelLimits.fromJson(
        _objectMap(json['limits'], 'model.limits'),
      ),
      toolProfile: ModelToolProfile.fromJson(
        _objectMap(json['toolProfile'], 'model.toolProfile'),
      ),
      dataBoundary: _parseDataBoundary(
        json['dataBoundary'],
        'model.dataBoundary',
      ),
      cost: ModelCostProfile.fromJson(
        _objectMap(json['cost'], 'model.cost'),
      ),
    );
    final approvedTaskClasses = _stringList(
      json,
      'approvedTaskClasses',
      'model',
    );
    final evaluationReasons = _stringList(
      json,
      'evaluationReasons',
      'model',
    );
    if (supportStatus == ModelSupportStatus.evaluationOnly &&
        approvedTaskClasses.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'evaluation-only JSON cannot contain approved task classes',
      );
    }
    if (supportStatus == ModelSupportStatus.approved &&
        evaluationReasons.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'approved JSON cannot contain evaluation-only reasons',
      );
    }
    return switch (supportStatus) {
      ModelSupportStatus.evaluationOnly => ModelDefinition.evaluationOnly(
          providerId: common.providerId,
          modelId: common.modelId,
          displayName: common.displayName,
          digest: common.digest,
          parameterSize: common.parameterSize,
          quantization: common.quantization,
          aliases: common.aliases,
          limits: common.limits,
          toolProfile: common.toolProfile,
          dataBoundary: common.dataBoundary,
          cost: common.cost,
          benchmarks: benchmarks,
          evaluationReasons: evaluationReasons,
        ),
      ModelSupportStatus.approved => ModelDefinition.approved(
          providerId: common.providerId,
          modelId: common.modelId,
          displayName: common.displayName,
          digest: common.digest,
          parameterSize: common.parameterSize,
          quantization: common.quantization,
          aliases: common.aliases,
          limits: common.limits,
          toolProfile: common.toolProfile,
          dataBoundary: common.dataBoundary,
          cost: common.cost,
          benchmarks: benchmarks,
          approvedTaskClasses: approvedTaskClasses,
        ),
    };
  }

  final String providerId;
  final String modelId;
  final String displayName;
  final String? digest;
  final String? parameterSize;
  final String? quantization;
  final List<String> aliases;
  final ModelLimits limits;
  final ModelToolProfile toolProfile;
  final ModelDataBoundary dataBoundary;
  final ModelCostProfile cost;
  final List<ModelBenchmarkEvidence> benchmarks;
  final List<String> approvedTaskClasses;
  final ModelSupportStatus supportStatus;
  final List<String> evaluationReasons;

  String get registryKey => '$providerId::$modelId';

  bool isApprovedFor(String taskClassId) =>
      supportStatus == ModelSupportStatus.approved &&
      approvedTaskClasses.contains(taskClassId);

  static List<ModelBenchmarkEvidence> _canonicalBenchmarks(
    Iterable<ModelBenchmarkEvidence> values,
  ) {
    final sorted = values.toList()
      ..sort((left, right) {
        final idOrder = left.benchmarkId.compareTo(right.benchmarkId);
        if (idOrder != 0) {
          return idOrder;
        }
        return left.taskClassId.compareTo(right.taskClassId);
      });
    final seen = <String>{};
    for (final benchmark in sorted) {
      final key = '${benchmark.benchmarkId}::${benchmark.taskClassId}';
      if (!seen.add(key)) {
        throw ModelRegistryValidationException(
          'model.benchmarks contains duplicate $key',
        );
      }
    }
    return List<ModelBenchmarkEvidence>.unmodifiable(sorted);
  }

  void _validateIdentity() {
    if (!_providerIdPattern.hasMatch(providerId)) {
      throw ModelRegistryValidationException(
        'model.providerId has invalid id $providerId',
      );
    }
    if (!_modelIdPattern.hasMatch(modelId)) {
      throw ModelRegistryValidationException(
        'model.modelId has invalid id $modelId',
      );
    }
    if (displayName.trim().isEmpty) {
      throw const ModelRegistryValidationException(
        'model.displayName must be non-empty',
      );
    }
    for (final alias in aliases) {
      if (alias == modelId) {
        throw ModelRegistryValidationException(
          'model $registryKey cannot alias its canonical modelId',
        );
      }
    }
    if (supportStatus == ModelSupportStatus.evaluationOnly &&
        approvedTaskClasses.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'evaluation-only model cannot expose approved task classes',
      );
    }
    if (supportStatus == ModelSupportStatus.approved && digest == null) {
      throw const ModelRegistryValidationException(
        'approved model must contain an immutable artifact digest',
      );
    }
    if (supportStatus == ModelSupportStatus.approved &&
        evaluationReasons.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'approved model cannot contain evaluation-only reasons',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'providerId': providerId,
        'modelId': modelId,
        'displayName': displayName,
        'digest': digest,
        'parameterSize': parameterSize,
        'quantization': quantization,
        'aliases': aliases,
        'limits': limits.toJson(),
        'toolProfile': toolProfile.toJson(),
        'dataBoundary': dataBoundary.wireName,
        'cost': cost.toJson(),
        'benchmarks': benchmarks
            .map((benchmark) => benchmark.toJson())
            .toList(growable: false),
        'approvedTaskClasses': approvedTaskClasses,
        'supportStatus': supportStatus.wireName,
        'evaluationReasons': evaluationReasons,
      };
}

/// Deterministic provider/model catalog. Runtime routing is intentionally out
/// of scope; this object only validates identity and approval metadata.
///
/// Discovery is fail-closed in this core class. Direct imports of this file
/// therefore cannot bypass artifact identity validation.
class ModelDefinitionRegistry {
  ModelDefinitionRegistry({
    required Iterable<ModelProviderDescriptor> providers,
    required Iterable<ModelDefinition> models,
  }) {
    final providerMap = <String, ModelProviderDescriptor>{};
    for (final provider in providers) {
      if (providerMap.containsKey(provider.providerId)) {
        throw ModelRegistryValidationException(
          'duplicate provider ${provider.providerId}',
        );
      }
      providerMap[provider.providerId] = provider;
    }

    final modelMap = <String, ModelDefinition>{};
    final aliasMap = <String, ModelDefinition>{};
    for (final model in models) {
      final provider = providerMap[model.providerId];
      if (provider == null) {
        throw ModelRegistryValidationException(
          'model ${model.registryKey} references unknown provider '
          '${model.providerId}',
        );
      }
      if (provider.dataBoundary != model.dataBoundary) {
        throw ModelRegistryValidationException(
          'model ${model.registryKey} data boundary does not match provider',
        );
      }
      if (modelMap.containsKey(model.registryKey)) {
        throw ModelRegistryValidationException(
          'duplicate model ${model.registryKey}',
        );
      }
      modelMap[model.registryKey] = model;
      for (final alias in model.aliases) {
        final aliasKey = '${model.providerId}::$alias';
        if (modelMap.containsKey(aliasKey) || aliasMap.containsKey(aliasKey)) {
          throw ModelRegistryValidationException(
            'duplicate model alias $aliasKey',
          );
        }
        aliasMap[aliasKey] = model;
      }
    }
    for (final modelKey in modelMap.keys) {
      if (aliasMap.containsKey(modelKey)) {
        throw ModelRegistryValidationException(
          'canonical model id collides with alias $modelKey',
        );
      }
    }

    _providers = UnmodifiableMapView<String, ModelProviderDescriptor>(
      SplayTreeMap<String, ModelProviderDescriptor>.from(providerMap),
    );
    _models = UnmodifiableMapView<String, ModelDefinition>(
      SplayTreeMap<String, ModelDefinition>.from(modelMap),
    );
    _aliases = UnmodifiableMapView<String, ModelDefinition>(
      SplayTreeMap<String, ModelDefinition>.from(aliasMap),
    );
  }

  factory ModelDefinitionRegistry.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{'schemaVersion', 'providers', 'models'},
      'registry',
    );
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 2) {
      throw const ModelRegistryValidationException(
        'model registry schemaVersion must be 2',
      );
    }
    return ModelDefinitionRegistry(
      providers: _objectList(json['providers'], 'registry.providers').map(
        (raw) => ModelProviderDescriptor.fromJson(
          _objectMap(raw, 'registry.providers[]'),
        ),
      ),
      models: _objectList(json['models'], 'registry.models').map(
        (raw) => ModelDefinition.fromJson(
          _objectMap(raw, 'registry.models[]'),
        ),
      ),
    );
  }

  late final Map<String, ModelProviderDescriptor> _providers;
  late final Map<String, ModelDefinition> _models;
  late final Map<String, ModelDefinition> _aliases;

  List<ModelProviderDescriptor> get providers =>
      List<ModelProviderDescriptor>.unmodifiable(_providers.values);

  List<ModelDefinition> get models =>
      List<ModelDefinition>.unmodifiable(_models.values);

  ModelProviderDescriptor? provider(String providerId) =>
      _providers[providerId];

  ModelDefinition? lookup(String providerId, String modelIdOrAlias) {
    final key = '$providerId::$modelIdOrAlias';
    return _models[key] ?? _aliases[key];
  }

  /// Reuses a registered record only when its artifact identity still matches.
  /// Any drift is quarantined as a non-persistent evaluation-only descriptor.
  ModelDefinition resolveDiscovered(ModelIdentity identity) {
    _validateDiscoveredIdentity(identity);
    final existing = lookup(identity.providerId, identity.name);
    if (existing != null) {
      final mismatches = _identityMismatches(existing, identity);
      if (mismatches.isEmpty) {
        return existing;
      }
      final quarantineModelId =
          '${identity.name}:identity-mismatch:${_identityFingerprint(identity)}';
      if (lookup(identity.providerId, quarantineModelId) != null) {
        throw ModelRegistryValidationException(
          'discovered model ${identity.exactId} identity quarantine collides '
          'with a registered model',
        );
      }
      return ModelDefinition.evaluationOnly(
        providerId: identity.providerId,
        modelId: quarantineModelId,
        displayName: identity.name,
        digest: _nonBlankOrNull(identity.digest),
        parameterSize: _nonBlankOrNull(identity.parameterSize),
        quantization: _nonBlankOrNull(identity.quantization),
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: existing.dataBoundary,
        cost: ModelCostProfile.unknown(),
        evaluationReasons: <String>[
          'discovered identity does not match registered '
              '${existing.registryKey}: ${mismatches.join(', ')}',
          'approval is blocked until the exact artifact identity is registered '
              'and measured',
        ],
      );
    }

    final provider = _providers[identity.providerId];
    if (provider == null) {
      throw ModelRegistryValidationException(
        'discovered model ${identity.exactId} uses an unknown provider; '
        'its data boundary cannot be inferred safely',
      );
    }
    return ModelDefinition.fromLegacyIdentity(
      identity,
      dataBoundary: provider.dataBoundary,
    );
  }

  ModelDefinition requireApproved({
    required String providerId,
    required String modelIdOrAlias,
    required String taskClassId,
  }) {
    _validateStableId(taskClassId, 'taskClassId');
    final model = lookup(providerId, modelIdOrAlias);
    if (model == null) {
      throw ModelRegistryValidationException(
        'model $providerId::$modelIdOrAlias is not registered',
      );
    }
    if (!model.isApprovedFor(taskClassId)) {
      throw ModelRegistryValidationException(
        'model ${model.registryKey} is not approved for $taskClassId',
      );
    }
    return model;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 2,
        'providers': providers
            .map((provider) => provider.toJson())
            .toList(growable: false),
        'models': models.map((model) => model.toJson()).toList(growable: false),
      };
}
