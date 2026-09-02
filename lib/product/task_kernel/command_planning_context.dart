import '../domain.dart';
import 'task_specification.dart';
import 'universal_task_plan.dart';

/// Durable canonical planning context for a prepared command.
///
/// PreparedCommand intentionally carries the executable projection only. A
/// steering replan also needs the semantic specification and canonical plan
/// that produced it, so they are persisted separately under the command id.
class CommandPlanningContextRecord {
  const CommandPlanningContextRecord({
    required this.commandId,
    required this.projectId,
    required this.specification,
    required this.family,
    required this.route,
    required this.routingRationale,
    required this.canonicalPlan,
    required this.consumedCoordinatorCapabilities,
    required this.createdAt,
    required this.updatedAt,
  });

  final String commandId;
  final String projectId;
  final TaskSpecification specification;
  final TaskFamily family;
  final PlanningRoute route;
  final String routingRationale;
  final UniversalTaskPlan canonicalPlan;
  final Set<String> consumedCoordinatorCapabilities;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get id => commandId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'commandId': commandId,
        'projectId': projectId,
        'specification': specification.toJson(),
        'family': family.name,
        'route': route.name,
        'routingRationale': routingRationale,
        'canonicalPlan': canonicalPlan.toJson(),
        'consumedCoordinatorCapabilities':
            consumedCoordinatorCapabilities.toList()..sort(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory CommandPlanningContextRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return CommandPlanningContextRecord(
      commandId: json['commandId']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      specification:
          TaskSpecification.fromJson(mapValue(json['specification'])),
      family: TaskFamily.values
              .where((value) => value.name == json['family']?.toString())
              .firstOrNull ??
          TaskFamily.software,
      route: PlanningRoute.values
              .where((value) => value.name == json['route']?.toString())
              .firstOrNull ??
          PlanningRoute.graph,
      routingRationale: json['routingRationale']?.toString() ?? '',
      canonicalPlan:
          UniversalTaskPlan.fromJson(mapValue(json['canonicalPlan'])),
      consumedCoordinatorCapabilities:
          stringList(json['consumedCoordinatorCapabilities']).toSet(),
      createdAt: parseUtc(json['createdAt'], fallback: now),
      updatedAt: parseUtc(json['updatedAt'], fallback: now),
    );
  }
}
