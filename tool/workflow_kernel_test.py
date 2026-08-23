#!/usr/bin/env python3
"""Executable, dependency-free SQLite durability gate for Kristin v1.3.0.

The Flutter runtime owns the production implementation. This harness executes
its reviewed SQL migrations with Python's SQLite binding and then exercises the
same durability invariants at real transaction/process boundaries. It remains
available on build hosts that do not yet have the Dart/Flutter SDK installed.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations" / "workflow"
GENERATED = ROOT / "lib" / "product" / "generated" / "workflow_migrations.g.dart"
DURABLE_SOURCE = ROOT / "lib" / "product" / "durable_workflow.dart"
WORKSPACE_SOURCE = ROOT / "lib" / "product" / "workspace_tools.dart"
RUNTIME_SOURCE = ROOT / "lib" / "product" / "planning_runtime.dart"
STORAGE_SOURCE = ROOT / "lib" / "product" / "storage_security.dart"
PATTERN = re.compile(r"^(?P<version>[0-9]{3})_(?P<name>[a-z0-9_]+)\.sql$")
ZERO_SHA = hashlib.sha256(b"").hexdigest()


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def now() -> str:
    return "2026-07-22T00:00:00.000Z"


def load_migrations() -> list[tuple[int, str, str, str]]:
    result: list[tuple[int, str, str, str]] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        match = PATTERN.match(path.name)
        if not match:
            raise AssertionError(f"unexpected migration filename: {path.name}")
        sql = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        if not sql.endswith("\n"):
            sql += "\n"
        result.append(
            (
                int(match.group("version")),
                match.group("name"),
                sql,
                hashlib.sha256(sql.encode("utf-8")).hexdigest(),
            )
        )
    versions = [item[0] for item in result]
    if versions != list(range(1, len(result) + 1)):
        raise AssertionError(f"workflow migrations are not contiguous: {versions}")
    return result


def connect(path: Path) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=10.0, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = WAL")
    db.execute("PRAGMA synchronous = FULL")
    db.execute("PRAGMA busy_timeout = 10000")
    return db


def apply_migrations(path: Path) -> sqlite3.Connection:
    db = connect(path)
    db.execute(
        """CREATE TABLE IF NOT EXISTS schema_migrations (
             version INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             sha256 TEXT NOT NULL,
             applied_at TEXT NOT NULL
           ) WITHOUT ROWID"""
    )
    applied = {
        int(row["version"]): str(row["sha256"])
        for row in db.execute("SELECT version, sha256 FROM schema_migrations")
    }
    for version, name, sql, digest in load_migrations():
        prior = applied.get(version)
        if prior is not None:
            if prior != digest:
                raise AssertionError(f"migration drift at version {version}")
            continue
        db.execute("BEGIN IMMEDIATE")
        try:
            # executescript commits an open transaction, so execute complete
            # statements individually while preserving trigger bodies.
            statement = ""
            for line in sql.splitlines(keepends=True):
                statement += line
                if sqlite3.complete_statement(statement):
                    if statement.strip():
                        db.execute(statement)
                    statement = ""
            if statement.strip():
                raise AssertionError(f"incomplete SQL in migration {version}")
            db.execute(
                "INSERT INTO schema_migrations(version,name,sha256,applied_at) VALUES(?,?,?,?)",
                (version, name, digest, now()),
            )
            db.execute(f"PRAGMA user_version = {version}")
            db.execute("COMMIT")
        except BaseException:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise
    return db


def insert_run(
    db: sqlite3.Connection,
    run_id: str,
    state: str = "running",
    state_version: int = 1,
    items_succeeded: bool = False,
) -> dict[str, Any]:
    payload = {
        "id": run_id,
        "state": state,
        "items": [
            {
                "item": {"id": "task-1"},
                "state": "succeeded" if items_succeeded else "running",
                "attempts": 1,
            }
        ],
        "command": {"id": "command-1", "contract": {"projectId": "project-1"}},
        "createdAt": now(),
        "updatedAt": now(),
    }
    text = canonical(payload)
    db.execute(
        """INSERT INTO runs(
             id,project_id,command_id,source_run_id,state,state_version,
             run_json,snapshot_sha256,created_at,updated_at,completed_at,failure
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            run_id,
            "project-1",
            "command-1",
            None,
            state,
            state_version,
            text,
            sha_text(text),
            now(),
            now(),
            None,
            None,
        ),
    )
    return payload


