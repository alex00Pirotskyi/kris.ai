#!/usr/bin/env python3
"""One-use secret handles for Kristin sandboxed execution.

The broker intentionally keeps its implementation in the Python standard library so
it is available before Dart/Flutter are installed. Secret values are stored only in
0600 files under a temp-directory broker root and are consumed through an atomic
rename+delete flow so one logical handle cannot be reused.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import secrets as token_source
import stat
import sys
import tempfile
from typing import Any

BROKER_ROOT = Path(tempfile.gettempdir()) / "kristin-secret-broker"


class SecretBrokerError(RuntimeError):
    pass


class SecretExpiredError(SecretBrokerError):
    pass


class SecretHandleMissingError(SecretBrokerError):
    pass


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _expires_at(seconds: int) -> str:
    return (_utc_now() + dt.timedelta(seconds=max(1, seconds))).isoformat()


def _handle_path(handle: str) -> Path:
    safe = handle.strip()
    if not safe or "/" in safe or "\\" in safe:
        raise SecretBrokerError("invalid secret handle")
    return BROKER_ROOT / f"{safe}.json"


def _ensure_root() -> None:
    BROKER_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(BROKER_ROOT, 0o700)


def issue_secret(value: str, *, owner: str = "", ttl_seconds: int = 300, purpose: str = "") -> dict[str, Any]:
    _ensure_root()
    handle = f"sh_{token_source.token_urlsafe(24).rstrip('=')}"
    path = _handle_path(handle)
    payload = {
        "handle": handle,
        "owner": owner,
        "purpose": purpose,
        "createdAt": _utc_now().isoformat(),
        "expiresAt": _expires_at(ttl_seconds),
        "value": value,
    }
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle_file:
            handle_file.write(data)
            handle_file.flush()
            os.fsync(handle_file.fileno())
    finally:
        try:
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        except OSError:
            pass
    return {
        "handle": handle,
        "expiresAt": payload["expiresAt"],
        "owner": owner,
        "purpose": purpose,
    }


def consume_secret(handle: str, *, owner: str = "") -> str:
    _ensure_root()
    path = _handle_path(handle)
    if not path.exists():
        raise SecretHandleMissingError("secret handle is missing or already consumed")
    claimed = path.with_suffix(f".{os.getpid()}.claimed")
    try:
        os.replace(path, claimed)
    except FileNotFoundError as exc:
        raise SecretHandleMissingError("secret handle is missing or already consumed") from exc
    try:
        payload = json.loads(claimed.read_text(encoding="utf-8"))
        expected_owner = str(payload.get("owner", ""))
        if owner and expected_owner and owner != expected_owner:
            raise SecretBrokerError("secret handle owner mismatch")
        expires_raw = str(payload.get("expiresAt", ""))
        try:
            expires_at = dt.datetime.fromisoformat(expires_raw)
        except ValueError as exc:
            raise SecretBrokerError("secret handle metadata is corrupted") from exc
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=dt.timezone.utc)
        if expires_at <= _utc_now():
            raise SecretExpiredError("secret handle expired before consumption")
        value = payload.get("value")
        if not isinstance(value, str):
            raise SecretBrokerError("secret payload is missing its value")
        return value
    finally:
        try:
            claimed.unlink(missing_ok=True)
        except TypeError:
            if claimed.exists():
                claimed.unlink()


def broker_stats() -> dict[str, Any]:
    _ensure_root()
    total = 0
    expired = 0
    now = _utc_now()
    for path in BROKER_ROOT.glob("*.json"):
        total += 1
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            expires = dt.datetime.fromisoformat(str(payload.get("expiresAt", "")))
            if expires.tzinfo is None:
                expires = expires.replace(tzinfo=dt.timezone.utc)
            if expires <= now:
                expired += 1
        except Exception:
            expired += 1
    return {
        "root": str(BROKER_ROOT),
        "pendingHandles": total,
        "expiredHandles": expired,
    }


def purge_expired() -> int:
    _ensure_root()
    removed = 0
    now = _utc_now()
    for path in list(BROKER_ROOT.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            expires = dt.datetime.fromisoformat(str(payload.get("expiresAt", "")))
            if expires.tzinfo is None:
                expires = expires.replace(tzinfo=dt.timezone.utc)
            if expires <= now:
                path.unlink(missing_ok=True)
                removed += 1
        except Exception:
            path.unlink(missing_ok=True)
            removed += 1
    return removed


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kristin one-use secret broker")
    sub = parser.add_subparsers(dest="command")

    issue_parser = sub.add_parser("issue")
    issue_parser.add_argument("--owner", default="")
    issue_parser.add_argument("--purpose", default="")
    issue_parser.add_argument("--ttl", type=int, default=300)
    issue_parser.add_argument("--value")

    consume_parser = sub.add_parser("consume")
    consume_parser.add_argument("handle")
    consume_parser.add_argument("--owner", default="")

    sub.add_parser("stats")
    sub.add_parser("purge")

    args = parser.parse_args(argv)
    if args.command == "issue":
        value = args.value if args.value is not None else sys.stdin.read()
        print(json.dumps(issue_secret(value, owner=args.owner, ttl_seconds=args.ttl, purpose=args.purpose), indent=2, sort_keys=True))
        return 0
    if args.command == "consume":
        sys.stdout.write(consume_secret(args.handle, owner=args.owner))
        return 0
    if args.command == "stats":
        print(json.dumps(broker_stats(), indent=2, sort_keys=True))
        return 0
    if args.command == "purge":
        print(json.dumps({"removed": purge_expired()}, indent=2, sort_keys=True))
        return 0
    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
