import 'dart:collection';
import 'dart:convert';

import '../domain.dart';

final RegExp _providerIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
final RegExp _modelIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/+-]*$');
final RegExp _stableIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
final RegExp _sha256DigestPattern = RegExp(r'^sha256:[0-9a-f]{64}$');
final RegExp _gitObjectIdPattern = RegExp(r'^[0-9a-f]{40}$');

const String _benchmarkEvidenceSchemaVersion = '1.0.0';
const String _benchmarkEvidenceKind = 'MODEL_BENCHMARK_RESULT';
const String _benchmarkEvidenceLocationKind = 'embedded_content_addressed';

class ModelRegistryValidationException implements Exception {
  const ModelRegistryValidationException(this.message);

  final String message;

  @override
  String toString() => 'ModelRegistryValidationException: $message';
}

enum ModelSupportStatus { evaluationOnly, approved }

enum ModelDataBoundary {
  localOnly,
  customerManagedEndpoint,
  thirdPartyService,
}

enum ModelEvidenceLevel { unknown, declared, measured }

enum ModelCostKind { unknown, noDirectCharge, metered }

enum ModelResolutionDisposition { registeredIdentity, evaluationOnly }

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
  return value;
}

String? _optionalString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw ModelRegistryValidationException(
      '$path.$key must be null or non-empty',
    );
  }
  return value;
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

bool _requiredBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) {
    throw ModelRegistryValidationException('$path.$key must be a boolean');
  }
  return value;
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

List<String> _canonicalIds(
  Iterable<String> values, {
  required String path,
  RegExp? pattern,
}) {
  final result = <String>{};
  for (final raw in values) {
    if (raw != raw.trim() ||
        raw.isEmpty ||
        (pattern != null && !pattern.hasMatch(raw))) {
      throw ModelRegistryValidationException('$path contains invalid id $raw');
    }
    if (!result.add(raw)) {
      throw ModelRegistryValidationException('$path contains duplicate $raw');
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
    if (raw != raw.trim() || raw.isEmpty) {
      throw ModelRegistryValidationException('$path contains an empty value');
    }
    result.add(raw);
  }
  return List<String>.unmodifiable(result.toList()..sort());
}

void _validateStableId(String value, String path) {
  if (value != value.trim() || !_stableIdPattern.hasMatch(value)) {
    throw ModelRegistryValidationException('$path has invalid id $value');
  }
}

String? _nonBlankOrNull(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value != value.trim()) {
    throw const ModelRegistryValidationException(
      'identity metadata must not contain surrounding whitespace',
    );
  }
  return value;
}

String? _canonicalSha256OrNull(String? value, String path) {
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value != value.trim() || !_sha256DigestPattern.hasMatch(value)) {
    throw ModelRegistryValidationException(
      '$path must be canonical sha256:<64 lowercase hex>',
    );
  }
  return value;
}

String _canonicalSha256(String value, String path) {
  final canonical = _canonicalSha256OrNull(value, path);
  if (canonical == null) {
    throw ModelRegistryValidationException(
      '$path must be canonical sha256:<64 lowercase hex>',
    );
  }
  return canonical;
}

String _canonicalGitObjectId(String value, String path) {
  if (value != value.trim() || !_gitObjectIdPattern.hasMatch(value)) {
    throw ModelRegistryValidationException(
      '$path must be a 40-character lowercase Git object id',
    );
  }
  return value;
}

Object? _canonicalizeJson(Object? value, String path) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ModelRegistryValidationException('$path contains non-finite number');
    }
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value
          .asMap()
          .entries
          .map((entry) => _canonicalizeJson(entry.value, '$path[${entry.key}]'))
          .toList(growable: false),
    );
  }
  if (value is Map) {
    final keys = value.keys.map((key) {
      if (key is! String) {
        throw ModelRegistryValidationException(
          '$path contains a non-string object key',
        );
      }
      return key;
    }).toList()
      ..sort();
    final result = SplayTreeMap<String, Object?>();
    for (final key in keys) {
      result[key] = _canonicalizeJson(value[key], '$path.$key');
    }
    return result;
  }
  throw ModelRegistryValidationException(
    '$path contains unsupported JSON value ${value.runtimeType}',
  );
}

String _canonicalJson(Map<String, Object?> value, String path) {
  final canonical = _canonicalizeJson(value, path);
  return jsonEncode(canonical);
}

const List<int> _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

