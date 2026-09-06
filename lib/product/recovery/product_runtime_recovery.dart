import 'dart:async';
import 'dart:math';

import '../capability_invocation.dart';
import '../crypto_utils.dart';
import '../domain.dart';
import '../product_runtime.dart';
import '../product_runtime_self_awareness.dart';
import '../self_awareness/capability_self_model.dart';
import '../storage_security.dart';
import '../task_kernel/complexity_router.dart';
import '../task_kernel/task_families.dart';
import '../task_kernel/task_specification.dart';
import '../task_kernel/universal_task_plan.dart';
import 'failure_recovery.dart';
import 'recovery_host.dart';

final class ProductRuntimeFailureJournal implements FailureJournal {
  const ProductRuntimeFailureJournal(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<void> recordFailure(FailureEvent event) => runtime.events.publish(
    'recovery.failure_recorded',
    event.id,
    <String, dynamic>{'failure': event.toJson()},
  );

  @override
  Future<void> recordAttempt(RecoveryAttempt attempt) => runtime.events.publish(
    'recovery.attempt_recorded',
    attempt.failureId,
    <String, dynamic>{'attempt': attempt.toJson()},
  );
}

final class ProductRuntimeRecoveryEventSink implements RecoveryEventSink {
  const ProductRuntimeRecoveryEventSink(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<void> emit(String type, Map<String, Object?> payload) =>
      runtime.events.publish(
        'recovery.$type',
        payload['failureId']?.toString() ?? newId('recovery_event'),
        Map<String, dynamic>.from(payload),
      );
}

/// Recovery strategy memory is replayed from the same durable EventJournal
/// ProductRuntime already owns. Historical decode failures are ignored but
/// remain available in the journal for diagnostics.
final class ProductRuntimeRecoveryExperienceStore
    implements RecoveryExperienceStore {
  ProductRuntimeRecoveryExperienceStore(this.runtime, {this.maxRetained = 512});

  final ProductRuntime runtime;
  final int maxRetained;
  final List<RecoveryExperience> _items = <RecoveryExperience>[];
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  Future<void> _load() async {
    if (_loaded) return;
    final events = await runtime.events.after(0, limit: 5000);
    final loaded = <RecoveryExperience>[];
    for (final event in events) {
      if (event.type != 'recovery.experience') continue;
      final raw = event.data['experience'];
      if (raw is! Map) continue;
      try {
        loaded.add(RecoveryExperience.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        // Invalid old memory cannot become authority or block startup.
      }
    }
    _items
      ..clear()
      ..addAll(loaded);
    _trim();
    _loaded = true;
  }

  @override
  Future<void> record(RecoveryExperience experience) {
    final completer = Completer<void>();
    _tail = _tail
        .then((_) async {
          await _load();
          await runtime.events.publish(
            'recovery.experience',
            experience.failureId ?? experience.id,
            <String, dynamic>{'experience': experience.toJson()},
          );
          _items.add(experience);
          _trim();
          completer.complete();
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted)
            completer.completeError(error, stackTrace);
        });
    return completer.future;
  }

  @override
  Future<List<RecoveryExperience>> find({
    required String failureSignature,
    String? environmentFingerprint,
  }) async {
    await _tail;
    await _load();
    return List<RecoveryExperience>.unmodifiable(
      _items.where((item) {
        if (item.failureSignature != failureSignature) return false;
        return environmentFingerprint == null ||
            item.environmentFingerprint == environmentFingerprint;
      }),
    );
  }

  void _trim() {
    if (_items.length > maxRetained) {
      _items.removeRange(0, _items.length - maxRetained);
    }
  }
}

final class ProductRuntimeFailureSelfContextResolver
    implements FailureSelfContextResolver {
  const ProductRuntimeFailureSelfContextResolver(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<SelfModelSessionOverlay> resolve(FailureEvent failure) async {
    ProjectRecord? project;
    ModelIdentity? model;
    if (failure.projectId != null) {
      project = await runtime.repositories.projects.get(failure.projectId!);
    }
    final sourceRun = failure.runId == null
        ? null
        : await runtime.getRun(failure.runId!);
    project ??= sourceRun == null
        ? null
        : await runtime.repositories.projects.get(
            sourceRun.command.contract.projectId,
          );
    model = sourceRun?.command.model;
    if (model == null && failure.modelExactId != null) {
      final discovered = await runtime.discoverModels();
      model = discovered
          .where((item) => item.exactId == failure.modelExactId)
          .firstOrNull;
    }
    return productSelfOverlay(
      key: 'recovery:${failure.rootFailureId ?? failure.id}',
      selectedProject: project,
      selectedModel: model,
    );
  }
}

/// Independent Owner/self-repair authority plugs in here. Merely registering
/// a recovery host, or observing Owner runtime availability, is not a grant.
abstract interface class RecoveryExternalAuthorityProvider {
  Future<RecoveryAuthorityEvaluation> evaluate({
    required ProductRuntime runtime,
    required FailureEvent failure,
    required RecoveryDecision decision,
    required Set<String> authorityNames,
  });
}

final class ProductRuntimeRecoveryAuthorityRegistry {
  ProductRuntimeRecoveryAuthorityRegistry._();
  static final Expando<RecoveryExternalAuthorityProvider> _providers =
      Expando<RecoveryExternalAuthorityProvider>('kristin-recovery-authority');

  static void register(
    ProductRuntime runtime,
    RecoveryExternalAuthorityProvider provider,
  ) {
    _providers[runtime] = provider;
  }

  static RecoveryExternalAuthorityProvider? forRuntime(
    ProductRuntime runtime,
  ) => _providers[runtime];
}

/// Canonical run grants prove ordinary permission scopes. Authority names that
/// are not PermissionScope values (notably owner/owner.self_repair) require an
/// independent provider. Unknown authority always fails closed.
final class ProductRuntimeRecoveryAuthorityGate
    implements RecoveryAuthorityGate {
  const ProductRuntimeRecoveryAuthorityGate(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async {
    if (decision.requiredAuthority.isEmpty) {
      return const RecoveryAuthorityEvaluation(
        allowed: true,
        reason: 'No additional authority is required by this strategy.',
      );
    }

    final byName = <String, PermissionScope>{
      for (final scope in PermissionScope.values) scope.name: scope,
    };
    final knownNames = decision.requiredAuthority
        .where(byName.containsKey)
        .toSet();
    final externalNames = decision.requiredAuthority.difference(knownNames);
    final granted = <String>{};
    final missing = <String>{};
    final notEvaluated = <String>{};

    if (knownNames.isNotEmpty) {
      final known = await _evaluateKnownScopes(
        failure,
        knownNames.map((name) => byName[name]!).toSet(),
      );
      granted.addAll(known.granted);
      missing.addAll(known.missing);
      notEvaluated.addAll(known.notEvaluated);
    }

    if (externalNames.isNotEmpty) {
      final provider = ProductRuntimeRecoveryAuthorityRegistry.forRuntime(
        runtime,
      );
      if (provider == null) {
        notEvaluated.addAll(externalNames);
      } else {
        final external = await provider.evaluate(
          runtime: runtime,
          failure: failure,
          decision: decision,
          authorityNames: externalNames,
        );
        granted.addAll(external.granted.intersection(externalNames));
        missing.addAll(external.missing.intersection(externalNames));
        notEvaluated.addAll(external.notEvaluated.intersection(externalNames));
        final unresolved = externalNames
            .difference(granted)
            .difference(missing)
            .difference(notEvaluated);
        if (external.allowed) {
          granted.addAll(unresolved);
        } else {
          notEvaluated.addAll(unresolved);
        }
      }
    }

    final allowed =
        missing.isEmpty &&
        notEvaluated.isEmpty &&
        granted.containsAll(decision.requiredAuthority);
    return RecoveryAuthorityEvaluation(
      allowed: allowed,
      reason: allowed
          ? 'Required recovery authority is explicitly proven for this operation.'
          : missing.isNotEmpty
          ? 'Required recovery authority is explicitly absent.'
          : 'Required recovery authority has not been evaluated.',
      granted: granted,
      missing: missing,
      notEvaluated: notEvaluated,
    );
  }

  Future<RecoveryAuthorityEvaluation> _evaluateKnownScopes(
    FailureEvent failure,
    Set<PermissionScope> required,
  ) async {
    if (required.isEmpty) {
      return const RecoveryAuthorityEvaluation(
        allowed: true,
        reason: 'No canonical permission scopes are required.',
      );
    }
    final runId = failure.runId;
    if (runId == null) {
      return RecoveryAuthorityEvaluation(
        allowed: false,
        reason:
            'No governed source run exists from which recovery permission can be proven.',
        notEvaluated: required.map((scope) => scope.name).toSet(),
      );
    }
    final source = await runtime.getRun(runId);
    if (source == null) {
      return RecoveryAuthorityEvaluation(
        allowed: false,
        reason: 'The source run no longer exists.',
        notEvaluated: required.map((scope) => scope.name).toSet(),
      );
    }
    final active = await _activeScopesFor(source);
    final missing = required.difference(active);
    return RecoveryAuthorityEvaluation(
      allowed: missing.isEmpty,
      reason: missing.isEmpty
          ? 'The original governed run has an active grant covering these scopes.'
          : 'The original governed run does not have all required scopes.',
      granted: required.intersection(active).map((scope) => scope.name).toSet(),
      missing: missing.map((scope) => scope.name).toSet(),
    );
  }

  Future<Set<PermissionScope>> _activeScopesFor(RunRecord source) async {
    final grants = await runtime.repositories.grants.all();
    final scopes = <PermissionScope>{};
    for (final grant in grants) {
      if (grant.projectId != source.command.contract.projectId ||
          grant.commandId != source.command.id ||
          grant.isExpired ||
          grant.remainingUses <= 0) {
        continue;
      }
      scopes.addAll(grant.scopes);
    }
    return scopes;
  }
}

/// Narrow, deterministic ProductRuntime recovery actuator. Arbitrary config
/// mutation is intentionally absent; an unknown L2 repair fails closed.
final class ProductRuntimeRecoveryActuator implements RecoveryActuator {
  const ProductRuntimeRecoveryActuator(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    final awareness = ProductSelfAwarenessRuntime.shared(runtime);
    final before = await awareness.snapshot(forceRefresh: true);
    final evidence = <String>[];

    if (decision.kind == RecoveryDecisionKind.retry) {
      if (failure.category == FailureCategory.browser) {
        if (!runtime.p3BrowserRuntime.available) {
          throw ProductException(
            'recovery_browser_unavailable',
            'Browser runtime is unavailable for retry.',
          );
        }
        await runtime.p3BrowserRuntime.probe(
          startupTimeout: const Duration(seconds: 10),
        );
        evidence.add('browserProbe:healthy');
      } else if (failure.category == FailureCategory.provider) {
        final models = await runtime.discoverModels();
        evidence.add('modelDiscovery:${models.length}');
      }
    } else if (decision.kind == RecoveryDecisionKind.restart) {
      if (failure.category == FailureCategory.browser) {
        final browser = await runtime.refreshProvisionedBrowserRuntime();
        if (!browser.available) {
          throw ProductException(
            'recovery_browser_unavailable',
            'Browser runtime is still unavailable after refresh.',
          );
        }
        await browser.probe(startupTimeout: const Duration(seconds: 10));
        evidence.add('browserRuntime:restarted');
      } else if (failure.projectId != null) {
        final status = await runtime.projectProcessStatus(failure.projectId!);
        if (status?.running == true) {
          await runtime.stopProject(failure.projectId!);
        }
        final started = await runtime.startProject(failure.projectId!);
        evidence.add('projectProcess:${started.processId}');
      } else {
        throw ProductException(
          'recovery_restart_target_missing',
          'No bounded runtime resource is identified for restart.',
        );
      }
    } else if (decision.kind == RecoveryDecisionKind.reconfigure) {
      if (failure.category == FailureCategory.browser) {
        final browser = await runtime.refreshProvisionedBrowserRuntime();
        evidence.add('browserProvisioning:${browser.statusCode}');
      } else if (failure.category == FailureCategory.provider) {
        final models = await runtime.discoverModels();
        evidence.add('providerDiscovery:${models.length}');
      } else {
        throw ProductException(
          'recovery_configuration_not_bounded',
          'This configuration repair has no deterministic bounded ProductRuntime actuator.',
        );
      }
    } else {
      throw StateError('recovery_actuator_kind_invalid:${decision.kind.name}');
    }

    final after = await awareness.snapshot(forceRefresh: true);
    final beforeHash = before.application.semanticFingerprint;
    final afterHash = after.application.semanticFingerprint;
    return RecoveryActionResult(
      summary: '${decision.strategyId} completed.',
      evidenceReferences: evidence,
      beforeFingerprint: beforeHash,
      afterFingerprint: afterHash,
      // A newly-created evidence id is not semantic progress by itself.
      materialProgress: beforeHash != afterHash,
    );
  }

  @override
  Future<RecoveryActionResult> rollback(
    RecoveryDecision decision,
    FailureEvent failure,
    RecoveryActionResult action,
  ) async {
    if (decision.kind == RecoveryDecisionKind.restart &&
        failure.projectId != null) {
      final stopped = await runtime.stopProject(failure.projectId!);
      return RecoveryActionResult(
        summary:
            'Stopped the restarted managed project process after failed verification.',
        evidenceReferences: <String>[
          ...action.evidenceReferences,
          'rollbackProcess:${stopped?.processId ?? 'none'}',
        ],
        beforeFingerprint: action.afterFingerprint,
        materialProgress: true,
      );
    }
    throw ProductException(
      'recovery_rollback_unavailable',
      'This recovery action has no deterministic rollback in ProductRuntime.',
    );
  }
}

final class ProductRuntimeRecoveryVerifier implements RecoveryVerifier {
  const ProductRuntimeRecoveryVerifier(this.runtime, this.contextResolver);
  final ProductRuntime runtime;
  final FailureSelfContextResolver contextResolver;

  @override
  Future<RecoveryVerification> verify(
    FailureEvent originalFailure,
    RecoveryActionResult action,
  ) async {
    final overlay = await contextResolver.resolve(originalFailure);

    if (originalFailure.category == FailureCategory.browser) {
      final browser = runtime.p3BrowserRuntime;
      if (!browser.available) {
        return const RecoveryVerification(
          passed: false,
          check: 'browser_runtime',
          observed: 'Browser runtime remains unavailable.',
        );
      }
      try {
        await browser.probe(startupTimeout: const Duration(seconds: 10));
        return RecoveryVerification(
          passed: true,
          check: 'browser_runtime',
          observed: 'Browser startup probe is healthy.',
          evidenceReferences: <String>[
            ...action.evidenceReferences,
            'browserProbe:verified',
          ],
          materialProgress: true,
        );
      } catch (error) {
        return RecoveryVerification(
          passed: false,
          check: 'browser_runtime',
          observed:
              'Browser startup probe failed: ${runtime.redactor.redact('$error')}',
        );
      }
    }

    if (originalFailure.modelExactId != null) {
      final snapshot = await ProductSelfAwarenessRuntime.shared(runtime)
          .selfModel
          .snapshot(
            forceRefresh: true,
            source: 'recovery_verifier',
            reason: 'provider_verification',
            overlay: overlay,
          );
      final selected = snapshot.application.selectedModel;
      final live = selected != null && selected['discovered'] == true;
      return RecoveryVerification(
        passed: live,
        check: 'selected_model_discovery',
        observed: live
            ? 'Selected model ${selected['exactId']} is present in fresh provider discovery.'
            : 'The selected model is not present in fresh provider discovery.',
        evidenceReferences: action.evidenceReferences,
        materialProgress: live,
      );
    }

    if (originalFailure.category == FailureCategory.process &&
        originalFailure.projectId != null) {
      final status = await runtime.projectProcessStatus(
        originalFailure.projectId!,
      );
      final running = status?.running == true;
      return RecoveryVerification(
        passed: running,
        check: 'managed_project_process',
        observed: running
            ? 'The managed project process is running.'
            : 'The managed project process is not running.',
        evidenceReferences: action.evidenceReferences,
        materialProgress: running,
        rollbackRecommended: !running,
      );
    }

    if (originalFailure.category == FailureCategory.project ||
        originalFailure.category == FailureCategory.execution ||
        originalFailure.category == FailureCategory.verification) {
      if (!action.materialProgress) {
        return RecoveryVerification(
          passed: false,
          check: 'kernel_recovery_progress',
          observed:
              'Recovery work did not establish a semantic state transition.',
          evidenceReferences: action.evidenceReferences,
        );
      }
      return RecoveryVerification(
        passed: true,
        check: 'kernel_recovery_terminal_result',
        observed:
            'Governed recovery work reached verified terminal success with semantic progress.',
        evidenceReferences: action.evidenceReferences,
        materialProgress: true,
      );
    }

    if (originalFailure.capabilityId != null) {
      final snapshot = await ProductSelfAwarenessRuntime.shared(runtime)
          .selfModel
          .snapshot(
            forceRefresh: true,
            source: 'recovery_verifier',
            reason: 'capability_verification',
            overlay: overlay,
          );
      final capability = snapshot.capability(originalFailure.capabilityId!);
      final usable = capability?.operationallyUsable == true;
      return RecoveryVerification(
        passed: usable,
        check: 'capability_operational_state',
        observed: usable
            ? '${originalFailure.capabilityId} is operationally usable.'
            : '${originalFailure.capabilityId} remains blocked or unhealthy.',
        evidenceReferences: action.evidenceReferences,
        materialProgress: action.materialProgress,
      );
    }

    return RecoveryVerification(
      passed: false,
      check: 'recovery_verification_unavailable',
      observed:
          'No deterministic verifier exists for this failure; recovery remains unverified.',
      evidenceReferences: action.evidenceReferences,
    );
  }
}

/// L3 repair is compiled and executed through the existing Universal Task
/// Kernel. Recovery may carry authority forward only when an active grant on
/// the original run covers every permission in the new recovery plan.
final class ProductRuntimeRecoveryTaskRouter implements RecoveryTaskRouter {
  ProductRuntimeRecoveryTaskRouter(this.runtime, this.internalRunIds);

  final ProductRuntime runtime;
  final Set<String> internalRunIds;

  @override
  Future<RecoveryActionResult> runRecoveryWork(
    RecoveryObjective objective,
  ) async {
    final failure = objective.failure;
    final projectId =
        failure.projectId ??
        failure.stateAfter['projectId']?.toString() ??
        failure.stateBefore['projectId']?.toString();
    if (projectId == null || projectId.isEmpty) {
      throw ProductException(
        'recovery_project_missing',
        'Code repair requires an explicit project identity.',
      );
    }
    final project = await runtime.repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException(
        'recovery_project_missing',
        'The recovery project no longer exists.',
      );
    }
    final source = failure.runId == null
        ? null
        : await runtime.getRun(failure.runId!);
    final model =
        source?.command.model ?? await _resolveModel(failure.modelExactId);
    if (model == null) {
      throw ProductException(
        'recovery_model_missing',
        'Code repair requires a live selected model.',
      );
    }

    final specification = TaskSpecification(
      id: newId('recovery_spec'),
      originalRequest: objective.objective,
      objective: objective.objective,
      targetRefs: <TaskTargetRef>[
        TaskTargetRef(
          kind: 'project',
          value: project.id,
          displayName: project.name,
          provenance: EvidenceProvenance.observed,
          resolved: true,
        ),
      ],
      hardConstraints: const <SpecificationClaim>[
        SpecificationClaim.inferred(
          'Preserve the original user objective and do not expand authority during recovery.',
          source: 'failure_supervisor',
        ),
      ],
      successCriteria: <SpecificationClaim>[
        SpecificationClaim.inferred(
          objective.successCondition,
          source: 'failure_supervisor',
        ),
      ],
      contextRefs: <String>[
        'failure:${failure.id}',
        if (failure.runId != null) 'run:${failure.runId}',
        if (failure.taskId != null) 'task:${failure.taskId}',
      ],
      capabilityHints: const <String>['agent.fix_project'],
      source: TaskSpecificationSource.deterministic,
      confidence: 1.0,
    );
    const consumed = <String>{'agent.fix_project'};
    final routing = const RoutingDecision(
      route: PlanningRoute.graph,
      family: TaskFamily.software,
      rationale:
          'Autonomic L3 recovery requires a governed diagnose/repair/verify graph.',
    );
    final planned = await runtime.taskKernel.plan(
      specification: specification,
      routing: routing,
      context: PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds: objective.selfContext.availableCapabilityIds,
        availableToolNames: runtime.tools.names,
        consumedCoordinatorCapabilities: consumed,
        localOnly: runtime.settings.localOnly,
      ),
    );
    final mode = source?.command.contract.mode ?? CommandMode.fix;
    final compiled = runtime.taskKernel.compile(
      plan: planned.plan,
      project: project,
      mode: mode,
      consumedCoordinatorCapabilities: consumed,
    );
    final prepared = PreparedCommand(
      id: newId('recovery_command'),
      requestKey: Sha256.text(
        canonicalJson(<String, dynamic>{
          'kind': 'autonomic_recovery',
          'failureId': failure.id,
          'projectId': project.id,
          'planHash': planned.plan.contentHash,
          'mode': mode.name,
          'model': model.toJson(),
        }),
      ),
      contract: compiled.contract,
      plan: compiled.plan,
      model: model,
      createdAt: DateTime.now().toUtc(),
    );
    await runtime.repositories.commands.put(prepared);
    await runtime.audit
        .append('recovery.command_prepared', prepared.id, <String, dynamic>{
          'failureId': failure.id,
          'projectId': project.id,
          'planHash': planned.plan.contentHash,
          'requiredPermissions':
              prepared.contract.requiredPermissions
                  .map((scope) => scope.name)
                  .toList()
                ..sort(),
        });
    await runtime.events.publish(
      'recovery.command_prepared',
      failure.id,
      <String, dynamic>{
        'failureId': failure.id,
        'commandId': prepared.id,
        'projectId': project.id,
      },
    );

    final run = await runtime.createRun(prepared.id);
    _rememberInternalRun(run.id);
    // The L3 repair run carries a NEW commandId (newId('recovery_command')),
    // so the parent's grants -- keyed by (projectId, commandId) -- cannot cover
    // it implicitly. Authority must be delegated explicitly, bounded by and
    // debited from what remains to the parent.
    await _delegateBoundedAuthority(
      source: source,
      target: run,
      required: prepared.contract.requiredPermissions,
    );
    final terminal = await runtime.execute(run.id);
    if (terminal.state != RunState.succeeded) {
      throw ProductException(
        'recovery_kernel_run_failed',
        terminal.failure ?? 'Governed recovery run did not succeed.',
        details: <String, dynamic>{
          'recoveryRunId': terminal.id,
          'state': terminal.state.name,
        },
      );
    }
    final evidence = await runtime.evidenceForRun(terminal.id);
    return RecoveryActionResult(
      summary: 'Governed kernel recovery run ${terminal.id} succeeded.',
      evidenceReferences: <String>[
        'recoveryRun:${terminal.id}',
        ...evidence.map((item) => 'evidence:${item.id}'),
      ],
      beforeFingerprint: failure.stateBefore.isEmpty
          ? ''
          : Sha256.text(canonicalJson(failure.stateBefore)),
      afterFingerprint: Sha256.text(
        canonicalJson(<String, Object?>{
          'runId': terminal.id,
          'state': terminal.state.name,
          'summary': terminal.summary,
          'evidence': evidence.map((item) => item.hash).toList(),
        }),
      ),
      // A succeeded recovery run has already crossed the governed runtime's
      // convergence/verifier boundary; this is semantic progress.
      materialProgress: true,
    );
  }

  @override
  Future<RecoveryActionResult> continueOriginalTask(
    FailureEvent failure,
  ) async {
    final runId = failure.runId;
    if (runId == null) {
      return const RecoveryActionResult(
        summary: 'No governed original run requires continuation.',
      );
    }
    final source = await runtime.getRun(runId);
    if (source == null) {
      throw ProductException(
        'recovery_source_run_missing',
        'The original run no longer exists.',
      );
    }
    switch (source.state) {
      case RunState.failed:
        final retry = await runtime.retryRun(source.id);
        // retryRun reuses the parent's PreparedCommand, so the continuation
        // shares its commandId and is already covered by the parent's grants.
        // Verify that coverage; mint nothing.
        await _assertContinuationAuthorityWithinParent(
          source: source,
          target: retry,
          required: retry.command.contract.requiredPermissions,
        );
        // This is the user's continued task, not an internal recovery child.
        // A repeated failure remains visible to the bounded strategy ladder.
        unawaited(runtime.execute(retry.id));
        await runtime.events.publish(
          'recovery.original_continuation_started',
          failure.id,
          <String, dynamic>{
            'failureId': failure.id,
            'sourceRunId': source.id,
            'continuationRunId': retry.id,
          },
        );
        return RecoveryActionResult(
          summary: 'Started linked continuation run ${retry.id}.',
          evidenceReferences: <String>['continuationRun:${retry.id}'],
          materialProgress: true,
        );
      case RunState.paused:
        await runtime.resume(source.id);
        return RecoveryActionResult(
          summary: 'Resumed paused original run ${source.id}.',
          evidenceReferences: <String>['resumedRun:${source.id}'],
          materialProgress: true,
        );
      case RunState.interrupted:
        await runtime.resume(source.id);
        unawaited(runtime.execute(source.id));
        return RecoveryActionResult(
          summary: 'Resumed interrupted original run ${source.id}.',
          evidenceReferences: <String>['resumedRun:${source.id}'],
          materialProgress: true,
        );
      case RunState.cancelled:
        throw ProductException(
          'recovery_user_cancelled',
          'The original task was cancelled; autonomic recovery will not override user cancellation.',
        );
      case RunState.succeeded:
        return RecoveryActionResult(
          summary: 'The original run is already succeeded.',
          evidenceReferences: <String>['run:${source.id}:succeeded'],
        );
      case RunState.prepared:
      case RunState.queued:
      case RunState.awaitingApproval:
      case RunState.running:
      case RunState.cancelling:
        return RecoveryActionResult(
          summary:
              'The original run is already nonterminal and does not need a duplicate continuation.',
          evidenceReferences: <String>['run:${source.id}:${source.state.name}'],
        );
    }
  }

  Future<ModelIdentity?> _resolveModel(String? exactId) async {
    if (exactId == null || exactId.isEmpty) return null;
    final models = await runtime.discoverModels();
    return models.where((item) => item.exactId == exactId).firstOrNull;
  }

  /// Asserts that a recovery continuation stays inside the authority that
  /// still remains to the run it continues. It deliberately mints nothing.
  ///
  /// INVARIANT: child_authority <= remaining_parent_authority, across scope,
  /// expiry, use budget and revocation.
  ///
  /// This holds structurally rather than by arithmetic. Permission enforcement
  /// is keyed by (projectId, commandId, scope) -- see PermissionService.require
  /// and its only caller, the governed tool gate in workspace_tools.dart; no
  /// permission check anywhere keys off runId. RunService.retryRun builds the
  /// continuation with `_createFreshRun(source.command, ...)`, passing the same
  /// PreparedCommand, so the continuation carries the *same* commandId as its
  /// parent. The parent's surviving grants therefore already authorize the
  /// continuation, and the continuation spends the parent's remaining uses
  /// against the parent's expiry.
  ///
  /// Calling ProductRuntime.approve() here would not "carry forward" anything;
  /// it would add a second grant to the same (projectId, commandId) pool with a
  /// fresh `max(100, maxToolCalls * 3)` use budget and a fresh two-hour window.
  /// Because PermissionService.require consumes whichever grant allows a scope,
  /// the pool's effective budget is the sum of its grants, so minting turned a
  /// parent with 3 remaining uses into 103, a parent expiring in 8 minutes into
  /// one usable for 2 hours, and gave every sibling continuation its own full
  /// budget. A finite human approval became renewable machine authority. That
  /// call is gone.
  ///
  /// Fail-closed cases are preserved by the filter below: an expired, revoked
  /// or exhausted parent grant contributes no scopes, so `required` is not
  /// covered and this throws rather than resurrecting dead authority. Recovery
  /// then escalates and asks a human instead of silently renewing.
  Future<void> _assertContinuationAuthorityWithinParent({
    required RunRecord? source,
    required RunRecord target,
    required Set<PermissionScope> required,
  }) async {
    if (required.isEmpty) return;
    final envelope = await _parentAuthorityEnvelope(
      source: source,
      target: target,
      required: required,
    );
    // No grant is minted. The continuation shares the parent's (projectId,
    // commandId) grants and spends their remaining budget against their
    // existing expiry. The evidence records what that inherited envelope was
    // at the moment of the decision, so an auditor can confirm the child never
    // received more than the parent still had.
    await runtime.events.publish(
      'recovery.authority_inherited_within_parent',
      target.id,
      <String, dynamic>{
        'sourceRunId': source?.id,
        'targetRunId': target.id,
        'sourceGrantIds': envelope.grantIds,
        'scopes': required.map((scope) => scope.name).toList()..sort(),
        'minted': false,
        'inheritedRemainingUses': envelope.remainingUses,
        'inheritedExpiresAt': envelope.latestExpiry.toUtc().toIso8601String(),
      },
    );
  }

  /// Delegates bounded authority to a governed recovery run that carries a
  /// *new* commandId, so the parent's grants cannot cover it implicitly.
  ///
  /// INVARIANT: child_authority <= remaining_parent_authority. Enforced by
  /// arithmetic here because sharing is not available:
  ///   * scope    -- never exceeds the parent's currently active scopes;
  ///   * expiry   -- never later than the parent's latest surviving expiry;
  ///   * uses     -- never more than the parent's total remaining uses, and the
  ///                 parent is debited by exactly what the child receives, so
  ///                 authority is conserved rather than created;
  ///   * lifetime -- an expired, revoked or exhausted parent contributes no
  ///                 scopes and this fails closed instead of resurrecting it.
  ///
  /// Debiting is what makes sibling delegation safe. Two recovery children of
  /// one parent draw from the same finite pool: the first reduces what the
  /// second can be given, and the sum can never exceed the original approval.
  /// Without the debit, each sibling would receive the parent's full remaining
  /// budget and N children would multiply a single human approval N times.
  Future<void> _delegateBoundedAuthority({
    required RunRecord? source,
    required RunRecord target,
    required Set<PermissionScope> required,
  }) async {
    if (required.isEmpty) return;
    final envelope = await _parentAuthorityEnvelope(
      source: source,
      target: target,
      required: required,
    );
    final now = DateTime.now().toUtc();
    final requested = max(100, target.budget.maxToolCalls * 3);
    final uses = min(requested, envelope.remainingUses);
    final window = envelope.latestExpiry.difference(now);
    if (uses <= 0 || window.inSeconds <= 0) {
      throw ProductException(
        'recovery_authority_exhausted',
        'The original approval has no remaining budget to delegate to recovery.',
        details: <String, dynamic>{
          'sourceRunId': source?.id,
          'targetRunId': target.id,
          'remainingUses': envelope.remainingUses,
        },
      );
    }
    await _debitParentGrants(envelope: envelope, uses: uses);
    await runtime.permissions.grant(
      projectId: target.command.contract.projectId,
      commandId: target.command.id,
      scopes: required,
      validity: window,
      uses: uses,
    );
    await runtime.events.publish(
      'recovery.authority_delegated_within_parent',
      target.id,
      <String, dynamic>{
        'sourceRunId': source?.id,
        'targetRunId': target.id,
        'sourceGrantIds': envelope.grantIds,
        'scopes': required.map((scope) => scope.name).toList()..sort(),
        'minted': true,
        'requestedUses': requested,
        'delegatedUses': uses,
        'parentRemainingUsesBefore': envelope.remainingUses,
        'parentRemainingUsesAfter': envelope.remainingUses - uses,
        'expiresAt': envelope.latestExpiry.toUtc().toIso8601String(),
      },
    );
  }

  /// Reduces the parent's surviving grants by exactly [uses], oldest-expiry
  /// first, so delegation moves authority instead of duplicating it.
  Future<void> _debitParentGrants({
    required _ParentAuthorityEnvelope envelope,
    required int uses,
  }) async {
    var outstanding = uses;
    final ordered = envelope.grants.toList()
      ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    for (final grant in ordered) {
      if (outstanding <= 0) break;
      final debit = min(outstanding, grant.remainingUses);
      if (debit <= 0) continue;
      await runtime.repositories.grants.put(
        PermissionGrant(
          id: grant.id,
          projectId: grant.projectId,
          commandId: grant.commandId,
          scopes: grant.scopes,
          createdAt: grant.createdAt,
          expiresAt: grant.expiresAt,
          remainingUses: grant.remainingUses - debit,
        ),
      );
      outstanding -= debit;
    }
  }

  /// Collects the parent's currently usable authority and fails closed when it
  /// does not cover [required].
  Future<_ParentAuthorityEnvelope> _parentAuthorityEnvelope({
    required RunRecord? source,
    required RunRecord target,
    required Set<PermissionScope> required,
  }) async {
    if (source == null) {
      throw ProductException(
        'recovery_authority_source_missing',
        'Recovery requires permissions but has no original governed run from which to prove them.',
      );
    }
    // The L3 repair command takes its project from the FailureEvent
    // (failure.projectId, or a projectId inside stateBefore/stateAfter), which
    // is producer-supplied. Without this check a failure naming a different
    // project would debit the parent's grants in one project and mint
    // authority in another. Authority may only move within the project that
    // granted it.
    final sourceProjectId = source.command.contract.projectId;
    final targetProjectId = target.command.contract.projectId;
    if (sourceProjectId != targetProjectId) {
      throw ProductException(
        'recovery_authority_project_mismatch',
        'Recovery may not move authority between projects.',
        details: <String, dynamic>{
          'sourceRunId': source.id,
          'targetRunId': target.id,
          'sourceProjectId': sourceProjectId,
          'targetProjectId': targetProjectId,
        },
      );
    }
    final grants = await runtime.repositories.grants.all();
    final activeScopes = <PermissionScope>{};
    final active = <PermissionGrant>[];
    var remainingUses = 0;
    DateTime? latestExpiry;
    for (final grant in grants) {
      if (grant.commandId != source.command.id ||
          grant.projectId != source.command.contract.projectId ||
          grant.isExpired ||
          grant.remainingUses <= 0) {
        continue;
      }
      activeScopes.addAll(grant.scopes);
      active.add(grant);
      remainingUses += grant.remainingUses;
      if (latestExpiry == null || grant.expiresAt.isAfter(latestExpiry)) {
        latestExpiry = grant.expiresAt;
      }
    }
    if (!activeScopes.containsAll(required) || latestExpiry == null) {
      final extra = required.difference(activeScopes);
      throw ProductException(
        'recovery_authority_expansion_rejected',
        'Recovery plan requires authority that was not granted to the original task.',
        details: <String, dynamic>{
          'sourceRunId': source.id,
          'targetRunId': target.id,
          'missingScopes': extra.map((scope) => scope.name).toList()..sort(),
        },
      );
    }
    return _ParentAuthorityEnvelope(
      grants: active,
      grantIds: active.map((grant) => grant.id).toList(growable: false),
      scopes: activeScopes,
      remainingUses: remainingUses,
      latestExpiry: latestExpiry,
    );
  }

  void _rememberInternalRun(String runId) {
    internalRunIds.add(runId);
    if (internalRunIds.length > 256) {
      internalRunIds.remove(internalRunIds.first);
    }
  }
}

/// The authority that still remains to a parent run at one instant: the ceiling
/// any recovery child may be given, and never more.
final class _ParentAuthorityEnvelope {
  const _ParentAuthorityEnvelope({
    required this.grants,
    required this.grantIds,
    required this.scopes,
    required this.remainingUses,
    required this.latestExpiry,
  });

