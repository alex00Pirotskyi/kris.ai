#!/usr/bin/env python3
"""Construct the exact P2 integration-alignment candidate for PR #14.

The helper executes only from reviewed protected-main control code. It patches
an exact, SHA-pinned P1/P2 landing target without executing target Python code
until after the two authorized source edits have been applied. Any source drift,
additional changed path, unknown push failure, or roadmap-authority mismatch
fails closed.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Iterable


class AlignmentError(RuntimeError):
    """Raised when an exact integration precondition is not satisfied."""


def run(
    command: list[str],
    *,
    cwd: Path,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        errors="replace",
    )
    if check and completed.returncode != 0:
        joined = " ".join(command)
        raise AlignmentError(
            f"command failed ({completed.returncode}): {joined}\n{completed.stdout}"
        )
    return completed


def git(cwd: Path, *arguments: str, check: bool = True) -> str:
    return run(["git", *arguments], cwd=cwd, check=check).stdout.strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise AlignmentError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


def patch_validate_release(text: str) -> str:
    additions = (
        (
            "                          'tool/prune_stale_legacy.dart',\n",
            "                          'tool/prune_stale_legacy.dart',\n"
            "                          'automation_host/probes/dart_native_probe.dart',\n",
        ),
        (
            "                          'lib/product/p2_owner_mode.dart',\n",
            "                          'lib/product/p2_owner_mode.dart',\n"
            "                          'lib/product/p2_owner_risk_authority.dart',\n",
        ),
        (
            "                          'test/product/p2_owner_mode_test.dart',\n",
            "                          'test/product/p2_owner_mode_test.dart',\n"
            "                          'test/product/p2_owner_risk_contract_test.dart',\n"
            "                          'test/product/p2_owner_risk_runtime_smoke_test.dart',\n"
            "                          'test/product/p2_qa_preview_gate_test.dart',\n",
        ),
    )
    for old, new in additions:
        text = replace_once(text, old, new, "active Dart allowlist")

    text = replace_once(
        text,
        '    ui = read(ROOT / "lib/product/ui.dart")\n'
        '    chat = read(ROOT / "lib/product/chat_studio.dart")\n'
        '    advanced = read(ROOT / "lib/product/ui_advanced.dart")\n',
        '    ui = read(ROOT / "lib/product/ui.dart")\n'
        '    chat = read(ROOT / "lib/product/chat_studio.dart")\n'
        '    p2_shell = read(ROOT / "lib/product/p2_app_shell.dart")\n'
        '    advanced = read(ROOT / "lib/product/ui_advanced.dart")\n',
        "P2 shell source binding",
    )
    text = replace_once(
        text,
        '    if "home: ChatStudio(" not in ui:\n'
        '        failures.append("the application does not open in ChatStudio")\n',
        '    if "home: P2KristinShell(" not in ui:\n'
        '        failures.append("the application does not open in the governed P2 shell")\n'
        '    if "chat: ChatStudio(" not in ui:\n'
        '        failures.append(\n'
        '            "the governed P2 shell does not receive ChatStudio as its chat workspace"\n'
        '        )\n'
        '    if not source_contains(p2_shell, "final pages = <Widget>[ widget.chat,"):\n'
        '        failures.append(\n'
        '            "the governed P2 shell does not keep ChatStudio as its primary page"\n'
        '        )\n'
        '    if not source_contains(p2_shell, "label: \'Chat\',"):\n'
        '        failures.append("the governed P2 shell does not expose the Chat destination")\n',
        "ChatStudio/P2 shell UX contract",
    )
    return text


def patch_p2_workflow(text: str) -> str:
    old = (
        "          dart format --output=none --set-exit-if-changed "
        "lib/product test/product\n"
    )
    new = "          python tool/dart_format_scope.py --check\n"
    text = replace_once(text, old, new, "governed Dart format scope")
    if "dart format --output=none --set-exit-if-changed lib/product test/product" in text:
        raise AlignmentError("broad generator-mutating Dart formatter remains active")
    return text


def known_workflow_write_rejection(output: str) -> bool:
    lowered = output.lower()
    return (
        "refusing to allow a github app to create or update workflow" in lowered
        or "refusing to allow an oauth app to create or update workflow" in lowered
        or ("workflow" in lowered and "scope" in lowered and "refused" in lowered)
    )


def read_config(control: Path) -> dict[str, object]:
    path = control / "config/p2_integration_alignment.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    required = {
        "schemaVersion",
        "repository",
        "roadmapAuthority",
        "controlBaseSha",
        "targetBranch",
        "expectedTargetHead",
        "authorizedPaths",
        "appliedProgressPath",
    }
    missing = sorted(required.difference(payload))
    if missing:
        raise AlignmentError(f"alignment config missing keys: {missing}")
    return payload


def exact_lines(values: Iterable[str]) -> list[str]:
    return sorted({value.replace("\\", "/") for value in values if value})


def changed_paths(target: Path, *, cached: bool = False) -> list[str]:
    arguments = ["diff"]
    if cached:
        arguments.append("--cached")
    arguments.extend(["--name-only", "--diff-filter=ACDMRTUXB"])
    tracked = git(target, *arguments).splitlines()
    untracked = git(target, "ls-files", "--others", "--exclude-standard").splitlines()
    return exact_lines([*tracked, *untracked])


def progress_document(
    *, control_sha: str, target_sha: str, roadmap_authority: str
) -> str:
    return f"""# P2 integration validator alignment applied

