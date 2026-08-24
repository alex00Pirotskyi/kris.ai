import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/research/research_browser_adapter.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  test('weak HTML is upgraded to rendered browser evidence', () async {
    var renderCalls = 0;
    final service = _service(
      baseFetch: (_) async => _source(
        content: 'Loading...',
        rawContent: '<html>${'x' * 3000}</html>',
      ),
    );
    service.attachRenderedPageLoader((url) async {
      renderCalls += 1;
      return _observation(url, visibleText: 'Rendered documentation');
    });

    final result = await service.fetch(Uri.parse('https://example.com/docs'));

    expect(renderCalls, 1);
    expect(result.content, 'Rendered documentation');
    expect(
        result.responseHeaders['x-kristin-research-mode'], 'rendered-browser');
    expect(result.rawContent, contains('"sourceKind":"rendered-browser"'));
  });

  test('strong static HTML stays on the cheap HTTP path', () async {
    var renderCalls = 0;
    final service = _service(
      baseFetch: (_) async => _source(
        content: 'A' * 2400,
        rawContent: '<div id="__next">${'A' * 2400}</div>',
      ),
    );
    service.attachRenderedPageLoader((url) async {
      renderCalls += 1;
      return _observation(url, visibleText: 'unused');
    });

    final result =
        await service.fetch(Uri.parse('https://example.com/article'));

    expect(renderCalls, 0);
    expect(result.content, 'A' * 2400);
  });

  test('HTTP failure can fall back to rendered browser evidence', () async {
    final service = _service(
      baseFetch: (_) async {
        throw ProductException('research_http_error', 'HTTP 403');
      },
    );
    service.attachRenderedPageLoader(
      (url) async => _observation(url, visibleText: 'Rendered after HTTP 403'),
    );

    final result = await service.fetch(Uri.parse('https://example.com/app'));

    expect(result.content, 'Rendered after HTTP 403');
    expect(
        result.responseHeaders['x-kristin-research-mode'], 'rendered-browser');
  });

  test('browser failure never discards a usable HTTP source', () async {
    final original = _source(
      content: 'Loading...',
      rawContent: '<html>${'x' * 3000}</html>',
    );
    final service = _service(baseFetch: (_) async => original);
    service.attachRenderedPageLoader((url) async {
      throw const P3BrowserRuntimeException('browser_worker_unavailable');
    });

    final result = await service.fetch(Uri.parse('https://example.com/docs'));

    expect(result.contentHash, original.contentHash);
    expect(result.content, original.content);
  });

  test('policy failures never fall through to browser rendering', () async {
    var renderCalls = 0;
    final service = _service(
      baseFetch: (_) async {
        throw ProductException(
          'research_private_address',
          'Private target rejected',
        );
      },
    );
    service.attachRenderedPageLoader((url) async {
      renderCalls += 1;
      return _observation(url, visibleText: 'must not render');
    });

    await expectLater(
      service.fetch(Uri.parse('https://127.0.0.1/private')),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'research_private_address',
        ),
      ),
    );
    expect(renderCalls, 0);
  });
}

P4BrowserAwareResearchService _service({
  required Future<ResearchSource> Function(Uri url) baseFetch,
}) =>
    P4BrowserAwareResearchService(
      policy: const ResearchPolicy(
        maxBytes: 1024 * 1024,
        maxRedirects: 3,
        timeout: Duration(seconds: 5),
      ),
      redactor: SecretRedactor(),
      baseFetchOverride: baseFetch,
    );

ResearchSource _source({
  required String content,
  required String rawContent,
}) =>
    ResearchSource(
      id: 'source-http',
      url: Uri.parse('https://example.com/source'),
      title: 'HTTP source',
      mimeType: 'text/html',
      contentHash: Sha256.text(content),
      fetchedAt: DateTime.utc(2026, 8, 24),
      content: content,
      rawContent: rawContent,
      requestedUrl: Uri.parse('https://example.com/source'),
    );

P3BrowserPageObservation _observation(
  Uri url, {
  required String visibleText,
}) {
  final screenshot = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==',
  );
  final observation = <String, Object?>{
    'schemaVersion': '1.0.0',
    'url': url.removeFragment().toString(),
    'title': 'Rendered fixture',
    'dom': <String, Object?>{
      'text': '<main>$visibleText</main>',
      'bytes': utf8.encode('<main>$visibleText</main>').length,
      'truncated': false,
    },
    'visibleText': <String, Object?>{
      'text': visibleText,
      'bytes': utf8.encode(visibleText).length,
      'truncated': false,
    },
    'accessibility': <String, Object?>{
      'text': 'main $visibleText',
      'bytes': utf8.encode('main $visibleText').length,
      'truncated': false,
    },
    'forms': const <Object?>[],
    'console': <String, Object?>{'entries': const <Object?>[]},
    'network': <String, Object?>{'entries': const <Object?>[]},
    'screenshot': <String, Object?>{
      'mediaType': 'image/jpeg',
      'bytes': screenshot.length,
      'sha256': Sha256.hex(screenshot),
      'base64': base64Encode(screenshot),
    },
  };
  return P3BrowserPageObservation.fromJson(<String, Object?>{
    'sessionId': 'render-session',
    'pageId': 'render-page',
    'observationHash': Sha256.text(canonicalJson(observation)),
    'observation': observation,
  });
}