int _rotr32(int value, int shift) {
  const mask = 0xffffffff;
  final normalized = value & mask;
  return ((normalized >> shift) | ((normalized << (32 - shift)) & mask)) &
      mask;
}

String _sha256Digest(List<int> input) {
  const mask = 0xffffffff;
  final bytes = <int>[...input];
  final bitLength = input.length * 8;
  bytes.add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  for (var offset = 0; offset < bytes.length; offset += 64) {
    final w = List<int>.filled(64, 0);
    for (var index = 0; index < 16; index++) {
      final base = offset + index * 4;
      w[index] = ((bytes[base] << 24) |
              (bytes[base + 1] << 16) |
              (bytes[base + 2] << 8) |
              bytes[base + 3]) &
          mask;
    }
    for (var index = 16; index < 64; index++) {
      final s0 = _rotr32(w[index - 15], 7) ^
          _rotr32(w[index - 15], 18) ^
          (w[index - 15] >> 3);
      final s1 = _rotr32(w[index - 2], 17) ^
          _rotr32(w[index - 2], 19) ^
          (w[index - 2] >> 10);
      w[index] =
          (w[index - 16] + s0 + w[index - 7] + s1) & mask;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var index = 0; index < 64; index++) {
      final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final ch = (e & f) ^ (((~e) & mask) & g);
      final temp1 = (h + s1 + ch + _sha256K[index] + w[index]) & mask;
      final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & mask;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & mask;
    }

    h0 = (h0 + a) & mask;
    h1 = (h1 + b) & mask;
    h2 = (h2 + c) & mask;
    h3 = (h3 + d) & mask;
    h4 = (h4 + e) & mask;
    h5 = (h5 + f) & mask;
    h6 = (h6 + g) & mask;
    h7 = (h7 + h) & mask;
  }

  final buffer = StringBuffer('sha256:');
  for (final word in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    buffer.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}

DateTime _parseUtcTimestamp(String raw, String path) {
  DateTime value;
  try {
    value = DateTime.parse(raw);
  } on FormatException {
    throw ModelRegistryValidationException(
      '$path must be an ISO-8601 timestamp',
    );
  }
  if (!value.isUtc) {
    throw ModelRegistryValidationException(
      '$path must include a UTC offset',
    );
  }
  return value.toUtc();
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
  _canonicalSha256OrNull(identity.digest, 'discovered.digest');
  _nonBlankOrNull(identity.parameterSize);
  _nonBlankOrNull(identity.quantization);
}

String _identityFingerprint(ModelIdentity identity) {
  final canonical = jsonEncode(<String, Object?>{
    'digest': _canonicalSha256OrNull(identity.digest, 'discovered.digest'),
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
  if (registered.digest !=
      _canonicalSha256OrNull(discovered.digest, 'discovered.digest')) {
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
      contextWindowTokens:
          _optionalInt(json, 'contextWindowTokens', 'limits'),
      maxOutputTokens: _optionalInt(json, 'maxOutputTokens', 'limits'),
      maxConcurrentRequests:
          _optionalInt(json, 'maxConcurrentRequests', 'limits'),
      maxToolCallsPerTurn:
          _optionalInt(json, 'maxToolCallsPerTurn', 'limits'),
      supportsStreaming:
          _requiredBool(json, 'supportsStreaming', 'limits'),
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
      supportsToolCalling:
          _requiredBool(json, 'supportsToolCalling', 'toolProfile'),
      supportsStructuredOutput:
          _requiredBool(json, 'supportsStructuredOutput', 'toolProfile'),
      supportsParallelToolCalls:
          _requiredBool(json, 'supportsParallelToolCalls', 'toolProfile'),
      supportedToolClasses:
          _stringList(json, 'supportedToolClasses', 'toolProfile'),
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
      inputPerMillionTokens:
          _optionalDouble(json, 'inputPerMillionTokens', 'cost'),
      outputPerMillionTokens:
          _optionalDouble(json, 'outputPerMillionTokens', 'cost'),
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
    if (prices.any(
      (price) => price != null && (!price.isFinite || price < 0),
    )) {
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

class ModelBenchmarkEvidence {
  ModelBenchmarkEvidence._({
    required this.benchmarkId,
    required this.taskClassId,
    required this.modelDigest,
    required this.score,
    required this.scoreUnit,
    required this.higherIsBetter,
    required this.sampleCount,
    required this.measuredAt,
    required this.candidateCommit,
    required this.candidateTree,
    required this.evidenceSha256,
    required this.evidencePayloadJson,
  });

  factory ModelBenchmarkEvidence._fromEvidencePayload({
    required Map<String, Object?> payload,
  }) {
    final canonicalPayload =
        _canonicalJson(payload, 'benchmark.evidence.payload');
    final parsed = (jsonDecode(canonicalPayload) as Map)
        .cast<String, Object?>();
    _rejectUnknownKeys(
      parsed,
      const <String>{
        'schemaVersion',
        'kind',
        'candidateCommit',
        'candidateTree',
        'benchmarkId',
        'taskClassId',
        'modelDigest',
        'score',
        'scoreUnit',
        'higherIsBetter',
        'sampleCount',
        'measuredAt',
      },
      'benchmark.evidence.payload',
    );
    if (_requiredString(
          parsed,
          'schemaVersion',
          'benchmark.evidence.payload',
        ) !=
        _benchmarkEvidenceSchemaVersion) {
      throw const ModelRegistryValidationException(
        'benchmark evidence schemaVersion must be 1.0.0',
      );
    }
    if (_requiredString(parsed, 'kind', 'benchmark.evidence.payload') !=
        _benchmarkEvidenceKind) {
      throw const ModelRegistryValidationException(
        'benchmark evidence kind must be MODEL_BENCHMARK_RESULT',
      );
    }
    final benchmarkId = _requiredString(
      parsed,
      'benchmarkId',
      'benchmark.evidence.payload',
    );
    final taskClassId = _requiredString(
      parsed,
      'taskClassId',
      'benchmark.evidence.payload',
    );
    _validateStableId(benchmarkId, 'benchmark.benchmarkId');
    _validateStableId(taskClassId, 'benchmark.taskClassId');
    final modelDigest = _canonicalSha256(
      _requiredString(
        parsed,
        'modelDigest',
        'benchmark.evidence.payload',
      ),
      'benchmark.modelDigest',
    );
    final score = _optionalDouble(
      parsed,
      'score',
      'benchmark.evidence.payload',
    );
    final sampleCount = _optionalInt(
      parsed,
      'sampleCount',
      'benchmark.evidence.payload',
    );
    if (score == null || !score.isFinite) {
      throw const ModelRegistryValidationException(
        'benchmark.score must be finite',
      );
    }
    if (sampleCount == null || sampleCount <= 0) {
      throw const ModelRegistryValidationException(
        'benchmark.sampleCount must be positive',
      );
    }
    final scoreUnit = _requiredString(
      parsed,
      'scoreUnit',
      'benchmark.evidence.payload',
    );
    if (scoreUnit != scoreUnit.trim()) {
      throw const ModelRegistryValidationException(
        'benchmark.scoreUnit must be canonical',
      );
    }
    final measuredAt = _parseUtcTimestamp(
      _requiredString(
        parsed,
        'measuredAt',
        'benchmark.evidence.payload',
      ),
      'benchmark.measuredAt',
    );
    final candidateCommit = _canonicalGitObjectId(
      _requiredString(
        parsed,
        'candidateCommit',
        'benchmark.evidence.payload',
      ),
      'benchmark.candidateCommit',
    );
    final candidateTree = _canonicalGitObjectId(
      _requiredString(
        parsed,
        'candidateTree',
        'benchmark.evidence.payload',
      ),
      'benchmark.candidateTree',
    );
    return ModelBenchmarkEvidence._(
      benchmarkId: benchmarkId,
      taskClassId: taskClassId,
      modelDigest: modelDigest,
      score: score,
      scoreUnit: scoreUnit,
      higherIsBetter: _requiredBool(
        parsed,
        'higherIsBetter',
        'benchmark.evidence.payload',
      ),
      sampleCount: sampleCount,
      measuredAt: measuredAt,
      candidateCommit: candidateCommit,
      candidateTree: candidateTree,
      evidenceSha256: _sha256Digest(utf8.encode(canonicalPayload)),
      evidencePayloadJson: canonicalPayload,
    );
  }

  factory ModelBenchmarkEvidence.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(
      json,
      const <String>{
        'benchmarkId',
        'taskClassId',
        'modelDigest',
        'score',
        'scoreUnit',
        'higherIsBetter',
        'sampleCount',
        'measuredAt',
        'evidence',
      },
      'benchmark',
    );
    final evidence = _objectMap(json['evidence'], 'benchmark.evidence');
    _rejectUnknownKeys(
      evidence,
      const <String>{
        'locationKind',
        'sha256',
        'payload',
      },
      'benchmark.evidence',
    );
    if (_requiredString(
          evidence,
          'locationKind',
          'benchmark.evidence',
        ) !=
        _benchmarkEvidenceLocationKind) {
      throw const ModelRegistryValidationException(
        'benchmark.evidence.locationKind must be embedded_content_addressed',
      );
    }
    final expectedSha = _canonicalSha256(
      _requiredString(evidence, 'sha256', 'benchmark.evidence'),
      'benchmark.evidence.sha256',
    );
    final payload =
        _objectMap(evidence['payload'], 'benchmark.evidence.payload');
    final verified =
        ModelBenchmarkEvidence._fromEvidencePayload(payload: payload);
    if (verified.evidenceSha256 != expectedSha) {
      throw ModelRegistryValidationException(
        'benchmark evidence digest mismatch: expected $expectedSha, '
        'computed ${verified.evidenceSha256}',
      );
    }

    final measuredAt = _parseUtcTimestamp(
      _requiredString(json, 'measuredAt', 'benchmark'),
      'benchmark.measuredAt',
    );
    final score = _optionalDouble(json, 'score', 'benchmark');
    final sampleCount = _optionalInt(json, 'sampleCount', 'benchmark');
    final topLevelMatches =
        _requiredString(json, 'benchmarkId', 'benchmark') ==
            verified.benchmarkId &&
        _requiredString(json, 'taskClassId', 'benchmark') ==
            verified.taskClassId &&
        _requiredString(json, 'modelDigest', 'benchmark') ==
            verified.modelDigest &&
        score == verified.score &&
        _requiredString(json, 'scoreUnit', 'benchmark') ==
            verified.scoreUnit &&
        _requiredBool(json, 'higherIsBetter', 'benchmark') ==
            verified.higherIsBetter &&
        sampleCount == verified.sampleCount &&
        measuredAt == verified.measuredAt;
    if (!topLevelMatches) {
      throw const ModelRegistryValidationException(
        'benchmark metadata does not match immutable evidence payload',
      );
    }
    return verified;
  }

  final String benchmarkId;
  final String taskClassId;
  final String modelDigest;
  final double score;
  final String scoreUnit;
  final bool higherIsBetter;
  final int sampleCount;
  final DateTime measuredAt;
  final String candidateCommit;
  final String candidateTree;
  final String evidenceSha256;
  final String evidencePayloadJson;

  String get evidenceLocationKind => _benchmarkEvidenceLocationKind;

  Map<String, Object?> toJson() => <String, Object?>{
        'benchmarkId': benchmarkId,
        'taskClassId': taskClassId,
        'modelDigest': modelDigest,
        'score': score,
        'scoreUnit': scoreUnit,
        'higherIsBetter': higherIsBetter,
        'sampleCount': sampleCount,
        'measuredAt': measuredAt.toIso8601String(),
        'evidence': <String, Object?>{
          'locationKind': _benchmarkEvidenceLocationKind,
          'sha256': evidenceSha256,
          'payload': jsonDecode(evidencePayloadJson),
        },
      };
}

class CredentialReferenceRequirement {
  CredentialReferenceRequirement({
    required this.referenceId,
    required this.resolver,
    required this.required,
    required this.purpose,
  }) {
    _validateStableId(referenceId, 'credential.referenceId');
    _validateStableId(resolver, 'credential.resolver');
    if (purpose != purpose.trim() || purpose.isEmpty) {
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
              (left, right) =>
                  left.referenceId.compareTo(right.referenceId),
            ),
        ) {
    if (providerId != providerId.trim() ||
        !_providerIdPattern.hasMatch(providerId)) {
      throw ModelRegistryValidationException(
        'provider.providerId has invalid id $providerId',
      );
    }
    if (displayName != displayName.trim() || displayName.isEmpty) {
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
      dataBoundary:
          _parseDataBoundary(json['dataBoundary'], 'provider.dataBoundary'),
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
    required List<String> approvedTaskClasses,
    required ModelSupportStatus supportStatus,
    required this.evaluationReasons,
  })  : _approvedTaskClasses = approvedTaskClasses,
        _supportStatus = supportStatus {
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
    final canonicalDigest =
        _canonicalSha256OrNull(digest, 'model.digest');
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
    final blockers = <String>[];
    String? canonicalDigest;
    try {
      canonicalDigest = _canonicalSha256OrNull(digest, 'model.digest');
    } on ModelRegistryValidationException catch (error) {
      blockers.add(error.message);
    }
    final canonicalBenchmarks = _canonicalBenchmarks(benchmarks);
    final canonicalTaskClasses = _canonicalIds(
      approvedTaskClasses,
      path: 'model.approvedTaskClasses',
      pattern: _stableIdPattern,
    );
    if (canonicalDigest == null) {
      blockers.add('artifact digest is required for approval');
    }
    if (canonicalDigest != null) {
      for (final benchmark in canonicalBenchmarks) {
        if (benchmark.modelDigest != canonicalDigest) {
          blockers.add(
            'benchmark ${benchmark.benchmarkId}::${benchmark.taskClassId} '
            'belongs to artifact ${benchmark.modelDigest}, expected '
            '$canonicalDigest',
          );
        }
      }
    }
    if (canonicalBenchmarks.isNotEmpty) {
      final candidateCommits =
          canonicalBenchmarks.map((item) => item.candidateCommit).toSet();
      final candidateTrees =
          canonicalBenchmarks.map((item) => item.candidateTree).toSet();
      if (candidateCommits.length != 1 || candidateTrees.length != 1) {
        blockers.add(
          'benchmark evidence must bind one exact candidate commit/tree',
        );
      }
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
        blockers.add(
          'tool calling is enabled but the tool-call limit is zero',
        );
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
        blockers.add(
          'task class $taskClassId has no immutable benchmark evidence',
        );
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
        digest: _canonicalSha256OrNull(
          identity.digest,
          'discovered.digest',
        ),
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
    final supportStatus =
        _parseSupportStatus(json['supportStatus'], 'model.supportStatus');
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
      dataBoundary:
          _parseDataBoundary(json['dataBoundary'], 'model.dataBoundary'),
      cost: ModelCostProfile.fromJson(
        _objectMap(json['cost'], 'model.cost'),
      ),
    );
    final approvedTaskClasses =
        _stringList(json, 'approvedTaskClasses', 'model');
    final evaluationReasons =
        _stringList(json, 'evaluationReasons', 'model');
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
  final List<String> evaluationReasons;
  final List<String> _approvedTaskClasses;
  final ModelSupportStatus _supportStatus;

  String get registryKey => '$providerId::$modelId';

  bool _isApprovedFor(String taskClassId) =>
      _supportStatus == ModelSupportStatus.approved &&
      _approvedTaskClasses.contains(taskClassId);

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
    if (providerId != providerId.trim() ||
        !_providerIdPattern.hasMatch(providerId)) {
      throw ModelRegistryValidationException(
        'model.providerId has invalid id $providerId',
      );
    }
    if (modelId != modelId.trim() || !_modelIdPattern.hasMatch(modelId)) {
      throw ModelRegistryValidationException(
        'model.modelId has invalid id $modelId',
      );
    }
    if (displayName != displayName.trim() || displayName.isEmpty) {
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
    if (benchmarks.isNotEmpty && digest == null) {
      throw const ModelRegistryValidationException(
        'model with benchmark evidence must contain an immutable artifact digest',
      );
    }
    for (final benchmark in benchmarks) {
      if (benchmark.modelDigest != digest) {
        throw ModelRegistryValidationException(
          'model $registryKey benchmark ${benchmark.benchmarkId}::'
          '${benchmark.taskClassId} belongs to artifact '
          '${benchmark.modelDigest}, expected $digest',
        );
      }
    }
    if (_supportStatus == ModelSupportStatus.evaluationOnly &&
        _approvedTaskClasses.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'evaluation-only model cannot expose approved task classes',
      );
    }
    if (_supportStatus == ModelSupportStatus.approved && digest == null) {
      throw const ModelRegistryValidationException(
        'approved model must contain an immutable artifact digest',
      );
    }
    if (_supportStatus == ModelSupportStatus.approved &&
        evaluationReasons.isNotEmpty) {
      throw const ModelRegistryValidationException(
        'approved model cannot contain evaluation-only reasons',
      );
    }
  }


}

class ModelRegistryMetadata {
  ModelRegistryMetadata._(ModelDefinition definition)
      : providerId = definition.providerId,
        modelId = definition.modelId,
        displayName = definition.displayName,
        digest = definition.digest,
        parameterSize = definition.parameterSize,
        quantization = definition.quantization,
        aliases = definition.aliases,
        limits = definition.limits,
        toolProfile = definition.toolProfile,
        dataBoundary = definition.dataBoundary,
        cost = definition.cost,
        benchmarks = definition.benchmarks;

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

  String get registryKey => '$providerId::$modelId';

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
        'benchmarks': benchmarks.map((item) => item.toJson()).toList(),
      };
}

class ResolvedModel {
  ResolvedModel._({
    required this.model,
    required this.disposition,
    required this.evaluationReasons,
  });

  final ModelRegistryMetadata model;
  final ModelResolutionDisposition disposition;
  final List<String> evaluationReasons;

  bool get isEvaluationOnly =>
      disposition == ModelResolutionDisposition.evaluationOnly;
}

class ApprovedModelHandle {
  ApprovedModelHandle._({
    required this.model,
    required this.identity,
    required this.taskClassId,
  });

  final ModelRegistryMetadata model;
  final ModelIdentity identity;
  final String taskClassId;
}

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
    if (json['schemaVersion'] != 2) {
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

  List<ModelRegistryMetadata> get models =>
      List<ModelRegistryMetadata>.unmodifiable(
        _models.values.map(ModelRegistryMetadata._),
      );

  ModelProviderDescriptor? provider(String providerId) =>
      _providers[providerId];

  ModelDefinition? _lookupDefinition(
    String providerId,
    String modelIdOrAlias,
  ) {
    final key = '$providerId::$modelIdOrAlias';
    return _models[key] ?? _aliases[key];
  }

  /// Metadata lookup is non-authoritative. It intentionally omits approval
  /// status, approved task classes, and approval predicates.
  ModelRegistryMetadata? lookup(
    String providerId,
    String modelIdOrAlias,
  ) {
    final definition = _lookupDefinition(providerId, modelIdOrAlias);
    return definition == null ? null : ModelRegistryMetadata._(definition);
  }

  ModelDefinition _resolveDiscoveredDefinition(ModelIdentity identity) {
    _validateDiscoveredIdentity(identity);
    final existing =
        _lookupDefinition(identity.providerId, identity.name);
    if (existing != null) {
      final mismatches = _identityMismatches(existing, identity);
      if (mismatches.isEmpty) {
        return existing;
      }
      final quarantineModelId =
          '${identity.name}:identity-mismatch:${_identityFingerprint(identity)}';
      if (_lookupDefinition(identity.providerId, quarantineModelId) != null) {
        throw ModelRegistryValidationException(
          'discovered model ${identity.exactId} identity quarantine collides '
          'with a registered model',
        );
      }
      return ModelDefinition.evaluationOnly(
        providerId: identity.providerId,
        modelId: quarantineModelId,
        displayName: identity.name,
        digest: _canonicalSha256OrNull(
          identity.digest,
          'discovered.digest',
        ),
        parameterSize: _nonBlankOrNull(identity.parameterSize),
        quantization: _nonBlankOrNull(identity.quantization),
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: existing.dataBoundary,
        cost: ModelCostProfile.unknown(),
        evaluationReasons: <String>[
          'discovered identity does not match registered '
              '${existing.registryKey}: ${mismatches.join(', ')}',
          'approval is blocked until the exact artifact identity is '
              'registered and measured',
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

  ResolvedModel resolveDiscovered(ModelIdentity identity) {
    final definition = _resolveDiscoveredDefinition(identity);
    return ResolvedModel._(
      model: ModelRegistryMetadata._(definition),
      disposition: definition._supportStatus == ModelSupportStatus.evaluationOnly
          ? ModelResolutionDisposition.evaluationOnly
          : ModelResolutionDisposition.registeredIdentity,
      evaluationReasons: List<String>.unmodifiable(definition.evaluationReasons),
    );
  }

  /// The only authorization-capable registry API. Metadata lookup and
  /// serialization never return an approval decision.
  ApprovedModelHandle requireApproved({
    required ModelIdentity identity,
    required String taskClassId,
  }) {
    _validateStableId(taskClassId, 'taskClassId');
    final model = _resolveDiscoveredDefinition(identity);
    if (!model._isApprovedFor(taskClassId)) {
      throw ModelRegistryValidationException(
        'model ${model.registryKey} is not approved for $taskClassId',
      );
    }
    return ApprovedModelHandle._(
      model: ModelRegistryMetadata._(model),
      identity: identity,
      taskClassId: taskClassId,
    );
  }

  /// Non-authoritative runtime metadata only. Approval policy is deliberately
  /// not serializable through the runtime registry API.
  Map<String, Object?> toMetadataJson() => <String, Object?>{
        'schemaVersion': 2,
        'providers':
            providers.map((provider) => provider.toJson()).toList(),
        'models': models.map((model) => model.toJson()).toList(),
      };
}
