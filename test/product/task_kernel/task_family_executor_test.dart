import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_doctor.dart';
import 'package:kristin_local_agent/product/task_kernel/kernel_task_graph_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_families.dart';
import 'package:kristin_local_agent/product/task_kernel/task_family_executor.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

void main() {
  test('research executes retrieval verification and synthesis as graph nodes', () async {
    final specification = TaskSpecification(
      id: 'spec-research',
      originalRequest: 'Compare current Flutter and Dart release information.',
      objective: 'Compare current Flutter and Dart release information.',
      subObjectives: const <String>[
        'current Flutter release information',
        'current Dart release information',
      ],
    );
    final plan = await const ResearchTaskFamilyPlanner().plan(
      specification: specification,
      route: PlanningRoute.compact,
      context: const PlanningContext(
        availableCapabilityIds: <String>{'research.search'},
      ),
    );
    final searches = <String>[];
    final states = <String, List<KernelTaskNodeState>>{};

    final result = await const ResearchTaskFamilyExecutor().execute(
      plan: plan,
      onStateChanged: (node) =>
          (states[node.taskId] ??= <KernelTaskNodeState>[]).add(node.state),
      search: (query) async {
        searches.add(query);
        return <Map<String, String>>[
          <String, String>{
            'title': 'Source ${searches.length}',
            'url': 'https://example.test/${searches.length}',
            'snippet': query,
          },
        ];
      },
      synthesize: (request, sources) async {
        expect(request, specification.originalRequest);
        expect(sources, hasLength(2));
        return 'Grounded comparison from ${sources.length} sources.';
      },
    );

    expect(searches, hasLength(2));
    expect(result.graph.succeeded, isTrue);
    expect(result.sources, hasLength(2));
    expect(result.answer, contains('2 sources'));
    expect(
      states['research_fact_1'],
      containsAllInOrder(<KernelTaskNodeState>[
        KernelTaskNodeState.queued,
        KernelTaskNodeState.running,
        KernelTaskNodeState.succeeded,
      ]),
    );
  });

  test('diagnostics collects one real report and propagates it through graph', () async {
    final specification = TaskSpecification(
      id: 'spec-diagnostics',
      originalRequest: 'Why is Kristin unhealthy?',
      objective: 'Explain current Kristin health.',
    );
    final plan = await const DiagnosticsTaskFamilyPlanner().plan(
      specification: specification,
      route: PlanningRoute.compact,
      context: const PlanningContext(
        availableCapabilityIds: <String>{'system.diagnose'},
      ),
    );
    var collections = 0;

    final result = await const DiagnosticsTaskFamilyExecutor().execute(
      plan: plan,
      collect: () async {
        collections++;
        return CapabilityDoctorReport(
          depth: CapabilityDoctorDepth.full,
          checkedAt: DateTime.utc(2026, 8, 31),
          checks: const <CapabilityDoctorCheck>[
            CapabilityDoctorCheck(
              id: 'model',
              title: 'Model',
              status: CapabilityDoctorStatus.ready,
              message: 'Connected.',
              required: true,
            ),
            CapabilityDoctorCheck(
              id: 'browser',
              title: 'Browser',
              status: CapabilityDoctorStatus.warning,
              message: 'Browser runtime is unavailable.',
              required: false,
            ),
          ],
        );
      },
    );

    expect(collections, 1);
    expect(result.graph.succeeded, isTrue);
    expect(result.report.warningCount, 1);
    expect(result.answer, contains('Browser runtime is unavailable'));
    expect(
      result.graph.results['diagnostics_collect']!.evidence['report'],
      isA<Map>(),
    );
  });
}
