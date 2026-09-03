import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification_patch.dart';

void main() {
  TaskSpecification base({List<UnresolvedQuestion> questions = const []}) =>
      TaskSpecification(
        id: 'spec-1',
        originalRequest: 'make it faster',
        objective: 'Make the application faster.',
        unresolvedQuestions: questions,
      );

  test('hard constraint steering stays a hard constraint', () {
    final revised = const TaskSpecificationPatch(
      kind: TaskSpecificationPatchKind.hardConstraint,
      value: "Don't change the database.",
    ).applyTo(base());

    expect(revised.objective, 'Make the application faster.');
    expect(revised.hardConstraints, hasLength(1));
    expect(
      revised.hardConstraints.single.statement,
      "Don't change the database.",
    );
    expect(
      revised.hardConstraints.single.provenance,
      EvidenceProvenance.userStated,
    );
  });

  test('clarification answer resolves only the identified question', () {
    final revised = const TaskSpecificationPatch(
      kind: TaskSpecificationPatchKind.clarificationAnswer,
      question: 'Which region?',
      value: 'Europe',
    ).applyTo(
      base(
        questions: const <UnresolvedQuestion>[
          UnresolvedQuestion(question: 'Which region?', blocking: true),
          UnresolvedQuestion(question: 'Which format?'),
        ],
      ),
    );

    expect(
      revised.unresolvedQuestions.map((item) => item.question),
      <String>['Which format?'],
    );
    expect(revised.assumptions.single.statement, contains('Europe'));
    expect(
      revised.assumptions.single.provenance,
      EvidenceProvenance.userStated,
    );
  });
}
