import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';

const String digestA =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String digestB =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String digestC =
    'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String digestZero =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';
const String candidateCommit = '1111111111111111111111111111111111111111';
const String candidateTree = '2222222222222222222222222222222222222222';
const String benchmarkEvidenceSha =
    'sha256:aa9351c8d629a6eb591756bc6eec3252a49f27b11b970ab329c2b17b65cd92f7';

ModelProviderDescriptor _localProvider({String providerId = 'ollama.local'}) =>
    ModelProviderDescriptor(
      providerId: providerId,
      displayName: 'Local Ollama',
      dataBoundary: ModelDataBoundary.localOnly,
    );

ModelLimits _measuredLimits() => ModelLimits(
      evidenceLevel: ModelEvidenceLevel.measured,
      contextWindowTokens: 32768,
      maxOutputTokens: 4096,
      maxConcurrentRequests: 1,
      maxToolCallsPerTurn: 0,
      supportsStreaming: true,
    );

ModelToolProfile _measuredNoTools() => ModelToolProfile(
      evidenceLevel: ModelEvidenceLevel.measured,
      supportsToolCalling: false,
      supportsStructuredOutput: true,
      supportsParallelToolCalls: false,
    );

Map<String, Object?> _benchmarkPayload() => <String, Object?>{
      'schemaVersion': '1.0.0',
      'kind': 'MODEL_BENCHMARK_RESULT',
      'candidateCommit': candidateCommit,
      'candidateTree': candidateTree,
      'benchmarkId': 'p6.code-fixture-v1',
      'taskClassId': 'code-generation',
      'modelDigest': digestA,
      'score': 0.91,
      'scoreUnit': 'ratio',
      'higherIsBetter': true,
      'sampleCount': 100,
      'measuredAt': '2026-08-06T00:00:00.000Z',
    };

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
        'payload': _benchmarkPayload(),
      },
    };

ModelBenchmarkEvidence _benchmark() =>
    ModelBenchmarkEvidence.fromJson(_benchmarkJson());

Map<String, Object?> _approvedPolicyJson() => <String, Object?>{
      'providerId': 'ollama.local',
      'modelId': 'qwen3:14b',
      'displayName': 'Qwen 3 14B',
      'digest': digestA,
      'parameterSize': '14B',
      'quantization': 'Q4_K_M',
      'aliases': <String>['qwen3-latest'],
      'limits': _measuredLimits().toJson(),
      'toolProfile': _measuredNoTools().toJson(),
      'dataBoundary': ModelDataBoundary.localOnly.wireName,
      'cost': ModelCostProfile.noDirectCharge().toJson(),
      'benchmarks': <Object?>[_benchmarkJson()],
      'approvedTaskClasses': <String>['code-generation'],
      'supportStatus': 'approved',
      'evaluationReasons': <String>[],
    };

ModelDefinition _approvedModel({
  String providerId = 'ollama.local',
  String modelId = 'qwen3:14b',
  String digest = digestA,
  Iterable<String> aliases = const <String>['qwen3-latest'],
  Iterable<ModelBenchmarkEvidence>? benchmarks,
}) =>
    ModelDefinition.approved(
      providerId: providerId,
      modelId: modelId,
      displayName: 'Qwen 3 14B',
      digest: digest,
      parameterSize: '14B',
      quantization: 'Q4_K_M',
      aliases: aliases,
      limits: _measuredLimits(),
      toolProfile: _measuredNoTools(),
      dataBoundary: ModelDataBoundary.localOnly,
      cost: ModelCostProfile.noDirectCharge(),
      benchmarks: benchmarks ?? <ModelBenchmarkEvidence>[_benchmark()],
      approvedTaskClasses: const <String>['code-generation'],
    );

ModelIdentity _identity({
  String providerId = 'ollama.local',
  required String name,
  String digest = digestA,
  String parameterSize = '14B',
  String quantization = 'Q4_K_M',
}) =>
    ModelIdentity(
      providerId: providerId,
      name: name,
      digest: digest,
      parameterSize: parameterSize,
      quantization: quantization,
      discoveredAt: DateTime.utc(2026, 8, 6),
    );

