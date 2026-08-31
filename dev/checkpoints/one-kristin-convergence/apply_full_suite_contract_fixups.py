#!/usr/bin/env python3
"""Reconcile two legacy full-suite contracts with the recovered runtime semantics.

This is a bounded qualification compatibility fixup only:
- durable steering remains pending until RunSteeringService.applied() acknowledges it;
- protocol-v3 supports bounded timestamp waits and model-only delegation while
  opaque wait handles remain fail-closed.

No product runtime code is changed.
"""
from __future__ import annotations

import argparse
import difflib
from pathlib import Path


HF_TEST = Path("test/product/hf_runner_chat_convergence_test.dart")
TAKEOVER_TEST = Path("test/product/runner_deferred_takeover_contract_test.dart")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def transform_hf_test(text: str) -> str:
    old = """  test('steering is queued then consumed exactly once', () async {
    final bus = LiveRunSignalBus();
    addTearDown(bus.close);
    final steering = RunSteeringService(
      liveSignals: bus,
      repository: _MemoryRunSteeringRepository(),
    );
    final queued = await steering.queue('run-a', 'keep everything local');
    expect(queued.text, 'keep everything local');
    final first = await steering.takePending('run-a');
    final second = await steering.takePending('run-a');
    expect(first, hasLength(1));
    expect(second, isEmpty);
  });
"""
    new = """  test('steering remains durable until explicitly acknowledged once', () async {
    final bus = LiveRunSignalBus();
    addTearDown(bus.close);
    final steering = RunSteeringService(
      liveSignals: bus,
      repository: _MemoryRunSteeringRepository(),
    );
    final queued = await steering.queue('run-a', 'keep everything local');
    expect(queued.text, 'keep everything local');

    final first = await steering.takePending('run-a');
    final replayBeforeAck = await steering.takePending('run-a');
    expect(first, hasLength(1));
    expect(replayBeforeAck, hasLength(1));
    expect(replayBeforeAck.single.id, first.single.id);

    await steering.applied('run-a', first);
    final afterAck = await steering.takePending('run-a');
    expect(afterAck, isEmpty);
  });
"""
    if new in text:
        if old in text:
            raise RuntimeError("HF steering contract: both old and new blocks are present")
        return text
    return replace_once(text, old, new, "HF durable steering contract")


def transform_takeover_test(text: str) -> str:
    old = """  test('Runner advertises only user takeover among deferred v3 controls', () {
    expect(
      source,
      contains(
          'Protocol v3 user_takeover is the only deferred control decision'),
    );
    expect(
      source,
      contains('Do not emit protocol-v3 wait or delegate decisions.'),
    );
    expect(source, contains('if (!executionStep.isUserTakeover) {'));
    expect(source, contains("'agent_decision_v3_deferred_action'"));
  });
"""
    new = """  test('Runner bounds deferred v3 controls and rejects opaque waits', () {
    expect(
      source,
      contains(
        'Protocol-v3 `wait` is allowed only with an absolute UTC `waitUntil` timestamp',
      ),
    );
    expect(
      source,
      contains(
        'Do not emit an opaque `waitHandle`; no signal source is registered for it yet.',
      ),
    );
    expect(
      source,
      contains(
        'Protocol-v3 `delegate` is allowed only to one of these bounded model-only roles',
      ),
    );
    expect(source, contains('Future<RunRecord> _executeBoundedDelegation({'));
    expect(
      source,
      contains(
        'if (!executionStep.isUserTakeover && !executableTimestampWait) {',
      ),
    );
    expect(source, contains("'agent_decision_v3_deferred_action'"));
  });
"""
    if new in text:
        if old in text:
            raise RuntimeError("deferred-v3 contract: both old and new blocks are present")
        return text
    return replace_once(text, old, new, "bounded deferred-v3 contract")


def render_diff(path: Path, before: str, after: str) -> str:
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    root = args.repo.resolve()
    transforms = {
        HF_TEST: transform_hf_test,
        TAKEOVER_TEST: transform_takeover_test,
    }
    changed = False
    for relative, transform in transforms.items():
        path = root / relative
        if not path.is_file():
            raise RuntimeError(f"required source file is missing: {relative}")
        before = path.read_text(encoding="utf-8")
        after = transform(before)
        if after == before:
            continue
        changed = True
        if args.apply:
            path.write_text(after, encoding="utf-8")
        else:
            print(render_diff(relative, before, after), end="")

    print(f"full-suite contract fixups {'applied' if args.apply else 'planned'}; changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
