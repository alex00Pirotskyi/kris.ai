import 'dart:math';

import 'domain.dart';

enum AdaptiveTestKind {
  staticAnalysis,
  unit,
  component,
  integration,
  regression,
  acceptance,
  manual,
}

enum AdaptiveFindingSeverity { info, recommendation, warning, critical }

final class TokenRange {
  const TokenRange({
    required this.low,
    required this.likely,
    required this.high,
  }) : assert(low >= 0),
       assert(likely >= low),
       assert(high >= likely);

  final int low;
  final int likely;
  final int high;

  TokenRange operator +(TokenRange other) => TokenRange(
    low: low + other.low,
    likely: likely + other.likely,
    high: high + other.high,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'low': low,
    'likely': likely,
    'high': high,
  };
}

final class TaskTokenEstimate {
  const TaskTokenEstimate({
    required this.taskId,
    required this.inputTokens,
    required this.outputTokens,
    required this.toolResultTokens,
    required this.totalTokens,
    required this.modelCalls,
    required this.retryProbability,
    required this.contextTokensSaved,
    required this.confidence,
  });

  final String taskId;
  final TokenRange inputTokens;
  final TokenRange outputTokens;
  final TokenRange toolResultTokens;
  final TokenRange totalTokens;
  final TokenRange modelCalls;
  final double retryProbability;
  final int contextTokensSaved;
  final double confidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskId': taskId,
    'inputTokens': inputTokens.toJson(),
    'outputTokens': outputTokens.toJson(),
    'toolResultTokens': toolResultTokens.toJson(),
    'totalTokens': totalTokens.toJson(),
    'modelCalls': modelCalls.toJson(),
    'retryProbability': retryProbability,
    'contextTokensSaved': contextTokensSaved,
    'confidence': confidence,
  };
}

final class MissionTestRecommendation {
  const MissionTestRecommendation({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.taskIds,
    required this.automated,
    required this.priority,
  });

  final String id;
  final AdaptiveTestKind kind;
  final String title;
  final String reason;
  final Set<String> taskIds;
  final bool automated;
  final int priority;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'title': title,
    'reason': reason,
    'taskIds': taskIds.toList()..sort(),
    'automated': automated,
    'priority': priority,
  };
}

final class AdaptivePlanningFinding {
  const AdaptivePlanningFinding({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    this.taskIds = const <String>{},
  });

  final String id;
  final AdaptiveFindingSeverity severity;
  final String title;
  final String detail;
  final Set<String> taskIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'severity': severity.name,
    'title': title,
    'detail': detail,
    'taskIds': taskIds.toList()..sort(),
  };
}

final class AdaptiveMission {
  const AdaptiveMission({
    required this.id,
    required this.title,
    required this.objective,
    required this.taskIds,
    required this.dependencies,
    required this.readyTaskIds,
    required this.criticalTaskIds,
    required this.economics,
    required this.tests,
    required this.risk,
    required this.confidence,
    required this.contextCapsule,
  });

  final String id;
  final String title;
  final String objective;
  final List<String> taskIds;
  final Set<String> dependencies;
  final Set<String> readyTaskIds;
  final Set<String> criticalTaskIds;
  final TokenRange economics;
  final List<MissionTestRecommendation> tests;
  final PlanRisk risk;
  final double confidence;
  final String contextCapsule;

  bool get ready => dependencies.isEmpty && readyTaskIds.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'objective': objective,
    'taskIds': taskIds,
    'dependencies': dependencies.toList()..sort(),
    'readyTaskIds': readyTaskIds.toList()..sort(),
    'criticalTaskIds': criticalTaskIds.toList()..sort(),
    'economics': economics.toJson(),
    'tests': tests.map((item) => item.toJson()).toList(growable: false),
    'risk': risk.name,
    'confidence': confidence,
    'contextCapsule': contextCapsule,
  };
}

final class AdaptiveTaskOptimizationResult {
  const AdaptiveTaskOptimizationResult({
    required this.tasks,
    required this.mergedTaskIds,
    required this.splitTaskIds,
    required this.verificationGateAdded,
    required this.findings,
  });

  final List<PlanTaskRecord> tasks;
  final Set<String> mergedTaskIds;
  final Set<String> splitTaskIds;
  final bool verificationGateAdded;
  final List<AdaptivePlanningFinding> findings;
}

final class AdaptiveMissionPlan {
  const AdaptiveMissionPlan({
    required this.planId,
    required this.missions,
    required this.taskEconomics,
    required this.readyFrontier,
    required this.criticalPath,
    required this.economics,
    required this.tests,
    required this.findings,
    required this.verificationCoverage,
    required this.contextTokensSaved,
    required this.lazyPacketCount,
    required this.prompt,
    required this.plan,
  });

  final String planId;
  final List<AdaptiveMission> missions;
  final Map<String, TaskTokenEstimate> taskEconomics;
  final Set<String> readyFrontier;
  final List<String> criticalPath;
  final TokenRange economics;
  final List<MissionTestRecommendation> tests;
  final List<AdaptivePlanningFinding> findings;
  final double verificationCoverage;
  final int contextTokensSaved;
  final int lazyPacketCount;
  final PromptStudioDraft prompt;
  final TaskPlanRecord plan;

  String runnerPacketFor(String taskId) {
    final task = plan.tasks.where((item) => item.id == taskId).firstOrNull;
    if (task == null) {
      return 'Unknown mission task $taskId.';
    }
    final mission = missions
        .where((item) => item.taskIds.contains(taskId))
        .firstOrNull;
    final estimate = taskEconomics[taskId];
    final testItems = tests
        .where((item) => item.taskIds.contains(taskId))
        .toList(growable: false);
    final readiness = readyFrontier.contains(taskId)
        ? 'READY FRONTIER: materialize and execute this packet now.'
        : 'LAZY PACKET: materialize after its dependencies have objective evidence.';
    final sections = <String>[
      readiness,
      if (mission != null) 'MISSION ${mission.title}\n${mission.contextCapsule}',
      'TASK ${task.id}: ${task.title}',
      if (task.objective.trim().isNotEmpty) 'OUTCOME\n${task.objective.trim()}',
      'INSTRUCTIONS\n${task.instructions.trim()}',
      if (task.dependencies.isNotEmpty)
        'DEPENDENCIES\n${(task.dependencies.toList()..sort()).join(', ')}',
      if (task.acceptanceCriteria.isNotEmpty)
        'DONE WHEN\n${task.acceptanceCriteria.map((item) => '- $item').join('\n')}',
      if (task.verificationSteps.isNotEmpty)
        'VERIFY\n${task.verificationSteps.map((item) => '- $item').join('\n')}',
      if (testItems.isNotEmpty)
        'RISK-BASED TESTS\n${testItems.map((item) => '- ${item.kind.name}: ${item.title}').join('\n')}',
      if (task.expectedArtifacts.isNotEmpty)
        'EXPECTED ARTIFACTS\n${task.expectedArtifacts.map((item) => '- $item').join('\n')}',
      if (estimate != null)
        'TOKEN BUDGET\n${estimate.totalTokens.low}–${estimate.totalTokens.high} estimated total tokens; likely ${estimate.totalTokens.likely}; ${(estimate.confidence * 100).round()}% estimate confidence.',
      'STOP AND REPLAN if the task crosses its high token estimate, requires an unlisted permission, invalidates a prerequisite, or cannot produce objective verification.',
    ];
    final packet = sections
        .where((item) => item.trim().isNotEmpty)
        .join('\n\n')
        .trim();
    return packet.length <= 6200 ? packet : packet.substring(0, 6200).trim();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'planId': planId,
    'missions': missions.map((item) => item.toJson()).toList(growable: false),
    'taskEconomics': taskEconomics.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'readyFrontier': readyFrontier.toList()..sort(),
    'criticalPath': criticalPath,
    'economics': economics.toJson(),
    'tests': tests.map((item) => item.toJson()).toList(growable: false),
    'findings': findings.map((item) => item.toJson()).toList(growable: false),
    'verificationCoverage': verificationCoverage,
    'contextTokensSaved': contextTokensSaved,
    'lazyPacketCount': lazyPacketCount,
  };
}

