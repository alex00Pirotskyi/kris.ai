import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/research_search_provider.dart';
import 'package:kristin_local_agent/product/run_preflight.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/tool_schema.dart';

void main() {
  group('built-in zero-key search provider', () {
    test('sends only the intended query and normalizes bounded results',
        () async {
      late SearchHttpRequest captured;
      final provider = BuiltInDuckDuckGoSearchProvider(
        timeout: const Duration(seconds: 2),
        maxBytes: 64 * 1024,
        transport: (request) async {
          captured = request;
          return SearchHttpResponse(
            statusCode: 200,
            headers: const <String, String>{
              'content-type': 'text/html; charset=UTF-8',
            },
            body: utf8.encode('''
              <html><body>
                <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fdocs&amp;rut=x">Example &amp; docs</a>
                <a class="result__snippet">Useful <b>official</b> documentation.</a>
                <a class="result__a" href="https://example.com/docs#fragment">Duplicate</a>
                <a class="result__snippet">Duplicate snippet</a>
                <a class="result__a" href="https://127.0.0.1/private">Private target</a>
                <a class="result__snippet">Must be rejected.</a>
              </body></html>
            '''),
          );
        },
      );

      final results = await provider.search(
        const SearchProviderRequest(query: 'flutter docs', count: 10),
      );

      expect(captured.method, 'POST');
      expect(captured.uri, Uri.https('html.duckduckgo.com', '/html/'));
      expect(captured.uri.query, isEmpty);
      expect(utf8.decode(captured.body), 'q=flutter+docs');
      expect(captured.headers[HttpHeaders.userAgentHeader], isNotEmpty);
      expect(results, hasLength(1));
      expect(results.single.title, 'Example & docs');
      expect(results.single.url, 'https://example.com/docs');
      expect(results.single.snippet, 'Useful official documentation.');
    });

    test('rejects invalid, non-HTTPS, and local result URLs', () {
      expect(normalizePublicSearchResultUrl('javascript:alert(1)'), isNull);
      expect(normalizePublicSearchResultUrl('http://example.com'), isNull);
      expect(normalizePublicSearchResultUrl('https://localhost/a'), isNull);
      expect(normalizePublicSearchResultUrl('https://10.0.0.1/a'), isNull);
      expect(normalizePublicSearchResultUrl('https://192.168.2.3/a'), isNull);
      expect(normalizePublicSearchResultUrl('https://[::1]/a'), isNull);
      expect(
        normalizePublicSearchResultUrl('https://example.com/a#fragment'),
        'https://example.com/a',
      );
    });

    test('fails safely on throttling, redirects, MIME, and challenges',
        () async {
      Future<void> expectCode(
        BuiltInDuckDuckGoSearchProvider provider,
        String code,
      ) =>
          expectLater(
            provider.search(const SearchProviderRequest(query: 'docs')),
            throwsA(
              isA<ProductException>().having(
                (error) => error.code,
                'code',
                code,
              ),
            ),
          );

      await expectCode(
        BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 1024,
          transport: (_) async => const SearchHttpResponse(
            statusCode: 429,
            headers: <String, String>{'retry-after': '30'},
            body: <int>[],
          ),
        ),
        'search_provider_rate_limited',
      );
      await expectCode(
        BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 1024,
          transport: (_) async => const SearchHttpResponse(
            statusCode: 302,
            headers: <String, String>{},
            body: <int>[],
          ),
        ),
        'search_provider_redirect_rejected',
      );
      await expectCode(
        BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 1024,
          transport: (_) async => SearchHttpResponse(
            statusCode: 200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
            body: utf8.encode('{}'),
          ),
        ),
        'search_provider_mime_rejected',
      );
      await expectCode(
        BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 4096,
          transport: (_) async => SearchHttpResponse(
            statusCode: 200,
            headers: const <String, String>{'content-type': 'text/html'},
            body: utf8.encode(
              '<html>Bots use DuckDuckGo too challenge-form</html>',
            ),
          ),
        ),
        'search_provider_rate_limited',
      );
    });

    test('rejects excessive responses before parsing', () async {
      final provider = BuiltInDuckDuckGoSearchProvider(
        timeout: const Duration(seconds: 1),
        maxBytes: 64,
        transport: (_) async => SearchHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: List<int>.filled(65, 0x20),
        ),
      );
      await expectLater(
        provider.search(const SearchProviderRequest(query: 'docs')),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'search_provider_response_too_large',
          ),
        ),
      );
    });

    test('honors cancellation before network execution', () async {
      final cancelled = Completer<void>()..complete();
      var transportCalled = false;
      final provider = BuiltInDuckDuckGoSearchProvider(
        timeout: const Duration(seconds: 1),
        maxBytes: 4096,
        transport: (_) async {
          transportCalled = true;
          throw StateError('transport must not be called');
        },
      );
      await expectLater(
        provider.search(
          SearchProviderRequest(
            query: 'docs',
            cancellation: cancelled.future,
            isCancelled: () => true,
          ),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      expect(transportCalled, isFalse);
    });
  });

  group('provider router', () {
    SearchProvider builtInSuccess() => BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 16 * 1024,
          transport: (_) async => SearchHttpResponse(
            statusCode: 200,
            headers: const <String, String>{'content-type': 'text/html'},
            body: utf8.encode('''
              <a class="result__a" href="https://example.com/free">Free result</a>
              <a class="result__snippet">No key required.</a>
            '''),
          ),
        );

    test('zero-key built-in search is the healthy baseline', () async {
      final router = SearchProviderRouter(builtIn: builtInSuccess());
      final response = await router.search(
        const SearchProviderRequest(query: 'current docs'),
      );
      expect(response.providerId, builtInSearchProviderId);
      expect(response.fallbackUsed, isFalse);
      expect(response.results.single.url, 'https://example.com/free');
      final probe = await router.probe();
      expect(probe.available, isTrue);
      expect(probe.message, 'Built-in web search is available.');
    });

    test('configured Brave remains an optional preferred provider', () async {
      final brave = BraveSearchProvider(
        apiKey: 'configured-key',
        callback: ({required query, required apiKey, required count}) async {
          expect(apiKey, 'configured-key');
          return <Map<String, String>>[
            <String, String>{
              'title': 'Brave result',
              'url': 'https://example.com/brave',
              'description': 'Optional provider.',
            },
          ];
        },
      );
      final response = await SearchProviderRouter(
        preferred: brave,
        builtIn: builtInSuccess(),
      ).search(const SearchProviderRequest(query: 'current docs'));
      expect(response.providerId, braveSearchProviderId);
      expect(response.fallbackUsed, isFalse);
      expect(response.results.single.snippet, 'Optional provider.');
    });

    test('optional provider failure falls back to zero-key built-in search',
        () async {
      final brave = BraveSearchProvider(
        apiKey: 'configured-key',
        callback: ({required query, required apiKey, required count}) async {
          throw ProductException('brave_unavailable', 'temporary outage');
        },
      );
      final response = await SearchProviderRouter(
        preferred: brave,
        builtIn: builtInSuccess(),
      ).search(const SearchProviderRequest(query: 'current docs'));
      expect(response.providerId, builtInSearchProviderId);
      expect(response.fallbackUsed, isTrue);
      expect(
          response.providerFailures, contains('brave-api:brave_unavailable'));
    });

    test('all-provider timeout is provider-neutral', () async {
      final router = SearchProviderRouter(
        builtIn: BuiltInDuckDuckGoSearchProvider(
          timeout: const Duration(seconds: 1),
          maxBytes: 4096,
          transport: (_) async {
            throw TimeoutException('offline');
          },
        ),
      );
      await expectLater(
        router.search(const SearchProviderRequest(query: 'current docs')),
        throwsA(
          isA<ProductException>()
              .having((error) => error.code, 'code', 'web_search_unavailable')
              .having(
                (error) => error.message,
                'message',
                'Web search is currently unavailable.',
              ),
        ),
      );
    });
  });

  group('research-search contract and preflight', () {
    test('research_search no longer requires a secret reference', () {
      final contract = const ToolSchemaRegistry().require('research_search');
      expect(contract.requiredArguments, contains('query'));
      expect(contract.requiredArguments, isNot(contains('secretReferenceId')));
      expect(contract.optionalArguments, contains('secretReferenceId'));
    });

    test('zero-key healthy provider satisfies required search preflight',
        () async {
      final fixture = await _preflightFixture(localOnly: false);
      var optionalProviderCalled = false;
      final service = RunPreflightService(
        resolver: const RunCapabilityResolver(),
        modelProbe: _readyModel,
        browserProbe: _readyBrowser,
        builtInResearchSearchProbe: _builtInAvailable,
        researchSearchProbe: (run, requirement) async {
          optionalProviderCalled = true;
          return _probeResult(requirement, false, 'optional unavailable');
        },
        settingsProvider: () => const ProductSettings(localOnly: false),
      );
      final receipt = await service.check(
        run: fixture.run,
        project: fixture.project,
      );
      expect(receipt.verdict, RunPreflightVerdict.ready);
      expect(receipt.blockingFailures, isEmpty);
      expect(optionalProviderCalled, isFalse);
      expect(
        receipt.probes
            .singleWhere((item) => item.key == 'research-search')
            .message,
        'Built-in web search is available.',
      );
    });

    test('local-only mode fails closed before any provider probe', () async {
      final fixture = await _preflightFixture(localOnly: true);
      var builtInCalled = false;
      var optionalCalled = false;
      final service = RunPreflightService(
        resolver: const RunCapabilityResolver(),
        modelProbe: _readyModel,
        browserProbe: _readyBrowser,
        builtInResearchSearchProbe: () async {
          builtInCalled = true;
          return _builtInAvailable();
        },
        researchSearchProbe: (run, requirement) async {
          optionalCalled = true;
          return _probeResult(requirement, true, 'ready');
        },
        settingsProvider: () => const ProductSettings(localOnly: true),
      );
      final receipt = await service.check(
        run: fixture.run,
        project: fixture.project,
      );
      expect(receipt.verdict, RunPreflightVerdict.blocked);
      expect(builtInCalled, isFalse);
      expect(optionalCalled, isFalse);
      expect(receipt.summary, contains('Kristin is in local-only mode'));
    });

    test('configured optional provider can satisfy built-in outage', () async {
      final fixture = await _preflightFixture(localOnly: false);
      final service = RunPreflightService(
        resolver: const RunCapabilityResolver(),
        modelProbe: _readyModel,
        browserProbe: _readyBrowser,
        builtInResearchSearchProbe: _builtInUnavailable,
        researchSearchProbe: (run, requirement) async =>
            _probeResult(requirement, true, 'Brave Search is available.'),
        settingsProvider: () => const ProductSettings(localOnly: false),
      );
      final receipt = await service.check(
        run: fixture.run,
        project: fixture.project,
      );
      expect(receipt.verdict, RunPreflightVerdict.ready);
      expect(
        receipt.probes
            .singleWhere((item) => item.key == 'research-search')
            .message,
        'Web search is available.',
      );
    });

    test('provider outage blocks with provider-neutral diagnostic', () async {
      final fixture = await _preflightFixture(localOnly: false);
      final service = RunPreflightService(
        resolver: const RunCapabilityResolver(),
        modelProbe: _readyModel,
        browserProbe: _readyBrowser,
        builtInResearchSearchProbe: _builtInUnavailable,
        researchSearchProbe: (run, requirement) async => _probeResult(
          requirement,
          false,
          'No Brave Search secret reference is configured.',
        ),
        settingsProvider: () => const ProductSettings(localOnly: false),
      );
      final receipt = await service.check(
        run: fixture.run,
        project: fixture.project,
      );
      expect(receipt.verdict, RunPreflightVerdict.blocked);
      expect(receipt.summary, 'Web search is currently unavailable.');
      expect(receipt.summary, isNot(contains('Brave')));
    });
  });
}

