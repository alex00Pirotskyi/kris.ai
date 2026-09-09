import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/product_error_normalizer.dart';
import 'package:kristin_local_agent/product/research_search_provider.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/kernel_task_graph_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_families.dart';
import 'package:kristin_local_agent/product/task_kernel/task_family_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

/// A provider that always fails with the code it was given, so the router's
/// aggregation can be observed without any network.
class _AlwaysFailingProvider implements SearchProvider {
  const _AlwaysFailingProvider(this.id, this.code);

  @override
  final String id;
  final String code;

  @override
  Future<List<SearchProviderResult>> search(SearchProviderRequest request) =>
      throw ProductException(code, 'Provider $id refused the request.');
}

void main() {
  UniversalTaskPlan researchPlan(List<UniversalTask> tasks) =>
      UniversalTaskPlan(
        id: 'plan',
        specification: TaskSpecification(
          id: 'spec',
          originalRequest: 'what is the weather in nha trang today',
          objective: 'Answer the weather question from public sources.',
        ),
        family: TaskFamily.research,
        route: PlanningRoute.compact,
        title: 'Research',
        rationale: 'test',
        tasks: tasks,
      );

  group('kernel task failure summaries', () {
    test('a failed node does not repeat its code inside the summary', () async {
      final plan = researchPlan(const <UniversalTask>[
        UniversalTask(
          id: 'retrieve',
          title: 'Retrieve',
          objective: 'Retrieve evidence.',
          instructions: 'Retrieve evidence.',
          acceptanceCriteria: <String>['Evidence exists.'],
          verificationSteps: <String>['Inspect evidence.'],
        ),
      ]);

      final result = await const KernelTaskGraphExecutor().execute(
        plan: plan,
        executeNode: (task, dependencies) async => throw ProductException(
          'web_search_unavailable',
          'Web search is currently unavailable.',
        ),
      );

      final failed = result.results['retrieve']!;
      expect(failed.state, KernelTaskNodeState.failed);
      expect(failed.failureCode, 'web_search_unavailable');
      // The code belongs to failureCode alone; ProductException.toString()
      // would have smuggled a second copy in here.
      expect(failed.summary, 'Web search is currently unavailable.');
      expect(failed.summary, isNot(contains('web_search_unavailable')));
    });

    test('a non-ProductException failure still records its full text',
        () async {
      final plan = researchPlan(const <UniversalTask>[
        UniversalTask(
          id: 'retrieve',
          title: 'Retrieve',
          objective: 'Retrieve evidence.',
          instructions: 'Retrieve evidence.',
          acceptanceCriteria: <String>['Evidence exists.'],
          verificationSteps: <String>['Inspect evidence.'],
        ),
      ]);

      final result = await const KernelTaskGraphExecutor().execute(
        plan: plan,
        executeNode: (task, dependencies) async =>
            throw StateError('transport exploded'),
      );

      final failed = result.results['retrieve']!;
      expect(failed.failureCode, 'kernel_task_executor_failed');
      expect(failed.summary, contains('transport exploded'));
    });
  });

  group('surfaced research failure text', () {
    test('a search failure reaches the user with its code stated once',
        () async {
      final plan = await const ResearchTaskFamilyPlanner().plan(
        specification: TaskSpecification(
          id: 'spec',
          originalRequest: 'what is the weather in nha trang today',
          objective: 'Answer the weather question from public sources.',
        ),
        route: PlanningRoute.compact,
        context: const PlanningContext(
          availableCapabilityIds: <String>{'research.search'},
        ),
      );

      Object? thrown;
      try {
        await const ResearchTaskFamilyExecutor().execute(
          plan: plan,
          search: (query) async => throw ProductException(
            'web_search_unavailable',
            'Web search is currently unavailable.',
          ),
          synthesize: (request, sources) async => 'unused',
        );
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ProductException>());
      final surfaced = ProductErrorNormalizer.userMessage(thrown!);
      expect(
        surfaced,
        'web_search_unavailable: Web search is currently unavailable.',
      );
      // The defect this pins: the code appeared twice in the banner.
      expect(
        'web_search_unavailable'.allMatches(surfaced).length,
        1,
      );
    });
  });

  group('web search unavailability reports why', () {
    test('the failure names every provider that refused', () async {
      final router = SearchProviderRouter(
        preferred: const _AlwaysFailingProvider(
          'brave-api',
          'search_provider_not_configured',
        ),
        builtIn: const _AlwaysFailingProvider(
          'duckduckgo-html',
          'search_provider_rate_limited',
        ),
      );

      await expectLater(
        router.search(const SearchProviderRequest(query: 'weather', count: 3)),
        throwsA(
          isA<ProductException>()
              .having((error) => error.code, 'code', 'web_search_unavailable')
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('search_provider_not_configured'),
                  contains('search_provider_rate_limited'),
                  // Neutral about which provider was tried.
                  isNot(contains('brave-api')),
                  isNot(contains('duckduckgo-html')),
                ),
              )
              .having(
            (error) => error.details['providerFailures'],
            'providerFailures',
            <String>[
              'brave-api:search_provider_not_configured',
              'duckduckgo-html:search_provider_rate_limited',
            ],
          ),
        ),
      );
    });

    test('a cancelled search is never reported as unavailable', () async {
      final router = SearchProviderRouter(
        builtIn: const _AlwaysFailingProvider('duckduckgo-html', 'cancelled'),
      );

      await expectLater(
        router.search(const SearchProviderRequest(query: 'weather', count: 3)),
        throwsA(
          isA<ProductException>()
              .having((error) => error.code, 'code', 'cancelled'),
        ),
      );
    });
  });

  group('search credential recognition', () {
    int rankOf(String environmentKey, {String label = '', String note = ''}) =>
        BraveSearchCredentialSelector.rank(
          environmentKey: environmentKey,
          label: label,
          description: note,
        );

    test('the canonical environment key is the strongest match', () {
      expect(rankOf('BRAVE_SEARCH_API_KEY'), 0);
      expect(rankOf('brave_search_api_key'), 0);
    });

    test('a reference described as brave search is recognised', () {
      expect(rankOf('SEARCH_KEY', label: 'Brave Search'), 1);
      expect(rankOf('KEY', note: 'brave search credential'), 1);
    });

    test('a reference mentioning only brave is still usable', () {
      expect(rankOf('KEY', label: 'Brave'), 2);
      expect(
        BraveSearchCredentialSelector.matches(
          environmentKey: 'KEY',
          label: 'Brave',
          description: '',
        ),
        isTrue,
      );
    });

    test('an unrelated credential is never selected for search', () {
      expect(
        rankOf('OPENAI_API_KEY', label: 'Model key', note: 'for generation'),
        BraveSearchCredentialSelector.unrelated,
      );
      expect(
        BraveSearchCredentialSelector.matches(
          environmentKey: 'OPENAI_API_KEY',
          label: 'Model key',
          description: 'for generation',
        ),
        isFalse,
      );
    });
  });
}
