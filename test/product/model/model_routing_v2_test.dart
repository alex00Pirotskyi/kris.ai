import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/key_registry_v2.dart';
import 'package:kristin_local_agent/product/model/model.dart';
import 'package:kristin_local_agent/product/model/model_routing_v2.dart';

const String _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _candidateCommit = '954f231fa28a22c85e0be3a76205cc31635f6466';
const String _candidateTree = '34aa8b80adc34255ca04986c2368759a05a3dfc9';
const String _executionId = 'p6-fixture-run-001';
const String _evidenceSha =
    'sha256:97567a8820af860646654e4f4f3a5dab01c62eeea9a51ff3c22aa04099a46a5c';
const String _authorityKeyId = 'p6-benchmark-test';
const String _authorityPublicKey =
    '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
const String _authoritySignature =
    '3e620ee2d983baa3b1c450020c676fb50c2824c33d335ab6266a0311334e074c'
    'ddf694726663b106c024eec83e5aebd796af11d2edfb07ba59445c276e949d06';

final class _MemoryDecisionStore implements ModelRoutingDecisionStoreV2 {
  final List<ModelRoutingDecisionV2> decisions = <ModelRoutingDecisionV2>[];

  @override
  Future<void> append(ModelRoutingDecisionV2 decision) async {
    decisions.add(decision);
  }
}

ModelBenchmarkTrustContext _trust() {
  final keys = ProtectedKeyRegistryV2()
    ..register(
      ProtectedKeyHandleV2(
        keyId: _authorityKeyId,
        purpose: ModelBenchmarkTrustContext.signerPurpose,
        provider: 'ephemeral_test',
        reference: 'test://p6-routing-authority',
        publicKeyHex: _authorityPublicKey,
        trustDomain: ModelBenchmarkTrustContext.trustDomain,
      ),
    );
  return ModelBenchmarkTrustContext(
    trustedKeys: keys,
    candidateTreesByCommit: const <String, String>{
      _candidateCommit: _candidateTree,
    },
  );
}

ModelBenchmarkEvidence _benchmark() => ModelBenchmarkEvidence.fromJson(
      <String, Object?>{
        'benchmarkId': 'p6.code-fixture-v1',
        'taskClassId': 'code-generation',
        'modelDigest': _digest,
        'score': 0.91,
        'scoreUnit': 'ratio',
        'higherIsBetter': true,
        'sampleCount': 100,
        'measuredAt': '2026-08-06T00:00:00.000Z',
        'executionId': _executionId,
        'evidence': <String, Object?>{
          'locationKind': 'embedded_content_addressed',
          'sha256': _evidenceSha,
          'payload': <String, Object?>{
            'schemaVersion': '1.0.0',
            'kind': 'MODEL_BENCHMARK_RESULT',
            'candidateCommit': _candidateCommit,
            'candidateTree': _candidateTree,
            'executionId': _executionId,
            'benchmarkId': 'p6.code-fixture-v1',
            'taskClassId': 'code-generation',
            'modelDigest': _digest,
            'score': 0.91,
            'scoreUnit': 'ratio',
            'higherIsBetter': true,
            'sampleCount': 100,
            'measuredAt': '2026-08-06T00:00:00.000Z',
          },
          'authority': <String, Object?>{
            'kind': 'ed25519_protected_key',
            'keyId': _authorityKeyId,
            'signature': _authoritySignature,
          },
        },
      },
      trustContext: _trust(),
    );

ModelDefinitionRegistry _registry() => ModelDefinitionRegistry(
      providers: <ModelProviderDescriptor>[
        ModelProviderDescriptor(
          providerId: 'ollama.local',
          displayName: 'Local Ollama',
          dataBoundary: ModelDataBoundary.localOnly,
        ),
      ],
      models: <ModelDefinition>[
        ModelDefinition.approved(
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
          benchmarks: <ModelBenchmarkEvidence>[_benchmark()],
          approvedTaskClasses: const <String>['code-generation'],
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

    test('router selects and records first exact approved model', () async {
      final store = _MemoryDecisionStore();
      final policy = _policy(
        executorPreferences: <String>[
          'ollama.local/missing@$_digest',
          'ollama.local/qwen3:14b@$_digest',
        ],
      );
      final decision = await _router(store: store, policy: policy).route(
        role: ModelRoleV2.executor,
        discoveredModels: <ModelIdentity>[_identity()],
      );

      expect(decision.role, ModelRoleV2.executor);
      expect(decision.taskClassId, 'code-generation');
      expect(decision.model.exactId, 'ollama.local/qwen3:14b@$_digest');
      expect(decision.policySha256, policy.sha256);
      expect(decision.toJson()['decisionSha256'], decision.decisionSha256);
      expect(decision.decisionSha256, hasLength(64));
      expect(store.decisions, hasLength(1));
      expect(store.decisions.single.decisionSha256, decision.decisionSha256);
    });

    test('JSONL store flushes a hash-bound durable routing record', () async {
      final directory = await Directory.systemTemp.createTemp('p6-routing-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/routing.jsonl');
      final decision = await _router(
        store: JsonlModelRoutingDecisionStoreV2(file),
      ).route(
        role: ModelRoleV2.verifier,
        discoveredModels: <ModelIdentity>[_identity()],
      );

      expect(await file.exists(), isTrue);
      final lines = await file.readAsLines();
      expect(lines, hasLength(1));
      final json = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(json['role'], 'verifier');
      expect(json['policySha256'], _policy().sha256);
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
