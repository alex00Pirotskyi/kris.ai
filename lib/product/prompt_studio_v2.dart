import 'dart:convert';
import 'dart:math';

import 'crypto_utils.dart';
import 'generated/prompt_studio_contracts.g.dart';
import 'protocol_types.dart';
import 'storage_security.dart';
import 'tool_schema.dart';
import 'workspace_tools.dart';

class PromptStudioV2ValidationException extends ProductException {
  PromptStudioV2ValidationException({
    required String document,
    required List<SchemaIssue> issues,
  }) : super(
          '${document}_schema_invalid',
          'The $document does not satisfy its versioned Prompt Studio 2 contract.',
          details: <String, dynamic>{
            'document': document,
            'contractDigest': promptStudioContractDigest,
            'issues': issues.map((item) => item.toJson()).toList(),
          },
        );
}

class PromptStudioV2Contracts {
  const PromptStudioV2Contracts._();

  static final Map<String, dynamic> specificationSchema =
      _decode(productSpecificationV2SchemaJson);
  static final Map<String, dynamic> taskPlanSchema =
      _decode(taskPlanV2SchemaJson);
  static final Map<String, dynamic> evaluationSchema =
      _decode(promptEvaluationDatasetV1SchemaJson);
  static final Map<String, dynamic> capabilityCatalog =
      _decode(planCapabilityCatalogV1Json);
  static final Map<String, dynamic> compilationReportSchema =
      _decode(planCompilationReportV1SchemaJson);

  static Map<String, dynamic> _decode(String source) =>
      Map<String, dynamic>.from(jsonDecode(source) as Map);

  static List<SchemaIssue> validateSpecification(Object? value) =>
      JsonSchemaValidator.validate(value, specificationSchema);

  static List<SchemaIssue> validateTaskPlan(Object? value) =>
      JsonSchemaValidator.validate(value, taskPlanSchema);

  static List<SchemaIssue> validateEvaluationDataset(Object? value) =>
      JsonSchemaValidator.validate(value, evaluationSchema);

  static List<SchemaIssue> validateCompilationReport(Object? value) =>
      JsonSchemaValidator.validate(value, compilationReportSchema);
}

abstract class PromptStudioV2Document {
  PromptStudioV2Document(Map<String, dynamic> value) : _value = _deepMap(value);

  final Map<String, dynamic> _value;

  Map<String, dynamic> toJson() => _deepMap(_value);
  String get contentHash => Sha256.text(canonicalJson(_value));
}

class ProductSpecificationV2 extends PromptStudioV2Document {
  ProductSpecificationV2._(super.value);

  factory ProductSpecificationV2.fromJson(Map<String, dynamic> value) {
    final issues = PromptStudioV2Contracts.validateSpecification(value);
    if (issues.isNotEmpty) {
      throw PromptStudioV2ValidationException(
        document: 'product_specification',
        issues: issues,
      );
    }
    return ProductSpecificationV2._(value);
  }

  String get id => _value['id']?.toString() ?? '';
  bool get localOnly => _map(_value['dataPolicy'])['localOnly'] != false;
  String get deploymentMode =>
      _map(_value['deploymentBoundary'])['mode']?.toString() ?? 'none';
  String? get deploymentTarget {
    final value =
        _map(_value['deploymentBoundary'])['target']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }
}

class TaskPlanV2 extends PromptStudioV2Document {
  TaskPlanV2._(super.value);

  factory TaskPlanV2.fromJson(Map<String, dynamic> value) {
    final issues = PromptStudioV2Contracts.validateTaskPlan(value);
    if (issues.isNotEmpty) {
      throw PromptStudioV2ValidationException(
        document: 'task_plan',
        issues: issues,
      );
    }
    return TaskPlanV2._(value);
  }

  String get id => _value['id']?.toString() ?? '';
  String get specificationId => _value['specificationId']?.toString() ?? '';
  bool get localOnly => _value['localOnly'] != false;
  List<Map<String, dynamic>> get tasks => _maps(_value['tasks']);
}

class PromptEvaluationDatasetV1 extends PromptStudioV2Document {
  PromptEvaluationDatasetV1._(super.value);

  factory PromptEvaluationDatasetV1.fromJson(Map<String, dynamic> value) {
    final issues = PromptStudioV2Contracts.validateEvaluationDataset(value);
    if (issues.isNotEmpty) {
      throw PromptStudioV2ValidationException(
        document: 'prompt_evaluation_dataset',
        issues: issues,
      );
    }
    return PromptEvaluationDatasetV1._(value);
  }

  String get id => _value['id']?.toString() ?? '';
  List<Map<String, dynamic>> get cases => _maps(_value['cases']);
}

class PlanCompilerPolicyV2 {
  const PlanCompilerPolicyV2({
    this.localOnly = true,
    this.sandboxAvailable = false,
    this.legacyUnsandboxedExecutionApproved = false,
    this.networkAllowed = false,
    this.humanWorkflowAvailable = false,
    this.selfModificationApproved = false,
    this.deploymentTarget,
    this.maxTasks = 100,
    this.maxTotalModelTurns = 1200,
    this.maxTotalToolCalls = 5000,
    this.maxTotalOutputBytes = 500000000,
  });

  final bool localOnly;
  final bool sandboxAvailable;
  final bool legacyUnsandboxedExecutionApproved;
  final bool networkAllowed;
  final bool humanWorkflowAvailable;
  final bool selfModificationApproved;
  final String? deploymentTarget;
  final int maxTasks;
  final int maxTotalModelTurns;
  final int maxTotalToolCalls;
  final int maxTotalOutputBytes;

