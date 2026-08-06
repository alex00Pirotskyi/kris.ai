import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';

ModelProviderDescriptor _provider() => ModelProviderDescriptor(
      providerId: 'ollama.local',
      displayName: 'Local Ollama',
      dataBoundary: ModelDataBoundary.localOnly,
    );

ModelDefinition _approvedModel() => ModelDefinition.approved(
      providerId: 'ollama.local',
      modelId: 'qwen3:14b',
      displayName: 'Qwen 3 14B',
      digest: 'sha256:0123456789abcdef',
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
      benchmarks: <ModelBenchmarkEvidence>[
        ModelBenchmarkEvidence(
          benchmarkId: 'p6.code-fixture-v1',
          taskClassId: 'code-generation',
          score: 0.91,
          scoreUnit: 'ratio',
          higherIsBetter: true,
          sampleCount: 100,
          measuredAt: DateTime.utc(2026, 8, 6),
          evidenceUri: 'release/evidence/P6-001/benchmark.json',
        ),
      ],
      approvedTaskClasses: const <String>['code-generation'],
    );

ModelIdentity _identity({
  required String name,
  String digest = 'sha256:0123456789abcdef',
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
    test('exact canonical and alias identities reuse the approved record', () {
      final approved = _approvedModel();
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_provider()],
        models: <ModelDefinition>[approved],
      );

      expect(
        registry.resolveDiscovered(_identity(name: 'qwen3:14b')),
        same(approved),
      );
      expect(
        registry.resolveDiscovered(_identity(name: 'qwen3-latest')),
        same(approved),
      );
    });

    for (final lookupName in <String>['qwen3:14b', 'qwen3-latest']) {
      test('$lookupName digest drift is quarantined evaluation-only', () {
        _expectQuarantined(
          lookupName: lookupName,
          changedField: 'digest',
          identity: _identity(
            name: lookupName,
            digest: 'sha256:changed-artifact',
          ),
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
      final identity = _identity(
        name: 'qwen3-latest',
        digest: 'sha256:changed-artifact',
      );

      final first = registry.resolveDiscovered(identity);
      final second = registry.resolveDiscovered(identity);

      expect(second.modelId, first.modelId);
      expect(second.toJson(), first.toJson());
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

  expect(resolved.supportStatus, ModelSupportStatus.evaluationOnly);
  expect(resolved.approvedTaskClasses, isEmpty);
  expect(
    resolved.modelId,
    startsWith('$lookupName:identity-mismatch:'),
  );
  expect(
    resolved.evaluationReasons.join(' '),
    contains(changedField),
  );
  expect(
    () => registry.requireApproved(
      providerId: resolved.providerId,
      modelIdOrAlias: resolved.modelId,
      taskClassId: 'code-generation',
    ),
    throwsA(
      isA<ModelRegistryValidationException>().having(
        (error) => error.message,
        'message',
        contains('is not registered'),
      ),
    ),
  );
}
