import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';
import 'package:kristin_local_agent/product/model/model_registry.dart' as direct;

const String digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String digestB =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String benchmarkEvidenceSha =
    'sha256:aa9351c8d629a6eb591756bc6eec3252a49f27b11b970ab329c2b17b65cd92f7';

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
      'evidence': <String, Object?>{
        'locationKind': 'embedded_content_addressed',
        'sha256': benchmarkEvidenceSha,
        'payload': <String, Object?>{
          'schemaVersion': '1.0.0',
          'kind': 'MODEL_BENCHMARK_RESULT',
          'candidateCommit': '1111111111111111111111111111111111111111',
          'candidateTree': '2222222222222222222222222222222222222222',
          'benchmarkId': 'p6.code-fixture-v1',
          'taskClassId': 'code-generation',
          'modelDigest': digestA,
          'score': 0.91,
          'scoreUnit': 'ratio',
          'higherIsBetter': true,
          'sampleCount': 100,
          'measuredAt': '2026-08-06T00:00:00.000Z',
        },
      },
    };

direct.ModelBenchmarkEvidence _directBenchmark() =>
    direct.ModelBenchmarkEvidence.fromJson(_benchmarkJson());

ModelBenchmarkEvidence _benchmark() =>
    ModelBenchmarkEvidence.fromJson(_benchmarkJson());

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
