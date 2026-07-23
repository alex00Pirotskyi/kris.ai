import 'dart:convert';
import 'dart:math';

const String kristinVersion = '1.9.0+190';
const String kristinReleaseChannel = 'preview';

enum CommandMode { ask, analyze, plan, build, fix, review, run }

bool isConversationalRequest(String request) {
  final normalized = request
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return false;
  }
  return RegExp(
        r'^(?:hi|hello|hey|hiya|howdy|good morning|good afternoon|good evening)'
        r'(?: there| kristin)?[!,.?]*$',
      ).hasMatch(normalized) ||
      RegExp(
        r'^(?:thanks|thank you|thank you very much|who are you|what can you do|'
        r'how are you|help|chat)[!,.?]*$',
      ).hasMatch(normalized);
}

bool isFailureInvestigationRequest(String request) {
  final normalized = request
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return false;
  }
  if (RegExp(
    r'\b(?:what went wrong (?:in|with|during)|diagnose|debug|troubleshoot|investigate) '
    r'(?:the )?(?:previous|prior|last|current|this|that) '
    r'(?:kristin )?(?:run|execution|attempt|workflow|job|session)\b',
  ).hasMatch(normalized)) {
    return true;
  }
  final runReference = RegExp(
    r'\b(?:kristin|agent|run|execution|attempt|workflow|job|session)\b',
  ).hasMatch(normalized);
  final taskReference = RegExp(r'\btask\b').hasMatch(normalized);
  final historicalReference = RegExp(
    r'\b(?:previous|prior|last|earlier|current|this|that|same)\b',
  ).hasMatch(normalized);
  final diagnosticVerb = RegExp(
    r'\b(?:diagnose|debug|troubleshoot|investigate|retry|resume|replay)\b',
  ).hasMatch(normalized);
  final failureSignal = RegExp(
    r'\b(?:fail(?:ed|ure|ing)?|timeout|invalid action|crash(?:ed)?|'
    r'interrupted?|stalled|exhausted)\b',
  ).hasMatch(normalized);
  if (runReference) {
    if (failureSignal && (historicalReference || diagnosticVerb)) {
      return true;
    }
    if (diagnosticVerb && historicalReference) {
      return true;
    }
  }
  return taskReference &&
      failureSignal &&
      (historicalReference || diagnosticVerb);
}

enum PermissionScope {
  projectRead,
  projectWrite,
  projectDelete,
  executeFinite,
  executeManaged,
  networkResearch,
  networkPackages,
  secretUse,
  deploymentPackage,
  mcpConnect,
}

enum RunState {
  prepared,
  awaitingApproval,
  queued,
  running,
  paused,
  cancelling,
  cancelled,
  succeeded,
  failed,
  interrupted,
}

enum WorkItemState {
  queued,
  running,
  blocked,
  awaitingApproval,
  succeeded,
  failed,
  cancelled,
}

enum EvidenceKind {
  model,
  research,
  knowledge,
  mutation,
  command,
  test,
  verification,
  deployment,
  audit,
}

enum ModelProviderKind { ollama, openAiCompatible }

String newId([String prefix = 'id']) {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  final entropy = List<int>.generate(12, (_) => random.nextInt(256));
  final token = base64UrlEncode(entropy).replaceAll('=', '');
  return '${prefix}_$now$token';
}

DateTime parseUtc(Object? value, {DateTime? fallback}) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) { return parsed.toUtc(); }
  }
  return fallback?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

List<String> stringList(Object? value) => value is List
    ? value.whereType<Object>().map((item) => item.toString()).toList()
    : const <String>[];

Map<String, dynamic> mapValue(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : <String, dynamic>{};

class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String rootPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'rootPath': rootPath,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory ProjectRecord.fromJson(Map<String, dynamic> json) => ProjectRecord(
        id: json['id']?.toString() ?? newId('project'),
        name: json['name']?.toString() ?? 'Project',
        rootPath: json['rootPath']?.toString() ?? '',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        updatedAt: parseUtc(json['updatedAt'], fallback: DateTime.now()),
      );
}

class SecretReference {
  const SecretReference({
    required this.id,
    required this.label,
    required this.environmentKey,
    required this.createdAt,
    this.description = '',
  });