  factory PlanCompilerPolicyV2.fromJson(Map<String, dynamic> value) {
    return PlanCompilerPolicyV2(
      localOnly: value['localOnly'] is bool ? value['localOnly'] as bool : true,
      sandboxAvailable: value['sandboxAvailable'] is bool
          ? value['sandboxAvailable'] as bool
          : false,
      legacyUnsandboxedExecutionApproved:
          value['legacyUnsandboxedExecutionApproved'] is bool
              ? value['legacyUnsandboxedExecutionApproved'] as bool
              : false,
      networkAllowed: value['networkAllowed'] is bool
          ? value['networkAllowed'] as bool
          : false,
      humanWorkflowAvailable: value['humanWorkflowAvailable'] is bool
          ? value['humanWorkflowAvailable'] as bool
          : false,
      selfModificationApproved: value['selfModificationApproved'] is bool
          ? value['selfModificationApproved'] as bool
          : false,
      deploymentTarget: _optionalString(value['deploymentTarget']),
      maxTasks: _int(value['maxTasks'], fallback: 100),
      maxTotalModelTurns: _int(value['maxTotalModelTurns'], fallback: 1200),
      maxTotalToolCalls: _int(value['maxTotalToolCalls'], fallback: 5000),
      maxTotalOutputBytes:
          _int(value['maxTotalOutputBytes'], fallback: 500000000),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'localOnly': localOnly,
        'sandboxAvailable': sandboxAvailable,
        'legacyUnsandboxedExecutionApproved':
            legacyUnsandboxedExecutionApproved,
        'networkAllowed': networkAllowed,
        'humanWorkflowAvailable': humanWorkflowAvailable,
        'selfModificationApproved': selfModificationApproved,
        'deploymentTarget': deploymentTarget,
        'maxTasks': maxTasks.clamp(1, 100).toInt(),
        'maxTotalModelTurns': max(0, maxTotalModelTurns),
        'maxTotalToolCalls': max(0, maxTotalToolCalls),
        'maxTotalOutputBytes': max(0, maxTotalOutputBytes),
      };
}

class PlanCompilationIssueV2 {
  const PlanCompilationIssueV2({
    required this.severity,
    required this.code,
    required this.message,
    this.taskId,
    this.path,
    this.details = const <String, dynamic>{},
  });

  final String severity;
  final String code;
  final String message;
  final String? taskId;
  final String? path;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'severity': severity,
        'code': code,
        'message': message,
        if (taskId != null) 'taskId': taskId,
        if (path != null) 'path': path,
        if (details.isNotEmpty) 'details': details,
      };
}

class _CapabilityV2 {
  const _CapabilityV2({
    required this.name,
    required this.tools,
    required this.requiresSandbox,
    required this.network,
    required this.mutation,
  });

  final String name;
  final Set<String> tools;
  final bool requiresSandbox;
  final bool network;
  final bool mutation;
}

class PromptStudioV2Compiler {
  PromptStudioV2Compiler(this.tools);

  final ToolRegistry tools;

  static final RegExp _externalClaim = RegExp(
    r'\b(?:public\s+url|host(?:ed|ing)?\s+online|deploy\s+to\s+(?:cloud|production|vercel|netlify|aws|azure|gcp)|publish\s+(?:online|publicly)|live\s+web\s+(?:research|verification)|browserstack|figma|adobe\s+xd|sketch|external\s+(?:api|service)|remote\s+service|internet\s+access)\b',
    caseSensitive: false,
  );
  static final RegExp _humanClaim = RegExp(
    r'\b(?:recruit|interview|survey|focus\s+group|user\s+study|participants?|human\s+tester|stakeholder\s+approval)\b',
    caseSensitive: false,
  );