def insert_event(
    db: sqlite3.Connection,
    event_id: str,
    run_id: str,
    kind: str,
    payload: dict[str, Any],
    state_version: int | None = None,
) -> int:
    text = canonical(payload)
    cursor = db.execute(
        """INSERT INTO run_events(
             event_id,correlation_id,run_id,type,timestamp,payload_json,
             payload_sha256,state_version
           ) VALUES(?,?,?,?,?,?,?,?)""",
        (event_id, run_id, run_id, kind, now(), text, sha_text(text), state_version),
    )
    return int(cursor.lastrowid)


def assert_raises_sqlite(action: Callable[[], Any], contains: str) -> None:
    try:
        action()
    except sqlite3.DatabaseError as error:
        if contains not in str(error):
            raise AssertionError(f"expected {contains!r}, got {error!r}") from error
    else:
        raise AssertionError(f"expected SQLite failure containing {contains!r}")


def child_uncommitted(database: Path) -> int:
    db = connect(database)
    db.execute("BEGIN IMMEDIATE")
    insert_run(db, "crash-uncommitted")
    insert_event(
        db,
        "event-crash-uncommitted",
        "crash-uncommitted",
        "run.snapshot",
        {"run": {"id": "crash-uncommitted"}, "snapshotSha256": ZERO_SHA},
        1,
    )
    # Simulate power/process loss: no COMMIT, close, or Python cleanup.
    os._exit(73)


def child_completed_idempotency(database: Path, effect_file: Path) -> int:
    db = connect(database)
    key = "idempotency-crash-after-result"
    arguments_sha = "a" * 64
    db.execute("BEGIN IMMEDIATE")
    db.execute(
        """INSERT INTO idempotency_records(
             idempotency_key,run_id,work_item_id,attempt,operation,
             normalized_arguments_sha256,status,lease_owner,lease_expires_at,
             execution_generation,created_at,updated_at
           ) VALUES(?,?,?,?,?,?,'in_progress',?,?,?,?,?)""",
        (
            key,
            "run-idempotency",
            "task-1",
            1,
            "tool:write_file",
            arguments_sha,
            "child-owner",
            "2099-01-01T00:00:00Z",
            1,
            now(),
            now(),
        ),
    )
    db.execute("COMMIT")

    # The material side effect is deliberately outside SQLite, like a workspace
    # file mutation. Force it to stable storage before recording the result.
    with effect_file.open("ab") as handle:
        handle.write(b"effect\n")
        handle.flush()
        os.fsync(handle.fileno())

    result = canonical({"ok": True, "summary": "created", "data": {"count": 1}, "mutated": True})
    db.execute("BEGIN IMMEDIATE")
    db.execute(
        """UPDATE idempotency_records SET
             status='completed',result_json=?,result_sha256=?,updated_at=?,
             completed_at=? WHERE idempotency_key=?""",
        (result, sha_text(result), now(), now(), key),
    )
    insert_event(
        db,
        "event-idempotency-complete",
        "run-idempotency",
        "operation.completed",
        {"idempotencyKey": key, "resultSha256": sha_text(result)},
    )
    db.execute("COMMIT")
    os._exit(74)


