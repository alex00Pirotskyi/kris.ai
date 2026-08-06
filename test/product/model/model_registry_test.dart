import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';

ModelProviderDescriptor _localProvider({String providerId = 'ollama.local'}) {
  return ModelProviderDescriptor(
    providerId: providerId,
    displayName: 'Local Ollama',
    dataBoundary: ModelDataBoundary.localOnly,
  );
}

ModelLimits _measuredLimits() {
  return ModelLimits(
    evidenceLevel: ModelEvidenceLevel.measured,
    contextWindowTokens: 32768,
    maxOutputTokens: 4096,
    maxConcurrentRequests: 1,
    maxToolCallsPerTurn: 0,
    supportsStreaming: true,
  );
}

ModelToolProfile _measuredNoTools() {
  return ModelToolProfile(
    evidenceLevel: ModelEvidenceLevel.measured,
    supportsToolCalling: false,
    supportsStructuredOutput: true,
    supportsParallelToolCalls: false,
  );
}

ModelBenchmarkEvidence _benchmark({
  String benchmarkId = 'p6.code-fixture-v1',
  String taskClassId = 'code-generation',
  String modelDigest = 'sha256:0123456789abcdef',
}) {
  return ModelBenchmarkEvidence(
    benchmarkId: benchmarkId,
    taskClassId: taskClassId,
    modelDigest: modelDigest,
    score: 0.91,
    scoreUnit: 'ratio',
    higherIsBetter: true,
    sampleCount: 100,
    measuredAt: DateTime.utc(2026, 8, 6),
    evidenceUri: 'release/evidence/P6-001/benchmark.json',
  );
}

ModelDefinition _approvedModel({
  String providerId = 'ollama.local',
  String modelId = 'qwen3:14b',
  Iterable<String> aliases = const <String>['qwen3-latest'],
}) {
  return ModelDefinition.approved(
    providerId: providerId,
    modelId: modelId,
    displayName: 'Qwen 3 14B',
    digest: 'sha256:0123456789abcdef',
    parameterSize: '14B',
    quantization: 'Q4_K_M',
    aliases: aliases,
    limits: _measuredLimits(),
    toolProfile: _measuredNoTools(),
    dataBoundary: ModelDataBoundary.localOnly,
    cost: ModelCostProfile.noDirectCharge(),
    benchmarks: <ModelBenchmarkEvidence>[_benchmark()],
    approvedTaskClasses: const <String>['code-generation'],
  );
}

ModelIdentity _identity({
  String providerId = 'ollama.local',
  required String name,
  String digest = 'sha256:0123456789abcdef',
  String parameterSize = '14B',
  String quantization = 'Q4_K_M',
}) {
  return ModelIdentity(
    providerId: providerId,
    name: name,
    digest: digest,
    parameterSize: parameterSize,
    quantization: quantization,
    discoveredAt: DateTime.utc(2026, 8, 6),
  );
}

