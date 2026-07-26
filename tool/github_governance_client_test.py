#!/usr/bin/env python3
"""Behavioral tests for the guarded P0-006 GitHub governance client."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "tool" / "github_governance.py"
CONFIG = ROOT / "config" / "repository_governance.json"
TOKEN = "fixture-secret-must-never-appear"


class ApiState:
    def __init__(self) -> None:
        self.ruleset: dict[str, object] | None = None
        self.repository: dict[str, object] = {
            "default_branch": "main",
            "allow_merge_commit": True,
            "allow_squash_merge": True,
            "allow_rebase_merge": True,
            "delete_branch_on_merge": False,
            "allow_auto_merge": False,
        }
        self.labels: dict[str, dict[str, object]] = {}
        self.requests: list[dict[str, object]] = []


class MockHandler(BaseHTTPRequestHandler):
    server_version = "KristinGovernanceFixture/1.0"

    @property
    def state(self) -> ApiState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _body(self) -> dict[str, object]:
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        value = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(value, dict):
            raise AssertionError("request body must be an object")
        return value

    def _record(self, body: dict[str, object] | None = None) -> None:
        self.state.requests.append(
            {
                "method": self.command,
                "path": self.path,
                "authorizationPresent": bool(self.headers.get("Authorization")),
                "apiVersion": self.headers.get("X-GitHub-Api-Version"),
                "body": body,
            }
        )

    def _json(self, status: int, value: object) -> None:
        raw = json.dumps(value, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        self._record()
        if path == "/repos/owner/repo/rulesets":
            if self.state.ruleset is None:
                self._json(200, [])
            else:
                self._json(
                    200,
                    [
                        {
                            "id": self.state.ruleset["id"],
                            "name": self.state.ruleset["name"],
                            "enforcement": self.state.ruleset["enforcement"],
                        }
                    ],
                )
            return
        if path == "/repos/owner/repo/rulesets/101":
            self._json(200, self.state.ruleset or {"message": "missing"})
            return
        if path == "/repos/owner/repo":
            self._json(200, self.state.repository)
            return
        if path == "/repos/owner/repo/labels":
            self._json(200, list(self.state.labels.values()))
            return
        self._json(404, {"message": f"unknown GET {path}"})

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        body = self._body()
        self._record(body)
        if path == "/repos/owner/repo/rulesets":
            self.state.ruleset = {"id": 101, **body}
            self._json(201, self.state.ruleset)
            return
        if path == "/repos/owner/repo/labels":
            name = str(body["name"])
            value = {"id": len(self.state.labels) + 1, **body}
            self.state.labels[name] = value
            self._json(201, value)
            return
        self._json(404, {"message": f"unknown POST {path}"})

    def do_PUT(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        body = self._body()
        self._record(body)
        if path == "/repos/owner/repo/rulesets/101":
            self.state.ruleset = {"id": 101, **body}
            self._json(200, self.state.ruleset)
            return
        self._json(404, {"message": f"unknown PUT {path}"})

    def do_PATCH(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        body = self._body()
        self._record(body)
        if path == "/repos/owner/repo":
            self.state.repository.update(body)
            self._json(200, self.state.repository)
            return
        prefix = "/repos/owner/repo/labels/"
        if path.startswith(prefix):
            old_name = unquote(path[len(prefix) :])
            current = self.state.labels.pop(old_name, {"id": len(self.state.labels) + 1})
            new_name = str(body.get("new_name") or old_name)
            current.update({"name": new_name, "color": body.get("color"), "description": body.get("description")})
            self.state.labels[new_name] = current
            self._json(200, current)
            return
        self._json(404, {"message": f"unknown PATCH {path}"})


class MockServer:
    def __init__(self) -> None:
        self.state = ApiState()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), MockHandler)
        self.server.state = self.state  # type: ignore[attr-defined]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        host, port = self.server.server_address
        return f"http://{host}:{port}"

    def __enter__(self) -> "MockServer":
        self.thread.start()
        return self

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def matrix() -> dict[str, object]:
    commit = "a" * 40
    return {
        "schemaVersion": "1.0.0",
        "milestone": "P0-003",
        "status": "passed",
        "commit": commit,
        "workflowRunUrl": "https://github.example/actions/runs/1",
        "lanes": {
            lane: {
                "status": "passed",
                "nativeBuild": "passed",
                "checkName": f"validate-{lane}",
                "jobUrl": f"https://github.example/actions/jobs/{index}",
                "environmentEvidence": f"release/evidence/P0-003/ci-environment-{lane}.json",
            }
            for index, lane in enumerate(("ubuntu", "windows", "macos"), 1)
        },
    }


class GovernanceClientTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="kristin-p0-006-client-")
        self.project = Path(self.temporary.name)
        (self.project / "tool").mkdir(parents=True)
        (self.project / "config").mkdir(parents=True)
        (self.project / "release/evidence/P0-003").mkdir(parents=True)
        shutil.copy2(CLIENT, self.project / "tool/github_governance.py")
        shutil.copy2(CONFIG, self.project / "config/repository_governance.json")
        (self.project / "release/evidence/P0-003/ci_matrix.json").write_text(
            json.dumps(matrix(), indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_client(self, *arguments: str, token: bool = False) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ)
        if token:
            env["TEST_GITHUB_TOKEN"] = TOKEN
        else:
            env.pop("TEST_GITHUB_TOKEN", None)
        return subprocess.run(
            [
                sys.executable,
                str(self.project / "tool/github_governance.py"),
                "--project",
                str(self.project),
                "--repository",
                "owner/repo",
                "--token-env",
                "TEST_GITHUB_TOKEN",
                *arguments,
            ],
            cwd=self.project,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=30,
        )

    def test_plan_requires_no_token_and_discloses_no_secret(self) -> None:
        result = self.run_client("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["milestone"], "P0-006")
        self.assertFalse(payload["tokenPersisted"])
        self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_apply_requires_solo_maintainer_confirmation(self) -> None:
        with MockServer() as server:
            result = self.run_client("--apply", "--api-base", server.base_url, token=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("confirm-solo-maintainer", result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)


    def test_verify_detects_remote_governance_drift(self) -> None:
        with MockServer() as server:
            applied = self.run_client(
                "--apply",
                "--confirm-solo-maintainer",
                "--api-base",
                server.base_url,
                token=True,
            )
            self.assertEqual(applied.returncode, 0, applied.stderr)
            pull_rule = next(
                rule
                for rule in server.state.ruleset["rules"]  # type: ignore[index]
                if rule["type"] == "pull_request"
            )
            pull_rule["parameters"]["required_review_thread_resolution"] = False
            verify = self.run_client("--verify", "--api-base", server.base_url, token=True)
            self.assertEqual(verify.returncode, 2)
            self.assertIn("required_review_thread_resolution", verify.stderr)
            self.assertNotIn(TOKEN, verify.stdout + verify.stderr)

    def test_apply_verify_and_repeat_are_idempotent_and_redacted(self) -> None:
        with MockServer() as server:
            first = self.run_client(
                "--apply",
                "--confirm-solo-maintainer",
                "--api-base",
                server.base_url,
                token=True,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            receipt = self.project / "release/evidence/P0-006/github_governance_receipt.json"
            self.assertTrue(receipt.is_file())
            first_receipt = receipt.read_text(encoding="utf-8")
            self.assertNotIn(TOKEN, first.stdout + first.stderr + first_receipt)
            self.assertEqual(server.state.ruleset["enforcement"], "active")  # type: ignore[index]
            self.assertEqual(len(server.state.labels), 8)

            verify = self.run_client("--verify", "--api-base", server.base_url, token=True)
            self.assertEqual(verify.returncode, 0, verify.stderr)
            self.assertNotIn(TOKEN, verify.stdout + verify.stderr + receipt.read_text(encoding="utf-8"))

            second = self.run_client(
                "--apply",
                "--confirm-solo-maintainer",
                "--api-base",
                server.base_url,
                token=True,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(len(server.state.labels), 8)
            self.assertEqual(
                [item["context"] for item in next(
                    rule["parameters"]["required_status_checks"]
                    for rule in server.state.ruleset["rules"]  # type: ignore[index]
                    if rule["type"] == "required_status_checks"
                )],
                ["validate-ubuntu", "validate-windows", "validate-macos"],
            )
            self.assertNotIn(TOKEN, second.stdout + second.stderr + receipt.read_text(encoding="utf-8"))

            self.assertTrue(server.state.requests)
            self.assertTrue(all(item["authorizationPresent"] for item in server.state.requests))
            self.assertTrue(all(item["apiVersion"] == "2026-03-10" for item in server.state.requests))


if __name__ == "__main__":
    unittest.main(verbosity=2)
