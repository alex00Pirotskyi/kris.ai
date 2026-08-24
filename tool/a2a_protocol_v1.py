#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping, Sequence


A2A_VERSION = "1.0"
A2A_VERSION_HEADER = "A2A-Version"
SUPPORTED_AUTH_SCHEMES = frozenset({"bearer", "oauth2", "mtls", "none"})


class TaskState(str, Enum):
    SUBMITTED = "submitted"
    WORKING = "working"
    INPUT_REQUIRED = "input_required"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELED = "canceled"
    UNKNOWN = "unknown"

    @property
    def terminal(self) -> bool:
        return self in {TaskState.COMPLETED, TaskState.FAILED, TaskState.CANCELED, TaskState.UNKNOWN}


@dataclass(frozen=True)
class AgentCard:
    agent_id: str
    name: str
    endpoint: str
    version: str
    skills: tuple[str, ...]
    auth_schemes: tuple[str, ...]
    streaming: bool
    async_tasks: bool

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "AgentCard":
        if str(value.get("protocolVersion") or "") != A2A_VERSION:
            raise ValueError("a2a_version_unsupported")
        agent_id = str(value.get("agentId") or "").strip()
        name = str(value.get("name") or "").strip()
        endpoint = str(value.get("endpoint") or "").strip()
        skills = tuple(sorted({str(item) for item in value.get("skills") or [] if str(item).strip()}))
        auth = tuple(sorted({str(item) for item in value.get("authSchemes") or [] if str(item).strip()}))
        if not agent_id or not name or not endpoint or not skills:
            raise ValueError("a2a_agent_card_incomplete")
        if not set(auth).issubset(SUPPORTED_AUTH_SCHEMES) or not auth:
            raise ValueError("a2a_auth_scheme_unsupported")
        return cls(
            agent_id=agent_id,
            name=name,
            endpoint=endpoint,
            version=str(value.get("version") or "0"),
            skills=skills,
            auth_schemes=auth,
            streaming=value.get("streaming") is True,
            async_tasks=value.get("asyncTasks") is True,
        )


@dataclass(frozen=True)
class Artifact:
    artifact_id: str
    media_type: str
    sha256: str
    bytes_count: int

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "Artifact":
        artifact_id = str(value.get("artifactId") or "").strip()
        media_type = str(value.get("mediaType") or "application/octet-stream").strip()
        sha256 = str(value.get("sha256") or "").lower()
        bytes_count = int(value.get("bytes") or 0)
        if not artifact_id or len(sha256) != 64 or any(ch not in "0123456789abcdef" for ch in sha256):
            raise ValueError("a2a_artifact_identity_invalid")
        if bytes_count < 0:
            raise ValueError("a2a_artifact_size_invalid")
        return cls(artifact_id, media_type, sha256, bytes_count)


@dataclass(frozen=True)
class Message:
    message_id: str
    role: str
    text: str

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "Message":
        message_id = str(value.get("messageId") or "").strip()
        role = str(value.get("role") or "").strip()
        text = str(value.get("text") or "")
        if not message_id or role not in {"user", "agent"}:
            raise ValueError("a2a_message_invalid")
        return cls(message_id, role, text)


@dataclass(frozen=True)
class TaskSnapshot:
    task_id: str
    state: TaskState
    messages: tuple[Message, ...]
    artifacts: tuple[Artifact, ...]
    revision: int

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "TaskSnapshot":
        task_id = str(value.get("taskId") or "").strip()
        if not task_id:
            raise ValueError("a2a_task_id_missing")
        try:
            state = TaskState(str(value.get("state") or ""))
        except ValueError as exc:
            raise ValueError("a2a_task_state_invalid") from exc
        revision = int(value.get("revision") or 0)
        if revision < 0:
            raise ValueError("a2a_task_revision_invalid")
        messages = tuple(Message.from_json(item) for item in value.get("messages") or [])
        artifacts = tuple(Artifact.from_json(item) for item in value.get("artifacts") or [])
        return cls(task_id, state, messages, artifacts, revision)


class A2AProtocolAdapter:
    def request_headers(self, *, auth_header: str | None = None) -> dict[str, str]:
        headers = {A2A_VERSION_HEADER: A2A_VERSION, "Content-Type": "application/json"}
        if auth_header:
            headers["Authorization"] = auth_header
        return headers

    def validate_response_headers(self, headers: Mapping[str, str]) -> None:
        version = headers.get(A2A_VERSION_HEADER) or headers.get(A2A_VERSION_HEADER.lower())
        if version != A2A_VERSION:
            raise ValueError("a2a_response_version_mismatch")

    def reconcile_stream(
        self,
        previous: TaskSnapshot | None,
        events: Sequence[Mapping[str, Any]],
    ) -> TaskSnapshot:
        current = previous
        for raw in events:
            snapshot = TaskSnapshot.from_json(raw)
            if current is not None:
                if snapshot.task_id != current.task_id:
                    raise ValueError("a2a_stream_task_changed")
                if snapshot.revision <= current.revision:
                    raise ValueError("a2a_stream_revision_replayed")
                if current.state.terminal and snapshot.state != current.state:
                    raise ValueError("a2a_terminal_state_changed")
            current = snapshot
        if current is None:
            raise ValueError("a2a_stream_empty")
        return current

    def classify_disconnect(self, snapshot: TaskSnapshot | None) -> TaskState:
        if snapshot is None or not snapshot.state.terminal:
            return TaskState.UNKNOWN
        return snapshot.state
