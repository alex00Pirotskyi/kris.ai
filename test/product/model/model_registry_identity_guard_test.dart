import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/key_registry_v2.dart';
import 'package:kristin_local_agent/product/model/model.dart';

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

ModelProviderDescriptor _provider() => ModelProviderDescriptor(
      providerId: 'ollama.local',
      displayName: 'Local Ollama',
      dataBoundary: ModelDataBoundary.localOnly,
    );

ModelBenchmarkTrustContext _benchmarkTrust() {
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
  return ModelBenchmarkTrustContext(
    trustedKeys: keys,
    candidateTreesByCommit: const <String, String>{
      candidateCommit: candidateTree,
    },
  );
}

ModelBenchmarkEvidence _benchmark() => ModelBenchmarkEvidence.fromJson(
      <String, Object?>{
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
      },
      trustContext: _benchmarkTrust(),
    );

ModelDefinition _approvedModel() => ModelDefinition.approved(
      providerId: 'ollama.local',
      modelId: 'qwen3:14b',
      displayName: 'Qwen 3 14B',
      digest: digestA,
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      aliases: const <String>['qwen3-latest'],
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
    );

ModelIdentity _identity({
  required String name,
  String digest = digestA,
  String parameterSize = '14B',
  String quantization = 'Q4_K_M',
}) =>
    ModelIdentity(
      providerId: 'ollama.local',
      name: name,
      digest: digest,
      parameterSize: parameterSize,
      quantization: quantization,
      discoveredAt: DateTime.utc(2026, 8, 6),
    );

void main() {
  group('P6-001 discovered identity guard', () {
    test(
        'exact canonical and alias identities resolve without granting by lookup',
        () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approvedModel()],
      );
      for (final name in <String>['qwen3:14b', 'qwen3-latest']) {
        final resolved = registry.resolveDiscovered(_identity(name: name));
        expect(resolved.isEvaluationOnly, isFalse);
        expect(resolved.model.registryKey, 'ollama.local::qwen3:14b');
        final handle = registry.requireApproved(
          identity: _identity(name: name),
          taskClassId: 'code-generation',
        );
        expect(handle.model.registryKey, 'ollama.local::qwen3:14b');
      }
    });

    for (final lookupName in <String>['qwen3:14b', 'qwen3-latest']) {
      test('$lookupName digest drift is quarantined evaluation-only', () {
        _expectQuarantined(
          lookupName: lookupName,
          changedField: 'digest',
          identity: _identity(name: lookupName, digest: digestB),
        );
      });
      test('$lookupName missing digest is quarantined evaluation-only', () {
        _expectQuarantined(
          lookupName: lookupName,
          changedField: 'digest',
          identity: _identity(name: lookupName, digest: ''),
        );
      });
      test('$lookupName parameter-size drift is quarantined evaluation-only',
          () {
        _expectQuarantined(
          lookupName: lookupName,
          changedField: 'parameterSize',
          identity: _identity(name: lookupName, parameterSize: '8B'),
        );
      });
      test('$lookupName quantization drift is quarantined evaluation-only', () {
        _expectQuarantined(
          lookupName: lookupName,
          changedField: 'quantization',
          identity: _identity(name: lookupName, quantization: 'Q8_0'),
        );
      });
    }

    test('quarantine identity is deterministic for repeated discovery', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approvedModel()],
      );
      final identity = _identity(name: 'qwen3-latest', digest: digestB);
      final first = registry.resolveDiscovered(identity);
      final second = registry.resolveDiscovered(identity);
      expect(second.model.modelId, first.model.modelId);
      expect(second.model.toJson(), first.model.toJson());
      expect(second.isEvaluationOnly, isTrue);
    });
  });
}

void _expectQuarantined({
  required String lookupName,
  required String changedField,
  required ModelIdentity identity,
}) {
  final registry = ModelDefinitionRegistry(
    providers: <ModelProviderDescriptor>[_provider()],
    models: <ModelDefinition>[_approvedModel()],
  );
  final resolved = registry.resolveDiscovered(identity);
  expect(resolved.isEvaluationOnly, isTrue);
  expect(resolved.model.modelId, startsWith('$lookupName:identity-mismatch:'));
  expect(resolved.evaluationReasons.join(' '), contains(changedField));
  expect(
    () => registry.requireApproved(
      identity: identity,
      taskClassId: 'code-generation',
    ),
    throwsA(
      isA<ModelRegistryValidationException>().having(
        (error) => error.message,
        'message',
        contains('is not approved for code-generation'),
      ),
    ),
  );
}
