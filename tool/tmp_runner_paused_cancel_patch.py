from pathlib import Path

source = Path('lib/product/planning_runtime.dart')
text = source.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'unexpected {label} source shape: {count} matches')
    text = text.replace(old, new, 1)


replace_once(
    """  Future<void> cancel(String runId) async {
    final control = _controls[runId];
    control?.cancellation.cancel();
    final run = await repositories.runs.get(runId);
    if (run != null &&
        !const <RunState>{
          RunState.cancelled,
          RunState.succeeded,
          RunState.failed,
        }.contains(run.state)) {
      await _save(run.copyWith(state: RunState.cancelling));
    }
    await events.publish('run.cancelling', runId, <String, dynamic>{
      'runId': runId,
    });
  }

""",
    """  Future<void> cancel(String runId) async {
    var control = _controls[runId];
    if (control != null && control.deferredSuspension) {
      control.cancellation.cancel();
      final active = _active[runId];
      if (active != null) {
        await active;
      }
      control = _controls[runId];
    }
    final run = await repositories.runs.get(runId);
    if (run == null) {
      throw ProductException('run_missing', 'Unknown run: $runId');
    }
    if (const <RunState>{
      RunState.cancelled,
      RunState.succeeded,
      RunState.failed,
    }.contains(run.state)) {
      return;
    }
    if (control == null && run.state == RunState.paused) {
      await _cancelDurablyPausedRun(run);
      return;
    }
    control?.cancellation.cancel();
    await _save(run.copyWith(state: RunState.cancelling));
    await events.publish('run.cancelling', runId, <String, dynamic>{
      'runId': runId,
    });
  }

  Future<void> _cancelDurablyPausedRun(RunRecord source) async {
    final leaseOwner = '$_instanceId:${newId('cancel_lease')}';
    final claimed = await repositories.workflow.acquireRunLease(
      runId: source.id,
      ownerId: leaseOwner,
      lease: _runLeaseDuration,
    );
    if (!claimed) {
      throw ProductException(
        'run_claimed',
        'This run is owned by another live Kristin workflow-kernel lease.',
        details: <String, dynamic>{'runId': source.id},
      );
    }
    _runLeaseOwners[source.id] = leaseOwner;
    final heartbeat = Timer.periodic(_runLeaseHeartbeat, (_) {
      unawaited(_renewRunLease(source.id, leaseOwner));
    });
    try {
      await _locks.runExclusive(source.command.contract.projectId, () async {
        final run = (await repositories.runs.get(source.id)) ?? source;
        if (const <RunState>{
          RunState.cancelled,
          RunState.succeeded,
          RunState.failed,
        }.contains(run.state)) {
          return;
        }
        if (run.state != RunState.paused) {
          throw ProductException(
            'run_cancel_state_changed',
            'Run ${run.id} is no longer durably paused for cancellation.',
            details: <String, dynamic>{
              'runId': run.id,
              'state': run.state.name,
            },
          );
        }
        final project = await repositories.projects.get(
          run.command.contract.projectId,
        );
        if (project == null) {
          throw ProductException(
            'project_missing',
            'The selected project is no longer registered; Kristin cannot safely roll back the paused run.',
          );
        }
        final boundary = await WorkspaceBoundary.open(project.rootPath);
        final checkpointRoot = Directory(
          '${directories.state.path}${Platform.pathSeparator}checkpoints',
        );
        await checkpointRoot.create(recursive: true);
        final transaction = await WorkspaceTransaction.begin(
          runId: run.id,
          boundary: boundary,
          checkpointRoot: checkpointRoot,
          audit: audit,
          workflow: repositories.workflow,
        );
        if (transaction.isCommitted) {
          throw ProductException(
            'run_cancel_transaction_committed',
            'The paused run workspace is already committed and cannot be cancelled by rollback.',
            details: <String, dynamic>{'runId': run.id},
          );
        }
        try {
          await transaction.rollback();
        } catch (error) {
          final failure = redactor.redact('$error');
          await _bestEffortAudit(
            'run.cancel_rollback_failed',
            run.id,
            <String, dynamic>{
              'runId': run.id,
              'error': failure,
            },
          );
          throw ProductException(
            'run_cancel_rollback_failed',
            'Kristin could not safely roll back the paused workspace.',
            details: <String, dynamic>{
              'runId': run.id,
              'error': failure,
            },
          );
        }
        final completedAt = DateTime.now().toUtc();
        final activeItems = run.items
            .where((progress) => progress.state == WorkItemState.running)
            .toList(growable: false);
        final cancelledItems = run.items
            .map(
              (progress) => progress.state == WorkItemState.running
                  ? progress.copyWith(
                      state: WorkItemState.cancelled,
                      lastError:
                          'Cancelled while waiting for durable continuation.',
                      completedAt: completedAt,
                    )
                  : progress,
            )
            .toList(growable: false);
        final cancelled = run.copyWith(
          state: RunState.cancelled,
          items: cancelledItems,
          completedAt: completedAt,
          failure: 'cancelled: Run cancelled while durably paused.',
        );
        await _save(cancelled);
        for (final progress in activeItems) {
          await repositories.workflow.recordTaskAttempt(
            runId: cancelled.id,
            workItemId: progress.item.id,
            attempt: progress.attempts,
            state: 'cancelled',
            errorClass: 'cancelled',
            errorCode: 'cancelled',
            retryDisposition: 'terminal',
            startedAt: progress.startedAt,
            completedAt: completedAt,
            details: const <String, dynamic>{
              'durablePausedCancellation': true,
            },
          );
        }
        try {
          await permissions.revokeForCommand(cancelled.command.id);
        } catch (_) {}
        final evidence = <String, dynamic>{
          'runId': cancelled.id,
          'durablePausedCancellation': true,
          'rolledBackWorkspace': true,
          'mutations': transaction.mutationCount,
        };
        await _bestEffortAudit('run.cancelled', cancelled.id, evidence);
        await _bestEffortEvent('run.cancelled', cancelled.id, evidence);
        try {
          await _recordEpisode(cancelled);
        } catch (_) {}
      });
    } finally {
      heartbeat.cancel();
      try {
        await repositories.workflow.releaseRunLease(
          runId: source.id,
          ownerId: leaseOwner,
        );
      } finally {
        if (_runLeaseOwners[source.id] == leaseOwner) {
          _runLeaseOwners.remove(source.id);
        }
      }
    }
  }

""",
    'cancel implementation',
)