final class AdaptivePlanningPreviewEstimate {
  const AdaptivePlanningPreviewEstimate({
    required this.planGeneration,
    required this.outputTokens,
    required this.expectedMissionCount,
    required this.expectedTaskCount,
    required this.sharedContextTokens,
    required this.confidence,
  });

  final TokenRange planGeneration;
  final TokenRange outputTokens;
  final int expectedMissionCount;
  final int expectedTaskCount;
  final int sharedContextTokens;
  final double confidence;
}

abstract final class AdaptiveMissionPlanner {
  static const String schemaVersion = 'adaptive-mission-planner.v1';

  static AdaptiveTaskOptimizationResult optimizeTasks({
    required List<PlanTaskRecord> tasks,
    required PromptStudioDraft prompt,
    required int maxTasks,
  }) {
    final safeLimit = maxTasks.clamp(1, 100).toInt();
    final findings = <AdaptivePlanningFinding>[];
    final mergedIds = <String>{};
    final splitIds = <String>{};
    final aliases = <String, String>{};
    final merged = <PlanTaskRecord>[];
    final sanitized = _sanitizeProposedTasks(
      tasks: tasks,
      prompt: prompt,
      findings: findings,
    );

    for (final task in sanitized) {
      PlanTaskRecord? duplicate;
      for (final candidate in merged.reversed) {
        if (_canMerge(candidate, task)) {
          duplicate = candidate;
          break;
        }
      }
      if (duplicate == null) {
        merged.add(task);
        continue;
      }
      final index = merged.indexWhere((item) => item.id == duplicate!.id);
      merged[index] = _mergeTasks(duplicate, task);
      aliases[task.id] = duplicate.id;
      mergedIds.add(task.id);
      findings.add(
        AdaptivePlanningFinding(
          id: 'merged_${task.id}',
          severity: AdaptiveFindingSeverity.info,
          title: 'Merged overlapping runner packets',
          detail:
              '${task.title} repeated the outcome and evidence path of ${duplicate.title}; one packet now carries the combined criteria.',
          taskIds: <String>{duplicate.id, task.id},
        ),
      );
    }

    var normalized = _rewireDependencies(merged, aliases);
    final split = <PlanTaskRecord>[];
    final verificationGateByTask = <String, String>{};
    for (final task in normalized) {
      final canSplit = normalized.length + verificationGateByTask.length < safeLimit;
      if (!_shouldSplit(task) || !canSplit) {
        split.add(task);
        if (_shouldSplit(task) && !canSplit) {
          findings.add(
            AdaptivePlanningFinding(
              id: 'oversized_${task.id}',
              severity: AdaptiveFindingSeverity.warning,
              title: 'Large task retained because the task ceiling is full',
              detail:
                  '${task.title} is likely to exceed a comfortable runner packet. Increase the ceiling or simplify its scope.',
              taskIds: <String>{task.id},
            ),
          );
        }
        continue;
      }
      final verificationId = _uniqueTaskId('${task.id}_verify', <String>{
        ...normalized.map((item) => item.id),
        ...split.map((item) => item.id),
      });
      split.add(_implementationSlice(task));
      split.add(_verificationSlice(task, verificationId));
      verificationGateByTask[task.id] = verificationId;
      splitIds.add(task.id);
      findings.add(
        AdaptivePlanningFinding(
          id: 'split_${task.id}',
          severity: AdaptiveFindingSeverity.recommendation,
          title: 'Separated implementation from proof',
          detail:
              '${task.title} was too broad for one reliable packet. Its verification now gates downstream work.',
          taskIds: <String>{task.id, verificationId},
        ),
      );
    }
    normalized = _rewireVerificationGates(split, verificationGateByTask);

    var verificationGateAdded = false;
    if (!_hasDedicatedVerification(normalized, prompt.mode)) {
      if (normalized.length < safeLimit) {
        normalized = <PlanTaskRecord>[
          ...normalized,
          _finalVerificationTask(normalized, prompt),
        ];
        verificationGateAdded = true;
      } else if (normalized.isNotEmpty) {
        final leafIds = _leafTaskIds(normalized);
        final targetIndex = normalized.lastIndexWhere(
          (item) => leafIds.contains(item.id),
        );
        final index = targetIndex < 0 ? normalized.length - 1 : targetIndex;
        final target = normalized[index];
        normalized = <PlanTaskRecord>[
          ...normalized.take(index),
          target.copyWith(
            allowedTools: <String>{...target.allowedTools, 'verify_project'},
            acceptanceCriteria: _uniqueStrings(<String>[
              ...target.acceptanceCriteria,
              ...prompt.acceptanceCriteria.take(4),
              'The complete enabled plan has objective verification evidence.',
            ], limit: 10),
            verificationSteps: _uniqueStrings(<String>[
              ...target.verificationSteps,
              'Run the detected analyzer, focused tests, regression checks, and build validation for the complete result.',
              'Inspect failure paths and confirm that unresolved limitations are reported rather than presented as passing.',
            ], limit: 10),
          ),
          ...normalized.skip(index + 1),
        ];
        verificationGateAdded = true;
      }
    }

    normalized = _normalizeTaskOrder(normalized.take(safeLimit).toList());
    return AdaptiveTaskOptimizationResult(
      tasks: List<PlanTaskRecord>.unmodifiable(normalized),
      mergedTaskIds: Set<String>.unmodifiable(mergedIds),
      splitTaskIds: Set<String>.unmodifiable(splitIds),
      verificationGateAdded: verificationGateAdded,
      findings: List<AdaptivePlanningFinding>.unmodifiable(findings),
    );
  }