  final String id;
  final String label;
  final String environmentKey;
  final String description;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'environmentKey': environmentKey,
        'description': description,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory SecretReference.fromJson(Map<String, dynamic> json) => SecretReference(
        id: json['id']?.toString() ?? newId('secret'),
        label: json['label']?.toString() ?? 'Secret',
        environmentKey: json['environmentKey']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class PermissionGrant {
  const PermissionGrant({
    required this.id,
    required this.projectId,
    required this.commandId,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
    required this.remainingUses,
  });

  final String id;
  final String projectId;
  final String commandId;
  final Set<PermissionScope> scopes;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int remainingUses;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
  bool allows(PermissionScope scope) => !isExpired && remainingUses > 0 && scopes.contains(scope);

  PermissionGrant consume() => PermissionGrant(
        id: id,
        projectId: projectId,
        commandId: commandId,
        scopes: scopes,
        createdAt: createdAt,
        expiresAt: expiresAt,
        remainingUses: remainingUses <= 0 ? 0 : remainingUses - 1,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'commandId': commandId,
        'scopes': scopes.map((scope) => scope.name).toList()..sort(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'remainingUses': remainingUses,
      };

  factory PermissionGrant.fromJson(Map<String, dynamic> json) => PermissionGrant(
        id: json['id']?.toString() ?? newId('grant'),
        projectId: json['projectId']?.toString() ?? '',
        commandId: json['commandId']?.toString() ?? '',
        scopes: stringList(json['scopes'])
            .map((name) => PermissionScope.values.where((scope) => scope.name == name).firstOrNull)
            .whereType<PermissionScope>()
            .toSet(),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        expiresAt: parseUtc(json['expiresAt'], fallback: DateTime.now()),
        remainingUses: int.tryParse(json['remainingUses']?.toString() ?? '') ?? 0,
      );
}

class ApiTokenRecord {
  const ApiTokenRecord({
    required this.id,
    required this.label,
    required this.hash,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
    this.projectId,
    this.revokedAt,
  });

  final String id;
  final String label;
  final String hash;
  final Set<String> scopes;
  final String? projectId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'hash': hash,
        'scopes': scopes.toList()..sort(),
        'projectId': projectId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
      };

  factory ApiTokenRecord.fromJson(Map<String, dynamic> json) => ApiTokenRecord(
        id: json['id']?.toString() ?? newId('token'),
        label: json['label']?.toString() ?? 'API token',
        hash: json['hash']?.toString() ?? '',
        scopes: stringList(json['scopes']).toSet(),
        projectId: json['projectId']?.toString(),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        expiresAt: parseUtc(json['expiresAt'], fallback: DateTime.now()),
        revokedAt: json['revokedAt'] == null ? null : parseUtc(json['revokedAt']),
      );
}

class ModelIdentity {
  const ModelIdentity({
    required this.providerId,
    required this.name,
    required this.digest,
    required this.discoveredAt,
    this.parameterSize = '',
    this.quantization = '',
  });

  final String providerId;
  final String name;
  final String digest;
  final String parameterSize;
  final String quantization;
  final DateTime discoveredAt;

  String get exactId => digest.isEmpty ? '$providerId/$name' : '$providerId/$name@$digest';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'providerId': providerId,
        'name': name,
        'digest': digest,
        'parameterSize': parameterSize,
        'quantization': quantization,
        'discoveredAt': discoveredAt.toUtc().toIso8601String(),
      };

  factory ModelIdentity.fromJson(Map<String, dynamic> json) => ModelIdentity(
        providerId: json['providerId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        digest: json['digest']?.toString() ?? '',
        parameterSize: json['parameterSize']?.toString() ?? '',
        quantization: json['quantization']?.toString() ?? '',
        discoveredAt: parseUtc(json['discoveredAt'], fallback: DateTime.now()),
      );
}

class AcceptanceCriterion {
  const AcceptanceCriterion({
    required this.id,
    required this.statement,
    required this.verification,
  });

  final String id;
  final String statement;
  final String verification;

  bool get isMeasurable {
    final combined = '$statement $verification'.toLowerCase();
    const markers = <String>[
      'test', 'verify', 'returns', 'renders', 'build', 'exit code', 'contains',
      'responds', 'passes', 'creates', 'does not', 'without', 'within', 'equals',
    ];
    return statement.trim().length >= 12 &&
        verification.trim().length >= 5 &&
        markers.any(combined.contains);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'statement': statement,
        'verification': verification,
      };

  factory AcceptanceCriterion.fromJson(Map<String, dynamic> json) => AcceptanceCriterion(
        id: json['id']?.toString() ?? newId('criterion'),
        statement: json['statement']?.toString() ?? '',
        verification: json['verification']?.toString() ?? '',
      );
}

class TaskContract {
  const TaskContract({
    required this.id,
    required this.revision,
    required this.projectId,
    required this.mode,
    required this.request,
    required this.acceptanceCriteria,
    required this.constraints,
    required this.researchQuestions,
    required this.requiredPermissions,
    required this.createdAt,
  });

  final String id;
  final int revision;
  final String projectId;
  final CommandMode mode;
  final String request;
  final List<AcceptanceCriterion> acceptanceCriteria;
  final List<String> constraints;
  final List<String> researchQuestions;
  final Set<PermissionScope> requiredPermissions;
  final DateTime createdAt;

  List<String> validate() {
    final errors = <String>[];
    if (projectId.trim().isEmpty) { errors.add('A project is required.'); }
    if (request.trim().length < 3 && !isConversationalRequest(request)) { errors.add('The request is too short.'); }
    if (acceptanceCriteria.isEmpty && mode != CommandMode.ask) {
      errors.add('At least one acceptance criterion is required.');
    }
    for (final criterion in acceptanceCriteria) {
      if (!criterion.isMeasurable) {
        errors.add('Criterion "${criterion.statement}" is not measurable.');
      }
    }
    return errors;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'revision': revision,
        'projectId': projectId,
        'mode': mode.name,
        'request': request,
        'acceptanceCriteria': acceptanceCriteria.map((item) => item.toJson()).toList(),
        'constraints': constraints,
        'researchQuestions': researchQuestions,
        'requiredPermissions': requiredPermissions.map((scope) => scope.name).toList()..sort(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory TaskContract.fromJson(Map<String, dynamic> json) => TaskContract(
        id: json['id']?.toString() ?? newId('contract'),
        revision: int.tryParse(json['revision']?.toString() ?? '') ?? 1,
        projectId: json['projectId']?.toString() ?? '',
        mode: CommandMode.values.where((mode) => mode.name == json['mode']).firstOrNull ?? CommandMode.ask,
        request: json['request']?.toString() ?? '',
        acceptanceCriteria: (json['acceptanceCriteria'] is List ? json['acceptanceCriteria'] as List : const <Object>[])
            .whereType<Map>()
            .map((item) => AcceptanceCriterion.fromJson(mapValue(item)))
            .toList(),
        constraints: stringList(json['constraints']),
        researchQuestions: stringList(json['researchQuestions']),
        requiredPermissions: stringList(json['requiredPermissions'])
            .map((name) => PermissionScope.values.where((scope) => scope.name == name).firstOrNull)
            .whereType<PermissionScope>()
            .toSet(),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class WorkItem {
  const WorkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.dependencies,
    required this.allowedTools,
    required this.acceptanceCriteria,
    this.maxAttempts = 2,
  });

  final String id;
  final String title;
  final String description;
  final Set<String> dependencies;
  final Set<String> allowedTools;
  final List<String> acceptanceCriteria;
  final int maxAttempts;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'dependencies': dependencies.toList()..sort(),
        'allowedTools': allowedTools.toList()..sort(),
        'acceptanceCriteria': acceptanceCriteria,
        'maxAttempts': maxAttempts,
      };

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
        id: json['id']?.toString() ?? newId('work'),
        title: json['title']?.toString() ?? 'Work item',
        description: json['description']?.toString() ?? '',
        dependencies: stringList(json['dependencies']).toSet(),
        allowedTools: stringList(json['allowedTools']).toSet(),
        acceptanceCriteria: stringList(json['acceptanceCriteria']),
        maxAttempts: int.tryParse(json['maxAttempts']?.toString() ?? '') ?? 2,
      );
}

class ExecutionPlan {
  const ExecutionPlan({
    required this.id,
    required this.contractId,
    required this.complexity,
    required this.rationale,
    required this.items,
    required this.createdAt,
  });

  final String id;
  final String contractId;
  final int complexity;
  final String rationale;
  final List<WorkItem> items;
  final DateTime createdAt;

  List<String> validate() {
    final errors = <String>[];
    final ids = items.map((item) => item.id).toSet();
    if (ids.length != items.length) { errors.add('Work item IDs must be unique.'); }
    for (final item in items) {
      if (item.title.trim().isEmpty || item.description.trim().isEmpty) {
        errors.add('Every work item requires a title and description.');
      }
      for (final dependency in item.dependencies) {
        if (!ids.contains(dependency)) { errors.add('${item.id} references missing dependency $dependency.'); }
        if (dependency == item.id) { errors.add('${item.id} cannot depend on itself.'); }
      }
    }
    final visited = <String>{};
    final active = <String>{};
    final byId = <String, WorkItem>{for (final item in items) item.id: item};
    bool cycle(String id) {
      if (active.contains(id)) { return true; }
      if (visited.contains(id)) { return false; }
      active.add(id);
      for (final dependency in byId[id]?.dependencies ?? const <String>{}) {
        if (cycle(dependency)) { return true; }
      }
      active.remove(id);
      visited.add(id);
      return false;
    }
    if (items.any((item) => cycle(item.id))) { errors.add('The plan contains a dependency cycle.'); }
    return errors;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'contractId': contractId,
        'complexity': complexity,
        'rationale': rationale,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory ExecutionPlan.fromJson(Map<String, dynamic> json) => ExecutionPlan(
        id: json['id']?.toString() ?? newId('plan'),
        contractId: json['contractId']?.toString() ?? '',
        complexity: int.tryParse(json['complexity']?.toString() ?? '') ?? 1,
        rationale: json['rationale']?.toString() ?? '',
        items: (json['items'] is List ? json['items'] as List : const <Object>[])
            .whereType<Map>()
            .map((item) => WorkItem.fromJson(mapValue(item)))
            .toList(),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class PreparedCommand {
  const PreparedCommand({
    required this.id,
    required this.requestKey,
    required this.contract,
    required this.plan,
    required this.model,
    required this.createdAt,
  });

  final String id;
  final String requestKey;
  final TaskContract contract;
  final ExecutionPlan plan;
  final ModelIdentity model;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'requestKey': requestKey,
        'contract': contract.toJson(),
        'plan': plan.toJson(),
        'model': model.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory PreparedCommand.fromJson(Map<String, dynamic> json) => PreparedCommand(
        id: json['id']?.toString() ?? newId('command'),
        requestKey: json['requestKey']?.toString() ?? '',
        contract: TaskContract.fromJson(mapValue(json['contract'])),
        plan: ExecutionPlan.fromJson(mapValue(json['plan'])),
        model: ModelIdentity.fromJson(mapValue(json['model'])),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class EvidenceRecord {
  const EvidenceRecord({
    required this.id,
    required this.runId,
    required this.workItemId,
    required this.kind,
    required this.summary,
    required this.payload,
    required this.hash,
    required this.createdAt,
  });

  final String id;
  final String runId;
  final String workItemId;
  final EvidenceKind kind;
  final String summary;
  final Map<String, dynamic> payload;
  final String hash;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'runId': runId,
        'workItemId': workItemId,
        'kind': kind.name,
        'summary': summary,
        'payload': payload,
        'hash': hash,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory EvidenceRecord.fromJson(Map<String, dynamic> json) => EvidenceRecord(
        id: json['id']?.toString() ?? newId('evidence'),
        runId: json['runId']?.toString() ?? '',
        workItemId: json['workItemId']?.toString() ?? '',
        kind: EvidenceKind.values.where((kind) => kind.name == json['kind']).firstOrNull ?? EvidenceKind.audit,
        summary: json['summary']?.toString() ?? '',
        payload: mapValue(json['payload']),
        hash: json['hash']?.toString() ?? '',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class WorkItemProgress {
  const WorkItemProgress({
    required this.item,
    required this.state,
    required this.attempts,
    this.lastError,
    this.startedAt,
    this.completedAt,
  });

  final WorkItem item;
  final WorkItemState state;
  final int attempts;
  final String? lastError;
  final DateTime? startedAt;
  final DateTime? completedAt;

  WorkItemProgress copyWith({
    WorkItemState? state,
    int? attempts,
    String? lastError,
    bool clearError = false,
    DateTime? startedAt,
    DateTime? completedAt,
  }) =>
      WorkItemProgress(
        item: item,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item': item.toJson(),
        'state': state.name,
        'attempts': attempts,
        'lastError': lastError,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
      };

  factory WorkItemProgress.fromJson(Map<String, dynamic> json) => WorkItemProgress(
        item: WorkItem.fromJson(mapValue(json['item'])),
        state: WorkItemState.values.where((state) => state.name == json['state']).firstOrNull ?? WorkItemState.queued,
        attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
        lastError: json['lastError']?.toString(),
        startedAt: json['startedAt'] == null ? null : parseUtc(json['startedAt']),
        completedAt: json['completedAt'] == null ? null : parseUtc(json['completedAt']),
      );
}

class AutonomyBudget {
  const AutonomyBudget({
    this.maxModelRequests = 80,
    this.maxToolCalls = 160,
    this.maxMutations = 80,
    this.maxRepairs = 6,
    this.maxConsecutiveFailures = 3,
    this.maxAgentTurnsPerAttempt = 24,
    this.minModelRequestsForRetry = 6,
    this.maxRepeatedToolOutcomes = 3,
    this.maxOutputBytes = 4000000,
    this.maxWallTime = const Duration(hours: 2),
  });

  factory AutonomyBudget.forPlan(ExecutionPlan plan) {
    final items = max(1, plan.items.length);
    final perItemRequests = plan.complexity >= 8
        ? 12
        : plan.complexity >= 5
            ? 9
            : 6;
    final modelRequests = max(80, min(800, items * perItemRequests + 16));
    final toolCalls = max(160, min(1600, items * perItemRequests * 2 + 32));
    final mutations = max(80, min(500, items * 5 + 24));
    final repairs = max(6, min(120, items * 2 + 4));
    final wallTimeHours = max(2, min(12, (items + 7) ~/ 8));
    return AutonomyBudget(
      maxModelRequests: modelRequests,
      maxToolCalls: toolCalls,
      maxMutations: mutations,
      maxRepairs: repairs,
      maxWallTime: Duration(hours: wallTimeHours),
    );
  }

  final int maxModelRequests;
  final int maxToolCalls;
  final int maxMutations;
  final int maxRepairs;
  final int maxConsecutiveFailures;
  final int maxAgentTurnsPerAttempt;
  final int minModelRequestsForRetry;
  final int maxRepeatedToolOutcomes;
  final int maxOutputBytes;
  final Duration maxWallTime;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'maxModelRequests': maxModelRequests,
        'maxToolCalls': maxToolCalls,
        'maxMutations': maxMutations,
        'maxRepairs': maxRepairs,
        'maxConsecutiveFailures': maxConsecutiveFailures,
        'maxAgentTurnsPerAttempt': maxAgentTurnsPerAttempt,
        'minModelRequestsForRetry': minModelRequestsForRetry,
        'maxRepeatedToolOutcomes': maxRepeatedToolOutcomes,
        'maxOutputBytes': maxOutputBytes,
        'maxWallTimeSeconds': maxWallTime.inSeconds,
      };

  factory AutonomyBudget.fromJson(Map<String, dynamic> json) {
    int bounded(String key, int fallback, int minimum, int maximum) =>
        (int.tryParse(json[key]?.toString() ?? '') ?? fallback)
            .clamp(minimum, maximum)
            .toInt();

    return AutonomyBudget(
      maxModelRequests: bounded('maxModelRequests', 80, 1, 800),
      maxToolCalls: bounded('maxToolCalls', 160, 1, 1600),
      maxMutations: bounded('maxMutations', 80, 0, 500),
      maxRepairs: bounded('maxRepairs', 6, 0, 120),
      maxConsecutiveFailures:
          bounded('maxConsecutiveFailures', 3, 1, 10),
      maxAgentTurnsPerAttempt:
          bounded('maxAgentTurnsPerAttempt', 24, 1, 40),
      minModelRequestsForRetry:
          bounded('minModelRequestsForRetry', 6, 1, 40),
      maxRepeatedToolOutcomes:
          bounded('maxRepeatedToolOutcomes', 3, 2, 10),
      maxOutputBytes:
          bounded('maxOutputBytes', 4000000, 65536, 16000000),
      maxWallTime: Duration(
        seconds: bounded('maxWallTimeSeconds', 7200, 60, 43200),
      ),
    );
  }
}

class RunRecord {
  const RunRecord({
    required this.id,
    required this.command,
    required this.state,
    required this.items,
    required this.budget,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.summary = '',
    this.failure,
    this.modelRequests = 0,
    this.toolCalls = 0,
    this.mutations = 0,
    this.repairs = 0,
    this.sourceRunId,
  });

  final String id;
  final PreparedCommand command;
  final RunState state;
  final List<WorkItemProgress> items;
  final AutonomyBudget budget;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String summary;
  final String? failure;
  final int modelRequests;
  final int toolCalls;
  final int mutations;
  final int repairs;
  final String? sourceRunId;

  RunRecord copyWith({
    RunState? state,
    List<WorkItemProgress>? items,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? summary,
    String? failure,
    bool clearFailure = false,
    int? modelRequests,
    int? toolCalls,
    int? mutations,
    int? repairs,
  }) =>
      RunRecord(
        id: id,
        command: command,
        state: state ?? this.state,
        items: items ?? this.items,
        budget: budget,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        summary: summary ?? this.summary,
        failure: clearFailure ? null : (failure ?? this.failure),
        modelRequests: modelRequests ?? this.modelRequests,
        toolCalls: toolCalls ?? this.toolCalls,
        mutations: mutations ?? this.mutations,
        repairs: repairs ?? this.repairs,
        sourceRunId: sourceRunId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'command': command.toJson(),
        'state': state.name,
        'items': items.map((item) => item.toJson()).toList(),
        'budget': budget.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'summary': summary,
        'failure': failure,
        'modelRequests': modelRequests,
        'toolCalls': toolCalls,
        'mutations': mutations,
        'repairs': repairs,
        'sourceRunId': sourceRunId,
      };

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
        id: json['id']?.toString() ?? newId('run'),
        command: PreparedCommand.fromJson(mapValue(json['command'])),
        state: RunState.values.where((state) => state.name == json['state']).firstOrNull ?? RunState.interrupted,
        items: (json['items'] is List ? json['items'] as List : const <Object>[])
            .whereType<Map>()
            .map((item) => WorkItemProgress.fromJson(mapValue(item)))
            .toList(),
        budget: AutonomyBudget.fromJson(mapValue(json['budget'])),
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        updatedAt: parseUtc(json['updatedAt'], fallback: DateTime.now()),
        startedAt: json['startedAt'] == null ? null : parseUtc(json['startedAt']),
        completedAt: json['completedAt'] == null ? null : parseUtc(json['completedAt']),
        summary: json['summary']?.toString() ?? '',
        failure: json['failure']?.toString(),
        modelRequests: int.tryParse(json['modelRequests']?.toString() ?? '') ?? 0,
        toolCalls: int.tryParse(json['toolCalls']?.toString() ?? '') ?? 0,
        mutations: int.tryParse(json['mutations']?.toString() ?? '') ?? 0,
        repairs: int.tryParse(json['repairs']?.toString() ?? '') ?? 0,
        sourceRunId: json['sourceRunId']?.toString(),
      );
}

class EventEnvelope {
  const EventEnvelope({
    required this.sequence,
    required this.id,
    required this.type,
    required this.correlationId,
    required this.timestamp,
    required this.data,
  });

  final int sequence;
  final String id;
  final String type;
  final String correlationId;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sequence': sequence,
        'id': id,
        'type': type,
        'correlationId': correlationId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'data': data,
      };

  factory EventEnvelope.fromJson(Map<String, dynamic> json) => EventEnvelope(
        sequence: int.tryParse(json['sequence']?.toString() ?? '') ?? 0,
        id: json['id']?.toString() ?? newId('event'),
        type: json['type']?.toString() ?? 'unknown',
        correlationId: json['correlationId']?.toString() ?? '',
        timestamp: parseUtc(json['timestamp'], fallback: DateTime.now()),
        data: mapValue(json['data']),
      );
}

class ResearchSource {
  const ResearchSource({
    required this.id,
    required this.url,
    required this.title,
    required this.mimeType,
    required this.contentHash,
    required this.fetchedAt,
    required this.content,
    this.rawContent = '',
    this.statusCode = 200,
    this.responseHeaders = const <String, String>{},
    this.redirectChain = const <String>[],
    this.requestedUrl,
  });

  final String id;
  final Uri url;
  final String title;
  final String mimeType;
  final String contentHash;
  final DateTime fetchedAt;
  final String content;
  final String rawContent;
  final int statusCode;
  final Map<String, String> responseHeaders;
  final List<String> redirectChain;
  final Uri? requestedUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'url': url.toString(),
        'title': title,
        'mimeType': mimeType,
        'contentHash': contentHash,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'content': content,
        'rawContent': rawContent,
        'statusCode': statusCode,
        'responseHeaders': responseHeaders,
        'redirectChain': redirectChain,
        'requestedUrl': requestedUrl?.toString(),
        'trust': 'untrusted_external_data',
      };

  factory ResearchSource.fromJson(Map<String, dynamic> json) => ResearchSource(
        id: json['id']?.toString() ?? newId('source'),
        url: Uri.tryParse(json['url']?.toString() ?? '') ?? Uri(),
        title: json['title']?.toString() ?? '',
        mimeType: json['mimeType']?.toString() ?? 'text/plain',
        contentHash: json['contentHash']?.toString() ?? '',
        fetchedAt: parseUtc(json['fetchedAt'], fallback: DateTime.now()),
        content: json['content']?.toString() ?? '',
        rawContent: json['rawContent']?.toString() ?? '',
        statusCode: int.tryParse(json['statusCode']?.toString() ?? '') ?? 200,
        responseHeaders: mapValue(json['responseHeaders']).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        redirectChain: stringList(json['redirectChain']),
        requestedUrl: switch (json['requestedUrl']?.toString().trim() ?? '') {
          final value when value.isNotEmpty => Uri.tryParse(value),
          _ => null,
        },
      );
}

enum KnowledgeKind { note, researchSource, researchSearch, episode }

enum ResearchArchiveKind { source, search }

class KnowledgeEntry {
  const KnowledgeEntry({
    required this.id,
    required this.projectId,
    required this.title,
    required this.content,
    required this.tags,
    required this.sourceUrl,
    required this.contentHash,
    required this.createdAt,
    required this.updatedAt,
    this.trust = 'user_or_verified',
    this.kind = KnowledgeKind.note,
    this.archiveId = '',
    this.pinned = false,
  });

  final String id;
  final String projectId;
  final String title;
  final String content;
  final Set<String> tags;
  final String sourceUrl;
  final String contentHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String trust;
  final KnowledgeKind kind;
  final String archiveId;
  final bool pinned;

  KnowledgeEntry copyWith({
    String? title,
    String? content,
    Set<String>? tags,
    String? sourceUrl,
    String? contentHash,
    DateTime? updatedAt,
    String? trust,
    KnowledgeKind? kind,
    String? archiveId,
    bool? pinned,
  }) =>
      KnowledgeEntry(
        id: id,
        projectId: projectId,
        title: title ?? this.title,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        contentHash: contentHash ?? this.contentHash,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        trust: trust ?? this.trust,
        kind: kind ?? this.kind,
        archiveId: archiveId ?? this.archiveId,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'title': title,
        'content': content,
        'tags': tags.toList()..sort(),
        'sourceUrl': sourceUrl,
        'contentHash': contentHash,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'trust': trust,
        'kind': kind.name,
        'archiveId': archiveId,
        'pinned': pinned,
      };

  factory KnowledgeEntry.fromJson(Map<String, dynamic> json) {
    final tags = stringList(json['tags']).toSet();
    final explicitKind = KnowledgeKind.values
        .where((candidate) => candidate.name == json['kind'])
        .firstOrNull;
    final inferredKind = tags.contains('research-search')
        ? KnowledgeKind.researchSearch
        : tags.contains('research') || (json['sourceUrl']?.toString().isNotEmpty ?? false)
            ? KnowledgeKind.researchSource
            : KnowledgeKind.note;
    return KnowledgeEntry(
      id: json['id']?.toString() ?? newId('knowledge'),
      projectId: json['projectId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      tags: tags,
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      contentHash: json['contentHash']?.toString() ?? '',
      createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      updatedAt: parseUtc(json['updatedAt'], fallback: DateTime.now()),
      trust: json['trust']?.toString() ?? 'user_or_verified',
      kind: explicitKind ?? inferredKind,
      archiveId: json['archiveId']?.toString() ?? '',
      pinned: json['pinned'] == true,
    );
  }
}

class ResearchArchiveRecord {
  const ResearchArchiveRecord({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.title,
    required this.query,
    required this.requestedUrl,
    required this.finalUrl,
    required this.provider,
    required this.mimeType,
    required this.contentHash,
    required this.rawContentHash,
    required this.statusCode,
    required this.responseHeaders,
    required this.redirectChain,
    required this.capturedAt,
    required this.rawObjectPath,
    required this.textObjectPath,
    required this.byteLength,
    required this.extractedCharacters,
    required this.resultCount,
    required this.knowledgeId,
    this.trust = 'untrusted_external_data',
  });

  final String id;
  final String projectId;
  final ResearchArchiveKind kind;
  final String title;
  final String query;
  final String requestedUrl;
  final String finalUrl;
  final String provider;
  final String mimeType;
  final String contentHash;
  final String rawContentHash;
  final int statusCode;
  final Map<String, String> responseHeaders;
  final List<String> redirectChain;
  final DateTime capturedAt;
  final String rawObjectPath;
  final String textObjectPath;
  final int byteLength;
  final int extractedCharacters;
  final int resultCount;
  final String knowledgeId;
  final String trust;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'kind': kind.name,
        'title': title,
        'query': query,
        'requestedUrl': requestedUrl,
        'finalUrl': finalUrl,
        'provider': provider,
        'mimeType': mimeType,
        'contentHash': contentHash,
        'rawContentHash': rawContentHash,
        'statusCode': statusCode,
        'responseHeaders': responseHeaders,
        'redirectChain': redirectChain,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'rawObjectPath': rawObjectPath,
        'textObjectPath': textObjectPath,
        'byteLength': byteLength,
        'extractedCharacters': extractedCharacters,
        'resultCount': resultCount,
        'knowledgeId': knowledgeId,
        'trust': trust,
      };

  factory ResearchArchiveRecord.fromJson(Map<String, dynamic> json) =>
      ResearchArchiveRecord(
        id: json['id']?.toString() ?? newId('archive'),
        projectId: json['projectId']?.toString() ?? '',
        kind: ResearchArchiveKind.values
                .where((candidate) => candidate.name == json['kind'])
                .firstOrNull ??
            ResearchArchiveKind.source,
        title: json['title']?.toString() ?? '',
        query: json['query']?.toString() ?? '',
        requestedUrl: json['requestedUrl']?.toString() ?? '',
        finalUrl: json['finalUrl']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        mimeType: json['mimeType']?.toString() ?? 'text/plain',
        contentHash: json['contentHash']?.toString() ?? '',
        rawContentHash: json['rawContentHash']?.toString() ?? '',
        statusCode: int.tryParse(json['statusCode']?.toString() ?? '') ?? 0,
        responseHeaders: mapValue(json['responseHeaders']).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        redirectChain: stringList(json['redirectChain']),
        capturedAt: parseUtc(json['capturedAt'], fallback: DateTime.now()),
        rawObjectPath: json['rawObjectPath']?.toString() ?? '',
        textObjectPath: json['textObjectPath']?.toString() ?? '',
        byteLength: int.tryParse(json['byteLength']?.toString() ?? '') ?? 0,
        extractedCharacters:
            int.tryParse(json['extractedCharacters']?.toString() ?? '') ?? 0,
        resultCount: int.tryParse(json['resultCount']?.toString() ?? '') ?? 0,
        knowledgeId: json['knowledgeId']?.toString() ?? '',
        trust: json['trust']?.toString() ?? 'untrusted_external_data',
      );
}

class MemoryEpisode {
  const MemoryEpisode({
    required this.id,
    required this.projectId,
    required this.runId,
    required this.request,
    required this.mode,
    required this.outcome,
    required this.summary,
    required this.failure,
    required this.lessons,
    required this.tags,
    required this.completedItems,
    required this.failedItems,
    required this.filesChanged,
    required this.evidenceIds,
    required this.evidenceHashes,
    required this.startedAt,
    required this.completedAt,
    required this.modelRequests,
    required this.toolCalls,
    required this.mutations,
    required this.repairs,
    required this.contentHash,
    required this.createdAt,
    this.pinned = false,
    this.admission = 'admitted',
    this.admissionReason = '',
    this.diagnosticOnly = false,
  });

  final String id;
  final String projectId;
  final String runId;
  final String request;
  final CommandMode mode;
  final RunState outcome;
  final String summary;
  final String failure;
  final String lessons;
  final Set<String> tags;
  final List<String> completedItems;
  final List<String> failedItems;
  final List<String> filesChanged;
  final List<String> evidenceIds;
  final List<String> evidenceHashes;
  final DateTime startedAt;
  final DateTime completedAt;
  final int modelRequests;
  final int toolCalls;
  final int mutations;
  final int repairs;
  final String contentHash;
  final DateTime createdAt;
  final bool pinned;
  final String admission;
  final String admissionReason;
  final bool diagnosticOnly;

  bool get successful => outcome == RunState.succeeded;

  MemoryEpisode copyWith({bool? pinned, String? admission, String? admissionReason, bool? diagnosticOnly}) => MemoryEpisode(
        id: id,
        projectId: projectId,
        runId: runId,
        request: request,
        mode: mode,
        outcome: outcome,
        summary: summary,
        failure: failure,
        lessons: lessons,
        tags: tags,
        completedItems: completedItems,
        failedItems: failedItems,
        filesChanged: filesChanged,
        evidenceIds: evidenceIds,
        evidenceHashes: evidenceHashes,
        startedAt: startedAt,
        completedAt: completedAt,
        modelRequests: modelRequests,
        toolCalls: toolCalls,
        mutations: mutations,
        repairs: repairs,
        contentHash: contentHash,
        createdAt: createdAt,
        pinned: pinned ?? this.pinned,
        admission: admission ?? this.admission,
        admissionReason: admissionReason ?? this.admissionReason,
        diagnosticOnly: diagnosticOnly ?? this.diagnosticOnly,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'runId': runId,
        'request': request,
        'mode': mode.name,
        'outcome': outcome.name,
        'summary': summary,
        'failure': failure,
        'lessons': lessons,
        'tags': tags.toList()..sort(),
        'completedItems': completedItems,
        'failedItems': failedItems,
        'filesChanged': filesChanged,
        'evidenceIds': evidenceIds,
        'evidenceHashes': evidenceHashes,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        'modelRequests': modelRequests,
        'toolCalls': toolCalls,
        'mutations': mutations,
        'repairs': repairs,
        'contentHash': contentHash,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'pinned': pinned,
        'admission': admission,
        'admissionReason': admissionReason,
        'diagnosticOnly': diagnosticOnly,
      };

  factory MemoryEpisode.fromJson(Map<String, dynamic> json) => MemoryEpisode(
        id: json['id']?.toString() ?? newId('episode'),
        projectId: json['projectId']?.toString() ?? '',
        runId: json['runId']?.toString() ?? '',
        request: json['request']?.toString() ?? '',
        mode: CommandMode.values
                .where((candidate) => candidate.name == json['mode'])
                .firstOrNull ??
            CommandMode.ask,
        outcome: RunState.values
                .where((candidate) => candidate.name == json['outcome'])
                .firstOrNull ??
            RunState.interrupted,
        summary: json['summary']?.toString() ?? '',
        failure: json['failure']?.toString() ?? '',
        lessons: json['lessons']?.toString() ?? '',
        tags: stringList(json['tags']).toSet(),
        completedItems: stringList(json['completedItems']),
        failedItems: stringList(json['failedItems']),
        filesChanged: stringList(json['filesChanged']),
        evidenceIds: stringList(json['evidenceIds']),
        evidenceHashes: stringList(json['evidenceHashes']),
        startedAt: parseUtc(json['startedAt'], fallback: DateTime.now()),
        completedAt: parseUtc(json['completedAt'], fallback: DateTime.now()),
        modelRequests: int.tryParse(json['modelRequests']?.toString() ?? '') ?? 0,
        toolCalls: int.tryParse(json['toolCalls']?.toString() ?? '') ?? 0,
        mutations: int.tryParse(json['mutations']?.toString() ?? '') ?? 0,
        repairs: int.tryParse(json['repairs']?.toString() ?? '') ?? 0,
        contentHash: json['contentHash']?.toString() ?? '',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        pinned: json['pinned'] == true,
        admission: json['admission']?.toString() ?? 'admitted',
        admissionReason: json['admissionReason']?.toString() ?? '',
        diagnosticOnly: json['diagnosticOnly'] == true,
      );
}

class KnowledgeSearchHit {
  const KnowledgeSearchHit({
    required this.citation,
    required this.kind,
    required this.recordId,
    required this.knowledgeId,
    required this.episodeId,
    required this.archiveId,
    required this.title,
    required this.sourceUrl,
    required this.snippet,
    required this.contentHash,
    required this.trust,
    required this.tags,
    required this.score,
    required this.lexicalScore,
    required this.semanticScore,
    required this.recencyScore,
    required this.capturedAt,
    required this.chunkIndex,
    this.freshness = 'unknown',
    this.freshnessReason = '',
  });

  final String citation;
  final KnowledgeKind kind;
  final String recordId;
  final String knowledgeId;
  final String episodeId;
  final String archiveId;
  final String title;
  final String sourceUrl;
  final String snippet;
  final String contentHash;
  final String trust;
  final Set<String> tags;
  final double score;
  final double lexicalScore;
  final double semanticScore;
  final double recencyScore;
  final DateTime capturedAt;
  final int chunkIndex;
  final String freshness;
  final String freshnessReason;

  String get marker => '[$citation]';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'citation': citation,
        'marker': marker,
        'kind': kind.name,
        'recordId': recordId,
        'knowledgeId': knowledgeId,
        'episodeId': episodeId,
        'archiveId': archiveId,
        'title': title,
        'sourceUrl': sourceUrl,
        'snippet': snippet,
        'contentHash': contentHash,
        'trust': trust,
        'tags': tags.toList()..sort(),
        'score': score,
        'lexicalScore': lexicalScore,
        'semanticScore': semanticScore,
        'recencyScore': recencyScore,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'chunkIndex': chunkIndex,
        'freshness': freshness,
        'freshnessReason': freshnessReason,
      };

  factory KnowledgeSearchHit.fromJson(Map<String, dynamic> json) =>
      KnowledgeSearchHit(
        citation: json['citation']?.toString() ?? 'K0',
        kind: KnowledgeKind.values
                .where((candidate) => candidate.name == json['kind'])
                .firstOrNull ??
            KnowledgeKind.note,
        recordId: json['recordId']?.toString() ?? '',
        knowledgeId: json['knowledgeId']?.toString() ?? '',
        episodeId: json['episodeId']?.toString() ?? '',
        archiveId: json['archiveId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        snippet: json['snippet']?.toString() ?? '',
        contentHash: json['contentHash']?.toString() ?? '',
        trust: json['trust']?.toString() ?? '',
        tags: stringList(json['tags']).toSet(),
        score: double.tryParse(json['score']?.toString() ?? '') ?? 0,
        lexicalScore:
            double.tryParse(json['lexicalScore']?.toString() ?? '') ?? 0,
        semanticScore:
            double.tryParse(json['semanticScore']?.toString() ?? '') ?? 0,
        recencyScore:
            double.tryParse(json['recencyScore']?.toString() ?? '') ?? 0,
        capturedAt: parseUtc(json['capturedAt'], fallback: DateTime.now()),
        chunkIndex: int.tryParse(json['chunkIndex']?.toString() ?? '') ?? 0,
        freshness: json['freshness']?.toString() ?? 'unknown',
        freshnessReason: json['freshnessReason']?.toString() ?? '',
      );
}

class KnowledgeRetrieval {
  const KnowledgeRetrieval({
    required this.projectId,
    required this.query,
    required this.hits,
    required this.generatedAt,
    required this.indexFingerprint,
    required this.documentsScanned,
    required this.chunksScanned,
  });

  final String projectId;
  final String query;
  final List<KnowledgeSearchHit> hits;
  final DateTime generatedAt;
  final String indexFingerprint;
  final int documentsScanned;
  final int chunksScanned;

  factory KnowledgeRetrieval.empty({
    required String projectId,
    required String query,
  }) =>
      KnowledgeRetrieval(
        projectId: projectId,
        query: query,
        hits: const <KnowledgeSearchHit>[],
        generatedAt: DateTime.now().toUtc(),
        indexFingerprint: '',
        documentsScanned: 0,
        chunksScanned: 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'query': query,
        'hits': hits.map((hit) => hit.toJson()).toList(),
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'indexFingerprint': indexFingerprint,
        'documentsScanned': documentsScanned,
        'chunksScanned': chunksScanned,
      };

  factory KnowledgeRetrieval.fromJson(Map<String, dynamic> json) =>
      KnowledgeRetrieval(
        projectId: json['projectId']?.toString() ?? '',
        query: json['query']?.toString() ?? '',
        hits: (json['hits'] is List ? json['hits'] as List : const <Object>[])
            .whereType<Map>()
            .map((item) => KnowledgeSearchHit.fromJson(mapValue(item)))
            .toList(),
        generatedAt: parseUtc(json['generatedAt'], fallback: DateTime.now()),
        indexFingerprint: json['indexFingerprint']?.toString() ?? '',
        documentsScanned:
            int.tryParse(json['documentsScanned']?.toString() ?? '') ?? 0,
        chunksScanned:
            int.tryParse(json['chunksScanned']?.toString() ?? '') ?? 0,
      );
}

class KnowledgeStats {
  const KnowledgeStats({
    required this.projectId,
    required this.notes,
    required this.researchSources,
    required this.searchSnapshots,
    required this.episodes,
    required this.pinned,
    required this.archiveBytes,
    required this.indexedChunks,
    required this.lastUpdatedAt,
  });

  final String projectId;
  final int notes;
  final int researchSources;
  final int searchSnapshots;
  final int episodes;
  final int pinned;
  final int archiveBytes;
  final int indexedChunks;
  final DateTime? lastUpdatedAt;

  int get total => notes + researchSources + searchSnapshots + episodes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'notes': notes,
        'researchSources': researchSources,
        'searchSnapshots': searchSnapshots,
        'episodes': episodes,
        'pinned': pinned,
        'archiveBytes': archiveBytes,
        'indexedChunks': indexedChunks,
        'lastUpdatedAt': lastUpdatedAt?.toUtc().toIso8601String(),
        'total': total,
      };
}


class PromptTemplateRecord {
  const PromptTemplateRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.systemPrompt,
    required this.userPrompt,
    required this.variables,
    required this.tags,
    required this.mode,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final String systemPrompt;
  final String userPrompt;
  final List<String> variables;
  final Set<String> tags;
  final CommandMode mode;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  PromptTemplateRecord copyWith({
    String? title,
    String? description,
    String? systemPrompt,
    String? userPrompt,
    List<String>? variables,
    Set<String>? tags,
    CommandMode? mode,
    int? version,
    DateTime? updatedAt,
  }) =>
      PromptTemplateRecord(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        userPrompt: userPrompt ?? this.userPrompt,
        variables: variables ?? this.variables,
        tags: tags ?? this.tags,
        mode: mode ?? this.mode,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  String renderForChat([Map<String, String> values = const <String, String>{}]) {
    String render(String input) {
      var output = input;
      for (final variable in variables) {
        output = output.replaceAll('{{$variable}}', values[variable] ?? '[$variable]');
      }
      return output.trim();
    }

    final system = render(systemPrompt);
    final user = render(userPrompt);
    if (system.isEmpty) { return user; }
    return '''Instructions for this task:
$system

Request:
$user''';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        'variables': variables,
        'tags': tags.toList()..sort(),
        'mode': mode.name,
        'version': version,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory PromptTemplateRecord.fromJson(Map<String, dynamic> json) => PromptTemplateRecord(
        id: json['id']?.toString() ?? newId('prompt'),
        title: json['title']?.toString() ?? 'Untitled prompt',
        description: json['description']?.toString() ?? '',
        systemPrompt: json['systemPrompt']?.toString() ?? '',
        userPrompt: json['userPrompt']?.toString() ?? '',
        variables: stringList(json['variables']),
        tags: stringList(json['tags']).toSet(),
        mode: CommandMode.values.where((item) => item.name == json['mode']).firstOrNull ?? CommandMode.build,
        version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        updatedAt: parseUtc(json['updatedAt'], fallback: DateTime.now()),
      );
}


enum PromptGenerationAction { generate, improve, simplify, addDetail }

enum PlanningDepth { auto, compact, detailed, exhaustive }

enum PlanUncertainty { low, medium, high }

enum PlanRisk { low, medium, high, critical }

class PromptStudioDraft {
  const PromptStudioDraft({
    required this.title,
    required this.purpose,
    required this.systemPrompt,
    required this.userPrompt,
    required this.variables,
    required this.assumptions,
    required this.clarifyingQuestions,
    required this.acceptanceCriteria,
    required this.outputExpectations,
    required this.guardrails,
    required this.stopConditions,
    required this.evaluationCases,
    required this.mode,
  });

  final String title;
  final String purpose;
  final String systemPrompt;
  final String userPrompt;
  final List<String> variables;
  final List<String> assumptions;
  final List<String> clarifyingQuestions;
  final List<String> acceptanceCriteria;
  final List<String> outputExpectations;
  final List<String> guardrails;
  final List<String> stopConditions;
  final List<String> evaluationCases;
  final CommandMode mode;

  List<String> validate() {
    final errors = <String>[];
    if (title.trim().isEmpty) { errors.add('The generated prompt needs a title.'); }
    if (purpose.trim().length < 8) { errors.add('The generated prompt needs a clear purpose.'); }
    if (systemPrompt.trim().length < 20) { errors.add('The generated system instructions are too short.'); }
    if (userPrompt.trim().length < 8) { errors.add('The generated user prompt is too short.'); }
    if (acceptanceCriteria.isEmpty) { errors.add('At least one acceptance criterion is required.'); }
    if (acceptanceCriteria.any((item) => item.trim().length < 8)) {
      errors.add('Acceptance criteria must be concrete and non-empty.');
    }
    return errors;
  }

  PromptStudioDraft copyWith({
    String? title,
    String? purpose,
    String? systemPrompt,
    String? userPrompt,
    List<String>? variables,
    List<String>? assumptions,
    List<String>? clarifyingQuestions,
    List<String>? acceptanceCriteria,
    List<String>? outputExpectations,
    List<String>? guardrails,
    List<String>? stopConditions,
    List<String>? evaluationCases,
    CommandMode? mode,
  }) =>
      PromptStudioDraft(
        title: title ?? this.title,
        purpose: purpose ?? this.purpose,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        userPrompt: userPrompt ?? this.userPrompt,
        variables: variables ?? this.variables,
        assumptions: assumptions ?? this.assumptions,
        clarifyingQuestions: clarifyingQuestions ?? this.clarifyingQuestions,
        acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
        outputExpectations: outputExpectations ?? this.outputExpectations,
        guardrails: guardrails ?? this.guardrails,
        stopConditions: stopConditions ?? this.stopConditions,
        evaluationCases: evaluationCases ?? this.evaluationCases,
        mode: mode ?? this.mode,
      );

  String renderForChat() {
    final sections = <String>[
      if (systemPrompt.trim().isNotEmpty) systemPrompt.trim(),
      if (assumptions.isNotEmpty) 'Assumptions:\n${assumptions.map((item) => '- $item').join('\n')}',
      if (acceptanceCriteria.isNotEmpty)
        'Acceptance criteria:\n${acceptanceCriteria.map((item) => '- $item').join('\n')}',
      if (outputExpectations.isNotEmpty)
        'Expected outputs:\n${outputExpectations.map((item) => '- $item').join('\n')}',
      if (guardrails.isNotEmpty) 'Guardrails:\n${guardrails.map((item) => '- $item').join('\n')}',
      if (stopConditions.isNotEmpty)
        'Stop conditions:\n${stopConditions.map((item) => '- $item').join('\n')}',
      'Task:\n${userPrompt.trim()}',
    ];
    return sections.join('\n\n');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'purpose': purpose,
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        'variables': variables,
        'assumptions': assumptions,
        'clarifyingQuestions': clarifyingQuestions,
        'acceptanceCriteria': acceptanceCriteria,
        'outputExpectations': outputExpectations,
        'guardrails': guardrails,
        'stopConditions': stopConditions,
        'evaluationCases': evaluationCases,
        'mode': mode.name,
      };

  factory PromptStudioDraft.fromJson(Map<String, dynamic> json) =>
      PromptStudioDraft(
        title: json['title']?.toString() ?? 'Generated prompt',
        purpose: json['purpose']?.toString() ?? '',
        systemPrompt: json['systemPrompt']?.toString() ?? '',
        userPrompt: json['userPrompt']?.toString() ?? '',
        variables: stringList(json['variables']),
        assumptions: stringList(json['assumptions']),
        clarifyingQuestions: stringList(json['clarifyingQuestions']),
        acceptanceCriteria: stringList(json['acceptanceCriteria']),
        outputExpectations: stringList(json['outputExpectations']),
        guardrails: stringList(json['guardrails']),
        stopConditions: stringList(json['stopConditions']),
        evaluationCases: stringList(json['evaluationCases']),
        mode: CommandMode.values
                .where((item) => item.name == json['mode']?.toString())
                .firstOrNull ??
            CommandMode.build,
      );
}

class PromptVersionRecord {
  const PromptVersionRecord({
    required this.id,
    required this.promptId,
    required this.versionNumber,
    required this.sourceGoal,
    required this.action,
    required this.draft,
    required this.model,
    required this.contentHash,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String promptId;
  final int versionNumber;
  final String sourceGoal;
  final PromptGenerationAction action;
  final PromptStudioDraft draft;
  final ModelIdentity model;
  final String contentHash;
  final String createdBy;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'promptId': promptId,
        'versionNumber': versionNumber,
        'sourceGoal': sourceGoal,
        'action': action.name,
        'draft': draft.toJson(),
        'model': model.toJson(),
        'contentHash': contentHash,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory PromptVersionRecord.fromJson(Map<String, dynamic> json) =>
      PromptVersionRecord(
        id: json['id']?.toString() ?? newId('prompt_version'),
        promptId: json['promptId']?.toString() ?? '',
        versionNumber:
            int.tryParse(json['versionNumber']?.toString() ?? '') ?? 1,
        sourceGoal: json['sourceGoal']?.toString() ?? '',
        action: PromptGenerationAction.values
                .where((item) => item.name == json['action']?.toString())
                .firstOrNull ??
            PromptGenerationAction.generate,
        draft: PromptStudioDraft.fromJson(mapValue(json['draft'])),
        model: ModelIdentity.fromJson(mapValue(json['model'])),
        contentHash: json['contentHash']?.toString() ?? '',
        createdBy: json['createdBy']?.toString() ?? 'user',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class PlanTaskRecord {
  const PlanTaskRecord({
    required this.id,
    required this.phase,
    required this.parentId,
    required this.title,
    required this.objective,
    required this.instructions,
    required this.dependencies,
    required this.acceptanceCriteria,
    required this.verificationSteps,
    required this.expectedArtifacts,
    required this.allowedTools,
    required this.complexity,
    required this.effortPoints,
    required this.uncertainty,
    required this.risk,
    required this.estimateConfidence,
    required this.expectedModelTurns,
    required this.expectedToolCalls,
    required this.maxAttempts,
    required this.enabled,
    required this.manual,
  });

  final String id;
  final String phase;
  final String? parentId;
  final String title;
  final String objective;
  final String instructions;
  final Set<String> dependencies;
  final List<String> acceptanceCriteria;
  final List<String> verificationSteps;
  final List<String> expectedArtifacts;
  final Set<String> allowedTools;
  final int complexity;
  final int effortPoints;
  final PlanUncertainty uncertainty;
  final PlanRisk risk;
  final double estimateConfidence;
  final int expectedModelTurns;
  final int expectedToolCalls;
  final int maxAttempts;
  final bool enabled;
  final bool manual;

  PlanTaskRecord copyWith({
    String? id,
    String? phase,
    String? parentId,
    bool clearParentId = false,
    String? title,
    String? objective,
    String? instructions,
    Set<String>? dependencies,
    List<String>? acceptanceCriteria,
    List<String>? verificationSteps,
    List<String>? expectedArtifacts,
    Set<String>? allowedTools,
    int? complexity,
    int? effortPoints,
    PlanUncertainty? uncertainty,
    PlanRisk? risk,
    double? estimateConfidence,
    int? expectedModelTurns,
    int? expectedToolCalls,
    int? maxAttempts,
    bool? enabled,
    bool? manual,
  }) =>
      PlanTaskRecord(
        id: id ?? this.id,
        phase: phase ?? this.phase,
        parentId: clearParentId ? null : (parentId ?? this.parentId),
        title: title ?? this.title,
        objective: objective ?? this.objective,
        instructions: instructions ?? this.instructions,
        dependencies: dependencies ?? this.dependencies,
        acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
        verificationSteps: verificationSteps ?? this.verificationSteps,
        expectedArtifacts: expectedArtifacts ?? this.expectedArtifacts,
        allowedTools: allowedTools ?? this.allowedTools,
        complexity: complexity ?? this.complexity,
        effortPoints: effortPoints ?? this.effortPoints,
        uncertainty: uncertainty ?? this.uncertainty,
        risk: risk ?? this.risk,
        estimateConfidence: estimateConfidence ?? this.estimateConfidence,
        expectedModelTurns: expectedModelTurns ?? this.expectedModelTurns,
        expectedToolCalls: expectedToolCalls ?? this.expectedToolCalls,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        enabled: enabled ?? this.enabled,
        manual: manual ?? this.manual,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'phase': phase,
        'parentId': parentId,
        'title': title,
        'objective': objective,
        'instructions': instructions,
        'dependencies': dependencies.toList()..sort(),
        'acceptanceCriteria': acceptanceCriteria,
        'verificationSteps': verificationSteps,
        'expectedArtifacts': expectedArtifacts,
        'allowedTools': allowedTools.toList()..sort(),
        'complexity': complexity,
        'effortPoints': effortPoints,
        'uncertainty': uncertainty.name,
        'risk': risk.name,
        'estimateConfidence': estimateConfidence,
        'expectedModelTurns': expectedModelTurns,
        'expectedToolCalls': expectedToolCalls,
        'maxAttempts': maxAttempts,
        'enabled': enabled,
        'manual': manual,
      };

  factory PlanTaskRecord.fromJson(Map<String, dynamic> json) {
    final parentId = json['parentId']?.toString().trim() ?? '';
    return PlanTaskRecord(
        id: json['id']?.toString() ?? newId('task'),
        phase: json['phase']?.toString() ?? 'Implementation',
        parentId: parentId.isEmpty ? null : parentId,
        title: json['title']?.toString() ?? 'Task',
        objective: json['objective']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        dependencies: stringList(json['dependencies']).toSet(),
        acceptanceCriteria: stringList(json['acceptanceCriteria']),
        verificationSteps: stringList(json['verificationSteps']),
        expectedArtifacts: stringList(json['expectedArtifacts']),
        allowedTools: stringList(json['allowedTools']).toSet(),
        complexity: (int.tryParse(json['complexity']?.toString() ?? '') ?? 3)
            .clamp(1, 10)
            .toInt(),
        effortPoints:
            int.tryParse(json['effortPoints']?.toString() ?? '') ?? 3,
        uncertainty: PlanUncertainty.values
                .where((item) => item.name == json['uncertainty']?.toString())
                .firstOrNull ??
            PlanUncertainty.medium,
        risk: PlanRisk.values
                .where((item) => item.name == json['risk']?.toString())
                .firstOrNull ??
            PlanRisk.medium,
        estimateConfidence:
            (double.tryParse(json['estimateConfidence']?.toString() ?? '') ??
                    0.6)
                .clamp(0.0, 1.0)
                .toDouble(),
        expectedModelTurns:
            (int.tryParse(json['expectedModelTurns']?.toString() ?? '') ?? 2)
                .clamp(1, 20)
                .toInt(),
        expectedToolCalls:
            (int.tryParse(json['expectedToolCalls']?.toString() ?? '') ?? 4)
                .clamp(0, 80)
                .toInt(),
        maxAttempts:
            (int.tryParse(json['maxAttempts']?.toString() ?? '') ?? 2)
                .clamp(1, 3)
                .toInt(),
        enabled: json['enabled'] != false,
        manual: json['manual'] == true,
      );
  }
}

class TaskPlanRecord {
  const TaskPlanRecord({
    required this.id,
    required this.promptId,
    required this.promptVersionId,
    required this.projectId,
    required this.revision,
    required this.previousPlanId,
    required this.title,
    required this.rationale,
    required this.depth,
    required this.maxLeafTasks,
    required this.tasks,
    required this.model,
    required this.contentHash,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String promptId;
  final String promptVersionId;
  final String projectId;
  final int revision;
  final String? previousPlanId;
  final String title;
  final String rationale;
  final PlanningDepth depth;
  final int maxLeafTasks;
  final List<PlanTaskRecord> tasks;
  final ModelIdentity model;
  final String contentHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<PlanTaskRecord> get enabledTasks =>
      tasks.where((item) => item.enabled).toList(growable: false);

  int get totalEffortPoints =>
      enabledTasks.fold<int>(0, (total, item) => total + item.effortPoints);

  int get highRiskTasks => enabledTasks
      .where((item) =>
          item.risk == PlanRisk.high || item.risk == PlanRisk.critical)
      .length;

  int get maxComplexity => enabledTasks.isEmpty
      ? 1
      : enabledTasks.map((item) => item.complexity).reduce(max);

  List<String> validate() {
    final errors = <String>[];
    if (title.trim().isEmpty) { errors.add('The task plan needs a title.'); }
    if (tasks.isEmpty) { errors.add('The task plan must contain at least one task.'); }
    if (tasks.length > maxLeafTasks || tasks.length > 100) {
      errors.add('The task plan exceeds its configured leaf-task limit.');
    }
    final ids = tasks.map((item) => item.id).toList(growable: false);
    if (ids.toSet().length != ids.length) { errors.add('Task IDs must be unique.'); }
    final byId = <String, PlanTaskRecord>{for (final item in tasks) item.id: item};
    for (final task in tasks) {
      if (task.title.trim().isEmpty || task.instructions.trim().isEmpty) {
        errors.add('${task.id} requires a title and instructions.');
      }
      if (task.acceptanceCriteria.isEmpty && !task.manual) {
        errors.add('${task.id} needs measurable acceptance criteria.');
      }
      if (task.verificationSteps.isEmpty && !task.manual) {
        errors.add('${task.id} needs at least one verification step.');
      }
      final parentId = task.parentId;
      if (parentId != null) {
        if (parentId == task.id) {
          errors.add('${task.id} cannot be its own parent.');
        } else if (!byId.containsKey(parentId)) {
          errors.add('${task.id} references missing parent $parentId.');
        }
      }
      for (final dependency in task.dependencies) {
        final target = byId[dependency];
        if (target == null) { errors.add('${task.id} references missing dependency $dependency.'); }
        if (dependency == task.id) { errors.add('${task.id} cannot depend on itself.'); }
        if (task.enabled && target != null && !target.enabled) {
          errors.add('${task.id} depends on disabled task $dependency.');
        }
      }
    }
    final parentVisited = <String>{};
    final parentActive = <String>{};
    bool parentCycle(String id) {
      if (parentActive.contains(id)) { return true; }
      if (parentVisited.contains(id)) { return false; }
      parentActive.add(id);
      final parentId = byId[id]?.parentId;
      if (parentId != null && byId.containsKey(parentId) && parentCycle(parentId)) {
        return true;
      }
      parentActive.remove(id);
      parentVisited.add(id);
      return false;
    }
    if (tasks.any((item) => parentCycle(item.id))) {
      errors.add('The task plan contains a parent hierarchy cycle.');
    }
    final visited = <String>{};
    final active = <String>{};
    bool cycle(String id) {
      if (active.contains(id)) { return true; }
      if (visited.contains(id)) { return false; }
      active.add(id);
      for (final dependency in byId[id]?.dependencies ?? const <String>{}) {
        if (cycle(dependency)) { return true; }
      }
      active.remove(id);
      visited.add(id);
      return false;
    }
    if (tasks.any((item) => cycle(item.id))) {
      errors.add('The task plan contains a dependency cycle.');
    }
    return errors;
  }

  TaskPlanRecord copyWith({
    String? id,
    int? revision,
    String? previousPlanId,
    bool clearPreviousPlanId = false,
    String? title,
    String? rationale,
    PlanningDepth? depth,
    int? maxLeafTasks,
    List<PlanTaskRecord>? tasks,
    String? contentHash,
    DateTime? updatedAt,
  }) =>
      TaskPlanRecord(
        id: id ?? this.id,
        promptId: promptId,
        promptVersionId: promptVersionId,
        projectId: projectId,
        revision: revision ?? this.revision,
        previousPlanId: clearPreviousPlanId
            ? null
            : (previousPlanId ?? this.previousPlanId),
        title: title ?? this.title,
        rationale: rationale ?? this.rationale,
        depth: depth ?? this.depth,
        maxLeafTasks: maxLeafTasks ?? this.maxLeafTasks,
        tasks: tasks ?? this.tasks,
        model: model,
        contentHash: contentHash ?? this.contentHash,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'promptId': promptId,
        'promptVersionId': promptVersionId,
        'projectId': projectId,
        'revision': revision,
        'previousPlanId': previousPlanId,
        'title': title,
        'rationale': rationale,
        'depth': depth.name,
        'maxLeafTasks': maxLeafTasks,
        'tasks': tasks.map((item) => item.toJson()).toList(),
        'model': model.toJson(),
        'contentHash': contentHash,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory TaskPlanRecord.fromJson(Map<String, dynamic> json) {
    final createdAt = parseUtc(json['createdAt'], fallback: DateTime.now());
    final previousPlanId = json['previousPlanId']?.toString().trim() ?? '';
    return TaskPlanRecord(
        id: json['id']?.toString() ?? newId('task_plan'),
        promptId: json['promptId']?.toString() ?? '',
        promptVersionId: json['promptVersionId']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        revision: int.tryParse(json['revision']?.toString() ?? '') ?? 1,
        previousPlanId: previousPlanId.isEmpty ? null : previousPlanId,
        title: json['title']?.toString() ?? 'Generated task plan',
        rationale: json['rationale']?.toString() ?? '',
        depth: PlanningDepth.values
                .where((item) => item.name == json['depth']?.toString())
                .firstOrNull ??
            PlanningDepth.auto,
        maxLeafTasks:
            (int.tryParse(json['maxLeafTasks']?.toString() ?? '') ?? 25)
                .clamp(1, 100)
                .toInt(),
        tasks: (json['tasks'] is List
                ? json['tasks'] as List
                : const <Object>[])
            .whereType<Map>()
            .map((item) => PlanTaskRecord.fromJson(mapValue(item)))
            .toList(),
        model: ModelIdentity.fromJson(mapValue(json['model'])),
        contentHash: json['contentHash']?.toString() ?? '',
        createdAt: createdAt,
        updatedAt: parseUtc(json['updatedAt'], fallback: createdAt),
      );
  }
}

enum DiagnosticStatus { passed, warning, failed, skipped }

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.message,
    this.command = '',
    this.output = '',
    this.exitCode,
    this.durationMs = 0,
  });

  final String id;
  final String title;
  final DiagnosticStatus status;
  final String message;
  final String command;
  final String output;
  final int? exitCode;
  final int durationMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'status': status.name,
        'message': message,
        'command': command,
        'output': output,
        'exitCode': exitCode,
        'durationMs': durationMs,
      };
}

class ProjectDiagnosticReport {
  const ProjectDiagnosticReport({
    required this.projectId,
    required this.projectType,
    required this.testCommand,
    required this.buildCommand,
    required this.runCommand,
    required this.checks,
    required this.generatedAt,
    this.analyzeCommand = '',
  });

  final String projectId;
  final String projectType;
  final String analyzeCommand;
  final String testCommand;
  final String buildCommand;
  final String runCommand;
  final List<DiagnosticCheck> checks;
  final DateTime generatedAt;

  bool get hasBlockingFailure => checks.any((check) => check.status == DiagnosticStatus.failed);
  int get passed => checks.where((check) => check.status == DiagnosticStatus.passed).length;
  int get warnings => checks.where((check) => check.status == DiagnosticStatus.warning).length;
  int get failed => checks.where((check) => check.status == DiagnosticStatus.failed).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'projectType': projectType,
        'analyzeCommand': analyzeCommand,
        'testCommand': testCommand,
        'buildCommand': buildCommand,
        'runCommand': runCommand,
        'checks': checks.map((check) => check.toJson()).toList(),
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'summary': <String, int>{
          'passed': passed,
          'warnings': warnings,
          'failed': failed,
        },
      };
}

class ProjectProcessStatus {
  const ProjectProcessStatus({
    required this.projectId,
    required this.processId,
    required this.label,
    required this.command,
    required this.pid,
    required this.running,
    required this.startedAt,
    required this.outputTail,
    required this.logFileName,
    this.exitCode,
    this.completedAt,
  });

  final String projectId;
  final String processId;
  final String label;
  final String command;
  final int pid;
  final bool running;
  final int? exitCode;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String outputTail;
  final String logFileName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'processId': processId,
        'label': label,
        'command': command,
        'pid': pid,
        'running': running,
        'exitCode': exitCode,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'outputTail': outputTail,
        'logFileName': logFileName,
      };
}

class AgentAction {
  const AgentAction({
    required this.kind,
    this.tool,
    this.arguments = const <String, dynamic>{},
    this.reason = '',
    this.summary = '',
  });

  final String kind;
  final String? tool;
  final Map<String, dynamic> arguments;
  final String reason;
  final String summary;

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    final actionObject = mapValue(json['action']);
    final toolObject = mapValue(json['tool']);
    final calls = json['tool_calls'] is List
        ? json['tool_calls'] as List
        : json['toolCalls'] is List
            ? json['toolCalls'] as List
            : const <Object>[];
    final firstCall = calls.whereType<Map>().firstOrNull;
    final toolCall = mapValue(
      firstCall ??
          json['toolCall'] ??
          json['tool_call'] ??
          json['functionCall'] ??
          json['function_call'],
    );
    final function = mapValue(json['function']);
    final nestedFunction = mapValue(toolCall['function']);
    final actionName = _firstText(<Object?>[
      actionObject['name'],
      actionObject['action'],
      actionObject['kind'],
      actionObject['type'],
    ]);
    final normalizedActionName = _normalizeKind(actionName);
    final actionNameIsTerminal = const <String>{'complete', 'fail'}
        .contains(normalizedActionName);
    final rawTool = _firstText(<Object?>[
      json['tool'],
      json['toolName'],
      json['tool_name'],
      json['functionName'],
      json['function_name'],
      json['command'],
      json['name'],
      toolObject['name'],
      toolObject['tool'],
      actionObject['tool'],
      actionNameIsTerminal ? null : actionObject['name'],
      toolCall['name'],
      function['name'],
      nestedFunction['name'],
    ]);
    final rawKind = _firstText(<Object?>[
      json['action'] is String ? json['action'] : null,
      json['kind'],
      json['type'],
      json['status'],
      json['operation'],
      json['act'],
      actionObject['action'],
      actionObject['kind'],
      actionObject['type'],
      actionNameIsTerminal ? actionObject['name'] : null,
      toolCall['type'],
    ]);
    final message = json['message'];
    final resultObject = mapValue(json['result']);
    final outputObject = mapValue(json['output']);
    final finalObject = mapValue(
      json['final_answer'] ?? json['finalAnswer'] ?? json['final'],
    );
    final summary = _firstText(<Object?>[
      json['summary'],
      json['answer'],
      json['final_answer'],
      json['finalAnswer'],
      json['final_response'],
      json['finalResponse'],
      json['output_text'],
      json['outputText'],
      json['response'],
      json['result'],
      json['final'],
      json['content'],
      json['text'],
      json['description'],
      json['details'] is String ? json['details'] : null,
      json['error'],
      message is String ? message : null,
      mapValue(message)['content'],
      mapValue(message)['text'],
      resultObject['summary'],
      resultObject['answer'],
      resultObject['content'],
      resultObject['text'],
      outputObject['summary'],
      outputObject['answer'],
      outputObject['content'],
      outputObject['text'],
      finalObject['summary'],
      finalObject['answer'],
      finalObject['content'],
      finalObject['text'],
      actionObject['summary'],
      actionObject['answer'],
      actionObject['final_answer'],
      actionObject['finalAnswer'],
      actionObject['result'],
      actionObject['content'],
      actionObject['text'],
    ]);
    var kind = _normalizeKind(rawKind);
    if (kind.isEmpty && normalizedActionName.isNotEmpty) {
      kind = normalizedActionName;
    }
    if (kind.isEmpty && rawTool.isNotEmpty) {
      kind = 'tool';
    } else if (kind.isEmpty &&
        json['error']?.toString().trim().isNotEmpty == true) {
      kind = 'fail';
    } else if (kind.isEmpty && summary.isNotEmpty) {
      kind = 'complete';
    }
    var arguments = _arguments(<Object?>[
      json['arguments'],
      json['args'],
      json['parameters'],
      json['params'],
      json['input'],
      json['toolInput'],
      json['tool_input'],
      json['actionInput'],
      json['action_input'],
      json['payload'],
      toolObject['arguments'],
      toolObject['args'],
      toolObject['parameters'],
      toolObject['params'],
      toolObject['input'],
      toolObject['toolInput'],
      toolObject['tool_input'],
      actionObject['arguments'],
      actionObject['args'],
      actionObject['parameters'],
      actionObject['params'],
      actionObject['input'],
      actionObject['toolInput'],
      actionObject['tool_input'],
      actionObject['actionInput'],
      actionObject['action_input'],
      toolCall['arguments'],
      toolCall['args'],
      toolCall['parameters'],
      toolCall['input'],
      function['arguments'],
      function['parameters'],
      nestedFunction['arguments'],
      nestedFunction['parameters'],
    ]);
    final commandValue = <Object?>[
      json['command'],
      toolObject['command'],
      actionObject['command'],
      toolCall['command'],
    ].where((value) => value is List || value is String).firstOrNull;
    if (commandValue is List) {
      arguments.putIfAbsent(
        'command',
        () => commandValue.map((item) => '$item').toList(growable: false),
      );
    } else if (commandValue is String && commandValue.trim().isNotEmpty) {
      arguments.putIfAbsent('command', () => commandValue.trim());
    }
    if (kind == 'tool' && arguments.isEmpty) {
      arguments = Map<String, dynamic>.from(json)
        ..removeWhere((key, _) => const <String>{
              'action',
              'kind',
              'type',
              'status',
              'operation',
              'act',
              'tool',
              'toolName',
              'tool_name',
              'functionName',
              'function_name',
              'command',
              'name',
              'arguments',
              'args',
              'parameters',
              'params',
              'input',
              'reason',
              'rationale',
              'explanation',
              'summary',
              'answer',
              'final_answer',
              'finalAnswer',
              'final_response',
              'finalResponse',
              'output_text',
              'outputText',
              'response',
              'result',
              'final',
              'content',
              'text',
              'error',
              'message',
              'tool_calls',
              'toolCalls',
              'toolCall',
              'tool_call',
              'functionCall',
              'function_call',
              'function',
            }.contains(key));
    }
    return AgentAction(
      kind: kind,
      tool: rawTool.isEmpty ? null : rawTool,
      arguments: arguments,
      reason: _firstText(<Object?>[
        json['reason'],
        json['rationale'],
        json['explanation'],
        json['thought'],
        actionObject['reason'],
        actionObject['rationale'],
      ]),
      summary: summary,
    );
  }

  static String _normalizeKind(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (const <String>{
      'tool',
      'tool_call',
      'toolcall',
      'call_tool',
      'use_tool',
      'execute_tool',
      'invoke_tool',
      'function',
      'function_call',
      'functioncall',
      'call_function',
      'invoke_function',
      'call',
    }.contains(normalized)) {
      return 'tool';
    }
    if (const <String>{
      'complete',
      'completed',
      'completion',
      'final',
      'final_answer',
      'final_response',
      'answer',
      'respond',
      'response',
      'reply',
      'message',
      'output',
      'result',
      'report',
      'conclusion',
      'finalize',
      'finalise',
      'respond_to_user',
      'done',
      'finish',
      'finished',
      'success',
      'succeeded',
      'ok',
    }.contains(normalized)) {
      return 'complete';
    }
    if (const <String>{
      'fail',
      'failed',
      'failure',
      'error',
      'stop',
      'blocked',
      'abort',
      'aborted',
      'unable',
      'cannot_complete',
    }.contains(normalized)) {
      return 'fail';
    }
    return normalized;
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num || value is bool) {
        return value.toString();
      }
    }
    return '';
  }

  static Map<String, dynamic> _arguments(Iterable<Object?> values) {
    for (final value in values) {
      if (value is Map) {
        return mapValue(value);
      }
      if (value is String && value.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) {
            return mapValue(decoded);
          }
        } catch (_) {
          // Continue to the next compatible argument representation.
        }
      }
    }
    return <String, dynamic>{};
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
