#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import socket
import socketserver
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


class IpcAuthenticationError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def canonical_message(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def request_mac(key: bytes, envelope: dict[str, Any]) -> str:
    unsigned = dict(envelope)
    unsigned.pop("mac", None)
    return hmac.new(key, canonical_message(unsigned), hashlib.sha256).hexdigest()


@dataclass
class ReplayCache:
    seen: set[tuple[str, str]]

    def __init__(self) -> None:
        self.seen = set()

    def consume(self, peer_id: str, request_id: str) -> None:
        token = (peer_id, request_id)
        if token in self.seen:
            raise IpcAuthenticationError("ipc_replay", "Request id was already consumed.")
        self.seen.add(token)


class LocalIpcAuthenticator:
    def __init__(self, peer_keys: dict[str, bytes], *, max_payload_bytes: int = 65536) -> None:
        self._peer_keys = dict(peer_keys)
        self._replay = ReplayCache()
        self.max_payload_bytes = max_payload_bytes

    def verify_request(self, envelope: dict[str, Any], *, now: datetime) -> dict[str, Any]:
        if envelope.get("schemaVersion") != "1.0.0":
            raise IpcAuthenticationError("ipc_version", "Unsupported IPC version.")
        peer_id = str(envelope.get("peerId") or "")
        request_id = str(envelope.get("requestId") or "")
        key = self._peer_keys.get(peer_id)
        if key is None:
            raise IpcAuthenticationError("ipc_unknown_peer", "Peer is not registered.")
        if not request_id:
            raise IpcAuthenticationError("ipc_request_id", "Request id is required.")
        body = envelope.get("body")
        if len(canonical_message(body)) > self.max_payload_bytes:
            raise IpcAuthenticationError("ipc_payload_limit", "Payload exceeds the configured limit.")
        try:
            deadline = datetime.fromisoformat(str(envelope["deadline"]).replace("Z", "+00:00"))
        except (KeyError, ValueError) as error:
            raise IpcAuthenticationError("ipc_deadline", "Deadline is invalid.") from error
        if deadline.astimezone(timezone.utc) <= now.astimezone(timezone.utc):
            raise IpcAuthenticationError("ipc_expired", "Request deadline has passed.")
        expected = request_mac(key, envelope)
        supplied = str(envelope.get("mac") or "")
        if not hmac.compare_digest(expected, supplied):
            raise IpcAuthenticationError("ipc_auth_failed", "Request authentication failed.")
        self._replay.consume(peer_id, request_id)
        return {"peerId": peer_id, "requestId": request_id, "body": body}

    def server_proof(self, *, peer_id: str, request_id: str, response: Any) -> dict[str, Any]:
        key = self._peer_keys[peer_id]
        payload = {
            "schemaVersion": "1.0.0",
            "peerId": "worker",
            "requestId": request_id,
            "serverNonce": secrets.token_hex(16),
            "body": response,
        }
        payload["mac"] = request_mac(key, payload)
        return payload


class _Handler(socketserver.StreamRequestHandler):
    authenticator: LocalIpcAuthenticator

    def handle(self) -> None:
        raw = self.rfile.readline(self.authenticator.max_payload_bytes + 4096)
        try:
            envelope = json.loads(raw.decode("utf-8"))
            verified = self.authenticator.verify_request(
                envelope, now=datetime.now(timezone.utc)
            )
            response = self.authenticator.server_proof(
                peer_id=verified["peerId"],
                request_id=verified["requestId"],
                response={"accepted": True},
            )
        except (json.JSONDecodeError, UnicodeDecodeError, IpcAuthenticationError) as error:
            response = {
                "schemaVersion": "1.0.0",
                "accepted": False,
                "error": getattr(error, "code", "ipc_malformed"),
            }
        self.wfile.write(canonical_message(response) + b"\n")


def run_loopback_server(
    authenticator: LocalIpcAuthenticator,
) -> tuple[socketserver.ThreadingTCPServer, threading.Thread]:
    handler = type("AuthenticatedHandler", (_Handler,), {"authenticator": authenticator})
    server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def send_loopback_request(address: tuple[str, int], envelope: dict[str, Any]) -> dict[str, Any]:
    with socket.create_connection(address, timeout=3) as connection:
        connection.sendall(canonical_message(envelope) + b"\n")
        raw = b""
        while not raw.endswith(b"\n"):
            chunk = connection.recv(4096)
            if not chunk:
                break
            raw += chunk
    return json.loads(raw.decode("utf-8"))
