#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tarfile
from typing import Iterable, Iterator
import zipfile

from source_tree_policy import is_generated_path

ROOT = Path(__file__).resolve().parents[1]
SKIP_PARTS = {"archive", ".git", ".dart_tool", "build", "dist", "node_modules", "__pycache__"}
TEXT_EXTENSIONS = {
    ".dart", ".yaml", ".yml", ".json", ".md", ".py", ".sh", ".ps1",
    ".toml", ".txt", ".xml", ".html", ".js", ".ts", ".ini", ".cfg",
    ".env", ".properties",
}
ARCHIVE_EXTENSIONS = {".zip", ".tar", ".tgz", ".gz"}
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_ARCHIVE_MEMBER_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_SCAN_BYTES = 16 * 1024 * 1024

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("private_key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("openai_key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("github_token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("telegram_token", re.compile(r"\b\d{7,12}:[A-Za-z0-9_-]{30,}\b")),
    ("aws_access_key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("google_api_key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b")),
    ("slack_token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("stripe_live_key", re.compile(r"\bsk_live_[A-Za-z0-9]{20,}\b")),
    (
        "generic_assignment",
        re.compile(
            r"(?i)\b(?:api[_-]?key|client[_-]?secret|secret|password|access[_-]?token|credential)"
            r"\s*[:=]\s*[\"'][^\"'\n]{16,}[\"']"
        ),
    ),
)
ENTROPY_CONTEXT = re.compile(
    r"(?i)(?:api[_-]?key|secret|password|token|credential).{0,32}([A-Za-z0-9+/=_-]{28,})"
)


@dataclass(frozen=True)
class Finding:
    source: str
    file: str
    line: int
    kind: str
    fingerprint: str

    def to_json(self) -> dict[str, object]:
        return {
            "source": self.source,
            "file": self.file,
            "line": self.line,
            "kind": self.kind,
            "fingerprint": self.fingerprint,
        }


def fingerprint(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]


def looks_placeholder(value: str) -> bool:
    lower = value.lower()
    return any(
        marker in lower
        for marker in (
            "<redacted>", "redacted", "example", "placeholder", "your_", "your-",
            "${", "environment:", "dummy", "fake-token", "test-secret", "not-a-secret",
        )
    )


def shannon_entropy(value: str) -> float:
    if not value:
        return 0.0
    counts: dict[str, int] = {}
    for char in value:
        counts[char] = counts.get(char, 0) + 1
    length = len(value)
    return -sum((count / length) * math.log2(count / length) for count in counts.values())


def scan_text(text: str, *, source: str, file: str) -> list[Finding]:
    findings: list[Finding] = []
    seen: set[tuple[str, int, str]] = set()
    for kind, pattern in PATTERNS:
        for match in pattern.finditer(text):
            value = match.group(0)
            if looks_placeholder(value):
                continue
            line = text.count("\n", 0, match.start()) + 1
            key = (kind, line, fingerprint(value))
            if key in seen:
                continue
            seen.add(key)
            findings.append(Finding(source, file, line, kind, key[2]))
    for match in ENTROPY_CONTEXT.finditer(text):
        value = match.group(1)
        if looks_placeholder(value):
            continue
        if re.fullmatch(r"[0-9a-fA-F]{32,128}", value):
            continue
        if shannon_entropy(value) < 4.2:
            continue
        line = text.count("\n", 0, match.start(1)) + 1
        key = ("high_entropy_credential", line, fingerprint(value))
        if key in seen:
            continue
        seen.add(key)
        findings.append(Finding(source, file, line, key[0], key[2]))
    return findings


def iter_worktree_files(root: Path) -> Iterator[Path]:
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if is_generated_path(relative):
            continue
        yield path


def scan_archive(path: Path, relative: str) -> list[Finding]:
    findings: list[Finding] = []
    consumed = 0

    def scan_member(name: str, data: bytes) -> None:
        nonlocal consumed
        if len(data) > MAX_ARCHIVE_MEMBER_BYTES:
            return
        consumed += len(data)
        if consumed > MAX_ARCHIVE_SCAN_BYTES:
            return
        text = data.decode("utf-8", errors="replace")
        findings.extend(scan_text(text, source="archive", file=f"{relative}!{name}"))

    try:
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                for info in archive.infolist():
                    if info.is_dir() or info.file_size > MAX_ARCHIVE_MEMBER_BYTES:
                        continue
                    if consumed >= MAX_ARCHIVE_SCAN_BYTES:
                        break
                    scan_member(info.filename, archive.read(info))
        elif tarfile.is_tarfile(path):
            with tarfile.open(path, "r:*") as archive:
                for info in archive.getmembers():
                    if not info.isfile() or info.size > MAX_ARCHIVE_MEMBER_BYTES:
                        continue
                    if consumed >= MAX_ARCHIVE_SCAN_BYTES:
                        break
                    stream = archive.extractfile(info)
                    if stream is not None:
                        scan_member(info.name, stream.read(MAX_ARCHIVE_MEMBER_BYTES + 1))
    except (OSError, ValueError, zipfile.BadZipFile, tarfile.TarError):
        return findings
    return findings


def scan_worktree(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    for path in iter_worktree_files(root):
        relative = path.relative_to(root).as_posix()
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if path.suffix.lower() in ARCHIVE_EXTENSIONS:
            findings.extend(scan_archive(path, relative))
            continue
        if size > MAX_FILE_BYTES:
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if path.suffix.lower() in TEXT_EXTENSIONS or b"\x00" not in data[:4096]:
            findings.extend(
                scan_text(data.decode("utf-8", errors="replace"), source="worktree", file=relative)
            )
        else:
            metadata = data[: min(len(data), MAX_FILE_BYTES)].decode("latin1", errors="replace")
            findings.extend(scan_text(metadata, source="binary_metadata", file=relative))
    return findings


def scan_history(root: Path) -> tuple[list[Finding], str]:
    git = root / ".git"
    if not git.exists():
        return [], "unavailable_no_git_metadata"
    command = [
        "git", "-C", str(root), "log", "--all", "--no-ext-diff", "--no-color", "-p",
        "--pretty=format:@@KRISTIN_COMMIT:%H",
    ]
    try:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError:
        return [], "unavailable_git_not_found"
    findings: list[Finding] = []
    commit = "unknown"
    file = "history"
    line_no = 0
    assert process.stdout is not None
    for raw in process.stdout:
        line = raw.rstrip("\n")
        if line.startswith("@@KRISTIN_COMMIT:"):
            commit = line.split(":", 1)[1]
            file = "history"
            line_no = 0
            continue
        if line.startswith("+++ b/"):
            file = line[6:]
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        line_no += 1
        for finding in scan_text(line[1:], source=f"history:{commit}", file=file):
            findings.append(Finding(finding.source, finding.file, line_no, finding.kind, finding.fingerprint))
    stderr = process.stderr.read() if process.stderr is not None else ""
    return_code = process.wait()
    if return_code != 0:
        return findings, f"failed:{return_code}:{fingerprint(stderr)}"
    return findings, "scanned"


def load_suppressions(path: Path, now: datetime) -> tuple[set[str], list[dict[str, str]]]:
    if not path.is_file():
        return set(), []
    payload = json.loads(path.read_text(encoding="utf-8"))
    active: set[str] = set()
    expired: list[dict[str, str]] = []
    for row in payload.get("suppressions") or []:
        fp = str(row.get("fingerprint") or "")
        owner = str(row.get("owner") or "")
        expires_raw = str(row.get("expiresAt") or "")
        if not fp or not owner or not expires_raw:
            expired.append({"fingerprint": fp, "owner": owner, "reason": "invalid_suppression"})
            continue
        expires = datetime.fromisoformat(expires_raw.replace("Z", "+00:00")).astimezone(timezone.utc)
        if expires <= now.astimezone(timezone.utc):
            expired.append({"fingerprint": fp, "owner": owner, "reason": "expired"})
        else:
            active.add(fp)
    return active, expired


def dedupe(findings: Iterable[Finding]) -> list[Finding]:
    unique: dict[tuple[str, str, int, str, str], Finding] = {}
    for finding in findings:
        key = (finding.source, finding.file, finding.line, finding.kind, finding.fingerprint)
        unique[key] = finding
    return [unique[key] for key in sorted(unique)]


def build_report(root: Path, *, include_history: bool, suppression_path: Path) -> dict[str, object]:
    now = datetime.now(timezone.utc)
    findings = scan_worktree(root)
    history_status = "disabled"
    if include_history:
        history_findings, history_status = scan_history(root)
        findings.extend(history_findings)
    active_suppressions, expired_suppressions = load_suppressions(suppression_path, now)
    filtered = [finding for finding in dedupe(findings) if finding.fingerprint not in active_suppressions]
    return {
        "schemaVersion": "2.0.0",
        "passed": not filtered and not expired_suppressions,
        "findingCount": len(filtered),
        "findings": [finding.to_json() for finding in filtered],
        "historyStatus": history_status,
        "suppressionCount": len(active_suppressions),
        "expiredSuppressions": expired_suppressions,
        "printsSecretValues": False,
        "capabilities": [
            "working_tree",
            "git_history",
            "provider_detectors",
            "entropy_detection",
            "archive_inspection",
            "binary_metadata",
            "fingerprint_only_reporting",
            "owned_expiring_suppressions",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=str(ROOT))
    parser.add_argument("--report")
    parser.add_argument("--no-history", action="store_true")
    parser.add_argument("--suppressions", default=".secret-scan-allowlist.json")
    args = parser.parse_args()
    root = Path(args.project).expanduser().resolve()
    report_path = Path(args.report).expanduser().resolve() if args.report else root / "release" / "SECRET_SCAN.json"
    suppression_path = Path(args.suppressions)
    if not suppression_path.is_absolute():
        suppression_path = root / suppression_path
    report = build_report(
        root,
        include_history=not args.no_history,
        suppression_path=suppression_path,
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "passed": report["passed"],
                "findingCount": report["findingCount"],
                "historyStatus": report["historyStatus"],
                "report": str(report_path),
            },
            sort_keys=True,
        )
    )
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
