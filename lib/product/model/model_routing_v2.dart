import 'dart:convert';
import 'dart:io';

import '../crypto_utils.dart';
import '../domain.dart';
import 'model_registry.dart';

enum ModelRoleV2 {
  planner,
  executor,
  verifier,
  browserObserver,
  extractor,
  reviewer,
}

extension ModelRoleV2Wire on ModelRoleV2 {
  String get wireName => switch (this) {
        ModelRoleV2.planner => 'planner',
        ModelRoleV2.executor => 'executor',
        ModelRoleV2.verifier => 'verifier',
        ModelRoleV2.browserObserver => 'browser_observer',
        ModelRoleV2.extractor => 'extractor',
        ModelRoleV2.reviewer => 'reviewer',
      };
}

enum ModelRoleOperationV2 {
  proposePlan,
  executeAction,
  verifyCriterion,
  observeBrowser,
  extractData,
  reviewResult,
  grantAuthority,
}

class ModelRoleAuthorityPolicyV2 {
  const ModelRoleAuthorityPolicyV2();

  bool allows(ModelRoleV2 role, ModelRoleOperationV2 operation) {
    if (operation == ModelRoleOperationV2.grantAuthority) return false;
    return switch (role) {
      ModelRoleV2.planner => operation == ModelRoleOperationV2.proposePlan,
      ModelRoleV2.executor => operation == ModelRoleOperationV2.executeAction,
      ModelRoleV2.verifier => operation == ModelRoleOperationV2.verifyCriterion,
      ModelRoleV2.browserObserver =>
        operation == ModelRoleOperationV2.observeBrowser,
      ModelRoleV2.extractor => operation == ModelRoleOperationV2.extractData,
      ModelRoleV2.reviewer => operation == ModelRoleOperationV2.reviewResult,
    };
  }

  void requireAllowed(ModelRoleV2 role, ModelRoleOperationV2 operation) {
    if (!allows(role, operation)) {
      throw StateError(
        'model_role_operation_denied:${role.wireName}:${operation.name}',
      );
    }
  }
}

class ModelRoleRouteV2 {
  ModelRoleRouteV2({
    required this.role,
    required this.taskClassId,
    required List<String> preferredExactModelIds,
  }) : preferredExactModelIds =
            List<String>.unmodifiable(preferredExactModelIds) {
    if (taskClassId.trim().isEmpty ||
        !RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(taskClassId)) {
      throw const ModelRegistryValidationException(
        'model routing taskClassId must be a stable lowercase id',
      );
    }
    if (this.preferredExactModelIds.isEmpty ||
        this.preferredExactModelIds.any((value) => value.trim().isEmpty) ||
        this.preferredExactModelIds.toSet().length !=
            this.preferredExactModelIds.length) {
      throw const ModelRegistryValidationException(
        'model routing preferences must be non-empty and unique',
      );
    }
  }

  final ModelRoleV2 role;
  final String taskClassId;
  final List<String> preferredExactModelIds;

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role.wireName,
        'taskClassId': taskClassId,
        'preferredExactModelIds': preferredExactModelIds,
      };
}

class ModelRoutingPolicyV2 {
  ModelRoutingPolicyV2({
    required this.policyId,
    required this.revision,
    required List<ModelRoleRouteV2> routes,
  }) : routes = Map<ModelRoleV2, ModelRoleRouteV2>.unmodifiable(
          <ModelRoleV2, ModelRoleRouteV2>{
            for (final route in routes) route.role: route,
          },
        ) {
    if (policyId.trim().isEmpty || revision <= 0) {
      throw const ModelRegistryValidationException(
        'model routing policy identity is invalid',
      );
    }
    if (routes.length != this.routes.length) {
      throw const ModelRegistryValidationException(
        'model routing policy contains duplicate roles',
      );
    }
    final missing = ModelRoleV2.values
        .where((role) => !this.routes.containsKey(role))
        .map((role) => role.wireName)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw ModelRegistryValidationException(
        'model routing policy is missing roles: ${missing.join(', ')}',
      );
    }
  }

  final String policyId;
  final int revision;
  final Map<ModelRoleV2, ModelRoleRouteV2> routes;

  ModelRoleRouteV2 routeFor(ModelRoleV2 role) => routes[role]!;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'policyId': policyId,
        'revision': revision,
        'routes': ModelRoleV2.values
            .map((role) => routes[role]!.toJson())
            .toList(growable: false),
      };

  String get sha256 => Sha256.text(canonicalJson(toJson()));
}

class ModelRoutingDecisionV2 {
  ModelRoutingDecisionV2({
    required this.role,
    required this.taskClassId,
    required this.model,
    required this.policyId,
    required this.policyRevision,
    required this.policySha256,
    required this.decidedAt,
    required this.reason,
  });

  final ModelRoleV2 role;
  final String taskClassId;
  final ModelIdentity model;
  final String policyId;
  final int policyRevision;
  final String policySha256;
  final DateTime decidedAt;
  final String reason;

  Map<String, Object?> _body() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'role': role.wireName,
        'taskClassId': taskClassId,
        'model': model.toJson(),
        'policyId': policyId,
        'policyRevision': policyRevision,
        'policySha256': policySha256,
        'decidedAt': decidedAt.toUtc().toIso8601String(),
        'reason': reason,
      };

  String get decisionSha256 => Sha256.text(canonicalJson(_body()));

  Map<String, Object?> toJson() => <String, Object?>{
        ..._body(),
        'decisionSha256': decisionSha256,
      };
}

abstract interface class ModelRoutingDecisionStoreV2 {
  Future<void> append(ModelRoutingDecisionV2 decision);
}

class JsonlModelRoutingDecisionStoreV2 implements ModelRoutingDecisionStoreV2 {
  JsonlModelRoutingDecisionStoreV2(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> append(ModelRoutingDecisionV2 decision) {
    final next = _tail.then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${jsonEncode(decision.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    _tail = next.catchError((Object _) {});
    return next;
  }
}

class ModelRoleRouterV2 {
  ModelRoleRouterV2({
    required this.registry,
    required this.policy,
    required this.decisionStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ModelDefinitionRegistry registry;
  final ModelRoutingPolicyV2 policy;
  final ModelRoutingDecisionStoreV2 decisionStore;
  final DateTime Function() _clock;

  Future<ModelRoutingDecisionV2> route({
    required ModelRoleV2 role,
    required Iterable<ModelIdentity> discoveredModels,
  }) async {
    final route = policy.routeFor(role);
    final candidates = <String, ModelIdentity>{};
    for (final identity in discoveredModels) {
      candidates.putIfAbsent(identity.exactId, () => identity);
    }
    final rejected = <String>[];
    for (final preferred in route.preferredExactModelIds) {
      final identity = candidates[preferred];
      if (identity == null) {
        rejected.add('$preferred:not_discovered');
        continue;
      }
      try {
        registry.requireApproved(
          identity: identity,
          taskClassId: route.taskClassId,
        );
        final decision = ModelRoutingDecisionV2(
          role: role,
          taskClassId: route.taskClassId,
          model: identity,
          policyId: policy.policyId,
          policyRevision: policy.revision,
          policySha256: policy.sha256,
          decidedAt: _clock().toUtc(),
          reason: 'first_policy_preference_with_exact_task_class_approval',
        );
        await decisionStore.append(decision);
        return decision;
      } on ModelRegistryValidationException catch (error) {
        rejected.add('$preferred:${Sha256.text(error.message)}');
      }
    }
    throw ModelRegistryValidationException(
      'no approved model route for ${role.wireName}; rejected=${rejected.join(',')}',
    );
  }
}
