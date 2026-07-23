import 'dart:convert';

import 'domain.dart';
import 'generated/protocol_contracts.g.dart';
import 'protocol_types.dart';
import 'storage_security.dart';

enum ToolRisk { read, mutation, destructive, process, network, external }

enum ToolIdempotency {
  normalizedArguments,
  contentHash,
  projectSnapshot,
  operationKey,
  requestHash,
}

enum ToolDescriptorDialect { canonical, model, openAiCompatible, mcp }

enum ToolSchemaPhase { input, output }

class ToolCompatibilityChange {
  const ToolCompatibilityChange({
    required this.kind,
    required this.target,
    this.source,
  });

  final String kind;
  final String target;
  final String? source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'target': target,
        if (source != null) 'source': source,
      };
}

class ToolInputNormalization {
  const ToolInputNormalization({
    required this.arguments,
    required this.changes,
  });

  final Map<String, dynamic> arguments;
  final List<ToolCompatibilityChange> changes;

  bool get changed => changes.isNotEmpty;
}

class ToolSchemaException extends ProductException {
  ToolSchemaException({
    required String code,
    required String message,
    required this.tool,
    required this.phase,
    required this.retryability,
    required this.issues,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) : super(
          code,
          message,
          details: <String, dynamic>{
            ...details,
            'tool': tool,
            'schemaPhase': phase.name,
            'retryability': retryability.wireName,
            'issues': issues.map((issue) => issue.toJson()).toList(),
          },
        );

  final String tool;
  final ToolSchemaPhase phase;
  final Retryability retryability;
  final List<SchemaIssue> issues;
}

class ToolContract {
  ToolContract._({
    required this.name,
    required this.version,
    required this.description,
    required this.permission,
    required this.risk,
    required this.idempotency,
    required this.dataBoundary,
    required this.compatibilityVersion,
    required this.inputSchema,
    required this.outputSchema,
    required this.example,
    required this.aliases,
  });

  factory ToolContract.fromJson(Map<String, dynamic> json) {
    return ToolContract._(
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      permission: _permission(json['permission']?.toString() ?? ''),
      risk: _risk(json['risk']?.toString() ?? ''),
      idempotency: _idempotency(json['idempotency']?.toString() ?? ''),
      dataBoundary: json['dataBoundary']?.toString() ?? 'project-local',
      compatibilityVersion:
          json['compatibilityVersion']?.toString() ?? '1.0.0',
      inputSchema: _map(json['inputSchema']),
      outputSchema: _map(json['outputSchema']),
      example: _map(json['example']),
      aliases: <String, List<String>>{
        for (final entry in _map(json['aliases']).entries)
          entry.key: _strings(entry.value),
      },
    );
  }

  final String name;
  final String version;
  final String description;
  final PermissionScope permission;
  final ToolRisk risk;
  final ToolIdempotency idempotency;
  final String dataBoundary;
  final String compatibilityVersion;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic> outputSchema;
  final Map<String, dynamic> example;
  final Map<String, List<String>> aliases;

  bool get isMutating =>
      risk == ToolRisk.mutation || risk == ToolRisk.destructive;

  List<String> get requiredArguments =>
      _strings(inputSchema['required']);

  List<String> get optionalArguments {
    final properties = _map(inputSchema['properties']).keys.toSet();
    properties.removeAll(requiredArguments);
    final values = properties.toList()..sort();
    return values;
  }

