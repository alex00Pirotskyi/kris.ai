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


def test_ci_receipt_portability() -> str:
    def load_module(relative: str, name: str):
        spec = importlib.util.spec_from_file_location(name, ROOT / relative)
        require(spec is not None and spec.loader is not None, f"cannot load {relative}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    capture = load_module("tool/capture_ci_environment.py", "p0_003_capture_portability")
    flutter_bat = r"C:\Program Files\Flutter\bin\flutter.bat"
    command = capture.prepare_command(
        ["flutter", "--version", "--machine"],
        windows=True,
        resolver=lambda _name: flutter_bat,
        command_processor=r"C:\Windows\System32\cmd.exe",
    )
    require(command is not None, "Windows Flutter command was not resolved")
    require(command[:4] == [r"C:\Windows\System32\cmd.exe", "/d", "/s", "/c"], "batch launcher does not use cmd.exe")
    require("flutter.bat" in command[4] and "--machine" in command[4], "Flutter batch command lost arguments")
    native = capture.prepare_command(
        ["git", "--version"], windows=False, resolver=lambda _name: "/usr/bin/git"
    )
    require(native == ["/usr/bin/git", "--version"], "native executable resolution drifted")

    record = load_module("tool/record_p0_003_ci.py", "p0_003_record_url_hygiene")
    cleaned = record.normalize_https_url("https://example.invalid/run/123\r\n", "--workflow-run-url")
    require(cleaned == "https://example.invalid/run/123", "URL CR/LF normalization failed")
    try:
        record.normalize_https_url("http://example.invalid", "--workflow-run-url")
    except record.EvidenceError:
        pass
    else:
        raise AssertionError("non-HTTPS evidence URL was accepted")
    with tempfile.TemporaryDirectory(prefix="kristin-p0-003-manifest-") as directory:
        project = Path(directory)
        output = project / "release/evidence/P0-003/ci_matrix.json"
        other = project / "docs/roadmap/STATUS.md"
        output.parent.mkdir(parents=True, exist_ok=True)
        other.parent.mkdir(parents=True, exist_ok=True)
        output.write_text('{"status":"old"}\n', encoding="utf-8", newline="\n")
        other.write_text("# Status\n", encoding="utf-8", newline="\n")
        manifest = project / "SOURCE_MANIFEST.sha256"
        manifest.write_text(
            f"{record.sha256(other)}  docs/roadmap/STATUS.md\n"
            f"{record.sha256(output)}  release/evidence/P0-003/ci_matrix.json\n",
            encoding="utf-8",
            newline="\n",
        )
        other_digest = record.sha256(other)
        output.write_text('{"status":"passed"}\n', encoding="utf-8", newline="\n")
        record.refresh_source_manifest_entry(project, output)
        entries = {}
        for line in manifest.read_text(encoding="utf-8").splitlines():
            digest, relative = line.split("  ", 1)
            entries[relative] = digest
        require(entries["docs/roadmap/STATUS.md"] == other_digest, "manifest refresh changed an unrelated entry")
        require(
            entries["release/evidence/P0-003/ci_matrix.json"] == record.sha256(output),
            "recorded P0-003 output hash was not refreshed",
        )
        require(b"\r" not in manifest.read_bytes(), "refreshed source manifest contains CR bytes")
    return "Windows receipt portability, URL hygiene, and recorded source-manifest refresh are executable"


def test_sdk_gate_order_and_nonmutation() -> str:
    verify = read("tool/verify.sh")
    format_command = "tool/dart_format_scope.py --check"
    require(verify.index("flutter pub get") < verify.index(format_command), "verify.sh formats before dependency resolution")
    require("python3 tool/dart_format_scope.py --check" in verify, "verify.sh does not use the non-mutating handwritten scope")
    require("flutter analyze --no-pub --fatal-warnings --fatal-infos" in verify, "verify.sh analyzer flags drifted")
    require("flutter test --no-pub --concurrency=1 --reporter expanded" in verify, "verify.sh test flags drifted")

    validator = read("tool/validate_release.py")
    tree = ast.parse(validator)
    node = next(item for item in tree.body if isinstance(item, ast.FunctionDef) and item.name == "check_sdk")
    segment = ast.get_source_segment(validator, node) or ""
    compact_segment = re.sub(r"\s+", " ", segment)
    require(compact_segment.index('"pub", "get"') < compact_segment.index('"tool/dart_format_scope.py", "--check"'), "release validator formats before pub get")
    require('"tool/dart_format_scope.py", "--check"' in compact_segment, "release validator does not use the handwritten scope")
    require('"--no-pub", "--fatal-warnings", "--fatal-infos"' in compact_segment, "release validator analyzer flags drifted")
    require('"--no-pub", "--concurrency=1", "--reporter", "expanded"' in compact_segment, "release validator test flags drifted")
    return "dependency resolution precedes non-mutating format, analysis, and test gates"


def test_ci_contract() -> str:
    workflow = read(".github/workflows/ci.yml")
    lines = workflow.splitlines()
    active_steps_indents: list[int] = []
    malformed_steps: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        while active_steps_indents and indent <= active_steps_indents[-1]:
            active_steps_indents.pop()
        if re.fullmatch(r"steps:\s*(?:#.*)?", stripped):
            active_steps_indents.append(indent)
            continue
        if re.match(r"^-\s+(?:name|run|uses):", stripped):
            if not active_steps_indents or indent <= active_steps_indents[-1]:
                malformed_steps.append(line)
    require(not malformed_steps, f"CI steps escaped the job steps list: {malformed_steps[:3]}")

    def position(*tokens: str) -> int:
        for index, line in enumerate(lines):
            compact = " ".join(line.strip().split())
            if all(token in compact for token in tokens):
                return index
        raise AssertionError("CI is missing command tokens: " + " ".join(tokens))

    pub_get = position("flutter", "pub", "get")
    format_check = position("tool/dart_format_scope.py", "--check")
    require(pub_get < format_check, "CI formats before pub get")
    position("flutter", "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos")
    position("flutter", "test", "--no-pub", "--concurrency=1", "--reporter", "expanded")
    for command_tokens in (
        ("python", "tool/v1_trust_disablement_test.py"),
        ("python", "tool/p0_003_repair_test.py"),
        ("python", "tool/generate_v170_contracts.py", "--check"),
        ("python", "tool/generate_v180_contracts.py", "--check"),
        ("python", "tool/generate_v190_contracts.py", "--check"),
    ):
        position(*command_tokens)
    explicit_jobs = all(
        re.search(rf"(?m)^\s*{re.escape(job_name)}:\s*(?:#.*)?$", workflow) is not None
        for job_name in ("validate-ubuntu", "validate-windows", "validate-macos")
    )
    matrix_jobs = (
        "validate-${{ matrix.lane }}" in workflow
        and all(re.search(rf"(?m)^\s*-\s+lane:\s*{lane}\s*(?:#.*)?$", workflow) is not None
                for lane in ("ubuntu", "windows", "macos"))
    )
    require(explicit_jobs or matrix_jobs, "CI does not expose stable Ubuntu, Windows, and macOS validation job names")
    return "three-OS workflow keeps every step inside its job and reaches trust, generator, repair, format, analyzer, test, validator, and native-build gates"



def test_handwritten_format_scope() -> str:
    completed = subprocess.run(
        [sys.executable, "tool/dart_format_scope_test.py"],
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
    scope = read("tool/dart_format_scope.py")
    require('"generated"' in scope and '".g.dart"' in scope, "format helper lacks generated exclusions")
    return "handwritten Dart is format-owned while generated contracts remain generator-owned"


def test_project_manager_system_contract_alignment() -> str:
    gate = read("tool/project_manager_v2_test.py")
    system = read("tool/system_test.py")
    capability_aware = (
        "Managed Run terminates the sandbox tree or fails closed when unavailable"
    )
    legacy = "Managed Run can be stopped with its process group"
    require(capability_aware in gate, "Project Manager capability-aware Run/Stop case is absent")
    require(capability_aware in system, "system contract does not recognize the capability-aware Run/Stop label")
    require(legacy in system, "system contract dropped compatibility with the reviewed legacy Run/Stop label")

    tree = ast.parse(system, filename="tool/system_test.py")
    condition = None
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or len(node.args) < 2:
            continue
        function_name = node.func.id if isinstance(node.func, ast.Name) else None
        first = node.args[0]
        if (
            function_name == "Result"
            and isinstance(first, ast.Constant)
            and first.value == "V1.6 Project Manager 2 operational layer"
        ):
            condition = node.args[1]
            break
    require(condition is not None, "V1.6 Project Manager aggregate predicate was not found")
    required_tokens = (
        "ProjectProfileV2",
        "snapshot_writable",
        "managed_project_processes",
        "artifact_records",
        "probe_backend",
        "ProjectManagerV2Service",
        "project_manager_snapshot",
    )
    compiled = compile(
        ast.fix_missing_locations(ast.Expression(condition)),
        "<p0-003-v1.6-system-contract>",
        "eval",
    )

    def evaluate(run_label: str) -> bool:
        namespace = {
            "contains_all": lambda source, values: all(value in source for value in values),
            "project_manager_tool": " ".join(required_tokens),
            "project_manager_v2": "",
            "v170_contracts": "",
            "project_manager_gate": (
                run_label + "\nAppend-only intelligence records reject mutation"
            ),
            "cli_source": "--project-manager",
        }
        return bool(eval(compiled, {"__builtins__": {}}, namespace))

    require(evaluate(capability_aware), "V1.6 aggregate rejects the renamed successful Project Manager gate")
    require(evaluate(legacy), "V1.6 aggregate dropped reviewed legacy-label compatibility")
    require(not evaluate("unrelated passing test"), "V1.6 aggregate accepts a missing Run/Stop gate")
    return "Project Manager executable labels and cumulative source-contract aggregation agree"

def test_status_terminal_newline() -> str:
    status = (ROOT / "docs/roadmap/STATUS.md").read_bytes()
    require(status.endswith(b"\n"), "STATUS.md lacks its terminal newline")
    require(not status.endswith(b"\n\n"), "STATUS.md has a blank line at EOF")
    return "generated STATUS.md ends with exactly one LF and passes Git whitespace policy"

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
        run_case("CI receipt portability", test_ci_receipt_portability),
        run_case("SDK gate ordering and nonmutation", test_sdk_gate_order_and_nonmutation),
        run_case("Three-OS CI contract", test_ci_contract),
        run_case("Handwritten Dart formatting scope", test_handwritten_format_scope),
        run_case("Project Manager system-contract alignment", test_project_manager_system_contract_alignment),
        run_case("STATUS terminal newline", test_status_terminal_newline),
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