  final List<PermissionGrant> grants;
  final List<String> grantIds;
  final Set<PermissionScope> scopes;
  final int remainingUses;
  final DateTime latestExpiry;
}

final class ProductRuntimeRecoveryHostRegistry {
  ProductRuntimeRecoveryHostRegistry._();
  static final Expando<KristinRecoveryHost> _hosts =
      Expando<KristinRecoveryHost>('kristin-recovery-host');

  static void register(ProductRuntime runtime, KristinRecoveryHost host) {
    _hosts[runtime] = host;
  }

  static KristinRecoveryHost? forRuntime(ProductRuntime runtime) =>
      _hosts[runtime];
}

final class ProductRuntimeSelfRepairCoordinator
    implements RecoverySelfRepairCoordinator {
  const ProductRuntimeSelfRepairCoordinator(this.runtime);
  final ProductRuntime runtime;

  @override
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  ) async {
    final owner = runtime.p2OwnerMode;
    if (!owner.available ||
        !owner.completionEligible ||
        !owner.secureIsolationActive) {
      throw ProductException(
        'owner_recovery_runtime_not_ready',
        'The isolated Owner runtime is not healthy enough for staged self-repair.',
      );
    }
    final host = ProductRuntimeRecoveryHostRegistry.forRuntime(runtime);
    if (host == null) {
      throw ProductException(
        'recovery_host_unavailable',
        'No independent Kristin recovery host is registered.',
      );
    }
    final raw = failure.stateAfter['recoveryCandidate'];
    if (raw is! Map) {
      throw ProductException(
        'recovery_candidate_missing',
        'L4 self-repair requires a staged candidate identity from the independent recovery boundary.',
      );
    }
    final candidate = Map<String, Object?>.from(raw);
    final identity = RecoveryVersionIdentity(
      version: candidate['version']?.toString() ?? '',
      sourceIdentity: candidate['sourceIdentity']?.toString() ?? '',
      artifactIdentity: candidate['artifactIdentity']?.toString() ?? '',
    );
    if (identity.version.isEmpty ||
        identity.sourceIdentity.isEmpty ||
        identity.artifactIdentity.isEmpty) {
      throw ProductException(
        'recovery_candidate_invalid',
        'The staged self-repair candidate identity is incomplete.',
      );
    }
    final before = await host.inspect();
    final after = await StagedSelfRepairCoordinator(host)
        .activateVerifiedCandidate(
          identity,
          failureEvidence: failure.evidenceReferences,
        );
    final activated =
        after.current.artifactIdentity == identity.artifactIdentity &&
        after.health == RecoveryHostHealth.healthy;
    if (!activated) {
      throw ProductException(
        'recovery_candidate_not_active',
        'The recovery host did not finish with the verified candidate active and healthy.',
      );
    }
    final beforeHash = Sha256.text(canonicalJson(before.toJson()));
    final afterHash = Sha256.text(canonicalJson(after.toJson()));
    return RecoveryActionResult(
      summary: 'Activated verified recovery candidate ${identity.version}.',
      evidenceReferences: <String>[
        ...failure.evidenceReferences,
        'recoveryHost:${identity.artifactIdentity}',
      ],
      beforeFingerprint: beforeHash,
      afterFingerprint: afterHash,
      materialProgress: beforeHash != afterHash,
    );
  }
}

/// One autonomic supervisor per ProductRuntime. It watches canonical run
/// failures; recovery-generated child runs are excluded to avoid recursive
/// concurrent repair. Linked user-task continuations remain visible so a
/// recurrence advances the bounded strategy ladder.
final class ProductRuntimeAutonomicRecovery {
  factory ProductRuntimeAutonomicRecovery.shared(ProductRuntime runtime) {
    final existing = _shared[runtime];
    if (existing != null) return existing;
    final created = ProductRuntimeAutonomicRecovery._(runtime);
    _shared[runtime] = created;
    return created;
  }