  ToolInputNormalization canonicalizeInput(Map<String, dynamic> raw) {
    final arguments = Map<String, dynamic>.from(raw);
    final changes = <ToolCompatibilityChange>[];

    for (final entry in aliases.entries) {
      final target = entry.key;
      for (final alias in entry.value) {
        if (!arguments.containsKey(alias)) {
          continue;
        }
        final aliasValue = arguments[alias];
        if (arguments.containsKey(target)) {
          if (!_jsonEquivalent(arguments[target], aliasValue)) {
            throw ToolSchemaException(
              code: 'argument_alias_conflict',
              message:
                  'Arguments "$target" and its compatibility alias "$alias" disagree.',
              tool: name,
              phase: ToolSchemaPhase.input,
              retryability: Retryability.modelCorrection,
              issues: <SchemaIssue>[
                SchemaIssue(
                  path: r'$.arguments.' + target,
                  keyword: 'aliasConflict',
                  message: 'Canonical and compatibility arguments disagree.',
                  expected: target,
                  actualType: _typeName(aliasValue),
                ),
              ],
              details: <String, dynamic>{
                'argument': target,
                'alias': alias,
              },
            );
          }
          arguments.remove(alias);
          changes.add(
            ToolCompatibilityChange(
              kind: 'duplicate_alias_removed',
              source: alias,
              target: target,
            ),
          );
          continue;
        }
        arguments[target] = aliasValue;
        arguments.remove(alias);
        changes.add(
          ToolCompatibilityChange(
            kind: 'alias_promoted',
            source: alias,
            target: target,
          ),
        );
      }
    }

    final properties = _map(inputSchema['properties']);
    for (final entry in properties.entries) {
      final property = _map(entry.value);
      if (!arguments.containsKey(entry.key) && property.containsKey('default')) {
        arguments[entry.key] = _cloneJson(property['default']);
        changes.add(
          ToolCompatibilityChange(
            kind: 'safe_default_applied',
            target: entry.key,
          ),
        );
      }
    }

    for (final entry in properties.entries) {
      if (!arguments.containsKey(entry.key)) {
        continue;
      }
      final schema = _map(entry.value);
      final value = arguments[entry.key];
      final expected = schema['type'];
      if (expected == 'integer' && value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          arguments[entry.key] = parsed;
          changes.add(
            ToolCompatibilityChange(
              kind: 'integer_string_normalized',
              target: entry.key,
            ),
          );
        }
      } else if (expected == 'boolean' && value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == 'false') {
          arguments[entry.key] = normalized == 'true';
          changes.add(
            ToolCompatibilityChange(
              kind: 'boolean_string_normalized',
              target: entry.key,
            ),
          );
        }
      }
    }

    return ToolInputNormalization(
      arguments: Map<String, dynamic>.unmodifiable(arguments),
      changes: List<ToolCompatibilityChange>.unmodifiable(changes),
    );
  }

  Map<String, dynamic> validateInput(Map<String, dynamic> arguments) {
    final issues = JsonSchemaValidator.validate(arguments, inputSchema);
    if (issues.isNotEmpty) {
      throw _inputException(issues);
    }
    return arguments;
  }

  void validateOutput(Map<String, dynamic> output) {
    final issues = JsonSchemaValidator.validate(output, outputSchema);
    if (issues.isNotEmpty) {
      throw ToolSchemaException(
        code: 'tool_output_invalid',
        message:
            'Tool $name returned data that does not satisfy output schema $version.',
        tool: name,
        phase: ToolSchemaPhase.output,
        retryability: Retryability.never,
        issues: issues,
        details: <String, dynamic>{
          'schemaVersion': version,
          'contractDigest': generatedProtocolContractDigest,
        },
      );
    }
  }

  ToolSchemaException _inputException(List<SchemaIssue> issues) {
    final first = issues.first;
    final argument = _topLevelArgument(first.path);
    final code = switch (first.keyword) {
      'required' => 'argument_required',
      'type' => 'argument_type_invalid',
      'additionalProperties' => 'argument_unknown',
      'format' => 'argument_format_invalid',
      'pattern' => 'argument_format_invalid',
      _ => 'argument_value_invalid',
    };
    final message = switch (code) {
      'argument_required' => 'Argument "$argument" is required.',
      'argument_type_invalid' =>
        'Argument "$argument" has the wrong JSON type.',
      'argument_unknown' =>
        'Tool $name received an argument that is not defined by its schema.',
      'argument_format_invalid' =>
        'Argument "$argument" does not satisfy its required format.',
      _ => 'Tool $name received an invalid argument value.',
    };
    return ToolSchemaException(
      code: code,
      message: message,
      tool: name,
      phase: ToolSchemaPhase.input,
      retryability: Retryability.modelCorrection,
      issues: issues,
      details: <String, dynamic>{
        if (argument.isNotEmpty) 'argument': argument,
        'schemaVersion': version,
        'contractDigest': generatedProtocolContractDigest,
        'repairExample': repairExample(),
      },
    );
  }

  Map<String, dynamic> repairExample() => <String, dynamic>{
        'action': 'tool',
        'tool': name,
        'arguments': _cloneJson(example),
      };

  String repairMessage(Iterable<SchemaIssue> issues) {
    final first = issues.firstOrNull;
    final issue = first == null ? '' : ' ${first.message}';
    return 'Retry one JSON tool decision using schema version $version.$issue '
        'Use exactly this shape: ${jsonEncode(repairExample())}';
  }

  Map<String, dynamic> descriptor({
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) {
    if (dialect == ToolDescriptorDialect.model) {
      return <String, dynamic>{
        'name': name,
        'version': version,
        'description': description,
        'permission': permission.name,
        'risk': risk.name,
        'inputSchema': inputSchema,
        'argumentSchema': <String, dynamic>{
          'required': requiredArguments,
          'optional': optionalArguments,
          'example': example,
        },
      };
    }
    if (dialect == ToolDescriptorDialect.openAiCompatible) {
      return <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{
          'name': name,
          'description': description,
          'parameters': inputSchema,
          'strict': true,
        },
      };
    }
    if (dialect == ToolDescriptorDialect.mcp) {
      return <String, dynamic>{
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'outputSchema': outputSchema,
        'annotations': <String, dynamic>{
          'permission': permission.name,
          'risk': risk.name,
          'idempotency': _idempotencyWireName(idempotency),
          'dataBoundary': dataBoundary,
        },
      };
    }
    return <String, dynamic>{
      'name': name,
      'version': version,
      'description': description,
      'permission': permission.name,
      'risk': risk.name,
      'idempotency': _idempotencyWireName(idempotency),
      'dataBoundary': dataBoundary,
      'compatibilityVersion': compatibilityVersion,
      'inputSchema': inputSchema,
      'outputSchema': outputSchema,
      'argumentSchema': <String, dynamic>{
        'required': requiredArguments,
        'optional': optionalArguments,
        'example': example,
      },
      'repairExample': repairExample(),
      'contractDigest': generatedProtocolContractDigest,
    };
  }
}

