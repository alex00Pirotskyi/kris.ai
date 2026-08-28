import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/task_kernel/complexity_router.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

/// The router's job is to decide how much planning a request is worth.
/// These are the acceptance scenarios from the product brief, asserted as
/// routing outcomes rather than as task counts -- a fixed task-count
/// threshold is exactly what the router must not be.
void main() {
  const compiler = ChatIntentCompiler();
  const router = ComplexityRouter();
  const deterministic = DeterministicUnderstanding();

  final knownTargets = <ChatTarget>[
    const ChatTarget(
      id: 'project-8b',
      displayName: 'test8B',
      type: ChatTargetType.project,
      aliases: <String>['test8b'],
    ),
  ];

  RoutingDecision routeFor(
    String input, {
    TaskSpecification? specification,
  }) {
    final decision = compiler.compile(input, knownTargets: knownTargets);
    return router.route(
      specification:
          specification ?? deterministic.understand(decision).specification,
      decision: decision,
    );
  }

  group('trivial work bypasses planning entirely', () {
    test('SCENARIO A: "hello" is conversation, not a task', () {
      final routing = routeFor('hello');
      expect(routing.route, PlanningRoute.direct);
      expect(routing.plans, isFalse);
    });

    test('an information question is answered, not planned', () {
      expect(routeFor('what is SQLite?').route, PlanningRoute.direct);
    });

    test('SCENARIO B: "/run @test8B" is a direct deterministic invocation', () {
      final routing = routeFor('/run @test8B');
      expect(routing.route, PlanningRoute.direct);
      expect(routing.rationale, contains('already fully specified'));
      // Authority still applies -- routing direct is not a permission
      // decision, and the rationale says so.
      expect(routing.rationale, contains('authority still applies'));
    });

    test('a bare target mention is context, not work', () {
      final routing = routeFor('@test8B');
      expect(routing.route, PlanningRoute.direct);
      expect(routing.rationale, contains('context'));
    });
  });

  group('substantial work receives deeper planning', () {
    test('SCENARIO C: an MP3 converter request routes to a full graph', () {
      final decision = compiler.compile(
        'Create a Flutter web MP3 converter. No accounts. Upload MP3, show '
        'progress and provide downloadable result with simple UX.',
      );
      final specification = TaskSpecification(
        id: 'spec_mp3',
        originalRequest: decision.parsed.originalText,
        objective: 'Build a Flutter web MP3 converter',
        subObjectives: <String>[
          'upload an MP3',
          'show conversion progress',
          'download the result',
        ],
        hardConstraints: <SpecificationClaim>[
          const SpecificationClaim.stated('No accounts or authentication.'),
        ],
        successCriteria: <SpecificationClaim>[
          const SpecificationClaim.inferred('An uploaded MP3 converts.'),
          const SpecificationClaim.inferred('The result is downloadable.'),
        ],
        source: TaskSpecificationSource.modelUnderstanding,
        confidence: 0.9,
      );
      final routing = router.route(
        specification: specification,
        decision: decision,
      );
      expect(routing.route, PlanningRoute.graph);
      expect(routing.family, TaskFamily.software);
    });

    test('a small well-specified change stays compact', () {
      final decision = compiler.compile('rename the About button');
      final routing = router.route(
        specification: TaskSpecification(
          id: 'spec_rename',
          originalRequest: 'rename the About button',
          objective: 'Rename the About button',
          source: TaskSpecificationSource.modelUnderstanding,
          confidence: 0.95,
        ),
        decision: decision,
      );
      expect(routing.route, PlanningRoute.compact);
      expect(routing.family, TaskFamily.software);
    });
  });

  group('a nominally-direct request with real internal structure', () {
    test('SCENARIO E: two independent facts earn a compact hidden graph', () {
      final decision = compiler.compile(
        '/search weather in Nha Trang and time in New York',
      );
      final routing = router.route(
        specification: TaskSpecification(
          id: 'spec_research',
          originalRequest: decision.parsed.originalText,
          objective: 'Answer both current factual questions',
          subObjectives: <String>[
            'current Nha Trang weather',
            'current New York local time',
          ],
          source: TaskSpecificationSource.modelUnderstanding,
          confidence: 0.9,
        ),
        decision: decision,
      );
      expect(routing.route, PlanningRoute.compact);
      expect(routing.family, TaskFamily.research);
      expect(routing.rationale, contains('2 independent sub-goals'));
    });

    test('a single-fact search stays direct', () {
      final routing = routeFor('/search current price of gold');
      expect(routing.route, PlanningRoute.direct);
      expect(routing.family, TaskFamily.research);
    });
  });

  group('family assignment covers every executor', () {
    test('every task family the kernel serves is reachable', () {
      expect(router.familyFor('agent.create_project'), TaskFamily.software);
      expect(router.familyFor('agent.modify_project'), TaskFamily.software);
      expect(router.familyFor('agent.fix_project'), TaskFamily.software);
      expect(router.familyFor('research.search'), TaskFamily.research);
      expect(router.familyFor('system.diagnose'), TaskFamily.diagnostics);
      expect(router.familyFor('owner.mode'), TaskFamily.owner);
    });

    test('SCENARIO H: a diagnostics question routes to diagnostics', () {
      final decision = compiler.compile('/diagnose');
      final routing = router.route(
        specification: TaskSpecification(
          id: 'spec_diag',
          originalRequest: 'Why is Kristin slow today?',
          objective: 'Explain why Kristin is slow today',
          subObjectives: <String>[
            'current capability health',
            'recent run latency',
          ],
          source: TaskSpecificationSource.modelUnderstanding,
          confidence: 0.8,
        ),
        decision: decision,
      );
      expect(routing.family, TaskFamily.diagnostics);
      expect(routing.route, PlanningRoute.compact);
    });
  });

  test('a blocking ambiguity stops planning and asks instead', () {
    final decision = compiler.compile(
      'modify @unknownproject to add a settings page',
      knownTargets: knownTargets,
    );
    final routing = router.route(
      specification: deterministic.understand(decision).specification,
      decision: decision,
    );
    expect(routing.requiresClarification, isTrue);
    expect(routing.route, PlanningRoute.direct);
    expect(routing.rationale, contains('unknownproject'));
  });
}
