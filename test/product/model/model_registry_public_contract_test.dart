import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/model/model.dart';

void main() {
  group('P6-001 public model-registry contract', () {
    test('product source cannot bypass the fail-closed facade', () {
      final violations = <String>[];
      final internalRegistryDirective = RegExp(
        r'''\b(?:import|export|part)\s+["'][^"']*model_registry\.dart["']''',
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll('\\', '/');
        if (path == 'lib/product/model/model.dart') {
          continue;
        }
        if (internalRegistryDirective.hasMatch(entity.readAsStringSync())) {
          violations.add(path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Product code must import model.dart so discovered artifact '
            'identity checks cannot be bypassed: ${violations.join(', ')}',
      );
    });

    test('bypass matcher covers relative and package URI forms', () {
      final internalRegistryDirective = RegExp(
        r'''\b(?:import|export|part)\s+["'][^"']*model_registry\.dart["']''',
      );

      expect(
        internalRegistryDirective.hasMatch("import './model_registry.dart';"),
        isTrue,
      );
      expect(
        internalRegistryDirective.hasMatch(
          "import 'package:kristin_local_agent/product/model/model_registry.dart';",
        ),
        isTrue,
      );
      expect(
        internalRegistryDirective.hasMatch("export 'model_registry.dart';"),
        isTrue,
      );
      expect(
        internalRegistryDirective.hasMatch("part '../model/model_registry.dart';"),
        isTrue,
      );
      expect(
        internalRegistryDirective.hasMatch("import 'model.dart';"),
        isFalse,
      );
    });

    test('quarantine IDs are deterministic and model-ID safe', () {
      final registered = ModelDefinition.approved(
        providerId: 'ollama.local',
        modelId: 'qwen3:14b',
        displayName: 'Qwen 3 14B',
        digest: 'sha256:registered',
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
        benchmarks: <ModelBenchmarkEvidence>[
          ModelBenchmarkEvidence(
            benchmarkId: 'p6.code-fixture-v1',
            taskClassId: 'code-generation',
            score: 1,
            scoreUnit: 'ratio',
            higherIsBetter: true,
            sampleCount: 1,
            measuredAt: DateTime.utc(2026, 8, 6),
            evidenceUri: 'release/evidence/P6-001/benchmark.json',
          ),
        ],
        approvedTaskClasses: const <String>['code-generation'],
      );
      final registry = ModelDefinitionRegistry(
        providers: <ModelProviderDescriptor>[
          ModelProviderDescriptor(
            providerId: 'ollama.local',
            displayName: 'Local Ollama',
            dataBoundary: ModelDataBoundary.localOnly,
          ),
        ],
        models: <ModelDefinition>[registered],
      );
      final identity = ModelIdentity(
        providerId: 'ollama.local',
        name: 'qwen3:14b',
        digest: 'sha256:changed',
        parameterSize: '14B',
        quantization: 'Q4_K_M',
        discoveredAt: DateTime.utc(2026, 8, 6),
      );

      final first = registry.resolveDiscovered(identity);
      final second = registry.resolveDiscovered(identity);

      expect(first.modelId, second.modelId);
      expect(first.modelId, matches(RegExp(r'^[A-Za-z0-9._:/+-]+$')));
      expect(first.modelId, isNot(contains('=')));
      expect(first.supportStatus, ModelSupportStatus.evaluationOnly);
    });
  });
}
