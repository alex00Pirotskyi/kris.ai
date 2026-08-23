#!/usr/bin/env python3
from __future__ import annotations

import a2a_protocol_v1 as a2a


def expect_error(fn, code: str) -> None:
    try:
        fn()
    except ValueError as exc:
        assert code in str(exc), exc
        return
    raise AssertionError(f"expected {code}")


def main() -> int:
    card = a2a.AgentCard.from_json(
        {
            "protocolVersion": "1.0",
            "agentId": "validator.agent",
            "name": "Validator",
            "endpoint": "https://agent.example.invalid/a2a",
            "version": "1.2.3",
            "skills": ["verify", "summarize"],
            "authSchemes": ["mtls", "bearer"],
            "streaming": True,
            "asyncTasks": True,
        }
    )
    assert card.streaming and card.async_tasks
    expect_error(
        lambda: a2a.AgentCard.from_json(
            {
                "protocolVersion": "0.9",
                "agentId": "bad",
                "name": "Bad",
                "endpoint": "https://bad.invalid",
                "skills": ["x"],
                "authSchemes": ["none"],
            }
        ),
        "a2a_version_unsupported",
    )

    adapter = a2a.A2AProtocolAdapter()
    headers = adapter.request_headers(auth_header="Bearer redacted")
    assert headers["A2A-Version"] == "1.0"
    adapter.validate_response_headers({"A2A-Version": "1.0"})
    expect_error(
        lambda: adapter.validate_response_headers({"A2A-Version": "0.9"}),
        "a2a_response_version_mismatch",
    )

    artifact = {
        "artifactId": "report",
        "mediaType": "application/json",
        "sha256": "a" * 64,
        "bytes": 42,
    }
    first = {
        "taskId": "task-1",
        "state": "working",
        "revision": 1,
        "messages": [{"messageId": "m1", "role": "agent", "text": "working"}],
        "artifacts": [],
    }
    final = {
        "taskId": "task-1",
        "state": "completed",
        "revision": 2,
        "messages": [{"messageId": "m2", "role": "agent", "text": "done"}],
        "artifacts": [artifact],
    }
    snapshot = adapter.reconcile_stream(None, [first, final])
    assert snapshot.state is a2a.TaskState.COMPLETED
    assert snapshot.artifacts[0].sha256 == "a" * 64
    assert adapter.classify_disconnect(snapshot) is a2a.TaskState.COMPLETED
    assert adapter.classify_disconnect(a2a.TaskSnapshot.from_json(first)) is a2a.TaskState.UNKNOWN

    expect_error(
        lambda: adapter.reconcile_stream(
            a2a.TaskSnapshot.from_json(first),
            [first],
        ),
        "a2a_stream_revision_replayed",
    )
    expect_error(
        lambda: adapter.reconcile_stream(
            snapshot,
            [
                {
                    **final,
                    "state": "working",
                    "revision": 3,
                }
            ],
        ),
        "a2a_terminal_state_changed",
    )

    print("PASS A2A protocol v1: card, version, auth, streaming and unknown outcomes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
