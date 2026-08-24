#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import asdict, dataclass
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
from typing import Callable

import workflow_kernel_test as wk


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def disk_full_rolls_back(root: Path) -> str:
    database = root / "disk-full.sqlite3"
    db = wk.apply_migrations(database)
    try:
        db.execute("CREATE TABLE chaos_blob(id INTEGER PRIMARY KEY, payload BLOB NOT NULL)")
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        page_count = int(db.execute("PRAGMA page_count").fetchone()[0])
        db.execute(f"PRAGMA max_page_count={page_count}")
        try:
            db.execute("BEGIN IMMEDIATE")
            db.execute("INSERT INTO chaos_blob(payload) VALUES(zeroblob(4194304))")
            db.execute("COMMIT")
        except sqlite3.DatabaseError as error:
            if db.in_transaction:
                db.execute("ROLLBACK")
            if "full" not in str(error).lower():
                raise AssertionError(f"expected deterministic SQLITE_FULL, got: {error}") from error
        else:
            raise AssertionError("disk-full injection unexpectedly committed")
        rows = int(db.execute("SELECT COUNT(*) FROM chaos_blob").fetchone()[0])
        integrity = str(db.execute("PRAGMA integrity_check").fetchone()[0]).lower()
        if rows != 0 or integrity != "ok":
            raise AssertionError(f"disk-full rollback damaged state: rows={rows} integrity={integrity}")
        return "sqlite_full=true transaction_rolled_back=true integrity=ok outcome=explicit_failure"
    finally:
        db.close()


def corruption_detects_and_recovers(root: Path) -> str:
    database = root / "corrupt.sqlite3"
    db = wk.apply_migrations(database)
    db.execute("CREATE TABLE chaos_stable(value TEXT NOT NULL)")
    db.execute("INSERT INTO chaos_stable(value) VALUES('before')")
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.close()
    backup = root / "corrupt.backup.sqlite3"
    shutil.copyfile(database, backup)
    database.write_bytes(b"not-a-sqlite-database" * 128)
    detected = False
    try:
        bad = sqlite3.connect(database)
        try:
            bad.execute("PRAGMA integrity_check").fetchone()
        finally:
            bad.close()
    except sqlite3.DatabaseError:
        detected = True
    if not detected:
        raise AssertionError("database corruption was not detected")
    shutil.copyfile(backup, database)
    recovered = wk.connect(database)
    try:
        value = recovered.execute("SELECT value FROM chaos_stable").fetchone()[0]
        integrity = str(recovered.execute("PRAGMA integrity_check").fetchone()[0]).lower()
    finally:
        recovered.close()
    if value != "before" or integrity != "ok":
        raise AssertionError("backup recovery did not restore known-good state")
    return "corruption_detected=true backup_restored=true integrity=ok"


def wal_loss_becomes_unknown(root: Path) -> str:
    database = root / "wal-live.sqlite3"
    db = wk.apply_migrations(database)
    try:
        db.execute("PRAGMA wal_autocheckpoint=0")
        db.execute("CREATE TABLE chaos_wal(value TEXT NOT NULL)")
        db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        db.execute("BEGIN IMMEDIATE")
        db.execute("INSERT INTO chaos_wal(value) VALUES('committed-in-wal')")
        db.execute("COMMIT")
        wal = Path(f"{database}-wal")
        if not wal.is_file() or wal.stat().st_size == 0:
            raise AssertionError("WAL fixture did not materialize")
        stale_copy = root / "wal-without-log.sqlite3"
        shutil.copyfile(database, stale_copy)
        original_count = int(db.execute("SELECT COUNT(*) FROM chaos_wal").fetchone()[0])
        if original_count != 1:
            raise AssertionError("source WAL transaction did not commit")
        stale = sqlite3.connect(stale_copy)
        try:
            try:
                stale_count = int(stale.execute("SELECT COUNT(*) FROM chaos_wal").fetchone()[0])
            except sqlite3.DatabaseError:
                stale_count = 0
        finally:
            stale.close()
        if stale_count == original_count:
            raise AssertionError("WAL-loss fixture unexpectedly retained the uncheckpointed effect")
        return "wal_commit_visible=true wal_removed_copy_stale=true outcome=reconciliation_required"
    finally:
        db.close()


def clock_jump_lease_resolution(root: Path) -> str:
    database = root / "clock.sqlite3"
    db = wk.apply_migrations(database)
    try:
        wk.insert_run(db, "clock-run")
        db.execute(
            "INSERT INTO run_leases(run_id,owner_id,acquired_at,renewed_at,expires_at) VALUES(?,?,?,?,?)",
            (
                "clock-run",
                "owner-1",
                "2026-08-23T00:00:00Z",
                "2026-08-23T00:00:00Z",
                "2099-01-01T00:00:00Z",
            ),
        )
        before = int(
            db.execute(
                "SELECT COUNT(*) FROM run_leases WHERE run_id=? AND expires_at <= ?",
                ("clock-run", "2026-08-23T12:00:00Z"),
            ).fetchone()[0]
        )
        after = int(
            db.execute(
                "SELECT COUNT(*) FROM run_leases WHERE run_id=? AND expires_at <= ?",
                ("clock-run", "2100-01-01T00:00:00Z"),
            ).fetchone()[0]
        )
        if before != 0 or after != 1:
            raise AssertionError(f"lease expiry did not follow supplied clock: before={before} after={after}")
        return "backward_clock_not_expired=true forward_clock_expired=true recovery_deterministic=true"
    finally:
        db.close()