void main() {
  group('P6-001 model registry v2', () {
    test('unknown discovered model starts evaluation-only', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: const <ModelDefinition>[],
      );
      final identity = _identity(
        name: 'unmeasured:latest',
        digest: digestZero,
        parameterSize: '7B',
        quantization: 'Q4_0',
      );

      final discovered = registry.resolveDiscovered(identity);
      expect(discovered.isEvaluationOnly, isTrue);
      expect(discovered.model.digest, digestZero);
      expect(
        discovered.evaluationReasons,
        contains('discovered model is not present in the approved registry'),
      );
      expect(
        () => registry.requireApproved(
          identity: identity,
          taskClassId: 'code-generation',
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('legacy empty metadata remains evaluation-only and normalized', () {
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
      expect(discovered.isEvaluationOnly, isTrue);
      expect(discovered.model.digest, isNull);
      expect(discovered.model.parameterSize, isNull);
      expect(discovered.model.quantization, isNull);
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
                contains('no immutable benchmark evidence'),
              ),
        ),
      );
    });

    test('artifact identities require canonical SHA-256 grammar', () {
      const invalid = <String>[
        'latest',
        'sha256:x',
        'sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ' sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ];
      for (final digest in invalid) {
        expect(
          () => _approvedModel(digest: digest),
          throwsA(
            isA<ModelRegistryValidationException>().having(
              (error) => error.message,
              'message',
              contains('canonical sha256:<64 lowercase hex>'),
            ),
          ),
          reason: digest,
        );
      }
    });

    test('discovered malformed digest fails before registry lookup', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: <ModelDefinition>[_approvedModel()],
      );
      expect(
        () => registry.resolveDiscovered(
          _identity(name: 'qwen3:14b', digest: 'sha256:short'),
        ),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('canonical sha256:<64 lowercase hex>'),
          ),
        ),
      );
    });

    test('benchmark evidence is content-addressed and exact', () {
      final benchmark = _benchmark();
      expect(benchmark.modelDigest, digestA);
      expect(benchmark.candidateCommit, candidateCommit);
      expect(benchmark.candidateTree, candidateTree);
      expect(benchmark.evidenceSha256, benchmarkEvidenceSha);
      expect(benchmark.evidenceLocationKind, 'embedded_content_addressed');

      final badDigest = _benchmarkJson();
      (badDigest['evidence'] as Map<String, Object?>)['sha256'] = digestB;
      expect(
        () => ModelBenchmarkEvidence.fromJson(badDigest),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('benchmark evidence digest mismatch'),
          ),
        ),
      );

      final metadataDrift = _benchmarkJson();
      metadataDrift['score'] = 0.92;
      expect(
        () => ModelBenchmarkEvidence.fromJson(metadataDrift),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('metadata does not match immutable evidence payload'),
          ),
        ),
      );
    });

    test('benchmark payload rejects mutable or malformed model identity', () {
      final json = _benchmarkJson();
      final payload = ((json['evidence'] as Map<String, Object?>)['payload']
          as Map<String, Object?>);
      payload['modelDigest'] = 'latest';
      json['modelDigest'] = 'latest';
      expect(
        () => ModelBenchmarkEvidence.fromJson(json),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('canonical sha256:<64 lowercase hex>'),
          ),
        ),
      );
    });

    test('benchmark payload rejects wrong schema and candidate identity', () {
      final wrongSchema = _benchmarkJson();
      (((wrongSchema['evidence'] as Map<String, Object?>)['payload'])
          as Map<String, Object?>)['schemaVersion'] = '2.0.0';
      expect(
        () => ModelBenchmarkEvidence.fromJson(wrongSchema),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('schemaVersion must be 1.0.0'),
          ),
        ),
      );

      final wrongCandidate = _benchmarkJson();
      (((wrongCandidate['evidence'] as Map<String, Object?>)['payload'])
          as Map<String, Object?>)['candidateCommit'] = 'not-a-git-object';
      expect(
        () => ModelBenchmarkEvidence.fromJson(wrongCandidate),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('40-character lowercase Git object id'),
          ),
        ),
      );
    });

    test('approval rejects benchmark evidence measured for another artifact', () {
      expect(
        () => _approvedModel(digest: digestC),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            allOf(contains('belongs to artifact $digestA'), contains(digestC)),
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
          digest: digestC,
          parameterSize: '14B',
          quantization: 'Q4_K_M',
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
            contains('belongs to artifact $digestA'),
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
            contains('benchmark evidence must contain an immutable artifact digest'),
          ),
        ),
      );
    });

    test('approved policy JSON cannot relabel artifact with stale evidence', () {
      final raw = _approvedPolicyJson();
      raw['digest'] = digestC;
      expect(
        () => ModelDefinition.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('belongs to artifact $digestA'),
          ),
        ),
      );
    });

    test('string lookup and runtime metadata never expose approval state', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: <ModelDefinition>[_approvedModel()],
      );
      for (final name in <String>['qwen3:14b', 'qwen3-latest']) {
        final metadata = registry.lookup('ollama.local', name);
        expect(metadata, isA<ModelRegistryMetadata>());
        final encoded = metadata!.toJson();
        expect(encoded.containsKey('supportStatus'), isFalse);
        expect(encoded.containsKey('approvedTaskClasses'), isFalse);
        expect(encoded.containsKey('evaluationReasons'), isFalse);
      }
      final runtime = jsonEncode(registry.toMetadataJson());
      expect(runtime, isNot(contains('approvedTaskClasses')));
      expect(runtime, isNot(contains('supportStatus')));
    });

    test('only exact discovered identity can yield task approval', () {
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[_localProvider()],
        models: <ModelDefinition>[_approvedModel()],
      );
      final handle = registry.requireApproved(
        identity: _identity(name: 'qwen3-latest'),
        taskClassId: 'code-generation',
      );
      expect(handle.model.registryKey, 'ollama.local::qwen3:14b');
      expect(handle.taskClassId, 'code-generation');
      expect(handle.identity.digest, digestA);
      expect(
        () => registry.requireApproved(
          identity: _identity(name: 'qwen3-latest', digest: digestB),
          taskClassId: 'code-generation',
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('registry metadata is deterministic and sorted', () {
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
      expect(
        registry.providers.map((provider) => provider.providerId),
        <String>['ollama.local', 'openai.remote'],
      );
      expect(
        registry.models.map((model) => model.registryKey),
        <String>['ollama.local::qwen3:14b', 'openai.remote::future-model'],
      );
      final first = jsonEncode(registry.toMetadataJson());
      final second = jsonEncode(registry.toMetadataJson());
      expect(second, first);
      expect(first, isNot(contains('approvedTaskClasses')));
    });

    test('duplicate canonical IDs and aliases are rejected', () {
      expect(
        () => ModelDefinitionRegistry(
          providers: <ModelProviderDescriptor>[_localProvider(), _localProvider()],
          models: const <ModelDefinition>[],
        ),
        throwsA(isA<ModelRegistryValidationException>()),
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
          <String, Object?>{...requirement.toJson(), 'value': 'secret-value'},
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
    });

    test('unknown JSON fields and timezone-free benchmark evidence are rejected',
        () {
      expect(
        () => ModelProviderDescriptor.fromJson(
          <String, Object?>{..._localProvider().toJson(), 'apiKey': 'secret'},
        ),
        throwsA(isA<ModelRegistryValidationException>()),
      );
      final raw = _benchmarkJson();
      final payload = ((raw['evidence'] as Map<String, Object?>)['payload']
          as Map<String, Object?>);
      payload['measuredAt'] = '2026-08-06T00:00:00';
      raw['measuredAt'] = '2026-08-06T00:00:00';
      expect(
        () => ModelBenchmarkEvidence.fromJson(raw),
        throwsA(
          isA<ModelRegistryValidationException>().having(
            (error) => error.message,
            'message',
            contains('must include a UTC offset'),
          ),
        ),
      );
    });

    test('evaluation-only policy JSON cannot smuggle approved task classes', () {
      final raw = _approvedPolicyJson();
      raw['supportStatus'] = 'evaluation_only';
      raw['evaluationReasons'] = <String>['not approved'];
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
