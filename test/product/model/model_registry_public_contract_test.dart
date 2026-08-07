import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/key_registry_v2.dart';
import 'package:kristin_local_agent/product/model/model.dart';
import 'package:kristin_local_agent/product/model/model_registry.dart'
    as direct;

const String digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String digestB =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String candidateCommit = '954f231fa28a22c85e0be3a76205cc31635f6466';
const String candidateTree = '34aa8b80adc34255ca04986c2368759a05a3dfc9';
const String benchmarkExecutionId = 'p6-fixture-run-001';
const String benchmarkEvidenceSha =
    'sha256:97567a8820af860646654e4f4f3a5dab01c62eeea9a51ff3c22aa04099a46a5c';
const String benchmarkAuthorityKeyId = 'p6-benchmark-test';
const String benchmarkAuthorityPublicKey =
    '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
const String benchmarkAuthoritySignature =
    '3e620ee2d983baa3b1c450020c676fb50c2824c33d335ab6266a0311334e074c'
    'ddf694726663b106c024eec83e5aebd796af11d2edfb07ba59445c276e949d06';

ModelLimits _limits() => ModelLimits(
      evidenceLevel: ModelEvidenceLevel.measured,
      contextWindowTokens: 32768,
      maxOutputTokens: 4096,
      maxConcurrentRequests: 1,
      maxToolCallsPerTurn: 0,
      supportsStreaming: true,
    );

ModelToolProfile _tools() => ModelToolProfile(
      evidenceLevel: ModelEvidenceLevel.measured,
      supportsToolCalling: false,
      supportsStructuredOutput: true,
      supportsParallelToolCalls: false,
    );

Map<String, Object?> _benchmarkJson() => <String, Object?>{
      'benchmarkId': 'p6.code-fixture-v1',
      'taskClassId': 'code-generation',
      'modelDigest': digestA,
      'score': 0.91,
      'scoreUnit': 'ratio',
      'higherIsBetter': true,
      'sampleCount': 100,
      'measuredAt': '2026-08-06T00:00:00.000Z',
      'executionId': benchmarkExecutionId,
      'evidence': <String, Object?>{
        'locationKind': 'embedded_content_addressed',
        'sha256': benchmarkEvidenceSha,
        'payload': <String, Object?>{
          'schemaVersion': '1.0.0',
          'kind': 'MODEL_BENCHMARK_RESULT',
          'candidateCommit': candidateCommit,
          'candidateTree': candidateTree,
          'executionId': benchmarkExecutionId,
          'benchmarkId': 'p6.code-fixture-v1',
          'taskClassId': 'code-generation',
          'modelDigest': digestA,
          'score': 0.91,
          'scoreUnit': 'ratio',
          'higherIsBetter': true,
          'sampleCount': 100,
          'measuredAt': '2026-08-06T00:00:00.000Z',
        },
        'authority': <String, Object?>{
          'kind': 'ed25519_protected_key',
          'keyId': benchmarkAuthorityKeyId,
          'signature': benchmarkAuthoritySignature,
        },
      },
    };

ProtectedKeyRegistryV2 _trustedKeys() {
  final keys = ProtectedKeyRegistryV2();
  keys.register(
    const ProtectedKeyHandleV2(
      keyId: benchmarkAuthorityKeyId,
      purpose: ModelBenchmarkTrustContext.signerPurpose,
      provider: 'ephemeral_test',
      reference: 'test://p6-benchmark-authority',
      publicKeyHex: benchmarkAuthorityPublicKey,
      trustDomain: ModelBenchmarkTrustContext.trustDomain,
    ),
  );
  return keys;
}

direct.ModelBenchmarkTrustContext _directTrust() =>
    direct.ModelBenchmarkTrustContext(
      trustedKeys: _trustedKeys(),
      candidateTreesByCommit: const <String, String>{
        candidateCommit: candidateTree,
      },
    );

ModelBenchmarkTrustContext _trust() => ModelBenchmarkTrustContext(
      trustedKeys: _trustedKeys(),
      candidateTreesByCommit: const <String, String>{
        candidateCommit: candidateTree,
      },
    );

direct.ModelBenchmarkEvidence _directBenchmark() =>
    direct.ModelBenchmarkEvidence.fromJson(
      _benchmarkJson(),
      trustContext: _directTrust(),
    );

ModelBenchmarkEvidence _benchmark() => ModelBenchmarkEvidence.fromJson(
      _benchmarkJson(),
      trustContext: _trust(),
    );

ModelProviderDescriptor _provider() => ModelProviderDescriptor(
      providerId: 'ollama.local',
      displayName: 'Local Ollama',
      dataBoundary: ModelDataBoundary.localOnly,
    );

