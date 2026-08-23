import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/mcp_protocol.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  group('MCP protocol registry', () {
    test('pins the current stable revision to the modern stateless era', () {
      final adapter = McpProtocolRegistry.requireStable(
        McpProtocolRegistry.currentStableVersion,
      );

      expect(adapter.version, '2026-07-28');
      expect(adapter.era, McpProtocolEra.modernStateless);
      expect(adapter.usesInitialize, isFalse);
      expect(adapter.usesPerRequestMetadata, isTrue);
    });

    test('keeps supported historical stable revisions in legacy era', () {
      for (final version in <String>[
        '2025-11-25',
        '2025-06-18',
        '2025-03-26',
        '2024-11-05',
      ]) {
        final adapter = McpProtocolRegistry.requireStable(version);
        expect(adapter.version, version);
        expect(adapter.era, McpProtocolEra.legacyInitialize);
        expect(adapter.usesInitialize, isTrue);
        expect(adapter.usesPerRequestMetadata, isFalse);
      }
    });

    test('draft and unknown protocol revisions fail closed', () {
      expect(
        () => McpProtocolRegistry.requireStable('DRAFT-2026-v2'),
        throwsA(isA<ProductException>()),
      );
      expect(
        () => McpProtocolRegistry.requireStable('2099-01-01'),
        throwsA(isA<ProductException>()),
      );
    });
  });

  group('modern request envelope', () {
    test(
      'stamps protocol identity and client capabilities on every request',
      () {
        final adapter = McpProtocolRegistry.requireStable('2026-07-28');
        final params = adapter.decorateRequestParams(
          <String, dynamic>{
            'name': 'search',
            'arguments': <String, dynamic>{'query': 'mcp'},
          },
          clientName: 'Kristin Local Agent',
          clientVersion: '1.9.0+190',
          clientCapabilities: const <String, dynamic>{},
        );

        final meta = params['_meta'] as Map<String, dynamic>;
        expect(meta['io.modelcontextprotocol/protocolVersion'], '2026-07-28');
        expect(meta['io.modelcontextprotocol/clientInfo'], <String, dynamic>{
          'name': 'Kristin Local Agent',
          'version': '1.9.0+190',
        });
        expect(
          meta['io.modelcontextprotocol/clientCapabilities'],
          <String, dynamic>{},
        );
      },
    );

    test('callers cannot override any MCP-reserved metadata prefix', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      for (final key in <String>[
        'io.modelcontextprotocol/protocolVersion',
        'dev.mcp/securityContext',
        'org.modelcontextprotocol.api/feature',
        'com.mcp.tools/override',
      ]) {
        expect(
          () => adapter.decorateRequestParams(
            <String, dynamic>{
              '_meta': <String, dynamic>{key: 'caller-controlled'},
            },
            clientName: 'Kristin Local Agent',
            clientVersion: '1.9.0+190',
          ),
          throwsA(isA<ProductException>()),
          reason: '$key is reserved by MCP',
        );
      }
    });

    test('ordinary application metadata remains available to callers', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      final params = adapter.decorateRequestParams(
        <String, dynamic>{
          '_meta': <String, dynamic>{
            'com.example.mcp/context': 'allowed',
            'com.example/context': <String, dynamic>{'trace': true},
          },
        },
        clientName: 'Kristin Local Agent',
        clientVersion: '1.9.0+190',
      );

      final meta = params['_meta'] as Map<String, dynamic>;
      expect(meta['com.example.mcp/context'], 'allowed');
      expect(meta['com.example/context'], <String, dynamic>{'trace': true});
      expect(meta['io.modelcontextprotocol/protocolVersion'], '2026-07-28');
    });

    test(
      'legacy requests remain byte-shape compatible without modern meta',
      () {
        final adapter = McpProtocolRegistry.requireStable('2024-11-05');
        final params = adapter.decorateRequestParams(
          <String, dynamic>{'name': 'search'},
          clientName: 'Kristin Local Agent',
          clientVersion: '1.9.0+190',
        );

        expect(params, <String, dynamic>{'name': 'search'});
        expect(params.containsKey('_meta'), isFalse);
      },
    );
  });

  group('version and capability floors', () {
    test(
      'legacy initialize cannot silently negotiate a different revision',
      () {
        final adapter = McpProtocolRegistry.requireStable('2025-11-25');
        expect(
          () => adapter.validateLegacyInitialize(
            <String, dynamic>{
              'protocolVersion': '2025-06-18',
              'capabilities': <String, dynamic>{'tools': <String, dynamic>{}},
            },
            requiredCapabilities: const <String>{'tools'},
          ),
          throwsA(isA<ProductException>()),
        );
      },
    );

    test('legacy initialize rejects removal of the tools capability', () {
      final adapter = McpProtocolRegistry.requireStable('2025-11-25');
      expect(
        () => adapter.validateLegacyInitialize(
          <String, dynamic>{
            'protocolVersion': '2025-11-25',
            'capabilities': <String, dynamic>{'resources': <String, dynamic>{}},
          },
          requiredCapabilities: const <String>{'tools'},
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test(
      'optional modern discovery still validates an explicit pin when used',
      () {
        final adapter = McpProtocolRegistry.requireStable('2026-07-28');
        final capabilities = adapter.validateModernDiscovery(
          <String, dynamic>{
            'supportedVersions': <String>['2026-07-28'],
            'capabilities': <String, dynamic>{
              'tools': <String, dynamic>{'listChanged': true},
            },
          },
          requiredCapabilities: const <String>{'tools'},
        );

        expect(capabilities, contains('tools'));
        expect(
          () => adapter.validateModernDiscovery(
            <String, dynamic>{
              'supportedVersions': <String>['2025-11-25'],
              'capabilities': <String, dynamic>{'tools': <String, dynamic>{}},
            },
            requiredCapabilities: const <String>{'tools'},
          ),
          throwsA(isA<ProductException>()),
        );
      },
    );
  });

  group('trusted tool catalog', () {
    test('parses paginated tools/list pages without requiring discovery', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      final page = adapter.parseToolCatalogPage(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'search',
            'inputSchema': <String, dynamic>{'type': 'object'},
          },
          <String, dynamic>{
            'name': 'read_file',
            'inputSchema': <String, dynamic>{'type': 'object'},
          },
        ],
        'nextCursor': 'page-2',
      });

      expect(page.toolNames, <String>{'search', 'read_file'});
      expect(page.nextCursor, 'page-2');
    });

    test('empty pagination cursor remains valid and present', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      final page = adapter.parseToolCatalogPage(<String, dynamic>{
        'tools': const <Map<String, dynamic>>[],
        'nextCursor': '',
      });

      expect(page.nextCursor, '');
    });

    test('missing trusted tool is rejected after catalog accumulation', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      expect(
        () => adapter.validateRequiredTools(
          <String>{'search'},
          <String>{'search', 'read_file'},
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('duplicate and malformed tool entries fail closed', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      expect(
        () => adapter.parseToolCatalogPage(<String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'search'},
            <String, dynamic>{'name': 'search'},
          ],
        }),
        throwsA(isA<ProductException>()),
      );
      expect(
        () => adapter.parseToolCatalogPage(<String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{'name': ''},
          ],
        }),
        throwsA(isA<ProductException>()),
      );
    });

    test('complete trusted tool set is accepted', () {
      final adapter = McpProtocolRegistry.requireStable('2024-11-05');
      expect(
        () => adapter.validateRequiredTools(
          <String>{'search', 'read_file', 'write_file'},
          <String>{'search', 'read_file'},
        ),
        returnsNormally,
      );
    });
  });
}
