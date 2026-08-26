import 'crypto_utils.dart';
import 'domain.dart';
import 'execution_intelligence.dart';

enum AdaptiveDecompositionReason {
  noProgress,
  complexityGrowth,
}

enum AdaptiveDecompositionDisposition {
  none,
  continueAutomatically,
  requireUserApproval,
  stopEquivalentLoop,
}

class AdaptivePlanMateriality {
  const AdaptivePlanMateriality({
    this.architectureChanged = false,
    this.technologyChanged = false,
    this.externalServiceChanged = false,
    this.scopeChanged = false,
    this.permissionsChanged = false,
    this.destructiveBehaviorChanged = false,
    this.costChanged = false,
    this.deploymentChanged = false,
    this.securityBoundaryChanged = false,
    this.userVisibleDesignChanged = false,
  });

  final bool architectureChanged;
  final bool technologyChanged;
  final bool externalServiceChanged;
  final bool scopeChanged;
  final bool permissionsChanged;
  final bool destructiveBehaviorChanged;
  final bool costChanged;
  final bool deploymentChanged;
  final bool securityBoundaryChanged;
  final bool userVisibleDesignChanged;

  bool get material =>
      architectureChanged ||
      technologyChanged ||
      externalServiceChanged ||
      scopeChanged ||
      permissionsChanged ||
      destructiveBehaviorChanged ||
      costChanged ||
      deploymentChanged ||
      securityBoundaryChanged ||
      userVisibleDesignChanged;

  List<String> get reasons => <String>[
        if (architectureChanged) 'architecture',
        if (technologyChanged) 'technology',
        if (externalServiceChanged) 'external service',
        if (scopeChanged) 'scope',
        if (permissionsChanged) 'permissions',
        if (destructiveBehaviorChanged) 'destructive behavior',
        if (costChanged) 'cost',
        if (deploymentChanged) 'deployment',
        if (securityBoundaryChanged) 'security boundary',
        if (userVisibleDesignChanged) 'user-visible design',
      ];
}

class AdaptiveDecompositionRequest {
  const AdaptiveDecompositionRequest({
    required this.plan,
    required this.progress,
    required this.convergenceDecision,
    required this.semanticProgress,
    required this.productiveRepairs,
    required this.discoveredSubproblems,
    required this.proposedRemainingItems,
    required this.materiality,
    required this.generation,
    this.previousRemainingCriteriaHashes = const <String>{},
  });

  final ExecutionPlan plan;
  final List<WorkItemProgress> progress;
  final ConvergenceDecision convergenceDecision;
  final bool semanticProgress;
  final int productiveRepairs;
  final int discoveredSubproblems;
  final List<WorkItem> proposedRemainingItems;
  final AdaptivePlanMateriality materiality;
  final int generation;
  final Set<String> previousRemainingCriteriaHashes;
}

class AdaptiveDecompositionDecision {
  const AdaptiveDecompositionDecision({
    required this.disposition,
    required this.reason,
    required this.completedItems,
    required this.remainingItems,
    required this.remainingCriteriaHash,
    required this.generation,
    required this.userMessage,
    required this.materiality,
  });

  final AdaptiveDecompositionDisposition disposition;
  final AdaptiveDecompositionReason? reason;
  final List<WorkItem> completedItems;
  final List<WorkItem> remainingItems;
  final String remainingCriteriaHash;
  final int generation;
  final String userMessage;
  final AdaptivePlanMateriality materiality;

  bool get triggered => disposition != AdaptiveDecompositionDisposition.none;
  bool get requiresApproval =>
      disposition == AdaptiveDecompositionDisposition.requireUserApproval;
  bool get mayContinue =>
      disposition == AdaptiveDecompositionDisposition.continueAutomatically;
}

class AdaptiveDecompositionService {
  const AdaptiveDecompositionService({
    this.complexityRepairThreshold = 4,
    this.complexitySubproblemThreshold = 3,
    this.maxGenerations = 4,
  });

  final int complexityRepairThreshold;
  final int complexitySubproblemThreshold;
  final int maxGenerations;

