#!/usr/bin/env python3
"""Executable P0-003 cross-platform repair gate.

This gate focuses on the integration failures reported after the first P0-003
starter attempt. It is standard-library-only and safe to run before Flutter is
installed. Flutter/Dart parsing, analysis, tests, and native builds remain
separate required gates.
"""
from __future__ import annotations

import argparse
import ast
from dataclasses import asdict, dataclass
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
GENERATORS = (
    "tool/generate_v170_contracts.py",
    "tool/generate_v180_contracts.py",
    "tool/generate_v190_contracts.py",
)
GENERATED = (
    "lib/product/generated/v170_contracts.g.dart",
    "lib/product/generated/v180_contracts.g.dart",
    "lib/product/generated/v190_contracts.g.dart",
)


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:  # noqa: BLE001 - report every failed invariant
        return Result(name, False, f"{type(error).__name__}: {error}")


def require(condition: bool, detail: str) -> None:
    if not condition:
        raise AssertionError(detail)


def test_literal_encoder() -> str:
    sys.path.insert(0, str(ROOT / "tool"))
    try:
        from dart_string_literal import dart_single_quoted_string
    finally:
        sys.path.pop(0)
    source = '{"$id":"schema","$ref":"#/$defs/item","path":"$.snapshotSha256","quote":"it\'s"}'
    encoded = dart_single_quoted_string(source)
    for token in (r"\$id", r"\$ref", r"#/\$defs/item", r"\$.snapshotSha256", r"it\'s"):
        require(token in encoded, f"encoded literal lacks {token}")
    require(not re.search(r"(?<!\\)\$", encoded), "an unescaped dollar remains")
    return "backslash, quote, dollar, newline, and Unicode line separators are encoded"


def test_generators_use_shared_encoder() -> str:
    for relative in GENERATORS:
        source = read(relative)
        ast.parse(source, filename=relative)
        require(
            "from dart_string_literal import dart_single_quoted_string" in source,
            f"{relative} does not import the shared encoder",
        )
        require(
            "escaped = dart_single_quoted_string(encoded)" in source,
            f"{relative} does not use the shared encoder",
        )
    return "three generators share one reviewed Dart literal encoder"


def test_generated_dart_dollar_safety() -> str:
    unsafe = re.compile(r"(?<!\\)\$(?:id|schema|ref|defs|\.snapshotSha256)")
    inspected = 0
    for relative in GENERATED:
        source = read(relative)
        matches = unsafe.findall(source)
        require(not matches, f"{relative} retains unescaped interpolation tokens: {matches[:5]}")
        inspected += source.count("\\$")
    require(inspected > 0, "generated schemas contain no escaped dollar evidence")
    return f"generated schemas contain {inspected} escaped dollar occurrences and no known unsafe token"


def test_generator_check_mode() -> str:
    for relative in GENERATORS:
        completed = subprocess.run(
            [sys.executable, relative, "--check"],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            check=False,
            timeout=60,
        )
        require(completed.returncode == 0, f"{relative} --check failed: {completed.stdout[-1000:]}")
    return "v170/v180/v190 generated files exactly match their generators"


def test_durable_jsonpath_literal() -> str:
    source = read("lib/product/durable_workflow.dart")
    require("json_extract(e.payload_json, '\\$.snapshotSha256')" in source, "escaped JSONPath is absent")
    require("json_extract(e.payload_json, '$.snapshotSha256')" not in source, "unescaped JSONPath remains")
    return "SQLite JSONPath remains literal at runtime without Dart interpolation"


def test_resource_import_fails_closed() -> str:
    source = read("tool/sandbox_worker.py")
    require("except ImportError" in source and "resource = None" in source, "resource import is not guarded")
    require("and resource is not None" in source, "sandbox availability does not require resource limits")
    require("if resource is None:" in source, "resource-limit application does not fail closed")

    probe = r'''
import builtins, importlib.util, pathlib, sys, types
path = pathlib.Path(sys.argv[1])
real_import = builtins.__import__
def guarded(name, *args, **kwargs):
    if name == "resource":
        raise ImportError("simulated non-POSIX host")
    return real_import(name, *args, **kwargs)
builtins.__import__ = guarded
stub = types.ModuleType("secret_broker")
stub.issue_secret = lambda *a, **k: {"handle": "unused"}
stub.consume_secret = lambda *a, **k: "unused"
sys.modules["secret_broker"] = stub
spec = importlib.util.spec_from_file_location("sandbox_worker_no_resource", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
assert module.resource is None
assert module.probe_backend()["available"] is False
try:
    module._apply_limits({})
except module.SandboxUnavailableError:
    pass
else:
    raise AssertionError("_apply_limits did not fail closed")
'''
    completed = subprocess.run(
        [sys.executable, "-c", probe, str(ROOT / "tool" / "sandbox_worker.py")],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        check=False,
        timeout=60,
    )
    require(completed.returncode == 0, completed.stdout[-1500:])
    return "module imports without POSIX resource support and sandbox execution remains unavailable"