source.write_text(text, encoding='utf-8', newline='\n')

test = Path('test/product/runner_deferred_takeover_contract_test.dart')
test_text = test.read_text(encoding='utf-8')
marker = """  test('resolved response is reintroduced as non-authority user intent', () {
"""
addition = """  test('durably paused cancellation rolls back before terminal state', () {
    expect(
      source,
      contains('if (control == null && run.state == RunState.paused) {'),
    );
    expect(source, contains('await _cancelDurablyPausedRun(run);'));
    expect(source, contains('Future<void> _cancelDurablyPausedRun('));
    expect(source, contains('await WorkspaceTransaction.begin('));
    expect(source, contains('await transaction.rollback();'));
    expect(source, contains('state: RunState.cancelled,'));
    expect(source, contains('state: WorkItemState.cancelled,'));
    expect(source, contains("state: 'cancelled',"));
    expect(source, contains("'durablePausedCancellation': true,"));
    expect(source, contains("'rolledBackWorkspace': true,"));
  });

  test('cancel waits for a deferred stack to unwind before rollback', () {
    expect(
      source,
      contains('if (control != null && control.deferredSuspension) {'),
    );
    expect(source, contains('control.cancellation.cancel();'));
    expect(source, contains('final active = _active[runId];'));
    expect(source, contains('await active;'));
    expect(source, contains('control = _controls[runId];'));
  });

"""
if test_text.count(marker) != 1:
    raise SystemExit(f'unexpected runner contract test shape: {test_text.count(marker)} matches')
test.write_text(
    test_text.replace(marker, addition + marker, 1),
    encoding='utf-8',
    newline='\n',
)
