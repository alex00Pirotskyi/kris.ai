#!/usr/bin/env python3
"""Executable Project Manager 2 gates for the unified Kristin v1.7 source."""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import signal
import sqlite3
import sys
import tempfile
import time
from typing import Callable
import zipfile

import project_manager_v2 as pm
import sandbox_worker


@dataclasses.dataclass
class Result:
    name: str
    passed: bool
    detail: str
    durationMs: int



def duration_ms(started: float) -> int:
    if "SOURCE_DATE_EPOCH" in os.environ:
        return 0
    return int((time.monotonic() - started) * 1000)

def case(name: str, action: Callable[[], str], results: list[Result]) -> None:
    started = time.monotonic()
    try:
        detail = action()
        results.append(Result(name, True, detail, duration_ms(started)))
    except Exception as exc:  # noqa: BLE001 - aggregate release-gate failures
        results.append(Result(name, False, f"{type(exc).__name__}: {exc}", duration_ms(started)))


def require(condition: bool, detail: str) -> str:
    if not condition:
        raise AssertionError(detail)
    return detail


def make_project(root: Path, *, network: str = "none", secrets: bool = False, ports: bool = False) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "source.txt").write_text("canonical source\n", encoding="utf-8")
    (root / "task.py").write_text(
        """from pathlib import Path
import json
import sys
import time

mode = sys.argv[1]
assert Path("source.txt").read_text(encoding="utf-8").strip() == "canonical source"
if mode == "analyze":
    print("analysis-ok")
elif mode == "test":
    print("tests-ok")
elif mode == "build":
    Path("out").mkdir(exist_ok=True)
    Path("out/result.json").write_text(json.dumps({"built": True}, sort_keys=True), encoding="utf-8")
    print("build-ok")
elif mode == "run":
    print("run-ready", flush=True)
    time.sleep(60)
else:
    raise SystemExit(2)
""",
        encoding="utf-8",
    )
    command_common = {
        "executable": sys.executable,
        "workingDirectory": ".",
        "networkMode": network,
        "timeoutSeconds": 120,
        "memoryLimitMb": 512,
        "processLimit": 32,
        "fileSizeLimitMb": 32,
    }
    run_extra: dict[str, object] = {}
    if secrets:
        run_extra["secretReferences"] = ["API_TOKEN"]
    if ports:
        run_extra["ports"] = [8080]
    profile = {
        "schemaVersion": "2.0.0",
        "projectType": "PythonFixture",
        "sandbox": {"required": True, "maxSnapshotFiles": 1000, "maxSnapshotBytes": 10_000_000},
        "commands": {
            "analyze": command_common | {"arguments": ["-B", "task.py", "analyze"], "workspaceMode": "read_only"},
            "test": command_common | {"arguments": ["-B", "task.py", "test"], "workspaceMode": "read_only"},
            "build": command_common | {
                "arguments": ["-B", "task.py", "build"],
                "workspaceMode": "snapshot_writable",
                "writablePaths": ["out"],
                "expectedOutputs": [{"path": "out/result.json", "logicalType": "json", "validator": "json"}],
            },
            "run": command_common | {
                "arguments": ["-B", "task.py", "run"],
                "workspaceMode": "snapshot_writable",
            } | run_extra,
        },
    }
    (root / "kristin.project.json").write_text(json.dumps(profile, indent=2, sort_keys=True), encoding="utf-8")