  AdaptiveDecompositionDecision decide(AdaptiveDecompositionRequest request) {
    final completed = request.progress
        .where((item) => item.state == WorkItemState.succeeded)
        .map((item) => item.item)
        .toList(growable: false);
    final completedIds = completed.map((item) => item.id).toSet();
    final currentRemaining = request.plan.items
        .where((item) => !completedIds.contains(item.id))
        .toList(growable: false);

    final stuck = !request.semanticProgress &&
        (request.convergenceDecision.action == ConvergenceAction.splitTask ||
            request.convergenceDecision.action ==
                ConvergenceAction.failConvergence);
    final complexityGrowth = request.semanticProgress &&
        request.productiveRepairs >= complexityRepairThreshold &&
        request.discoveredSubproblems >= complexitySubproblemThreshold &&
        request.proposedRemainingItems.length > currentRemaining.length;

    if (!stuck && !complexityGrowth) {
      return AdaptiveDecompositionDecision(
        disposition: AdaptiveDecompositionDisposition.none,
        reason: null,
        completedItems: completed,
        remainingItems: currentRemaining,
        remainingCriteriaHash: _remainingHash(currentRemaining),
        generation: request.generation,
        userMessage: '',
        materiality: request.materiality,
      );
    }

    final proposed = request.proposedRemainingItems.isEmpty
        ? currentRemaining
        : _preserveCompletedDependencies(
            completedIds: completedIds,
            items: request.proposedRemainingItems,
          );
    final remainingHash = _remainingHash(proposed);
    final nextGeneration = request.generation + 1;
    final equivalent =
        request.previousRemainingCriteriaHashes.contains(remainingHash);
    if (equivalent || nextGeneration > maxGenerations) {
      return AdaptiveDecompositionDecision(
        disposition: AdaptiveDecompositionDisposition.stopEquivalentLoop,
        reason: stuck
            ? AdaptiveDecompositionReason.noProgress
            : AdaptiveDecompositionReason.complexityGrowth,
        completedItems: completed,
        remainingItems: proposed,
        remainingCriteriaHash: remainingHash,
        generation: nextGeneration,
        userMessage:
            'I am not making new objective progress with another equivalent decomposition. Completed work is preserved, and this remaining part needs a different decision before continuing.',
        materiality: request.materiality,
      );
    }

    if (request.materiality.material) {
      final changed = request.materiality.reasons.join(', ');
      return AdaptiveDecompositionDecision(
        disposition: AdaptiveDecompositionDisposition.requireUserApproval,
        reason: stuck
            ? AdaptiveDecompositionReason.noProgress
            : AdaptiveDecompositionReason.complexityGrowth,
        completedItems: completed,
        remainingItems: proposed,
        remainingCriteriaHash: remainingHash,
        generation: nextGeneration,
        userMessage:
            'This turned out to be more involved than the original plan. The revised approach changes $changed, so I need your approval before continuing.',
        materiality: request.materiality,
      );
    }

    return AdaptiveDecompositionDecision(
      disposition: AdaptiveDecompositionDisposition.continueAutomatically,
      reason: stuck
          ? AdaptiveDecompositionReason.noProgress
          : AdaptiveDecompositionReason.complexityGrowth,
      completedItems: completed,
      remainingItems: proposed,
      remainingCriteriaHash: remainingHash,
      generation: nextGeneration,
      userMessage: stuck
          ? 'I am having trouble making reliable progress with this part, so I am breaking the remaining work into smaller steps.'
          : 'This part is more involved than expected, so I am breaking the remaining work into smaller steps to keep progress reliable.',
      materiality: request.materiality,
    );
  }

  List<WorkItem> _preserveCompletedDependencies({
    required Set<String> completedIds,
    required List<WorkItem> items,
  }) {
    final proposedIds = items.map((item) => item.id).toSet();
    return items.map((item) {
      final dependencies = item.dependencies
          .where((id) => proposedIds.contains(id) || completedIds.contains(id))
          .toSet();
      return WorkItem(
        id: item.id,
        title: item.title,
        description: item.description,
        dependencies: dependencies,
        allowedTools: item.allowedTools,
        acceptanceCriteria: item.acceptanceCriteria,
        maxAttempts: item.maxAttempts,
      );
    }).toList(growable: false);
  }

  String _remainingHash(List<WorkItem> items) {
    final normalized = items
        .map(
          (item) => <String, dynamic>{
            'title': item.title.trim().toLowerCase(),
            'description': item.description.trim().toLowerCase(),
            'acceptanceCriteria': item.acceptanceCriteria
                .map((criterion) => criterion.trim().toLowerCase())
                .toList()
              ..sort(),
            'allowedTools': item.allowedTools.toList()..sort(),
          },
        )
        .toList();
    return Sha256.text(canonicalJson(normalized));
  }
}