ModelDefinition _approved() => ModelDefinition.approved(
      providerId: 'ollama.local',
      modelId: 'qwen3:14b',
      displayName: 'Qwen 3 14B',
      digest: digestA,
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      aliases: const <String>['qwen3-latest'],
      limits: _limits(),
      toolProfile: _tools(),
      dataBoundary: ModelDataBoundary.localOnly,
      cost: ModelCostProfile.noDirectCharge(),
      benchmarks: <ModelBenchmarkEvidence>[_benchmark()],
      approvedTaskClasses: const <String>['code-generation'],
    );

ModelIdentity _identity({
  String name = 'qwen3:14b',
  String digest = digestA,
}) =>
    ModelIdentity(
      providerId: 'ollama.local',
      name: name,
      digest: digest,
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      discoveredAt: DateTime.utc(2026, 8, 6),
    );

void main() {
  group('P6-001 public model-registry contract', () {
    test('direct core import exposes metadata lookup but no approval predicate',
        () {
      final registry = direct.ModelDefinitionRegistry(
        providers: <direct.ModelProviderDescriptor>[
          direct.ModelProviderDescriptor(
            providerId: 'ollama.local',
            displayName: 'Local Ollama',
            dataBoundary: direct.ModelDataBoundary.localOnly,
          ),
        ],
        models: <direct.ModelDefinition>[
          direct.ModelDefinition.approved(
            providerId: 'ollama.local',
            modelId: 'qwen3:14b',
            displayName: 'Qwen 3 14B',
            digest: digestA,
            parameterSize: '14B',
            quantization: 'Q4_K_M',
            aliases: const <String>['qwen3-latest'],
            limits: direct.ModelLimits(
              evidenceLevel: direct.ModelEvidenceLevel.measured,
              contextWindowTokens: 32768,
              maxOutputTokens: 4096,
              maxConcurrentRequests: 1,
              maxToolCallsPerTurn: 0,
              supportsStreaming: true,
            ),
            toolProfile: direct.ModelToolProfile(
              evidenceLevel: direct.ModelEvidenceLevel.measured,
              supportsToolCalling: false,
              supportsStructuredOutput: true,
              supportsParallelToolCalls: false,
            ),
            dataBoundary: direct.ModelDataBoundary.localOnly,
            cost: direct.ModelCostProfile.noDirectCharge(),
            benchmarks: <direct.ModelBenchmarkEvidence>[_directBenchmark()],
            approvedTaskClasses: const <String>['code-generation'],
          ),
        ],
      );

      for (final name in <String>['qwen3:14b', 'qwen3-latest']) {
        final metadata = registry.lookup('ollama.local', name);
        expect(metadata, isA<direct.ModelRegistryMetadata>());
        final json = metadata!.toJson();
        expect(json.containsKey('supportStatus'), isFalse);
        expect(json.containsKey('approvedTaskClasses'), isFalse);
        expect(json.containsKey('evaluationReasons'), isFalse);
      }
      final registryJson = jsonEncode(registry.toMetadataJson());
      expect(registryJson, isNot(contains('supportStatus')));
      expect(registryJson, isNot(contains('approvedTaskClasses')));
    });

    test('direct core approval still requires exact discovered identity', () {
      final registry = direct.ModelDefinitionRegistry(
        providers: <direct.ModelProviderDescriptor>[
          direct.ModelProviderDescriptor(
            providerId: 'ollama.local',
            displayName: 'Local Ollama',
            dataBoundary: direct.ModelDataBoundary.localOnly,
          ),
        ],
        models: <direct.ModelDefinition>[
          direct.ModelDefinition.approved(
            providerId: 'ollama.local',
            modelId: 'qwen3:14b',
            displayName: 'Qwen 3 14B',
            digest: digestA,
            parameterSize: '14B',
            quantization: 'Q4_K_M',
            aliases: const <String>['qwen3-latest'],
            limits: direct.ModelLimits(
              evidenceLevel: direct.ModelEvidenceLevel.measured,
              contextWindowTokens: 32768,
              maxOutputTokens: 4096,
              maxConcurrentRequests: 1,
              maxToolCallsPerTurn: 0,
              supportsStreaming: true,
            ),
            toolProfile: direct.ModelToolProfile(
              evidenceLevel: direct.ModelEvidenceLevel.measured,
              supportsToolCalling: false,
              supportsStructuredOutput: true,
              supportsParallelToolCalls: false,
            ),
            dataBoundary: direct.ModelDataBoundary.localOnly,
            cost: direct.ModelCostProfile.noDirectCharge(),
            benchmarks: <direct.ModelBenchmarkEvidence>[_directBenchmark()],
            approvedTaskClasses: const <String>['code-generation'],
          ),
        ],
      );
      final handle = registry.requireApproved(
        identity: _identity(name: 'qwen3-latest'),
        taskClassId: 'code-generation',
      );
      expect(handle.model.registryKey, 'ollama.local::qwen3:14b');
      expect(
        () => registry.requireApproved(
          identity: _identity(name: 'qwen3-latest', digest: digestB),
          taskClassId: 'code-generation',
        ),
        throwsA(isA<direct.ModelRegistryValidationException>()),
      );
    });

    test('direct core rejects malformed immutable digest identities', () {
      expect(
        () => direct.ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'bad',
          displayName: 'Bad',
          digest: 'latest',
          limits: direct.ModelLimits(
            evidenceLevel: direct.ModelEvidenceLevel.measured,
            contextWindowTokens: 4096,
            maxOutputTokens: 1024,
            maxConcurrentRequests: 1,
            maxToolCallsPerTurn: 0,
            supportsStreaming: false,
          ),
          toolProfile: direct.ModelToolProfile(
            evidenceLevel: direct.ModelEvidenceLevel.measured,
            supportsToolCalling: false,
            supportsStructuredOutput: false,
            supportsParallelToolCalls: false,
          ),
          dataBoundary: direct.ModelDataBoundary.localOnly,
          cost: direct.ModelCostProfile.noDirectCharge(),
          benchmarks: <direct.ModelBenchmarkEvidence>[_directBenchmark()],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<direct.ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('canonical sha256:<64 lowercase hex>'),
          ),
        ),
      );
    });

    test('direct core import cannot turn self-authored evidence into approval',
        () {
      final raw = _benchmarkJson();
      (raw['evidence'] as Map<String, Object?>).remove('authority');
      final untrusted = direct.ModelBenchmarkEvidence.fromJson(raw);
      expect(untrusted.hasTrustedExecutionReceipt, isFalse);
      expect(
        () => direct.ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'self-authored',
          displayName: 'Self-authored',
          digest: digestA,
          limits: direct.ModelLimits(
            evidenceLevel: direct.ModelEvidenceLevel.measured,
            contextWindowTokens: 4096,
            maxOutputTokens: 1024,
            maxConcurrentRequests: 1,
            maxToolCallsPerTurn: 0,
            supportsStreaming: false,
          ),
          toolProfile: direct.ModelToolProfile(
            evidenceLevel: direct.ModelEvidenceLevel.measured,
            supportsToolCalling: false,
            supportsStructuredOutput: false,
            supportsParallelToolCalls: false,
          ),
          dataBoundary: direct.ModelDataBoundary.localOnly,
          cost: direct.ModelCostProfile.noDirectCharge(),
          benchmarks: <direct.ModelBenchmarkEvidence>[untrusted],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<direct.ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('no trusted execution authority'),
          ),
        ),
      );
    });

    test('content-addressed benchmark evidence rejects digest tampering', () {
      final json = _benchmarkJson();
      (json['evidence'] as Map<String, Object?>)['sha256'] = digestB;
      expect(
        () => direct.ModelBenchmarkEvidence.fromJson(json),
        throwsA(
          isA<direct.ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('benchmark evidence digest mismatch'),
          ),
        ),
      );
    });

    test('approved records still require immutable artifact identity', () {
      expect(
        () => ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'digestless',
          displayName: 'Digestless',
          limits: _limits(),
          toolProfile: _tools(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          benchmarks: <ModelBenchmarkEvidence>[_benchmark()],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('quarantine IDs remain deterministic and model-ID safe', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approved()],
      );
      final identity = _identity(digest: digestB);
      final first = registry.resolveDiscovered(identity);
      final second = registry.resolveDiscovered(identity);
      expect(first.model.modelId, second.model.modelId);
      expect(first.model.modelId, matches(RegExp(r'^[A-Za-z0-9._:/+-]+$')));
      expect(first.model.modelId, isNot(contains('=')));
      expect(first.isEvaluationOnly, isTrue);
    });

    test('malformed discovered IDs fail closed before metadata lookup', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approved()],
      );
      expect(
        () => registry.resolveDiscovered(
          ModelIdentity(
            providerId: ' ollama.local',
            name: 'qwen3:14b',
            digest: digestA,
            parameterSize: '14B',
            quantization: 'Q4_K_M',
            discoveredAt: DateTime.utc(2026, 8, 6),
          ),
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });
  });
}
