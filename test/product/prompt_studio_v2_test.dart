import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/generated/prompt_studio_contracts.g.dart';
import 'package:kristin_local_agent/product/prompt_studio_v2.dart';
import 'package:kristin_local_agent/product/tool_schema.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
      jsonDecode(
        File('test/product/fixtures/prompt_studio_v2/$name').readAsStringSync(),
      ) as Map,
    );

Map<String, dynamic> deepCopy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  final compiler = PromptStudioV2Compiler(ToolRegistry.standard());
  final specification =
      ProductSpecificationV2.fromJson(fixture('specification.json'));
  final policy =
      PlanCompilerPolicyV2.fromJson(fixture('policy.local_only.json'));

  group('Prompt Studio 2 generated contracts', () {
    test('exposes versioned schemas and a deterministic digest', () {
      expect(promptStudioSpecificationSchemaVersion, '2.0.0');
      expect(promptStudioTaskPlanSchemaVersion, '2.0.0');
      expect(promptStudioEvaluationSchemaVersion, '1.0.0');
      expect(promptStudioCompilerVersion, '1.0.0');
      expect(promptStudioContractDigest, hasLength(64));
      expect(
        PromptStudioV2Contracts.capabilityCatalog['catalogVersion'],
        '1.0.0',
      );
    });

    test('enforces uniqueItems and exclusiveMinimum schema keywords', () {
      final invalidSpecification = deepCopy(fixture('specification.json'));
      invalidSpecification['targetUsers'] = <String>['developer', 'developer'];
      expect(
        () => ProductSpecificationV2.fromJson(invalidSpecification),
        throwsA(
          isA<PromptStudioV2ValidationException>().having(
            (error) => error.details.toString(),
            'issues',
            contains('uniqueItems'),
          ),
        ),
      );

      final invalidDataset = deepCopy(fixture('evaluation_dataset.json'));
      final cases = invalidDataset['cases'] as List;
      final firstCase = Map<String, dynamic>.from(cases.first as Map);
      firstCase['weight'] = 0;
      cases[0] = firstCase;
      expect(
        () => PromptEvaluationDatasetV1.fromJson(invalidDataset),
        throwsA(
          isA<PromptStudioV2ValidationException>().having(
            (error) => error.details.toString(),
            'issues',
            contains('exclusiveMinimum'),
          ),
        ),
      );
    });
  });

  group('deterministic plan compiler', () {
    for (final count in <int>[1, 10, 50, 100]) {
      test('compiles and dry-runs the $count-task fixture', () {
        final name = 'plan_${count.toString().padLeft(3, '0')}.json';
        final plan = TaskPlanV2.fromJson(fixture(name));
        final first = compiler.compile(
          specification: specification,
          plan: plan,
          policy: policy,
        );
        final second = compiler.compile(
          specification: specification,
          plan: plan,
          policy: policy,
        );
        final simulation =
            Map<String, dynamic>.from(first['simulation'] as Map);

        expect(first['executable'], isTrue);
        expect(first['outputHash'], second['outputHash']);
        expect(first['issues'], isEmpty);
        expect(simulation['taskCount'], count);
        expect(simulation['readyTaskCount'], count);
        expect(simulation['dryRun'], isTrue);
        expect(simulation['sideEffectsPerformed'], isFalse);
        expect((first['topologicalOrder'] as List), hasLength(count));
        expect(
          (Map<String, dynamic>.from(first['quality'] as Map))['score'],
          100.0,
        );
      });
    }

    test('rejects duplicate task IDs and dangling specification references',
        () {
      final duplicatePlan = deepCopy(fixture('plan_010.json'));
      final duplicateTasks = duplicatePlan['tasks'] as List;
      (duplicateTasks[1] as Map)['id'] = (duplicateTasks[0] as Map)['id'];
      final duplicateReport = compiler.compile(
        specification: specification,
        plan: TaskPlanV2.fromJson(duplicatePlan),
        policy: policy,
      );
      final duplicateCodes = (duplicateReport['issues'] as List)
          .whereType<Map>()
          .map((issue) => issue['code'])
          .toSet();
      expect(duplicateReport['executable'], isFalse);
      expect(duplicateCodes, contains('task_id_duplicate'));

      final invalidSpecification = deepCopy(fixture('specification.json'));
      final functional = invalidSpecification['functionalRequirements'] as List;
      final nonFunctional =
          invalidSpecification['nonFunctionalRequirements'] as List;
      nonFunctional
          .add(deepCopy(Map<String, dynamic>.from(functional.first as Map)));
      final criteria = invalidSpecification['acceptanceCriteria'] as List;
      final firstCriterion = Map<String, dynamic>.from(criteria.first as Map);
      (firstCriterion['requirementIds'] as List).add('requirement_missing');
      (firstCriterion['evidenceValidatorIds'] as List).add('validator_missing');
      criteria[0] = firstCriterion;
      criteria.add(deepCopy(firstCriterion));
      final specificationReport = compiler.compile(
        specification: ProductSpecificationV2.fromJson(invalidSpecification),
        plan: TaskPlanV2.fromJson(fixture('plan_001.json')),
        policy: policy,
      );
      final specificationCodes = (specificationReport['issues'] as List)
          .whereType<Map>()
          .map((issue) => issue['code'])
          .toSet();
      expect(specificationReport['executable'], isFalse);
      expect(
        specificationCodes,
        containsAll(<String>{
          'requirement_id_duplicate',
          'criterion_id_duplicate',
          'criterion_requirement_missing',
          'criterion_validator_missing',
        }),
      );
    });

    test('blocks process execution while the v1.4 sandbox boundary is absent',
        () {
      final planValue = deepCopy(fixture('plan_001.json'));
      final task = (planValue['tasks'] as List).first as Map;
      task['taskType'] = 'build';
      task['requiredCapabilities'] = <String>[
        'project.inspect',
        'project.mutate',
        'process.execute',
      ];
      task['allowedTools'] = <String>['read_file', 'write_file', 'run_command'];
      final report = compiler.compile(
        specification: specification,
        plan: TaskPlanV2.fromJson(planValue),
        policy: policy,
      );
      final codes = (report['issues'] as List)
          .whereType<Map>()
          .map((issue) => issue['code'])
          .toSet();

      expect(report['executable'], isFalse);
      expect(codes, contains('sandbox_required'));
    });

    test('permits an explicitly approved legacy unsandboxed dry run only', () {
      final planValue = deepCopy(fixture('plan_001.json'));
      final task = (planValue['tasks'] as List).first as Map;
      task['taskType'] = 'build';
      task['requiredCapabilities'] = <String>[
        'project.inspect',
        'project.mutate',
        'process.execute',
      ];
      task['allowedTools'] = <String>['read_file', 'write_file', 'run_command'];
      final report = compiler.compile(
        specification: specification,
        plan: TaskPlanV2.fromJson(planValue),
        policy: const PlanCompilerPolicyV2(
          localOnly: true,
          sandboxAvailable: false,
          legacyUnsandboxedExecutionApproved: true,
        ),
      );
      final simulation = Map<String, dynamic>.from(report['simulation'] as Map);

      expect(report['executable'], isTrue);
      expect(simulation['dryRun'], isTrue);
      expect(simulation['sideEffectsPerformed'], isFalse);
      expect(simulation['requiredApprovals'],
          contains('legacy_unsandboxed_execution'));
    });
  });

  group('prompt evaluation and revision impact', () {
    test('measures the fixture improvement without model execution', () {
      const evaluator = PromptStudioV2Evaluator();
      final dataset = PromptEvaluationDatasetV1.fromJson(
        fixture('evaluation_dataset.json'),
      );
      final comparison = evaluator.comparePromptVersions(
        baseline: fixture('prompt.baseline.json'),
        candidate: fixture('prompt.candidate.json'),
        dataset: dataset,
      );
      final impact =
          Map<String, dynamic>.from(comparison['measuredImpact'] as Map);

      expect(
        (Map<String, dynamic>.from(comparison['baseline'] as Map))['score'],
        25.0,
      );
      expect(
        (Map<String, dynamic>.from(comparison['candidate'] as Map))['score'],
        100.0,
      );
      expect(impact['scoreDelta'], 75.0);
      expect(comparison['comparisonHash'], hasLength(64));
    });
  });
}