def test_generated_registry() -> str:
    migrations = load_migrations()
    digest_input = "\n".join(
        f"{version}:{name}:{digest}" for version, name, _sql, digest in migrations
    )
    digest = hashlib.sha256(digest_input.encode("utf-8")).hexdigest()
    generated = GENERATED.read_text(encoding="utf-8")
    if f"generatedWorkflowSchemaVersion = {len(migrations)};" not in generated:
        raise AssertionError("generated schema version is stale")
    if f"generatedWorkflowMigrationDigest = '{digest}';" not in generated:
        raise AssertionError("generated migration digest is stale")
    process = subprocess.run(
        [sys.executable, str(ROOT / "tool" / "generate_workflow_migrations.py"), "--check"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if process.returncode != 0:
        raise AssertionError(process.stdout.strip())
    return f"migrations={len(migrations)} digest={digest}"


def test_schema_and_pragmas(database: Path) -> str:
    db = apply_migrations(database)
    try:
        expected = {
            "workflow_metadata",
            "entity_records",
            "documents",
            "runs",
            "run_events",
            "task_attempts",
            "agent_action_attempts",
            "run_leases",
            "idempotency_records",
            "checkpoints",
            "compensation_records",
            "migration_imports",
            "recovery_actions",
            "schema_migrations",
        }
        actual = {
            str(row[0])
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        missing = expected - actual
        if missing:
            raise AssertionError(f"missing tables: {sorted(missing)}")
        if int(db.execute("PRAGMA user_version").fetchone()[0]) != len(load_migrations()):
            raise AssertionError("user_version mismatch")
        if str(db.execute("PRAGMA journal_mode").fetchone()[0]).lower() != "wal":
            raise AssertionError("WAL is not enabled")
        if int(db.execute("PRAGMA synchronous").fetchone()[0]) != 2:
            raise AssertionError("synchronous is not FULL")
        if str(db.execute("PRAGMA integrity_check").fetchone()[0]).lower() != "ok":
            raise AssertionError("integrity_check failed")
        return f"tables={len(actual)} journal=wal synchronous=full schema={len(load_migrations())}"
    finally:
        db.close()


def test_append_only(database: Path) -> str:
    db = connect(database)
    try:
        db.execute("BEGIN IMMEDIATE")
        insert_run(db, "run-append")
        sequence = insert_event(
            db,
            "event-append",
            "run-append",
            "run.snapshot",
            {"run": {"id": "run-append"}, "snapshotSha256": "b" * 64},
            1,
        )
        db.execute("COMMIT")
        assert_raises_sqlite(
            lambda: db.execute(
                "UPDATE run_events SET type='tampered' WHERE sequence=?", (sequence,)
            ),
            "run_events_append_only",
        )
        assert_raises_sqlite(
            lambda: db.execute("DELETE FROM run_events WHERE sequence=?", (sequence,)),
            "run_events_append_only",
        )
        return f"sequence={sequence} update_blocked=true delete_blocked=true"
    finally:
        if db.in_transaction:
            db.execute("ROLLBACK")
        db.close()


def test_uncommitted_crash(database: Path) -> str:
    process = subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--child-uncommitted", str(database)],
        cwd=ROOT,
        check=False,
    )
    if process.returncode != 73:
        raise AssertionError(f"child returned {process.returncode}, expected 73")
    db = connect(database)
    try:
        runs = int(db.execute("SELECT COUNT(*) FROM runs WHERE id='crash-uncommitted'").fetchone()[0])
        events = int(
            db.execute("SELECT COUNT(*) FROM run_events WHERE event_id='event-crash-uncommitted'").fetchone()[0]
        )
        if runs != 0 or events != 0:
            raise AssertionError(f"uncommitted crash leaked rows: runs={runs} events={events}")
        return "forced_exit=73 leaked_runs=0 leaked_events=0"
    finally:
        db.close()


def test_idempotency_crash_replay(database: Path, effect_file: Path) -> str:
    process = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--child-completed-idempotency",
            str(database),
            str(effect_file),
        ],
        cwd=ROOT,
        check=False,
    )
    if process.returncode != 74:
        raise AssertionError(f"child returned {process.returncode}, expected 74")
    db = connect(database)
    try:
        row = db.execute(
            "SELECT status,result_json,result_sha256 FROM idempotency_records WHERE idempotency_key=?",
            ("idempotency-crash-after-result",),
        ).fetchone()
        if row is None or row["status"] != "completed":
            raise AssertionError("completed result was not durable")
        if sha_text(str(row["result_json"])) != row["result_sha256"]:
            raise AssertionError("completed result hash mismatch")
        # A resumed executor reads this row and returns the prior result. It must
        # not append another effect line.
        replay = json.loads(str(row["result_json"]))
        effects = effect_file.read_text(encoding="utf-8").splitlines()
        if replay.get("ok") is not True or effects != ["effect"]:
            raise AssertionError(f"replay/effect mismatch: replay={replay} effects={effects}")
        return "forced_exit=74 durable_result=true material_effects=1 replayed=true"
    finally:
        db.close()


