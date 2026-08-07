import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/mcp_protocol.dart';

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
}
