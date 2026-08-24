import 'generated/protocol_contracts.g.dart';
import 'tool_schema_base.dart' as base;

export 'tool_schema_base.dart' hide ToolSchemaRegistry;

const String _researchSearchName = 'research_search';
const String _researchSearchCompatibilityVersion = '2.0.0';
const String _researchSearchDescription =
    'Search the web through the approved provider router. Built-in search needs no secret; secretReferenceId optionally selects a configured provider.';

Map<String, dynamic> _effectiveResearchSearchJson() {
  final values = generatedToolRegistry['tools'];
  if (values is! List<Object?>) {
    throw StateError('Generated tool registry is malformed.');
  }
  for (final value in values) {
    if (value is! Map || value['name']?.toString() != _researchSearchName) {
      continue;
    }
    final json = Map<String, dynamic>.from(value);
    final compatibilityVersion =
        json['compatibilityVersion']?.toString() ?? json['version']?.toString();
    if (compatibilityVersion != _researchSearchCompatibilityVersion) {
      return json;
    }
    final inputSchema = Map<String, dynamic>.from(
      json['inputSchema'] as Map<dynamic, dynamic>? ??
          const <dynamic, dynamic>{},
    );
    final required = (inputSchema['required'] as List<Object?>? ??
            const <Object?>[])
        .map((item) => item.toString())
        .where((item) => item != 'secretReferenceId')
        .toList(growable: false);
    inputSchema['required'] = required;
    return <String, dynamic>{
      ...json,
      'description': _researchSearchDescription,
      'inputSchema': inputSchema,
      'example': const <String, dynamic>{
        'query': 'official API documentation',
      },
    };
  }
  throw StateError('Generated research_search contract is missing.');
}

/// Runtime compatibility facade for the published tool-registry v2 contract.
///
/// Registry v2 originally made the Brave secret reference mandatory for
/// `research_search`. The hotfix keeps that generated artifact immutable while
/// relaxing only the v2 runtime contract so built-in zero-key search is the
/// baseline and a secret reference is optional provider configuration.
class ToolSchemaRegistry {
  const ToolSchemaRegistry();

  static const base.ToolSchemaRegistry _base = base.ToolSchemaRegistry();
  static final base.ToolContract _researchSearch =
      base.ToolContract.fromJson(_effectiveResearchSearchJson());

  String get version => _base.version;
  String get contractDigest => _base.contractDigest;
  Set<String> get names => _base.names;

  base.ToolContract? find(String name) =>
      name == _researchSearchName ? _researchSearch : _base.find(name);

  base.ToolContract require(String name) {
    final contract = find(name);
    if (contract != null) {
      return contract;
    }
    return _base.require(name);
  }

  base.ToolInputNormalization normalizeAndValidate(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final contract = require(name);
    final normalized = contract.canonicalizeInput(arguments);
    contract.validateInput(normalized.arguments);
    return normalized;
  }

  List<Map<String, dynamic>> descriptors({
    Set<String>? allowlist,
    base.ToolDescriptorDialect dialect = base.ToolDescriptorDialect.canonical,
  }) =>
      names
          .where((name) => allowlist == null || allowlist.contains(name))
          .map((name) => require(name).descriptor(dialect: dialect))
          .toList(growable: false);

  void verifyCoverage(Iterable<String> handlerNames) =>
      _base.verifyCoverage(handlerNames);
}