class ToolSchemaRegistry {
  const ToolSchemaRegistry();

  static final Map<String, ToolContract> _contracts =
      <String, ToolContract>{
    for (final value in generatedToolRegistry['tools'] as List<Object?>)
      if (value is Map)
        value['name'].toString(): ToolContract.fromJson(
          Map<String, dynamic>.from(value),
        ),
  };

  String get version => generatedToolRegistryVersion;
  String get contractDigest => generatedProtocolContractDigest;

  Set<String> get names => Set<String>.unmodifiable(_contracts.keys);

  ToolContract? find(String name) => _contracts[name];

  ToolContract require(String name) {
    final contract = find(name);
    if (contract == null) {
      throw ToolSchemaException(
        code: 'tool_unknown',
        message: 'Unknown tool: $name',
        tool: name,
        phase: ToolSchemaPhase.input,
        retryability: Retryability.never,
        issues: <SchemaIssue>[
          SchemaIssue(
            path: r'$.tool',
            keyword: 'enum',
            message: 'The tool name is not registered.',
            expected: names.toList()..sort(),
            actualType: 'string',
          ),
        ],
        details: <String, dynamic>{
          'registryVersion': version,
          'contractDigest': contractDigest,
        },
      );
    }
    return contract;
  }

  ToolInputNormalization normalizeAndValidate(
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
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) =>
      _contracts.values
          .where(
            (contract) =>
                allowlist == null || allowlist.contains(contract.name),
          )
          .map((contract) => contract.descriptor(dialect: dialect))
          .toList(growable: false);

  void verifyCoverage(Iterable<String> handlerNames) {
    final handlers = handlerNames.toSet();
    final missingContracts = handlers.difference(names);
    final missingHandlers = names.difference(handlers);
    if (missingContracts.isNotEmpty || missingHandlers.isNotEmpty) {
      throw ProductException(
        'tool_registry_drift',
        'Executable tool handlers and the generated schema registry disagree.',
        details: <String, dynamic>{
          'missingContracts': missingContracts.toList()..sort(),
          'missingHandlers': missingHandlers.toList()..sort(),
          'registryVersion': version,
          'contractDigest': contractDigest,
        },
      );
    }
  }
}

class JsonSchemaValidator {
  const JsonSchemaValidator._();

  static List<SchemaIssue> validate(
    Object? value,
    Map<String, dynamic> schema, {
    String path = r'$',
  }) {
    final issues = <SchemaIssue>[];
    _validate(value, schema, path, issues);
    return List<SchemaIssue>.unmodifiable(issues);
  }

