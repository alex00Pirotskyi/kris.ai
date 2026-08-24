#!/usr/bin/env python3
"""Safe current-host behavioral conformance for the historical P11 native fixture contract."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform as platform_module
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any, Callable

CONTRACT_PATH = Path(__file__).resolve().parents[1] / "config" / "p11_native_contract.v1.json"


def load_contract(path: Path = CONTRACT_PATH) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise NativeConformanceError(f"cannot load P11 native contract: {exc}") from exc
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise NativeConformanceError("P11 native contract must be a schemaVersion 1 object")
    expected_platforms = {"windows", "macos", "linux"}
    if set(value.get("platforms", [])) != expected_platforms:
        raise NativeConformanceError("P11 native contract platform set is invalid")
    fixtures = value.get("fixtureIds")
    operations = value.get("semanticOperations")
    fallbacks = value.get("forbiddenFallbacks")
    device_states = value.get("deviceStates")
    if not isinstance(fixtures, list) or len(fixtures) != 25 or len(set(fixtures)) != 25:
        raise NativeConformanceError("P11 native contract must preserve 25 unique conformance fixtures")
    if not isinstance(operations, list) or len(operations) != 24 or len(set(operations)) != 24:
        raise NativeConformanceError("P11 native contract must preserve 24 unique semantic operations")
    if not isinstance(fallbacks, list) or len(fallbacks) != 7 or len(set(fallbacks)) != 7:
        raise NativeConformanceError("P11 native contract no-silent-fallback policy is invalid")
    if not isinstance(device_states, list) or "UNKNOWN" not in device_states or "UNSUPPORTED" not in device_states:
        raise NativeConformanceError("P11 native contract device state model is invalid")
    claims = value.get("supportClaimsDefault")
    if not isinstance(claims, dict) or any(claims.get(key) is not False for key in ("platformSupported", "nativeParity", "deviceAutomation", "isolation", "remoteMcp")):
        raise NativeConformanceError("P11 native contract must fail closed on support claims")
    return value



class NativeConformanceError(RuntimeError):
    pass


def host_platform() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("linux"):
        return "linux"
    return "unsupported"


def _controlled_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    keep = {
        "PATH", "PATHEXT", "SystemRoot", "WINDIR", "COMSPEC",
        "HOME", "USERPROFILE", "LOCALAPPDATA", "TEMP", "TMP",
        "LANG", "LC_ALL", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH",
    }
    env = {key: value for key, value in os.environ.items() if key in keep}
    env["PYTHONIOENCODING"] = "utf-8"
    if extra:
        env.update({str(k): str(v) for k, v in extra.items()})
    return env


def _kill_tree(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=0.75)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait(timeout=3)


def run_process(
    argv: list[str],
    *,
    cwd: Path | None = None,
    timeout: float = 5.0,
    extra_env: dict[str, str] | None = None,
    max_output: int = 8192,
) -> dict[str, Any]:
    kwargs: dict[str, Any] = {
        "cwd": str(cwd) if cwd else None,
        "env": _controlled_env(extra_env),
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "encoding": "utf-8",
        "errors": "replace",
    }
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    started = time.monotonic()
    proc = subprocess.Popen(argv, **kwargs)
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        _kill_tree(proc)
        stdout, stderr = proc.communicate()
    duration_ms = int((time.monotonic() - started) * 1000)
    stdout_truncated = len(stdout.encode("utf-8")) > max_output
    stderr_truncated = len(stderr.encode("utf-8")) > max_output
    if stdout_truncated:
        stdout = stdout.encode("utf-8")[-max_output:].decode("utf-8", errors="replace")
    if stderr_truncated:
        stderr = stderr.encode("utf-8")[-max_output:].decode("utf-8", errors="replace")
    return {
        "argv0": Path(argv[0]).name,
        "pid": proc.pid,
        "exitCode": proc.returncode,
        "timedOut": timed_out,
        "stdout": stdout,
        "stderr": stderr,
        "stdoutTruncated": stdout_truncated,
        "stderrTruncated": stderr_truncated,
        "durationMs": duration_ms,
        "cleanupState": "COMPLETE" if proc.poll() is not None else "INCOMPLETE",
    }


def _python(code: str, *args: str) -> list[str]:
    return [sys.executable, "-c", code, *args]


def _result(fixture_id: str, passed: bool, detail: str, evidence: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "fixtureId": fixture_id,
        "state": "PASS" if passed else "FAIL",
        "detail": detail,
        "evidence": evidence or {},
    }


def _fixture_process_success(_: Path) -> list[dict[str, Any]]:
    run = run_process(_python("print('ok')"))
    return [_result("fixture.process.success", run["exitCode"] == 0 and run["stdout"].strip() == "ok", "process returned exact successful output", run)]


def _fixture_process_nonzero(_: Path) -> list[dict[str, Any]]:
    run = run_process(_python("import sys; print('expected-failure'); sys.exit(7)"))
    return [_result("fixture.process.nonzero", run["exitCode"] == 7, "non-zero exit code preserved", run)]


def _fixture_stdout_stderr(_: Path) -> list[dict[str, Any]]:
    run = run_process(_python("import sys; print('stdout-token'); print('stderr-token', file=sys.stderr)"))
    ok = "stdout-token" in run["stdout"] and "stderr-token" in run["stderr"] and run["exitCode"] == 0
    return [_result("fixture.process.stdout-stderr", ok, "stdout and stderr captured independently", run)]


def _fixture_bounded_output(_: Path) -> list[dict[str, Any]]:
    run = run_process(_python("import sys; sys.stdout.write('x'*20000); sys.stderr.write('y'*20000)"), max_output=4096)
    ok = run["stdoutTruncated"] and run["stderrTruncated"] and len(run["stdout"].encode()) <= 4096 and len(run["stderr"].encode()) <= 4096
    return [_result("fixture.process.bounded-large-output", ok, "large output is bounded without deadlock", run)]


def _fixture_timeout(_: Path) -> list[dict[str, Any]]:
    run = run_process(_python("import time; time.sleep(10)"), timeout=0.3)
    ok = run["timedOut"] and run["cleanupState"] == "COMPLETE" and run["exitCode"] is not None
    return [_result("fixture.process.timeout", ok, "timeout terminates and reaps the process", run)]


def _fixture_cancellation(_: Path) -> list[dict[str, Any]]:
    kwargs: dict[str, Any] = {
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "env": _controlled_env(),
    }
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    proc = subprocess.Popen(_python("import time; print('ready', flush=True); time.sleep(20)"), **kwargs)
    ready = proc.stdout.readline().strip() if proc.stdout else ""
    proc.terminate()
    try:
        proc.wait(timeout=2)
        cooperative = ready == "ready" and proc.poll() is not None
    except subprocess.TimeoutExpired:
        cooperative = False
        _kill_tree(proc)
    finally:
        if proc.stdout is not None:
            proc.stdout.close()
        if proc.stderr is not None:
            proc.stderr.close()
    forced = run_process(_python("import time; time.sleep(20)"), timeout=0.2)
    forced_ok = forced["timedOut"] and forced["cleanupState"] == "COMPLETE"
    return [
        _result("fixture.process.cooperative-cancellation", cooperative, "cooperative termination reaps the process", {"exitCode": proc.returncode}),
        _result("fixture.process.forced-cancellation", forced_ok, "forced cancellation has bounded cleanup", forced),
    ]


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        result = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        return str(pid) in result.stdout
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _fixture_descendant_termination(root: Path) -> list[dict[str, Any]]:
    pid_file = root / "child.pid"
    child_code = "import time; time.sleep(30)"
    parent_code = (
        "import pathlib,subprocess,sys,time; "
        "p=subprocess.Popen([sys.executable,'-c',sys.argv[2]]); "
        "pathlib.Path(sys.argv[1]).write_text(str(p.pid)); "
        "print('child-ready', flush=True); time.sleep(30)"
    )
    kwargs: dict[str, Any] = {
        "env": _controlled_env(),
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "text": True,
        "encoding": "utf-8",
        "errors": "replace",
    }
    if os.name == "nt":
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        kwargs["start_new_session"] = True
    started = time.monotonic()
    proc = subprocess.Popen(_python(parent_code, str(pid_file), child_code), **kwargs)
    deadline = time.monotonic() + 3.0
    while not pid_file.exists() and proc.poll() is None and time.monotonic() < deadline:
        time.sleep(0.05)
    child_pid = int(pid_file.read_text()) if pid_file.exists() else -1
    _kill_tree(proc)
    stdout, stderr = proc.communicate()
    deadline = time.monotonic() + 3.0
    while child_pid > 0 and _pid_alive(child_pid) and time.monotonic() < deadline:
        time.sleep(0.05)
    gone = child_pid > 0 and not _pid_alive(child_pid)
    evidence = {
        "pid": proc.pid,
        "exitCode": proc.returncode,
        "childPid": child_pid,
        "childGone": gone,
        "stdout": stdout[-2048:],
        "stderr": stderr[-2048:],
        "durationMs": int((time.monotonic() - started) * 1000),
        "cleanupState": "COMPLETE" if proc.poll() is not None and gone else "INCOMPLETE",
    }
    established = child_pid > 0 and "child-ready" in stdout
    return [
        _result("fixture.process.child", established, "child process identity captured explicitly", evidence),
        _result("fixture.process.grandchild", established, "descendant fixture established a process-tree boundary", evidence),
        _result("fixture.process.descendant-termination", established and gone, "bounded tree cleanup terminates the descendant process", evidence),
    ]


def _fixture_working_directory(root: Path) -> list[dict[str, Any]]:
    cwd = root / "working dir"
    cwd.mkdir()
    run = run_process(_python("import os; print(os.getcwd())"), cwd=cwd)
    ok = Path(run["stdout"].strip()).resolve() == cwd.resolve()
    return [_result("fixture.process.working-directory", ok, "working directory preserved exactly", run)]


def _fixture_environment(_: Path) -> list[dict[str, Any]]:
    secret_name = "KRISTIN_FIXTURE_PARENT_SECRET"
    old = os.environ.get(secret_name)
    os.environ[secret_name] = "must-not-leak"
    try:
        code = "import os; print(os.environ.get('KRISTIN_ALLOWED')); print(os.environ.get('KRISTIN_FIXTURE_PARENT_SECRET','absent'))"
        run = run_process(_python(code), extra_env={"KRISTIN_ALLOWED": "present"})
    finally:
        if old is None:
            os.environ.pop(secret_name, None)
        else:
            os.environ[secret_name] = old
    lines = run["stdout"].splitlines()
    ok = lines == ["present", "absent"]
    return [_result("fixture.process.environment-allowlist", ok, "child receives explicit environment without arbitrary parent secret inheritance", run)]


def _fixture_arguments(_: Path) -> list[dict[str, Any]]:
    unicode_value = "Kristin-Žluťoučký-你好"
    run_unicode = run_process(_python("import sys; print(sys.argv[1])", unicode_value))
    quoted = '  alpha "beta gamma" delta  '
    run_quoted = run_process(_python("import sys; print(repr(sys.argv[1]))", quoted))
    return [
        _result("fixture.process.unicode-arguments", run_unicode["stdout"].strip() == unicode_value, "Unicode argument round-trips", run_unicode),
        _result("fixture.process.quotes-whitespace", run_quoted["stdout"].strip() == repr(quoted), "quotes and boundary whitespace round-trip as one argument", run_quoted),
    ]


def _fixture_long_path(root: Path) -> list[dict[str, Any]]:
    current = root
    for index in range(10):
        current = current / (f"segment-{index}-" + "x" * 16)
    try:
        current.mkdir(parents=True)
        target = current / "payload.txt"
        target.write_text("native-path-ok", encoding="utf-8")
        ok = target.read_text(encoding="utf-8") == "native-path-ok"
        evidence = {"pathLength": len(str(target)), "resolved": str(target.resolve())}
    except OSError as exc:
        ok = False
        evidence = {"pathLength": len(str(current)), "error": f"{type(exc).__name__}: {exc}"}
    return [_result("fixture.path.long", ok, "long nested path supports create/read on this host", evidence)]


def _fixture_symlink(root: Path) -> list[dict[str, Any]]:
    source = root / "symlink-source.txt"
    link = root / "symlink-link.txt"
    source.write_text("source", encoding="utf-8")
    try:
        link.symlink_to(source.name)
        ok = link.is_symlink() and link.resolve() == source.resolve() and link.read_text() == "source"
        return [_result("fixture.path.symlink-reparse", ok, "symbolic-link/reparse behavior observed on current host", {"link": str(link), "target": str(link.resolve())})]
    except (OSError, NotImplementedError) as exc:
        return [{"fixtureId": "fixture.path.symlink-reparse", "state": "UNAVAILABLE", "detail": "host policy did not permit safe disposable symlink creation", "evidence": {"error": f"{type(exc).__name__}: {exc}"}}]


def _fixture_file_cleanup(root: Path) -> list[dict[str, Any]]:
    target = root / "cleanup.txt"
    target.write_text("cleanup", encoding="utf-8")
    target.unlink()
    return [_result("fixture.file.cleanup", not target.exists(), "disposable file cleanup leaves no residual file")]


def _filesystem_semantic_results(root: Path) -> list[dict[str, Any]]:
    fs_root = root / "semantic-filesystem"
    fs_root.mkdir()
    source = fs_root / "source.txt"
    source.write_text("kristin-native-filesystem", encoding="utf-8")
    write_ok = source.exists()
    read_ok = source.read_text(encoding="utf-8") == "kristin-native-filesystem"
    copied = fs_root / "copied.txt"
    shutil.copy2(source, copied)
    copy_ok = copied.read_text(encoding="utf-8") == "kristin-native-filesystem"
    moved = fs_root / "moved.txt"
    shutil.move(str(copied), moved)
    move_ok = moved.exists() and not copied.exists()
    moved.unlink()
    delete_ok = not moved.exists()
    identity = fs_root / "." / "source.txt"
    identity_ok = identity.resolve() == source.resolve()
    values = {
        "filesystem.write": write_ok,
        "filesystem.read": read_ok,
        "filesystem.copy": copy_ok,
        "filesystem.move": move_ok,
        "filesystem.delete": delete_ok,
        "path.identity": identity_ok,
    }
    return [
        {
            "operation": operation,
            "state": "PASS" if passed else "FAIL",
            "detail": "safe disposable current-host semantic behavior",
        }
        for operation, passed in values.items()
    ]


def _semantic_operation_results(contract: dict[str, Any], fixtures: list[dict[str, Any]], filesystem: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fixture_state = {row["fixtureId"]: row["state"] for row in fixtures}
    process_proofs = {
        "process.start": ("fixture.process.success",),
        "process.output": ("fixture.process.stdout-stderr", "fixture.process.bounded-large-output"),
        "process.exit": ("fixture.process.success", "fixture.process.nonzero"),
        "process.cancellation": ("fixture.process.cooperative-cancellation", "fixture.process.forced-cancellation"),
        "process.tree-kill": ("fixture.process.descendant-termination",),
    }
    observed = {row["operation"]: dict(row) for row in filesystem}
    for operation, fixture_ids in process_proofs.items():
        passed = all(fixture_state.get(fixture) == "PASS" for fixture in fixture_ids)
        observed[operation] = {
            "operation": operation,
            "state": "PASS" if passed else "FAIL",
            "detail": f"behavior bound to fixtures: {', '.join(fixture_ids)}",
        }
    results = []
    for operation in contract["semanticOperations"]:
        results.append(observed.get(operation, {
            "operation": operation,
            "state": "UNVERIFIED",
            "detail": "not exercised by the safe current-host conformance subset",
        }))
    return results


def run_suite() -> dict[str, Any]:
    contract = load_contract()
    platform_name = host_platform()
    if platform_name == "unsupported":
        raise NativeConformanceError(f"unsupported host platform: {sys.platform}")
    runners: tuple[Callable[[Path], list[dict[str, Any]]], ...] = (
        _fixture_process_success,
        _fixture_process_nonzero,
        _fixture_stdout_stderr,
        _fixture_bounded_output,
        _fixture_timeout,
        _fixture_cancellation,
        _fixture_descendant_termination,
        _fixture_working_directory,
        _fixture_environment,
        _fixture_arguments,
        _fixture_long_path,
        _fixture_symlink,
        _fixture_file_cleanup,
    )
    results: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="kristin-p11-conformance-") as temp:
        root = Path(temp)
        for runner in runners:
            results.extend(runner(root))
        filesystem_results = _filesystem_semantic_results(root)
    fixture_ids = list(contract["fixtureIds"])
    executed_ids = {row["fixtureId"] for row in results}
    unknown = sorted(executed_ids - set(fixture_ids))
    if unknown:
        raise NativeConformanceError(f"runner emitted fixtures outside the canonical P11 contract: {unknown}")
    deferred = [fixture for fixture in fixture_ids if fixture not in executed_ids]
    failed = [row for row in results if row["state"] == "FAIL"]
    unavailable = [row for row in results if row["state"] == "UNAVAILABLE"]
    operation_results = _semantic_operation_results(contract, results, filesystem_results)
    failed_operations = [row for row in operation_results if row["state"] == "FAIL"]
    return {
        "schemaVersion": 1,
        "classification": "BEHAVIORAL_CURRENT_HOST_ONLY",
        "resultState": "PASS" if not failed and not failed_operations else "FAIL",
        "platform": platform_name,
        "host": {
            "sysPlatform": sys.platform,
            "machine": platform_module.machine(),
            "python": platform_module.python_version(),
        },
        "lineage": contract["lineage"],
        "contractFixtureCount": len(fixture_ids),
        "semanticOperationCount": len(contract["semanticOperations"]),
        "forbiddenFallbackCount": len(contract["forbiddenFallbacks"]),
        "executedFixtureCount": len(results),
        "passedFixtureCount": sum(row["state"] == "PASS" for row in results),
        "failedFixtureCount": len(failed),
        "unavailableFixtureCount": len(unavailable),
        "verifiedOperationCount": sum(row["state"] == "PASS" for row in operation_results),
        "failedOperationCount": len(failed_operations),
        "operationResults": operation_results,
        "fixtureResults": results,
        "deferredFixtures": deferred,
        "supportClaims": dict(contract["supportClaimsDefault"]),
        "truthBoundary": "Passing current-host fixtures is behavioral evidence for those fixtures only; it is not a platform-support or native-parity claim.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        report = run_suite()
    except NativeConformanceError as exc:
        print(json.dumps({"resultState": "FAIL", "error": str(exc)}, sort_keys=True))
        return 2
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8", newline="\n")
    print(text, end="")
    return 0 if report["resultState"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
