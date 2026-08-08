import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/mcp_protocol.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  group('MCP tools/list opaque cursor contract', () {
    final adapter = McpProtocolRegistry.requireStable('2026-07-28');

    test('preserves an opaque cursor byte-for-byte', () {
      const cursor = '  opaque cursor\twith whitespace  ';
      final page = adapter.parseToolCatalogPage(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'search'},
        ],
        'nextCursor': cursor,
      });

      expect(page.nextCursor, cursor);
    });

    test('treats an empty string cursor as present and valid', () {
      final page = adapter.parseToolCatalogPage(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'search'},
        ],
        'nextCursor': '',
      });

      expect(page.nextCursor, '');
    });

    test('rejects non-string cursors instead of coercing them', () {
      expect(
        () => adapter.parseToolCatalogPage(<String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'search'},
          ],
          'nextCursor': 42,
        }),
        throwsA(isA<ProductException>()),
      );
    });
  });

  group('MCP tools/list tool-name typing', () {
    final adapter = McpProtocolRegistry.requireStable('2026-07-28');

    test('rejects non-string tool names instead of coercing them', () {
      expect(
        () => adapter.parseToolCatalogPage(<String, dynamic>{
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{'name': 42},
          ],
        }),
        throwsA(isA<ProductException>()),
      );
    });

    test('preserves protocol tool names exactly', () {
      const name = '  tool name with spaces  ';
      final page = adapter.parseToolCatalogPage(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{'name': name},
        ],
      });

      expect(page.toolNames, <String>{name});
    });
  });

  group('MCP reserved metadata contract', () {
    final adapter = McpProtocolRegistry.requireStable('2026-07-28');

    test('rejects all reserved MCP DNS-label families', () {
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

    test('preserves application-owned metadata outside reserved families', () {
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
      expect(
        meta['com.example/context'],
        <String, dynamic>{'trace': true},
      );
    });
  });
}
