#!/usr/bin/env python3
"""Apply safe scope-changing steering continuation/replanning.

This transformer builds on apply_semantic_durable_steering.py. Scope-changing
steering is persisted, allowed to reach only a verified between-work-item
boundary, commits the source run transaction there, replans/reconciles through
the UniversalTaskKernel, and creates a linked continuation run that starts in
awaitingApproval under a new command id. No authority is inherited.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def git_head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


CONTEXT_SOURCE = r'''import '../domain.dart';
import 'task_specification.dart';
import 'universal_task_plan.dart';

/// Durable canonical planning context for a prepared command.
///
/// PreparedCommand intentionally carries the executable projection only. A
/// steering replan also needs the semantic specification and canonical plan
/// that produced it, so they are persisted separately under the command id.
class CommandPlanningContextRecord {
  const CommandPlanningContextRecord({
    required this.commandId,
    required this.projectId,
    required this.specification,
    required this.family,
    required this.route,
    required this.routingRationale,
    required this.canonicalPlan,
    required this.consumedCoordinatorCapabilities,
    required this.createdAt,
    required this.updatedAt,
  });

  final String commandId;
  final String projectId;
  final TaskSpecification specification;
  final TaskFamily family;
  final PlanningRoute route;
  final String routingRationale;
  final UniversalTaskPlan canonicalPlan;
  final Set<String> consumedCoordinatorCapabilities;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get id => commandId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'commandId': commandId,
        'projectId': projectId,
        'specification': specification.toJson(),
        'family': family.name,
        'route': route.name,
        'routingRationale': routingRationale,
        'canonicalPlan': canonicalPlan.toJson(),
        'consumedCoordinatorCapabilities':
            consumedCoordinatorCapabilities.toList()..sort(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory CommandPlanningContextRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return CommandPlanningContextRecord(
      commandId: json['commandId']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      specification:
          TaskSpecification.fromJson(mapValue(json['specification'])),
      family: TaskFamily.values
              .where((value) => value.name == json['family']?.toString())
              .firstOrNull ??
          TaskFamily.software,
      route: PlanningRoute.values
              .where((value) => value.name == json['route']?.toString())
              .firstOrNull ??
          PlanningRoute.graph,
      routingRationale: json['routingRationale']?.toString() ?? '',
      canonicalPlan:
          UniversalTaskPlan.fromJson(mapValue(json['canonicalPlan'])),
      consumedCoordinatorCapabilities:
          stringList(json['consumedCoordinatorCapabilities']).toSet(),
      createdAt: parseUtc(json['createdAt'], fallback: now),
      updatedAt: parseUtc(json['updatedAt'], fallback: now),
    );
  }
}
'''


TEST_SOURCE = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String planning;
  late String runtime;
  late String storage;
  late String steering;
  late String specification;

  setUpAll(() {
    planning = File('lib/product/planning_runtime.dart').readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
    storage = File('lib/product/storage_security.dart').readAsStringSync();
    steering = File('lib/product/run_steering.dart').readAsStringSync();
    specification =
        File('lib/product/task_kernel/task_specification.dart').readAsStringSync();
  });

  test('scope steering stops only at a verified task boundary', () {
    expect(planning, contains('_interruptAtSteeringReplanBoundary('));
    expect(planning, contains('await transaction.commit();'));
    final verification = planning.indexOf('_deterministicVerification(');
    final finalBoundary = planning.lastIndexOf('_interruptAtSteeringReplanBoundary(');
    expect(verification, greaterThanOrEqualTo(0));
    expect(finalBoundary, greaterThan(verification));
    expect(
      planning,
      contains('steering_replan_requested: Scope changed after a verified task boundary.'),
    );
    expect(planning, contains("'run.steering_replan_boundary'"));
    expect(planning, contains('attachSteeringReplanHandler'));
  });

  test('replan uses canonical context and reconciliation', () {
    expect(storage, contains('commandPlanningContexts'));
    expect(runtime, contains('CommandPlanningContextRecord'));
    expect(runtime, contains('taskKernel.reconcile('));
    expect(runtime, contains('CompletedTaskRecord.of('));
    expect(runtime, contains('createContinuationRun('));
    expect(runtime, contains('sourceRunId: source.id'));
    expect(runtime, contains('reconciliation.plan.enabledTasks.isEmpty'));
    expect(runtime, contains("title: 'Verify reconciled project state'"));
    expect(runtime, contains('plan: executablePlan'));
  });

  test('continuation never inherits authority implicitly', () {
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('requiredPermissions'));
    expect(runtime, isNot(contains('permissions.grant(')));
    expect(steering, contains('continuationRunId'));
  });

  test('scope directives remain user intent, not permission claims', () {
    expect(specification, contains('scopeDirectives'));
    expect(specification, contains('applyForReplan('));
    expect(steering, contains("'steering_authority_claim_rejected'"));
  });
}
'''


def transform_task_spec(src: str) -> str:
    src = rep(
        src,
        "    this.addedProhibitedEffects = const <String>[],\n    this.requiresReplan = false,\n",
        "    this.addedProhibitedEffects = const <String>[],\n    this.scopeDirectives = const <String>[],\n    this.authorityClaimRejected = false,\n    this.requiresReplan = false,\n",
        "patch scope constructor",
    )
    src = rep(
        src,
        "  final List<String> addedProhibitedEffects;\n  final bool requiresReplan;\n",
        "  final List<String> addedProhibitedEffects;\n  final List<String> scopeDirectives;\n  final bool authorityClaimRejected;\n  final bool requiresReplan;\n",
        "patch scope field",
    )
    src = rep(
        src,
        "      return TaskSpecificationPatch(\n        sourceText: value,\n        requiresReplan: true,\n      );\n",
        "      return TaskSpecificationPatch(\n        sourceText: value,\n        authorityClaimRejected: true,\n      );\n",
        "patch authority classification",
    )
    src = rep(
        src,
        "        addedProhibitedEffects: <String>[value],\n      );\n",
        "        addedProhibitedEffects: <String>[value],\n        requiresReplan: true,\n      );\n",
        "hard constraint requires replan",
    )
    src = rep(
        src,
        "    // An unclassified imperative can change topology or deliverables. It is\n    // intentionally not injected into a reviewed plan as an opaque sentence.\n    return TaskSpecificationPatch(sourceText: value, requiresReplan: true);\n",
        "    // An unclassified imperative can change topology or deliverables. It\n    // becomes explicit user-stated scope for a reviewed replan, never an\n    // opaque executor hint.\n    return TaskSpecificationPatch(\n      sourceText: value,\n      scopeDirectives: <String>[value],\n      requiresReplan: true,\n    );\n",
        "patch scope classification",
    )
    anchor = "  String renderForExecutor() {\n"
    method = r'''  TaskSpecification applyForReplan(TaskSpecification specification) {
    final safe = TaskSpecificationPatch(
      sourceText: sourceText,
      addedHardConstraints: addedHardConstraints,
      addedPreferences: addedPreferences,
      addedSuccessCriteria: addedSuccessCriteria,
      addedProhibitedEffects: addedProhibitedEffects,
    ).applyTo(specification);
    if (scopeDirectives.isEmpty) return safe;
    return safe.copyWith(
      subObjectives: <String>{
        ...safe.subObjectives,
        ...scopeDirectives,
      }.toList(growable: false),
      contextRefs: <String>{
        ...safe.contextRefs,
        'steering-scope:${Sha256.text(sourceText)}',
      }.toList(growable: false),
    );
  }

'''
    src = rep(src, anchor, method + anchor, "patch apply replan method")
    src = rep(
        src,
        "        'addedProhibitedEffects': addedProhibitedEffects,\n        'requiresReplan': requiresReplan,\n",
        "        'addedProhibitedEffects': addedProhibitedEffects,\n        'scopeDirectives': scopeDirectives,\n        'authorityClaimRejected': authorityClaimRejected,\n        'requiresReplan': requiresReplan,\n",
        "patch scope json",
    )
    src = rep(
        src,
        "      addedProhibitedEffects: stringList(json['addedProhibitedEffects']),\n      requiresReplan: json['requiresReplan'] == true,\n",
        "      addedProhibitedEffects: stringList(json['addedProhibitedEffects']),\n      scopeDirectives: stringList(json['scopeDirectives']),\n      authorityClaimRejected: json['authorityClaimRejected'] == true,\n      requiresReplan: json['requiresReplan'] == true,\n",
        "patch scope from json",
    )
    return src


def transform_record(src: str) -> str:
    src = rep(
        src,
        "enum RunSteeringRecordState { pending, applied, cleared }\n",
        "enum RunSteeringRecordState { pending, replanning, applied, cleared }\n",
        "steering states",
    )
    src = rep(
        src,
        "    this.workItemId,\n    this.appliedAt,\n",
        "    this.workItemId,\n    this.appliedAt,\n    this.continuationRunId,\n    this.reconciliation = const <Map<String, dynamic>>[],\n",
        "steering continuation constructor",
    )
    src = rep(
        src,
        "  final String? workItemId;\n  final DateTime? appliedAt;\n",
        "  final String? workItemId;\n  final DateTime? appliedAt;\n  final String? continuationRunId;\n  final List<Map<String, dynamic>> reconciliation;\n",
        "steering continuation fields",
    )
    src = rep(
        src,
        "    DateTime? appliedAt,\n  }) =>\n",
        "    DateTime? appliedAt,\n    String? continuationRunId,\n    List<Map<String, dynamic>>? reconciliation,\n  }) =>\n",
        "steering copy params",
    )
    src = rep(
        src,
        "        appliedAt: appliedAt ?? this.appliedAt,\n      );\n",
        "        appliedAt: appliedAt ?? this.appliedAt,\n        continuationRunId: continuationRunId ?? this.continuationRunId,\n        reconciliation: reconciliation ?? this.reconciliation,\n      );\n",
        "steering copy values",
    )
    src = rep(
        src,
        "        if (appliedAt != null) 'appliedAt': appliedAt!.toIso8601String(),\n      };\n",
        "        if (appliedAt != null) 'appliedAt': appliedAt!.toIso8601String(),\n        if (continuationRunId != null) 'continuationRunId': continuationRunId,\n        if (reconciliation.isNotEmpty) 'reconciliation': reconciliation,\n      };\n",
        "steering json continuation",
    )
    src = rep(
        src,
        "        appliedAt: _date(json['appliedAt']),\n      );\n",
        "        appliedAt: _date(json['appliedAt']),\n        continuationRunId: _nullable(json['continuationRunId']),\n        reconciliation: (json['reconciliation'] is List\n                ? json['reconciliation'] as List\n                : const <Object>[])\n            .whereType<Map>()\n            .map((value) => mapValue(value))\n            .toList(growable: false),\n      );\n",
        "steering json parse continuation",
    )
    return src


def transform_steering(src: str) -> str:
    src = rep(
        src,
        "    required this.patch,\n    required this.createdAt,\n  });\n",
        "    required this.patch,\n    required this.createdAt,\n    this.continuationRunId,\n    this.reconciliationSummary = '',\n  });\n",
        "instruction continuation ctor",
    )
    src = rep(
        src,
        "  final TaskSpecificationPatch patch;\n  final DateTime createdAt;\n",
        "  final TaskSpecificationPatch patch;\n  final DateTime createdAt;\n  final String? continuationRunId;\n  final String reconciliationSummary;\n",
        "instruction continuation fields",
    )
    src = rep(
        src,
        "        'createdAt': createdAt.toIso8601String(),\n      };\n",
        "        'createdAt': createdAt.toIso8601String(),\n        if (continuationRunId != null) 'continuationRunId': continuationRunId,\n        if (reconciliationSummary.isNotEmpty)\n          'reconciliationSummary': reconciliationSummary,\n      };\n",
        "instruction continuation json",
    )
    src = rep(
        src,
        "        createdAt: record.createdAt,\n      );\n",
        "        createdAt: record.createdAt,\n        continuationRunId: record.continuationRunId,\n        reconciliationSummary: record.reconciliation.isEmpty\n            ? ''\n            : _reconciliationSummary(record.reconciliation),\n      );\n",
        "instruction continuation from record",
    )
    src = rep(
        src,
        "    if (patch.requiresReplan) {\n      throw ProductException(\n        'steering_requires_replan',\n        'This direction changes task scope and needs a reviewed replan before it can change an active run.',\n        details: <String, dynamic>{\n          'runId': runId,\n          'patch': patch.toJson(),\n          'grantsAuthority': false,\n        },\n      );\n    }\n",
        "    if (patch.authorityClaimRejected) {\n      throw ProductException(\n        'steering_authority_claim_rejected',\n        'Steering can change task intent, but it cannot grant or widen authority.',\n        details: <String, dynamic>{\n          'runId': runId,\n          'patch': patch.toJson(),\n          'grantsAuthority': false,\n        },\n      );\n    }\n",
        "allow scope replan queue",
    )
    src = rep(
        src,
        "          'patch': instruction.patch.toJson(),\n          'authorityBearing': false,\n        },\n",
        "          'patch': instruction.patch.toJson(),\n          'authorityBearing': false,\n          'requiresReplan': instruction.patch.requiresReplan,\n        },\n",
        "queued steering signal replan flag",
    )
    src = rep(
        src,
        "            record.state == RunSteeringRecordState.pending)\n",
        "            record.state == RunSteeringRecordState.pending &&\n            !record.patch.requiresReplan)\n",
        "exclude replan patches from executor takePending",
    )
    anchor = "  Future<void> clear(String runId) async {\n"
    method = r'''  Future<List<RunSteeringInstruction>> pendingReplan(String runId) async {
    final values = (await repository.all())
        .where((record) =>
            record.runId == runId &&
            const <RunSteeringRecordState>{
              RunSteeringRecordState.pending,
              RunSteeringRecordState.replanning,
            }.contains(record.state) &&
            record.patch.requiresReplan)
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return values.map(RunSteeringInstruction.fromRecord).toList(growable: false);
  }

  Future<void> markReplanning(
    String runId,
    Iterable<RunSteeringInstruction> instructions,
  ) async {
    for (final instruction in instructions) {
      final record = await repository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) continue;
      await repository.put(record.copyWith(state: RunSteeringRecordState.replanning));
    }
  }

  Future<void> markContinuationReady(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    required String continuationRunId,
    required List<Map<String, dynamic>> reconciliation,
  }) async {
    final now = DateTime.now().toUtc();
    for (final instruction in instructions) {
      final record = await repository.get(instruction.id);
      if (record == null || record.runId != runId) continue;
      await repository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          continuationRunId: continuationRunId,
          reconciliation: reconciliation,
          appliedAt: now,
        ),
      );
    }
  }

'''
    src = rep(src, anchor, method + anchor, "steering continuation methods")
    # Add summary helper before end of file.
    src = src.rstrip() + r'''

String _reconciliationSummary(List<Map<String, dynamic>> values) {
  final counts = <String, int>{};
  for (final value in values) {
    final outcome = value['outcome']?.toString() ?? '';
    if (outcome.isNotEmpty) counts[outcome] = (counts[outcome] ?? 0) + 1;
  }
  final parts = <String>[
    if ((counts['preserved'] ?? 0) > 0) '${counts['preserved']} preserved',
    if ((counts['invalidated'] ?? 0) > 0) '${counts['invalidated']} invalidated',
    if ((counts['added'] ?? 0) > 0) '${counts['added']} added',
    if ((counts['removed'] ?? 0) > 0) '${counts['removed']} removed',
  ];
  return parts.isEmpty ? 'Plan reconciled.' : parts.join(', ');
}
'''
    return src


def transform_storage(src: str) -> str:
    src = rep(
        src,
        "import 'run_steering_record.dart';\n",
        "import 'run_steering_record.dart';\nimport 'task_kernel/command_planning_context.dart';\n",
        "storage command context import",
    )
    src = rep(
        src,
        "    required this.runSteeringRecords,\n",
        "    required this.runSteeringRecords,\n    required this.commandPlanningContexts,\n",
        "storage command context ctor",
    )
    src = rep(
        src,
        "  final EntityRepository<RunSteeringRecord> runSteeringRecords;\n",
        "  final EntityRepository<RunSteeringRecord> runSteeringRecords;\n  final EntityRepository<CommandPlanningContextRecord> commandPlanningContexts;\n",
        "storage command context field",
    )
    block = """      runSteeringRecords: collection<RunSteeringRecord>(\n        name: 'run_steering_records',\n        fromJson: RunSteeringRecord.fromJson,\n        toJson: (value) => value.toJson(),\n        idOf: (value) => value.id,\n      ),\n"""
    src = rep(
        src,
        block,
        block + """      commandPlanningContexts: collection<CommandPlanningContextRecord>(\n        name: 'command_planning_contexts',\n        fromJson: CommandPlanningContextRecord.fromJson,\n        toJson: (value) => value.toJson(),\n        idOf: (value) => value.id,\n      ),\n""",
        "storage command context collection",
    )
    return src


def transform_planning(src: str) -> str:
    src = rep(
        src,
        "  final RunSteeringService steering;\n  final ProjectResourceLocks _locks = ProjectResourceLocks();\n",
        "  final RunSteeringService steering;\n  Future<void> Function(RunRecord source)? _steeringReplanHandler;\n  final ProjectResourceLocks _locks = ProjectResourceLocks();\n",
        "coordinator steering callback field",
    )
    anchor = "  Future<void> reconcileInterruptedRuns() async {\n"
    method = r'''  void attachSteeringReplanHandler(
    Future<void> Function(RunRecord source) handler,
  ) {
    _steeringReplanHandler = handler;
  }

  Future<RunRecord> createContinuationRun(
    PreparedCommand command, {
    required String sourceRunId,
  }) =>
      _createFreshRun(
        command,
        budget: AutonomyBudget.forPlan(command.plan),
        sourceRunId: sourceRunId,
      );

'''
    src = rep(src, anchor, method + anchor, "coordinator continuation API")
    # At every between-item boundary, interrupt/replan before a new task starts.
    src = rep(
        src,
        "        run = (await repositories.runs.get(run.id)) ?? run;\n        final progress = run.items[itemIndex];\n",
        "        run = (await repositories.runs.get(run.id)) ?? run;\n        final steeringBoundary = await _interruptAtSteeringReplanBoundary(\n          run,\n          transaction,\n        );\n        if (steeringBoundary != null) return steeringBoundary;\n        final progress = run.items[itemIndex];\n",
        "between-item steering boundary",
    )
    src = rep(
        src,
        "      }\n      await transaction.commit();\n      run = run.copyWith(\n        state: RunState.succeeded,\n",
        "      }\n      final finalSteeringBoundary = await _interruptAtSteeringReplanBoundary(\n        run,\n        transaction,\n      );\n      if (finalSteeringBoundary != null) return finalSteeringBoundary;\n      await transaction.commit();\n      run = run.copyWith(\n        state: RunState.succeeded,\n",
        "post-verification steering boundary",
    )
    # Prevent old plan from being resumed after a crash between boundary and continuation materialization.
    src = rep(
        src,
        "    await _throwIfDeferredInteractionPending(run.id);\n    if (run.state != RunState.awaitingApproval &&\n",
        "    await _throwIfDeferredInteractionPending(run.id);\n    final pendingReplan = await steering.pendingReplan(run.id);\n    if (run.state == RunState.interrupted && pendingReplan.isNotEmpty) {\n      throw ProductException(\n        'steering_continuation_required',\n        'This run stopped at a safe steering boundary and must continue through its reconciled plan.',\n        details: <String, dynamic>{\n          'runId': run.id,\n          'instructionIds': pendingReplan.map((value) => value.id).toList(),\n          'grantsAuthority': false,\n        },\n      );\n    }\n    if (run.state != RunState.awaitingApproval &&\n",
        "old plan resume gate",
    )
    src = rep(
        src,
        "      final requestNumber = current.modelRequests + 1;\n",
        r'''      final replanSteering = await steering.pendingReplan(current.id);
      final immediateConstraintGuidance = replanSteering
          .map((instruction) => instruction.patch.renderForExecutor().trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (immediateConstraintGuidance.isNotEmpty) {
        final envelope = AgentContextEnvelope(
          source: AgentContextSource.user,
          trust: AgentContextTrust.userIntent,
          content: immediateConstraintGuidance.map((value) => '- $value').join('\n'),
          metadata: const <String, Object?>{
            'authorityBearing': false,
            'pendingPlanReconciliation': true,
          },
        );
        user = '$user\n\nNEW USER CONSTRAINTS PENDING PLAN RECONCILIATION\n'
            '${envelope.render()}\nRespect these constraints immediately for future '
            'decisions in this work item. They grant no authority. The task '
            'graph will be reconciled at the next verified work-item boundary.';
      }
      final requestNumber = current.modelRequests + 1;
''',
        "immediate constraint guidance before reconciliation boundary",
    )
    # Add boundary implementation before _failBeforeTransaction.
    anchor2 = "  Future<RunRecord> _failBeforeTransaction(\n"
    boundary = r'''  Future<RunRecord?> _interruptAtSteeringReplanBoundary(
    RunRecord run,
    WorkspaceTransaction transaction,
  ) async {
    final pending = await steering.pendingReplan(run.id);
    if (pending.isEmpty) return null;
    await steering.markReplanning(run.id, pending);
    if (!transaction.isCommitted) {
      // This method is called only between verified work items (or after the
      // final item). Committing here establishes a clean continuation base and
      // never blesses an in-flight, unverified mutation.
      await transaction.commit();
    }
    final now = DateTime.now().toUtc();
    final interrupted = run.copyWith(
      state: RunState.interrupted,
      completedAt: now,
      failure: 'steering_replan_requested: Scope changed after a verified task boundary.',
    );
    await _save(interrupted);
    try {
      await permissions.revokeForCommand(interrupted.command.id);
    } catch (_) {}
    final evidence = <String, dynamic>{
      'runId': interrupted.id,
      'instructionIds': pending.map((value) => value.id).toList(),
      'committedWorkspace': true,
      'verifiedBoundaryOnly': true,
      'authorityInherited': false,
    };
    await _bestEffortAudit('run.steering_replan_boundary', interrupted.id, evidence);
    await _bestEffortEvent('run.steering_replan_boundary', interrupted.id, evidence);
    liveSignals.publish(
      LiveRunSignal.phase(
        runId: interrupted.id,
        phase: 'replanning',
        message: 'Scope changed. Replanning from verified completed work.',
      ),
    );
    final handler = _steeringReplanHandler;
    if (handler != null) {
      await handler(interrupted);
    }
    return interrupted;
  }

'''
    src = rep(src, anchor2, boundary + anchor2, "steering boundary implementation")
    return src


def transform_runtime(src: str) -> str:
    src = rep(
        src,
        "import 'run_steering.dart';\n",
        "import 'run_steering.dart';\nimport 'run_steering_record.dart';\n",
        "runtime steering record import",
    )
    src = rep(
        src,
        "import 'task_kernel/complexity_router.dart';\n",
        "import 'task_kernel/command_planning_context.dart';\n"
        "import 'task_kernel/complexity_router.dart';\n"
        "import 'task_kernel/plan_reconciliation.dart';\n"
        "import 'task_kernel/universal_task_plan.dart';\n",
        "runtime continuation domain imports",
    )
    src = rep(
        src,
        "    telemetryBridge.start();\n",
        "    coordinator.attachSteeringReplanHandler(\n      runtime._materializePendingSteeringContinuation,\n    );\n    telemetryBridge.start();\n",
        "attach steering replan handler",
    )
    src = rep(
        src,
        "    await coordinator.reconcileInterruptedRuns();\n    await coordinator.reconcileMemoryEpisodes();\n",
        "    await coordinator.reconcileInterruptedRuns();\n    await runtime.reconcileSteeringContinuations();\n    await coordinator.reconcileMemoryEpisodes();\n",
        "startup steering continuation reconciliation",
    )
    # Persist canonical planning context for every kernel-prepared command.
    marker = """    if (existing == null) {\n      await repositories.commands.put(prepared);\n      await audit.append('task_kernel.compiled', prepared.id, <String, dynamic>{\n"""
    if marker not in src:
        raise RuntimeError("kernel context persist: prepareThroughKernel marker not found")
    # Insert after the complete if block by anchoring the return.
    return_anchor = """    return KernelPreparedPlan(\n      command: command,\n      canonical: result.plan,\n"""
    context_write = r'''    final contextNow = DateTime.now().toUtc();
    final existingContext = await repositories.commandPlanningContexts.get(command.id);
    await repositories.commandPlanningContexts.put(
      CommandPlanningContextRecord(
        commandId: command.id,
        projectId: project.id,
        specification: specification,
        family: routing.family,
        route: routing.route,
        routingRationale: routing.rationale,
        canonicalPlan: result.plan,
        consumedCoordinatorCapabilities: consumed,
        createdAt: existingContext?.createdAt ?? contextNow,
        updatedAt: contextNow,
      ),
    );
'''
    src = rep(src, return_anchor, context_write + return_anchor, "persist kernel canonical context")

    # Replace simple steerRun delegate with a reload that can return continuation identity.
    src = rep(
        src,
        "  Future<RunSteeringInstruction> steerRun(String runId, String text) =>\n      runs.queueSteering(runId, text);\n",
        r'''  Future<RunSteeringInstruction> steerRun(String runId, String text) async {
    final queued = await runs.queueSteering(runId, text);
    if (!queued.patch.requiresReplan) return queued;
    // The coordinator materializes the continuation when the source reaches
    // the verified boundary. Reload the durable record so callers receive the
    // continuation id when it was created synchronously during this call.
    final record = await repositories.runSteeringRecords.get(queued.id);
    return record == null ? queued : RunSteeringInstruction.fromRecord(record);
  }
''',
        "runtime steer reload",
    )

    anchor = "  Future<PromptStudioDraft> generatePromptDraft({\n"
    methods = r'''  Future<void> reconcileSteeringContinuations() async {
    final runsNeedingContinuation = (await repositories.runs.all()).where(
      (run) =>
          run.state == RunState.interrupted &&
          (run.failure ?? '').startsWith('steering_replan_requested:'),
    );
    for (final run in runsNeedingContinuation) {
      final pending = (await repositories.runSteeringRecords.all()).where(
        (record) =>
            record.runId == run.id &&
            const <RunSteeringRecordState>{
              RunSteeringRecordState.pending,
              RunSteeringRecordState.replanning,
            }.contains(record.state) &&
            record.patch.requiresReplan,
      );
      if (pending.isEmpty) continue;
      try {
        await _materializePendingSteeringContinuation(run);
      } catch (error) {
        await audit.append(
          'steering.replan_recovery_failed',
          run.id,
          <String, dynamic>{
            'runId': run.id,
            'error': redactor.redact('$error'),
            'authorityInherited': false,
          },
        );
      }
    }
  }

  Future<void> _materializePendingSteeringContinuation(RunRecord source) async {
    final durable = (await repositories.runSteeringRecords.all())
        .where((record) =>
            record.runId == source.id &&
            const <RunSteeringRecordState>{
              RunSteeringRecordState.pending,
              RunSteeringRecordState.replanning,
            }.contains(record.state) &&
            record.patch.requiresReplan)
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    if (durable.isEmpty) return;
    final already = durable
        .map((record) => record.continuationRunId)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (already != null) return;

    final context =
        await repositories.commandPlanningContexts.get(source.command.id);
    if (context == null) {
      throw ProductException(
        'steering_replan_context_missing',
        'The source command has no durable canonical planning context.',
        details: <String, dynamic>{'runId': source.id},
      );
    }
    final project = await repositories.projects.get(context.projectId);
    if (project == null) {
      throw ProductException(
        'project_missing',
        'The project was removed before the steering continuation could be planned.',
        details: <String, dynamic>{'runId': source.id},
      );
    }

    var revisedSpecification = context.specification;
    for (final record in durable) {
      revisedSpecification = record.patch.applyForReplan(revisedSpecification);
    }
    final revisedRouting = RoutingDecision(
      route: context.route == PlanningRoute.compact
          ? PlanningRoute.graph
          : context.route,
      family: context.family,
      rationale:
          'Scope changed during execution; replan from the prior canonical family and promote compact work to a reviewed graph.',
    );
    final result = await taskKernel.plan(
      specification: revisedSpecification,
      routing: revisedRouting,
      context: PlanningContext(
        project: project,
        model: source.command.model,
        availableCapabilityIds:
            kKristinCapabilities.map((item) => item.id).toSet(),
        availableToolNames: tools.names,
        consumedCoordinatorCapabilities:
            context.consumedCoordinatorCapabilities,
        localOnly: _settings.localOnly,
      ),
    );

    final priorById = <String, UniversalTask>{
      for (final task in context.canonicalPlan.tasks) task.id: task,
    };
    final sourceEvidence = await evidenceForRun(source.id);
    final completed = <CompletedTaskRecord>[];
    for (final progress in source.items.where(
      (value) => value.state == WorkItemState.succeeded,
    )) {
      final task = priorById[progress.item.id];
      if (task == null) continue;
      final evidenceIds = sourceEvidence
          .where((value) => value.workItemId == progress.item.id)
          .map((value) => value.id)
          .toList(growable: false);
      completed.add(
        CompletedTaskRecord.of(
          task,
          evidence: <String, dynamic>{
            'sourceRunId': source.id,
            'workItemId': progress.item.id,
            'attempts': progress.attempts,
            'evidenceIds': evidenceIds,
          },
        ),
      );
    }
    final reconciliation = taskKernel.reconcile(
      previous: context.canonicalPlan,
      revised: result.plan,
      completed: completed,
    );
    // A scope reduction can legitimately leave no implementation work. The
    // compiler rejects an empty executable graph, and skipping the run would
    // also skip the Runner's deterministic final verification. Preserve the
    // reconciled disabled tasks and add one hidden read-only verification
    // bridge so the normal governed verification/commit path still runs.
    final executablePlan = reconciliation.plan.enabledTasks.isEmpty
        ? reconciliation.plan.copyWith(
            tasks: <UniversalTask>[
              ...reconciliation.plan.tasks,
              UniversalTask(
                id: newId('task_verify'),
                title: 'Verify reconciled project state',
                objective:
                    'Confirm that the reconciled scope is already satisfied before final project verification.',
                instructions:
                    'Do not mutate the project. Inspect the current project state only if needed, then report that deterministic reconciliation left no implementation work. Final governed project verification runs after this item.',
                phase: 'Verification',
                acceptanceCriteria: const <String>[
                  'No enabled implementation task remains after reconciliation.',
                ],
                verificationSteps: const <String>[
                  'Run the command-mode deterministic project verification gates.',
                ],
                allowedTools: const <String>{'inspect_file'},
                complexity: 1,
                effortPoints: 1,
                estimateConfidence: 1,
                maxAttempts: 1,
                hidden: true,
                provenance: EvidenceProvenance.inferred,
              ),
            ],
          )
        : reconciliation.plan;
    final compiled = taskKernel.compile(
      plan: executablePlan,
      project: project,
      mode: source.command.contract.mode,
      request: revisedSpecification.originalRequest,
      consumedCoordinatorCapabilities:
          context.consumedCoordinatorCapabilities,
    );
    final now = DateTime.now().toUtc();
    final command = PreparedCommand(
      id: newId('command'),
      requestKey: Sha256.text(
        canonicalJson(<String, dynamic>{
          'sourceRunId': source.id,
          'sourceCommandId': source.command.id,
          'steeringIds': durable.map((value) => value.id).toList(),
          'specification': revisedSpecification.contentKey,
          'planHash': executablePlan.contentHash,
          'mode': source.command.contract.mode.name,
          'model': source.command.model.toJson(),
        }),
      ),
      contract: compiled.contract,
      plan: compiled.plan,
      model: source.command.model,
      createdAt: now,
    );
    await repositories.commands.put(command);
    await repositories.commandPlanningContexts.put(
      CommandPlanningContextRecord(
        commandId: command.id,
        projectId: project.id,
        specification: revisedSpecification,
        family: revisedRouting.family,
        route: revisedRouting.route,
        routingRationale: revisedRouting.rationale,
        canonicalPlan: executablePlan,
        consumedCoordinatorCapabilities:
            context.consumedCoordinatorCapabilities,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final continuation = await runs.createContinuationRun(
      command,
      sourceRunId: source.id,
    );
    final instructions = durable
        .map(RunSteeringInstruction.fromRecord)
        .toList(growable: false);
    await runSteering.markContinuationReady(
      source.id,
      instructions,
      continuationRunId: continuation.id,
      reconciliation:
          reconciliation.reconciliations.map((value) => value.toJson()).toList(),
    );
    final details = <String, dynamic>{
      'sourceRunId': source.id,
      'continuationRunId': continuation.id,
      'sourceCommandId': source.command.id,
      'continuationCommandId': command.id,
      'reconciliation':
          reconciliation.reconciliations.map((value) => value.toJson()).toList(),
      'sourceRequiredPermissions':
          source.command.contract.requiredPermissions.map((value) => value.name).toList()..sort(),
      'requiredPermissions':
          command.contract.requiredPermissions.map((value) => value.name).toList()..sort(),
      'authorityInherited': false,
      'continuationState': continuation.state.name,
    };
    await audit.append('steering.replanned', source.id, details);
    await events.publish('steering.replanned', source.id, details);
  }

'''
    src = rep(src, anchor, methods + anchor, "runtime steering continuation methods")
    return src


def transform_semantic_steering_test(src: str) -> str:
    src = rep(
        src,
        "import 'package:kristin_local_agent/product/domain.dart';\n",
        "",
        "semantic steering final unused domain import",
    )
    src = rep(
        src,
        "    expect(instruction.patch.requiresReplan, isFalse);\n",
        "    expect(instruction.patch.requiresReplan, isTrue);\n",
        "semantic steering hard constraint now replans",
    )
    src = rep(
        src,
        "    expect((await service.takePending('run-1')).single.id, instruction.id);\n    await service.applied('run-1', <RunSteeringInstruction>[instruction], workItemId: 'work-2');\n    expect((await service.takePending('run-1')), isEmpty);\n    expect(repository.values[instruction.id]!.state, RunSteeringRecordState.applied);\n",
        "    expect(await service.takePending('run-1'), isEmpty);\n    expect((await service.pendingReplan('run-1')).single.id, instruction.id);\n    expect(repository.values[instruction.id]!.state, RunSteeringRecordState.pending);\n",
        "semantic steering hard constraint boundary expectations",
    )
    old = """    await expectLater(
      service.queue('run-1', 'also build an admin dashboard'),
      throwsA(isA<ProductException>().having(
        (error) => error.code,
        'code',
        'steering_requires_replan',
      )),
    );
"""
    new = """    final instruction =
        await service.queue('run-1', 'also build an admin dashboard');
    expect(instruction.patch.requiresReplan, isTrue);
    expect(instruction.patch.scopeDirectives, contains('also build an admin dashboard'));
    expect((await service.pendingReplan('run-1')).single.id, instruction.id);
"""
    src = rep(src, old, new, "semantic steering scope expansion expectations")
    return src


def transform_source_contract(src: str) -> str:
    return rep(
        src,
        "        'lib/product/task_kernel/complexity_router.dart',\n",
        "        'lib/product/task_kernel/complexity_router.dart',\n        'lib/product/task_kernel/command_planning_context.dart',\n",
        "source contract command context",
    )


def compute(root: Path):
    transforms = {
        root / 'lib/product/task_kernel/task_specification.dart': transform_task_spec,
        root / 'lib/product/run_steering_record.dart': transform_record,
        root / 'lib/product/run_steering.dart': transform_steering,
        root / 'lib/product/storage_security.dart': transform_storage,
        root / 'lib/product/planning_runtime.dart': transform_planning,
        root / 'lib/product/product_runtime.dart': transform_runtime,
        root / 'test/product/semantic_durable_steering_test.dart': transform_semantic_steering_test,
        root / 'test/product/source_contract_test.dart': transform_source_contract,
    }
    result = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f'missing source file: {path}')
        before = path.read_text()
        result[path] = (before, fn(before))
    created = {
        root / 'lib/product/task_kernel/command_planning_context.dart': CONTEXT_SOURCE,
        root / 'test/product/steering_scope_continuation_contract_test.dart': TEST_SOURCE,
    }
    for path, after in created.items():
        before = path.read_text() if path.exists() else ''
        if before and before != after:
            raise RuntimeError(f'{path}: file already exists with different content')
        result[path] = (before, after)
    return result


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('repo')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--diff', action='store_true')
    p.add_argument('--allow-head-drift', action='store_true')
    args = p.parse_args()
    root = Path(args.repo).resolve()
    head = git_head(root)
    if head and head != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(f'refusing HEAD {head}; expected {EXPECTED_HEAD}')
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f'a/{rel}', tofile=f'b/{rel}',
            )), end='')
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
