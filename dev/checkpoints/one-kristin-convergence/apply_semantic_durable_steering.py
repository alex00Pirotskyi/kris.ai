#!/usr/bin/env python3
"""Apply durable, authority-neutral TaskSpecificationPatch steering.

This local source transformer turns in-flight steering from an in-memory prose
queue into durable semantic patches. Constraint/preference/criterion patches
can apply at the next safe model boundary. Scope-expanding patches are marked
as requiring a replan and fail closed until a continuation-run reconciliation
path is available.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def git_head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


RECORD_SOURCE = r'''import 'domain.dart';
import 'task_kernel/task_specification.dart';

enum RunSteeringRecordState { pending, applied, cleared }

class RunSteeringRecord {
  const RunSteeringRecord({
    required this.id,
    required this.runId,
    required this.text,
    required this.patch,
    required this.state,
    required this.createdAt,
    this.workItemId,
    this.appliedAt,
  });

  final String id;
  final String runId;
  final String text;
  final TaskSpecificationPatch patch;
  final RunSteeringRecordState state;
  final DateTime createdAt;
  final String? workItemId;
  final DateTime? appliedAt;

  RunSteeringRecord copyWith({
    RunSteeringRecordState? state,
    String? workItemId,
    DateTime? appliedAt,
  }) =>
      RunSteeringRecord(
        id: id,
        runId: runId,
        text: text,
        patch: patch,
        state: state ?? this.state,
        createdAt: createdAt,
        workItemId: workItemId ?? this.workItemId,
        appliedAt: appliedAt ?? this.appliedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'runId': runId,
        'text': text,
        'patch': patch.toJson(),
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        if (workItemId != null) 'workItemId': workItemId,
        if (appliedAt != null) 'appliedAt': appliedAt!.toIso8601String(),
      };

  factory RunSteeringRecord.fromJson(Map<String, dynamic> json) =>
      RunSteeringRecord(
        id: json['id']?.toString() ?? newId('steer'),
        runId: json['runId']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        patch: TaskSpecificationPatch.fromJson(mapValue(json['patch'])),
        state: RunSteeringRecordState.values
                .where((value) => value.name == json['state']?.toString())
                .firstOrNull ??
            RunSteeringRecordState.pending,
        createdAt: _date(json['createdAt']) ?? DateTime.now().toUtc(),
        workItemId: _nullable(json['workItemId']),
        appliedAt: _date(json['appliedAt']),
      );
}

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toUtc();

String? _nullable(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
'''


STEERING_SOURCE = r'''import 'domain.dart';
import 'repository.dart';
import 'run_live_signals.dart';
import 'run_steering_record.dart';
import 'task_kernel/task_specification.dart';

class RunSteeringInstruction {
  const RunSteeringInstruction({
    required this.id,
    required this.runId,
    required this.text,
    required this.patch,
    required this.createdAt,
  });

  final String id;
  final String runId;
  final String text;
  final TaskSpecificationPatch patch;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'runId': runId,
        'text': text,
        'patch': patch.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory RunSteeringInstruction.fromRecord(RunSteeringRecord record) =>
      RunSteeringInstruction(
        id: record.id,
        runId: record.runId,
        text: record.text,
        patch: record.patch,
        createdAt: record.createdAt,
      );
}

class RunSteeringService {
  RunSteeringService({
    required this.liveSignals,
    required this.repository,
  });

  final LiveRunSignalBus liveSignals;
  final EntityRepository<RunSteeringRecord> repository;

  Future<RunSteeringInstruction> queue(String runId, String text) async {
    final normalized = text.trim();
    if (normalized.length < 2) {
      throw ProductException(
        'steering_too_short',
        'Describe the direction you want Kristin to apply.',
      );
    }
    if (normalized.length > 4000) {
      throw ProductException(
        'steering_too_long',
        'A steering message cannot exceed 4,000 characters.',
      );
    }
    final patch = TaskSpecificationPatch.fromUserSteering(normalized);
    if (patch.requiresReplan) {
      throw ProductException(
        'steering_requires_replan',
        'This direction changes task scope and needs a reviewed replan before it can change an active run.',
        details: <String, dynamic>{
          'runId': runId,
          'patch': patch.toJson(),
          'grantsAuthority': false,
        },
      );
    }
    final now = DateTime.now().toUtc();
    final record = RunSteeringRecord(
      id: newId('steer'),
      runId: runId,
      text: normalized,
      patch: patch,
      state: RunSteeringRecordState.pending,
      createdAt: now,
    );
    await repository.put(record);
    final instruction = RunSteeringInstruction.fromRecord(record);
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        kind: LiveRunSignalKind.steeringQueued,
        timestamp: now,
        data: <String, dynamic>{
          'instructionId': instruction.id,
          'text': instruction.text,
          'patch': instruction.patch.toJson(),
          'authorityBearing': false,
        },
      ),
    );
    return instruction;
  }

  Future<List<RunSteeringInstruction>> takePending(String runId) async {
    final values = (await repository.all())
        .where((record) =>
            record.runId == runId &&
            record.state == RunSteeringRecordState.pending)
        .toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<RunSteeringInstruction>.unmodifiable(
      values.map(RunSteeringInstruction.fromRecord),
    );
  }

  Future<void> applied(
    String runId,
    Iterable<RunSteeringInstruction> instructions, {
    String? workItemId,
  }) async {
    final values = instructions.toList(growable: false);
    if (values.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final instruction in values) {
      final record = await repository.get(instruction.id);
      if (record == null ||
          record.runId != runId ||
          record.state != RunSteeringRecordState.pending) {
        continue;
      }
      await repository.put(
        record.copyWith(
          state: RunSteeringRecordState.applied,
          workItemId: workItemId,
          appliedAt: now,
        ),
      );
    }
    liveSignals.publish(
      LiveRunSignal(
        sequence: 0,
        runId: runId,
        workItemId: workItemId,
        kind: LiveRunSignalKind.steeringApplied,
        timestamp: now,
        data: <String, dynamic>{
          'instructionIds': values.map((item) => item.id).toList(),
          'count': values.length,
          'authorityBearing': false,
        },
      ),
    );
  }

  Future<void> clear(String runId) async {
    final pending = (await repository.all()).where(
      (record) =>
          record.runId == runId &&
          record.state == RunSteeringRecordState.pending,
    );
    for (final record in pending) {
      await repository.put(
        record.copyWith(state: RunSteeringRecordState.cleared),
      );
    }
  }
}
'''


PATCH_SOURCE = r'''

/// A user-authored, authority-neutral change to an existing task specification.
///
/// Steering is not a second raw-prompt channel. The user's words are retained,
/// but safe in-flight changes are projected into the same semantic vocabulary
/// used by Understanding and Planning. Scope expansion is explicitly marked as
/// requiring a reviewed replan instead of being smuggled into a running graph.
class TaskSpecificationPatch {
  const TaskSpecificationPatch({
    required this.sourceText,
    this.addedHardConstraints = const <SpecificationClaim>[],
    this.addedPreferences = const <SpecificationClaim>[],
    this.addedSuccessCriteria = const <SpecificationClaim>[],
    this.addedProhibitedEffects = const <String>[],
    this.requiresReplan = false,
  });

  final String sourceText;
  final List<SpecificationClaim> addedHardConstraints;
  final List<SpecificationClaim> addedPreferences;
  final List<SpecificationClaim> addedSuccessCriteria;
  final List<String> addedProhibitedEffects;
  final bool requiresReplan;

  bool get grantsAuthority => false;

  factory TaskSpecificationPatch.fromUserSteering(String text) {
    final value = text.trim();
    if (value.length < 2) {
      throw ArgumentError.value(text, 'text', 'Steering text is too short.');
    }
    final lower = value.toLowerCase();
    final authorityClaim = RegExp(
      r'\b(?:grant(?:ed)?|authori[sz](?:e|ed|ation)|approv(?:e|ed|al)|permission(?:s)?|full access|root access|admin access)\b',
    ).hasMatch(lower);
    if (authorityClaim) {
      // The text remains evidence, but it can never become authority or a
      // constraint that tells the executor permission was granted.
      return TaskSpecificationPatch(
        sourceText: value,
        requiresReplan: true,
      );
    }

    final negative = RegExp(
      r"\b(?:do not|don't|dont|never|must not|without|avoid|stop using|no longer use)\b",
    ).hasMatch(lower);
    if (negative) {
      return TaskSpecificationPatch(
        sourceText: value,
        addedHardConstraints: <SpecificationClaim>[
          SpecificationClaim.stated(value, source: 'steering'),
        ],
        addedProhibitedEffects: <String>[value],
      );
    }

    final preference = RegExp(
      r'\b(?:prefer|ideally|if possible|keep|favor|favour|would rather)\b',
    ).hasMatch(lower);
    if (preference) {
      return TaskSpecificationPatch(
        sourceText: value,
        addedPreferences: <SpecificationClaim>[
          SpecificationClaim.stated(value, source: 'steering'),
        ],
      );
    }

    final criterion = RegExp(
      r'\b(?:make sure|ensure|must still|should still|verify|needs to|has to)\b',
    ).hasMatch(lower);
    if (criterion) {
      return TaskSpecificationPatch(
        sourceText: value,
        addedSuccessCriteria: <SpecificationClaim>[
          SpecificationClaim.stated(value, source: 'steering'),
        ],
      );
    }

    // An unclassified imperative can change topology or deliverables. It is
    // intentionally not injected into a reviewed plan as an opaque sentence.
    return TaskSpecificationPatch(sourceText: value, requiresReplan: true);
  }

  TaskSpecification applyTo(TaskSpecification specification) {
    if (requiresReplan) {
      return specification;
    }
    return specification.copyWith(
      hardConstraints: _mergeClaims(
        specification.hardConstraints,
        addedHardConstraints,
      ),
      preferences: _mergeClaims(
        specification.preferences,
        addedPreferences,
      ),
      successCriteria: _mergeClaims(
        specification.successCriteria,
        addedSuccessCriteria,
      ),
      prohibitedEffects: <String>{
        ...specification.prohibitedEffects,
        ...addedProhibitedEffects,
      }.toList(growable: false),
      contextRefs: <String>{
        ...specification.contextRefs,
        'steering:${Sha256.text(sourceText)}',
      }.toList(growable: false),
    );
  }

  String renderForExecutor() {
    final sections = <String>[
      for (final constraint in addedHardConstraints)
        'Hard constraint: ${constraint.statement}',
      for (final preference in addedPreferences)
        'Preference: ${preference.statement}',
      for (final criterion in addedSuccessCriteria)
        'Success criterion: ${criterion.statement}',
      for (final effect in addedProhibitedEffects)
        'Prohibited effect: $effect',
    ];
    return sections.join('\n');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sourceText': sourceText,
        'addedHardConstraints':
            addedHardConstraints.map((value) => value.toJson()).toList(),
        'addedPreferences':
            addedPreferences.map((value) => value.toJson()).toList(),
        'addedSuccessCriteria':
            addedSuccessCriteria.map((value) => value.toJson()).toList(),
        'addedProhibitedEffects': addedProhibitedEffects,
        'requiresReplan': requiresReplan,
        'grantsAuthority': false,
      };

  factory TaskSpecificationPatch.fromJson(Map<String, dynamic> json) {
    List<SpecificationClaim> claims(Object? raw) =>
        (raw is List ? raw : const <Object>[])
            .whereType<Map>()
            .map((value) => SpecificationClaim.fromJson(mapValue(value)))
            .toList(growable: false);
    return TaskSpecificationPatch(
      sourceText: json['sourceText']?.toString() ?? '',
      addedHardConstraints: claims(json['addedHardConstraints']),
      addedPreferences: claims(json['addedPreferences']),
      addedSuccessCriteria: claims(json['addedSuccessCriteria']),
      addedProhibitedEffects: stringList(json['addedProhibitedEffects']),
      requiresReplan: json['requiresReplan'] == true,
    );
  }

  static List<SpecificationClaim> _mergeClaims(
    List<SpecificationClaim> existing,
    List<SpecificationClaim> additions,
  ) {
    final result = <SpecificationClaim>[...existing];
    final seen = existing.map((value) => value.statement.trim().toLowerCase()).toSet();
    for (final claim in additions) {
      if (seen.add(claim.statement.trim().toLowerCase())) {
        result.add(claim);
      }
    }
    return List<SpecificationClaim>.unmodifiable(result);
  }
}
'''


TEST_SOURCE = r'''import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/run_live_signals.dart';
import 'package:kristin_local_agent/product/run_steering.dart';
import 'package:kristin_local_agent/product/run_steering_record.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';

class _MemoryRepository implements EntityRepository<RunSteeringRecord> {
  final Map<String, RunSteeringRecord> values = <String, RunSteeringRecord>{};
  @override Future<List<RunSteeringRecord>> all() async => values.values.toList();
  @override Future<RunSteeringRecord?> get(String id) async => values[id];
  @override Future<void> put(RunSteeringRecord item) async { values[item.id] = item; }
  @override Future<void> putAll(Iterable<RunSteeringRecord> items) async { for (final item in items) values[item.id] = item; }
  @override Future<void> remove(String id) async { values.remove(id); }
  @override Future<void> removeWhere(bool Function(RunSteeringRecord item) predicate) async { values.removeWhere((_, value) => predicate(value)); }
  @override Future<void> replaceAll(Iterable<RunSteeringRecord> items) async { values..clear()..addEntries(items.map((item) => MapEntry(item.id, item))); }
}

void main() {
  test('constraint steering is semantic, durable, and authority-neutral', () async {
    final repository = _MemoryRepository();
    final service = RunSteeringService(
      liveSignals: LiveRunSignalBus(),
      repository: repository,
    );
    final instruction = await service.queue('run-1', "don't use Firebase");
    expect(instruction.patch.requiresReplan, isFalse);
    expect(instruction.patch.grantsAuthority, isFalse);
    expect(instruction.patch.addedHardConstraints.single.statement, contains('Firebase'));
    expect((await service.takePending('run-1')).single.id, instruction.id);
    await service.applied('run-1', <RunSteeringInstruction>[instruction], workItemId: 'work-2');
    expect((await service.takePending('run-1')), isEmpty);
    expect(repository.values[instruction.id]!.state, RunSteeringRecordState.applied);
  });

  test('scope expansion requires a reviewed replan instead of raw injection', () async {
    final service = RunSteeringService(
      liveSignals: LiveRunSignalBus(),
      repository: _MemoryRepository(),
    );
    await expectLater(
      service.queue('run-1', 'also build an admin dashboard'),
      throwsA(isA<ProductException>().having(
        (error) => error.code,
        'code',
        'steering_requires_replan',
      )),
    );
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
'''


def transform_task_spec(source: str) -> str:
    if 'class TaskSpecificationPatch {' in source:
        return source
    if not source.rstrip().endswith('}'):
        raise RuntimeError('task specification: unexpected file ending')
    return source.rstrip() + PATCH_SOURCE + '\n'


def transform_storage(source: str) -> str:
    source = replace_once(
        source,
        "import 'repository.dart';\n",
        "import 'repository.dart';\nimport 'run_steering_record.dart';\n",
        'storage steering record import',
    )
    source = replace_once(
        source,
        "    required this.evidence,\n",
        "    required this.evidence,\n    required this.runSteeringRecords,\n",
        'repository steering constructor',
    )
    source = replace_once(
        source,
        "  final EntityRepository<EvidenceRecord> evidence;\n",
        "  final EntityRepository<EvidenceRecord> evidence;\n  final EntityRepository<RunSteeringRecord> runSteeringRecords;\n",
        'repository steering field',
    )
    evidence_block = """      evidence: collection<EvidenceRecord>(\n        name: 'evidence',\n        fromJson: EvidenceRecord.fromJson,\n        toJson: (value) => value.toJson(),\n        idOf: (value) => value.id,\n      ),\n"""
    steering_block = evidence_block + """      runSteeringRecords: collection<RunSteeringRecord>(\n        name: 'run_steering_records',\n        fromJson: RunSteeringRecord.fromJson,\n        toJson: (value) => value.toJson(),\n        idOf: (value) => value.id,\n      ),\n"""
    source = replace_once(source, evidence_block, steering_block, 'repository steering collection')
    return source


def transform_runtime(source: str) -> str:
    return replace_once(
        source,
        "    final runSteering = RunSteeringService(liveSignals: liveRunSignals);\n",
        "    final runSteering = RunSteeringService(\n      liveSignals: liveRunSignals,\n      repository: repositories.runSteeringRecords,\n    );\n",
        'runtime steering repository wiring',
    )


def transform_planning(source: str) -> str:
    source = replace_once(
        source,
        "    final instruction = steering.queue(runId, text);\n",
        "    final instruction = await steering.queue(runId, text);\n",
        'queue durable steering',
    )
    source = replace_once(
        source,
        "        'text': instruction.text,\n",
        "        'text': instruction.text,\n        'patch': instruction.patch.toJson(),\n        'grantsAuthority': false,\n",
        'steering queue event patch',
    )
    source = replace_once(
        source,
        "      final pendingSteering = steering.takePending(current.id);\n",
        "      final pendingSteering = await steering.takePending(current.id);\n",
        'await pending steering',
    )
    source = replace_once(
        source,
        "            .map((instruction) => '- ${instruction.text}')\n",
        "            .map((instruction) => '- ${instruction.patch.renderForExecutor()}')\n",
        'semantic executor steering',
    )
    source = replace_once(
        source,
        "        steering.applied(\n",
        "        await steering.applied(\n",
        'persist applied steering',
    )
    return source


def transform_source_contract(source: str) -> str:
    return replace_once(
        source,
        "        'lib/product/run_steering.dart',\n",
        "        'lib/product/run_steering.dart',\n        'lib/product/run_steering_record.dart',\n",
        'source contract steering record',
    )


def compute(root: Path):
    transforms = {
        root / 'lib/product/task_kernel/task_specification.dart': transform_task_spec,
        root / 'lib/product/storage_security.dart': transform_storage,
        root / 'lib/product/run_steering.dart': lambda _: STEERING_SOURCE,
        root / 'lib/product/product_runtime.dart': transform_runtime,
        root / 'lib/product/planning_runtime.dart': transform_planning,
        root / 'test/product/source_contract_test.dart': transform_source_contract,
    }
    result = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f'missing source file: {path}')
        before = path.read_text()
        result[path] = (before, fn(before))
    created = {
        root / 'lib/product/run_steering_record.dart': RECORD_SOURCE,
        root / 'test/product/semantic_durable_steering_test.dart': TEST_SOURCE,
    }
    for path, after in created.items():
        before = path.read_text() if path.exists() else ''
        if before and before != after:
            raise RuntimeError(f'{path}: file already exists with different content')
        result[path] = (before, after)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('repo')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--diff', action='store_true')
    parser.add_argument('--allow-head-drift', action='store_true')
    args = parser.parse_args()
    root = Path(args.repo).resolve()
    head = git_head(root)
    if head and head != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(f'refusing HEAD {head}; expected {EXPECTED_HEAD}')
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=f'a/{rel}', tofile=f'b/{rel}',
            )), end='')
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
