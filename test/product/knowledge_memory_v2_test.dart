import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/knowledge_memory_v2.dart';

void main() {
  test(
      'memory admission policy quarantines unsuccessful runs without evidence expansion',
      () {
    const policy = MemoryAdmissionPolicy();
    final episode = MemoryEpisode(
      id: 'episode-1',
      projectId: 'project-1',
      runId: 'run-1',
      request: 'Run the preview server',
      mode: CommandMode.build,
      outcome: RunState.failed,
      summary: '',
      failure: 'Port collision',
      lessons: 'Reserve the preview port.',
      tags: const <String>{'episode', 'failed'},
      completedItems: const <String>[],
      failedItems: const <String>['Run'],
      filesChanged: const <String>[],
      evidenceIds: const <String>['evidence-1'],
      evidenceHashes: const <String>[
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      ],
      startedAt: DateTime.utc(2026, 7, 22, 10),
      completedAt: DateTime.utc(2026, 7, 22, 10, 1),
      modelRequests: 1,
      toolCalls: 1,
      mutations: 0,
      repairs: 0,
      contentHash:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      createdAt: DateTime.utc(2026, 7, 22, 10, 1),
    );
    final decision = policy.evaluateEpisode(episode);
    expect(decision.status, 'quarantined');
    expect(decision.diagnosticOnly, isTrue);
    expect(decision.retrievalAllowed, isFalse);
  });

  test('skill publication requires explicit approval and replay', () {
    final candidate = SkillCandidateRecord(
      id: 'candidate-1',
      projectId: 'project-1',
      sourceEpisodeId: 'episode-1',
      title: 'Repair build pipeline',
      instructions: 'Use the retained snapshot and verify the package output.',
      triggers: const <String>{'repair', 'build'},
      recommendedTools: const <String>{
        'read_file',
        'write_file',
        'verify_project'
      },
      evidenceHashes: const <String>[
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      ],
      candidateHash:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      createdAt: DateTime.utc(2026, 7, 22, 11),
    );
    final published = PublishedSkillRecord(
      id: 'published-1',
      candidateId: candidate.id,
      version: 1,
      title: candidate.title,
      instructions: candidate.instructions,
      recommendedTools: candidate.recommendedTools,
      approvalNote: 'Reviewed and approved.',
      manifestHash:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      publishedAt: DateTime.utc(2026, 7, 22, 11, 5),
    );
    expect(published.approvalNote, isNotEmpty);
    expect(published.version, 1);
  });
}