  ProductRuntimeAutonomicRecovery._(this.runtime) {
    awareness = ProductSelfAwarenessRuntime.shared(runtime);
    contextResolver = ProductRuntimeFailureSelfContextResolver(runtime);
    experiences = ProductRuntimeRecoveryExperienceStore(runtime);
    taskRouter = ProductRuntimeRecoveryTaskRouter(runtime, _internalRunIds);
    supervisor = FailureSupervisor(
      selfModel: awareness.selfModel,
      journal: ProductRuntimeFailureJournal(runtime),
      events: ProductRuntimeRecoveryEventSink(runtime),
      router: taskRouter,
      actuator: ProductRuntimeRecoveryActuator(runtime),
      verifier: ProductRuntimeRecoveryVerifier(runtime, contextResolver),
      authority: ProductRuntimeRecoveryAuthorityGate(runtime),
      selfRepair: ProductRuntimeSelfRepairCoordinator(runtime),
      selfContext: contextResolver,
      experiences: experiences,
      causalGraph: awareness.causalGraph,
    );
    _subscription = runtime.eventStream.listen(_onRuntimeEvent);
  }

  static final Expando<ProductRuntimeAutonomicRecovery> _shared =
      Expando<ProductRuntimeAutonomicRecovery>('kristin-autonomic-recovery');

