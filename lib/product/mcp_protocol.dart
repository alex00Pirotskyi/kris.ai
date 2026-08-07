import 'storage_security.dart';

const String mcpCurrentStableProtocolVersion = '2026-07-28';
const String mcpLegacyProtocolVersion = '2024-11-05';

enum McpProtocolEra {
  legacyInitialize,
  modernStateless,
}

class McpToolCatalogPage {
  const McpToolCatalogPage({
    required this.toolNames,
    required this.nextCursor,
  });

  final Set<String> toolNames;
  final String? nextCursor;
}

/// A protocol revision adapter isolates wire-era behavior from MCP product code.
///
/// Only revisions explicitly listed by [McpProtocolRegistry] are accepted by
/// production trust records. Draft and unknown revision strings fail closed.
class McpProtocolAdapter {
  const McpProtocolAdapter._({
    required this.version,
    required this.era,
  });

  final String version;
  final McpProtocolEra era;

  bool get usesInitialize => era == McpProtocolEra.legacyInitialize;
  bool get usesPerRequestMetadata => era == McpProtocolEra.modernStateless;

  Map<String, dynamic> decorateRequestParams(
    Map<String, dynamic> params, {
    required String clientName,
    required String clientVersion,
    Map<String, dynamic> clientCapabilities = const <String, dynamic>{},
  }) {
    final decorated = <String, dynamic>{...params};
    if (!usesPerRequestMetadata) {
      return decorated;
    }

    final rawMeta = decorated['_meta'];
    final meta = rawMeta == null
        ? <String, dynamic>{}
        : _stringKeyedMap(rawMeta, code: 'mcp_request_meta_invalid');
    final reserved =
        meta.keys.where(_isReservedMcpMetaKey).toList(growable: false);
    if (reserved.isNotEmpty) {
      throw ProductException(
        'mcp_reserved_meta_rejected',
        'Reserved MCP protocol metadata is controlled by the client adapter.',
        details: <String, dynamic>{'keys': reserved..sort()},
      );
    }
    meta['io.modelcontextprotocol/protocolVersion'] = version;
    meta['io.modelcontextprotocol/clientInfo'] = <String, String>{
      'name': clientName,
      'version': clientVersion,
    };
    meta['io.modelcontextprotocol/clientCapabilities'] = <String, dynamic>{
      ...clientCapabilities
    };
    decorated['_meta'] = meta;
    return decorated;
  }

  Set<String> validateLegacyInitialize(
    Map<String, dynamic> result, {
    Set<String> requiredCapabilities = const <String>{},
  }) {
    if (!usesInitialize) {
      throw ProductException(
        'mcp_protocol_era_mismatch',
        'A modern MCP revision cannot use the initialize handshake.',
        details: <String, dynamic>{'protocolVersion': version},
      );
    }
    final negotiated = result['protocolVersion']?.toString().trim() ?? '';
    if (negotiated != version) {
      throw ProductException(
        'mcp_protocol_version_mismatch',
        'The MCP server did not accept the explicitly trusted protocol version.',
        details: <String, dynamic>{
          'requested': version,
          'negotiated': negotiated,
        },
      );
    }
    return _validateCapabilityFloor(
      result['capabilities'],
      requiredCapabilities: requiredCapabilities,
    );
  }