void main() {
  group('P6-001 model registry v2', () {
    test('unknown discovered model starts evaluation-only', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: const <ModelDefinition>[],
      );
      final identity = _identity(
        name: 'unmeasured:latest',
        digest: 'sha256:unmeasured',
        parameterSize: '7B',
        quantization: 'Q4_0',
      );

      final discovered = registry.resolveDiscovered(identity);

      expect(discovered.supportStatus, ModelSupportStatus.evaluationOnly);
      expect(discovered.approvedTaskClasses, isEmpty);
      expect(discovered.limits.evidenceLevel, ModelEvidenceLevel.unknown);
      expect(
        discovered.evaluationReasons,
        contains(
          'discovered model is not present in the approved registry',
        ),
      );
      expect(
        () => registry.requireApproved(
          identity: identity,
          taskClassId: 'code-generation',
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('legacy empty metadata is normalized and round-trips', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: const <ModelDefinition>[],
      );
      final discovered = registry.resolveDiscovered(
        ModelIdentity(
          providerId: 'ollama.local',
          name: 'metadata-free',
          digest: '',
          discoveredAt: DateTime.utc(2026, 8, 6),
        ),
      );

      expect(discovered.digest, isNull);
      expect(discovered.parameterSize, isNull);
      expect(discovered.quantization, isNull);
      expect(
        ModelDefinition.fromJson(discovered.toJson()).toJson(),
        discovered.toJson(),
      );
    });

    test('unknown provider fails closed because boundary is not known', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: const <ModelDefinition>[],
      );

      expect(
        () => registry.resolveDiscovered(
          ModelIdentity(
            providerId: 'unregistered.remote',
            name: 'unknown-model',
            digest: '',
            discoveredAt: DateTime.utc(2026, 8, 6),
          ),
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('data boundary cannot be inferred safely'),
          ),
        ),
      );
    });

    test('approval requires digest, measured limits, cost, and benchmark evidence',
        () {
      expect(
        () => ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'unmeasured:latest',
          displayName: 'Unmeasured',
          limits: ModelLimits.unknown(),
          toolProfile: ModelToolProfile.unknown(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.unknown(),
          benchmarks: const <ModelBenchmarkEvidence>[],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<ModelRegistryValidationException>()
              .having(
                (error) => error.message,
                'message',
                contains('artifact digest is required for approval'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('limits are not measured and complete'),
              )
              .having(
                (error) => error.message,
                'message',
                contains(
                    'task class code-generation has no benchmark evidence'),
              ),
        ),
      );
    });

    test('approval rejects benchmark evidence measured for another artifact', () {
      expect(
        () => ModelDefinition.approved(
          providerId: 'ollama.local',
          modelId: 'replacement:latest',
          displayName: 'Replacement',
          digest: 'sha256:replacement-artifact',
          parameterSize: '14B',
          quantization: 'Q4_K_M',
          limits: _measuredLimits(),
          toolProfile: _measuredNoTools(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          benchmarks: <ModelBenchmarkEvidence>[
            _benchmark(modelDigest: 'sha256:old-artifact'),
          ],
          approvedTaskClasses: const <String>['code-generation'],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('belongs to artifact sha256:old-artifact'),
              contains('expected sha256:replacement-artifact'),
            ),
          ),
        ),
      );
    });

    test('evaluation-only model rejects benchmark evidence from another artifact',
        () {
      expect(
        () => ModelDefinition.evaluationOnly(
          providerId: 'ollama.local',
          modelId: 'evaluation:latest',
          displayName: 'Evaluation',
          digest: 'sha256:evaluation-artifact',
          parameterSize: '14B',
          quantization: 'Q4_K_M',
          limits: _measuredLimits(),
          toolProfile: _measuredNoTools(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          benchmarks: <ModelBenchmarkEvidence>[
            _benchmark(modelDigest: 'sha256:other-artifact'),
          ],
          evaluationReasons: const <String>['evaluation pending'],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('belongs to artifact sha256:other-artifact'),
              contains('expected sha256:evaluation-artifact'),
            ),
          ),
        ),
      );
    });

    test('evaluation-only benchmark evidence requires model artifact identity',
        () {
      expect(
        () => ModelDefinition.evaluationOnly(
          providerId: 'ollama.local',
          modelId: 'evaluation:digestless',
          displayName: 'Evaluation digestless',
          limits: _measuredLimits(),
          toolProfile: _measuredNoTools(),
          dataBoundary: ModelDataBoundary.localOnly,
          cost: ModelCostProfile.noDirectCharge(),
          benchmarks: <ModelBenchmarkEvidence>[_benchmark()],
          evaluationReasons: const <String>['evaluation pending'],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains(
              'model with benchmark evidence must contain an immutable artifact digest',
            ),
          ),
        ),
      );
    });

    test('approved JSON cannot relabel an artifact and retain stale benchmarks',
        () {
      final raw = _approvedModel().toJson();
      raw['digest'] = 'sha256:replacement-artifact';

      expect(
        () => ModelDefinition.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('belongs to artifact sha256:0123456789abcdef'),
              contains('expected sha256:replacement-artifact'),
            ),
          ),
        ),
      );
    });

    test('benchmark JSON requires an exact model digest', () {
      final raw = _benchmark().toJson();
      raw.remove('modelDigest');

      expect(
        () => ModelBenchmarkEvidence.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('benchmark.modelDigest must be non-empty'),
          ),
        ),
      );
    });

    test('approved model is restricted to benchmark-backed task classes', () {
      final model = _approvedModel();
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: <ModelDefinition>[model],
      );

      expect(
        registry.requireApproved(
          identity: _identity(name: 'qwen3-latest'),
          taskClassId: 'code-generation',
        ),
        same(model),
      );
      expect(
        () => registry.requireApproved(
          identity: _identity(name: 'qwen3:14b'),
          taskClassId: 'browser-control',
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('is not approved for browser-control'),
          ),
        ),
      );
    });

    test('registry round-trip is deterministic and sorted', () {
      final remote = ModelProviderDescriptor(
        providerId: 'openai.remote',
        displayName: 'OpenAI-compatible remote',
        dataBoundary: ModelDataBoundary.thirdPartyService,
        credentialRequirements: <CredentialReferenceRequirement>[
          CredentialReferenceRequirement(
            referenceId: 'openai.api-key',
            resolver: 'secret-vault',
            required: true,
            purpose: 'Authenticate the configured provider endpoint.',
          ),
        ],
      );
      final evaluation = ModelDefinition.evaluationOnly(
        providerId: 'openai.remote',
        modelId: 'future-model',
        displayName: 'Future model',
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: ModelDataBoundary.thirdPartyService,
        cost: ModelCostProfile.unknown(),
        evaluationReasons: const <String>['benchmark evidence is missing'],
      );
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[remote, _localProvider()],
        models: <ModelDefinition>[evaluation, _approvedModel()],
      );

      final encoded = registry.toJson();
      final roundTrip = ModelDefinitionRegistry.fromJson(
        (jsonDecode(jsonEncode(encoded)) as Map).cast<String, Object?>(),
      );

      expect(roundTrip.toJson(), encoded);
      expect(
        roundTrip.providers.map((provider) => provider.providerId),
        <String>['ollama.local', 'openai.remote'],
      );
      expect(
        roundTrip.models.map((model) => model.registryKey),
        <String>[
          'ollama.local::qwen3:14b',
          'openai.remote::future-model',
        ],
      );
    });

    test('duplicate canonical IDs and aliases are rejected', () {
      expect(
        () => ModelDefinitionRegistry(
          providers: <ModelProviderDescriptor>[
            _localProvider(),
            _localProvider(),
          ],
          models: const <ModelDefinition>[],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('duplicate provider'),
          ),
        ),
      );

      expect(
        () => ModelDefinitionRegistry(
          providers: <ModelProviderDescriptor>[_localProvider()],
          models: <ModelDefinition>[
            _approvedModel(
              modelId: 'qwen3:14b',
              aliases: const <String>['shared-alias'],
            ),
            _approvedModel(
              modelId: 'qwen3:8b',
              aliases: const <String>['shared-alias'],
            ),
          ],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('duplicate model alias'),
          ),
        ),
      );
    });

    test('provider and model data boundaries must agree', () {
      final remoteModel = ModelDefinition.evaluationOnly(
        providerId: 'ollama.local',
        modelId: 'misbound-model',
        displayName: 'Misbound model',
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: ModelDataBoundary.thirdPartyService,
        cost: ModelCostProfile.unknown(),
      );

      expect(
        () => ModelDefinitionRegistry(
          providers: <ModelProviderDescriptor>[_localProvider()],
          models: <ModelDefinition>[remoteModel],
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('data boundary does not match provider'),
          ),
        ),
      );
    });

    test('credential records contain references, never secret values', () {
      final requirement = CredentialReferenceRequirement(
        referenceId: 'provider.api-key',
        resolver: 'secret-vault',
        required: true,
        purpose: 'Authenticate without persisting secret material.',
      );

      expect(
        requirement.toJson().keys.toSet(),
        <String>{'referenceId', 'resolver', 'required', 'purpose'},
      );
      expect(jsonEncode(requirement.toJson()), isNot(contains('secret-value')));
      expect(
        () => CredentialReferenceRequirement.fromJson(
          <String, Object?>{
            ...requirement.toJson(),
            'value': 'secret-value',
          },
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('unsupported fields: value'),
          ),
        ),
      );
    });

    test('unknown JSON fields and timezone-free benchmarks are rejected', () {
      expect(
        () => ModelProviderDescriptor.fromJson(
          <String, Object?>{
            ..._localProvider().toJson(),
            'apiKey': 'must-not-be-accepted',
          },
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('unsupported fields: apiKey'),
          ),
        ),
      );

      final rawBenchmark = _benchmark().toJson();
      rawBenchmark['measuredAt'] = '2026-08-06T00:00:00';
      expect(
        () => ModelBenchmarkEvidence.fromJson(rawBenchmark),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('must include a UTC offset'),
          ),
        ),
      );
    });

    test('evaluation-only JSON cannot smuggle approved task classes', () {
      final raw = ModelDefinition.evaluationOnly(
        providerId: 'ollama.local',
        modelId: 'evaluation-model',
        displayName: 'Evaluation model',
        limits: ModelLimits.unknown(),
        toolProfile: ModelToolProfile.unknown(),
        dataBoundary: ModelDataBoundary.localOnly,
        cost: ModelCostProfile.unknown(),
      ).toJson();
      raw['approvedTaskClasses'] = <String>['code-generation'];

      expect(
        () => ModelDefinition.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('evaluation-only JSON'),
          ),
        ),
      );
    });
  });
}