  final ProductRuntime runtime;
  final Set<String> _internalRunIds = <String>{};
  late final ProductSelfAwarenessRuntime awareness;
  late final ProductRuntimeFailureSelfContextResolver contextResolver;
  late final ProductRuntimeRecoveryExperienceStore experiences;
  late final ProductRuntimeRecoveryTaskRouter taskRouter;
  late final FailureSupervisor supervisor;
  StreamSubscription<EventEnvelope>? _subscription;
  final Set<String> _handledFailureEvents = <String>{};

  void _onRuntimeEvent(EventEnvelope event) {
    if (event.type != 'run.failed') return;
    final runId = event.data['runId']?.toString() ?? event.correlationId;
    if (runId.isEmpty || _internalRunIds.contains(runId)) return;
    if (!_handledFailureEvents.add(event.id)) return;
    if (_handledFailureEvents.length > 1024) {
      _handledFailureEvents.remove(_handledFailureEvents.first);
    }
    unawaited(_handleRunFailure(event, runId));
  }

  Future<void> _handleRunFailure(EventEnvelope event, String runId) async {
    try {
      final run = await runtime.getRun(runId);
      if (run == null) return;
      final message = runtime.redactor.redact(
        event.data['error']?.toString() ?? run.failure ?? 'Run failed.',
      );
      final failure = FailureEvent(
        severity: FailureSeverity.error,
        category: _categoryFor(message, operation: 'run.execute'),
        subsystem: 'run',
        operation: 'execute',
        message: message,
        runId: run.id,
        workItemId: event.data['workItemId']?.toString(),
        projectId: run.command.contract.projectId,
        modelExactId: run.command.model.exactId,
        errorCode: _errorCode(message),
        expectedState: 'The original governed run reaches succeeded state.',
        stateBefore: <String, Object?>{
          'runId': run.id,
          'state': run.state.name,
          'sourceRunId': run.sourceRunId,
        },
        requiredAuthority: run.command.contract.requiredPermissions
            .map((scope) => scope.name)
            .toSet(),
        evidenceReferences: <String>['runtimeEvent:${event.id}'],
      );
      await supervisor.handle(failure);
    } catch (error) {
      await runtime.events.publish(
        'recovery.supervisor_failed',
        runId,
        <String, dynamic>{
          'runId': runId,
          'error': runtime.redactor.redact('$error'),
        },
      );
    }
  }

