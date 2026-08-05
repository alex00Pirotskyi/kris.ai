import 'p2_automation_host_operations.dart';
import 'p2_effect_boundary.dart';
import 'p2_p1_authority_adapter.dart';

/// Mutable product-runtime binding selected by the desktop control plane.
///
/// There is deliberately no synthetic default. A host operation attempted
/// before an actual run/task has activated Owner Mode fails closed.
final class P2ProductBindingContext implements P2HostBindingProvider {
  P2ProductBindingContext({
    this.actorId = 'desktop_host',
    this.accessProfileId = 'owner',
  });

  final String actorId;
  final String accessProfileId;
  String? _runId;
  String? _taskId;
  int _generation = 0;

  bool get active => _runId != null && _taskId != null;
  int get generation => _generation;
  String? get runId => _runId;
  String? get taskId => _taskId;

  void activate({required String runId, required String taskId}) {
    final run = runId.trim();
    final task = taskId.trim();
    if (run.isEmpty || task.isEmpty) {
      throw StateError('p2_product_binding_invalid');
    }
    if (!const <String>{
      'owner',
      'owner_unattended',
    }.contains(accessProfileId)) {
      throw StateError('p2_product_binding_profile_invalid');
    }
    _runId = run;
    _taskId = task;
    _generation += 1;
  }

  void clear({required String runId, required String taskId}) {
    if (_runId != runId || _taskId != taskId) {
      throw StateError('p2_product_binding_clear_mismatch');
    }
    _runId = null;
    _taskId = null;
    _generation += 1;
  }

  @override
  P2EffectBinding bindingFor(String operation) {
    final run = _runId;
    final task = _taskId;
    if (run == null || task == null) {
      throw StateError('p2_product_binding_inactive');
    }
    return P2P1OperationRegistry.binding(
      runId: run,
      taskId: task,
      actorId: actorId,
      accessProfileId: accessProfileId,
      operation: operation,
    );
  }

  Map<String, Object?> get provenance => <String, Object?>{
        'implementation': 'P2ProductBindingContext',
        'active': active,
        'runId': _runId,
        'taskId': _taskId,
        'actorId': actorId,
        'accessProfileId': accessProfileId,
        'generation': _generation,
        'syntheticDefault': false,
      };
}