  Map<String, dynamic> compile({
    required ProductSpecificationV2 specification,
    required TaskPlanV2 plan,
    PlanCompilerPolicyV2 policy = const PlanCompilerPolicyV2(),
  }) {
    final policyJson = policy.toJson();
    final issues = <PlanCompilationIssueV2>[];
    final capabilityState = _capabilities();
    final capabilities = capabilityState.$1;
    final defaults = capabilityState.$2;
    final validatorCapabilities = capabilityState.$3;
    final knownTools = tools.names;
    final tasks = plan.tasks;
    final byId = <String, Map<String, dynamic>>{};
    for (final task in tasks) {
      final taskId = task['id']?.toString() ?? '';
      if (taskId.isEmpty) {
        continue;
      }
      if (byId.containsKey(taskId)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'task_id_duplicate',
            message:
                'Duplicate task ID $taskId prevents deterministic graph compilation.',
            taskId: taskId,
            path: r'$.tasks',
          ),
        );
        continue;
      }
      byId[taskId] = task;
    }

    if (plan.specificationId != specification.id) {
      issues.add(
        const PlanCompilationIssueV2(
          severity: 'error',
          code: 'specification_link_mismatch',
          message:
              'The plan does not reference the supplied product specification.',
          path: r'$.specificationId',
        ),
      );
    }
    if (plan.localOnly != specification.localOnly) {
      issues.add(
        const PlanCompilationIssueV2(
          severity: 'error',
          code: 'local_only_contract_mismatch',
          message:
              'The plan localOnly flag must match the product specification data policy.',
          path: r'$.localOnly',
        ),
      );
    }
    final effectiveLocalOnly =
        policy.localOnly || plan.localOnly || specification.localOnly;
    final effectiveMaxTasks = policy.maxTasks.clamp(1, 100).toInt();
    if (tasks.length > effectiveMaxTasks) {
      issues.add(
        PlanCompilationIssueV2(
          severity: 'error',
          code: 'task_limit_exceeded',
          message:
              'The plan contains ${tasks.length} tasks but policy allows $effectiveMaxTasks.',
          path: r'$.tasks',
        ),
      );
    }

    final specificationValue = specification.toJson();
    final specificationArtifacts = _maps(specificationValue['artifacts']);
    final specificationValidatorIds = <String>{};
    final specificationRequirementIds = <String>{};
    final seenRequirementIds = <String>{};
    for (final field in const <String>[
      'functionalRequirements',
      'nonFunctionalRequirements',
    ]) {
      for (final requirement in _maps(specificationValue[field])) {
        final requirementId = requirement['id']?.toString() ?? '';
        if (requirementId.isEmpty) {
          continue;
        }
        if (!seenRequirementIds.add(requirementId)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'requirement_id_duplicate',
              message: 'Duplicate specification requirement ID $requirementId.',
              path: '\$.$field',
            ),
          );
        }
        specificationRequirementIds.add(requirementId);
      }
    }
    final seenArtifactIds = <String>{};
    final seenValidatorIds = <String>{};
    for (final artifact in specificationArtifacts) {
      final artifactId = artifact['id']?.toString() ?? '';
      if (artifactId.isNotEmpty && !seenArtifactIds.add(artifactId)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'artifact_id_duplicate',
            message: 'Duplicate specification artifact ID $artifactId.',
            path: r'$.artifacts',
          ),
        );
      }
      for (final validator in _maps(artifact['validators'])) {
        final validatorId = validator['id']?.toString() ?? '';
        if (validatorId.isEmpty) {
          continue;
        }
        specificationValidatorIds.add(validatorId);
        if (!seenValidatorIds.add(validatorId)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'validator_id_duplicate',
              message: 'Duplicate validator ID $validatorId.',
              path: r'$.artifacts',
            ),
          );
        }
      }
    }
    final seenCriterionIds = <String>{};
    for (final criterion in _maps(specificationValue['acceptanceCriteria'])) {
      final criterionId = criterion['id']?.toString() ?? '';
      if (criterionId.isNotEmpty && !seenCriterionIds.add(criterionId)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'criterion_id_duplicate',
            message:
                'Duplicate specification acceptance criterion ID $criterionId.',
            path: r'$.acceptanceCriteria',
          ),
        );
      }
      for (final validatorId in _strings(criterion['evidenceValidatorIds'])) {
        if (!specificationValidatorIds.contains(validatorId)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'criterion_validator_missing',
              message:
                  'Specification criterion $criterionId references missing validator $validatorId.',
              path: r'$.acceptanceCriteria',
            ),
          );
        }
      }
      for (final requirementId in _strings(criterion['requirementIds'])) {
        if (!specificationRequirementIds.contains(requirementId)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'criterion_requirement_missing',
              message:
                  'Specification criterion $criterionId references missing requirement $requirementId.',
              path: r'$.acceptanceCriteria',
            ),
          );
        }
      }
    }

    final dependencyEdges = <String, Set<String>>{};
    final parentEdges = <String, Set<String>>{};
    for (final task in tasks) {
      final taskId = task['id']?.toString() ?? '';
      final dependencies = _strings(task['dependencies']).toSet();
      dependencyEdges[taskId] = dependencies;
      final parentId = task['parentId']?.toString().trim() ?? '';
      parentEdges[taskId] = parentId.isEmpty ? <String>{} : <String>{parentId};
      for (final dependency in dependencies) {
        if (!byId.containsKey(dependency)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'dependency_missing',
              message:
                  'Task $taskId references missing dependency $dependency.',
              taskId: taskId,
            ),
          );
        } else if (task['enabled'] != false &&
            byId[dependency]?['enabled'] == false) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'dependency_disabled',
              message:
                  'Enabled task $taskId depends on disabled task $dependency.',
              taskId: taskId,
            ),
          );
        }
      }
      if (parentId.isNotEmpty && !byId.containsKey(parentId)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'parent_missing',
            message: 'Task $taskId references missing parent $parentId.',
            taskId: taskId,
          ),
        );
      } else if (parentId == taskId && parentId.isNotEmpty) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'parent_self_reference',
            message: 'Task $taskId cannot parent itself.',
            taskId: taskId,
          ),
        );
      }
    }
    for (final cycle in _cycles(byId.keys.toList(), dependencyEdges)) {
      issues.add(
        PlanCompilationIssueV2(
          severity: 'error',
          code: 'dependency_cycle',
          message: 'Dependency cycle detected: ${cycle.join(' -> ')}.',
        ),
      );
    }
    for (final cycle in _cycles(byId.keys.toList(), parentEdges)) {
      issues.add(
        PlanCompilationIssueV2(
          severity: 'error',
          code: 'parent_cycle',
          message: 'Parent hierarchy cycle detected: ${cycle.join(' -> ')}.',
        ),
      );
    }

    final compiledTasks = <Map<String, dynamic>>[];
    final blockReasons = <String, Set<String>>{};
    final approvals = <String>{};
    final producedPaths = <String, String>{};
    var capabilityRequired = 0;
    var capabilityCovered = 0;
    var criteriaTotal = 0;
    var criteriaVerified = 0;
    var artifactsTotal = 0;
    var artifactsValidated = 0;

    for (final task in tasks) {
      final taskId = task['id']?.toString() ?? '';
      final enabled = task['enabled'] != false;
      final manual = task['manual'] == true;
      final explicit = _strings(task['requiredCapabilities']).toSet();
      final inferred = <String>{
        ...(defaults[task['taskType']?.toString() ?? 'analysis'] ??
            const <String>[]),
      };
      final outputArtifacts = _maps(task['outputArtifacts']);
      if (outputArtifacts.isNotEmpty && !manual) {
        inferred.add('project.mutate');
      }
      for (final artifact in outputArtifacts) {
        for (final validator in _maps(artifact['validators'])) {
          final capability =
              validatorCapabilities[validator['kind']?.toString() ?? ''];
          if (capability != null) {
            inferred.add(capability);
          }
        }
      }
      for (final validator in _maps(task['verification'])) {
        final capability =
            validatorCapabilities[validator['kind']?.toString() ?? ''];
        if (capability != null) {
          inferred.add(capability);
        }
      }
      if (task['dataBoundary'] == 'network') {
        inferred.add('research.network');
      }
      if (task['dataBoundary'] == 'external') {
        inferred.add('external.mcp');
      }
      if (manual) {
        inferred.add('human.approval');
      }
      final required = <String>{...explicit, ...inferred};
      final allowed = _strings(task['allowedTools']).toSet();
      final taskBlocks = blockReasons.putIfAbsent(taskId, () => <String>{});

      for (final toolName in allowed.difference(knownTools)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'tool_unknown',
            message: 'Task $taskId allows unknown tool $toolName.',
            taskId: taskId,
          ),
        );
        taskBlocks.add('tool_unknown');
      }
      for (final capabilityName in required.toList()..sort()) {
        capabilityRequired += 1;
        final capability = capabilities[capabilityName];
        if (capability == null) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'capability_unknown',
              message:
                  'Task $taskId requires unknown capability $capabilityName.',
              taskId: taskId,
            ),
          );
          taskBlocks.add('capability_unknown');
          continue;
        }
        final covered = capabilityName == 'human.approval'
            ? manual ||
                const <String>{'approval', 'manual'}
                    .contains(task['taskType']?.toString())
            : capability.tools.intersection(allowed).isNotEmpty;
        if (covered) {
          capabilityCovered += 1;
        } else {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'capability_tool_gap',
              message:
                  'Task $taskId requires $capabilityName but allowedTools contains no tool that provides it.',
              taskId: taskId,
              details: <String, dynamic>{
                'capability': capabilityName,
                'providerTools': capability.tools.toList()..sort(),
              },
            ),
          );
          taskBlocks.add('capability_tool_gap');
        }
        if (capability.network && enabled && !manual) {
          if (effectiveLocalOnly || !policy.networkAllowed) {
            issues.add(
              PlanCompilationIssueV2(
                severity: 'error',
                code: 'network_capability_blocked',
                message:
                    'Task $taskId requires network capability $capabilityName under a network-blocking policy.',
                taskId: taskId,
              ),
            );
            taskBlocks.add('network_capability_blocked');
          }
        }
        if (capability.requiresSandbox &&
            enabled &&
            !manual &&
            !policy.sandboxAvailable) {
          if (policy.legacyUnsandboxedExecutionApproved) {
            issues.add(
              PlanCompilationIssueV2(
                severity: 'warning',
                code: 'legacy_unsandboxed_execution',
                message:
                    'Task $taskId requires $capabilityName; execution is permitted only by the explicit legacy unsandboxed override.',
                taskId: taskId,
              ),
            );
            approvals.add('legacy_unsandboxed_execution');
          } else {
            issues.add(
              PlanCompilationIssueV2(
                severity: 'error',
                code: 'sandbox_required',
                message:
                    'Task $taskId requires $capabilityName, but the v1.4 sandbox boundary is unavailable.',
                taskId: taskId,
              ),
            );
            taskBlocks.add('sandbox_required');
          }
        }
      }
      for (final capabilityName in inferred.difference(explicit)) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'required_capability_undeclared',
            message:
                'Task $taskId needs inferred capability $capabilityName, but it is absent from requiredCapabilities.',
            taskId: taskId,
          ),
        );
        taskBlocks.add('required_capability_undeclared');
      }

      final text = _taskText(task);
      if (effectiveLocalOnly && _externalClaim.hasMatch(text)) {
        final severity = manual ? 'warning' : 'error';
        issues.add(
          PlanCompilationIssueV2(
            severity: severity,
            code: 'local_only_external_claim',
            message:
                'Task $taskId contains an external-service or public-hosting claim in local-only mode.',
            taskId: taskId,
          ),
        );
        if (severity == 'error') {
          taskBlocks.add('local_only_external_claim');
        }
      }
      if (_humanClaim.hasMatch(text) && !policy.humanWorkflowAvailable) {
        if (manual) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'warning',
              code: 'human_workflow_manual',
              message:
                  'Task $taskId remains manual until a human workflow is configured.',
              taskId: taskId,
            ),
          );
        } else {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'human_workflow_missing',
              message:
                  'Task $taskId claims human participation but is not manual and no human workflow is configured.',
              taskId: taskId,
            ),
          );
          taskBlocks.add('human_workflow_missing');
        }
      }
      if (task['targetScope'] == 'host_application' &&
          !policy.selfModificationApproved) {
        issues.add(
          PlanCompilationIssueV2(
            severity: 'error',
            code: 'self_modification_not_approved',
            message:
                'Task $taskId targets Kristin itself without an explicit development-project approval.',
            taskId: taskId,
          ),
        );
        taskBlocks.add('self_modification_not_approved');
      }

      if (task['taskType'] == 'deployment' && !manual) {
        final target =
            policy.deploymentTarget ?? specification.deploymentTarget;
        if (const <String>{'none', 'external_manual'}
            .contains(specification.deploymentMode)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'deployment_mode_not_executable',
              message:
                  'Task $taskId is automated, but the specification deployment mode is ${specification.deploymentMode}.',
              taskId: taskId,
            ),
          );
          taskBlocks.add('deployment_mode_not_executable');
        }
        if (specification.deploymentMode == 'external_automated' &&
            (target == null || target.trim().isEmpty)) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'deployment_target_missing',
              message:
                  'Task $taskId requests automated deployment without a configured target.',
              taskId: taskId,
            ),
          );
          taskBlocks.add('deployment_target_missing');
        }
        approvals.add('deployment');
      }

      final localValidatorIds = <String>{};
      for (final artifact in outputArtifacts) {
        for (final validator in _maps(artifact['validators'])) {
          final id = validator['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            localValidatorIds.add(id);
          }
        }
      }
      for (final validator in _maps(task['verification'])) {
        final id = validator['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          localValidatorIds.add(id);
        }
      }
      for (final criterion in _maps(task['acceptanceCriteria'])) {
        criteriaTotal += 1;
        final references = _strings(criterion['evidenceValidatorIds']).toSet();
        if (references.isNotEmpty &&
            references.difference(localValidatorIds).isEmpty) {
          criteriaVerified += 1;
        } else {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'acceptance_evidence_missing',
              message:
                  'Task $taskId has an acceptance criterion without resolvable validator evidence.',
              taskId: taskId,
              details: <String, dynamic>{
                'criterionId': criterion['id'],
                'missing': references.difference(localValidatorIds).toList()
                  ..sort(),
              },
            ),
          );
          taskBlocks.add('acceptance_evidence_missing');
        }
      }
      for (final artifact in outputArtifacts) {
        artifactsTotal += 1;
        final validators = _maps(artifact['validators']);
        final deterministic = validators.any(
          (item) =>
              item['deterministic'] == true && item['kind'] != 'manual_review',
        );
        if (deterministic || manual) {
          artifactsValidated += 1;
        } else if (artifact['required'] == true) {
          issues.add(
            PlanCompilationIssueV2(
              severity: 'error',
              code: 'artifact_validator_missing',
              message:
                  'Required artifact ${artifact['id']} from task $taskId lacks a deterministic validator.',
              taskId: taskId,
            ),
          );
          taskBlocks.add('artifact_validator_missing');
        }
        final path = artifact['path']?.toString().replaceAll('\\', '/') ?? '';
        if (path.isNotEmpty) {
          final prior = producedPaths[path];
          final dependencies = _strings(task['dependencies']).toSet();
          if (prior != null && !dependencies.contains(prior)) {
            issues.add(
              PlanCompilationIssueV2(
                severity: 'error',
                code: 'artifact_path_producer_conflict',
                message:
                    'Tasks $prior and $taskId both produce $path without an explicit dependency.',
                taskId: taskId,
              ),
            );
            taskBlocks.add('artifact_path_producer_conflict');
          }
          producedPaths[path] = taskId;
        }
      }

      final risk = task['risk']?.toString() ?? 'low';
      if (const <String>{'high', 'critical'}.contains(risk)) {
        approvals.add('risk:$risk');
      }
      final boundary = task['dataBoundary']?.toString() ?? 'project';
      if (const <String>{'secret', 'external', 'network'}.contains(boundary)) {
        approvals.add('data_boundary:$boundary');
      }
      if (allowed.where(knownTools.contains).any((toolName) {
        final toolRisk = tools.contractFor(toolName).risk;
        return const <ToolRisk>{
          ToolRisk.destructive,
          ToolRisk.external,
          ToolRisk.network,
        }.contains(toolRisk);
      })) {
        approvals.add('high_risk_tool');
      }

      final status = !enabled
          ? 'disabled'
          : manual
              ? 'manual'
              : taskBlocks.isNotEmpty
                  ? 'blocked'
                  : 'ready';
      compiledTasks.add(<String, dynamic>{
        'id': taskId,
        'status': status,
        'inferredCapabilities': inferred.toList()..sort(),
        'requiredCapabilities': required.toList()..sort(),
        'allowedTools': allowed.toList()..sort(),
        'approvalRequired': manual ||
            const <String>{'high', 'critical'}.contains(risk) ||
            const <String>{'secret', 'external', 'network'}.contains(boundary),
        'blockReasons': taskBlocks.toList()..sort(),
      });
    }

    final schedule = _topologicalBatches(tasks);
    final order = schedule.$1;
    final batches = schedule.$2;
    final batchIndex = <String, int>{
      for (var index = 0; index < batches.length; index++)
        for (final taskId in batches[index]) taskId: index,
    };
    for (final task in compiledTasks) {
      final taskId = task['id']?.toString() ?? '';
      task['topologicalIndex'] =
          order.contains(taskId) ? order.indexOf(taskId) : null;
      task['executionBatch'] = batchIndex[taskId];
    }

    final enabledTasks = tasks.where((task) => task['enabled'] != false);
    final totalModelTurns = enabledTasks.fold<int>(
      0,
      (total, task) =>
          total + _int(_map(task['budgets'])['modelTurns'], fallback: 0),
    );
    final totalToolCalls = enabledTasks.fold<int>(
      0,
      (total, task) =>
          total + _int(_map(task['budgets'])['toolCalls'], fallback: 0),
    );
    final totalOutputBytes = enabledTasks.fold<int>(
      0,
      (total, task) =>
          total + _int(_map(task['budgets'])['outputBytes'], fallback: 0),
    );
    _checkBudget(
      issues,
      label: 'model turns',
      actual: totalModelTurns,
      maximum: policy.maxTotalModelTurns,
    );
    _checkBudget(
      issues,
      label: 'tool calls',
      actual: totalToolCalls,
      maximum: policy.maxTotalToolCalls,
    );
    _checkBudget(
      issues,
      label: 'output bytes',
      actual: totalOutputBytes,
      maximum: policy.maxTotalOutputBytes,
    );

    final errors = issues.where((item) => item.severity == 'error').toList();
    final warnings =
        issues.where((item) => item.severity == 'warning').toList();
    final graphErrorCodes = <String>{
      'task_id_duplicate',
      'dependency_missing',
      'dependency_disabled',
      'dependency_cycle',
      'parent_missing',
      'parent_cycle',
      'parent_self_reference',
    };
    final policyErrorCodes = <String>{
      'network_capability_blocked',
      'sandbox_required',
      'local_only_external_claim',
      'human_workflow_missing',
      'self_modification_not_approved',
      'deployment_mode_not_executable',
      'deployment_target_missing',
      'plan_budget_exceeded',
    };
    final graphErrors =
        errors.where((item) => graphErrorCodes.contains(item.code)).length;
    final policyErrors =
        errors.where((item) => policyErrorCodes.contains(item.code)).length;
    final schemaScore = 20.0;
    final graphScore = max(0.0, 20.0 - graphErrors * 5.0);
    final capabilityScore = capabilityRequired == 0
        ? 20.0
        : 20.0 * capabilityCovered / capabilityRequired;
    final verificationScore =
        criteriaTotal == 0 ? 15.0 : 15.0 * criteriaVerified / criteriaTotal;
    final artifactScore =
        artifactsTotal == 0 ? 15.0 : 15.0 * artifactsValidated / artifactsTotal;
    final policyScore = max(0.0, 10.0 - policyErrors * 3.0);
    final baseScore = schemaScore +
        graphScore +
        capabilityScore +
        verificationScore +
        artifactScore +
        policyScore;
    final score = max(
      0.0,
      baseScore -
          min(40.0, errors.length * 10.0) -
          min(10.0, warnings.length * 1.0),
    );
    final statusCounts = <String, int>{};
    for (final task in compiledTasks) {
      final status = task['status']?.toString() ?? 'blocked';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }
    final simulation = <String, dynamic>{
      'dryRun': true,
      'sideEffectsPerformed': false,
      'taskCount': tasks.length,
      'enabledTaskCount': enabledTasks.length,
      'readyTaskCount': statusCounts['ready'] ?? 0,
      'manualTaskCount': statusCounts['manual'] ?? 0,
      'blockedTaskCount': statusCounts['blocked'] ?? 0,
      'disabledTaskCount': statusCounts['disabled'] ?? 0,
      'executionBatchCount': batches.length,
      'criticalPathEffortPoints': _longestEffortPath(tasks, order),
      'estimatedBudgets': <String, dynamic>{
        'modelTurns': totalModelTurns,
        'toolCalls': totalToolCalls,
        'outputBytes': totalOutputBytes,
      },
      'materialOutputPaths': producedPaths.keys.toList()..sort(),
      'requiredApprovals': approvals.toList()..sort(),
      'sandboxAvailable': policy.sandboxAvailable,
      'localOnly': effectiveLocalOnly,
    };
    final inputHash = Sha256.text(
      canonicalJson(<String, dynamic>{
        'specification': specification.toJson(),
        'plan': plan.toJson(),
        'policy': policyJson,
        'toolRegistryVersion': tools.schemas.version,
        'capabilityCatalogVersion':
            PromptStudioV2Contracts.capabilityCatalog['catalogVersion'],
      }),
    );
    final report = <String, dynamic>{
      'schemaVersion': '1.0.0',
      'planId': plan.id,
      'specificationId': specification.id,
      'inputHash': inputHash,
      'compilerVersion': promptStudioCompilerVersion,
      'executable': errors.isEmpty,
      'issues': (issues.map((item) => item.toJson()).toList()
        ..sort((left, right) {
          final severityOrder = <String, int>{
            'error': 0,
            'warning': 1,
            'info': 2,
          };
          final severity = (severityOrder[left['severity']] ?? 3)
              .compareTo(severityOrder[right['severity']] ?? 3);
          if (severity != 0) {
            return severity;
          }
          final task = (left['taskId']?.toString() ?? '')
              .compareTo(right['taskId']?.toString() ?? '');
          if (task != 0) {
            return task;
          }
          return (left['code']?.toString() ?? '')
              .compareTo(right['code']?.toString() ?? '');
        })),
      'topologicalOrder': order,
      'executionBatches': batches,
      'compiledTasks': compiledTasks,
      'quality': <String, dynamic>{
        'score': double.parse(score.toStringAsFixed(2)),
        'grade': _grade(score),
        'categories': <String, dynamic>{
          'schema': schemaScore,
          'graph': double.parse(graphScore.toStringAsFixed(2)),
          'capability': double.parse(capabilityScore.toStringAsFixed(2)),
          'verification': double.parse(verificationScore.toStringAsFixed(2)),
          'artifacts': double.parse(artifactScore.toStringAsFixed(2)),
          'policy': double.parse(policyScore.toStringAsFixed(2)),
        },
        'metrics': <String, dynamic>{
          'errors': errors.length,
          'warnings': warnings.length,
          'capabilitiesCovered': capabilityCovered,
          'capabilitiesRequired': capabilityRequired,
          'criteriaVerified': criteriaVerified,
          'criteriaTotal': criteriaTotal,
          'artifactsValidated': artifactsValidated,
          'artifactsTotal': artifactsTotal,
        },
      },
      'simulation': simulation,
    };
    report['outputHash'] = Sha256.text(canonicalJson(report));
    final reportIssues =
        PromptStudioV2Contracts.validateCompilationReport(report);
    if (reportIssues.isNotEmpty) {
      throw PromptStudioV2ValidationException(
        document: 'plan_compilation_report',
        issues: reportIssues,
      );
    }
    return report;
  }

  (Map<String, _CapabilityV2>, Map<String, List<String>>, Map<String, String>)
      _capabilities() {
    final catalog = PromptStudioV2Contracts.capabilityCatalog;
    final capabilities = <String, _CapabilityV2>{};
    for (final item in _maps(catalog['capabilities'])) {
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty) {
        continue;
      }
      capabilities[name] = _CapabilityV2(
        name: name,
        tools: _strings(item['tools']).toSet(),
        requiresSandbox: item['requiresSandbox'] == true,
        network: item['network'] == true,
        mutation: item['mutation'] == true,
      );
    }
    final defaults = <String, List<String>>{
      for (final entry in _map(catalog['taskTypeDefaults']).entries)
        entry.key: _strings(entry.value),
    };
    final validators = <String, String>{
      for (final entry in _map(catalog['validatorCapabilities']).entries)
        entry.key: entry.value.toString(),
    };
    return (capabilities, defaults, validators);
  }

  List<List<String>> _cycles(
    List<String> nodes,
    Map<String, Set<String>> edges,
  ) {
    final state = <String, int>{for (final node in nodes) node: 0};
    final stack = <String>[];
    final found = <List<String>>[];

    void visit(String node) {
      state[node] = 1;
      stack.add(node);
      final next = (edges[node] ?? const <String>{}).toList()..sort();
      for (final dependency in next) {
        if (!state.containsKey(dependency)) {
          continue;
        }
        if (state[dependency] == 0) {
          visit(dependency);
        } else if (state[dependency] == 1) {
          final index = stack.indexOf(dependency);
          if (index >= 0) {
            found.add(<String>[...stack.sublist(index), dependency]);
          }
        }
      }
      stack.removeLast();
      state[node] = 2;
    }

    for (final node in nodes) {
      if (state[node] == 0) {
        visit(node);
      }
    }
    final unique = <String, List<String>>{};
    for (final cycle in found) {
      unique[cycle.join('|')] = cycle;
    }
    return unique.values.toList();
  }

  (List<String>, List<List<String>>) _topologicalBatches(
    List<Map<String, dynamic>> tasks,
  ) {
    final enabled = tasks.where((task) => task['enabled'] != false).toList();
    final ids = enabled.map((task) => task['id']?.toString() ?? '').toSet();
    final dependencies = <String, Set<String>>{
      for (final task in enabled)
        task['id']?.toString() ?? '':
            _strings(task['dependencies']).where(ids.contains).toSet(),
    }..remove('');
    final reverse = <String, Set<String>>{};
    final indegree = <String, int>{
      for (final entry in dependencies.entries) entry.key: entry.value.length,
    };
    for (final entry in dependencies.entries) {
      for (final dependency in entry.value) {
        reverse.putIfAbsent(dependency, () => <String>{}).add(entry.key);
      }
    }
    final orderValues = <String, int>{
      for (final task in enabled)
        task['id']?.toString() ?? '': _int(task['order'], fallback: 0),
    }..remove('');
    int compare(String left, String right) {
      final order = (orderValues[left] ?? 0).compareTo(orderValues[right] ?? 0);
      return order == 0 ? left.compareTo(right) : order;
    }

    var ready = indegree.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList()
      ..sort(compare);
    final order = <String>[];
    final batches = <List<String>>[];
    while (ready.isNotEmpty) {
      final batch = List<String>.from(ready);
      batches.add(batch);
      order.addAll(batch);
      final next = <String>[];
      for (final taskId in batch) {
        final children = (reverse[taskId] ?? const <String>{}).toList()
          ..sort(compare);
        for (final child in children) {
          indegree[child] = (indegree[child] ?? 1) - 1;
          if (indegree[child] == 0) {
            next.add(child);
          }
        }
      }
      ready = next..sort(compare);
    }
    final remaining = ids.difference(order.toSet()).toList()..sort(compare);
    order.addAll(remaining);
    return (order, batches);
  }

  int _longestEffortPath(
    List<Map<String, dynamic>> tasks,
    List<String> order,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final task in tasks.where((item) => item['enabled'] != false))
        task['id']?.toString() ?? '': task,
    }..remove('');
    final distance = <String, int>{};
    for (final taskId in order) {
      final task = byId[taskId];
      if (task == null) {
        continue;
      }
      final parents = _strings(task['dependencies'])
          .map((dependency) => distance[dependency] ?? 0);
      final prior = parents.isEmpty ? 0 : parents.reduce(max);
      distance[taskId] = prior + _int(task['effortPoints'], fallback: 1);
    }
    return distance.values.isEmpty ? 0 : distance.values.reduce(max);
  }

  void _checkBudget(
    List<PlanCompilationIssueV2> issues, {
    required String label,
    required int actual,
    required int maximum,
  }) {
    if (actual <= maximum) {
      return;
    }
    issues.add(
      PlanCompilationIssueV2(
        severity: 'error',
        code: 'plan_budget_exceeded',
        message: 'Plan $label budget $actual exceeds policy maximum $maximum.',
      ),
    );
  }

  String _taskText(Map<String, dynamic> task) {
    final parts = <String>[
      task['title']?.toString() ?? '',
      task['objective']?.toString() ?? '',
      task['instructions']?.toString() ?? '',
    ];
    for (final artifact in _maps(task['outputArtifacts'])) {
      parts.add(artifact['description']?.toString() ?? '');
      parts.add(artifact['path']?.toString() ?? '');
    }
    for (final criterion in _maps(task['acceptanceCriteria'])) {
      parts.add(criterion['statement']?.toString() ?? '');
    }
    return parts.join(' ').toLowerCase();
  }

  String _grade(num score) {
    if (score >= 90) {
      return 'A';
    }
    if (score >= 80) {
      return 'B';
    }
    if (score >= 70) {
      return 'C';
    }
    if (score >= 60) {
      return 'D';
    }
    return 'F';
  }
}