**Recorded:** 2026-08-05
**Worker:** A
**Human roadmap authority:** `{roadmap_authority}`
**Protected control:** `{control_sha}`
**Reconciled PR #14 parent:** `{target_sha}`

## What changed

Two integration contracts were aligned with the already-merged P2 architecture:

1. `tool/validate_release.py` now inventories the five intentional P2 Dart sources that were already compiled and tested, and validates the shipped `P2KristinShell` composition rather than requiring the pre-P2 direct `ChatStudio` root.
2. `.github/workflows/p2-owner-mode.yml` now uses the governed handwritten-Dart format scope. Generator-owned Dart remains validated by its generators instead of being rewritten by a broad formatter.

No runtime API, P1 authority interface, Owner Mode command schema, evidence schema, message size, native boundary, or future-phase interface changes.

## Roadmap authorization

`docs/roadmap/MASTER.md` requires P2 to land as a complete tri-OS vertical slice without weakening validation or confusing Owner Mode with isolation. These edits repair the integration gates that prevented the existing P2 shell and source contracts from being evaluated on their actual architecture. They do not authorize P3 work.

## Validation performed

The protected controller requires and records:

- exact protected-main ancestry;
- exact PR #14 target head and remote-ref identity;
- exact one-time source anchors;
- governed source-manifest regeneration;
- P2 governed source inventory;
- P2 application-composition and runtime-resource contracts;
- P0-003 integration repair;
- strict roadmap validation;
- release validation with the current P2 shell contract;
- Git whitespace validation;
- an exact four-path candidate diff.

Fresh pull-request workflows must then rerun product gates, P1A, P2 source contracts, branch hygiene, and native builds on the resulting commit.

## Challenges encountered

The reconciled P2 branch passed formatting, Flutter analysis, Flutter tests, P1 closure, and security contracts on Windows, macOS, and Ubuntu, but failed at two stale integration assumptions. The release validator omitted five newly integrated Dart files and still expected `ChatStudio` to be the application root. Separately, the P2 workflow invoked `dart format` over generated files and therefore mutated six generator-owned outputs.

## Resolutions

The release gate was strengthened to prove the composed shell contains `ChatStudio` as the primary chat page and exposes the Chat destination. The formatter gate was narrowed to the repository's governed handwritten scope; generator verification remains independent and blocking.

## Compatibility impact

The P2 application shell, P1/P2 interfaces, persisted evidence formats, and parallel P3 branch contracts are unchanged. Parallel workers should rebase normally; there is no product-source redesign to merge.

## Remaining risks

This commit does not supply controlled-runner behavioral evidence and does not close P2. The owner-risk evidence finalizer must still run against the exact protected commit after PR #14 lands. Public-GA, production, independent-security, and signed-installer claims remain false.

## Merge considerations for parallel branches

Future-phase branches should retain `P2KristinShell` as the current application composition point and should not copy the removed broad formatter command. Any future UI composition change must update the release contract explicitly rather than satisfying it with comments or hidden routes.

## Next dependency-controlled action

