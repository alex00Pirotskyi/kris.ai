#!/usr/bin/env python3
"""Follow steering continuation runs in One-Kristin Chat and project canonical activity.

This is a guarded source transformer. It performs no Git writes.
It assumes the earlier state-convergence and scope-continuation slices have run.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def head(root: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()


def rep(src: str, old: str, new: str, label: str) -> str:
    count = src.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return src.replace(old, new, 1)


def transform_session(src: str) -> str:
    anchor = """  void updateRun(RunRecord run) {\n    _attachRun(run, restoring: false);\n  }\n\n"""
    method = r'''  /// Replaces a retired steering source run with its linked continuation.
  ///
  /// This is the only conversation-level exception to the normal rule that a
  /// different non-terminal run cannot replace the attached run. It is narrow:
  /// the source must already be interrupted, the continuation must name that
  /// exact source through [RunRecord.sourceRunId], and no authority is copied.
  void replaceRunWithContinuation({
    required RunRecord source,
    required RunRecord continuation,
  }) {
    final attached = _currentRun;
    if (attached == null || attached.id != source.id) {
      throw const KristinConversationSessionException(
        'conversation_continuation_source_mismatch',
        'The steering continuation can replace only the currently attached source run.',
      );
    }
    if (source.state != RunState.interrupted ||
        continuation.sourceRunId != source.id) {
      throw const KristinConversationSessionException(
        'conversation_continuation_link_invalid',
        'A steering continuation must be linked to an interrupted source run.',
      );
    }
    _currentRun = continuation;
    _prepared = continuation.command;
    _activeRequest = continuation.command.contract.request;
    selectProject(continuation.command.contract.projectId);
    selectModel(continuation.command.model.exactId);
    _deferredInteraction = null;
    _awaitingPermission = continuation.state == RunState.awaitingApproval;
    clearLiveExecution();
  }

'''
    return rep(src, anchor, anchor + method, "session continuation handoff")


def transform_runtime(src: str) -> str:
    anchor = """  Future<RunSteeringInstruction> steerRun(String runId, String text) async {\n"""
    method = r'''  /// Returns the durable steering continuation linked to [sourceRunId], if
  /// materialization has completed. This is a read-only projection used by
  /// One-Kristin Chat to follow the same logical task after reconciliation.
  Future<RunRecord?> steeringContinuationForSourceRun(String sourceRunId) async {
    final records = (await repositories.runSteeringRecords.all())
        .where((record) =>
            record.runId == sourceRunId &&
            (record.continuationRunId?.trim().isNotEmpty ?? false))
        .toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final continuationId = records.firstOrNull?.continuationRunId;
    if (continuationId == null || continuationId.trim().isEmpty) return null;
    final continuation = await repositories.runs.get(continuationId);
    if (continuation == null || continuation.sourceRunId != sourceRunId) {
      return null;
    }
    return continuation;
  }

'''
    return rep(src, anchor, method + anchor, "runtime continuation lookup")


def transform_studio(src: str) -> str:
    old = r'''  Future<void> _refreshCurrentRun() async {
    final run = currentRun;
    if (run == null) return;
    final refreshed = await _perform<RunRecord?>(
      'Refreshing execution',
      () => runtime.getRun(run.id),
      silent: true,
    );
    if (refreshed == null || !mounted) return;
    final newTerminal = const <RunState>{
      RunState.succeeded,
      RunState.failed,
      RunState.cancelled,
    }.contains(refreshed.state);
    final loadedEvidence =
        newTerminal ? await runtime.evidenceForRun(refreshed.id) : evidence;
    final deferred = newTerminal
        ? null
        : await runtime.latestDeferredInteraction(refreshed.id);
    _mutate(() {
      currentRun = refreshed;
      conversationSession.setDeferredInteraction(deferred);
      evidence = loadedEvidence;
      // Completed work is recorded against the canonical plan as it
      // happens, so a later replan can preserve it instead of asking the
      // user to watch finished tasks run a second time.
      completedTasks = _completedTasksFrom(refreshed);
      awaitingPermission = refreshed.state == RunState.awaitingApproval;
      if (conversationSession.awaitingUserInput) {
        status = conversationSession.deferredUserPrompt ??
            'Kristin needs your input before continuing.';
      } else if (newTerminal) {
        status = refreshed.state == RunState.succeeded
            ? 'Finished and verified'
            : 'Execution stopped safely';
      }
    });
  }
'''
    new = r'''  Future<void> _refreshCurrentRun() async {
    final run = currentRun;
    if (run == null) return;
    final refreshed = await _perform<RunRecord?>(
      'Refreshing execution',
      () => runtime.getRun(run.id),
      silent: true,
    );
    if (refreshed == null || !mounted) return;

    // Scope-changing steering retires the source only at a verified task
    // boundary and creates a linked awaiting-approval continuation. Follow
    // that durable link instead of leaving Chat attached to the interrupted
    // source plan. The session validates the source/continuation relationship.
    final continuation = refreshed.state == RunState.interrupted
        ? await runtime.steeringContinuationForSourceRun(refreshed.id)
        : null;
    final visibleRun = continuation ?? refreshed;
    final newTerminal = const <RunState>{
      RunState.succeeded,
      RunState.failed,
      RunState.cancelled,
    }.contains(visibleRun.state);
    final loadedEvidence = continuation != null
        ? await runtime.evidenceForRun(visibleRun.id)
        : newTerminal
            ? await runtime.evidenceForRun(visibleRun.id)
            : evidence;
    final deferred = newTerminal
        ? null
        : await runtime.latestDeferredInteraction(visibleRun.id);
    _mutate(() {
      if (continuation != null) {
        // Refresh the source first so the session sees its durable interrupted
        // state, then perform the narrow linked-run handoff.
        conversationSession.updateRun(refreshed);
        conversationSession.replaceRunWithContinuation(
          source: refreshed,
          continuation: continuation,
        );
        prepared = continuation.command;
        activeRequest = continuation.command.contract.request;
        selectedProjectId = continuation.command.contract.projectId;
        selectedModelId = continuation.command.model.exactId;
      } else {
        currentRun = visibleRun;
      }
      conversationSession.setDeferredInteraction(deferred);
      evidence = loadedEvidence;
      completedTasks = _completedTasksFrom(visibleRun);
      awaitingPermission = visibleRun.state == RunState.awaitingApproval;
      if (continuation != null && visibleRun.state == RunState.awaitingApproval) {
        status = 'Scope updated. Review permissions for the reconciled continuation.';
      } else if (conversationSession.awaitingUserInput) {
        status = conversationSession.deferredUserPrompt ??
            'Kristin needs your input before continuing.';
      } else if (newTerminal) {
        status = visibleRun.state == RunState.succeeded
            ? 'Finished and verified'
            : 'Execution stopped safely';
      }
    });
  }
'''
    return rep(src, old, new, "studio continuation refresh")


def transform_view(src: str) -> str:
    src = rep(
        src,
        r'''  Widget _runCard(RunRecord run) {
    final done =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    final showModelAnswer = run.command.contract.mode == CommandMode.ask &&
        liveAssistantText.trim().isNotEmpty;
''',
        r'''  Widget _runCard(RunRecord run) {
    final done =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    final showModelAnswer = run.command.contract.mode == CommandMode.ask &&
        liveAssistantText.trim().isNotEmpty;
    final activitySignals = liveSignals
        .where((signal) =>
            signal.kind != LiveRunSignalKind.modelTextDelta &&
            signal.kind != LiveRunSignalKind.heartbeat)
        .toList(growable: false);
    final recentActivity = activitySignals.length <= 10
        ? activitySignals
        : activitySignals.sublist(activitySignals.length - 10);
''',
        "run card activity list",
    )
    src = rep(
        src,
        r'''              if (liveToolOutput.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _technicalBox(liveToolOutput),
              ],
''',
        r'''              if (recentActivity.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent activity',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 4),
                ...recentActivity.map(
                  (signal) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_activityIcon(signal), size: 18),
                    title: Text(_activityLabel(signal)),
                    subtitle: Text(
                      signal.workItemId == null
                          ? _activityTimestamp(signal)
                          : '${_activityTimestamp(signal)} · ${signal.workItemId}',
                    ),
                  ),
                ),
              ],
              if (liveToolOutput.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _technicalBox(liveToolOutput),
              ],
''',
        "details activity projection",
    )
    anchor = """  Widget _technicalBox(String value) {\n"""
    helpers = r'''  String _activityLabel(LiveRunSignal signal) {
    final message = signal.data['message']?.toString().trim() ?? '';
    final tool = signal.data['tool']?.toString().trim() ?? '';
    return switch (signal.kind) {
      LiveRunSignalKind.phase ||
      LiveRunSignalKind.preflight ||
      LiveRunSignalKind.modelProgress =>
        message.isEmpty ? 'Kristin advanced to the next safe step.' : message,
      LiveRunSignalKind.toolStarted =>
        tool.isEmpty ? 'Started a governed tool.' : 'Using $tool',
      LiveRunSignalKind.toolOutput =>
        tool.isEmpty ? 'Receiving governed tool output.' : 'Receiving output from $tool',
      LiveRunSignalKind.toolCompleted =>
        tool.isEmpty ? 'Governed tool completed.' : '$tool completed',
      LiveRunSignalKind.toolFailed =>
        tool.isEmpty ? 'A governed tool needs attention.' : '$tool needs attention',
      LiveRunSignalKind.steeringQueued =>
        'Your direction was queued for the next safe boundary.',
      LiveRunSignalKind.steeringApplied =>
        'Your direction was applied to future work.',
      LiveRunSignalKind.modelTextDelta => 'Model response streaming',
      LiveRunSignalKind.heartbeat => 'Execution heartbeat',
    };
  }

  IconData _activityIcon(LiveRunSignal signal) => switch (signal.kind) {
        LiveRunSignalKind.toolStarted ||
        LiveRunSignalKind.toolOutput ||
        LiveRunSignalKind.toolCompleted =>
          Icons.build_outlined,
        LiveRunSignalKind.toolFailed => Icons.error_outline,
        LiveRunSignalKind.steeringQueued ||
        LiveRunSignalKind.steeringApplied =>
          Icons.alt_route,
        LiveRunSignalKind.preflight => Icons.fact_check_outlined,
        LiveRunSignalKind.modelProgress ||
        LiveRunSignalKind.modelTextDelta =>
          Icons.psychology_outlined,
        LiveRunSignalKind.phase => Icons.timeline_outlined,
        LiveRunSignalKind.heartbeat => Icons.monitor_heart_outlined,
      };

  String _activityTimestamp(LiveRunSignal signal) {
    final value = signal.timestamp.toLocal();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

'''
    return rep(src, anchor, helpers + anchor, "activity helper methods")


TEST_SOURCE = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('Chat follows a linked steering continuation without authority inheritance', () {
    final session = source('lib/product/kristin_conversation_session.dart');
    final studio = source('lib/product/chat_control_plane_studio.dart');
    final runtime = source('lib/product/product_runtime.dart');
    expect(session, contains('replaceRunWithContinuation'));
    expect(session, contains('continuation.sourceRunId != source.id'));
    expect(studio, contains('steeringContinuationForSourceRun(refreshed.id)'));
    expect(studio, contains('Review permissions for the reconciled continuation'));
    expect(runtime, contains('steeringContinuationForSourceRun'));
  });

  test('Details projects canonical live activity and hides raw token deltas', () {
    final view = source('lib/product/chat_control_plane_studio_view.dart');
    expect(view, contains("'Recent activity'"));
    expect(view, contains('signal.kind != LiveRunSignalKind.modelTextDelta'));
    expect(view, contains('signal.kind != LiveRunSignalKind.heartbeat'));
    expect(view, contains('_activityLabel'));
  });
}
'''


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    transforms = {
        root / "lib/product/kristin_conversation_session.dart": transform_session,
        root / "lib/product/product_runtime.dart": transform_runtime,
        root / "lib/product/chat_control_plane_studio.dart": transform_studio,
        root / "lib/product/chat_control_plane_studio_view.dart": transform_view,
    }
    result: dict[Path, tuple[str, str]] = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f"missing source file: {path}")
        before = path.read_text()
        after = fn(before)
        result[path] = (before, after)
    test = root / "test/product/chat_continuation_activity_contract_test.dart"
    before = test.read_text() if test.exists() else ""
    result[test] = (before, TEST_SOURCE)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--diff", action="store_true")
    ap.add_argument("--allow-head-drift", action="store_true")
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    current = head(root)
    if current != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(
            f"refusing HEAD {current}; expected {EXPECTED_HEAD}; review drift first"
        )
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            if before == after:
                continue
            print(
                "".join(
                    difflib.unified_diff(
                        before.splitlines(True),
                        after.splitlines(True),
                        fromfile=str(path.relative_to(root)),
                        tofile=str(path.relative_to(root)),
                    )
                )
            )
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
        print("Applied continuation handoff + canonical activity projection slice.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
