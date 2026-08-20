import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/adaptive_mission_planning.dart';
import 'package:kristin_local_agent/product/agent_decision.dart';
import 'package:kristin_local_agent/product/agent_protocol.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';
import 'package:kristin_local_agent/product/retry_policy.dart';
import 'package:kristin_local_agent/product/tool_schema.dart';

void main() {
  group('P25 diagnostic reliability rescue', () {
    test('completion envelope does not spend a repair turn on boilerplate', () {
      const codec = AgentDecisionCodec();
      final decision = codec.decodeCanonical(<String, dynamic>{
        'action': 'complete',
        'status': 'success',
      });

      expect(decision, isA<CompleteDecision>());
      final complete = decision as CompleteDecision;
      expect(complete.summary, isNotEmpty);
      expect(complete.summary, contains('objective evidence'));
    });

    test('root file inspection becomes a bounded directory listing', () {
      const adapter = AgentProtocolAdapter();
      final decision = adapter.parseDecision(
        '{"action":"tool","tool":"inspect_file","arguments":{"path":"."}}',
        item: _workItem(
          allowedTools: const <String>{'inspect_file', 'list_directory'},
        ),
        allowPlainCompletion: false,
      );

      expect(decision, isA<ToolDecision>());
      final tool = decision as ToolDecision;
      expect(tool.tool, 'list_directory');
      expect(tool.arguments['path'], '.');
      expect(tool.arguments['recursive'], false);
    });

    test('invented search secret falls back to local knowledge', () {
      const adapter = AgentProtocolAdapter();
      final decision = adapter.parseDecision(
        '{"action":"tool","tool":"research_search","arguments":{"query":"official API documentation","secretReferenceId":"secret_ref_123"}}',
        item: _workItem(
          allowedTools: const <String>{
            'research_search',
            'knowledge_search',
          },
        ),
        allowPlainCompletion: false,
      );

      expect(decision, isA<ToolDecision>());
      final tool = decision as ToolDecision;
      expect(tool.tool, 'knowledge_search');
      expect(tool.arguments['query'], 'official API documentation');
      expect(tool.arguments.containsKey('secretReferenceId'), isFalse);
    });

    test('local execution has room to recover without restoring huge context', () {
      final budget = PhaseBudget.localExecution();

      expect(budget.maxModelRequests, greaterThanOrEqualTo(8));
      expect(budget.maxRepairs, greaterThanOrEqualTo(6));
      expect(budget.maxToolCalls, greaterThanOrEqualTo(18));
      expect(budget.maxOutputTokens, lessThanOrEqualTo(768));
      expect(budget.maxContextCharacters, lessThanOrEqualTo(6000));
    });

    test('model tool descriptors stay compact while canonical schemas stay full',
        () {
      const registry = ToolSchemaRegistry();
      const tools = <String>{
        'list_directory',
        'read_file',
        'inspect_file',
        'write_file',
        'run_command',
        'verify_project',
      };
      final model = registry.descriptors(
        allowlist: tools,
        dialect: ToolDescriptorDialect.model,
      );
      final canonical = registry.descriptors(
        allowlist: tools,
        dialect: ToolDescriptorDialect.canonical,
      );
      final modelJson = jsonEncode(model);
      final canonicalJson = jsonEncode(canonical);

      expect(modelJson.length, lessThan(canonicalJson.length * 0.6));
      for (final descriptor in model) {
        expect(descriptor, isNot(contains('inputSchema')));
        expect(descriptor, isNot(contains('outputSchema')));
        expect(descriptor['arguments'], isA<Map>());
        final arguments = Map<String, dynamic>.from(
          descriptor['arguments'] as Map,
        );
        expect(arguments, contains('required'));
        expect(arguments, contains('types'));
        expect(arguments, contains('example'));
      }
      for (final descriptor in canonical) {
        expect(descriptor, contains('inputSchema'));
        expect(descriptor, contains('outputSchema'));
      }
    });

    test('known deterministic failures are never blind transient retries', () {
      const taxonomy = WorkflowRetryTaxonomy();

      expect(
        taxonomy.classify('model_action_invalid').disposition,
        RetryDisposition.retrySameAttempt,
      );
      expect(
        taxonomy.classify('path_not_file').disposition,
        RetryDisposition.retrySameAttempt,
      );
      expect(
        taxonomy.classify('permission_required').disposition,
        RetryDisposition.requireUser,
      );
      expect(
        taxonomy.classify('agent_turn_limit').disposition,
        RetryDisposition.never,
      );
      expect(
        taxonomy.classify('agent_stalled_repeated_tool_outcome').disposition,
        RetryDisposition.never,
      );
      expect(
        taxonomy.classify('totally_new_failure_code').disposition,
        RetryDisposition.never,
      );
    });

    test('web app URLs do not invent research or deployment missions', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'research',
            phase: 'Discovery',
            title: 'Research MP3 to URL conversion tools',
            objective: 'Search the web for current MP3 upload services.',
            tools: const <String>{
              'knowledge_search',
              'research_search',
              'research_fetch',
            },
          ),
          _task(
            id: 'implementation',
            title: 'Build the MP3 upload web app',
            objective:
                'Upload MP3 files and return downloadable URLs to the user.',
            dependencies: const <String>{'research'},
            tools: const <String>{
              'inspect_file',
              'write_file',
              'research_fetch',
            },
          ),
          _task(
            id: 'deployment',
            phase: 'Release',
            title: 'Deploy the web app',
            objective: 'Publish the app to a hosting server.',
            dependencies: const <String>{'implementation'},
            tools: const <String>{'package_deployment', 'verify_project'},
          ),
        ],
        prompt: _prompt(
          'Build a simple web app where I upload MP3 files and receive downloadable URLs.',
        ),
        maxTasks: 8,
      );

      final ids = result.tasks.map((task) => task.id).toSet();
      expect(ids, isNot(contains('research')));
      expect(ids, isNot(contains('deployment')));
      final implementation = result.tasks.singleWhere(
        (task) => task.id == 'implementation',
      );
      expect(implementation.dependencies, isEmpty);
      expect(implementation.allowedTools, isNot(contains('research_search')));
      expect(implementation.allowedTools, isNot(contains('research_fetch')));
      expect(implementation.allowedTools, isNot(contains('package_deployment')));
      expect(
        result.findings.any(
          (finding) => finding.id == 'pruned_research_research',
        ),
        isTrue,
      );
      expect(
        result.findings.any(
          (finding) => finding.id == 'pruned_deployment_deployment',
        ),
        isTrue,
      );
    });

    test('web project setup creates source artifacts instead of command text', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'setup',
            phase: 'Setup',
            title: 'Initialize project workspace',
            objective: 'Scaffold the web application project.',
            tools: const <String>{'write_file', 'inspect_file'},
            artifacts: const <String>['project_root'],
          ),
        ],
        prompt: _prompt(
          'Build a simple web app where I upload MP3 files and receive downloadable URLs.',
        ),
        maxTasks: 6,
      );

      final setup = result.tasks.singleWhere((task) => task.id == 'setup');
      expect(setup.title, 'Create the minimal web application scaffold');
      expect(
        setup.expectedArtifacts,
        containsAll(<String>['index.html', 'styles.css', 'app.js', 'README.md']),
      );
      expect(setup.expectedArtifacts, isNot(contains('project_root')));
      expect(setup.instructions, contains('Do not write shell commands'));
      expect(setup.instructions, contains('index.html'));
    });

    test('explicit research and deployment intent remains available', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'research',
            phase: 'Discovery',
            title: 'Research official current documentation',
            tools: const <String>{'research_search', 'research_fetch'},
          ),
          _task(
            id: 'deployment',
            phase: 'Release',
            title: 'Deploy the application',
            dependencies: const <String>{'research'},
            tools: const <String>{'package_deployment'},
          ),
        ],
        prompt: _prompt(
          'Research the latest official documentation, then deploy and publicly host the result.',
        ),
        maxTasks: 8,
      );

      final ids = result.tasks.map((task) => task.id).toSet();
      expect(ids, contains('research'));
      expect(ids, contains('deployment'));
    });

    test('overlapping design packets merge instead of duplicating UX work', () {
      final result = AdaptiveMissionPlanner.optimizeTasks(
        tasks: <PlanTaskRecord>[
          _task(
            id: 'design_a',
            phase: 'Design',
            title: 'Create responsive wireframes and user flows',
            objective: 'Document responsive screens and user flows.',
            artifacts: const <String>['docs/design/wireframes.md'],
          ),
          _task(
            id: 'design_b',
            phase: 'Design',
            title: 'Design screen flows and responsive mockups',
            objective: 'Document responsive mockups and screen flows.',
            artifacts: const <String>['docs/design/wireframes.md'],
          ),
        ],
        prompt: _prompt('Build the requested app with a clean responsive UI.'),
        maxTasks: 6,
      );

      expect(result.mergedTaskIds, contains('design_b'));
      expect(result.tasks.map((task) => task.id), isNot(contains('design_b')));
    });
  });
}

