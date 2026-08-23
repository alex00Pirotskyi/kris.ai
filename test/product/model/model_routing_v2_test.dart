import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';

const String _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final class _MemoryDecisionStore implements ModelRoutingDecisionStoreV2 {
  final List<ModelRoutingDecisionV2> decisions = <ModelRoutingDecisionV2>[];

  @override
  Future<void> append(ModelRoutingDecisionV2 decision) async {
    decisions.add(decision);
  }
}

ModelDefinitionRegistry _registry() => ModelDefinitionRegistry(
      providers: <ModelProviderDescriptor>[
        ModelProviderDescriptor(
          providerId: 'ollama.local',
          displayName: 'Local Ollama',
          dataBoundary: ModelDataBoundary.localOnly,
        ),
      ],
      models: <ModelDefinition>[
        ModelDefinition.evaluationOnly(
          providerId: 'ollama.local',
          modelId: 'qwen3:14b',
          displayName: 'Qwen 3 14B',
          digest: _digest,
          parameterSize: '14B',
          quantization: 'Q4_K_M',
          limits: ModelLimits(
            evidenceLevel: ModelEvidenceLevel.measured,
            contextWindowTokens: 32768,
            maxOutputTokens: 4096,
            maxConcurrentRequests: 1,
            maxToolCallsPerTurn: 0,
            supportsStreaming: true,
          ),
          toolProfile: ModelToolProfile(
            evidenceLevel: ModelEvidenceLevel.measured,
            supportsToolCalling: false,
            supportsStructuredOutput: true,
            supportsParallelToolCalls: false,
          ),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          evaluationReasons: const <String>[
            'host-controlled benchmark authority is not configured',
          ],
        ),
      ],
    );

ModelIdentity _identity({String name = 'qwen3:14b', String digest = _digest}) =>
    ModelIdentity(
      providerId: 'ollama.local',
      name: name,
      digest: digest,
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      discoveredAt: DateTime.utc(2026, 8, 23),
    );

ModelRoutingPolicyV2 _policy({List<String>? executorPreferences}) {
  final preferred = <String>['ollama.local/qwen3:14b@$_digest'];
  return ModelRoutingPolicyV2(
    policyId: 'desktop-default',
    revision: 3,
    routes: <ModelRoleRouteV2>[
      for (final role in ModelRoleV2.values)
        ModelRoleRouteV2(
          role: role,
          taskClassId: 'code-generation',
          preferredExactModelIds:
              role == ModelRoleV2.executor && executorPreferences != null
                  ? executorPreferences
                  : preferred,
        ),
    ],
  );
}

ModelRoleRouterV2 _router({
  required ModelRoutingDecisionStoreV2 store,
  ModelRoutingPolicyV2? policy,
}) =>
    ModelRoleRouterV2(
      registry: _registry(),
      policy: policy ?? _policy(),
      decisionStore: store,
      clock: () => DateTime.utc(2026, 8, 23, 16),
    );

void main() {
  group('P6-002/P6-003 role-based model routing', () {
    test('every role is explicit and no model role can grant authority', () {
      const authority = ModelRoleAuthorityPolicyV2();
      expect(
        authority.allows(
          ModelRoleV2.planner,
          ModelRoleOperationV2.proposePlan,
        ),
        isTrue,
      );
      expect(
        authority.allows(
          ModelRoleV2.executor,
          ModelRoleOperationV2.executeAction,
        ),
        isTrue,
      );
      expect(
        authority.allows(
          ModelRoleV2.verifier,
          ModelRoleOperationV2.verifyCriterion,
        ),
        isTrue,
      );
      for (final role in ModelRoleV2.values) {
        expect(
          authority.allows(role, ModelRoleOperationV2.grantAuthority),
          isFalse,
          reason: role.wireName,
        );
      }
      expect(
        () => authority.requireAllowed(
          ModelRoleV2.executor,
          ModelRoleOperationV2.verifyCriterion,
        ),
        throwsStateError,
      );
    });

    test('policy must define all six roles exactly once', () {
      expect(
        () => ModelRoutingPolicyV2(
          policyId: 'incomplete',
          revision: 1,
          routes: <ModelRoleRouteV2>[
            ModelRoleRouteV2(
              role: ModelRoleV2.executor,
              taskClassId: 'code-generation',
              preferredExactModelIds: <String>[
                'ollama.local/qwen3:14b@$_digest',
              ],
            ),
          ],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('evaluation-only models cannot be routed or persisted', () async {
      final store = _MemoryDecisionStore();
      final policy = _policy(
        executorPreferences: <String>[
          'ollama.local/missing@$_digest',
          'ollama.local/qwen3:14b@$_digest',
        ],
      );

      await expectLater(
        _router(store: store, policy: policy).route(
          role: ModelRoleV2.executor,
          discoveredModels: <ModelIdentity>[_identity()],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
      expect(store.decisions, isEmpty);
    });

    test('JSONL store flushes a hash-bound durable routing record', () async {
      final directory = await Directory.systemTemp.createTemp('p6-routing-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/routing.jsonl');
      final policy = _policy();
      final decision = ModelRoutingDecisionV2(
        role: ModelRoleV2.verifier,
        taskClassId: 'code-generation',
        model: _identity(),
        policyId: policy.policyId,
        policyRevision: policy.revision,
        policySha256: policy.sha256,
        decidedAt: DateTime.utc(2026, 8, 23, 16),
        reason: 'fixture_host_approved_route_record',
      );
      await JsonlModelRoutingDecisionStoreV2(file).append(decision);

      expect(await file.exists(), isTrue);
      final lines = await file.readAsLines();
      expect(lines, hasLength(1));
      final json = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(json['role'], 'verifier');
      expect(json['policySha256'], policy.sha256);
      expect(json['decisionSha256'], decision.decisionSha256);
    });

    test('identity-mismatched candidates never route or persist', () async {
      final store = _MemoryDecisionStore();
      await expectLater(
        _router(store: store).route(
          role: ModelRoleV2.executor,
          discoveredModels: <ModelIdentity>[
            _identity(
              digest:
                  'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
          ],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
      expect(store.decisions, isEmpty);
    });

    test('routing never falls outside the policy preference set', () async {
      final store = _MemoryDecisionStore();
      await expectLater(
        _router(
          store: store,
          policy: _policy(
            executorPreferences: <String>['ollama.local/missing@$_digest'],
          ),
        ).route(
          role: ModelRoleV2.executor,
          discoveredModels: <ModelIdentity>[_identity()],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
      expect(store.decisions, isEmpty);
    });
  });
}
