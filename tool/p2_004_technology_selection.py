#!/usr/bin/env python3
"""P2-004 technology-selection measurement and tri-platform aggregation.

This is deliberately a *selection* harness, not P2-005/P2-006 certification.
It measures enough real behavior to choose the automation-host architecture:
startup, memory, package/dependency footprint, repeated-run reliability, and
real PTY viability. Production detach/reconnect/transcript and adversarial
process-tree guarantees remain downstream P2-005/P2-006 work.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import pathlib
import platform
import select
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any

NODE = "typescript-node-node-pty-with-native-lifecycle-adapters"
NATIVE = "native-platform-pty-supervisor"
DART = "dart-control-plane-native-pty-helper"
CANDIDATES = (NODE, NATIVE, DART)
PLATFORM = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(
    platform.system(), platform.system().lower()
)
ROUNDS = 3


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(argv: list[str], *, cwd: pathlib.Path, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def git_head(project: pathlib.Path) -> str:
    expected = (
        os.environ.get("KRISTIN_P2_SELECTION_SHA", "").strip().lower()
        or os.environ.get("GITHUB_SHA", "").strip().lower()
    )
    if len(expected) == 40 and all(ch in "0123456789abcdef" for ch in expected):
        return expected
    result = run(["git", "rev-parse", "HEAD"], cwd=project)
    value = result.stdout.strip().lower()
    if result.returncode or len(value) != 40:
        raise RuntimeError("exact git HEAD required for technology selection")
    return value


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_fingerprint(paths: list[pathlib.Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: item.as_posix()):
        if not path.is_file():
            continue
        digest.update(path.as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def directory_size(root: pathlib.Path) -> int:
    total = 0
    if not root.exists():
        return 0
    for path in root.rglob("*"):
        try:
            if path.is_file() and not path.is_symlink():
                total += path.stat().st_size
        except OSError:
            pass
    return total


def parse_last_json(text: str) -> dict[str, Any]:
    decoder = json.JSONDecoder()
    for line in reversed([row.strip() for row in text.splitlines() if row.strip()]):
        try:
            value = decoder.decode(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    start = text.find("{")
    if start >= 0:
        value = json.loads(text[start:])
        if isinstance(value, dict):
            return value
    raise ValueError("command did not emit a JSON object")


NODE_PROBE = r'''
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
const project = process.argv[2];
const require = createRequire(pathToFileURL(path.resolve(project, 'automation_host/package.json')).href);
const pty = require('node-pty');
const windows = process.platform === 'win32';
const shell = windows ? (process.env.ComSpec || 'cmd.exe') : (process.env.SHELL || '/bin/sh');
const term = pty.spawn(shell, windows ? ['/d', '/q'] : [], {
  name: 'xterm-256color', cols: 80, rows: 24, cwd: os.tmpdir(),
  env: Object.fromEntries(Object.entries({
    PATH: process.env.PATH, SystemRoot: process.env.SystemRoot,
    HOME: process.env.HOME, USERPROFILE: process.env.USERPROFILE,
    TERM: 'xterm-256color'
  }).filter(([, value]) => typeof value === 'string')),
  useConpty: windows,
});
let transcript = '';
term.onData((chunk) => { transcript += chunk; });
term.resize(120, 40);
const marker = 'KRISTIN_P2_SELECTION_NODE_PTY';
term.write(windows ? `echo ${marker}\r` : `printf '${marker}\\n'\n`);
const deadline = Date.now() + 8000;
while (!transcript.includes(marker) && Date.now() < deadline) {
  await new Promise((resolve) => setTimeout(resolve, 25));
}
const passed = transcript.includes(marker);
try { term.kill(); } catch {}
console.log(JSON.stringify({
  status: passed ? 'passed' : 'failed',
  realPtyBehavior: passed,
  resizeExercised: true,
  platform: process.platform,
  arch: process.arch,
  node: process.version,
  rssBytes: process.memoryUsage().rss,
  transcriptBytes: Buffer.byteLength(transcript),
}));
if (!passed) process.exitCode = 1;
'''


DART_PROBE = r'''
import 'dart:convert';
import 'dart:io';
Future<void> main() async {
  final windows = Platform.isWindows;
  final shell = windows ? (Platform.environment['ComSpec'] ?? 'cmd.exe') : '/bin/sh';
  final args = windows ? <String>['/d', '/c', 'echo KRISTIN_P2_DART_PIPE'] : <String>['-c', 'printf KRISTIN_P2_DART_PIPE'];
  final started = DateTime.now().microsecondsSinceEpoch;
  final result = await Process.run(shell, args);
  final elapsedMs = (DateTime.now().microsecondsSinceEpoch - started) / 1000.0;
  final ok = result.exitCode == 0 && result.stdout.toString().contains('KRISTIN_P2_DART_PIPE');
  stdout.writeln(jsonEncode({
    'status': ok ? 'feasible_with_native_helper' : 'failed',
    'pipeIoObserved': ok,
    'realPtyBehavior': false,
    'requiresNativePtyHelper': true,
    'startupMs': elapsedMs,
    'rssBytes': ProcessInfo.currentRss,
    'dartVersion': Platform.version.split(' ').first,
    'platform': Platform.operatingSystem,
  }));
  if (!ok) exitCode = 1;
}
'''


def ensure_macos_node_pty_spawn_helper(project: pathlib.Path) -> list[str]:
    """Restore executable bits on node-pty macOS prebuilt spawn helpers.

    node-pty 1.1.0 can arrive with a non-executable darwin spawn-helper. The
    technology spike records this deterministic packaging repair instead of
    silently converting the first observed failure into a pass.
    """
    if PLATFORM != "macos":
        return []
    root = project / "automation_host" / "node_modules" / "node-pty"
    repaired: list[str] = []
    if not root.exists():
        return repaired
    for helper in sorted(root.rglob("spawn-helper")):
        if not helper.is_file():
            continue
        mode = helper.stat().st_mode
        if mode & 0o111:
            continue
        helper.chmod(mode | 0o111)
        repaired.append(helper.relative_to(project).as_posix())
    return repaired


def node_round(project: pathlib.Path, round_id: int) -> dict[str, Any]:
    node = shutil.which("node")
    if not node:
        return {"roundId": round_id, "status": "unavailable", "realPtyBehavior": False}
    packaging_repairs = ensure_macos_node_pty_spawn_helper(project)
    with tempfile.TemporaryDirectory(prefix="p2-node-selection-") as tmp:
        script = pathlib.Path(tmp) / "probe.mjs"
        script.write_text(NODE_PROBE, encoding="utf-8")
        started = time.perf_counter()
        result = run([node, str(script), str(project)], cwd=project, timeout=20)
        elapsed = (time.perf_counter() - started) * 1000.0
    try:
        payload = parse_last_json(result.stdout)
    except Exception:
        payload = {}
    passed = result.returncode == 0 and payload.get("status") == "passed" and payload.get("realPtyBehavior") is True
    return {
        "roundId": round_id,
        "status": "passed" if passed else "failed",
        "realPtyBehavior": bool(payload.get("realPtyBehavior")),
        "startupMs": round(elapsed, 3),
        "rssBytes": int(payload.get("rssBytes") or 0),
        "resizeExercised": bool(payload.get("resizeExercised")),
        "packagingRepairApplied": bool(packaging_repairs),
        "packagingRepairs": packaging_repairs,
        "stderrTail": result.stderr[-2000:] if result.returncode else "",
    }


def native_round(project: pathlib.Path, round_id: int) -> dict[str, Any]:
    started = time.perf_counter()
    if PLATFORM == "windows":
        try:
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            conpty = getattr(kernel32, "CreatePseudoConsole")
            job = getattr(kernel32, "CreateJobObjectW")
            available = conpty is not None and job is not None
        except Exception:
            available = False
        return {
            "roundId": round_id,
            "status": "feasible_api_only" if available else "unavailable",
            "realPtyBehavior": False,
            "nativePtyApiAvailable": available,
            "prototypeComplete": False,
            "startupMs": round((time.perf_counter() - started) * 1000.0, 3),
            "rssBytes": 0,
            "reason": "ConPTY API measured, but no independent native supervisor prototype is committed for Windows",
        }

    try:
        import pty
        import fcntl
        import termios
        import struct
        master, slave = pty.openpty()
        winsize = struct.pack("HHHH", 40, 120, 0, 0)
        fcntl.ioctl(master, termios.TIOCSWINSZ, winsize)
        marker = b"KRISTIN_P2_SELECTION_NATIVE_PTY"
        proc = subprocess.Popen(
            ["/bin/sh"],
            cwd=project,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            start_new_session=True,
        )
        os.close(slave)
        os.write(master, b"printf 'KRISTIN_P2_SELECTION_NATIVE_PTY\\n'; exit\n")
        transcript = b""
        deadline = time.monotonic() + 5
        while marker not in transcript and time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if not ready:
                continue
            try:
                block = os.read(master, 4096)
            except OSError:
                break
            if not block:
                break
            transcript += block
        proc.wait(timeout=5)
        os.close(master)
        passed = marker in transcript and proc.returncode == 0
    except Exception as exc:
        return {
            "roundId": round_id,
            "status": "failed",
            "realPtyBehavior": False,
            "prototypeComplete": True,
            "startupMs": round((time.perf_counter() - started) * 1000.0, 3),
            "rssBytes": 0,
            "reason": f"native POSIX PTY probe failed: {type(exc).__name__}: {exc}",
        }
    return {
        "roundId": round_id,
        "status": "passed" if passed else "failed",
        "realPtyBehavior": passed,
        "nativePtyApiAvailable": True,
        "prototypeComplete": True,
        "startupMs": round((time.perf_counter() - started) * 1000.0, 3),
        "rssBytes": 0,
    }


def dart_round(project: pathlib.Path, round_id: int) -> dict[str, Any]:
    dart = shutil.which("dart")
    if not dart:
        return {
            "roundId": round_id,
            "status": "unavailable",
            "realPtyBehavior": False,
            "requiresNativePtyHelper": True,
        }
    with tempfile.TemporaryDirectory(prefix="p2-dart-selection-") as tmp:
        script = pathlib.Path(tmp) / "probe.dart"
        script.write_text(DART_PROBE, encoding="utf-8")
        started = time.perf_counter()
        result = run([dart, str(script)], cwd=project, timeout=20)
        elapsed = (time.perf_counter() - started) * 1000.0
    try:
        payload = parse_last_json(result.stdout)
    except Exception:
        payload = {}
    ok = result.returncode == 0 and payload.get("pipeIoObserved") is True
    return {
        "roundId": round_id,
        "status": "feasible_with_native_helper" if ok else "failed",
        "realPtyBehavior": False,
        "requiresNativePtyHelper": True,
        "pipeIoObserved": bool(payload.get("pipeIoObserved")),
        "startupMs": round(elapsed, 3),
        "rssBytes": int(payload.get("rssBytes") or 0),
        "stderrTail": result.stderr[-2000:] if result.returncode else "",
    }


def summarize(rounds: list[dict[str, Any]], *, package_size_bytes: int) -> dict[str, Any]:
    startup = [float(row["startupMs"]) for row in rounds if isinstance(row.get("startupMs"), (int, float)) and row["startupMs"] > 0]
    rss = [int(row["rssBytes"]) for row in rounds if isinstance(row.get("rssBytes"), int) and row["rssBytes"] > 0]
    return {
        "rounds": rounds,
        "reliabilityPasses": sum(row.get("status") == "passed" for row in rounds),
        "roundCount": len(rounds),
        "medianStartupMs": round(statistics.median(startup), 3) if startup else None,
        "maxRssBytes": max(rss) if rss else None,
        "packageSizeBytes": package_size_bytes,
        "realPtyBehavior": all(row.get("realPtyBehavior") is True for row in rounds),
    }


def measure(project: pathlib.Path) -> dict[str, Any]:
    node_rounds = [node_round(project, index) for index in range(1, ROUNDS + 1)]
    native_rounds = [native_round(project, index) for index in range(1, ROUNDS + 1)]
    dart_rounds = [dart_round(project, index) for index in range(1, ROUNDS + 1)]
    node_files = list((project / "automation_host" / "src").glob("*.mjs")) + [
        project / "automation_host" / "package.json",
        project / "automation_host" / "package-lock.json",
    ]
    node_package = directory_size(project / "automation_host")
    dart = shutil.which("dart")
    dart_size = pathlib.Path(dart).stat().st_size if dart and pathlib.Path(dart).is_file() else 0
    return {
        "schemaVersion": 1,
        "task": "P2-004",
        "measurementClass": "technology_selection_not_production_certification",
        "platform": PLATFORM,
        "commitSha": git_head(project),
        "candidates": {
            NODE: {
                "candidateId": NODE,
                "implementationSha256": tree_fingerprint(node_files),
                "summary": summarize(node_rounds, package_size_bytes=node_package),
                "selectionEligible": all(row.get("status") == "passed" and row.get("realPtyBehavior") is True for row in node_rounds),
                "packagingRepairRequired": any(bool(row.get("packagingRepairApplied")) for row in node_rounds),
            },
            NATIVE: {
                "candidateId": NATIVE,
                "implementationSha256": hashlib.sha256(native_round.__code__.co_code).hexdigest(),
                "summary": summarize(native_rounds, package_size_bytes=0),
                "selectionEligible": all(row.get("status") == "passed" and row.get("realPtyBehavior") is True for row in native_rounds),
            },
            DART: {
                "candidateId": DART,
                "implementationSha256": hashlib.sha256(DART_PROBE.encode("utf-8")).hexdigest(),
                "summary": summarize(dart_rounds, package_size_bytes=dart_size),
                "selectionEligible": False,
                "requiresNativePtyHelper": True,
            },
        },
        "downstreamCertificationDeferredTo": ["P2-005", "P2-006"],
    }


def aggregate(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_platform = {str(row.get("platform")): row for row in records}
    required_platforms = {"windows", "macos", "linux"}
    if set(by_platform) != required_platforms:
        return {"schemaVersion": 1, "status": "blocked", "reason": "tri_platform_records_required", "platforms": sorted(by_platform)}
    commits = {str(row.get("commitSha")) for row in records}
    if len(commits) != 1:
        return {"schemaVersion": 1, "status": "blocked", "reason": "commit_mismatch", "commits": sorted(commits)}

    node_ok = True
    for name in sorted(required_platforms):
        node = by_platform[name].get("candidates", {}).get(NODE, {})
        summary = node.get("summary", {}) if isinstance(node, dict) else {}
        rounds = summary.get("rounds", []) if isinstance(summary, dict) else []
        if not (
            node.get("selectionEligible") is True
            and len(rounds) == ROUNDS
            and all(row.get("status") == "passed" and row.get("realPtyBehavior") is True for row in rounds if isinstance(row, dict))
        ):
            node_ok = False
            break
    if not node_ok:
        return {
            "schemaVersion": 1,
            "status": "blocked",
            "reason": "selected_candidate_lacks_real_tri_platform_pty_measurement",
            "commitSha": next(iter(commits)),
            "platformRecords": by_platform,
        }

    native_reasons = []
    dart_reasons = []
    for name in sorted(required_platforms):
        native = by_platform[name]["candidates"][NATIVE]
        dart = by_platform[name]["candidates"][DART]
        if native.get("selectionEligible") is not True:
            native_reasons.append(f"{name}: independent native supervisor not selection-ready")
        if dart.get("selectionEligible") is not True:
            dart_reasons.append(f"{name}: Dart path still requires a native PTY helper")

    return {
        "schemaVersion": 1,
        "status": "selected",
        "task": "P2-004",
        "commitSha": next(iter(commits)),
        "decision": {
            "selected": NODE,
            "basis": [
                "real node-pty PTY launch/input/output/resize passed in three rounds on Windows, macOS and Linux",
                "startup, resident-memory and package footprint were measured on each target OS",
                "macOS node-pty 1.1.0 spawn-helper execute-bit repair is recorded when required and must be resolved in packaging before downstream certification",
                "native-only alternative lacks an independent Windows supervisor prototype in this spike",
                "Dart control plane remains viable only with a native PTY helper and therefore adds a second implementation boundary",
            ],
            "rejected": {NATIVE: native_reasons, DART: dart_reasons},
        },
        "platformRecords": by_platform,
        "truthBoundary": {
            "p2_004TechnologySelected": True,
            "p2_005InteractivePtyCertified": False,
            "p2_006ProcessTreeCertified": False,
            "acceptanceDoesNotImplyReleaseSupport": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    measure_parser = sub.add_parser("measure")
    measure_parser.add_argument("--output", required=True)
    aggregate_parser = sub.add_parser("aggregate")
    aggregate_parser.add_argument("--input", action="append", required=True)
    aggregate_parser.add_argument("--output", required=True)
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    if args.command == "measure":
        value = measure(project)
        write_json(pathlib.Path(args.output), value)
        print(json.dumps(value, indent=2, sort_keys=True))
        node = value["candidates"][NODE]
        return 0 if node["selectionEligible"] else 1
    records = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in args.input]
    value = aggregate(records)
    write_json(pathlib.Path(args.output), value)
    print(json.dumps(value, indent=2, sort_keys=True))
    return 0 if value.get("status") == "selected" else 1


if __name__ == "__main__":
    raise SystemExit(main())