Require fresh commit-specific PR #14 checks. Merge only when all protected source, product, P1A, P2, native-build, manifest, and governance gates pass. After landing, execute the exact protected P2 owner-risk behavioral evidence workflow and update P2 status documents before identifying—but not implementing—the first dependency-satisfied P3 task.
"""


def verify_candidate_contract(target: Path) -> None:
    validator = (target / "tool/validate_release.py").read_text(encoding="utf-8")
    workflow = (target / ".github/workflows/p2-owner-mode.yml").read_text(
        encoding="utf-8"
    )
    for path in (
        "automation_host/probes/dart_native_probe.dart",
        "lib/product/p2_owner_risk_authority.dart",
        "test/product/p2_owner_risk_contract_test.dart",
        "test/product/p2_owner_risk_runtime_smoke_test.dart",
        "test/product/p2_qa_preview_gate_test.dart",
    ):
        if validator.count(repr(path)) != 1:
            raise AlignmentError(
                f"validator allowlist does not contain {path} exactly once"
            )
    required_validator_tokens = (
        'p2_shell = read(ROOT / "lib/product/p2_app_shell.dart")',
        'if "home: P2KristinShell(" not in ui:',
        'if "chat: ChatStudio(" not in ui:',
        'source_contains(p2_shell, "final pages = <Widget>[ widget.chat,")',
        'source_contains(p2_shell, "label: \'Chat\',")',
    )
    for token in required_validator_tokens:
        if validator.count(token) != 1:
            raise AlignmentError(
                f"validator shell contract missing or duplicated: {token}"
            )
    if workflow.count("python tool/dart_format_scope.py --check") != 1:
        raise AlignmentError(
            "P2 workflow must invoke governed Dart format scope exactly once"
        )
    if "dart format --output=none --set-exit-if-changed lib/product test/product" in workflow:
        raise AlignmentError("P2 workflow still mutates generator-owned Dart")


def execute(control: Path, target: Path, status_path: Path) -> int:
    status: dict[str, object] = {
        "schemaVersion": "1.0.0",
        "status": "failed",
        "candidateCommit": "",
        "refUpdatedByAction": False,
        "error": "",
    }
    try:
        config = read_config(control)
        repository = str(config["repository"])
        if os.environ.get("GITHUB_REPOSITORY", repository) != repository:
            raise AlignmentError("workflow repository does not match reviewed config")
        roadmap_authority = str(config["roadmapAuthority"])
        if roadmap_authority != "docs/roadmap/MASTER.md":
            raise AlignmentError("MASTER.md is not the configured human roadmap authority")
        if not (control / roadmap_authority).is_file():
            raise AlignmentError("reviewed MASTER.md is absent from protected control")

        control_sha = git(control, "rev-parse", "HEAD")
        control_base = str(config["controlBaseSha"])
        run(
            ["git", "merge-base", "--is-ancestor", control_base, control_sha],
            cwd=control,
        )

        expected_target = str(config["expectedTargetHead"])
        target_branch = str(config["targetBranch"])
        target_sha = git(target, "rev-parse", "HEAD")
        if target_sha != expected_target:
            raise AlignmentError(
                f"target head mismatch: expected {expected_target}, found {target_sha}"
            )
        remote = git(target, "ls-remote", "origin", f"refs/heads/{target_branch}")
        remote_sha = remote.split()[0] if remote else ""
        if remote_sha != expected_target:
            raise AlignmentError(
                f"remote target mismatch: expected {expected_target}, found {remote_sha}"
            )
        if git(target, "status", "--porcelain"):
            raise AlignmentError("target checkout is not clean before alignment")

        validator_path = target / "tool/validate_release.py"
        workflow_path = target / ".github/workflows/p2-owner-mode.yml"
        validator_path.write_text(
            patch_validate_release(validator_path.read_text(encoding="utf-8")),
            encoding="utf-8",
            newline="\n",
        )
        workflow_path.write_text(
            patch_p2_workflow(workflow_path.read_text(encoding="utf-8")),
            encoding="utf-8",
            newline="\n",
        )
        applied_progress = str(config["appliedProgressPath"])
        progress_path = target / applied_progress
        progress_path.parent.mkdir(parents=True, exist_ok=True)
        progress_path.write_text(
            progress_document(
                control_sha=control_sha,
                target_sha=target_sha,
                roadmap_authority=roadmap_authority,
            ),
            encoding="utf-8",
            newline="\n",
        )

        run([sys.executable, "tool/p2_refresh_source_manifest.py", "."], cwd=target)
        verify_candidate_contract(target)

        validation_commands = (
            [sys.executable, "tool/p2_source_inventory_test.py", "--project", "."],
            [sys.executable, "tool/p2_patch_application_composition_test.py"],
            [sys.executable, "tool/p2_runtime_resource_contract_test.py"],
            [sys.executable, "tool/p0_003_repair_test.py"],
            [
                sys.executable,
                "tool/roadmap_control.py",
                "validate",
                "--project",
                ".",
                "--strict",
            ],
            [sys.executable, "tool/validate_release.py", "--skip-tests"],
        )
        for command in validation_commands:
            run(command, cwd=target)
        run(["git", "diff", "--check"], cwd=target)

        authorized = exact_lines(str(path) for path in config["authorizedPaths"])
        observed = changed_paths(target)
        if observed != authorized:
            raise AlignmentError(
                f"candidate path mismatch: expected {authorized}, observed {observed}"
            )

        git(target, "config", "user.name", "Kristin P2 Integration")
        git(
            target,
            "config",
            "user.email",
            "41898282+github-actions[bot]@users.noreply.github.com",
        )
        git(target, "add", "--", *authorized)
        run(["git", "diff", "--cached", "--check"], cwd=target)
        cached = changed_paths(target, cached=True)
        if cached != authorized:
            raise AlignmentError(
                f"cached candidate mismatch: expected {authorized}, observed {cached}"
            )
        git(
            target,
            "commit",
            "-m",
            "fix(p2): align release and formatter integration contracts",
        )
        candidate = git(target, "rev-parse", "HEAD")
        parent = git(target, "rev-parse", "HEAD^1")
        if parent != expected_target:
            raise AlignmentError(
                f"candidate parent mismatch: expected {expected_target}, found {parent}"
            )
        commit_paths = exact_lines(
            git(
                target,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                candidate,
            ).splitlines()
        )
        if commit_paths != authorized:
            raise AlignmentError(
                f"committed path mismatch: expected {authorized}, observed {commit_paths}"
            )

        push = run(
            ["git", "push", "origin", f"HEAD:refs/heads/{target_branch}"],
            cwd=target,
            check=False,
        )
        status.update(
            {
                "repository": repository,
                "roadmapAuthority": roadmap_authority,
                "controlBaseSha": control_base,
                "controlHead": control_sha,
                "targetBranch": target_branch,
                "expectedTargetHead": expected_target,
                "candidateCommit": candidate,
                "authorizedPaths": authorized,
                "pushOutput": push.stdout[-4000:],
            }
        )
        if push.returncode == 0:
            status["status"] = "ref-updated"
            status["refUpdatedByAction"] = True
        elif known_workflow_write_rejection(push.stdout):
            status["status"] = "candidate-ready"
        else:
            raise AlignmentError(
                f"unexpected target publication failure ({push.returncode}): "
                f"{push.stdout}"
            )
        return 0
    except Exception as failure:
        status["error"] = str(failure)
        return 1
    finally:
        status_path.parent.mkdir(parents=True, exist_ok=True)
        status_path.write_text(
            json.dumps(status, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )


def self_test() -> None:
    sample_validator = """EXPECTED_DART_FILES = {
                          'tool/prune_stale_legacy.dart',
                          'lib/product/p2_owner_mode.dart',
                          'test/product/p2_owner_mode_test.dart',
}