class PromptStudioV2Evaluator {
  const PromptStudioV2Evaluator();

  Map<String, dynamic> comparePromptVersions({
    required Map<String, dynamic> baseline,
    required Map<String, dynamic> candidate,
    required PromptEvaluationDatasetV1 dataset,
  }) {
    final baselineResult = evaluatePrompt(baseline, dataset);
    final candidateResult = evaluatePrompt(candidate, dataset);
    final result = <String, dynamic>{
      'schemaVersion': '1.0.0',
      'datasetId': dataset.id,
      'baseline': baselineResult,
      'candidate': candidateResult,
      'diff': diffPromptVersions(baseline, candidate),
      'measuredImpact': <String, dynamic>{
        'scoreDelta': double.parse(
          ((candidateResult['score'] as num) - (baselineResult['score'] as num))
              .toStringAsFixed(2),
        ),
        'passedCaseDelta': _int(candidateResult['passedCases'], fallback: 0) -
            _int(baselineResult['passedCases'], fallback: 0),
        'acceptanceCriterionDelta':
            _list(candidate['acceptanceCriteria']).length -
                _list(baseline['acceptanceCriteria']).length,
        'variableDelta': _list(candidate['variables']).length -
            _list(baseline['variables']).length,
      },
    };
    result['comparisonHash'] = Sha256.text(canonicalJson(result));
    return result;
  }

