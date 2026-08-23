import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  group('P8-006 research adversarial boundary', () {
    late ResearchService service;

    setUp(() {
      service = ResearchService(
        policy: const ResearchPolicy(
          maxBytes: 1024 * 1024,
          maxRedirects: 4,
          timeout: Duration(seconds: 2),
        ),
        redactor: SecretRedactor(),
      );
    });

    test('rejects non-HTTPS and embedded credentials before network access', () async {
      await expectLater(
        service.validateUri(Uri.parse('http://example.invalid/source')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'research_scheme_rejected',
          ),
        ),
      );
      await expectLater(
        service.validateUri(Uri.parse('https://user:secret@example.invalid/source')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'research_credentials_rejected',
          ),
        ),
      );
    });

    test('rejects IPv4 loopback SSRF target', () async {
      await expectLater(
        service.validateUri(Uri.parse('https://127.0.0.1/private')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'research_private_address',
          ),
        ),
      );
    });

    test('rejects IPv6 loopback SSRF target', () async {
      await expectLater(
        service.validateUri(Uri.parse('https://[::1]/private')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'research_private_address',
          ),
        ),
      );
    });

    test('rejects hostless research targets', () async {
      await expectLater(
        service.validateUri(Uri(scheme: 'https', path: '/relative')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'research_host_missing',
          ),
        ),
      );
    });
  });
}