  /// Validates an optional modern `server/discover` response.
  ///
  /// Discovery is not required by the 2026-07-28 protocol. Runtime code must
  /// never make successful discovery a prerequisite for a pinned modern
  /// connection; the mandatory feature endpoint is the authoritative proof.
  Set<String> validateModernDiscovery(
    Map<String, dynamic> result, {
    Set<String> requiredCapabilities = const <String>{},
  }) {
    if (usesInitialize) {
      throw ProductException(
        'mcp_protocol_era_mismatch',
        'A legacy MCP revision cannot use modern discovery as its negotiated era.',
        details: <String, dynamic>{'protocolVersion': version},
      );
    }
    final rawVersions = result['supportedVersions'];
    if (rawVersions is! List) {
      throw ProductException(
        'mcp_discovery_invalid',
        'MCP server discovery did not declare supported protocol versions.',
      );
    }
    final supported = rawVersions
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!supported.contains(version)) {
      final sorted = supported.toList()..sort();
      throw ProductException(
        'mcp_protocol_version_mismatch',
        'The MCP server does not advertise the explicitly trusted protocol version.',
        details: <String, dynamic>{
          'requested': version,
          'supported': sorted,
        },
      );
    }
    return _validateCapabilityFloor(
      result['capabilities'],
      requiredCapabilities: requiredCapabilities,
    );
  }

  McpToolCatalogPage parseToolCatalogPage(Map<String, dynamic> result) {
    final rawTools = result['tools'];
    if (rawTools is! List) {
      throw ProductException(
        'mcp_tool_catalog_invalid',
        'MCP tools/list response did not contain a tool array.',
      );
    }

    final names = <String>{};
    for (final rawTool in rawTools) {
      final tool = _stringKeyedMap(rawTool, code: 'mcp_tool_catalog_invalid');
      final name = tool['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        throw ProductException(
          'mcp_tool_catalog_invalid',
          'MCP tools/list returned a tool without a name.',
        );
      }
      if (!names.add(name)) {
        throw ProductException(
          'mcp_tool_catalog_invalid',
          'MCP tools/list returned a duplicate tool name.',
          details: <String, dynamic>{'tool': name},
        );
      }
    }

    final rawCursor = result['nextCursor'];
    final nextCursor = rawCursor == null ? null : rawCursor.toString().trim();
    if (rawCursor != null && nextCursor!.isEmpty) {
      throw ProductException(
        'mcp_tool_catalog_invalid',
        'MCP tools/list returned an empty pagination cursor.',
      );
    }
    return McpToolCatalogPage(
      toolNames: Set<String>.unmodifiable(names),
      nextCursor: nextCursor,
    );
  }

  void validateRequiredTools(
    Set<String> availableTools,
    Set<String> requiredTools,
  ) {
    final missing = requiredTools.difference(availableTools).toList()..sort();
    if (missing.isNotEmpty) {
      throw ProductException(
        'mcp_tool_removed',
        'The MCP server no longer exposes tools required by this trust.',
        details: <String, dynamic>{
          'protocolVersion': version,
          'missing': missing,
        },
      );
    }
  }

  Set<String> _validateCapabilityFloor(
    Object? rawCapabilities, {
    required Set<String> requiredCapabilities,
  }) {
    final capabilities = _stringKeyedMap(
      rawCapabilities,
      code: 'mcp_capabilities_invalid',
    );
    final malformed = <String>[];
    for (final entry in capabilities.entries) {
      if (entry.value is! Map) {
        malformed.add(entry.key);
      }
    }
    if (malformed.isNotEmpty) {
      malformed.sort();
      throw ProductException(
        'mcp_capabilities_invalid',
        'MCP server capabilities must use object-valued declarations.',
        details: <String, dynamic>{'capabilities': malformed},
      );
    }

    final available = capabilities.keys.toSet();
    final missing = requiredCapabilities.difference(available).toList()..sort();
    if (missing.isNotEmpty) {
      throw ProductException(
        'mcp_capability_removed',
        'The MCP server no longer provides capabilities required by this trust.',
        details: <String, dynamic>{
          'protocolVersion': version,
          'missing': missing,
        },
      );
    }
    return Set<String>.unmodifiable(available);
  }
}

class McpProtocolRegistry {
  const McpProtocolRegistry._();

  static const String currentStableVersion = mcpCurrentStableProtocolVersion;

  static const List<String> stableVersions = <String>[
    '2026-07-28',
    '2025-11-25',
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];

  static const McpProtocolAdapter _modern20260728 = McpProtocolAdapter._(
    version: '2026-07-28',
    era: McpProtocolEra.modernStateless,
  );
  static const McpProtocolAdapter _legacy20251125 = McpProtocolAdapter._(
    version: '2025-11-25',
    era: McpProtocolEra.legacyInitialize,
  );
  static const McpProtocolAdapter _legacy20250618 = McpProtocolAdapter._(
    version: '2025-06-18',
    era: McpProtocolEra.legacyInitialize,
  );
  static const McpProtocolAdapter _legacy20250326 = McpProtocolAdapter._(
    version: '2025-03-26',
    era: McpProtocolEra.legacyInitialize,
  );
  static const McpProtocolAdapter _legacy20241105 = McpProtocolAdapter._(
    version: '2024-11-05',
    era: McpProtocolEra.legacyInitialize,
  );

  static McpProtocolAdapter requireStable(String rawVersion) {
    final version = rawVersion.trim();
    switch (version) {
      case '2026-07-28':
        return _modern20260728;
      case '2025-11-25':
        return _legacy20251125;
      case '2025-06-18':
        return _legacy20250618;
      case '2025-03-26':
        return _legacy20250326;
      case '2024-11-05':
        return _legacy20241105;
    }
    if (version.toUpperCase().contains('DRAFT') ||
        version.toUpperCase().contains('RC')) {
      throw ProductException(
        'mcp_protocol_draft_rejected',
        'Draft or release-candidate MCP revisions require a separately reviewed adapter and explicit opt-in.',
        details: <String, dynamic>{'protocolVersion': version},
      );
    }
    throw ProductException(
      'mcp_protocol_unsupported',
      'MCP protocol revision is not supported by the production adapter registry.',
      details: <String, dynamic>{
        'protocolVersion': version,
        'supported': stableVersions,
      },
    );
  }
}

bool _isReservedMcpMetaKey(String key) {
  final separator = key.indexOf('/');
  if (separator <= 0) {
    return false;
  }
  final labels = key.substring(0, separator).split('.');
  if (labels.length < 2) {
    return false;
  }
  final secondLabel = labels[1].toLowerCase();
  return secondLabel == 'modelcontextprotocol' || secondLabel == 'mcp';
}

Map<String, dynamic> _stringKeyedMap(
  Object? value, {
  required String code,
}) {
  if (value is! Map) {
    throw ProductException(code, 'Expected a JSON object.');
  }
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw ProductException(code, 'Expected JSON object keys to be strings.');
  }
}