  static void _validate(
    Object? value,
    Map<String, dynamic> schema,
    String path,
    List<SchemaIssue> issues,
  ) {
    if (schema.containsKey('const') &&
        !_jsonEquivalent(value, schema['const'])) {
      issues.add(
        SchemaIssue(
          path: path,
          keyword: 'const',
          message: 'Value must equal the schema constant.',
          expected: schema['const'],
          actualType: _typeName(value),
        ),
      );
      return;
    }
    final enumValues = schema['enum'];
    if (enumValues is List &&
        !enumValues.any((candidate) => _jsonEquivalent(value, candidate))) {
      issues.add(
        SchemaIssue(
          path: path,
          keyword: 'enum',
          message: 'Value is not one of the allowed values.',
          expected: enumValues,
          actualType: _typeName(value),
        ),
      );
      return;
    }

    final type = schema['type'];
    if (type != null && !_matchesType(value, type)) {
      issues.add(
        SchemaIssue(
          path: path,
          keyword: 'type',
          message: 'Expected JSON type $type.',
          expected: type,
          actualType: _typeName(value),
        ),
      );
      return;
    }

    if (value is Map) {
      final object = Map<String, dynamic>.from(value);
      final properties = _map(schema['properties']);
      for (final required in _strings(schema['required'])) {
        if (!object.containsKey(required)) {
          issues.add(
            SchemaIssue(
              path: '$path.$required',
              keyword: 'required',
              message: 'Required property "$required" is missing.',
              expected: required,
              actualType: 'missing',
            ),
          );
        }
      }
      for (final entry in object.entries) {
        final child = properties[entry.key];
        if (child != null) {
          _validate(
            entry.value,
            _map(child),
            '$path.${entry.key}',
            issues,
          );
          continue;
        }
        final additional = schema['additionalProperties'];
        if (additional == false) {
          issues.add(
            SchemaIssue(
              path: '$path.${entry.key}',
              keyword: 'additionalProperties',
              message: 'Property "${entry.key}" is not allowed.',
              expected: properties.keys.toList()..sort(),
              actualType: _typeName(entry.value),
            ),
          );
        } else if (additional is Map) {
          _validate(
            entry.value,
            Map<String, dynamic>.from(additional),
            '$path.${entry.key}',
            issues,
          );
        }
      }
    }

    if (value is List) {
      final minimum = _int(schema['minItems']);
      final maximum = _int(schema['maxItems']);
      if (minimum != null && value.length < minimum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'minItems',
            message: 'Array has fewer than $minimum items.',
            expected: minimum,
            actualType: 'array',
          ),
        );
      }
      if (maximum != null && value.length > maximum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'maxItems',
            message: 'Array has more than $maximum items.',
            expected: maximum,
            actualType: 'array',
          ),
        );
      }
      if (schema['uniqueItems'] == true) {
        final seen = <String>{};
        for (var index = 0; index < value.length; index++) {
          final fingerprint = canonicalJson(value[index]);
          if (!seen.add(fingerprint)) {
            issues.add(
              SchemaIssue(
                path: '$path[$index]',
                keyword: 'uniqueItems',
                message: 'Array items must be unique.',
                expected: true,
                actualType: 'array',
              ),
            );
          }
        }
      }
      final items = schema['items'];
      if (items is Map) {
        for (var index = 0; index < value.length; index++) {
          _validate(
            value[index],
            Map<String, dynamic>.from(items),
            '$path[$index]',
            issues,
          );
        }
      }
    }

    if (value is String) {
      final minimum = _int(schema['minLength']);
      final maximum = _int(schema['maxLength']);
      if (minimum != null && value.length < minimum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'minLength',
            message: 'String is shorter than $minimum characters.',
            expected: minimum,
            actualType: 'string',
          ),
        );
      }
      if (maximum != null && value.length > maximum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'maxLength',
            message: 'String is longer than $maximum characters.',
            expected: maximum,
            actualType: 'string',
          ),
        );
      }
      final pattern = schema['pattern']?.toString();
      if (pattern != null && !RegExp(pattern).hasMatch(value)) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'pattern',
            message: 'String does not match its required pattern.',
            expected: pattern,
            actualType: 'string',
          ),
        );
      }
      final format = schema['format']?.toString();
      if (format != null && !_validFormat(value, format)) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'format',
            message: 'String is not a valid $format value.',
            expected: format,
            actualType: 'string',
          ),
        );
      }
    }

    if (value is num) {
      final minimum = _number(schema['minimum']);
      final maximum = _number(schema['maximum']);
      if (minimum != null && value < minimum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'minimum',
            message: 'Number is below the allowed minimum.',
            expected: minimum,
            actualType: _typeName(value),
          ),
        );
      }
      if (maximum != null && value > maximum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'maximum',
            message: 'Number is above the allowed maximum.',
            expected: maximum,
            actualType: _typeName(value),
          ),
        );
      }
      final exclusiveMinimum = _number(schema['exclusiveMinimum']);
      final exclusiveMaximum = _number(schema['exclusiveMaximum']);
      if (exclusiveMinimum != null && value <= exclusiveMinimum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'exclusiveMinimum',
            message: 'Number must be greater than the exclusive minimum.',
            expected: exclusiveMinimum,
            actualType: _typeName(value),
          ),
        );
      }
      if (exclusiveMaximum != null && value >= exclusiveMaximum) {
        issues.add(
          SchemaIssue(
            path: path,
            keyword: 'exclusiveMaximum',
            message: 'Number must be less than the exclusive maximum.',
            expected: exclusiveMaximum,
            actualType: _typeName(value),
          ),
        );
      }
    }

    _validateAlternatives(value, schema, path, issues, 'allOf');
    _validateAlternatives(value, schema, path, issues, 'anyOf');
    _validateAlternatives(value, schema, path, issues, 'oneOf');
  }

  static void _validateAlternatives(
    Object? value,
    Map<String, dynamic> schema,
    String path,
    List<SchemaIssue> issues,
    String keyword,
  ) {
    final branches = schema[keyword];
    if (branches is! List || branches.isEmpty) {
      return;
    }
    final results = <List<SchemaIssue>>[];
    for (final branch in branches.whereType<Map>()) {
      final branchIssues = <SchemaIssue>[];
      _validate(value, Map<String, dynamic>.from(branch), path, branchIssues);
      results.add(branchIssues);
    }
    final passing = results.where((result) => result.isEmpty).length;
    final valid = switch (keyword) {
      'allOf' => passing == results.length,
      'oneOf' => passing == 1,
      _ => passing >= 1,
    };
    if (!valid) {
      issues.add(
        SchemaIssue(
          path: path,
          keyword: keyword,
          message: 'Value does not satisfy the $keyword schema branches.',
          expected: keyword == 'oneOf' ? 1 : 'at least one',
          actualType: _typeName(value),
        ),
      );
    }
  }
}

