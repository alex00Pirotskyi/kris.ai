#!/usr/bin/env python3
"""Self-test qualification ordering/fail-closed behavior with fake toolchains.

Actual 20-slice application is covered separately by validate_orchestrator_smoke.py.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
QUALIFIER = ROOT / "qualify_real_checkout.py"

TOOLS = [
    "toolchain_lock_test.py",
    "workflow_kernel_test.py",
    "validate_release.py",
]

PRODUCTION_GATE_NEEDLES = [
    "toolchain_lock_test.py",
    "generate_v170_contracts.py",
    "generate_v180_contracts.py",
    "generate_v190_contracts.py",
    "generate_protocol_contracts.py",
    "source_tree_policy_test.py",
    "generated_state_guard_test.py",
    "generated_state_guard.py",
    "p0_007_assurance_test.py",
    "generate_workflow_migrations.py",
    "workflow_kernel_test.py",
    "generate_prompt_studio_contracts.py",
    "generate_prompt_studio_fixtures.py",
    "prompt_studio_v2_test.py",
    "dart_format_scope.py",
    "validate_release.py",
]


def write_executable(path: Path, source: str) -> None:
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def make_repo(
    base: Path,
    *,
    fail_gate: str | None = None,
    mutate_lock_on_pub: bool = False,
) -> tuple[Path, Path]:
    repo = base / "repo"
    repo.mkdir()
    for directory in ["tool", "config", "test/product/task_kernel", "test/product", "lib/product/task_kernel"]:
        (repo / directory).mkdir(parents=True, exist_ok=True)
    markers = {
        "lib/product/run_steering_record.dart": "class TaskSpecificationPatch {}\n",
        "lib/product/task_kernel/research_task_family_executor.dart": "class ResearchTaskFamilyExecutor {}\n",
        "lib/product/agent_delegation_record.dart": "class AgentDelegationRecord {}\n",
        "test/product/authority_convergence_contract_test.dart": "// authority convergence\n",
        "test/product/chat_failure_projection_contract_test.dart": "// technical error detail\n",
        "test/product/kristin_conversation_session_test.dart": "void main() {}\n",
    }
    for relative, content in markers.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    (repo / "pubspec.lock").write_text(
        "packages:\n"
        "  fixture_existing:\n"
        "    dependency: transitive\n"
        "    description:\n"
        "      name: fixture_existing\n"
        "      url: \"https://pub.dev\"\n"
        "    source: hosted\n"
        "    version: \"1.0.0\"\n"
        "  timezone:\n"
        "    dependency: \"direct main\"\n"
        "    description:\n"
        "      name: timezone\n"
        "      url: \"https://pub.dev\"\n"
        "    source: hosted\n"
        "    version: \"0.10.1\"\n"
        "sdks:\n"
        "  dart: \">=3.5.0 <4.0.0\"\n",
        encoding="utf-8",
    )
    (repo / "config/toolchains.lock.json").write_text(
        json.dumps({
            "schemaVersion": "1.0.0",
            "sourceCommit": "0" * 40,
            "python": {"version": "3.12.10"},
            "flutter": {"version": "3.44.8", "channel": "stable"},
            "dart": {"version": "3.12.2", "pinnedBy": "flutter-sdk"},
            "githubActions": {},
            "runners": {"ubuntu": "ubuntu-24.04", "windows": "windows-2025", "macos": "macos-15"},
            "cache": {},
            "lockfiles": [{"path": "pubspec.lock", "sha256": "0" * 64}],
            "declaredInputFingerprint": "0" * 64,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    (repo / "SOURCE_MANIFEST.sha256").write_text("original\n", encoding="utf-8")
    for name in TOOLS:
        rc = 7 if name == fail_gate else 0
        (repo / "tool" / name).write_text(
            f"import sys\nprint('FAKE {name}')\nsys.exit({rc})\n",
            encoding="utf-8",
        )
    (repo / "tool/p2_refresh_source_manifest.py").write_text(
        "from pathlib import Path\nPath('SOURCE_MANIFEST.sha256').write_text('refreshed\\n')\n",
        encoding="utf-8",
    )

    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Qualifier Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "seed"], check=True)

    # Create one changed Dart path so the qualifier exercises its scoped format path.
    with (repo / "lib/product/run_steering_record.dart").open("a", encoding="utf-8") as handle:
        handle.write("// changed\n")

    bin_dir = base / "bin"
    bin_dir.mkdir()
    write_executable(
        bin_dir / "flutter",
        "#!/usr/bin/env python3\n"
        "import os, pathlib, sys\n"
        "print('FAKE FLUTTER', ' '.join(sys.argv[1:]))\n"
        "if os.environ.get('FAKE_MUTATE_LOCK') == '1' and sys.argv[1:3] == ['pub', 'get']:\n"
        "    p = pathlib.Path('pubspec.lock')\n"
        "    p.write_text(p.read_text().replace('version: \\\"1.0.0\\\"', 'version: \\\"1.0.1\\\"'))\n"
        "sys.exit(0)\n",
    )
    write_executable(
        bin_dir / "dart",
        "#!/usr/bin/env python3\nimport sys\nprint('FAKE DART', ' '.join(sys.argv[1:]))\nsys.exit(0)\n",
    )
    return repo, bin_dir


def run_case(
    *,
    fail_gate: str | None,
    mutate_lock_on_pub: bool = False,
    format_only: bool = False,
) -> tuple[int, dict, str]:
    with tempfile.TemporaryDirectory(prefix="one-kristin-qualifier-") as temp:
        base = Path(temp)
        repo, bin_dir = make_repo(
            base,
            fail_gate=fail_gate,
            mutate_lock_on_pub=mutate_lock_on_pub,
        )
        report_dir = base / "report"
        env = os.environ.copy()
        env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
        if mutate_lock_on_pub:
            env["FAKE_MUTATE_LOCK"] = "1"
        driver = base / "qualifier_driver.py"
        driver.write_text(
            "import sys\n"
            f"sys.path.insert(0, {str(ROOT)!r})\n"
            "import qualify_real_checkout as q\n"
            "q.PRE_ANALYZER_REPO_GATES = [['python', 'tool/workflow_kernel_test.py', '--project', '.']]\n"
            "q.POST_FLUTTER_REPO_GATES = [['python', 'tool/validate_release.py', '--skip-tests']]\n"
            "raise SystemExit(q.main())\n",
            encoding="utf-8",
        )
        command = [
            sys.executable,
            str(driver),
            str(repo),
            "--allow-head-mismatch",
            "--allow-dirty",
            "--already-applied",
            "--format",
        ]
        if not format_only:
            command.extend([
                "--repo-gates",
                "--focused",
                "--full-flutter",
                "--refresh-source-manifest",
            ])
        command.extend(["--report-dir", str(report_dir)])
        completed = subprocess.run(command, text=True, capture_output=True, env=env)
        payload = json.loads((report_dir / "one-kristin-qualification.json").read_text())
        manifest = (repo / "SOURCE_MANIFEST.sha256").read_text()
        return completed.returncode, payload, manifest


def main() -> int:
    qualifier_source = QUALIFIER.read_text(encoding="utf-8")
    missing = [needle for needle in PRODUCTION_GATE_NEEDLES if needle not in qualifier_source]
    assert not missing, f"production qualifier lost reviewed gate(s): {missing}"
    print("OK production qualifier retains reviewed gate inventory")

    rc, payload, manifest = run_case(fail_gate=None)
    assert rc == 0, payload
    assert payload["outcome"] == "passed"
    assert manifest == "refreshed\n"
    names = [item["name"] for item in payload["steps"]]
    assert names[0] == "verify bundle already applied"
    assert names.index("locked toolchain preflight") < names.index("flutter pub get")
    assert names.index("verify timezone lock") == names.index("flutter pub get") + 1
    assert names.index("sync governed toolchain lock") == names.index("verify timezone lock") + 1
    assert names.index("locked toolchain post-Pub") == names.index("sync governed toolchain lock") + 1
    assert "format changed Dart" in names
    assert "flutter analyze" in names
    assert "focused One-Kristin tests" in names
    assert "full Flutter tests" in names
    assert names[-2:] == ["refresh SOURCE_MANIFEST.sha256", "git diff --check"]
    print("OK qualifier success path and manifest-last ordering")

    rc, payload, manifest = run_case(fail_gate="workflow_kernel_test.py")
    assert rc == 1, payload
    assert payload["outcome"] == "failed"
    assert manifest == "original\n", "manifest changed despite earlier gate failure"
    names = [item["name"] for item in payload["steps"]]
    assert "refresh SOURCE_MANIFEST.sha256" not in names
    print("OK qualifier fails closed and preserves manifest on earlier gate failure")

    rc, payload, manifest = run_case(fail_gate=None, mutate_lock_on_pub=True)
    assert rc == 1, payload
    assert payload["outcome"] == "failed"
    assert "pre-existing locked packages" in (payload.get("failure") or "")
    assert manifest == "original\n", "manifest changed despite unrelated Pub lock churn"
    names = [item["name"] for item in payload["steps"]]
    assert "sync governed toolchain lock" not in names
    assert "refresh SOURCE_MANIFEST.sha256" not in names
    print("OK qualifier rejects unrelated pre-existing Pub lockfile churn")

    rc, payload, manifest = run_case(fail_gate=None, format_only=True)
    assert rc == 0, payload
    assert payload["outcome"] == "passed"
    assert manifest == "original\n", "format-only qualification must not refresh source manifest"
    names = [item["name"] for item in payload["steps"]]
    assert names == [
        "verify bundle already applied",
        "locked toolchain preflight",
        "format changed Dart",
    ], names
    assert "flutter pub get" not in names
    assert "flutter analyze" not in names
    print("OK format-only qualification verifies locked toolchain before formatting")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
