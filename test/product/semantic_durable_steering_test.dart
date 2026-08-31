import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/run_live_signals.dart';
import 'package:kristin_local_agent/product/run_steering.dart';
import 'package:kristin_local_agent/product/run_steering_record.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';

class _MemoryRepository implements EntityRepository<RunSteeringRecord> {
  final Map<String, RunSteeringRecord> values = <String, RunSteeringRecord>{};
  @override
  Future<List<RunSteeringRecord>> all() async => values.values.toList();
  @override
  Future<RunSteeringRecord?> get(String id) async => values[id];
  @override
  Future<void> put(RunSteeringRecord item) async {
    values[item.id] = item;
  }

  @override
  Future<void> putAll(Iterable<RunSteeringRecord> items) async {
    for (final item in items) {
      values[item.id] = item;
    }
  }

  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }

  @override
  Future<void> removeWhere(
      bool Function(RunSteeringRecord item) predicate) async {
    values.removeWhere((_, value) => predicate(value));
  }

  @override
  Future<void> replaceAll(Iterable<RunSteeringRecord> items) async {
    values
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.id, item)));
  }
}

void main() {
  test('constraint steering is semantic, durable, and authority-neutral',
      () async {
    final repository = _MemoryRepository();
    final service = RunSteeringService(
      liveSignals: LiveRunSignalBus(),
      repository: repository,
    );
    final instruction = await service.queue('run-1', "don't use Firebase");
    expect(instruction.patch.requiresReplan, isTrue);
    expect(instruction.patch.grantsAuthority, isFalse);
    expect(instruction.patch.addedHardConstraints.single.statement,
        contains('Firebase'));
    expect(await service.takePending('run-1'), isEmpty);
    expect((await service.pendingReplan('run-1')).single.id, instruction.id);
    expect(repository.values[instruction.id]!.state,
        RunSteeringRecordState.pending);
  });

  test('scope expansion requires a reviewed replan instead of raw injection',
      () async {
    final service = RunSteeringService(
      liveSignals: LiveRunSignalBus(),
      repository: _MemoryRepository(),
    );
    final instruction =
        await service.queue('run-1', 'also build an admin dashboard');
    expect(instruction.patch.requiresReplan, isTrue);
    expect(instruction.patch.scopeDirectives,
        contains('also build an admin dashboard'));
    expect((await service.pendingReplan('run-1')).single.id, instruction.id);
  });

  test('patch application preserves semantic sections', () {
    final source = TaskSpecification(
      id: 'spec-1',
      originalRequest: 'build the app',
      objective: 'Build the app',
    );
    final patch = TaskSpecificationPatch.fromUserSteering('prefer a simple UI');
    final revised = patch.applyTo(source);
    expect(revised.preferences.single.statement, contains('simple UI'));
    expect(revised.contextRefs.single, startsWith('steering:'));
  });
}
