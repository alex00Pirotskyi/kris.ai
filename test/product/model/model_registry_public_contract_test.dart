import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/key_registry_v2.dart';
import 'package:kristin_local_agent/product/model/model_registry.dart';

const String digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
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

ModelBenchmarkTrustContext _callerSuppliedTrust() {
  final keys = ProtectedKeyRegistryV2();
  keys.register(
    const ProtectedKeyHandleV2(
      keyId: benchmarkAuthorityKeyId,
      purpose: ModelBenchmarkTrustContext.signerPurpose,
      provider: 'caller_supplied',
      reference: 'caller://self-authored-benchmark-key',
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

void main() {
  group('P6-001 benchmark trust-root public contract', () {
    test('content-addressed benchmark metadata remains usable for evaluation',
        () {
      final benchmark = ModelBenchmarkEvidence.fromJson(_benchmarkJson());
      expect(benchmark.evidenceSha256, benchmarkEvidenceSha);
      expect(benchmark.candidateCommit, candidateCommit);
      expect(benchmark.candidateTree, candidateTree);
      expect(benchmark.hasTrustedExecutionReceipt, isFalse);
      expect(jsonEncode(benchmark.toJson()), contains(benchmarkEvidenceSha));
    });

    test('caller-supplied keys and candidate mappings never become trusted',
        () {
      final benchmark = ModelBenchmarkEvidence.fromJson(
        _benchmarkJson(),
        trustContext: _callerSuppliedTrust(),
      );
      expect(
        benchmark.hasTrustedExecutionReceipt,
        isFalse,
        reason: 'Public callers cannot be their own benchmark trust root.',
      );
    });

    test('caller-supplied benchmark trust cannot manufacture model approval',
        () {
      final benchmark = ModelBenchmarkEvidence.fromJson(
        _benchmarkJson(),
        trustContext: _callerSuppliedTrust(),
      );
      expect(
        () => ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'self-approved',
          displayName: 'Self approved',
          digest: digestA,
          parameterSize: '14B',
          quantization: 'Q4_K_M',
          limits: _limits(),
          toolProfile: _tools(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          benchmarks: <ModelBenchmarkEvidence>[benchmark],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('no trusted execution authority'),
          ),
        ),
      );
    });

    test('approved policy JSON fails closed without host benchmark authority',
        () {
      final raw = <String, Object?>{
        'providerId': 'ollama.local',
        'modelId': 'qwen3:14b',
        'displayName': 'Qwen 3 14B',
        'digest': digestA,
        'parameterSize': '14B',
        'quantization': 'Q4_K_M',
        'aliases': <String>['qwen3-latest'],
        'limits': _limits().toJson(),
        'toolProfile': _tools().toJson(),
        'dataBoundary': ModelDataBoundary.localOnly.wireName,
        'cost': ModelCostProfile.noDirectCharge().toJson(),
        'benchmarks': <Object?>[_benchmarkJson()],
        'approvedTaskClasses': <String>['code-generation'],
        'supportStatus': 'approved',
        'evaluationReasons': <String>[],
      };
      expect(
        () => ModelDefinition.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('no trusted execution authority'),
          ),
        ),
      );
      expect(
        () => ModelDefinition.fromJson(
          raw,
          benchmarkTrust: _callerSuppliedTrust(),
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('public source documents the host-controlled trust boundary', () {
      final source =
          File('lib/product/model/model_registry.dart').readAsStringSync();
      expect(source, contains('host-controlled benchmark authority'));
      expect(
        source,
        isNot(contains('trustedExecutionReceipt = true;')),
        reason: 'No public parse path may promote caller-provided trust.',
      );
    });
  });
}