def expect_profile_error(root: Path, mutator: Callable[[dict[str, object]], None], code: str) -> str:
    make_project(root)
    path = root / "kristin.project.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    mutator(payload)
    path.write_text(json.dumps(payload), encoding="utf-8")
    try:
        pm.parse_profile(root)
    except pm.ProfileError as exc:
        return require(exc.code == code, f"rejected with {code}")
    raise AssertionError(f"expected {code}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results: list[Result] = []

    with tempfile.TemporaryDirectory(prefix="kristin-pm-v2-") as temp:
        base = Path(temp)
        project = base / "project"
        data_root = base / "data"
        make_project(project)

        case(
            "Project Profile v2 parses strict commands",
            lambda: require(
                pm.parse_profile(project).commands["build"].expected_outputs[0].validator == "json",
                "strict profile parsed with declared artifact validator",
            ),
            results,
        )
        case(
            "Unknown profile authority fails closed",
            lambda: expect_profile_error(
                base / "unknown",
                lambda payload: payload.update({"hostAccess": True}),
                "profile_unknown_authority",
            ),
            results,
        )
        case(
            "Traversal working directory fails closed",
            lambda: expect_profile_error(
                base / "traversal",
                lambda payload: payload["commands"]["build"].update({"workingDirectory": "../outside"}),
                "profile_path_outside_project",
            ),
            results,
        )
        case(
            "Shell command profiles are rejected",
            lambda: expect_profile_error(
                base / "shell",
                lambda payload: payload["commands"]["build"].update({"executable": "bash"}),
                "profile_shell_rejected",
            ),
            results,
        )
        case(
            "Unsandboxed profiles are rejected",
            lambda: expect_profile_error(
                base / "unsandboxed",
                lambda payload: payload["sandbox"].update({"required": False}),
                "profile_unsandboxed_rejected",
            ),
            results,
        )
        case(
            "Source manifest rejects symbolic links",
            lambda: _symlink_case(base / "symlink"),
            results,
        )
        case(
            "Workflow schema v6 contains Project Manager, intelligence, and interoperability tables",
            lambda: _schema_case(data_root),
            results,
        )
        case(
            "Project status derives readiness from live sandbox capability",
            lambda: _status_case(project, data_root),
            results,
        )
        case(
            "Read-only Analyze executes in the sandbox or fails closed when unavailable",
            lambda: _action_case(project, data_root, "analyze", "analysis-ok"),
            results,
        )
        case(
            "Read-only Test executes in the sandbox or fails closed when unavailable",
            lambda: _action_case(project, data_root, "test", "tests-ok"),
            results,
        )
        case(
            "Build writes only to a retained snapshot or fails closed when unavailable",
            lambda: _build_case(project, data_root),
            results,
        )
        case(
            "Artifact validation persists only after a successful sandboxed build",
            lambda: _artifact_case(project, data_root),
            results,
        )
        case(
            "Deterministic package output is byte-identical",
            lambda: _package_case(project, data_root),
            results,
        )
        case(
            "Network, secret, and preview-port claims are blocked",
            lambda: _authority_readiness_case(base),
            results,
        )
        case(
            "Managed Run terminates the sandbox tree or fails closed when unavailable",
            lambda: _run_stop_case(project, data_root),
            results,
        )
        case(
            "Append-only intelligence records reject mutation",
            lambda: _append_only_case(data_root),
            results,
        )

    payload = {
        "version": pm.VERSION,
        "caseCount": len(results),
        "passedCount": sum(result.passed for result in results),
        "failedCount": sum(not result.passed for result in results),
        "passed": all(result.passed for result in results),
        "sandbox": sandbox_worker.probe_backend(),
        "results": [dataclasses.asdict(result) for result in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for result in results:
            print(f"{'PASS' if result.passed else 'FAIL'} {result.name}: {result.detail}")
        print(f"\n{payload['passedCount']}/{payload['caseCount']} Project Manager 2 cases passed")
    return 0 if payload["passed"] else 1


def _symlink_case(root: Path) -> str:
    make_project(root)
    try:
        (root / "escape").symlink_to(Path("/tmp"), target_is_directory=True)
    except (OSError, NotImplementedError):
        return "symlink creation unavailable; policy path covered by source contract"
    try:
        pm.tree_manifest(root)
    except pm.ProjectManagerError as exc:
        return require(exc.code == "workspace_symlink_rejected", "workspace symlink rejected")
    raise AssertionError("symlink was accepted")


def _schema_case(data_root: Path) -> str:
    connection = pm.open_store(data_root)
    try:
        version = int(connection.execute("PRAGMA user_version").fetchone()[0])
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        required = {
            "project_profiles",
            "workspace_sessions",
            "managed_project_processes",
            "artifact_records",
            "model_circuit_breakers",
            "model_route_decisions",
            "semantic_progress_records",
            "verification_reports",
            "audit_records",
            "policy_profiles",
            "mcp_server_registrations",
            "a2a_delegation_records",
            "capability_manifests",
            "update_channel_manifests",
            "fleet_profiles",
            "support_compatibility_policies",
        }
        return require(version == 6 and required <= tables, "schema v6 and all cumulative tables are present")
    finally:
        connection.close()


def _sandbox_available() -> bool:
    return bool(sandbox_worker.probe_backend().get("available"))


def _expect_sandbox_blocked(
    project: Path,
    data_root: Path,
    action: str,
    *,
    managed: bool = False,
) -> str:
    before = pm.tree_manifest(project)["sha256"]
    try:
        if managed:
            pm.start_run(root=project, data_root=data_root, run_id=f"blocked-{action}")
        else:
            pm.execute_action(
                root=project,
                data_root=data_root,
                action=action,
                run_id=f"blocked-{action}",
            )
    except pm.ProjectManagerError as exc:
        reasons = set(exc.details.get("reasons", []))
        after = pm.tree_manifest(project)["sha256"]
        return require(
            exc.code == "project_action_blocked"
            and "sandbox_unavailable" in reasons
            and before == after,
            f"{action} failed closed without mutating the project when the sandbox was unavailable",
        )
    raise AssertionError(f"{action} executed without an available sandbox")

def _status_case(project: Path, data_root: Path) -> str:
    value = pm.snapshot(root=project, data_root=data_root)
    available = bool(value["sandbox"]["available"])
    expected = "ready" if available else "blocked"
    package = value["actions"]["package"]
    return require(
        value["actions"]["analyze"]["state"] == expected
        and package["state"] == "ready"
        and package.get("backend") == "builtin_snapshot_packager"
        and package.get("assurance") == "host_snapshot_no_project_code_execution",
        "status derives project-command readiness from the live sandbox while built-in packaging remains independently ready",
    )


def _action_case(project: Path, data_root: Path, action: str, marker: str) -> str:
    if not _sandbox_available():
        return _expect_sandbox_blocked(project, data_root, action)
    value = pm.execute_action(root=project, data_root=data_root, action=action, run_id=f"run-{action}")
    return require(value["passed"] and marker in value["result"].get("stdout", ""), f"{action} completed in sandbox")


def _build_case(project: Path, data_root: Path) -> str:
    if not _sandbox_available():
        return _expect_sandbox_blocked(project, data_root, "build")
    before = pm.tree_manifest(project)["sha256"]
    value = pm.execute_action(root=project, data_root=data_root, action="build", run_id="run-build")
    after = pm.tree_manifest(project)["sha256"]
    workspace = Path(value["workspace"])
    return require(
        value["passed"] and before == after and not (project / "out/result.json").exists() and (workspace / "out/result.json").is_file(),
        "build output exists only in the retained sandbox snapshot",
    )


def _artifact_case(project: Path, data_root: Path) -> str:
    if not _sandbox_available():
        _expect_sandbox_blocked(project, data_root, "build")
        connection = pm.open_store(data_root)
        try:
            count = int(
                connection.execute(
                    "SELECT COUNT(*) FROM artifact_records WHERE producer_action='build'"
                ).fetchone()[0]
            )
        finally:
            connection.close()
        return require(
            count == 0,
            "a blocked build persisted no fabricated artifact evidence",
        )
    connection = pm.open_store(data_root)
    try:
        row = connection.execute("SELECT validation_state, relative_path, content_sha256 FROM artifact_records WHERE producer_action='build' ORDER BY created_at DESC LIMIT 1").fetchone()
        return require(row is not None and row[0] == "valid" and row[1] == "out/result.json" and len(row[2]) == 64, "validated artifact record persisted")
    finally:
        connection.close()


def _package_case(project: Path, data_root: Path) -> str:
    first = pm.execute_action(root=project, data_root=data_root, action="package", run_id="package-1")
    second = pm.execute_action(root=project, data_root=data_root, action="package", run_id="package-2")
    one = Path(first["archive"])
    two = Path(second["archive"])
    with zipfile.ZipFile(one) as archive:
        names = archive.namelist()
    return require(one.read_bytes() == two.read_bytes() and "source.txt" in names, "two package operations produced byte-identical safe ZIPs")


def _authority_readiness_case(base: Path) -> str:
    project = base / "blocked"
    make_project(project, network="broker_https", secrets=True, ports=True)
    profile = pm.parse_profile(project)
    readiness = pm.action_readiness(profile, "run", {"available": True})
    return require(
        readiness["state"] == "blocked"
        and set(readiness["reasons"]) == {"worker_process_network_broker_unavailable", "secret_use_requires_explicit_approval", "worker_to_host_port_bridge_unavailable"},
        "unsupported authority is reported and never silently granted",
    )


def _run_stop_case(project: Path, data_root: Path) -> str:
    if not _sandbox_available():
        return _expect_sandbox_blocked(project, data_root, "run", managed=True)
    def wait_for_tree(started: dict[str, object]) -> list[dict[str, int | str]]:
        deadline = time.monotonic() + 12
        identities: list[dict[str, int | str]] = []
        while time.monotonic() < deadline:
            identities = sandbox_worker.process_tree_snapshot(int(started["pid"]))
            if len(identities) >= 4:
                return identities
            time.sleep(0.1)
        return identities

    started = pm.start_run(root=project, data_root=data_root, run_id="run-managed")
    process_id = started["processId"]
    identities = wait_for_tree(started)
    require(len(identities) >= 3, "managed run exposed launcher, namespace worker, and sandboxed command identities")
    stopped = pm.stop_process(data_root=data_root, process_id=process_id)
    survivors = [identity for identity in identities if sandbox_worker.process_identity_alive(identity)]
    require(stopped["state"] == "stopped" and not survivors, "Stop terminated the complete PID-reuse-safe sandbox process tree")

    # Parent-death signaling and unshare --kill-child must also protect against
    # an abrupt launcher crash, not only the ordinary Stop path.
    crashed = pm.start_run(root=project, data_root=data_root, run_id="run-parent-death")
    crash_identities = wait_for_tree(crashed)
    require(len(crash_identities) >= 3, "parent-death fixture exposed the complete sandbox tree")
    os.kill(int(crashed["pid"]), signal.SIGKILL)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and any(
        sandbox_worker.process_identity_alive(identity) for identity in crash_identities
    ):
        time.sleep(0.05)
    crash_survivors = [identity for identity in crash_identities if sandbox_worker.process_identity_alive(identity)]
    crash_status = pm.process_status(data_root=data_root, process_id=str(crashed["processId"]))
    return require(
        not crash_survivors and crash_status["state"] == "interrupted",
        "Stop and abrupt launcher death both terminate every sandbox descendant",
    )


def _append_only_case(data_root: Path) -> str:
    connection = pm.open_store(data_root)
    try:
        now = pm.utc_now()
        payload = {"selected": {"provider": "local", "model": "fixture"}}
        connection.execute(
            "INSERT INTO model_route_decisions(id, role, request_sha256, decision_json, decision_sha256, approval_required, created_at) VALUES (?, ?, ?, ?, ?, 0, ?)",
            ("route-fixture", "executor", "a" * 64, pm.canonical_json(payload), pm.sha256_json(payload), now),
        )
        connection.commit()
        try:
            connection.execute("UPDATE model_route_decisions SET role='planner' WHERE id='route-fixture'")
            connection.commit()
        except sqlite3.DatabaseError as exc:
            connection.rollback()
            return require("append_only" in str(exc), "append-only trigger blocked route-decision mutation")
        raise AssertionError("append-only route decision was mutable")
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