Future<SearchProviderProbe> _builtInAvailable() async =>
    const SearchProviderProbe(
      available: true,
      providerId: builtInSearchProviderId,
      resultCount: 1,
      message: 'Built-in web search is available.',
    );

Future<SearchProviderProbe> _builtInUnavailable() async =>
    const SearchProviderProbe(
      available: false,
      message: 'Web search is currently unavailable.',
    );

RunCapabilityProbeResult _probeResult(
  RunCapabilityRequirement requirement,
  bool ok,
  String message,
) =>
    RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: ok,
      required: requirement.required,
      message: message,
      durationMilliseconds: 1,
    );

Future<RunCapabilityProbeResult> _readyModel(
  ModelIdentity model,
  RunCapabilityRequirement requirement,
) async =>
    _probeResult(requirement, true, 'model ready');

Future<RunCapabilityProbeResult> _readyBrowser(
  RunCapabilityRequirement requirement,
) async =>
    _probeResult(requirement, true, 'browser ready');

Future<({ProjectRecord project, RunRecord run})> _preflightFixture({
  required bool localOnly,
}) async {
  final root = await Directory.systemTemp.createTemp('kristin-free-search-');
  addTearDown(() => root.delete(recursive: true));
  final project = ProjectRecord(
    id: 'project',
    name: 'fixture',
    rootPath: root.path,
    createdAt: DateTime.utc(2026, 8, 24),
    updatedAt: DateTime.utc(2026, 8, 24),
  );
  final model = ModelIdentity(
    providerId: 'ollama',
    name: 'phi4-mini:latest',
    digest: 'fixture',
    discoveredAt: DateTime.utc(2026, 8, 24),
  );
  final contract = TaskContract(
    id: 'contract',
    revision: 2,
    projectId: project.id,
    mode: CommandMode.ask,
    request:
        localOnly ? 'Research current docs locally' : 'Research current docs',
    acceptanceCriteria: const <AcceptanceCriterion>[
      AcceptanceCriterion(
        id: 'criterion',
        statement: 'Current documentation is researched.',
        verification: 'Verify bounded search results.',
      ),
    ],
    constraints: const <String>[],
    researchQuestions: const <String>['What is current?'],
    requiredPermissions: const <PermissionScope>{
      PermissionScope.projectRead,
      PermissionScope.networkResearch,
    },
    createdAt: DateTime.utc(2026, 8, 24),
  );
  final item = WorkItem(
    id: 'work',
    title: 'Research',
    description: 'Search current documentation.',
    dependencies: const <String>{},
    allowedTools: const <String>{'research_search'},
    acceptanceCriteria: const <String>['Search completed.'],
    maxAttempts: 2,
  );
  final command = PreparedCommand(
    id: 'command',
    requestKey: 'fixture',
    contract: contract,
    plan: ExecutionPlan(
      id: 'plan',
      contractId: contract.id,
      complexity: 1,
      rationale: 'fixture',
      items: <WorkItem>[item],
      createdAt: DateTime.utc(2026, 8, 24),
    ),
    model: model,
    createdAt: DateTime.utc(2026, 8, 24),
  );
  final run = RunRecord(
    id: 'run',
    command: command,
    state: RunState.prepared,
    items: <WorkItemProgress>[
      WorkItemProgress(
        item: item,
        state: WorkItemState.queued,
        attempts: 0,
      ),
    ],
    budget: const AutonomyBudget(),
    createdAt: DateTime.utc(2026, 8, 24),
    updatedAt: DateTime.utc(2026, 8, 24),
  );
  return (project: project, run: run);
}
