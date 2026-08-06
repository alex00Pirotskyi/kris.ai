import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';
import 'package:kristin_local_agent/product/model/model_registry.dart' as direct;

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

ModelBenchmarkEvidence _benchmark() => ModelBenchmarkEvidence(
      benchmarkId: 'p6.code-fixture-v1',
      taskClassId: 'code-generation',
      modelDigest: 'sha256:registered',
      score: 1,
      scoreUnit: 'ratio',
      higherIsBetter: true,
      sampleCount: 1,
      measuredAt: DateTime.utc(2026, 8, 6),
      evidenceUri: 'release/evidence/P6-001/benchmark.json',
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
      digest: 'sha256:registered',
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

ModelIdentity _changedIdentity({String name = 'qwen3:14b'}) => ModelIdentity(
      providerId: 'ollama.local',
      name: name,
      digest: 'sha256:changed',
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      discoveredAt: DateTime.utc(2026, 8, 6),
    );

void main() {
  group('P6-001 public model-registry contract', () {
    test('direct core import cannot bypass artifact identity validation', () {
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
            digest: 'sha256:registered',
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
            benchmarks: <direct.ModelBenchmarkEvidence>[
              direct.ModelBenchmarkEvidence(
                benchmarkId: 'p6.code-fixture-v1',
                taskClassId: 'code-generation',
                modelDigest: 'sha256:registered',
                score: 1,
                scoreUnit: 'ratio',
                higherIsBetter: true,
                sampleCount: 1,
                measuredAt: DateTime.utc(2026, 8, 6),
                evidenceUri: 'release/evidence/P6-001/benchmark.json',
              ),
            ],
            approvedTaskClasses: const <String>['code-generation'],
          ),
        ],
      );

      for (final name in <String>['qwen3:14b', 'qwen3-latest']) {
        final resolved = registry.resolveDiscovered(
          ModelIdentity(
            providerId: 'ollama.local',
            name: name,
            digest: 'sha256:changed',
            parameterSize: '14B',
            quantization: 'Q4_K_M',
            discoveredAt: DateTime.utc(2026, 8, 6),
          ),
        );
        expect(resolved.supportStatus, direct.ModelSupportStatus.evaluationOnly);
        expect(resolved.approvedTaskClasses, isEmpty);
        expect(resolved.modelId, startsWith('$name:identity-mismatch:'));
      }
    });

    test('direct core import rejects cross-artifact benchmark evidence', () {
      expect(
        () => direct.ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'replacement:latest',
          displayName: 'Replacement',
          digest: 'sha256:replacement',
          parameterSize: '14B',
          quantization: 'Q4_K_M',
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
          benchmarks: <direct.ModelBenchmarkEvidence>[
            direct.ModelBenchmarkEvidence(
              benchmarkId: 'p6.code-fixture-v1',
              taskClassId: 'code-generation',
              modelDigest: 'sha256:registered',
              score: 1,
              scoreUnit: 'ratio',
              higherIsBetter: true,
              sampleCount: 1,
              measuredAt: DateTime.utc(2026, 8, 6),
              evidenceUri: 'release/evidence/P6-001/benchmark.json',
            ),
          ],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<direct.ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('belongs to artifact sha256:registered'),
              contains('expected sha256:replacement'),
            ),
          ),
        ),
      );
    });

    test('approved records require an immutable artifact digest', () {
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
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('artifact digest is required for approval'),
          ),
        ),
      );

      final raw = _approved().toJson();
      raw['digest'] = null;
      expect(
        () => ModelDefinition.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('artifact digest is required for approval'),
          ),
        ),
      );
    });

    test('quarantine IDs are deterministic and model-ID safe', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approved()],
      );
      final identity = _changedIdentity();

      final first = registry.resolveDiscovered(identity);
      final second = registry.resolveDiscovered(identity);

      expect(first.modelId, second.modelId);
      expect(first.modelId, matches(RegExp(r'^[A-Za-z0-9._:/+-]+$')));
      expect(first.modelId, isNot(contains('=')));
      expect(first.supportStatus, ModelSupportStatus.evaluationOnly);
    });

    test('malformed discovered IDs fail closed before lookup', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[_approved()],
      );

      expect(
        () => registry.resolveDiscovered(
          ModelIdentity(
            providerId: ' ollama.local',
            name: 'qwen3:14b',
            digest: 'sha256:registered',
            parameterSize: '14B',
            quantization: 'Q4_K_M',
            discoveredAt: DateTime.utc(2026, 8, 6),
          ),
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
      expect(
        () => registry.resolveDiscovered(
          ModelIdentity(
            providerId: 'ollama.local',
            name: ' qwen3:14b',
            digest: 'sha256:registered',
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
