import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/adaptive_decomposition.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';

void main() {
  const service = AdaptiveDecompositionService();
  const splitter = AdaptiveWorkItemSplitter();

  WorkItem item(
    String id,
    String title, {
    Set<String> dependencies = const <String>{},
    List<String>? criteria,
  }) {
    return WorkItem(
      id: id,
      title: title,
      description: 'Implement $title reliably.',
      dependencies: dependencies,
      allowedTools: const <String>{'read_file', 'write_file'},
      acceptanceCriteria:
          criteria ?? <String>['$title is objectively verified.'],
    );
  }

  ExecutionPlan plan(List<WorkItem> items) => ExecutionPlan(
        id: 'plan-1',
        contractId: 'contract-1',
        complexity: 7,
        rationale: 'test',
        items: items,
        createdAt: DateTime.utc(2026, 8, 26),
      );

  WorkItemProgress progress(WorkItem item, WorkItemState state) =>
      WorkItemProgress(item: item, state: state, attempts: 1);

  test('productive repairs alone do not trigger decomposition', () {
    final first = item('a', 'Create app');
    final second = item('b', 'Implement backend', dependencies: <String>{'a'});
    final decision = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[first, second]),
        progress: <WorkItemProgress>[
          progress(first, WorkItemState.succeeded),
          progress(second, WorkItemState.running),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.continueExecution,
          reason: 'progress',
          stalledTurns: 0,
        ),
        semanticProgress: true,
        productiveRepairs: 8,
        discoveredSubproblems: 1,
        proposedRemainingItems: <WorkItem>[second],
        materiality: const AdaptivePlanMateriality(),
        generation: 0,
      ),
    );
    expect(decision.disposition, AdaptiveDecompositionDisposition.none);
    expect(decision.completedItems.map((item) => item.id), contains('a'));
  });

  test('no-progress split signal decomposes remaining work automatically', () {
    final done = item('a', 'Create app');
    final coarse = item('b', 'Implement backend', dependencies: <String>{'a'});
    final route = item('b1', 'Implement booking route');
    final validation = item(
      'b2',
      'Validate booking input',
      dependencies: <String>{'b1'},
    );
    final decision = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[done, coarse]),
        progress: <WorkItemProgress>[
          progress(done, WorkItemState.succeeded),
          progress(coarse, WorkItemState.failed),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.splitTask,
          reason: 'stuck',
          stalledTurns: 4,
        ),
        semanticProgress: false,
        productiveRepairs: 0,
        discoveredSubproblems: 2,
        proposedRemainingItems: <WorkItem>[route, validation],
        materiality: const AdaptivePlanMateriality(),
        generation: 0,
      ),
    );
    expect(
      decision.disposition,
      AdaptiveDecompositionDisposition.continueAutomatically,
    );
    expect(decision.reason, AdaptiveDecompositionReason.noProgress);
    expect(decision.completedItems.map((item) => item.id), <String>['a']);
    expect(
      decision.remainingItems.map((item) => item.id),
      <String>['b1', 'b2'],
    );
    expect(decision.userMessage, contains('smaller steps'));
  });

  test('complexity growth can decompose while progress remains healthy', () {
    final coarse = item('backend', 'Implement backend');
    final pieces = <WorkItem>[
      item('route', 'Implement route'),
      item('validation', 'Implement validation'),
      item('persistence', 'Implement persistence'),
      item('tests', 'Implement tests'),
    ];
    final decision = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[coarse]),
        progress: <WorkItemProgress>[
          progress(coarse, WorkItemState.running),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.continueExecution,
          reason: 'productive',
          stalledTurns: 0,
        ),
        semanticProgress: true,
        productiveRepairs: 6,
        discoveredSubproblems: 4,
        proposedRemainingItems: pieces,
        materiality: const AdaptivePlanMateriality(),
        generation: 0,
      ),
    );
    expect(
      decision.disposition,
      AdaptiveDecompositionDisposition.continueAutomatically,
    );
    expect(decision.reason, AdaptiveDecompositionReason.complexityGrowth);
  });

  test('material architecture change waits for user approval', () {
    final coarse = item('db', 'Implement local persistence');
    final hosted = item('hosted', 'Connect hosted database');
    final decision = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[coarse]),
        progress: <WorkItemProgress>[
          progress(coarse, WorkItemState.failed),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.splitTask,
          reason: 'stuck',
          stalledTurns: 4,
        ),
        semanticProgress: false,
        productiveRepairs: 0,
        discoveredSubproblems: 2,
        proposedRemainingItems: <WorkItem>[hosted],
        materiality: const AdaptivePlanMateriality(
          architectureChanged: true,
          externalServiceChanged: true,
        ),
        generation: 0,
      ),
    );
    expect(
      decision.disposition,
      AdaptiveDecompositionDisposition.requireUserApproval,
    );
    expect(decision.requiresApproval, isTrue);
    expect(decision.userMessage, contains('architecture'));
    expect(decision.userMessage, contains('external service'));
  });

  test('equivalent remaining decomposition cannot loop forever', () {
    final coarse = item('backend', 'Implement backend');
    final split = item('route', 'Implement route');
    final first = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[coarse]),
        progress: <WorkItemProgress>[
          progress(coarse, WorkItemState.failed),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.splitTask,
          reason: 'stuck',
          stalledTurns: 4,
        ),
        semanticProgress: false,
        productiveRepairs: 0,
        discoveredSubproblems: 1,
        proposedRemainingItems: <WorkItem>[split],
        materiality: const AdaptivePlanMateriality(),
        generation: 0,
      ),
    );
    final repeated = service.decide(
      AdaptiveDecompositionRequest(
        plan: plan(<WorkItem>[coarse]),
        progress: <WorkItemProgress>[
          progress(coarse, WorkItemState.failed),
        ],
        convergenceDecision: const ConvergenceDecision(
          action: ConvergenceAction.splitTask,
          reason: 'stuck',
          stalledTurns: 4,
        ),
        semanticProgress: false,
        productiveRepairs: 0,
        discoveredSubproblems: 1,
        proposedRemainingItems: <WorkItem>[split],
        materiality: const AdaptivePlanMateriality(),
        generation: first.generation,
        previousRemainingCriteriaHashes: <String>{
          first.remainingCriteriaHash,
        },
      ),
    );
    expect(
      repeated.disposition,
      AdaptiveDecompositionDisposition.stopEquivalentLoop,
    );
    expect(repeated.completedItems, isEmpty);
  });

  test('single-objective splitter preserves downstream dependency identity', () {
    final coarse = item(
      'backend',
      'Implement backend',
      dependencies: <String>{'baseline'},
    );
    final pieces = splitter.split(coarse, generation: 1);

    expect(pieces.length, 2);
    expect(pieces.first.id, 'backend__adaptive_1_1');
    expect(pieces.first.dependencies, <String>{'baseline'});
    expect(pieces.last.id, 'backend');
    expect(pieces.last.dependencies, <String>{'backend__adaptive_1_1'});
    expect(pieces.every((piece) => piece.allowedTools == coarse.allowedTools), isTrue);
  });

  test('multi-criterion splitter chains at most three verifiable pieces', () {
    final coarse = item(
      'feature',
      'Implement feature',
      criteria: const <String>[
        'First behavior is objectively verified.',
        'Second behavior is objectively verified.',
        'Third behavior is objectively verified.',
        'Fourth behavior is objectively verified.',
      ],
    );
    final pieces = splitter.split(coarse, generation: 2);

    expect(pieces.length, 3);
    expect(pieces[0].id, 'feature__adaptive_2_1');
    expect(pieces[1].id, 'feature__adaptive_2_2');
    expect(pieces[2].id, 'feature');
    expect(pieces[1].dependencies, <String>{pieces[0].id});
    expect(pieces[2].dependencies, <String>{pieces[1].id});
    expect(pieces[2].acceptanceCriteria.length, 2);
  });

  test('remaining criteria hash ignores replacement ids', () {
    final left = item('one', 'Implement route');
    final right = item('two', 'Implement route');

    expect(
      service.remainingCriteriaHash(<WorkItem>[left]),
      service.remainingCriteriaHash(<WorkItem>[right]),
    );
  });
}