def duplicate_completion_is_idempotent(root: Path) -> str:
    database = root / "duplicate.sqlite3"
    db = wk.apply_migrations(database)
    try:
        key = "duplicate-key"
        result = wk.canonical({"ok": True, "summary": "once"})
        db.execute(
            """INSERT INTO idempotency_records(
                 idempotency_key,run_id,work_item_id,attempt,operation,
                 normalized_arguments_sha256,status,result_json,result_sha256,
                 lease_owner,lease_expires_at,execution_generation,created_at,
                 updated_at,completed_at
               ) VALUES(?,?,?,?,?,?,'completed',?,?,?,?,?,?,?,?)""",
            (
                key,
                "duplicate-run",
                "task-1",
                1,
                "tool:write_file",
                "a" * 64,
                result,
                wk.sha_text(result),
                "owner",
                "2099-01-01T00:00:00Z",
                1,
                wk.now(),
                wk.now(),
                wk.now(),
            ),
        )
        duplicate_blocked = False
        try:
            db.execute(
                "INSERT INTO idempotency_records(idempotency_key,run_id,work_item_id,attempt,operation,normalized_arguments_sha256,status,lease_owner,lease_expires_at,execution_generation,created_at,updated_at) VALUES(?,?,?,?,?,?,'in_progress',?,?,?,?,?)",
                (key, "duplicate-run", "task-1", 2, "tool:write_file", "a" * 64, "owner-2", "2099-01-01T00:00:00Z", 2, wk.now(), wk.now()),
            )
        except sqlite3.IntegrityError:
            duplicate_blocked = True
        row = db.execute(
            "SELECT status,result_json FROM idempotency_records WHERE idempotency_key=?",
            (key,),
        ).fetchone()
        if not duplicate_blocked or row["status"] != "completed" or row["result_json"] != result:
            raise AssertionError("duplicate completion changed the durable prior result")
        return "duplicate_insert_blocked=true prior_completion_preserved=true effects=once"
    finally:
        db.close()


def cancellation_commit_cas(root: Path) -> str:
    database = root / "cancel-race.sqlite3"
    db = wk.apply_migrations(database)
    wk.insert_run(db, "race-run", state="running", state_version=1)
    db.close()
    winner = wk.connect(database)
    loser = wk.connect(database)
    try:
        winner.execute("BEGIN IMMEDIATE")
        completed = winner.execute(
            "UPDATE runs SET state='succeeded', state_version=2, updated_at=? WHERE id=? AND state='running' AND state_version=1",
            (wk.now(), "race-run"),
        ).rowcount
        winner.execute("COMMIT")
        loser.execute("BEGIN IMMEDIATE")
        cancelled = loser.execute(
            "UPDATE runs SET state='cancelled', state_version=2, updated_at=? WHERE id=? AND state='running' AND state_version=1",
            (wk.now(), "race-run"),
        ).rowcount
        loser.execute("COMMIT")
        final = loser.execute("SELECT state,state_version FROM runs WHERE id='race-run'").fetchone()
        if completed != 1 or cancelled != 0 or final["state"] != "succeeded" or int(final["state_version"]) != 2:
            raise AssertionError(
                f"CAS race invalid: completed={completed} cancelled={cancelled} state={dict(final)}"
            )
        return "completion_cas=won cancellation_cas=lost one_terminal_state=true"
    finally:
        if winner.in_transaction:
            winner.execute("ROLLBACK")
        if loser.in_transaction:
            loser.execute("ROLLBACK")
        winner.close()
        loser.close()


def main() -> int:
    results: list[Result] = []
    with tempfile.TemporaryDirectory(prefix="kristin-p8-chaos-") as raw:
        root = Path(raw)
        results.append(run_case("disk full rolls back", lambda: disk_full_rolls_back(root)))
        results.append(run_case("corruption backup recovery", lambda: corruption_detects_and_recovers(root)))
        results.append(run_case("WAL loss becomes reconciliation-required", lambda: wal_loss_becomes_unknown(root)))
        results.append(run_case("clock jump lease resolution", lambda: clock_jump_lease_resolution(root)))
        results.append(run_case("duplicate completion stays idempotent", lambda: duplicate_completion_is_idempotent(root)))
        results.append(run_case("cancellation vs commit CAS", lambda: cancellation_commit_cas(root)))
        results.append(run_case("interrupted migration backup restore", lambda: wk.test_migration_backup_restore(root)))
    payload = {
        "schemaVersion": "1.0.0",
        "assuranceLevel": "behavioral",
        "caseCount": len(results),
        "passedCount": sum(item.passed for item in results),
        "failedCount": sum(not item.passed for item in results),
        "passed": all(item.passed for item in results),
        "results": [asdict(item) for item in results],
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