  Map<String, dynamic> evaluatePrompt(
    Map<String, dynamic> prompt,
    PromptEvaluationDatasetV1 dataset,
  ) {
    final text = <String>[
      prompt['title']?.toString() ?? '',
      prompt['purpose']?.toString() ?? '',
      prompt['systemPrompt']?.toString() ?? '',
      prompt['userPrompt']?.toString() ?? '',
      ..._strings(prompt['assumptions']),
      ..._strings(prompt['clarifyingQuestions']),
      ..._strings(prompt['outputExpectations']),
      ..._strings(prompt['guardrails']),
      ..._strings(prompt['stopConditions']),
    ].join(' ').toLowerCase();
    final criteria =
        _strings(prompt['acceptanceCriteria']).join(' ').toLowerCase();
    final variables = _strings(prompt['variables']).toSet();
    final cases = <Map<String, dynamic>>[];
    var weightedScore = 0.0;
    var totalWeight = 0.0;
    for (final item in dataset.cases) {
      final checks = <Map<String, dynamic>>[];
      for (final term in _strings(item['requiredTerms'])) {
        checks.add(<String, dynamic>{
          'kind': 'required_term',
          'value': term,
          'passed': text.contains(term.toLowerCase()),
        });
      }
      for (final term in _strings(item['forbiddenTerms'])) {
        checks.add(<String, dynamic>{
          'kind': 'forbidden_term',
          'value': term,
          'passed': !text.contains(term.toLowerCase()),
        });
      }
      for (final variable in _strings(item['requiredVariables'])) {
        checks.add(<String, dynamic>{
          'kind': 'required_variable',
          'value': variable,
          'passed': variables.contains(variable),
        });
      }
      for (final term in _strings(item['requiredCriterionTerms'])) {
        checks.add(<String, dynamic>{
          'kind': 'criterion_term',
          'value': term,
          'passed': criteria.contains(term.toLowerCase()),
        });
      }
      final expectedMode = item['expectedMode']?.toString() ?? '';
      checks.add(<String, dynamic>{
        'kind': 'expected_mode',
        'value': expectedMode,
        'passed': prompt['mode']?.toString() == expectedMode,
      });
      final passed = checks.where((check) => check['passed'] == true).length;
      final score = checks.isEmpty ? 100.0 : 100.0 * passed / checks.length;
      final weight = _number(item['weight'], fallback: 1.0);
      weightedScore += score * weight;
      totalWeight += weight;
      cases.add(<String, dynamic>{
        'id': item['id']?.toString() ?? '',
        'score': double.parse(score.toStringAsFixed(2)),
        'passed': checks.every((check) => check['passed'] == true),
        'checks': checks,
        'tags': _strings(item['tags']),
        'weight': weight,
      });
    }
    final score = totalWeight == 0 ? 0.0 : weightedScore / totalWeight;
    final result = <String, dynamic>{
      'schemaVersion': '1.0.0',
      'datasetId': dataset.id,
      'promptHash': Sha256.text(canonicalJson(prompt)),
      'score': double.parse(score.toStringAsFixed(2)),
      'passedCases': cases.where((item) => item['passed'] == true).length,
      'caseCount': cases.length,
      'cases': cases,
    };
    result['resultHash'] = Sha256.text(canonicalJson(result));
    return result;
  }