WorkItem _workItem({required Set<String> allowedTools}) => WorkItem(
      id: 'work_diagnostic',
      title: 'Inspect project and establish evidence baseline',
      description: 'Inspect the selected project without inventing external work.',
      dependencies: const <String>{},
      allowedTools: allowedTools,
      acceptanceCriteria: const <String>['Relevant project state is grounded.'],
      maxAttempts: 2,
    );

PromptStudioDraft _prompt(String userPrompt) => PromptStudioDraft(
      title: 'Diagnostic regression prompt',
      purpose: 'Deliver exactly the requested local product behavior.',
      systemPrompt:
          'Use only capabilities required by the approved request and verify the result.',
      userPrompt: userPrompt,
      variables: const <String>[],
      assumptions: const <String>[],
      clarifyingQuestions: const <String>[],
      acceptanceCriteria: const <String>[
        'The requested behavior is implemented.',
        'The result has objective verification evidence.',
      ],
      outputExpectations: const <String>['Working product source'],
      guardrails: const <String>['Do not invent unrequested external work.'],
      stopConditions: const <String>[],
      evaluationCases: const <String>['Normal path', 'Failure path'],
      mode: CommandMode.build,
    );

PlanTaskRecord _task({
  required String id,
  required String title,
  String objective = 'Deliver a bounded product outcome.',
  String phase = 'Implementation',
  Set<String> dependencies = const <String>{},
  Set<String> tools = const <String>{'inspect_file', 'write_file'},
  List<String>? artifacts,
}) =>
    PlanTaskRecord(
      id: id,
      phase: phase,
      parentId: null,
      title: title,
      objective: objective,
      instructions: objective,
      dependencies: dependencies,
      acceptanceCriteria: const <String>[
        'The bounded outcome is present and inspectable.',
      ],
      verificationSteps: const <String>['Inspect the resulting artifact.'],
      expectedArtifacts: artifacts ?? <String>['Artifact for $title'],
      allowedTools: tools,
      complexity: 4,
      effortPoints: 3,
      uncertainty: PlanUncertainty.medium,
      risk: PlanRisk.medium,
      estimateConfidence: 0.75,
      expectedModelTurns: 2,
      expectedToolCalls: 4,
      maxAttempts: 2,
      enabled: true,
      manual: false,
    );
