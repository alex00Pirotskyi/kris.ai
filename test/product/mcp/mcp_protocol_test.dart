import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/mcp_protocol.dart';

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
    test('stamps protocol identity and client capabilities on every request', () {
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
      expect(
        meta['io.modelcontextprotocol/clientInfo'],
        <String, dynamic>{
          'name': 'Kristin Local Agent',
          'version': '1.9.0+190',
        },
      );
      expect(
        meta['io.modelcontextprotocol/clientCapabilities'],
        <String, dynamic>{},
      );
    });

    test('callers cannot override reserved protocol metadata', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      expect(
        () => adapter.decorateRequestParams(
          <String, dynamic>{
            '_meta': <String, dynamic>{
              'io.modelcontextprotocol/protocolVersion': '2099-01-01',
            },
          },
          clientName: 'Kristin Local Agent',
          clientVersion: '1.9.0+190',
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('legacy requests remain byte-shape compatible without modern meta', () {
      final adapter = McpProtocolRegistry.requireStable('2024-11-05');
      final params = adapter.decorateRequestParams(
        <String, dynamic>{'name': 'search'},
        clientName: 'Kristin Local Agent',
        clientVersion: '1.9.0+190',
      );

      expect(params, <String, dynamic>{'name': 'search'});
      expect(params.containsKey('_meta'), isFalse);
    });
  });

  group('version and capability floors', () {
    test('modern discovery requires the explicitly pinned revision', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      expect(
        () => adapter.validateModernDiscovery(
          <String, dynamic>{
            'supportedVersions': <String>['2025-11-25'],
            'capabilities': <String, dynamic>{
              'tools': <String, dynamic>{},
            },
          },
          requiredCapabilities: const <String>{'tools'},
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('modern discovery rejects silent removal of required tools', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      expect(
        () => adapter.validateModernDiscovery(
          <String, dynamic>{
            'supportedVersions': <String>['2026-07-28'],
            'capabilities': <String, dynamic>{
              'resources': <String, dynamic>{},
            },
          },
          requiredCapabilities: const <String>{'tools'},
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('legacy initialize cannot silently negotiate a different revision', () {
      final adapter = McpProtocolRegistry.requireStable('2025-11-25');
      expect(
        () => adapter.validateLegacyInitialize(
          <String, dynamic>{
            'protocolVersion': '2025-06-18',
            'capabilities': <String, dynamic>{
              'tools': <String, dynamic>{},
            },
          },
          requiredCapabilities: const <String>{'tools'},
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('valid modern discovery returns the negotiated capability set', () {
      final adapter = McpProtocolRegistry.requireStable('2026-07-28');
      final capabilities = adapter.validateModernDiscovery(
        <String, dynamic>{
          'supportedVersions': <String>['2026-07-28', '2025-11-25'],
          'capabilities': <String, dynamic>{
            'tools': <String, dynamic>{'listChanged': true},
            'resources': <String, dynamic>{},
          },
        },
        requiredCapabilities: const <String>{'tools'},
      );

      expect(capabilities, containsAll(<String>['tools', 'resources']));
    });
  });
}
