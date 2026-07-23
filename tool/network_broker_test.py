#!/usr/bin/env python3
"""Deterministic policy gate for the HTTPS network broker."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path

import network_broker


@dataclass
class Result:
    name: str
    status: str
    detail: str


class Gate:
    def __init__(self) -> None:
        self.results: list[Result] = []

    def check(self, name: str, callback) -> None:
        try:
            detail = callback()
        except Exception as exc:  # noqa: BLE001 - deterministic gate must capture failures
            self.results.append(Result(name, "failed", f"{type(exc).__name__}: {exc}"))
        else:
            self.results.append(Result(name, "passed", detail))

    @property
    def passed(self) -> bool:
        return all(item.status == "passed" for item in self.results)


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _expects_error(text: str, callback) -> str:
    try:
        callback()
    except network_broker.NetworkBrokerError as exc:
        _assert(text in str(exc), str(exc))
        return str(exc)
    raise AssertionError("expected NetworkBrokerError")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    gate = Gate()
    gate.check(
        "HTTPS-only policy",
        lambda: _expects_error(
            "https URLs",
            lambda: network_broker.fetch_https("http://example.com"),
        ),
    )
    gate.check(
        "Reject URL credentials",
        lambda: _expects_error(
            "embedded URL credentials",
            lambda: network_broker.fetch_https("https://user:pass@example.com/"),
        ),
    )
    gate.check(
        "Reject non-443 ports",
        lambda: _expects_error(
            "port 443",
            lambda: network_broker.fetch_https("https://example.com:444/"),
        ),
    )
    gate.check(
        "Reject localhost resolution",
        lambda: _expects_error(
            "private, loopback",
            lambda: network_broker.fetch_https("https://127.0.0.1/"),
        ),
    )
    gate.check(
        "Allowlist enforcement",
        lambda: _expects_error(
            "allowlist",
            lambda: network_broker.fetch_https("https://example.com/", allow_hosts=["openai.com"]),
        ),
    )
    gate.check(
        "Private DNS helper rejection",
        lambda: _expects_error(
            "private, loopback",
            lambda: network_broker.resolve_public_addresses("localhost"),
        ),
    )

    payload = {
        "version": "1.9.0+190",
        "passed": gate.passed,
        "results": [asdict(item) for item in gate.results],
    }
    if args.json_output:
        Path(args.json_output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    else:
        print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if gate.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