  Map<String, dynamic> diffPromptVersions(
    Map<String, dynamic> baseline,
    Map<String, dynamic> candidate,
  ) {
    final fields = <String>{...baseline.keys, ...candidate.keys}.toList()
      ..sort();
    final changed = <Map<String, dynamic>>[];
    for (final field in fields) {
      final before = baseline[field];
      final after = candidate[field];
      if (canonicalJson(before) == canonicalJson(after)) {
        continue;
      }
      final item = <String, dynamic>{
        'field': field,
        'beforeHash': Sha256.text(canonicalJson(before)),
        'afterHash': Sha256.text(canonicalJson(after)),
      };
      if (before is List && after is List) {
        final beforeValues = <String, Object?>{
          for (final value in before) canonicalJson(value): value,
        };
        final afterValues = <String, Object?>{
          for (final value in after) canonicalJson(value): value,
        };
        final addedKeys = afterValues.keys
            .toSet()
            .difference(beforeValues.keys.toSet())
            .toList()
          ..sort();
        final removedKeys = beforeValues.keys
            .toSet()
            .difference(afterValues.keys.toSet())
            .toList()
          ..sort();
        item['added'] = addedKeys.map((key) => afterValues[key]).toList();
        item['removed'] = removedKeys.map((key) => beforeValues[key]).toList();
      }
      changed.add(item);
    }
    final result = <String, dynamic>{
      'schemaVersion': '1.0.0',
      'baselineHash': Sha256.text(canonicalJson(baseline)),
      'candidateHash': Sha256.text(canonicalJson(candidate)),
      'changedFields': changed,
      'changedFieldCount': changed.length,
    };
    result['diffHash'] = Sha256.text(canonicalJson(result));
    return result;
  }
}