PermissionScope _permission(String value) => PermissionScope.values.firstWhere(
      (permission) => permission.name == value,
      orElse: () => throw StateError('Unknown generated permission: $value'),
    );

ToolRisk _risk(String value) => ToolRisk.values.firstWhere(
      (risk) => risk.name == value,
      orElse: () => throw StateError('Unknown generated tool risk: $value'),
    );

ToolIdempotency _idempotency(String value) => switch (value) {
      'normalized_arguments' => ToolIdempotency.normalizedArguments,
      'content_hash' => ToolIdempotency.contentHash,
      'project_snapshot' => ToolIdempotency.projectSnapshot,
      'operation_key' => ToolIdempotency.operationKey,
      'request_hash' => ToolIdempotency.requestHash,
      _ => throw StateError('Unknown generated idempotency policy: $value'),
    };

String _idempotencyWireName(ToolIdempotency value) => switch (value) {
      ToolIdempotency.normalizedArguments => 'normalized_arguments',
      ToolIdempotency.contentHash => 'content_hash',
      ToolIdempotency.projectSnapshot => 'project_snapshot',
      ToolIdempotency.operationKey => 'operation_key',
      ToolIdempotency.requestHash => 'request_hash',
    };

Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const <String>[];

int? _int(Object? value) => value is int
    ? value
    : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');

num? _number(Object? value) => value is num
    ? value
    : num.tryParse(value?.toString() ?? '');

Object? _cloneJson(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _cloneJson(entry.value),
    };
  }
  if (value is List) {
    return value.map(_cloneJson).toList(growable: false);
  }
  return value;
}

bool _jsonEquivalent(Object? left, Object? right) {
  try {
    return jsonEncode(left) == jsonEncode(right);
  } catch (_) {
    return left == right;
  }
}

String _typeName(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return 'boolean';
  if (value is int) return 'integer';
  if (value is num) return 'number';
  if (value is String) return 'string';
  if (value is List) return 'array';
  if (value is Map) return 'object';
  return value.runtimeType.toString();
}

bool _matchesType(Object? value, Object type) {
  final types = type is List ? type.map((item) => '$item') : <String>['$type'];
  return types.any((candidate) {
    return switch (candidate) {
      'null' => value == null,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num && value is! bool,
      'string' => value is String,
      'array' => value is List,
      'object' => value is Map,
      _ => false,
    };
  });
}

bool _validFormat(String value, String format) {
  if (format == 'date-time') {
    return DateTime.tryParse(value) != null;
  }
  if (format == 'https-uri') {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty &&
        !uri.hasFragment &&
        uri.userInfo.isEmpty;
  }
  if (format == 'project-relative-path') {
    return value.trim().isNotEmpty && !value.contains('\u0000');
  }
  return true;
}

String _topLevelArgument(String path) {
  final normalized = path
      .replaceFirst(r'$.arguments.', '')
      .replaceFirst(r'$.', '');
  return normalized.split(RegExp(r'[.\[]')).first;
}

extension _FirstSchemaIssue on Iterable<SchemaIssue> {
  SchemaIssue? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