  Future<RecoveryVerification?> handleOperationalFailure({
    required String operation,
    required Object error,
    String? projectId,
    String? modelExactId,
    String? capabilityId,
    Set<String> requiredAuthority = const <String>{},
    Map<String, Object?> stateBefore = const <String, Object?>{},
    Map<String, Object?> stateAfter = const <String, Object?>{},
  }) async {
    final message = runtime.redactor.redact('$error');
    final failure = FailureEvent(
      severity: FailureSeverity.error,
      category: _categoryFor(message, operation: operation),
      subsystem: operation.contains('.')
          ? operation.split('.').first
          : 'runtime',
      operation: operation,
      message: message,
      projectId: projectId,
      modelExactId: modelExactId,
      capabilityId: capabilityId,
      errorCode: _errorCode(message),
      requiredAuthority: requiredAuthority,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
    );
    return supervisor.handle(failure);
  }

  FailureCategory _categoryFor(String message, {required String operation}) {
    final lower = '$operation $message'.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('authority') ||
        lower.contains('approval')) {
      return FailureCategory.permission;
    }
    if (lower.contains('browser') || lower.contains('playwright')) {
      return FailureCategory.browser;
    }
    if (lower.contains('provider') ||
        lower.contains('model') ||
        lower.contains('ollama')) {
      return FailureCategory.provider;
    }
    if (lower.contains('dependency') ||
        lower.contains('package') ||
        lower.contains('lockfile')) {
      return FailureCategory.dependency;
    }
    if (operation.contains('start') ||
        operation.contains('stop') ||
        operation.contains('restart') ||
        lower.contains('process')) {
      return FailureCategory.process;
    }
    if (operation.startsWith('project.')) return FailureCategory.project;
    if (operation.startsWith('research.')) return FailureCategory.provider;
    return FailureCategory.execution;
  }

  String? _errorCode(String message) {
    final match = RegExp(
      r'\b([a-z][a-z0-9_]{3,})\s*:',
    ).firstMatch(message.toLowerCase());
    return match?.group(1);
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