def test_sdk_gate_order_and_nonmutation() -> str:
    verify = read("tool/verify.sh")
    require(verify.index("flutter pub get") < verify.index("dart format"), "verify.sh formats before dependency resolution")
    require("dart format --output=none --set-exit-if-changed" in verify, "verify.sh mutates source")
    require("flutter analyze --no-pub --fatal-warnings --fatal-infos" in verify, "verify.sh analyzer flags drifted")
    require("flutter test --no-pub --concurrency=1 --reporter expanded" in verify, "verify.sh test flags drifted")

    validator = read("tool/validate_release.py")
    tree = ast.parse(validator)
    node = next(item for item in tree.body if isinstance(item, ast.FunctionDef) and item.name == "check_sdk")
    segment = ast.get_source_segment(validator, node) or ""
    compact_segment = re.sub(r"\s+", " ", segment)
    require(compact_segment.index('"pub", "get"') < compact_segment.index('"format"'), "release validator formats before pub get")
    require('"--no-pub", "--fatal-warnings", "--fatal-infos"' in compact_segment, "release validator analyzer flags drifted")
    require('"--no-pub", "--concurrency=1", "--reporter", "expanded"' in compact_segment, "release validator test flags drifted")
    return "dependency resolution precedes non-mutating format, analysis, and test gates"


def test_ci_contract() -> str:
    workflow = read(".github/workflows/ci.yml")
    malformed_steps = [
        line
        for line in workflow.splitlines()
        if re.match(r"^(?:  |    )- (?:name|run|uses):", line)
    ]
    require(not malformed_steps, f"CI steps escaped the job steps list: {malformed_steps[:3]}")
    require(workflow.index("flutter pub get") < workflow.index("dart format"), "CI formats before pub get")
    require("tool/prune_stale_legacy.dart" in workflow, "CI format scope omits the Dart migration tool")
    require("flutter analyze --no-pub --fatal-warnings --fatal-infos" in workflow, "CI analyzer is not strict")
    require("flutter test --no-pub --concurrency=1 --reporter expanded" in workflow, "CI tests are not deterministic")
    for command in (
        "python tool/v1_trust_disablement_test.py",
        "python tool/p0_003_repair_test.py",
        "python tool/generate_v170_contracts.py --check",
        "python tool/generate_v180_contracts.py --check",
        "python tool/generate_v190_contracts.py --check",
    ):
        require(command in workflow, f"CI is missing {command}")
    return "three-OS workflow reaches trust, generator, repair, format, analyzer, test, validator, and native-build gates"


def test_v1_trust_stays_disabled() -> str:
    completed = subprocess.run(
        [sys.executable, "tool/v1_trust_disablement_test.py"],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        check=False,
        timeout=60,
    )
    require(completed.returncode == 0, completed.stdout[-1500:])
    require("v1_trust_disabled" in completed.stdout, "trust-disablement receipt is absent")
    return "P0-002 forgery regression remains active"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output")
    args = parser.parse_args()
    results = [
        run_case("Shared Dart literal encoder", test_literal_encoder),
        run_case("Generators use the shared encoder", test_generators_use_shared_encoder),
        run_case("Generated Dart dollar safety", test_generated_dart_dollar_safety),
        run_case("Generated contract check mode", test_generator_check_mode),
        run_case("Durable workflow JSONPath literal", test_durable_jsonpath_literal),
        run_case("POSIX resource import fails closed", test_resource_import_fails_closed),
        run_case("SDK gate ordering and nonmutation", test_sdk_gate_order_and_nonmutation),
        run_case("Three-OS CI contract", test_ci_contract),
        run_case("P0-002 trust remains disabled", test_v1_trust_stays_disabled),
    ]
    failed = [item for item in results if not item.passed]
    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-003",
        "caseCount": len(results),
        "passedCount": len(results) - len(failed),
        "failedCount": len(failed),
        "passed": not failed,
        "results": [asdict(item) for item in results],
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        path = Path(args.json_output)
        if not path.is_absolute():
            path = ROOT / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
