#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

import secret_scan


def run(*args: str, cwd: Path) -> None:
    completed = subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise AssertionError(f"command failed: {args}\n{completed.stdout}\n{completed.stderr}")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kristin-secret-scan-") as raw:
        root = Path(raw)
        openai_fixture = "sk" + "-" + ("A" * 30)
        entropy_fixture = "qN8bYk4XwR1sT7vL2pM9cD6fH3jK5zQ0aE8uI1oP"
        aws_fixture = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
        slack_fixture = "xox" + "b-" + ("1234567890" * 3)
        (root / ".env").write_text(
            f"OPENAI_API_KEY='{openai_fixture}'\n",
            encoding="utf-8",
        )
        (root / "entropy.txt").write_text(
            f"credential='{entropy_fixture}'\n",
            encoding="utf-8",
        )
        (root / "blob.bin").write_bytes(
            b"\x00\x01" + aws_fixture.encode("ascii") + b"\x00",
        )
        with zipfile.ZipFile(root / "bundle.zip", "w") as archive:
            archive.writestr("config.txt", f"token='{slack_fixture}'\n")

        findings = secret_scan.scan_worktree(root)
        kinds = {finding.kind for finding in findings}
        assert "openai_key" in kinds
        assert "high_entropy_credential" in kinds
        assert "aws_access_key" in kinds
        assert "slack_token" in kinds
        assert all(len(finding.fingerprint) == 16 for finding in findings)
        serialized = json.dumps([finding.to_json() for finding in findings], sort_keys=True)
        assert openai_fixture not in serialized
        assert slack_fixture not in serialized

        first = findings[0]
        suppressions = root / ".secret-scan-allowlist.json"
        suppressions.write_text(
            json.dumps(
                {
                    "suppressions": [
                        {
                            "fingerprint": first.fingerprint,
                            "owner": "security-test",
                            "expiresAt": "2099-01-01T00:00:00Z",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        active, expired = secret_scan.load_suppressions(
            suppressions,
            datetime(2026, 8, 23, tzinfo=timezone.utc),
        )
        assert first.fingerprint in active and not expired

    with tempfile.TemporaryDirectory(prefix="kristin-secret-history-") as raw:
        root = Path(raw)
        run("git", "init", "-q", cwd=root)
        run("git", "config", "user.email", "test@example.invalid", cwd=root)
        run("git", "config", "user.name", "Kristin Test", cwd=root)
        historical = root / "historical.txt"
        github_fixture = "gh" + "p_" + ("C" * 30)
        historical.write_text(
            f"GITHUB_TOKEN='{github_fixture}'\n",
            encoding="utf-8",
        )
        run("git", "add", "historical.txt", cwd=root)
        run("git", "commit", "-qm", "seed history fixture", cwd=root)
        historical.unlink()
        run("git", "add", "-u", cwd=root)
        run("git", "commit", "-qm", "remove history fixture", cwd=root)
        findings, status = secret_scan.scan_history(root)
        assert status == "scanned"
        assert any(finding.kind == "github_token" for finding in findings)
        payload = json.dumps([finding.to_json() for finding in findings])
        assert github_fixture not in payload

    print("PASS secret scan v2: providers, entropy, archives, binary metadata, history and fingerprints")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