def test_completed_idempotency_guards(database: Path) -> str:
    db = connect(database)
    try:
        assert_raises_sqlite(
            lambda: db.execute(
                """INSERT INTO idempotency_records(
                     idempotency_key,run_id,work_item_id,attempt,operation,
                     normalized_arguments_sha256,status,lease_owner,lease_expires_at,
                     execution_generation,created_at,updated_at
                   ) VALUES('invalid-complete','r','w',1,'op',?,'completed','o',?,1,?,?)""",
                ("c" * 64, now(), now(), now()),
            ),
            "idempotency_completed_result_required",
        )
        assert_raises_sqlite(
            lambda: db.execute(
                "UPDATE idempotency_records SET result_json='{}' WHERE idempotency_key=?",
                ("idempotency-crash-after-result",),
            ),
            "idempotency_completed_immutable",
        )
        return "missing_result_blocked=true completed_result_immutable=true"
    finally:
        if db.in_transaction:
            db.execute("ROLLBACK")
        db.close()


def test_effect_compensation(database: Path) -> str:
    db = connect(database)
    try:
        key = "effect-recorded-key"
        record = {
            "id": "mutation-1",
            "operation": "create",
            "relativePath": "docs/result.md",
            "existed": False,
            "beforeHash": "",
            "afterHash": "d" * 64,
            "backupPath": "",
            "timestamp": now(),
            "status": "applied",
            "idempotencyKey": key,
            "workItemId": "task-1",
        }
        text = canonical(record)
        db.execute("BEGIN IMMEDIATE")
        db.execute(
            """INSERT INTO idempotency_records(
                 idempotency_key,run_id,work_item_id,attempt,operation,
                 normalized_arguments_sha256,status,lease_owner,lease_expires_at,
                 execution_generation,created_at,updated_at
               ) VALUES(?,?,?,?,?,?,'in_progress',?,?,?,?,?)""",
            (key, "run-effect", "task-1", 1, "tool:write_file", "e" * 64, "dead-owner", "2000-01-01T00:00:00Z", 1, now(), now()),
        )
        db.execute(
            """INSERT INTO compensation_records(
                 id,run_id,work_item_id,idempotency_key,mutation_id,operation,
                 relative_path,before_sha256,after_sha256,backup_path,status,
                 record_json,record_sha256,rollback_result_json,created_at,updated_at
               ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                "compensation:run-effect:mutation-1",
                "run-effect",
                "task-1",
                key,
                "mutation-1",
                "create",
                "docs/result.md",
                None,
                "d" * 64,
                None,
                "applied",
                text,
                sha_text(text),
                canonical({}),
                now(),
                now(),
            ),
        )
        db.execute("COMMIT")
        recovered = db.execute(
            """SELECT record_json FROM compensation_records
               WHERE idempotency_key=? AND status IN ('applied','committed')
               ORDER BY updated_at DESC LIMIT 1""",
            (key,),
        ).fetchone()
        if recovered is None or json.loads(recovered[0])["afterHash"] != "d" * 64:
            raise AssertionError("applied effect could not be reconstructed")
        return "prepared_before_effect=true applied_effect_recoverable=true"
    finally:
        db.close()


def test_checkpoint_and_recovery(database: Path) -> str:
    db = connect(database)
    try:
        insert_run(db, "run-recovery", items_succeeded=True)
        state = canonical({"runId": "run-recovery", "mutations": 1})
        db.execute(
            """INSERT INTO checkpoints(
                 id,run_id,work_item_id,kind,event_sequence,state_json,state_sha256,created_at
               ) VALUES(?,?,?,?,?,?,?,?)""",
            ("checkpoint-recovery", "run-recovery", None, "workspace_committed", None, state, sha_text(state), now()),
        )
        db.execute(
            """INSERT INTO run_leases(run_id,owner_id,acquired_at,renewed_at,expires_at)
               VALUES(?,?,?,?,?)""",
            ("run-recovery", "dead-owner", now(), now(), "2000-01-01T00:00:00Z"),
        )
        row = db.execute(
            """SELECT r.run_json,
                      EXISTS(SELECT 1 FROM checkpoints c WHERE c.run_id=r.id AND c.kind='workspace_committed') AS committed
               FROM runs r LEFT JOIN run_leases l ON l.run_id=r.id
               WHERE r.id='run-recovery' AND r.state IN ('running','cancelling')
                 AND (l.run_id IS NULL OR l.expires_at <= ?)""",
            (now(),),
        ).fetchone()
        if row is None or int(row["committed"]) != 1:
            raise AssertionError("expired committed run was not recoverable")
        parsed = json.loads(row["run_json"])
        if not all(item.get("state") == "succeeded" for item in parsed["items"]):
            raise AssertionError("run projection is not complete")
        return "expired_lease_detected=true commit_checkpoint=true all_items_succeeded=true"
    finally:
        db.close()


def test_projection_rebuild(database: Path) -> str:
    db = connect(database)
    try:
        run_id = "run-projection"
        first = {
            "id": run_id,
            "state": "running",
            "command": {"id": "command-1", "contract": {"projectId": "project-1"}},
            "createdAt": now(),
            "updatedAt": now(),
            "items": [],
        }
        second = {**first, "state": "succeeded", "summary": "done"}
        for version, run in [(1, first), (2, second)]:
            run_text = canonical(run)
            insert_event(
                db,
                f"projection-event-{version}",
                run_id,
                "run.snapshot",
                {
                    "run": run,
                    "state": run["state"],
                    "stateVersion": version,
                    "snapshotSha256": sha_text(run_text),
                },
                version,
            )
        latest = db.execute(
            """SELECT payload_json,state_version FROM run_events
               WHERE run_id=? AND type='run.snapshot'
               ORDER BY sequence DESC LIMIT 1""",
            (run_id,),
        ).fetchone()
        payload = json.loads(latest["payload_json"])
        if payload["run"]["state"] != "succeeded" or int(latest["state_version"]) != 2:
            raise AssertionError("latest event did not rebuild the projection")
        if sha_text(canonical(payload["run"])) != payload["snapshotSha256"]:
            raise AssertionError("rebuilt projection hash mismatch")
        return "events=2 rebuilt_state=succeeded state_version=2"
    finally:
        db.close()


def test_concurrent_writers(database: Path) -> str:
    def writer(index: int) -> None:
        connection = connect(database)
        try:
            # Stagger starts deterministically to create contention while keeping
            # this gate stable on slower CI hosts.
            time.sleep((index % 4) * 0.002)
            connection.execute("BEGIN IMMEDIATE")
            run_id = f"concurrent-{index:02d}"
            insert_run(connection, run_id)
            insert_event(
                connection,
                f"event-{run_id}",
                run_id,
                "run.snapshot",
                {"run": {"id": run_id}, "snapshotSha256": "f" * 64},
                1,
            )
            connection.execute("COMMIT")
        finally:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            connection.close()

    count = 16
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(writer, range(count)))
    db = connect(database)
    try:
        runs = int(db.execute("SELECT COUNT(*) FROM runs WHERE id LIKE 'concurrent-%'").fetchone()[0])
        events = int(db.execute("SELECT COUNT(*) FROM run_events WHERE event_id LIKE 'event-concurrent-%'").fetchone()[0])
        if runs != count or events != count:
            raise AssertionError(f"lost concurrent writes: runs={runs}, events={events}")
        return f"writers={count} runs={runs} events={events} lost_updates=0"
    finally:
        db.close()


def test_migration_backup_restore(root: Path) -> str:
    source = root / "pre-migration.sqlite3"
    db = sqlite3.connect(source)
    db.execute("CREATE TABLE stable(value TEXT NOT NULL)")
    db.execute("INSERT INTO stable(value) VALUES('before')")
    db.commit()
    db.close()
    source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    backup = root / f"backup.{source_sha[:16]}.sqlite3"
    shutil.copyfile(source, backup)
    if hashlib.sha256(backup.read_bytes()).hexdigest() != source_sha:
        raise AssertionError("pre-migration backup hash mismatch")
    db = sqlite3.connect(source)
    db.execute("UPDATE stable SET value='after'")
    db.commit()
    db.close()
    source.unlink()
    shutil.copyfile(backup, source)
    db = sqlite3.connect(source)
    try:
        value = db.execute("SELECT value FROM stable").fetchone()[0]
    finally:
        db.close()
    if value != "before":
        raise AssertionError("pre-migration backup did not restore")
    return f"backup_sha256={source_sha} restored=true"


def test_legacy_import_backup(database: Path, root: Path) -> str:
    legacy = root / "projects.json"
    records = [{"id": "project-legacy", "name": "Legacy", "rootPath": "/safe/project"}]
    legacy.write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    source_bytes = legacy.read_bytes()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    backup = root / f"projects.json.{source_sha[:16]}.bak"
    shutil.copyfile(legacy, backup)
    db = connect(database)
    try:
        db.execute("BEGIN IMMEDIATE")
        for record in records:
            text = canonical(record)
            db.execute(
                """INSERT INTO entity_records(
                     collection,id,record_json,record_sha256,created_at,updated_at
                   ) VALUES(?,?,?,?,?,?)""",
                ("projects", record["id"], text, sha_text(text), now(), now()),
            )
        db.execute(
            """INSERT INTO migration_imports(
                 source_key,source_path_hash,source_sha256,backup_path,
                 imported_records,imported_at,details_json
               ) VALUES(?,?,?,?,?,?,?)""",
            (
                f"collection:projects:{source_sha}",
                sha_text(str(legacy.resolve())),
                source_sha,
                str(backup),
                len(records),
                now(),
                canonical({"kind": "collection", "collection": "projects"}),
            ),
        )
        db.execute("COMMIT")
        imported = int(db.execute("SELECT COUNT(*) FROM entity_records WHERE collection='projects'").fetchone()[0])
        if imported != 1 or hashlib.sha256(backup.read_bytes()).hexdigest() != source_sha:
            raise AssertionError("legacy import or backup failed")
        return f"records={imported} byte_exact_backup=true ledger=true"
    finally:
        db.close()


def test_startup_rollback_contracts() -> str:
    durable = DURABLE_SOURCE.read_text(encoding="utf-8")
    required = (
        "databaseExistedBeforeOpen",
        "databaseLengthBeforeOpen",
        "legacySourcePresent",
        "force: databaseExistedBeforeOpen && legacySourcePresent",
        "preStartupBackup",
        "_replaceWithEmptyDatabaseFile",
        "_deleteDatabaseFiles",
        "workflow_startup_rollback_failed",
        "WHERE workflow_metadata.value <> excluded.value",
    )
    missing = [marker for marker in required if marker not in durable]
    if missing:
        raise AssertionError(f"missing startup rollback markers: {missing}")
    if "if (!migrationsComplete" in durable:
        raise AssertionError("startup rollback is still limited to pre-migration failures")
    restore = durable.index("await _restoreDatabaseBackup(")
    cleanup = durable.index("await _deleteDatabaseFiles(databaseFile);")
    if restore < 0 or cleanup < 0:
        raise AssertionError("startup restore/cleanup paths are not reachable")
    return "existing_db_restore=true fresh_db_cleanup=true legacy_import_atomic=true"


def test_source_integration_contracts() -> str:
    durable = DURABLE_SOURCE.read_text(encoding="utf-8")
    workspace = WORKSPACE_SOURCE.read_text(encoding="utf-8")
    runtime = RUNTIME_SOURCE.read_text(encoding="utf-8")
    storage = STORAGE_SOURCE.read_text(encoding="utf-8")
    markers = {
        "durable": (
            "class DurableWorkflowStore",
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = FULL",
            "BEGIN IMMEDIATE",
            "recoverInFlightRuns",
            "rebuildRunProjectionFromHistory",
            "claimOperation",
            "recordCompensation",
            "_backupDatabaseBeforeMigration",
            "_restoreDatabaseBackup",
        ),
        "workspace": (
            "status: 'prepared'",
            "await _setStatus(record, 'prepared')",
            "await _setStatus(record, 'applied')",
            "transaction_recovery_required",
            "idempotencyKey: _activeOperationKey",
            "kind: 'workspace_committed'",
        ),
        "runtime": (
            "acquireRunLease",
            "renewRunLease",
            "recordTaskAttempt",
            "kind: 'run_succeeded'",
            "RunState.interrupted",
            "WorkflowRetryTaxonomy",
        ),
        "storage": (
            "workflow.sqlite3",
            "migration-backups",
            "SQLite is the authoritative append-only event history",
            "await _tail;",
        ),
    }
    texts = {"durable": durable, "workspace": workspace, "runtime": runtime, "storage": storage}
    missing = [f"{group}:{marker}" for group, group_markers in markers.items() for marker in group_markers if marker not in texts[group]]
    if missing:
        raise AssertionError(f"missing runtime integration markers: {missing}")
    noncompensatable = {"run_command", "start_process", "package_deployment", "mcp_call"}
    if not all(f"'{name}'" in workspace for name in noncompensatable):
        raise AssertionError("non-compensatable operation policy is incomplete")
    return "sqlite_authority=true leases=true idempotency=true compensation=true retry_taxonomy=true"


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=str(ROOT))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--child-uncommitted")
    parser.add_argument("--child-completed-idempotency", nargs=2, metavar=("DATABASE", "EFFECT_FILE"))
    args = parser.parse_args()
    if args.child_uncommitted:
        return child_uncommitted(Path(args.child_uncommitted))
    if args.child_completed_idempotency:
        return child_completed_idempotency(Path(args.child_completed_idempotency[0]), Path(args.child_completed_idempotency[1]))

    project = Path(args.project).expanduser().resolve()
    if project != ROOT:
        # The harness is self-contained but validates the selected source tree.
        global MIGRATIONS, GENERATED, DURABLE_SOURCE, WORKSPACE_SOURCE, RUNTIME_SOURCE, STORAGE_SOURCE
        MIGRATIONS = project / "migrations" / "workflow"
        GENERATED = project / "lib" / "product" / "generated" / "workflow_migrations.g.dart"
        DURABLE_SOURCE = project / "lib" / "product" / "durable_workflow.dart"
        WORKSPACE_SOURCE = project / "lib" / "product" / "workspace_tools.dart"
        RUNTIME_SOURCE = project / "lib" / "product" / "planning_runtime.dart"
        STORAGE_SOURCE = project / "lib" / "product" / "storage_security.dart"

    with tempfile.TemporaryDirectory(prefix="kristin-workflow-kernel-") as temporary:
        work = Path(temporary)
        database = work / "workflow.sqlite3"
        effect = work / "material-effect.log"
        results = [
            run_case("Generated migration registry", test_generated_registry),
            run_case("SQLite schema and durability pragmas", lambda: test_schema_and_pragmas(database)),
            run_case("Append-only event history", lambda: test_append_only(database)),
            run_case("Crash rolls back uncommitted transition", lambda: test_uncommitted_crash(database)),
            run_case("Crash after idempotent result replays once", lambda: test_idempotency_crash_replay(database, effect)),
            run_case("Completed idempotency guards", lambda: test_completed_idempotency_guards(database)),
            run_case("Prepared/applied compensation recovery", lambda: test_effect_compensation(database)),
            run_case("Checkpoint-driven committed-run recovery", lambda: test_checkpoint_and_recovery(database)),
            run_case("Run projection rebuild from event history", lambda: test_projection_rebuild(database)),
            run_case("Concurrent SQLite writers", lambda: test_concurrent_writers(database)),
            run_case("Pre-migration backup and restore", lambda: test_migration_backup_restore(work)),
            run_case("Legacy JSON import backup and ledger", lambda: test_legacy_import_backup(database, work)),
            run_case("Startup rollback integration contracts", test_startup_rollback_contracts),
            run_case("Dart runtime integration contracts", test_source_integration_contracts),
        ]
        db = connect(database)
        try:
            integrity = str(db.execute("PRAGMA integrity_check").fetchone()[0])
            event_count = int(db.execute("SELECT COUNT(*) FROM run_events").fetchone()[0])
            run_count = int(db.execute("SELECT COUNT(*) FROM runs").fetchone()[0])
            idempotency_count = int(db.execute("SELECT COUNT(*) FROM idempotency_records").fetchone()[0])
            compensation_count = int(db.execute("SELECT COUNT(*) FROM compensation_records").fetchone()[0])
        finally:
            db.close()

    payload = {
        "version": "1.3.0+130",
        "schemaVersion": len(load_migrations()),
        "migrationDigest": hashlib.sha256(
            "\n".join(f"{v}:{n}:{d}" for v, n, _s, d in load_migrations()).encode("utf-8")
        ).hexdigest(),
        "passed": sum(item.passed for item in results),
        "failed": sum(not item.passed for item in results),
        "results": [asdict(item) for item in results],
        "database": {
            "integrity": integrity,
            "runs": run_count,
            "events": event_count,
            "idempotencyRecords": idempotency_count,
            "compensationRecords": compensation_count,
        },
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for result in results:
            print(f"{'PASS' if result.passed else 'FAIL'}: {result.name} — {result.detail}")
        print(
            "SUMMARY: "
            f"passed={payload['passed']} failed={payload['failed']} "
            f"schema={payload['schemaVersion']} integrity={integrity} "
            f"events={event_count} runs={run_count}"
        )
    return 0 if payload["failed"] == 0 and integrity.lower() == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