class PromptStudioV2Service {
  PromptStudioV2Service({
    required ToolRegistry tools,
    required this.audit,
    required this.events,
    required ProductSettings Function() settingsProvider,
  })  : compiler = PromptStudioV2Compiler(tools),
        _settingsProvider = settingsProvider;

  final PromptStudioV2Compiler compiler;
  final PromptStudioV2Evaluator evaluator = const PromptStudioV2Evaluator();
  final AuditChain audit;
  final EventJournal events;
  final ProductSettings Function() _settingsProvider;

  ProductSpecificationV2 validateSpecification(Map<String, dynamic> value) =>
      ProductSpecificationV2.fromJson(value);

  TaskPlanV2 validateTaskPlan(Map<String, dynamic> value) =>
      TaskPlanV2.fromJson(value);

  PromptEvaluationDatasetV1 validateEvaluationDataset(
    Map<String, dynamic> value,
  ) =>
      PromptEvaluationDatasetV1.fromJson(value);

  Future<Map<String, dynamic>> compileAndSimulate({
    required Map<String, dynamic> specification,
    required Map<String, dynamic> plan,
    PlanCompilerPolicyV2? policy,
  }) async {
    final settings = _settingsProvider();
    final effectivePolicy = policy ??
        PlanCompilerPolicyV2(
          localOnly: settings.localOnly,
          sandboxAvailable: false,
          legacyUnsandboxedExecutionApproved: false,
          networkAllowed: !settings.localOnly,
        );
    final specificationDocument = validateSpecification(specification);
    final planDocument = validateTaskPlan(plan);
    final report = compiler.compile(
      specification: specificationDocument,
      plan: planDocument,
      policy: effectivePolicy,
    );
    await audit.append(
      'prompt_studio_v2.plan_compiled',
      planDocument.id,
      <String, dynamic>{
        'planId': planDocument.id,
        'specificationId': specificationDocument.id,
        'inputHash': report['inputHash'],
        'outputHash': report['outputHash'],
        'executable': report['executable'],
        'quality': report['quality'],
        'simulation': report['simulation'],
        'contractDigest': promptStudioContractDigest,
      },
    );
    await events.publish(
      'prompt_studio_v2.plan_compiled',
      planDocument.id,
      <String, dynamic>{
        'planId': planDocument.id,
        'specificationId': specificationDocument.id,
        'outputHash': report['outputHash'],
        'executable': report['executable'],
        'qualityScore': _map(report['quality'])['score'],
        'readyTaskCount': _map(report['simulation'])['readyTaskCount'],
        'blockedTaskCount': _map(report['simulation'])['blockedTaskCount'],
      },
    );
    return report;
  }

