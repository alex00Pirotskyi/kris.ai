import 'dart:collection';
import 'dart:convert';

class CapabilityGrantValidationException implements Exception {
  CapabilityGrantValidationException(this.message);
  final String message;
  @override
  String toString() => 'CapabilityGrantValidationException: $message';
}

class CapabilityGrantV2 {
  CapabilityGrantV2._(this._json);

  final Map<String, dynamic> _json;

  factory CapabilityGrantV2.fromJson(Map<String, dynamic> input) {
    final copied = _deepCopy(input);
    _validate(copied);
    return CapabilityGrantV2._(copied);
  }

  String get grantId => _json['grantId'] as String;
  Map<String, dynamic> get binding =>
      Map<String, dynamic>.unmodifiable(_map(_json['binding'], 'binding'));
  Map<String, dynamic> get validity =>
      Map<String, dynamic>.unmodifiable(_map(_json['validity'], 'validity'));
  bool get requiresWorkerAuthentication => true;

  Map<String, dynamic> toJson() => _deepCopy(_json);

  String canonicalSigningPayload() {
    final value = toJson();
    final auth = _map(value['auth'], 'auth');
    auth.remove('mac');
    value['auth'] = auth;
    return jsonEncode(_sort(value));
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  static Map<String, dynamic> _map(dynamic value, String field) {
    if (value is! Map) {
      throw CapabilityGrantValidationException('$field must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _string(dynamic value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw CapabilityGrantValidationException('$field must be non-empty');
    }
    return value.trim();
  }

  static void _validate(Map<String, dynamic> value) {
    const required = <String>{
      'schemaVersion',
      'grantId',
      'issuer',
      'binding',
      'scope',
      'budgets',
      'validity',
      'nonce',
      'auth',
    };
    if (value.keys.toSet().difference(required).isNotEmpty ||
        required.difference(value.keys.toSet()).isNotEmpty) {
      throw CapabilityGrantValidationException('grant fields are not exact');
    }
    if (value['schemaVersion'] != '2.0.0') {
      throw CapabilityGrantValidationException('unsupported schemaVersion');
    }
    _string(value['grantId'], 'grantId');
    _string(value['nonce'], 'nonce');
    final issuer = _map(value['issuer'], 'issuer');
    if (issuer['actorId'] != 'desktop_host' ||
        issuer['authority'] != 'desktop_host:deterministic_policy') {
      throw CapabilityGrantValidationException(
          'issuer is not policy authority');
    }
    final binding = _map(value['binding'], 'binding');
    for (final field in const <String>{
      'runId',
      'taskId',
      'actorId',
      'toolId',
      'accessProfileId'
    }) {
      _string(binding[field], 'binding.$field');
    }
    final scope = _map(value['scope'], 'scope');
    for (final field in const <String>{
      'paths',
      'process',
      'network',
      'browser',
      'secrets'
    }) {
      _map(scope[field], 'scope.$field');
    }
    if (_map(scope['secrets'], 'scope.secrets')['rawReveal'] != false) {
      throw CapabilityGrantValidationException(
          'raw secret reveal is forbidden');
    }
    final validity = _map(value['validity'], 'validity');
    for (final field in const <String>{'issuedAt', 'notBefore', 'expiresAt'}) {
      final parsed =
          DateTime.tryParse(_string(validity[field], 'validity.$field'));
      if (parsed == null || !parsed.isUtc) {
        throw CapabilityGrantValidationException('validity.$field must be UTC');
      }
    }
    final maxUses = validity['maxUses'];
    if (maxUses is! int || maxUses < 1) {
      throw CapabilityGrantValidationException('maxUses must be positive');
    }
    final auth = _map(value['auth'], 'auth');
    if (auth['algorithm'] != 'hmac-sha256') {
      throw CapabilityGrantValidationException('unsupported auth algorithm');
    }
    _string(auth['keyId'], 'auth.keyId');
    final mac = _string(auth['mac'], 'auth.mac');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(mac)) {
      throw CapabilityGrantValidationException('auth.mac is invalid');
    }
    _rejectEmbeddedKeyMaterial(value);
  }

  static void _rejectEmbeddedKeyMaterial(dynamic value) {
    const forbidden = <String>{
      'keyMaterial',
      'secretValue',
      'rawSecret',
      'privateKey',
      'signingKey'
    };
    if (value is Map) {
      for (final entry in value.entries) {
        if (forbidden.contains(entry.key)) {
          throw CapabilityGrantValidationException('embedded key material');
        }
        _rejectEmbeddedKeyMaterial(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        _rejectEmbeddedKeyMaterial(item);
      }
    }
  }

  static dynamic _sort(dynamic value) {
    if (value is Map) {
      final result = SplayTreeMap<String, dynamic>();
      for (final entry in value.entries) {
        result[entry.key.toString()] = _sort(entry.value);
      }
      return result;
    }
    if (value is List) {
      return value.map<dynamic>(_sort).toList(growable: false);
    }
    return value;
  }
}
