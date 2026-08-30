import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification_patch.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification_patch_classifier.dart';

void main() {
  final model = ModelIdentity(
    providerId: 'test',
    name: 'semantic-test',
    digest: 'digest',
    discoveredAt: DateTime.utc(2026, 8, 30),
  );

  test('model classification cannot bypass deterministic clarification validation', () async {
    final classifier = ModelTaskSpecificationPatchClassifier(
      model: model,
      generate: (request) async => ModelGenerationResult(
        text: '{"kind":"clarificationAnswer","value":"Europe","question":"Which region?","reason":"answers the pending region question"}',
        identity: model,
        startedAt: DateTime.utc(2026, 8, 30),
        firstTokenAt: DateTime.utc(2026, 8, 30),
        completedAt: DateTime.utc(2026, 8, 30),
      ),
    );
    final specification = TaskSpecification(
      id: 'spec',
      originalRequest: 'compare offers',
      objective: 'Compare the offers.',
      unresolvedQuestions: const <UnresolvedQuestion>[
        UnresolvedQuestion(question: 'Which region?', blocking: true),
      ],
    );

    final patch = await classifier.classify(
      specification: specification,
      userMessage: 'Use Europe.',
    );
    expect(patch.kind, TaskSpecificationPatchKind.clarificationAnswer);
    final revised = patch.applyTo(specification);
    expect(revised.blockingQuestions, isEmpty);
  });
}