  Future<Map<String, dynamic>> comparePromptVersions({
    required Map<String, dynamic> baseline,
    required Map<String, dynamic> candidate,
    required Map<String, dynamic> dataset,
  }) async {
    final datasetDocument = validateEvaluationDataset(dataset);
    final report = evaluator.comparePromptVersions(
      baseline: baseline,
      candidate: candidate,
      dataset: datasetDocument,
    );
    await audit.append(
      'prompt_studio_v2.prompt_evaluated',
      datasetDocument.id,
      <String, dynamic>{
        'datasetId': datasetDocument.id,
        'baselineHash': _map(report['diff'])['baselineHash'],
        'candidateHash': _map(report['diff'])['candidateHash'],
        'measuredImpact': report['measuredImpact'],
        'comparisonHash': report['comparisonHash'],
      },
    );
    await events.publish(
      'prompt_studio_v2.prompt_evaluated',
      datasetDocument.id,
      <String, dynamic>{
        'datasetId': datasetDocument.id,
        'measuredImpact': report['measuredImpact'],
        'comparisonHash': report['comparisonHash'],
      },
    );
    return report;
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false)
    : const <Map<String, dynamic>>[];

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

List<String> _strings(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const <String>[];

int _int(Object? value, {required int fallback}) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;

double _number(Object? value, {required double fallback}) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? fallback;

String? _optionalString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

Map<String, dynamic> _deepMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
