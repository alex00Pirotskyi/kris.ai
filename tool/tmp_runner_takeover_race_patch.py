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
    """    control.paused = false;
    final execution = _locks.runExclusive(
""",
    """    control.paused = false;
    control.deferredSuspension = false;
    final execution = _locks.runExclusive(
""",
    'execute control reset',
)

replace_once(
    """  Future<void> resume(String runId) async {
    await _throwIfDeferredInteractionPending(runId);
    final control = _controls[runId];
    if (control != null) {
""",
    """  Future<void> resume(String runId) async {
    await _throwIfDeferredInteractionPending(runId);
    final control = _controls[runId];
    if (control != null && control.deferredSuspension) {
      final active = _active[runId];
      if (active != null) {
        await active;
      }
      unawaited(execute(runId));
      return;
    }
    if (control != null) {
""",
    'deferred resume handoff',
)

replace_once(
    """          final interaction = await AgentDeferredInteractionStore(
            repositories.workflow,
          ).persist(
            runId: current.id,
            workItemId: progress.item.id,
            step: executionStep,
          );
          throw _DeferredInteractionSuspension(interaction);
""",
    """          control.deferredSuspension = true;
          late final AgentDeferredInteraction interaction;
          try {
            interaction = await AgentDeferredInteractionStore(
              repositories.workflow,
            ).persist(
              runId: current.id,
              workItemId: progress.item.id,
              step: executionStep,
            );
          } catch (_) {
            control.deferredSuspension = false;
            rethrow;
          }
          throw _DeferredInteractionSuspension(interaction);
""",
    'deferred persist marker',
)

replace_once(
    """class RunControl {
  RunControl(this.cancellation);
  final CancellationSignal cancellation;
  bool paused = false;
}
""",
    """class RunControl {
  RunControl(this.cancellation);
  final CancellationSignal cancellation;
  bool paused = false;
  bool deferredSuspension = false;
}
""",
    'run control flag',
)

source.write_text(text, encoding='utf-8', newline='\n')

test = Path('test/product/runner_deferred_takeover_contract_test.dart')
test_text = test.read_text(encoding='utf-8')
marker = """  test('resolved response is reintroduced as non-authority user intent', () {
"""
addition = """  test('resume waits for deferred stack release before re-entering execute', () {
    expect(source, contains('bool deferredSuspension = false;'));
    expect(source, contains('control.deferredSuspension = true;'));
    expect(
      source,
      contains('if (control != null && control.deferredSuspension) {'),
    );
    expect(source, contains('final active = _active[runId];'));
    expect(source, contains('await active;'));
    expect(source, contains('unawaited(execute(runId));'));
    expect(source, contains('control.deferredSuspension = false;'));
  });

"""
if test_text.count(marker) != 1:
    raise SystemExit(f'unexpected runner contract test shape: {test_text.count(marker)} matches')
test.write_text(
    test_text.replace(marker, addition + marker, 1),
    encoding='utf-8',
    newline='\n',
)