def ux():
    ui = read(ROOT / "lib/product/ui.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    advanced = read(ROOT / "lib/product/ui_advanced.dart")
    failures = []

    if "home: ChatStudio(" not in ui:
        failures.append("the application does not open in ChatStudio")
"""
    patched = patch_validate_release(sample_validator)
    assert "P2KristinShell" in patched
    assert "p2_owner_risk_authority.dart" in patched
    assert "dart_native_probe.dart" in patched
    try:
        patch_validate_release(patched)
    except AlignmentError:
        pass
    else:
        raise AssertionError("validator patch must reject replay")

    sample_workflow = (
        "steps:\n"
        "      - name: Exact source and toolchain gates\n"
        "        run: |\n"
        "          dart format --output=none --set-exit-if-changed "
        "lib/product test/product\n"
    )
    patched_workflow = patch_p2_workflow(sample_workflow)
    assert "python tool/dart_format_scope.py --check" in patched_workflow
    try:
        patch_p2_workflow(patched_workflow)
    except AlignmentError:
        pass
    else:
        raise AssertionError("workflow patch must reject replay")

    assert known_workflow_write_rejection(
        "refusing to allow a GitHub App to create or update workflow "
        ".github/workflows/x.yml"
    )
    assert not known_workflow_write_rejection("remote rejected: protected branch")

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        status = root / "status.json"
        status.write_text("{}\n", encoding="utf-8")
        assert status.is_file()
    print("P2 integration alignment exact-patch self-test: PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--control", type=Path)
    parser.add_argument("--target", type=Path)
    parser.add_argument("--status", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    if arguments.control is None or arguments.target is None or arguments.status is None:
        parser.error("--control, --target, and --status are required for execution")
    return execute(
        arguments.control.resolve(),
        arguments.target.resolve(),
        arguments.status.resolve(),
    )


if __name__ == "__main__":
    raise SystemExit(main())
