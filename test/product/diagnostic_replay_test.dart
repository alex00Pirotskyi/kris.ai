import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_protocol.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  test(
    'all compact production diagnostics satisfy their repaired contracts',
    () async {
      final corpus = Directory('test/product/fixtures/diagnostic_replay');
      expect(await corpus.exists(), isTrue);
      final files = await corpus
          .list(followLinks: false)
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .cast<File>()
          .toList();
      files.sort((left, right) => left.path.compareTo(right.path));
      expect(files, isNotEmpty);

      for (final file in files) {
        final decoded = jsonDecode(await file.readAsString());
        expect(decoded, isA<Map>());
        final replay = mapValue(mapValue(decoded)['replayInput']);
        final expected = mapValue(mapValue(decoded)['expected']);
        final allowedTools = stringList(replay['allowedTools']).toSet();
        final path = replay['expectedArtifactPath']?.toString() ?? '';
        final item = WorkItem(
          id: mapValue(decoded)['id']?.toString() ?? file.path,
          title: 'Create project-local wireframes and user flows',
          description:
              'Create and inspect `$path` for the calculator application.',
          dependencies: const <String>{},
          allowedTools: allowedTools,
          acceptanceCriteria: const <String>[
            'The artifact is product-specific and objectively validated.',
          ],
        );
        final action = const AgentProtocolAdapter().parse(
          jsonEncode(replay['modelEnvelope']),
          item: item,
          allowPlainCompletion: false,
        );
        expect(action.tool, expected['normalizedTool'], reason: file.path);
        expect(
          action.arguments['path'],
          expected['normalizedPath'],
          reason: file.path,
        );

        if (expected['contentMustBePreserved'] == true) {
          final sourceAction = mapValue(
            mapValue(replay['modelEnvelope'])['action'],
          );
          expect(
            action.arguments['content'],
            sourceAction['content'],
            reason: file.path,
          );
        }

        if (mapValue(decoded)['id'] == 'v116_markdown_path_repair_loop') {
          final request = replay['request']?.toString() ?? '';
          final recovery = const BoundedArtifactRecoveryPolicy().actionFor(
            item: item,
            request: request,
          );
          expect(recovery, isNotNull);
          final recoveryAction = recovery!;
          expect(recoveryAction.tool, 'write_file');
          expect(recoveryAction.arguments['path'], path);
          final content = recoveryAction.arguments['content']?.toString() ?? '';
          final assessment = const ArtifactEvidencePolicy().assess(
            item: item,
            request: request,
            tool: 'inspect_file',
            result: ToolResult(
              ok: true,
              summary: 'Inspected replay artifact.',
              data: <String, dynamic>{
                'path': mapValue(
                  mapValue(replay['modelEnvelope'])['arguments'],
                )['filePath'],
                'sha256': 'diagnostic-replay-hash',
                'textPreview': content,
              },
            ),
            mutatedPaths: <String>{
              mapValue(
                    mapValue(replay['modelEnvelope'])['arguments'],
                  )['filePath']
                      ?.toString() ??
                  '',
            },
          );
          expect(assessment.state, ArtifactEvidenceState.complete);

          final automaticTarget =
              const AutomaticArtifactVerificationPolicy().inspectionTarget(
            item: item,
            mutationResult: const ToolResult(
              ok: true,
              summary: 'Created replay artifact.',
              data: <String, dynamic>{},
              mutated: true,
            ),
            mutationPaths: <String>{
              mapValue(
                    mapValue(replay['modelEnvelope'])['arguments'],
                  )['filePath']
                      ?.toString() ??
                  '',
            },
          );
          expect(automaticTarget, path);

          final observed = mapValue(mapValue(decoded)['observed']);
          expect(
            RunRetryBudgetPolicy(
              minimumRemainingRepairs: int.parse(
                expected['minimumRemainingRepairs'].toString(),
              ),
            ).canStartAnotherAttempt(
              repairs: int.parse(observed['repairsBeforeRetry'].toString()),
              maxRepairs: int.parse(observed['maxRepairs'].toString()),
            ),
            expected['retryAllowedAtObservedState'],
          );

          expect(
            () => const AgentProtocolAdapter().parse(
              jsonEncode(replay['copiedCoordinatorEnvelope']),
              item: item,
              allowPlainCompletion: false,
            ),
            throwsA(isA<ProductException>()),
          );
        }
      }
    },
  );
}