  static List<PlanTaskRecord> _sanitizeProposedTasks({
    required List<PlanTaskRecord> tasks,
    required PromptStudioDraft prompt,
    required List<AdaptivePlanningFinding> findings,
  }) {
    if (tasks.isEmpty) {
      return const <PlanTaskRecord>[];
    }
    final promptText = <String>[
      prompt.title,
      prompt.purpose,
      prompt.systemPrompt,
      prompt.userPrompt,
      ...prompt.assumptions,
      ...prompt.acceptanceCriteria,
      ...prompt.outputExpectations,
      ...prompt.guardrails,
    ].join(' ').toLowerCase();
    final externalResearchRequested = _explicitExternalResearchIntent(promptText);
    final deploymentRequested = _explicitDeploymentIntent(promptText);
    final dropped = <String, PlanTaskRecord>{};

    for (final task in tasks) {
      final taskText = <String>[
        task.phase,
        task.title,
        task.objective,
        task.instructions,
        ...task.expectedArtifacts,
      ].join(' ').toLowerCase();
      final researchTask = task.allowedTools.any(
            const <String>{'research_search', 'research_fetch'}.contains,
          ) ||
          RegExp(
            r'\b(?:research|search the web|web research|online research|official sources?|current sources?|latest sources?)\b',
          ).hasMatch(taskText);
      final deploymentTask = task.allowedTools.contains('package_deployment') ||
          RegExp(
            r'\b(?:deploy(?:ment)?|publish|public hosting|hosting server|production environment|go live|ship live)\b',
          ).hasMatch(taskText);
      if (researchTask && !externalResearchRequested) {
        dropped[task.id] = task;
        findings.add(
          AdaptivePlanningFinding(
            id: 'pruned_research_${task.id}',
            severity: AdaptiveFindingSeverity.info,
            title: 'Removed unrequested external research',
            detail:
                '${task.title} introduced web research that is not part of the approved prompt. Its dependencies are rewired directly so execution does not spend model turns or secrets on invented discovery work.',
            taskIds: <String>{task.id},
          ),
        );
      } else if (deploymentTask && !deploymentRequested) {
        dropped[task.id] = task;
        findings.add(
          AdaptivePlanningFinding(
            id: 'pruned_deployment_${task.id}',
            severity: AdaptiveFindingSeverity.info,
            title: 'Removed unrequested deployment',
            detail:
                '${task.title} introduced hosting or deployment that the approved prompt did not request. Local preview and objective verification remain available without inventing an external release step.',
            taskIds: <String>{task.id},
          ),
        );
      }
    }

    if (dropped.length == tasks.length) {
      return tasks
          .map(
            (task) => _stripUnrequestedCapabilities(
              task,
              externalResearchRequested: externalResearchRequested,
              deploymentRequested: deploymentRequested,
            ),
          )
          .toList(growable: false);
    }

    Set<String> expandDependency(String id, Set<String> visited) {
      if (!visited.add(id)) {
        return const <String>{};
      }
      final removed = dropped[id];
      if (removed == null) {
        return <String>{id};
      }
      return <String>{
        for (final dependency in removed.dependencies)
          ...expandDependency(dependency, <String>{...visited}),
      };
    }

    return tasks.where((task) => !dropped.containsKey(task.id)).map((task) {
      final dependencies = <String>{
        for (final dependency in task.dependencies)
          ...expandDependency(dependency, <String>{}),
      }..remove(task.id);
      final parentId = task.parentId != null && dropped.containsKey(task.parentId)
          ? null
          : task.parentId;
      final rewired = task.copyWith(
        dependencies: dependencies,
        parentId: parentId,
        clearParentId: task.parentId != null && parentId == null,
      );
      return _stripUnrequestedCapabilities(
        rewired,
        externalResearchRequested: externalResearchRequested,
        deploymentRequested: deploymentRequested,
      );
    }).toList(growable: false);
  }

  static PlanTaskRecord _stripUnrequestedCapabilities(
    PlanTaskRecord task, {
    required bool externalResearchRequested,
    required bool deploymentRequested,
  }) {
    final tools = <String>{...task.allowedTools};
    if (!externalResearchRequested) {
      tools.removeAll(const <String>{'research_search', 'research_fetch'});
    }
    if (!deploymentRequested) {
      tools.remove('package_deployment');
    }
    return task.copyWith(allowedTools: tools);
  }

  static bool _explicitExternalResearchIntent(String text) => RegExp(
    r'\b(?:research|search(?: the)? web|look up|lookup|browse online|find (?:current|latest|official) (?:docs?|documentation|sources?|information)|current documentation|latest documentation|official documentation|online sources?)\b',
  ).hasMatch(text.toLowerCase());

  static bool _explicitDeploymentIntent(String text) => RegExp(
    r'\b(?:deploy(?:ment)?|publish|host(?:ing)?|production environment|publicly accessible|public hosting|go live|ship live)\b',
  ).hasMatch(text.toLowerCase());

