import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';

/// The specification is the semantic boundary the rest of the kernel
/// depends on, so these tests are about the DISTINCTIONS it preserves --
/// objective vs hard constraint vs preference vs assumption -- not about
/// field plumbing.
void main() {
  group('TaskSpecification preserves semantic distinctions', () {
    // The scenario from the product brief: "Make this app faster but
    // don't change the database and keep the UI simple."
    TaskSpecification fasterApp() => TaskSpecification(
          id: 'spec_faster',
          originalRequest: 'Make this app faster but do not change the '
              'database and keep the UI simple.',
          objective: 'Improve application performance',
          hardConstraints: <SpecificationClaim>[
            const SpecificationClaim.stated(
              'The database must not be modified.',
            ),
          ],
          preferences: <SpecificationClaim>[
            const SpecificationClaim.stated('Keep UI changes minimal.'),
          ],
          successCriteria: <SpecificationClaim>[
            const SpecificationClaim.inferred(
              'A measurable performance improvement is observable.',
            ),
            const SpecificationClaim.inferred(
              'Existing behavior remains valid.',
            ),
          ],
        );

    test('a hard constraint is not interchangeable with a preference', () {
      final specification = fasterApp();
      expect(specification.hardConstraints, hasLength(1));
      expect(specification.preferences, hasLength(1));
      expect(
        specification.hardConstraints.single.statement,
        contains('database'),
      );
      expect(specification.preferences.single.statement, contains('UI'));
      // Both are claims, but only one is inviolable, and the type keeps
      // them in different places rather than in one prose blob.
      expect(specification.hardConstraints.single.isEstablished, isTrue);
    });

    test('the constraint survives being rendered for a planning model', () {
      final rendered = fasterApp().renderForPlanner();
      expect(rendered, contains('HARD CONSTRAINTS (never violate these)'));
      expect(rendered, contains('The database must not be modified.'));
      expect(rendered, contains('PREFERENCES'));
      expect(rendered, contains('Keep UI changes minimal.'));
      // The constraint must be labelled as a constraint in the prompt --
      // not merely present somewhere in the request text, which is how a
      // planner loses it.
      final constraintIndex =
          rendered.indexOf('HARD CONSTRAINTS (never violate these)');
      final preferenceIndex = rendered.indexOf('PREFERENCES');
      expect(constraintIndex, lessThan(preferenceIndex));
    });

    test('a merely-assumed claim cannot be treated as inviolable', () {
      final specification = TaskSpecification(
        id: 'spec_bad',
        originalRequest: 'Speed this up.',
        objective: 'Improve performance',
        hardConstraints: <SpecificationClaim>[
          // A model guessed this. It must not become a rule.
          const SpecificationClaim.assumed('Never touch the network layer.'),
        ],
      );
      final errors = specification.validate();
      expect(errors, isNotEmpty);
      expect(errors.join(' '), contains('not established'));
    });

    test('provenance separates what is known from what is guessed', () {
      expect(
        const SpecificationClaim.stated('x').isEstablished,
        isTrue,
      );
      expect(
        const SpecificationClaim(
          statement: 'x',
          provenance: EvidenceProvenance.observed,
        ).isEstablished,
        isTrue,
      );
      expect(const SpecificationClaim.assumed('x').isEstablished, isFalse);
      expect(const SpecificationClaim.inferred('x').isEstablished, isFalse);
      expect(
        const SpecificationClaim(
          statement: 'x',
          provenance: EvidenceProvenance.unknown,
        ).isEstablished,
        isFalse,
      );
    });

    test('content key is stable across ids and timestamps', () {
      final first = fasterApp();
      final second = fasterApp().copyWith(
        id: 'a-completely-different-id',
        createdAt: DateTime.utc(2020),
      );
      expect(second.contentKey, first.contentKey);
      // ...and changes when the semantics change.
      final third = fasterApp().copyWith(
        hardConstraints: const <SpecificationClaim>[],
      );
      expect(third.contentKey, isNot(first.contentKey));
    });

    test('round-trips through JSON without losing structure', () {
      final original = fasterApp().copyWith(
        subObjectives: <String>['reduce startup time', 'reduce frame drops'],
        targetRefs: <TaskTargetRef>[
          const TaskTargetRef(
            kind: 'project',
            value: 'project-1',
            displayName: 'Demo',
            provenance: EvidenceProvenance.observed,
            resolved: true,
          ),
        ],
        unresolvedQuestions: <UnresolvedQuestion>[
          const UnresolvedQuestion(
            question: 'Which screen is slow?',
            blocking: true,
          ),
        ],
        prohibitedEffects: <String>['schema migration'],
        source: TaskSpecificationSource.modelUnderstanding,
        confidence: 0.92,
      );
      final restored = TaskSpecification.fromJson(original.toJson());
      expect(restored.objective, original.objective);
      expect(restored.hardConstraints.single.provenance,
          EvidenceProvenance.userStated);
      expect(restored.preferences.single.statement, 'Keep UI changes minimal.');
      expect(restored.targetRefs.single.resolved, isTrue);
      expect(restored.blockingQuestions, hasLength(1));
      expect(restored.prohibitedEffects, contains('schema migration'));
      expect(restored.confidence, closeTo(0.92, 0.0001));
      expect(restored.hasSemanticUnderstanding, isTrue);
      expect(restored.contentKey, original.contentKey);
    });

    test('a deterministic specification never claims semantic understanding',
        () {
      final specification = TaskSpecification(
        id: 'spec_det',
        originalRequest: '/run @test8B',
        objective: 'Run test8B',
        source: TaskSpecificationSource.deterministic,
      );
      expect(specification.hasSemanticUnderstanding, isFalse);
      expect(specification.validate(), isEmpty);
    });
  });
}