  static AdaptiveMissionPlan analyzePlan({
    required TaskPlanRecord plan,
    required PromptStudioDraft prompt,
  }) {
    final enabled = plan.tasks.where((item) => item.enabled).toList();
    final readyFrontier = enabled
        .where((item) => item.dependencies.isEmpty)
        .map((item) => item.id)
        .toSet();
    final promptTokens = estimateTextTokens(<String>[
      prompt.purpose,
      prompt.systemPrompt,
      prompt.userPrompt,
      ...prompt.assumptions,
      ...prompt.acceptanceCriteria,
      ...prompt.outputExpectations,
      ...prompt.guardrails,
    ].join('\n'));
    final groups = _missionGroups(enabled);
    final taskEconomics = <String, TaskTokenEstimate>{};
    var contextTokensSaved = 0;
    for (final group in groups) {
      final contextShare = max(90, min(420, promptTokens ~/ max(1, group.length)));
      for (final task in group) {
        final estimate = estimateTask(
          task: task,
          prompt: prompt,
          model: plan.model,
          sharedContextTokens: contextShare,
        );
        taskEconomics[task.id] = estimate;
        contextTokensSaved += estimate.contextTokensSaved;
      }
    }
    final criticalPath = _criticalPath(enabled, taskEconomics);
    final criticalSet = criticalPath.toSet();
    final tests = _testRecommendations(enabled, prompt);
    final missionIndexByTask = <String, String>{};
    for (var index = 0; index < groups.length; index++) {
      for (final task in groups[index]) {
        missionIndexByTask[task.id] = 'mission_${(index + 1).toString().padLeft(2, '0')}';
      }
    }
    final missions = <AdaptiveMission>[];
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final missionId = 'mission_${(index + 1).toString().padLeft(2, '0')}';
      final groupIds = group.map((item) => item.id).toSet();
      final dependencies = group
          .expand((item) => item.dependencies)
          .where((id) => !groupIds.contains(id))
          .map((id) => missionIndexByTask[id])
          .whereType<String>()
          .where((id) => id != missionId)
          .toSet();
      final missionTests = tests
          .where((item) => item.taskIds.any(groupIds.contains))
          .toList(growable: false);
      final economics = group.fold<TokenRange>(
        const TokenRange(low: 0, likely: 0, high: 0),
        (total, task) => total +
            (taskEconomics[task.id]?.totalTokens ??
                const TokenRange(low: 0, likely: 0, high: 0)),
      );
      missions.add(
        AdaptiveMission(
          id: missionId,
          title: _missionTitle(group, index),
          objective: _missionObjective(group),
          taskIds: group.map((item) => item.id).toList(growable: false),
          dependencies: dependencies,
          readyTaskIds: group
              .where((item) => readyFrontier.contains(item.id))
              .map((item) => item.id)
              .toSet(),
          criticalTaskIds: group
              .where((item) => criticalSet.contains(item.id))
              .map((item) => item.id)
              .toSet(),
          economics: economics,
          tests: missionTests,
          risk: group.map((item) => item.risk).reduce(_higherRisk),
          confidence: group
                  .map((item) => item.estimateConfidence)
                  .fold<double>(0, (total, value) => total + value) /
              group.length,
          contextCapsule: _contextCapsule(group, prompt),
        ),
      );
    }
    final economics = taskEconomics.values.fold<TokenRange>(
      const TokenRange(low: 0, likely: 0, high: 0),
      (total, item) => total + item.totalTokens,
    );
    final coverage = _verificationCoverage(enabled, tests);
    final findings = <AdaptivePlanningFinding>[
      ..._analysisFindings(
        tasks: enabled,
        economics: taskEconomics,
        criticalPath: criticalPath,
        coverage: coverage,
      ),
    ];
    return AdaptiveMissionPlan(
      planId: plan.id,
      missions: List<AdaptiveMission>.unmodifiable(missions),
      taskEconomics: Map<String, TaskTokenEstimate>.unmodifiable(taskEconomics),
      readyFrontier: Set<String>.unmodifiable(readyFrontier),
      criticalPath: List<String>.unmodifiable(criticalPath),
      economics: economics,
      tests: List<MissionTestRecommendation>.unmodifiable(tests),
      findings: List<AdaptivePlanningFinding>.unmodifiable(findings),
      verificationCoverage: coverage,
      contextTokensSaved: contextTokensSaved,
      lazyPacketCount: max(0, enabled.length - readyFrontier.length),
      prompt: prompt,
      plan: plan,
    );
  }

  static AdaptivePlanningPreviewEstimate preview({
    required PromptStudioDraft prompt,
    required ModelIdentity model,
    required PlanningDepth depth,
    required int maxTasks,
  }) {
    final promptTokens = estimateTextTokens(prompt.renderForChat());
    final depthFactor = switch (depth) {
      PlanningDepth.compact => 0.68,
      PlanningDepth.detailed => 1.18,
      PlanningDepth.exhaustive => 1.55,
      PlanningDepth.auto => 1.0,
    };
    final complexitySignals = <String>[
      prompt.userPrompt,
      prompt.purpose,
      ...prompt.acceptanceCriteria,
      ...prompt.outputExpectations,
    ].join(' ').toLowerCase();
    final integrationSignals = RegExp(
      r'\b(api|database|storage|network|browser|ble|process|service|integration|migration|security)\b',
    ).allMatches(complexitySignals).length;
    final uiSignals = RegExp(
      r'\b(ui|ux|screen|widget|responsive|accessibility|desktop|mobile)\b',
    ).allMatches(complexitySignals).length;
    final expectedTasks = min(
      maxTasks.clamp(1, 100).toInt(),
      max(1, (2 + integrationSignals * 0.7 + uiSignals * 0.35) * depthFactor)
          .round(),
    );
    final expectedMissions = min(6, max(1, (expectedTasks / 3).ceil()));
    final outputLikely = 360 + expectedTasks * 220 + expectedMissions * 70;
    final modelFactor = _modelPlanningFactor(model);
    final output = TokenRange(
      low: max(420, (outputLikely * 0.70).round()),
      likely: max(560, (outputLikely * modelFactor).round()),
      high: max(900, (outputLikely * (1.28 + expectedTasks * 0.012)).round()),
    );
    final likely = promptTokens + output.likely;
    return AdaptivePlanningPreviewEstimate(
      planGeneration: TokenRange(
        low: max(500, promptTokens + output.low),
        likely: likely,
        high: max(likely, promptTokens + output.high + 180),
      ),
      outputTokens: output,
      expectedMissionCount: expectedMissions,
      expectedTaskCount: expectedTasks,
      sharedContextTokens: min(900, max(120, promptTokens)),
      confidence: (0.86 - expectedTasks * 0.018).clamp(0.48, 0.86).toDouble(),
    );
  }

  static TaskTokenEstimate estimateTask({
    required PlanTaskRecord task,
    required PromptStudioDraft prompt,
    required ModelIdentity model,
    int? sharedContextTokens,
  }) {
    final taskText = <String>[
      task.title,
      task.objective,
      task.instructions,
      ...task.acceptanceCriteria,
      ...task.verificationSteps,
      ...task.expectedArtifacts,
    ].join('\n');
    final taskTokens = estimateTextTokens(taskText);
    final fullPromptTokens = estimateTextTokens(prompt.renderForChat());
    final contextTokens = sharedContextTokens ?? min(420, max(100, fullPromptTokens ~/ 3));
    final toolSchemaTokens = task.allowedTools.length * 52;
    final mutationBonus = task.allowedTools.any(_mutationTool) ? 150 : 0;
    final inputPerTurn = 330 + taskTokens + contextTokens + toolSchemaTokens;
    final outputPerTurn = min(
      1180,
      120 +
          task.complexity * 48 +
          task.expectedArtifacts.length * 45 +
          task.acceptanceCriteria.length * 18 +
          mutationBonus,
    );
    final turns = task.expectedModelTurns.clamp(1, 10).toInt();
    final toolResults = task.expectedToolCalls.clamp(0, 80).toInt() *
        (46 + task.complexity * 11);
    final retryProbability = _retryProbability(task);
    final modelFactor = _modelPlanningFactor(model);
    final baseInput = (inputPerTurn * turns * modelFactor).round();
    final baseOutput = (outputPerTurn * turns * modelFactor).round();
    final baseTotal = baseInput + baseOutput + toolResults;
    final lowTotal = max(180, (baseTotal * 0.70).round());
    final likelyTotal = max(
      lowTotal,
      (baseTotal * (1 + retryProbability * 0.55)).round(),
    );
    final highTotal = max(
      likelyTotal,
      (baseTotal * (1.35 + retryProbability)).round() + 160,
    );
    final callsLikely = max(1, turns);
    final callsHigh = max(callsLikely, (turns * (1 + retryProbability)).ceil());
    return TaskTokenEstimate(
      taskId: task.id,
      inputTokens: TokenRange(
        low: max(90, (baseInput * 0.72).round()),
        likely: baseInput,
        high: max(baseInput, (baseInput * (1.18 + retryProbability)).round()),
      ),
      outputTokens: TokenRange(
        low: max(60, (baseOutput * 0.62).round()),
        likely: baseOutput,
        high: max(baseOutput, (baseOutput * (1.28 + retryProbability)).round()),
      ),
      toolResultTokens: TokenRange(
        low: max(0, (toolResults * 0.55).round()),
        likely: toolResults,
        high: max(toolResults, (toolResults * 1.45).round()),
      ),
      totalTokens: TokenRange(
        low: lowTotal,
        likely: likelyTotal,
        high: highTotal,
      ),
      modelCalls: TokenRange(
        low: max(1, turns - 1),
        likely: callsLikely,
        high: callsHigh,
      ),
      retryProbability: retryProbability,
      contextTokensSaved: max(0, (fullPromptTokens - contextTokens) * turns),
      confidence: (1 - retryProbability * 0.72).clamp(0.35, 0.92).toDouble(),
    );
  }

  static int estimateTextTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    final codeSymbols = RegExp(r'[{}\[\]();=<>_/\\]').allMatches(normalized).length;
    final nonAscii = normalized.runes.where((rune) => rune > 127).length;
    final codeRatio = codeSymbols / max(1, normalized.length);
    final nonAsciiRatio = nonAscii / max(1, normalized.runes.length);
    final charsPerToken = nonAsciiRatio > 0.08
        ? 2.35
        : codeRatio > 0.10
            ? 3.05
            : 3.82;
    final lexicalTokens = RegExp(r'\S+').allMatches(normalized).length;
    return max(1, max((normalized.length / charsPerToken).ceil(), lexicalTokens));
  }

  static List<List<PlanTaskRecord>> _missionGroups(List<PlanTaskRecord> tasks) {
    final orderedPhases = <String>[];
    final byPhase = <String, List<PlanTaskRecord>>{};
    for (final task in tasks) {
      final phase = task.phase.trim().isEmpty ? 'Delivery' : task.phase.trim();
      if (!byPhase.containsKey(phase)) {
        orderedPhases.add(phase);
        byPhase[phase] = <PlanTaskRecord>[];
      }
      byPhase[phase]!.add(task);
    }
    final groups = <List<PlanTaskRecord>>[];
    for (final phase in orderedPhases) {
      final values = byPhase[phase]!;
      for (var start = 0; start < values.length; start += 4) {
        groups.add(values.skip(start).take(4).toList(growable: false));
      }
    }
    return groups;
  }

  static String _missionTitle(List<PlanTaskRecord> group, int index) {
    final phase = group.first.phase.trim();
    if (phase.isNotEmpty) {
      return phase;
    }
    return 'Mission ${index + 1}';
  }

  static String _missionObjective(List<PlanTaskRecord> group) {
    final values = _uniqueStrings(
      group
          .map((item) => item.objective.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      limit: 3,
    );
    return values.isEmpty ? group.first.title : values.join(' · ');
  }

  static String _contextCapsule(
    List<PlanTaskRecord> group,
    PromptStudioDraft prompt,
  ) {
    final artifacts = _uniqueStrings(
      group.expand((item) => item.expectedArtifacts).toList(),
      limit: 6,
    );
    final criteria = _uniqueStrings(
      <String>[
        ...group.expand((item) => item.acceptanceCriteria),
        ...prompt.acceptanceCriteria,
      ],
      limit: 6,
    );
    final capsule = <String>[
      'Outcome: ${_missionObjective(group)}',
      if (artifacts.isNotEmpty) 'Shared artifacts: ${artifacts.join(' | ')}',
      if (criteria.isNotEmpty) 'Shared gates: ${criteria.join(' | ')}',
      if (prompt.guardrails.isNotEmpty)
        'Guardrails: ${prompt.guardrails.take(3).join(' | ')}',
    ].join('\n');
    return capsule.length <= 1100 ? capsule : capsule.substring(0, 1100).trim();
  }

  static List<String> _criticalPath(
    List<PlanTaskRecord> tasks,
    Map<String, TaskTokenEstimate> economics,
  ) {
    final byId = <String, PlanTaskRecord>{for (final task in tasks) task.id: task};
    final score = <String, int>{};
    final previous = <String, String?>{};
    int calculate(String id) {
      final cached = score[id];
      if (cached != null) {
        return cached;
      }
      final task = byId[id];
      if (task == null) {
        return 0;
      }
      var bestDependencyScore = 0;
      String? bestDependency;
      for (final dependency in task.dependencies) {
        final dependencyScore = calculate(dependency);
        if (dependencyScore > bestDependencyScore) {
          bestDependencyScore = dependencyScore;
          bestDependency = dependency;
        }
      }
      final own = economics[id]?.totalTokens.likely ?? 1;
      score[id] = bestDependencyScore + own;
      previous[id] = bestDependency;
      return score[id]!;
    }

    for (final task in tasks) {
      calculate(task.id);
    }
    if (score.isEmpty) {
      return const <String>[];
    }
    var current = score.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final reversed = <String>[];
    while (true) {
      reversed.add(current);
      final dependency = previous[current];
      if (dependency == null) {
        break;
      }
      current = dependency;
    }
    return reversed.reversed.toList(growable: false);
  }

  static List<MissionTestRecommendation> _testRecommendations(
    List<PlanTaskRecord> tasks,
    PromptStudioDraft prompt,
  ) {
    final recommendations = <String, MissionTestRecommendation>{};
    void add(
      AdaptiveTestKind kind,
      String title,
      String reason,
      PlanTaskRecord task, {
      required bool automated,
      required int priority,
    }) {
      final key = '${kind.name}:$title';
      final existing = recommendations[key];
      recommendations[key] = MissionTestRecommendation(
        id: 'test_${kind.name}_${recommendations.length + 1}',
        kind: kind,
        title: title,
        reason: reason,
        taskIds: <String>{...?existing?.taskIds, task.id},
        automated: automated,
        priority: min(existing?.priority ?? priority, priority),
      );
    }

    for (final task in tasks) {
      final text = '${task.title} ${task.objective} ${task.instructions} '
              '${task.expectedArtifacts.join(' ')}'
          .toLowerCase();
      if (_looksLikeCode(text) || task.allowedTools.any(_mutationTool)) {
        add(
          AdaptiveTestKind.staticAnalysis,
          'Analyzer and source-contract checks',
          'Code-producing tasks need fast structural feedback before broader tests.',
          task,
          automated: true,
          priority: 1,
        );
        add(
          AdaptiveTestKind.unit,
          'Focused logic and failure-path tests',
          'Deterministic logic should be isolated from slower integration checks.',
          task,
          automated: true,
          priority: 2,
        );
      }
      if (RegExp(r'\b(ui|ux|widget|screen|dialog|layout|responsive|accessibility)\b')
          .hasMatch(text)) {
        add(
          AdaptiveTestKind.component,
          'Widget state and interaction tests',
          'Visible behavior needs loading, empty, error, keyboard, and interruption coverage.',
          task,
          automated: true,
          priority: 2,
        );
        add(
          AdaptiveTestKind.manual,
          'Focused visual and usability review',
          'Automated tests cannot certify hierarchy, wording, and perceived responsiveness.',
          task,
          automated: false,
          priority: 5,
        );
      }
      if (RegExp(
        r'\b(api|database|storage|file|network|http|browser|process|service|ble|integration|migration)\b',
      ).hasMatch(text)) {
        add(
          AdaptiveTestKind.integration,
          'Boundary integration tests',
          'Cross-component state, cancellation, persistence, and failure propagation need direct coverage.',
          task,
          automated: true,
          priority: 2,
        );
      }
      if (RegExp(r'\b(fix|bug|regression|repair|restore|compatibility)\b')
          .hasMatch(text)) {
        add(
          AdaptiveTestKind.regression,
          'Reproduce the original failure before the fix',
          'A fix is not protected until the observed failure becomes a permanent test.',
          task,
          automated: true,
          priority: 1,
        );
      }
      if (task.risk.index >= PlanRisk.high.index) {
        add(
          AdaptiveTestKind.integration,
          'High-risk boundary, rollback, and interruption tests',
          'High-risk work needs direct proof that partial failure does not corrupt the surrounding mission.',
          task,
          automated: true,
          priority: 1,
        );
        add(
          AdaptiveTestKind.regression,
          'High-risk failure and recovery regressions',
          'The highest-impact failure paths need permanent deterministic protection.',
          task,
          automated: true,
          priority: 1,
        );
      }
      add(
        AdaptiveTestKind.acceptance,
        'Task acceptance and artifact inspection',
        'Every runner packet needs objective evidence bound to its declared outcome.',
        task,
        automated: true,
        priority: 3,
      );
    }
    final allIds = tasks.map((item) => item.id).toSet();
    if (tasks.isNotEmpty) {
      recommendations['acceptance:final'] = MissionTestRecommendation(
        id: 'test_acceptance_final',
        kind: AdaptiveTestKind.acceptance,
        title: 'End-to-end definition-of-done gate',
        reason:
            'The complete plan must satisfy the approved prompt, not merely complete individual packets.',
        taskIds: allIds,
        automated: true,
        priority: 1,
      );
    }
    final sorted = recommendations.values.toList()
      ..sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        return priority != 0 ? priority : a.title.compareTo(b.title);
      });
    return sorted;
  }

  static double _verificationCoverage(
    List<PlanTaskRecord> tasks,
    List<MissionTestRecommendation> tests,
  ) {
    if (tasks.isEmpty) {
      return 0;
    }
    var total = 0.0;
    for (final task in tasks) {
      final required = _requiredTestKinds(task);
      final covered = tests
          .where((test) => test.taskIds.contains(task.id))
          .map((test) => test.kind)
          .toSet();
      final kindCoverage = required.isEmpty
          ? 1.0
          : covered.intersection(required).length / required.length;
      var score = kindCoverage * 0.52;
      if (task.acceptanceCriteria.length >= 2) {
        score += 0.18;
      } else if (task.acceptanceCriteria.isNotEmpty) {
        score += 0.10;
      }
      if (task.verificationSteps.length >= 2) {
        score += 0.18;
      } else if (task.verificationSteps.isNotEmpty) {
        score += 0.10;
      }
      if (task.allowedTools.contains('verify_project') ||
          task.verificationSteps.any(
            (item) => RegExp(
              r'\b(test|verify|analy[sz]e|build|inspect|reproduce)\b',
              caseSensitive: false,
            ).hasMatch(item),
          )) {
        score += 0.12;
      }
      total += min(1.0, score);
    }
    return (total / tasks.length).clamp(0.0, 1.0).toDouble();
  }

  static Set<AdaptiveTestKind> _requiredTestKinds(PlanTaskRecord task) {
    final text = '${task.title} ${task.objective} ${task.instructions} '
            '${task.expectedArtifacts.join(' ')}'
        .toLowerCase();
    final result = <AdaptiveTestKind>{AdaptiveTestKind.acceptance};
    if (_looksLikeCode(text) || task.allowedTools.any(_mutationTool)) {
      result
        ..add(AdaptiveTestKind.staticAnalysis)
        ..add(AdaptiveTestKind.unit);
    }
    if (RegExp(
      r'\b(ui|ux|widget|screen|dialog|layout|responsive|accessibility)\b',
    ).hasMatch(text)) {
      result
        ..add(AdaptiveTestKind.component)
        ..add(AdaptiveTestKind.manual);
    }
    if (RegExp(
      r'\b(api|database|storage|file|network|http|browser|process|service|ble|integration|migration)\b',
    ).hasMatch(text)) {
      result.add(AdaptiveTestKind.integration);
    }
    if (RegExp(r'\b(fix|bug|regression|repair|restore|compatibility)\b')
        .hasMatch(text)) {
      result.add(AdaptiveTestKind.regression);
    }
    if (task.risk.index >= PlanRisk.high.index) {
      result
        ..add(AdaptiveTestKind.integration)
        ..add(AdaptiveTestKind.regression);
    }
    return result;
  }

  static List<AdaptivePlanningFinding> _analysisFindings({
    required List<PlanTaskRecord> tasks,
    required Map<String, TaskTokenEstimate> economics,
    required List<String> criticalPath,
    required double coverage,
  }) {
    final findings = <AdaptivePlanningFinding>[];
    final totalLikely = economics.values.fold<int>(
      0,
      (total, item) => total + item.totalTokens.likely,
    );
    for (final task in tasks) {
      final estimate = economics[task.id];
      if (estimate != null && estimate.totalTokens.high > 18000) {
        findings.add(
          AdaptivePlanningFinding(
            id: 'token_${task.id}',
            severity: AdaptiveFindingSeverity.warning,
            title: 'Task has a wide token envelope',
            detail:
                '${task.title} may use up to ${estimate.totalTokens.high} tokens. Split it or materialize a smaller ready-frontier packet.',
            taskIds: <String>{task.id},
          ),
        );
      }
      if (task.risk.index >= PlanRisk.high.index &&
          task.verificationSteps.length < 2) {
        findings.add(
          AdaptivePlanningFinding(
            id: 'risk_${task.id}',
            severity: AdaptiveFindingSeverity.critical,
            title: 'High-risk task needs deeper proof',
            detail:
                '${task.title} is ${task.risk.name} risk but has fewer than two verification steps.',
            taskIds: <String>{task.id},
          ),
        );
      }
    }
    final criticalLikely = criticalPath.fold<int>(
      0,
      (total, id) => total + (economics[id]?.totalTokens.likely ?? 0),
    );
    if (totalLikely > 0 && criticalLikely / totalLikely > 0.72) {
      findings.add(
        AdaptivePlanningFinding(
          id: 'critical_path_concentration',
          severity: AdaptiveFindingSeverity.recommendation,
          title: 'Most work sits on one critical path',
          detail:
              '${(criticalLikely / totalLikely * 100).round()}% of likely token use is serial. Independent missions could be separated or simplified.',
          taskIds: criticalPath.toSet(),
        ),
      );
    }
    if (coverage < 0.78) {
      findings.add(
        AdaptivePlanningFinding(
          id: 'verification_coverage',
          severity: AdaptiveFindingSeverity.warning,
          title: 'Verification coverage is incomplete',
          detail:
              'Only ${(coverage * 100).round()}% of the planned evidence surface is covered. Add failure-path, integration, or acceptance checks before launch.',
        ),
      );
    }
    if (findings.isEmpty) {
      findings.add(
        const AdaptivePlanningFinding(
          id: 'healthy_plan',
          severity: AdaptiveFindingSeverity.info,
          title: 'Mission graph is balanced',
          detail:
              'Task size, dependency order, token ranges, and verification coverage are within the adaptive planner’s preferred envelope.',
        ),
      );
    }
    return findings;
  }

  static bool _canMerge(PlanTaskRecord a, PlanTaskRecord b) {
    if (a.manual || b.manual || a.phase.trim().toLowerCase() != b.phase.trim().toLowerCase()) {
      return false;
    }
    final similarity = _jaccard(
      _terms('${a.title} ${a.objective}'),
      _terms('${b.title} ${b.objective}'),
    );
    final dependencyDifference = <String>{
      ...a.dependencies.difference(b.dependencies),
      ...b.dependencies.difference(a.dependencies),
    }.length;
    if (dependencyDifference > 1) {
      return false;
    }
    final categoryA = _semanticTaskCategory(a);
    final categoryB = _semanticTaskCategory(b);
    if (categoryA != null && categoryA == categoryB) {
      final artifactSimilarity = _jaccard(
        _terms(a.expectedArtifacts.join(' ')),
        _terms(b.expectedArtifacts.join(' ')),
      );
      if (const <String>{'design', 'verification'}.contains(categoryA) &&
          (similarity >= 0.42 || artifactSimilarity >= 0.34)) {
        return true;
      }
    }
    return similarity >= 0.70;
  }

  static String? _semanticTaskCategory(PlanTaskRecord task) {
    final text = <String>[
      task.phase,
      task.title,
      task.objective,
      task.instructions,
      ...task.expectedArtifacts,
    ].join(' ').toLowerCase();
    if (RegExp(r'\b(?:wireframes?|mockups?|user flows?|ux flows?|screen flows?|prototype|design system)\b')
        .hasMatch(text)) {
      return 'design';
    }
    if (RegExp(r'\b(?:verify|verification|validation|regression|acceptance|test suite|quality gate)\b')
        .hasMatch(text)) {
      return 'verification';
    }
    if (RegExp(r'\b(?:research|search the web|online research|official sources?)\b')
        .hasMatch(text)) {
      return 'research';
    }
    if (RegExp(r'\b(?:deploy|deployment|publish|hosting|production environment)\b')
        .hasMatch(text)) {
      return 'deployment';
    }
    return null;
  }

  static PlanTaskRecord _mergeTasks(PlanTaskRecord a, PlanTaskRecord b) {
    return a.copyWith(
      title: a.title.length <= b.title.length ? a.title : b.title,
      objective: _joinUnique(a.objective, b.objective, limit: 560),
      instructions: _joinUnique(a.instructions, b.instructions, limit: 1800),
      dependencies: <String>{...a.dependencies, ...b.dependencies}
        ..remove(a.id)
        ..remove(b.id),
      acceptanceCriteria: _uniqueStrings(<String>[
        ...a.acceptanceCriteria,
        ...b.acceptanceCriteria,
      ], limit: 12),
      verificationSteps: _uniqueStrings(<String>[
        ...a.verificationSteps,
        ...b.verificationSteps,
      ], limit: 12),
      expectedArtifacts: _uniqueStrings(<String>[
        ...a.expectedArtifacts,
        ...b.expectedArtifacts,
      ], limit: 12),
      allowedTools: <String>{...a.allowedTools, ...b.allowedTools},
      complexity: max(a.complexity, b.complexity),
      effortPoints: _effortPoint(a.effortPoints + b.effortPoints),
      uncertainty: a.uncertainty.index >= b.uncertainty.index
          ? a.uncertainty
          : b.uncertainty,
      risk: _higherRisk(a.risk, b.risk),
      estimateConfidence: min(a.estimateConfidence, b.estimateConfidence),
      expectedModelTurns: min(8, max(a.expectedModelTurns, b.expectedModelTurns) + 1),
      expectedToolCalls: min(80, max(a.expectedToolCalls, b.expectedToolCalls) + 2),
      maxAttempts: max(a.maxAttempts, b.maxAttempts),
      enabled: a.enabled || b.enabled,
    );
  }

  static List<PlanTaskRecord> _rewireDependencies(
    List<PlanTaskRecord> tasks,
    Map<String, String> aliases,
  ) {
    String resolve(String id) {
      var current = id;
      final visited = <String>{};
      while (aliases.containsKey(current) && visited.add(current)) {
        current = aliases[current]!;
      }
      return current;
    }

    return tasks
        .map(
          (task) => task.copyWith(
            parentId: task.parentId == null ? null : resolve(task.parentId!),
            dependencies: task.dependencies
                .map(resolve)
                .where((id) => id != task.id)
                .toSet(),
          ),
        )
        .toList(growable: false);
  }

  static bool _shouldSplit(PlanTaskRecord task) {
    if (task.manual || task.verificationSteps.length < 2) {
      return false;
    }
    final text = '${task.title} ${task.objective} ${task.instructions}'.toLowerCase();
    final implementation = RegExp(
      r'\b(build|implement|create|develop|fix|refactor|migrate|redesign|integrate)\b',
    ).hasMatch(text);
    return implementation &&
        (task.complexity >= 8 ||
            task.expectedModelTurns >= 7 ||
            task.expectedToolCalls >= 24);
  }

  static PlanTaskRecord _implementationSlice(PlanTaskRecord task) {
    final implementationCriteria = task.acceptanceCriteria
        .where(
          (item) => !RegExp(
            r'\b(test|verify|validation|coverage|pass)\b',
            caseSensitive: false,
          ).hasMatch(item),
        )
        .toList();
    return task.copyWith(
      acceptanceCriteria: implementationCriteria.isEmpty
          ? <String>['${task.title} produces its declared inspectable artifacts.']
          : implementationCriteria.take(6).toList(growable: false),
      verificationSteps: <String>[
        'Inspect the produced artifacts before the dedicated verification packet runs.',
      ],
      complexity: max(2, task.complexity - 1),
      effortPoints: _effortPoint(max(1, task.effortPoints - 2)),
      expectedModelTurns: max(2, task.expectedModelTurns - 2),
      expectedToolCalls: max(2, (task.expectedToolCalls * 0.72).round()),
      maxAttempts: min(2, task.maxAttempts),
    );
  }

  static PlanTaskRecord _verificationSlice(
    PlanTaskRecord task,
    String verificationId,
  ) {
    return PlanTaskRecord(
      id: verificationId,
      phase: task.phase,
      parentId: task.parentId,
      title: 'Verify ${task.title}',
      objective:
          'Prove the implementation satisfies its acceptance criteria and fails safely.',
      instructions:
          'Run the smallest risk-based test set that covers the changed behavior, then inspect the declared artifacts and failure paths. Record exact limitations instead of treating missing evidence as passing.',
      dependencies: <String>{task.id},
      acceptanceCriteria: _uniqueStrings(<String>[
        ...task.acceptanceCriteria,
        'The original task has objective verification evidence.',
      ], limit: 10),
      verificationSteps: _uniqueStrings(<String>[
        ...task.verificationSteps,
        'Exercise at least one relevant failure or interruption path.',
        'Run the detected project verification command and inspect its exact result.',
      ], limit: 10),
      expectedArtifacts: <String>[
        'Verification evidence for ${task.title}',
        ...task.expectedArtifacts.take(5),
      ],
      allowedTools: <String>{
        ...task.allowedTools,
        'inspect_file',
        'verify_project',
      },
      complexity: max(2, task.complexity - 3),
      effortPoints: _effortPoint(max(2, min(5, task.effortPoints ~/ 2))),
      uncertainty: task.uncertainty == PlanUncertainty.high
          ? PlanUncertainty.medium
          : task.uncertainty,
      risk: task.risk,
      estimateConfidence: min(0.95, task.estimateConfidence + 0.08),
      expectedModelTurns: 2,
      expectedToolCalls: max(3, (task.expectedToolCalls * 0.32).round()),
      maxAttempts: 1,
      enabled: task.enabled,
      manual: false,
    );
  }

  static List<PlanTaskRecord> _rewireVerificationGates(
    List<PlanTaskRecord> tasks,
    Map<String, String> gateByTask,
  ) {
    return tasks.map((task) {
      final dependencies = task.dependencies.map((dependency) {
        final gate = gateByTask[dependency];
        if (gate == null || gate == task.id) {
          return dependency;
        }
        return gate;
      }).toSet();
      return task.copyWith(dependencies: dependencies);
    }).toList(growable: false);
  }

  static bool _hasDedicatedVerification(
    List<PlanTaskRecord> tasks,
    CommandMode mode,
  ) {
    if (!const <CommandMode>{CommandMode.build, CommandMode.fix}.contains(mode)) {
      return true;
    }
    return tasks.any((task) {
      final text = '${task.phase} ${task.title} ${task.objective}'.toLowerCase();
      final verificationFocused = RegExp(
        r'\b(test|verify|validation|quality|regression|acceptance|proof)\b',
      ).hasMatch(text);
      return verificationFocused &&
          (task.allowedTools.contains('verify_project') ||
              task.verificationSteps.length >= 2);
    });
  }

  static PlanTaskRecord _finalVerificationTask(
    List<PlanTaskRecord> tasks,
    PromptStudioDraft prompt,
  ) {
    final ids = tasks.map((item) => item.id).toSet();
    final id = _uniqueTaskId('task_final_verification', ids);
    final leafIds = _leafTaskIds(tasks);
    return PlanTaskRecord(
      id: id,
      phase: 'Verification',
      parentId: null,
      title: 'Validate the complete result',
      objective:
          'Prove the integrated result satisfies the approved prompt and remains honest about unsupported behavior.',
      instructions:
          'Run analyzer, focused unit and integration tests, regression checks, and the detected build verification. Inspect the final artifacts and exercise relevant error, cancellation, and empty-state paths.',
      dependencies: leafIds,
      acceptanceCriteria: _uniqueStrings(<String>[
        ...prompt.acceptanceCriteria,
        'All enabled mission outcomes have objective evidence.',
        'Known limitations and unperformed manual checks remain explicit.',
      ], limit: 10),
      verificationSteps: <String>[
        'Run the detected project analyzer, tests, and build checks.',
        'Inspect the final diff or artifacts against the approved definition of done.',
        'Exercise at least one material failure, interruption, or recovery path.',
      ],
      expectedArtifacts: const <String>[
        'Final verification report',
        'Bounded failure-path evidence',
      ],
      allowedTools: const <String>{'inspect_file', 'verify_project'},
      complexity: 4,
      effortPoints: 3,
      uncertainty: PlanUncertainty.low,
      risk: tasks.isEmpty
          ? PlanRisk.low
          : tasks.map((item) => item.risk).reduce(_higherRisk),
      estimateConfidence: 0.82,
      expectedModelTurns: 2,
      expectedToolCalls: 6,
      maxAttempts: 1,
      enabled: true,
      manual: false,
    );
  }

  static Set<String> _leafTaskIds(List<PlanTaskRecord> tasks) {
    final dependedOn = tasks.expand((item) => item.dependencies).toSet();
    return tasks
        .where((item) => item.enabled && !dependedOn.contains(item.id))
        .map((item) => item.id)
        .toSet();
  }

  static List<PlanTaskRecord> _normalizeTaskOrder(List<PlanTaskRecord> tasks) {
    final byId = <String, PlanTaskRecord>{for (final task in tasks) task.id: task};
    final emitted = <String>{};
    final ordered = <PlanTaskRecord>[];
    while (ordered.length < tasks.length) {
      final next = tasks.where((task) {
        return !emitted.contains(task.id) &&
            task.dependencies.every(
              (dependency) => emitted.contains(dependency) || !byId.containsKey(dependency),
            );
      }).firstOrNull;
      if (next == null) {
        return tasks;
      }
      ordered.add(next);
      emitted.add(next.id);
    }
    return ordered;
  }

  static double _retryProbability(PlanTaskRecord task) {
    final uncertainty = switch (task.uncertainty) {
      PlanUncertainty.low => 0.07,
      PlanUncertainty.medium => 0.19,
      PlanUncertainty.high => 0.34,
    };
    final risk = switch (task.risk) {
      PlanRisk.low => 0.03,
      PlanRisk.medium => 0.10,
      PlanRisk.high => 0.23,
      PlanRisk.critical => 0.38,
    };
    final confidencePenalty = (1 - task.estimateConfidence) * 0.34;
    final sizePenalty = max(0, task.complexity - 6) * 0.025;
    return (uncertainty + risk + confidencePenalty + sizePenalty)
        .clamp(0.04, 0.72)
        .toDouble();
  }

  static double _modelPlanningFactor(ModelIdentity model) {
    final parameter = model.parameterSize.toUpperCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*B').firstMatch(parameter);
    final billions = double.tryParse(match?.group(1) ?? '') ?? 4.0;
    final quantization = model.quantization.toUpperCase();
    final quantizedDiscount = quantization.contains('Q4')
        ? 0.94
        : quantization.contains('Q8')
            ? 1.02
            : 1.0;
    return (1 + max(0.0, billions - 4) * 0.018) * quantizedDiscount;
  }

  static PlanRisk _higherRisk(PlanRisk a, PlanRisk b) =>
      a.index >= b.index ? a : b;

  static bool _mutationTool(String name) => const <String>{
    'write_file',
    'replace_text',
    'apply_patch',
  }.contains(name);

  static bool _looksLikeCode(String text) => RegExp(
    r'\b(code|class|function|method|module|dart|flutter|python|javascript|typescript|c\+\+|firmware|implementation|refactor|compile|build)\b',
  ).hasMatch(text);

  static Set<String> _terms(String value) {
    const ignored = <String>{
      'a',
      'an',
      'and',
      'the',
      'to',
      'of',
      'for',
      'with',
      'in',
      'on',
      'task',
      'implement',
      'create',
      'build',
    };
    return RegExp(r'[a-z0-9_]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => term.length > 2 && !ignored.contains(term))
        .toSet();
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final intersection = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : intersection / union;
  }

  static String _joinUnique(String a, String b, {required int limit}) {
    final left = a.trim();
    final right = b.trim();
    final value = left.isEmpty
        ? right
        : right.isEmpty || left.contains(right)
            ? left
            : '$left\n$right';
    return value.length <= limit ? value : value.substring(0, limit).trim();
  }

  static List<String> _uniqueStrings(
    List<String> values, {
    required int limit,
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) {
        continue;
      }
      result.add(trimmed);
      if (result.length >= limit) {
        break;
      }
    }
    return result;
  }

  static int _effortPoint(int value) {
    const values = <int>[1, 2, 3, 5, 8, 13];
    return values.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }

  static String _uniqueTaskId(String candidate, Set<String> used) {
    if (!used.contains(candidate)) {
      return candidate;
    }
    var suffix = 2;
    while (used.contains('${candidate}_$suffix')) {
      suffix++;
    }
    return '${candidate}_$suffix';
  }
}
