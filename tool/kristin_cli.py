#!/usr/bin/env python3
"""Local diagnostics and project commands for Kristin Local Agent.

The CLI intentionally uses only Python's standard library so a source checkout can
be diagnosed before Flutter or Dart is installed. Commands are executed without a
shell and are bounded where practical.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import zipfile
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from typing import Iterable, Sequence

import plan_compiler as prompt_studio_compiler
import execution_intelligence
import project_manager_v2
import sandbox_worker
import knowledge_memory_v2
import file_adapters
import interoperability_admin_v19
import release_ops_v19

VERSION = "1.9.0+190"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TIMEOUT = 8 * 60
MAX_CAPTURE = 2 * 1024 * 1024

_BASE_ENVIRONMENT_KEYS = frozenset(
    {
        "PATH",
        "PATHEXT",
        "SYSTEMROOT",
        "SYSTEMDRIVE",
        "WINDIR",
        "COMSPEC",
        "HOME",
        "USERPROFILE",
        "HOMEDRIVE",
        "HOMEPATH",
        "APPDATA",
        "LOCALAPPDATA",
        "PROGRAMDATA",
        "TMP",
        "TEMP",
        "LANG",
        "LC_ALL",
        "CI",
        "OS",
        "PROCESSOR_ARCHITECTURE",
        "PROCESSOR_IDENTIFIER",
        "NUMBER_OF_PROCESSORS",
    }
)

# Flutter and Dart use these variables to locate the Pub cache, SDKs, custom
# package mirrors, enterprise proxies, and certificate stores. Keeping them
# out of the child environment made `flutter pub get` fail under Kristin even
# when the same command succeeded in the user's terminal.
_SDK_ENVIRONMENT_KEYS = frozenset(
    {
        "PUB_CACHE",
        "PUB_HOSTED_URL",
        "PUB_ENVIRONMENT",
        "FLUTTER_ROOT",
        "FLUTTER_STORAGE_BASE_URL",
        "DART_SDK",
        "ANDROID_HOME",
        "ANDROID_SDK_ROOT",
        "JAVA_HOME",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "NO_PROXY",
        "ALL_PROXY",
        "SSL_CERT_FILE",
        "SSL_CERT_DIR",
        "CURL_CA_BUNDLE",
        "REQUESTS_CA_BUNDLE",
        "GIT_SSL_CAINFO",
        "GIT_CONFIG_GLOBAL",
        "GIT_CONFIG_SYSTEM",
        "GIT_SSH",
        "GIT_SSH_COMMAND",
        "SSH_AUTH_SOCK",
        "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME",
        "XDG_DATA_HOME",
    }
)


@dataclass(frozen=True)
class CommandSpec:
    label: str
    argv: tuple[str, ...]
    environment: tuple[tuple[str, str], ...] = ()
    environment_profile: str = "auto"
    execution_mode: str = "sandbox"

    @property
    def display(self) -> str:
        return subprocess.list2cmdline(list(self.argv))


@dataclass(frozen=True)
class ProjectProfile:
    kind: str
    required_executable: str = ""
    tests: tuple[CommandSpec, ...] = ()
    build: CommandSpec | None = None
    run: CommandSpec | None = None
    source: str = "detected"
    analysis: tuple[CommandSpec, ...] = ()


@dataclass
class Check:
    name: str
    status: str
    detail: str
    command: str = ""
    exit_code: int | None = None
    duration_ms: int | None = None
    output: str = ""


_sandbox_probe_cache: dict[str, object] | None = None


def sandbox_capabilities() -> dict[str, object]:
    global _sandbox_probe_cache
    if _sandbox_probe_cache is None:
        _sandbox_probe_cache = sandbox_worker.probe_backend()
    return dict(_sandbox_probe_cache)


def _command_workspace_mode(spec: CommandSpec) -> str:
    label = spec.label.lower()
    if any(token in label for token in ("analysis", "lint", "typecheck", "doctor")):
        return "read_only"
    return "snapshot_writable"


def _sandbox_output(stdout: str, stderr: str) -> str:
    payload: list[str] = []
    if stdout.strip():
        payload.append(stdout.rstrip())
    if stderr.strip():
        payload.append(stderr.rstrip())
    return "\n".join(payload)


@dataclass
class Report:
    command: str
    project: str
    version: str = VERSION
    generated_at: str = field(
        default_factory=lambda: dt.datetime.now(dt.timezone.utc).isoformat()
    )
    profile: str = "Unknown"
    checks: list[Check] = field(default_factory=list)

    @property
    def failed(self) -> bool:
        return any(check.status == "FAIL" for check in self.checks)

    @property
    def warnings(self) -> bool:
        return any(check.status in {"WARN", "SKIP"} for check in self.checks)

    def add(
        self,
        name: str,
        status: str,
        detail: str,
        *,
        command: str = "",
        exit_code: int | None = None,
        duration_ms: int | None = None,
        output: str = "",
    ) -> None:
        self.checks.append(
            Check(
                name=name,
                status=status,
                detail=detail,
                command=command,
                exit_code=exit_code,
                duration_ms=duration_ms,
                output=output,
            )
        )


def _read_json(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _command_from_json(value: object, label: str) -> CommandSpec | None:
    if not isinstance(value, dict):
        return None
    executable = str(value.get("executable", "")).strip()
    arguments = value.get("arguments", [])
    if not executable or not isinstance(arguments, list):
        return None
    return CommandSpec(label, tuple([executable, *[str(item) for item in arguments]]))


def _flutter_target() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def detect_profile(root: Path) -> ProjectProfile:
    custom_path = root / "kristin.project.json"
    if custom_path.is_file():
        custom = _read_json(custom_path)
        analyze = _command_from_json(custom.get("analyze"), "Custom project analysis")
        test = _command_from_json(custom.get("test"), "Custom project tests")
        build = _command_from_json(custom.get("build"), "Custom project build")
        run = _command_from_json(custom.get("run"), "Custom project run")
        required = next(
            (item.argv[0] for item in (analyze, test, build, run) if item is not None), ""
        )
        return ProjectProfile(
            kind=str(custom.get("type", "Custom")).strip() or "Custom",
            required_executable=required,
            tests=(test,) if test else (),
            build=build,
            run=run,
            source="kristin.project.json",
            analysis=(analyze,) if analyze else (),
        )

    pubspec = root / "pubspec.yaml"
    if pubspec.is_file():
        content = pubspec.read_text(encoding="utf-8", errors="replace")
        is_flutter = bool(re.search(r"sdk:\s*flutter", content)) or bool(
            re.search(r"(?m)^flutter:\s*$", content)
        )
        if is_flutter:
            return ProjectProfile(
                kind="Flutter",
                required_executable="flutter",
                tests=(
                    CommandSpec("Flutter analysis", ("flutter", "analyze")),
                    CommandSpec("Flutter tests", ("flutter", "test")),
                ),
                build=CommandSpec(
                    "Flutter desktop build", ("flutter", "build", _flutter_target())
                ),
                run=CommandSpec(
                    "Flutter desktop run",
                    ("flutter", "run", "-d", _flutter_target()),
                ),
                analysis=(CommandSpec("Flutter analysis", ("flutter", "analyze")),),
            )
        return ProjectProfile(
            kind="Dart",
            required_executable="dart",
            tests=(
                CommandSpec("Dart analysis", ("dart", "analyze")),
                CommandSpec("Dart tests", ("dart", "test")),
            ),
            run=CommandSpec("Dart application", ("dart", "run")),
            analysis=(CommandSpec("Dart analysis", ("dart", "analyze")),),
        )

    package_json = root / "package.json"
    if package_json.is_file():
        package = _read_json(package_json)
        scripts_value = package.get("scripts", {})
        scripts = scripts_value if isinstance(scripts_value, dict) else {}
        tests: list[CommandSpec] = []
        analysis: list[CommandSpec] = []
        if "lint" in scripts:
            lint = CommandSpec("JavaScript lint", ("npm", "run", "lint"))
            analysis.append(lint)
            tests.append(lint)
        if "typecheck" in scripts:
            analysis.append(
                CommandSpec("JavaScript typecheck", ("npm", "run", "typecheck"))
            )
        if "test" in scripts:
            tests.append(CommandSpec("JavaScript tests", ("npm", "test")))
        build = (
            CommandSpec("JavaScript build", ("npm", "run", "build"))
            if "build" in scripts
            else None
        )
        run_script = "dev" if "dev" in scripts else "start" if "start" in scripts else ""
        run = (
            CommandSpec("Node application", ("npm", "run", run_script))
            if run_script
            else None
        )
        return ProjectProfile(
            "Node.js / JavaScript",
            "npm",
            tuple(tests),
            build,
            run,
            analysis=tuple(analysis),
        )

    if any((root / name).is_file() for name in ("pyproject.toml", "requirements.txt", "setup.py")):
        python = "python" if os.name == "nt" else "python3"
        run_file = next(
            (name for name in ("main.py", "app.py", "server.py") if (root / name).is_file()),
            None,
        )
        return ProjectProfile(
            kind="Python",
            required_executable=python,
            tests=(CommandSpec("Python tests", (python, "-m", "pytest", "-q")),),
            build=CommandSpec("Python package build", (python, "-m", "build")),
            run=CommandSpec("Python application", (python, run_file)) if run_file else None,
            analysis=(
                CommandSpec(
                    "Python compile check",
                    (python, "-m", "compileall", "-q", "."),
                ),
            ),
        )

    if (root / "go.mod").is_file():
        return ProjectProfile(
            "Go",
            "go",
            (CommandSpec("Go tests", ("go", "test", "./...")),),
            CommandSpec("Go build", ("go", "build", "./...")),
            CommandSpec("Go run", ("go", "run", ".")),
            analysis=(CommandSpec("Go vet", ("go", "vet", "./...")),),
        )
    if (root / "Cargo.toml").is_file():
        return ProjectProfile(
            "Rust",
            "cargo",
            (CommandSpec("Rust tests", ("cargo", "test")),),
            CommandSpec("Rust build", ("cargo", "build")),
            CommandSpec("Rust run", ("cargo", "run")),
            analysis=(CommandSpec("Rust check", ("cargo", "check")),),
        )
    if any(root.glob("*.sln")) or any(root.glob("*.csproj")):
        return ProjectProfile(
            ".NET",
            "dotnet",
            (CommandSpec(".NET tests", ("dotnet", "test", "--nologo")),),
            CommandSpec(".NET build", ("dotnet", "build", "--nologo")),
            CommandSpec(".NET run", ("dotnet", "run")),
            analysis=(
                CommandSpec(".NET analysis build", ("dotnet", "build", "--nologo")),
            ),
        )
    if (root / "pom.xml").is_file():
        return ProjectProfile(
            "Java / Maven",
            "mvn",
            (CommandSpec("Maven tests", ("mvn", "test")),),
            CommandSpec("Maven package", ("mvn", "package", "-DskipTests")),
            analysis=(CommandSpec("Maven compile", ("mvn", "compile")),),
        )
    if any((root / name).exists() for name in ("gradlew", "gradlew.bat", "build.gradle", "build.gradle.kts")):
        wrapper = (
            r".\gradlew.bat"
            if os.name == "nt" and (root / "gradlew.bat").exists()
            else "./gradlew"
            if (root / "gradlew").exists()
            else "gradle"
        )
        return ProjectProfile(
            "Java / Gradle",
            wrapper,
            (CommandSpec("Gradle tests", (wrapper, "test")),),
            CommandSpec("Gradle build", (wrapper, "build")),
            analysis=(CommandSpec("Gradle classes", (wrapper, "classes")),),
        )
    if (root / "CMakeLists.txt").is_file():
        return ProjectProfile(
            "CMake / native",
            "cmake",
            (
                CommandSpec("CMake configure", ("cmake", "-S", ".", "-B", "build")),
                CommandSpec("CMake build", ("cmake", "--build", "build")),
            ),
            CommandSpec("CMake build", ("cmake", "--build", "build")),
            analysis=(
                CommandSpec("CMake configure", ("cmake", "-S", ".", "-B", "build")),
            ),
        )
    if (root / "index.html").is_file():
        python = "python" if os.name == "nt" else "python3"
        return ProjectProfile(
            "Static website",
            python,
            run=CommandSpec("Static preview", (python, "-m", "http.server", "8080")),
        )
    return ProjectProfile("Unknown")


def resolve_executable(executable: str, cwd: Path) -> str | None:
    if not executable:
        return None
    if any(separator in executable for separator in ("/", "\\")) or executable.startswith("."):
        candidate = Path(executable)
        if not candidate.is_absolute():
            candidate = cwd / candidate
        return str(candidate.resolve()) if candidate.is_file() else None
    return shutil.which(executable)


def _decode_output(value: bytes) -> str:
    bounded = value[:MAX_CAPTURE]
    output = bounded.decode("utf-8", errors="replace")
    if len(value) > MAX_CAPTURE:
        output += f"\n[output truncated at {MAX_CAPTURE} bytes]"
    return _diagnostic_redact(output)


def _command_environment_profile(spec: CommandSpec) -> str:
    if spec.environment_profile != "auto":
        return spec.environment_profile
    executable = re.split(r"[\\/]", spec.argv[0])[-1].lower()
    executable = re.sub(r"\.(?:bat|cmd|exe)$", "", executable)
    return "sdk" if executable in {"dart", "flutter"} else "default"


def _safe_environment(*, profile: str = "default") -> dict[str, str]:
    allowed = set(_BASE_ENVIRONMENT_KEYS)
    if profile == "sdk":
        allowed.update(_SDK_ENVIRONMENT_KEYS)
    return {
        key: value
        for key, value in os.environ.items()
        if key.upper() in allowed
    }


def _failure_hint(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    diagnostics = [line for line in lines if line.startswith("- ")]
    if diagnostics:
        return diagnostics[-1]

    # Flutter's compact reporter can place the failing test name several lines
    # before the exception. Preserve that identity so Release Test failures are
    # actionable instead of surfacing only the final provider exception.
    test_failures = [
        line
        for line in lines
        if "[E]" in line
        or line.startswith("To run this test again:")
        or ("test/" in line.replace("\\", "/") and "Some tests failed" in line)
    ]

    generic = {
        "failed to update packages.",
        "pub get failed.",
        "process finished with exit code 1",
        "process finished with exit code 65",
    }
    indicators = (
        "because ",
        "could not ",
        "unable to ",
        "socketexception",
        "handshakeexception",
        "certificate",
        "proxy",
        "permission denied",
        "access is denied",
        "not found",
        "version solving failed",
        "connection ",
        "timed out",
        "timeout",
        "expected:",
        "actual:",
    )
    meaningful = [
        line
        for line in lines
        if line.lower() not in generic
        and any(indicator in line.lower() for indicator in indicators)
    ]
    if test_failures:
        selected: list[str] = []
        selected.append(test_failures[-1])
        if meaningful and meaningful[-1] != selected[-1]:
            selected.append(meaningful[-1])
        return " | ".join(selected[-2:])
    if meaningful:
        return " | ".join(meaningful[-3:])
    non_generic = [line for line in lines if line.lower() not in generic]
    return non_generic[-1] if non_generic else (lines[-1] if lines else "No command output was captured.")


def run_bounded(spec: CommandSpec, cwd: Path, timeout: int = DEFAULT_TIMEOUT) -> Check:
    executable = resolve_executable(spec.argv[0], cwd)
    if executable is None:
        return Check(
            spec.label,
            "SKIP",
            f"{spec.argv[0]} was not found on PATH.",
            command=spec.display,
        )
    argv = (executable, *spec.argv[1:])
    environment_profile = _command_environment_profile(spec)
    environment = _safe_environment(profile=environment_profile)
    environment.update(dict(spec.environment))
    workspace_mode = _command_workspace_mode(spec)
    started = dt.datetime.now(dt.timezone.utc)

    if spec.execution_mode == "host":
        try:
            completed = subprocess.run(
                list(argv),
                cwd=cwd,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="replace",
                timeout=timeout,
            )
            output = _diagnostic_redact(_sandbox_output(completed.stdout, completed.stderr))
            duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
            passed = completed.returncode == 0
            failure_hint = _failure_hint(output)
            detail = (
                "Trusted host diagnostic completed successfully."
                if passed
                else f"Trusted host diagnostic exited with code {completed.returncode}: {failure_hint[:1000]}"
            )
            return Check(
                spec.label,
                "PASS" if passed else "FAIL",
                detail,
                command=spec.display,
                exit_code=completed.returncode,
                duration_ms=duration,
                output=output,
            )
        except subprocess.TimeoutExpired:
            duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
            return Check(
                spec.label,
                "FAIL",
                f"Trusted host diagnostic exceeded the {timeout}-second limit.",
                command=spec.display,
                duration_ms=duration,
            )
        except OSError as error:
            return Check(spec.label, "FAIL", str(error), command=spec.display)

    capabilities = sandbox_capabilities()
    if not capabilities.get("available"):
        detail = "; ".join(str(item) for item in capabilities.get("issues", [])) or "sandbox backend unavailable"
        return Check(
            spec.label,
            "SKIP",
            f"Sandbox worker unavailable: {detail}",
            command=spec.display,
        )
    try:
        result = sandbox_worker.run_finite(
            executable=argv[0],
            arguments=list(argv[1:]),
            project_root=cwd,
            working_directory='.',
            workspace_mode=workspace_mode,
            timeout_seconds=timeout,
            environment=environment,
            max_output_bytes=MAX_CAPTURE,
        )
        output = _diagnostic_redact(_sandbox_output(str(result.get("stdout", "")), str(result.get("stderr", ""))))
        duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
        passed = int(result.get("exitCode", 1)) == 0
        failure_hint = _failure_hint(output)
        detail = (
            f"Sandboxed command completed successfully in {workspace_mode} mode."
            if passed
            else f"Sandboxed command exited with code {result.get('exitCode')}: {failure_hint[:1000]}"
        )
        return Check(
            spec.label,
            "PASS" if passed else "FAIL",
            detail,
            command=spec.display,
            exit_code=int(result.get("exitCode", 1)),
            duration_ms=duration or int(result.get("durationMs", 0) or 0),
            output=output,
        )
    except subprocess.TimeoutExpired:
        duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
        return Check(
            spec.label,
            "FAIL",
            f"Sandboxed command exceeded the {timeout}-second limit.",
            command=spec.display,
            duration_ms=duration,
        )
    except sandbox_worker.SandboxError as error:
        duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
        return Check(
            spec.label,
            "FAIL",
            str(error),
            command=spec.display,
            duration_ms=duration,
        )
    except OSError as error:
        return Check(spec.label, "FAIL", str(error), command=spec.display)


def _append_check(report: Report, check: Check) -> None:
    report.checks.append(check)


def _ollama_status() -> tuple[str, str]:
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/tags",
        headers={"User-Agent": f"Kristin-Doctor/{VERSION}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=1.25) as response:
            payload = json.loads(response.read(512 * 1024).decode("utf-8", errors="replace"))
        models = payload.get("models", []) if isinstance(payload, dict) else []
        count = len(models) if isinstance(models, list) else 0
        if count:
            return "PASS", f"Ollama is reachable with {count} model(s)."
        return "WARN", "Ollama is reachable but no models were reported."
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return "WARN", "Ollama is not reachable on 127.0.0.1:11434; cloud or another local provider can still be configured in the app."


def doctor(project: Path) -> Report:
    report = Report(command="doctor", project=str(project))
    if not project.exists():
        report.add("Project folder", "FAIL", "The selected project folder does not exist.")
        return report
    if not project.is_dir():
        report.add("Project folder", "FAIL", "The selected project path is not a directory.")
        return report
    report.add("Project folder", "PASS", "The project folder is available.")
    report.add(
        "Project access",
        "PASS" if os.access(project, os.R_OK) else "FAIL",
        "The project folder is readable." if os.access(project, os.R_OK) else "The project folder is not readable.",
    )
    profile = detect_profile(project)
    report.profile = profile.kind
    report.add(
        "Project profile",
        "WARN" if profile.kind == "Unknown" else "PASS",
        "No supported profile was detected; add kristin.project.json for explicit commands."
        if profile.kind == "Unknown"
        else f"{profile.kind} detected from {profile.source} configuration.",
    )
    if profile.required_executable:
        resolved = resolve_executable(profile.required_executable, project)
        report.add(
            "Project toolchain",
            "PASS" if resolved else "FAIL",
            f"{profile.required_executable} is available at {resolved}."
            if resolved
            else f"{profile.required_executable} was not found on PATH.",
            command=profile.required_executable,
        )
    else:
        report.add("Project toolchain", "WARN", "No project toolchain could be inferred.")
    report.add(
        "Test profile",
        "PASS" if profile.tests else "WARN",
        f"{len(profile.tests)} quick-test command(s) detected."
        if profile.tests
        else "No automatic quick-test command was detected.",
        command=" && ".join(item.display for item in profile.tests),
    )
    git = shutil.which("git")
    report.add(
        "Git",
        "PASS" if git else "WARN",
        f"Git is available at {git}." if git else "Git is not installed; change tracking will be limited.",
    )
    sandbox = sandbox_capabilities()
    report.add(
        "Sandbox worker",
        "PASS" if sandbox.get("available") else "WARN",
        "Linux namespace sandbox backend is ready for read-only and snapshot-writable execution."
        if sandbox.get("available")
        else ("; ".join(str(item) for item in sandbox.get("issues", [])) or "Sandbox backend unavailable on this host."),
    )
    free = shutil.disk_usage(project).free
    if free > 16 * 1024**5:
        report.add(
            "Free disk space",
            "WARN",
            "The host reports an unbounded or virtual project volume; verify real capacity before large builds.",
        )
    else:
        report.add(
            "Free disk space",
            "PASS" if free >= 1024**3 else "WARN",
            f"{free / (1024**3):.1f} GiB is available on the project volume.",
        )
    status, detail = _ollama_status()
    report.add("Local model provider", status, detail)
    if (ROOT.samefile(project) if project.exists() else False):
        report.add(
            "Kristin source release",
            "PASS" if (ROOT / "tool" / "validate_release.py").is_file() else "FAIL",
            f"Kristin Local Agent {VERSION} source tree detected.",
        )
    return report


def _tree_sitter_check(project: Path) -> Check:
    started = dt.datetime.now(dt.timezone.utc)
    try:
        from tree_sitter import Language, Parser  # type: ignore
        import tree_sitter_dart  # type: ignore

        parser = Parser(Language(tree_sitter_dart.language()))
        errors: list[str] = []
        count = 0
        for path in sorted((project / "lib").rglob("*.dart")) + sorted((project / "test").rglob("*.dart")):
            count += 1
            tree = parser.parse(path.read_bytes())
            if tree.root_node.has_error:
                errors.append(str(path.relative_to(project)))
        duration = int((dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000)
        return Check(
            "Dart grammar parse",
            "PASS" if not errors else "FAIL",
            f"Parsed {count} Dart source file(s) without grammar errors."
            if not errors
            else f"Grammar errors found in: {', '.join(errors[:20])}",
            duration_ms=duration,
        )
    except ImportError:
        return Check(
            "Dart grammar parse",
            "SKIP",
            "Optional tree-sitter Dart parser is unavailable; Flutter analysis remains the authoritative compiler gate.",
        )


def _is_kristin_tree(project: Path) -> bool:
    return (project / "tool" / "validate_release.py").is_file() and (project / "lib" / "product").is_dir()


def _level_rank(level: str) -> int:
    return {"quick": 0, "full": 1, "system": 2, "release": 3}.get(level, 0)


def _release_reproducibility_check(project: Path) -> Check:
    started = dt.datetime.now(dt.timezone.utc)
    try:
        with tempfile.TemporaryDirectory(prefix="kristin-release-a-") as first_dir, tempfile.TemporaryDirectory(
            prefix="kristin-release-b-"
        ) as second_dir:
            hashes: list[str] = []
            member_counts: list[int] = []
            for output_dir in (Path(first_dir), Path(second_dir)):
                completed = subprocess.run(
                    (
                        sys.executable,
                        str(project / "tool" / "release.py"),
                        "--skip-validation",
                        "--output-dir",
                        str(output_dir),
                    ),
                    cwd=project,
                    env=_safe_environment(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=False,
                    timeout=DEFAULT_TIMEOUT,
                    check=False,
                )
                output = _decode_output(completed.stdout or b"")
                if completed.returncode != 0:
                    return Check(
                        "Deterministic release packaging",
                        "FAIL",
                        "The release packager failed during reproducibility verification.",
                        command="python tool/release.py --skip-validation",
                        exit_code=completed.returncode,
                        output=output,
                    )
                archives = sorted(output_dir.glob("*.zip"))
                if len(archives) != 1:
                    return Check(
                        "Deterministic release packaging",
                        "FAIL",
                        f"Expected one release ZIP, found {len(archives)}.",
                        output=output,
                    )
                archive = archives[0]
                data = archive.read_bytes()
                hashes.append(hashlib.sha256(data).hexdigest())
                with zipfile.ZipFile(archive, "r") as package:
                    bad = package.testzip()
                    if bad:
                        return Check(
                            "Deterministic release packaging",
                            "FAIL",
                            f"Corrupt ZIP member: {bad}",
                        )
                    names = package.namelist()
                    roots = {name.split("/", 1)[0] for name in names if name}
                    if len(names) != len(set(names)) or len(roots) != 1:
                        return Check(
                            "Deterministic release packaging",
                            "FAIL",
                            "The release ZIP has duplicate members or more than one top-level directory.",
                        )
                    member_counts.append(len(names))
            duration = int(
                (dt.datetime.now(dt.timezone.utc) - started).total_seconds() * 1000
            )
            if hashes[0] != hashes[1]:
                return Check(
                    "Deterministic release packaging",
                    "FAIL",
                    "Two independent release builds produced different SHA-256 hashes.",
                    duration_ms=duration,
                )
            return Check(
                "Deterministic release packaging",
                "PASS",
                f"Two clean packages were byte-identical ({member_counts[0]} members, SHA-256 {hashes[0]}).",
                duration_ms=duration,
            )
    except subprocess.TimeoutExpired:
        return Check(
            "Deterministic release packaging",
            "FAIL",
            "Release packaging exceeded the configured deadline.",
        )
    except (OSError, zipfile.BadZipFile) as error:
        return Check(
            "Deterministic release packaging",
            "FAIL",
            f"Release packaging verification failed: {error}",
        )


def replay_all(project: Path) -> Report:
    report = Report(command="test --replay-all", project=str(project))
    if not project.is_dir():
        report.add("Project folder", "FAIL", "The selected project folder does not exist.")
        return report
    report.profile = detect_profile(project).kind
    if not _is_kristin_tree(project):
        report.add(
            "Kristin replay corpus",
            "FAIL",
            "--replay-all must target a Kristin source checkout.",
        )
        return report
    _append_check(
        report,
        run_bounded(
            CommandSpec(
                "Compact diagnostic replay corpus",
                (sys.executable, "tool/replay_diagnostics.py"),
            ),
            project,
            timeout=5 * 60,
        ),
    )
    if report.failed:
        return report
    if resolve_executable("flutter", project):
        _append_check(
            report,
            run_bounded(
                CommandSpec(
                    "Dart behavioral diagnostic replay",
                    (
                        "flutter",
                        "test",
                        "--concurrency=1",
                        "test/product/diagnostic_replay_test.dart",
                    ),
                    environment_profile="sdk",
                ),
                project,
                timeout=15 * 60,
            ),
        )
    else:
        report.add(
            "Dart behavioral diagnostic replay",
            "WARN",
            "Flutter is not installed. The compact replay corpus passed; run the same command on a Flutter workstation for native behavioral execution.",
        )
    return report


def test_project(project: Path, level: str = "quick") -> Report:
    level = level if level in {"quick", "full", "system", "release"} else "quick"
    rank = _level_rank(level)
    report = Report(command=f"test --{level}", project=str(project))
    if not project.is_dir():
        report.add("Project folder", "FAIL", "The selected project folder does not exist.")
        return report
    profile = detect_profile(project)
    report.profile = profile.kind

    if _is_kristin_tree(project):
        _append_check(report, _tree_sitter_check(project))
        checks = [
            CommandSpec(
                "Python source compilation",
                (sys.executable, "-m", "compileall", "-q", "tool", "scripts"),
            ),
            CommandSpec(
                "Generated typed protocol and schema contracts",
                (sys.executable, "tool/protocol_contract_test.py"),
            ),
            CommandSpec(
                "Generated workflow migration registry",
                (sys.executable, "tool/generate_workflow_migrations.py", "--check"),
            ),
            CommandSpec(
                "Durable SQLite workflow kernel",
                (sys.executable, "tool/workflow_kernel_test.py"),
            ),
            CommandSpec(
                "Sandbox worker and secret broker",
                (sys.executable, "tool/sandbox_worker_test.py"),
                execution_mode="host",
            ),
            CommandSpec(
                "HTTPS network broker policy gate",
                (sys.executable, "tool/network_broker_test.py"),
                execution_mode="host",
            ),
            CommandSpec(
                "Generated Prompt Studio 2 contracts",
                (sys.executable, "tool/generate_prompt_studio_contracts.py", "--check"),
            ),
            CommandSpec(
                "Generated Prompt Studio 2 fixtures",
                (sys.executable, "tool/generate_prompt_studio_fixtures.py", "--check"),
            ),
            CommandSpec(
                "Prompt Studio 2 compiler and dry-run fixtures",
                (sys.executable, "tool/prompt_studio_v2_test.py"),
            ),
            CommandSpec(
                "Knowledge, memory, skills, and freshness",
                (sys.executable, "tool/knowledge_memory_v2_test.py"),
            ),
            CommandSpec(
                "Core file-adapter registry",
                (sys.executable, "tool/file_adapter_test.py"),
            ),
            CommandSpec(
                "Golden diagnostic replay corpus",
                (sys.executable, "tool/replay_diagnostics.py"),
            ),
            CommandSpec(
                "Governed source validation",
                (sys.executable, "scripts/validate_architecture.py", "--skip-tests"),
            ),
            CommandSpec(
                "Bounded secret scan",
                (sys.executable, "tool/secret_scan.py"),
            ),
        ]
        if rank >= 2:
            checks.append(
                CommandSpec(
                    "Offline system contract fixtures",
                    (sys.executable, "tool/system_test.py", "--project", "."),
                    execution_mode="host",
                )
            )
        if rank >= 3:
            checks.append(
                CommandSpec(
                    "Release source validation",
                    (
                        sys.executable,
                        "tool/validate_release.py",
                        "--skip-tests",
                        "--skip-sdk",
                    ),
                    (("SOURCE_DATE_EPOCH", "1784678400"),),
                    execution_mode="host",
                )
            )
        for spec in checks:
            check = run_bounded(spec, project, timeout=15 * 60)
            _append_check(report, check)
            if check.status == "FAIL":
                return report

        flutter = resolve_executable("flutter", project)
        dart = resolve_executable("dart", project)
        if rank >= 1 and flutter:
            compile_specs: list[CommandSpec] = []
            if dart:
                compile_specs.append(
                    CommandSpec(
                        "Dart formatting",
                        (
                            "dart",
                            "format",
                            "--output=none",
                            "--set-exit-if-changed",
                            ".",
                        ),
                        environment_profile="sdk",
                    )
                )
            compile_specs.extend(
                (
                    CommandSpec(
                        "Flutter dependency resolution",
                        ("flutter", "pub", "get"),
                        environment_profile="sdk",
                    ),
                    CommandSpec(
                        "Flutter analysis",
                        ("flutter", "analyze", "--no-pub"),
                        environment_profile="sdk",
                    ),
                    CommandSpec(
                        "Flutter tests",
                        (
                            "flutter",
                            "test",
                            "--no-pub",
                            "--concurrency=1",
                        ),
                        environment_profile="sdk",
                    ),
                )
            )
            for spec in compile_specs:
                check = run_bounded(spec, project, timeout=20 * 60)
                _append_check(report, check)
                if check.status == "FAIL":
                    return report
            if rank >= 2:
                focused = run_bounded(
                    CommandSpec(
                        "V1 Prompt-to-Task system fixtures",
                        (
                            "flutter",
                            "test",
                            "--no-pub",
                            "--concurrency=1",
                            "test/product/v1_product_preview_test.dart",
                            "test/product/budget_diagnostics_test.dart",
                        ),
                        environment_profile="sdk",
                    ),
                    project,
                    timeout=20 * 60,
                )
                _append_check(report, focused)
                if focused.status == "FAIL":
                    return report
        elif rank >= 1:
            report.add(
                "Flutter compile gates",
                "SKIP",
                "Flutter is not installed; formatting, dependency resolution, analyzer, and Flutter tests were not run.",
                command=(
                    "dart format --output=none --set-exit-if-changed . && "
                    "flutter pub get && flutter analyze --no-pub && flutter test --no-pub --concurrency=1"
                ),
            )
        else:
            report.add(
                "Flutter compile gates",
                "SKIP" if not flutter else "WARN",
                "Use `kristin test --full` to run Flutter formatting, dependency, analyzer, and test gates."
                if flutter
                else "Flutter is not installed; use `kristin test --full` on a Flutter workstation for compile validation.",
            )

        if rank >= 3 and not report.failed:
            _append_check(report, _release_reproducibility_check(project))
        return report

    if not profile.tests:
        report.add(
            "Quick tests",
            "WARN",
            "No safe test profile was detected. Add kristin.project.json to define one.",
        )
        return report
    for spec in profile.tests:
        check = run_bounded(spec, project)
        _append_check(report, check)
        if check.status == "FAIL":
            break
    if rank >= 1 and not report.failed and profile.build is not None:
        _append_check(report, run_bounded(profile.build, project, timeout=15 * 60))
    if rank >= 2 and not _is_kristin_tree(project):
        report.add(
            "Kristin system fixtures",
            "SKIP",
            "Prompt-to-Task system fixtures apply only to the Kristin source project.",
        )
    return report


def _app_data_root() -> Path:
    if os.name == "nt":
        base = os.environ.get("APPDATA") or os.environ.get("LOCALAPPDATA") or str(Path.cwd())
        return Path(base) / "KristinLocalAgent"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "KristinLocalAgent"
    xdg = os.environ.get("XDG_STATE_HOME")
    return (Path(xdg) if xdg else Path.home() / ".local" / "state") / "kristin-local-agent"


def _workflow_database_path(data_root: Path) -> Path:
    return data_root / "state" / "workflow.sqlite3"


def _open_workflow_readonly(data_root: Path) -> sqlite3.Connection | None:
    database = _workflow_database_path(data_root)
    if not database.is_file():
        return None
    connection = sqlite3.connect(
        f"{database.resolve().as_uri()}?mode=ro",
        uri=True,
        timeout=5.0,
    )
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    connection.execute("PRAGMA busy_timeout = 5000")
    return connection


def _workflow_summary(data_root: Path, run_id: str = "") -> dict[str, object]:
    database = _workflow_database_path(data_root)
    connection = _open_workflow_readonly(data_root)
    if connection is None:
        return {
            "present": False,
            "database": str(database),
            "schemaVersion": 0,
            "integrity": "not_found",
        }
    try:
        tables = {
            str(row["name"])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        integrity_rows = connection.execute("PRAGMA quick_check").fetchall()
        integrity = "; ".join(str(row[0]) for row in integrity_rows) or "missing"
        counts: dict[str, int] = {}
        for table in (
            "runs",
            "run_events",
            "task_attempts",
            "idempotency_records",
            "checkpoints",
            "compensation_records",
            "recovery_actions",
            "migration_imports",
        ):
            if table not in tables:
                continue
            if run_id and table in {
                "runs",
                "run_events",
                "task_attempts",
                "idempotency_records",
                "checkpoints",
                "compensation_records",
                "recovery_actions",
            }:
                column = "id" if table == "runs" else "run_id"
                count = connection.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE {column} = ?",
                    (run_id,),
                ).fetchone()[0]
            else:
                count = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            counts[table] = int(count)
        metadata: dict[str, str] = {}
        if "workflow_metadata" in tables:
            metadata = {
                str(row["key"]): str(row["value"])
                for row in connection.execute(
                    "SELECT key, value FROM workflow_metadata ORDER BY key"
                )
            }
        return {
            "present": True,
            "database": str(database),
            "bytes": database.stat().st_size,
            "sha256": hashlib.sha256(database.read_bytes()).hexdigest(),
            "schemaVersion": int(connection.execute("PRAGMA user_version").fetchone()[0]),
            "journalMode": str(connection.execute("PRAGMA journal_mode").fetchone()[0]),
            "integrity": integrity,
            "foreignKeyViolations": len(connection.execute("PRAGMA foreign_key_check").fetchall()),
            "focusRunId": run_id,
            "counts": counts,
            "metadata": metadata,
        }
    finally:
        connection.close()


def verify_workflow(data_root: Path, run_id: str, json_output: bool) -> int:
    try:
        summary = _workflow_summary(data_root, run_id)
    except sqlite3.Error as error:
        summary = {
            "present": True,
            "database": str(_workflow_database_path(data_root)),
            "integrity": "error",
            "error": str(error),
        }
    ok = bool(summary.get("present")) and str(summary.get("integrity", "")).lower() == "ok"
    ok = ok and int(summary.get("foreignKeyViolations", 0) or 0) == 0
    if json_output:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(f"Kristin Workflow Store — {VERSION}")
        print(f"Database: {summary.get('database')}")
        print(f"Present: {summary.get('present')}")
        print(f"Schema version: {summary.get('schemaVersion', 0)}")
        print(f"Integrity: {summary.get('integrity')}")
        print(f"Foreign-key violations: {summary.get('foreignKeyViolations', 0)}")
        counts = summary.get("counts", {})
        if isinstance(counts, dict):
            for name, count in sorted(counts.items()):
                print(f"{name}: {count}")
        if summary.get("error"):
            print(f"Error: {summary['error']}", file=sys.stderr)
    return 0 if ok else 1


def show_logs(data_root: Path, tail: int) -> int:
    found = False
    connection = None
    try:
        connection = _open_workflow_readonly(data_root)
        if connection is not None:
            found = True
            print(f"\n== {_workflow_database_path(data_root)} :: run_events ==")
            rows = connection.execute(
                """SELECT sequence, event_id, correlation_id, run_id, type,
                          timestamp, payload_json, causation_id, idempotency_key,
                          state_version
                   FROM run_events ORDER BY sequence DESC LIMIT ?""",
                (tail,),
            ).fetchall()
            for row in reversed(rows):
                try:
                    payload = json.loads(str(row["payload_json"]))
                except json.JSONDecodeError:
                    payload = {"payloadSha256": hashlib.sha256(str(row["payload_json"]).encode()).hexdigest()}
                print(json.dumps({
                    "sequence": row["sequence"],
                    "id": row["event_id"],
                    "correlationId": row["correlation_id"],
                    "runId": row["run_id"],
                    "type": row["type"],
                    "timestamp": row["timestamp"],
                    "data": payload,
                    "causationId": row["causation_id"],
                    "idempotencyKey": row["idempotency_key"],
                    "stateVersion": row["state_version"],
                }, sort_keys=True))
    except sqlite3.Error as error:
        print(f"Workflow database could not be read: {error}", file=sys.stderr)
    finally:
        if connection is not None:
            connection.close()

    files = [data_root / "logs" / "audit.jsonl"]
    if not found:
        files.insert(0, data_root / "logs" / "events.jsonl")
    for path in files:
        print(f"\n== {path} ==")
        if not path.is_file():
            print("No log file found.")
            continue
        found = True
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for line in lines[-tail:]:
            print(line)
    return 0 if found else 1


_DIAGNOSTIC_SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+"),
    re.compile(r"(?i)((?:api[_-]?key|token|secret|password)\s*[:=]\s*)[^\s,;]+"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"),
)
_DIAGNOSTIC_SOURCE_KEYS = {
    "content", "rawcontent", "filecontent", "source", "sourcecode",
    "oldtext", "newtext", "replacement", "patch", "base64", "binary",
    "systemprompt", "userprompt", "prompt",
}


def _diagnostic_redact(value: str) -> str:
    output = value.replace("\x00", "")
    output = re.sub(
        r"(?i)\b(https?|socks5h?)://[^/\s:@]+:[^@\s/]+@",
        r"\1://[REDACTED]@",
        output,
    )
    for pattern in _DIAGNOSTIC_SECRET_PATTERNS:
        output = pattern.sub(
            lambda match: (match.group(1) if match.lastindex else "") + "[REDACTED]",
            output,
        )
    return output


def _diagnostic_sanitize(value: object, key: str = "") -> object:
    if isinstance(value, dict):
        return {
            str(name): _diagnostic_sanitize(item, str(name))
            for name, item in value.items()
        }
    if isinstance(value, list):
        return [_diagnostic_sanitize(item, key) for item in value]
    if not isinstance(value, str):
        return value
    redacted = _diagnostic_redact(value)
    if re.search(r"(?:secret|token|password|credential|authorization|api.?key)", key, re.IGNORECASE):
        return "[REDACTED]"
    if key.lower() in _DIAGNOSTIC_SOURCE_KEYS:
        return {
            "omitted": True,
            "characters": len(redacted),
            "sha256": hashlib.sha256(redacted.encode("utf-8")).hexdigest(),
        }
    if len(redacted) <= 8000:
        return redacted
    return {
        "truncated": True,
        "characters": len(redacted),
        "sha256": hashlib.sha256(redacted.encode("utf-8")).hexdigest(),
        "preview": redacted[:2000] + "…",
    }


def _diagnostic_json_lines(path: Path, max_bytes: int = 32 * 1024 * 1024) -> tuple[bytes, bool]:
    if not path.is_file():
        return b"", False
    raw = path.read_bytes()
    truncated = len(raw) > max_bytes
    selected = raw[-max_bytes:] if truncated else raw
    output: list[str] = []
    for line in selected.decode("utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            output.append(json.dumps(_diagnostic_sanitize(json.loads(line)), sort_keys=True))
        except json.JSONDecodeError:
            output.append(json.dumps({
                "omittedMalformedRecord": True,
                "characters": len(line),
                "sha256": hashlib.sha256(line.encode("utf-8")).hexdigest(),
            }, sort_keys=True))
    return (("\n".join(output) + ("\n" if output else "")).encode("utf-8"), truncated)


def _decode_sql_json(value: object) -> object:
    if value is None:
        return None
    try:
        return json.loads(str(value))
    except json.JSONDecodeError:
        text = str(value)
        return {
            "malformed": True,
            "characters": len(text),
            "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        }


def _workflow_diagnostic_payloads(
    data_root: Path,
    run_id: str,
) -> dict[str, object]:
    connection = _open_workflow_readonly(data_root)
    if connection is None:
        return {}
    payloads: dict[str, object] = {}
    try:
        payloads["workflow-summary.json"] = _workflow_summary(data_root, run_id)
        tables = {
            str(row["name"])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        if "runs" in tables:
            query = "SELECT run_json FROM runs"
            args: tuple[object, ...] = ()
            if run_id:
                query += " WHERE id = ?"
                args = (run_id,)
            query += " ORDER BY updated_at DESC, id LIMIT 50000"
            payloads["runs-redacted.json"] = [
                _decode_sql_json(row["run_json"])
                for row in connection.execute(query, args)
            ]
        if "run_events" in tables:
            query = """SELECT sequence, event_id, correlation_id, run_id, type,
                              timestamp, payload_json, payload_sha256,
                              causation_id, idempotency_key, state_version
                       FROM run_events"""
            args = ()
            if run_id:
                query += " WHERE run_id = ? OR correlation_id = ?"
                args = (run_id, run_id)
            query += " ORDER BY sequence LIMIT 100000"
            payloads["run-events-redacted.json"] = [
                {
                    "sequence": row["sequence"],
                    "id": row["event_id"],
                    "correlationId": row["correlation_id"],
                    "runId": row["run_id"],
                    "type": row["type"],
                    "timestamp": row["timestamp"],
                    "data": _decode_sql_json(row["payload_json"]),
                    "payloadSha256": row["payload_sha256"],
                    "causationId": row["causation_id"],
                    "idempotencyKey": row["idempotency_key"],
                    "stateVersion": row["state_version"],
                }
                for row in connection.execute(query, args)
            ]
        for table, output_name in (
            ("task_attempts", "task-attempts-redacted.json"),
            ("idempotency_records", "idempotency-redacted.json"),
            ("checkpoints", "checkpoints-redacted.json"),
            ("compensation_records", "compensation-redacted.json"),
            ("recovery_actions", "recovery-actions-redacted.json"),
            ("migration_imports", "migration-imports-redacted.json"),
        ):
            if table not in tables:
                continue
            query = f"SELECT * FROM {table}"
            args = ()
            if run_id and table != "migration_imports":
                query += " WHERE run_id = ?"
                args = (run_id,)
            query += " LIMIT 100000"
            rows: list[dict[str, object]] = []
            for row in connection.execute(query, args):
                item = dict(row)
                for key in tuple(item):
                    if key.endswith("_json"):
                        item[key] = _decode_sql_json(item[key])
                rows.append(item)
            payloads[output_name] = rows
        if "entity_records" in tables:
            for collection in ("projects", "evidence"):
                query = "SELECT record_json FROM entity_records WHERE collection = ?"
                args: tuple[object, ...] = (collection,)
                if run_id and collection == "evidence":
                    query += " AND json_extract(record_json, '$.runId') = ?"
                    args = (collection, run_id)
                query += " ORDER BY updated_at DESC, id LIMIT 50000"
                payloads[f"{collection}-redacted.json"] = [
                    _decode_sql_json(row["record_json"])
                    for row in connection.execute(query, args)
                ]
        if "documents" in tables:
            row = connection.execute(
                "SELECT document_json FROM documents WHERE key = 'settings'"
            ).fetchone()
            if row is not None:
                payloads["settings-redacted.json"] = _decode_sql_json(
                    row["document_json"]
                )
        return payloads
    finally:
        connection.close()


def export_logs(data_root: Path, output: Path | None, run_id: str = "") -> int:
    generated = dt.datetime.now(dt.timezone.utc)
    destination = output or (Path.cwd() / f"kristin-diagnostics-{generated.strftime('%Y%m%dT%H%M%SZ')}.zip")
    destination = destination.expanduser().resolve()
    entries: dict[str, bytes] = {}
    inventory: list[dict[str, object]] = []

    def add(name: str, payload: bytes, truncated: bool = False) -> None:
        entries[name] = payload
        inventory.append({
            "name": name,
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "truncated": truncated,
        })

    for file_name in ("events.jsonl", "audit.jsonl"):
        payload, truncated = _diagnostic_json_lines(data_root / "logs" / file_name)
        if payload:
            add(file_name.replace(".jsonl", "-redacted.jsonl"), payload, truncated)

    workflow_payloads = _workflow_diagnostic_payloads(data_root, run_id)
    for name, value in workflow_payloads.items():
        payload = (
            json.dumps(_diagnostic_sanitize(value), indent=2, sort_keys=True) + "\n"
        ).encode("utf-8")
        add(name, payload)

    if not workflow_payloads:
        for file_name in ("runs.json", "evidence.json", "projects.json", "settings.json"):
            source = data_root / "state" / file_name
            if not source.is_file():
                continue
            try:
                value = json.loads(source.read_text(encoding="utf-8", errors="replace"))
            except json.JSONDecodeError:
                value = {"malformed": True, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
            if run_id and file_name == "runs.json" and isinstance(value, list):
                value = [item for item in value if isinstance(item, dict) and str(item.get("id", "")) == run_id]
            if run_id and file_name == "evidence.json" and isinstance(value, list):
                value = [item for item in value if isinstance(item, dict) and str(item.get("runId", "")) == run_id]
            payload = (json.dumps(_diagnostic_sanitize(value), indent=2, sort_keys=True) + "\n").encode("utf-8")
            add(file_name.replace(".json", "-redacted.json"), payload)

    process_root = data_root / "logs" / "managed-processes"
    if process_root.is_dir():
        for process_file in sorted(path for path in process_root.rglob("*") if path.is_file())[:200]:
            raw = process_file.read_bytes()
            truncated = len(raw) > 1024 * 1024
            selected = raw[-1024 * 1024:] if truncated else raw
            relative = process_file.relative_to(process_root).as_posix()
            safe_relative = re.sub(r"[^A-Za-z0-9._/-]", "_", relative)
            if not safe_relative or ".." in Path(safe_relative).parts:
                continue
            text = _diagnostic_redact(selected.decode("utf-8", errors="replace"))
            add(f"managed-processes/{safe_relative}", text.encode("utf-8"), truncated)

    diagnostics = {
        "schema": "kristin.diagnostics.cli.v3",
        "version": VERSION,
        "generatedAt": generated.isoformat(),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "focusRunId": run_id,
        "dataRootFingerprint": hashlib.sha256(str(data_root).encode("utf-8")).hexdigest(),
        "privacy": {
            "secretRedactionApplied": True,
            "sourceLikePayloadsReplacedByHashes": True,
            "largeStringsBounded": True,
            "reviewBeforeSharing": True,
        },
    }
    add("diagnostics.json", (json.dumps(diagnostics, indent=2, sort_keys=True) + "\n").encode("utf-8"))

    readme = f"""# Kristin diagnostic log bundle

Created by Kristin Local Agent {VERSION} at {generated.isoformat()}.
Focus run: {run_id or 'all'}

This ZIP contains redacted SQLite workflow events, checkpoints, idempotency and compensation metadata, audit records, run state, and evidence metadata. Source-like payloads are represented by hashes. Review the archive before sharing because it can still contain project names, request text, URLs, relative paths, command output, error messages, and bounded model-response previews.
"""
    add("README.md", readme.encode("utf-8"))
    manifest = {
        "schema": "kristin.diagnostics.cli.v3",
        "version": VERSION,
        "generatedAt": generated.isoformat(),
        "dataRootFingerprint": hashlib.sha256(str(data_root).encode("utf-8")).hexdigest(),
        "focusRunId": run_id,
        "entries": inventory,
    }
    entries["bundle-manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, entries[name])
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f"Diagnostic log bundle: {destination}")
    print(f"SHA-256: {digest}")
    print("Review the ZIP before sharing it.")
    return 0



def _load_json_list(path: Path) -> list[dict[str, object]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def _load_entity_collection(
    data_root: Path,
    collection: str,
    legacy_file_name: str,
) -> list[dict[str, object]]:
    connection = None
    try:
        connection = _open_workflow_readonly(data_root)
        if connection is not None:
            rows = connection.execute(
                """SELECT record_json FROM entity_records
                   WHERE collection = ? ORDER BY updated_at DESC, id""",
                (collection,),
            )
            output: list[dict[str, object]] = []
            for row in rows:
                value = _decode_sql_json(row["record_json"])
                if isinstance(value, dict):
                    output.append(value)
            return output
    except sqlite3.Error:
        pass
    finally:
        if connection is not None:
            connection.close()
    return _load_json_list(data_root / "state" / legacy_file_name)


def _resolve_project_id(data_root: Path, supplied: str) -> str:
    projects = _load_entity_collection(data_root, "projects", "projects.json")
    value = supplied.strip()
    if value:
        for project in projects:
            candidates = {
                str(project.get("id", "")),
                str(project.get("name", "")),
                str(project.get("rootPath", "")),
            }
            if value in candidates:
                return str(project.get("id", value))
        return value
    if len(projects) == 1:
        return str(projects[0].get("id", ""))
    available = ", ".join(
        f"{item.get('name', 'project')} ({item.get('id', '')})" for item in projects[:20]
    )
    raise ValueError(
        "Specify --project-id."
        + (f" Available projects: {available}" if available else " No registered projects were found.")
    )


def _terms(value: str) -> set[str]:
    stop = {
        "the", "and", "for", "with", "that", "this", "from", "into", "are",
        "was", "were", "will", "would", "should", "could", "have", "has", "had",
        "not", "but", "about", "your", "you", "our", "their", "they", "them",
        "project", "task",
    }
    return {
        token
        for token in re.findall(r"[a-z0-9_-]{2,}", value.lower())
        if token not in stop
    }


def inspect_knowledge(
    data_root: Path,
    project_id_value: str,
    *,
    query: str,
    limit: int,
    show_archive: bool,
    show_memory: bool,
    json_output: bool,
) -> int:
    try:
        project_id = _resolve_project_id(data_root, project_id_value)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    knowledge = [
        item
        for item in _load_entity_collection(data_root, "knowledge", "knowledge.json")
        if str(item.get("projectId", "")) == project_id
    ]
    archive = [
        item
        for item in _load_entity_collection(data_root, "research_archive", "research_archive.json")
        if str(item.get("projectId", "")) == project_id
    ]
    memory = [
        item
        for item in _load_entity_collection(data_root, "memory_episodes", "memory_episodes.json")
        if str(item.get("projectId", "")) == project_id
    ]
    archive.sort(key=lambda item: str(item.get("capturedAt", "")), reverse=True)
    memory.sort(
        key=lambda item: (bool(item.get("pinned")), str(item.get("completedAt", ""))),
        reverse=True,
    )
    index_path = data_root / "cache" / "knowledge-index" / f"{re.sub(r'[^A-Za-z0-9_.-]', '_', project_id)}.json"
    index = _read_json(index_path)
    stats = {
        "projectId": project_id,
        "notes": sum(str(item.get("kind", "note")) == "note" for item in knowledge),
        "researchSources": sum(str(item.get("kind", "")) == "source" for item in archive),
        "searchSnapshots": sum(str(item.get("kind", "")) == "search" for item in archive),
        "episodes": len(memory),
        "pinned": sum(bool(item.get("pinned")) for item in knowledge)
        + sum(bool(item.get("pinned")) for item in memory),
        "archiveBytes": sum(max(0, int(item.get("byteLength", 0) or 0)) for item in archive),
        "indexedChunks": len(index.get("chunks", [])) if isinstance(index.get("chunks"), list) else 0,
        "dataRoot": str(data_root),
    }
    payload: dict[str, object] = {"stats": stats}
    if show_archive:
        payload["researchArchive"] = archive[:limit]
    elif show_memory:
        payload["episodes"] = memory[:limit]
    elif query.strip():
        query_terms = _terms(query)
        candidates: list[tuple[float, dict[str, object]]] = []
        for item in knowledge:
            text = " ".join(
                str(item.get(key, ""))
                for key in ("title", "content", "sourceUrl", "tags")
            )
            overlap = len(query_terms & _terms(text))
            phrase = query.lower() in text.lower()
            score = float(overlap) + (3.0 if phrase else 0.0) + (0.5 if item.get("pinned") else 0.0)
            if score > 0:
                candidates.append((score, {"type": "knowledge", **item}))
        for item in memory:
            text = " ".join(
                str(item.get(key, ""))
                for key in ("request", "summary", "failure", "lessons", "filesChanged", "tags")
            )
            overlap = len(query_terms & _terms(text))
            phrase = query.lower() in text.lower()
            score = float(overlap) + (3.0 if phrase else 0.0) + (0.5 if item.get("pinned") else 0.0)
            if score > 0:
                candidates.append((score, {"type": "episode", **item}))
        candidates.sort(key=lambda item: item[0], reverse=True)
        payload["query"] = query
        payload["results"] = [
            {"diagnosticScore": score, **item}
            for score, item in candidates[:limit]
        ]
        payload["note"] = (
            "CLI ranking is a diagnostic lexical view. The desktop runtime and governed API use the v0.9 hybrid index."
        )
    if json_output:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    print(f"Kristin Knowledge — {VERSION}")
    print(f"Project: {project_id}")
    print(f"Data root: {data_root}\n")
    print(
        "Notes: {notes} | Sources: {researchSources} | Searches: {searchSnapshots} | "
        "Episodes: {episodes} | Pinned: {pinned} | Indexed excerpts: {indexedChunks}".format(**stats)
    )
    if show_archive:
        for item in archive[:limit]:
            print(
                f"\n{item.get('capturedAt', '')}  {item.get('kind', '')}  {item.get('title', '')}\n"
                f"  archive={item.get('id', '')}  hash={item.get('contentHash', '')}\n"
                f"  url={item.get('finalUrl', '') or item.get('requestedUrl', '')}"
            )
    elif show_memory:
        for item in memory[:limit]:
            print(
                f"\n{item.get('completedAt', '')}  {item.get('outcome', '')}  {item.get('request', '')}\n"
                f"  run={item.get('runId', '')}  pinned={bool(item.get('pinned'))}\n"
                f"  lessons={str(item.get('lessons', ''))[:500]}"
            )
    elif query.strip():
        results = payload.get("results", [])
        if isinstance(results, list):
            for index, item in enumerate(results, start=1):
                if not isinstance(item, dict):
                    continue
                title = item.get("title") or item.get("request") or item.get("runId")
                excerpt = item.get("content") or item.get("lessons") or ""
                print(
                    f"\nK{index}  score={item.get('diagnosticScore')}  {title}\n"
                    f"  {str(excerpt)[:700]}"
                )
        print("\nNote: CLI ranking is diagnostic; the app/API use the v0.9 hybrid index.")
    return 0

def _report_path(command: str) -> Path:
    safe_command = re.sub(r"[^a-z0-9]+", "-", command.lower()).strip("-")
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    directory = ROOT / "reports"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"kristin-{safe_command}-{timestamp}.json"


def write_report(report: Report, output: Path | None = None) -> Path:
    path = output or _report_path(report.command)
    if path.suffix.lower() != ".json":
        path = path.with_suffix(".json")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(asdict(report), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    markdown = [
        f"# Kristin {report.command.title()} Report",
        "",
        f"- Version: `{report.version}`",
        f"- Project: `{report.project}`",
        f"- Profile: `{report.profile}`",
        f"- Generated: `{report.generated_at}`",
        "",
        "| Status | Check | Detail | Command |",
        "|---|---|---|---|",
    ]
    raw_lines = [
        f"Kristin {report.command} — {report.version}",
        f"Project: {report.project}",
        f"Profile: {report.profile}",
        f"Generated: {report.generated_at}",
        "",
    ]
    for check in report.checks:
        detail = check.detail.replace("|", "\\|").replace("\n", " ")
        command = check.command.replace("|", "\\|")
        markdown.append(
            f"| {check.status} | {check.name} | {detail} | `{command}` |"
        )
        raw_lines.extend(
            [
                f"[{check.status}] {check.name}",
                f"Detail: {check.detail}",
                f"Command: {check.command}" if check.command else "Command: (none)",
                f"Exit code: {check.exit_code}"
                if check.exit_code is not None
                else "Exit code: (not applicable)",
                f"Duration ms: {check.duration_ms}"
                if check.duration_ms is not None
                else "Duration ms: (not recorded)",
                "Output:",
                check.output or "(no captured output)",
                "",
            ]
        )
    passed = sum(item.status == "PASS" for item in report.checks)
    warnings = sum(item.status in {"WARN", "SKIP"} for item in report.checks)
    failed = sum(item.status == "FAIL" for item in report.checks)
    markdown.extend(
        [
            "",
            "## Result",
            "",
            f"{passed} passed, {warnings} warning/skipped, {failed} failed.",
        ]
    )
    path.with_suffix(".md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    path.with_suffix(".log").write_text("\n".join(raw_lines) + "\n", encoding="utf-8")
    return path


def print_report(report: Report, *, json_output: bool = False, output: Path | None = None) -> int:
    path = write_report(report, output)
    if json_output:
        print(json.dumps(asdict(report), indent=2, sort_keys=True))
    else:
        print(f"Kristin {report.command.title()} — {VERSION}")
        print(f"Project: {report.project}")
        print(f"Profile: {report.profile}\n")
        for check in report.checks:
            print(f"{check.status:<5} {check.name}: {check.detail}")
            if check.command:
                print(f"      command: {check.command}")
        passed = sum(item.status == "PASS" for item in report.checks)
        warnings = sum(item.status in {"WARN", "SKIP"} for item in report.checks)
        failed = sum(item.status == "FAIL" for item in report.checks)
        print(f"\nResult: {passed} passed, {warnings} warning/skipped, {failed} failed")
        print(f"Report: {path}")
        print(f"Markdown: {path.with_suffix('.md')}")
        print(f"Raw log: {path.with_suffix('.log')}")
    return 1 if report.failed else 0


def execute_profile_commands(
    profile: ProjectProfile,
    project: Path,
    action: str,
) -> int:
    commands: tuple[CommandSpec, ...]
    if action == "analyze":
        commands = profile.analysis
    elif action == "build":
        commands = (profile.build,) if profile.build is not None else ()
    else:
        raise ValueError(f"Unsupported project action: {action}")
    if not commands:
        print(
            f"No {action} command was detected for {profile.kind}.",
            file=sys.stderr,
        )
        print(
            f"Add an {action} entry to kristin.project.json.",
            file=sys.stderr,
        )
        return 2
    for spec in commands:
        check = run_bounded(spec, project, timeout=DEFAULT_TIMEOUT)
        print(f"{check.status:<5} {check.name}: {check.detail}")
        print(f"      command: {check.command}")
        if check.output.strip():
            print(check.output.rstrip())
        if check.status == "FAIL":
            return check.exit_code if check.exit_code not in (None, 0) else 1
    return 0


def execute_run(profile: ProjectProfile, project: Path, execute: bool) -> int:
    if profile.run is None:
        print(f"No run command was detected for {profile.kind}.", file=sys.stderr)
        print("Add a run entry to kristin.project.json.", file=sys.stderr)
        return 2
    print(f"Project profile: {profile.kind}")
    print(f"Run command: {profile.run.display}")
    if not execute:
        print("Dry run only. Add --execute to start the project.")
        return 0
    executable = resolve_executable(profile.run.argv[0], project)
    if executable is None:
        print(f"{profile.run.argv[0]} was not found on PATH.", file=sys.stderr)
        return 1
    try:
        result = sandbox_worker.run_finite(
            executable=executable,
            arguments=list(profile.run.argv[1:]),
            project_root=project,
            working_directory='.',
            workspace_mode='snapshot_writable',
            timeout_seconds=DEFAULT_TIMEOUT,
            environment=_safe_environment(profile=_command_environment_profile(profile.run)),
            max_output_bytes=MAX_CAPTURE,
        )
        output = _sandbox_output(str(result.get('stdout', '')), str(result.get('stderr', '')))
        if output.strip():
            print(_diagnostic_redact(output.rstrip()))
        return int(result.get('exitCode', 1))
    except KeyboardInterrupt:
        return 130
    except sandbox_worker.SandboxError as error:
        print(str(error), file=sys.stderr)
        return 1
    except OSError as error:
        print(str(error), file=sys.stderr)
        return 1


def _project(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _effective_prompt_policy(path: Path | None) -> Path:
    live = sandbox_capabilities()
    policy = _read_json(path) if path is not None else {}
    requested = bool(policy.get("sandboxAvailable")) if path is not None else True
    policy["sandboxAvailable"] = bool(live.get("available")) and requested
    policy.setdefault("localOnly", True)
    policy.setdefault("networkAllowed", False)
    policy.setdefault("legacyUnsandboxedExecutionApproved", False)
    temp = tempfile.NamedTemporaryFile(prefix="kristin-policy-", suffix=".json", delete=False)
    with temp:
        temp.write(json.dumps(policy, sort_keys=True).encode("utf-8"))
    return Path(temp.name)


def prompt_studio_command(args: argparse.Namespace) -> int:
    command: list[str] = []
    temporary_policy: Path | None = None
    if args.command == "plan-compile":
        command = [
            "compile",
            "--spec",
            str(args.spec.expanduser().resolve()),
            "--plan",
            str(args.plan.expanduser().resolve()),
        ]
        temporary_policy = _effective_prompt_policy(args.policy)
        command.extend(("--policy", str(temporary_policy)))
        if args.output is not None:
            command.extend(("--output", str(args.output.expanduser().resolve())))
        if args.fail_on_errors:
            command.append("--fail-on-errors")
    elif args.command == "prompt-evaluate":
        command = [
            "evaluate-prompt",
            "--baseline",
            str(args.baseline.expanduser().resolve()),
            "--candidate",
            str(args.candidate.expanduser().resolve()),
            "--dataset",
            str(args.dataset.expanduser().resolve()),
        ]
        if args.output is not None:
            command.extend(("--output", str(args.output.expanduser().resolve())))
    elif args.command == "plan-compare":
        command = [
            "compare-plans",
            "--spec",
            str(args.spec.expanduser().resolve()),
            "--baseline",
            str(args.baseline.expanduser().resolve()),
            "--candidate",
            str(args.candidate.expanduser().resolve()),
        ]
        temporary_policy = _effective_prompt_policy(args.policy)
        command.extend(("--policy", str(temporary_policy)))
        if args.output is not None:
            command.extend(("--output", str(args.output.expanduser().resolve())))
    else:
        raise ValueError(f"Unsupported Prompt Studio command: {args.command}")
    try:
        return prompt_studio_compiler.main(command)
    except (OSError, ValueError, prompt_studio_compiler.CompilationInputError) as error:
        print(f"Prompt Studio 2 operation failed: {error}", file=sys.stderr)
        return 2
    finally:
        if temporary_policy is not None:
            temporary_policy.unlink(missing_ok=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kristin", description="Kristin Local Agent diagnostics and project runner")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    subparsers = parser.add_subparsers(dest="command")

    doctor_parser = subparsers.add_parser("doctor", help="check project and local prerequisites")
    doctor_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))
    doctor_parser.add_argument("--json", action="store_true")
    doctor_parser.add_argument("--output", type=Path)

    test_parser = subparsers.add_parser("test", help="run detected bounded project checks")
    test_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))
    mode = test_parser.add_mutually_exclusive_group()
    mode.add_argument("--quick", action="store_true", help="run source and quick project gates (default)")
    mode.add_argument("--full", action="store_true", help="also run formatting, compile, analyzer, and test gates")
    mode.add_argument("--system", action="store_true", help="run full gates plus Prompt-to-Task, cancellation, API, and recovery fixtures")
    mode.add_argument("--release", action="store_true", help="run system gates plus source validation and deterministic package verification")
    mode.add_argument("--replay-all", action="store_true", help="replay every compact production-failure fixture and its Dart behavioral contracts")
    mode.add_argument("--workflow-kernel", action="store_true", help="run only the executable SQLite crash, recovery, migration, and idempotency gate")
    mode.add_argument("--execution-intelligence", action="store_true", help="run only the v1.7 router, verifier, semantic-progress, and convergence gate")
    mode.add_argument("--project-manager", action="store_true", help="run only the Project Manager 2 sandboxed operation gate")
    test_parser.add_argument("--json", action="store_true")
    test_parser.add_argument("--output", type=Path)

    analyze_parser = subparsers.add_parser(
        "analyze",
        help="run the detected bounded project analysis command",
    )
    analyze_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))

    build_project_parser = subparsers.add_parser(
        "build",
        help="run the detected bounded project build command",
    )
    build_project_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))

    run_parser = subparsers.add_parser("run", help="show or execute the detected project run command")
    run_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))
    run_parser.add_argument("--execute", action="store_true")

    logs_parser = subparsers.add_parser("logs", help="show or export internal diagnostic logs")
    logs_parser.add_argument("--tail", type=int, default=50)
    logs_parser.add_argument("--data-root", type=Path, default=_app_data_root())
    logs_parser.add_argument("--export", action="store_true", help="save a redacted diagnostic ZIP")
    logs_parser.add_argument("--output", type=Path, help="diagnostic ZIP path")
    logs_parser.add_argument("--run-id", default="", help="focus run records and evidence on one run")

    workflow_parser = subparsers.add_parser(
        "workflow",
        help="verify the durable SQLite workflow database and show record counts",
    )
    workflow_parser.add_argument("--data-root", type=Path, default=_app_data_root())
    workflow_parser.add_argument("--run-id", default="")
    workflow_parser.add_argument("--json", action="store_true")

    sandbox_parser = subparsers.add_parser(
        "sandbox",
        help="inspect the live sandbox worker capability report",
    )
    sandbox_parser.add_argument("--json", action="store_true")

    plan_compile_parser = subparsers.add_parser(
        "plan-compile",
        help="compile and dry-run a canonical Prompt Studio 2 plan",
    )
    plan_compile_parser.add_argument("--spec", type=Path, required=True)
    plan_compile_parser.add_argument("--plan", type=Path, required=True)
    plan_compile_parser.add_argument("--policy", type=Path)
    plan_compile_parser.add_argument("--output", type=Path)
    plan_compile_parser.add_argument("--fail-on-errors", action="store_true")

    prompt_evaluate_parser = subparsers.add_parser(
        "prompt-evaluate",
        help="compare two prompt versions against a deterministic evaluation dataset",
    )
    prompt_evaluate_parser.add_argument("--baseline", type=Path, required=True)
    prompt_evaluate_parser.add_argument("--candidate", type=Path, required=True)
    prompt_evaluate_parser.add_argument("--dataset", type=Path, required=True)
    prompt_evaluate_parser.add_argument("--output", type=Path)

    plan_compare_parser = subparsers.add_parser(
        "plan-compare",
        help="measure the impact of a canonical task-plan revision",
    )
    plan_compare_parser.add_argument("--spec", type=Path, required=True)
    plan_compare_parser.add_argument("--baseline", type=Path, required=True)
    plan_compare_parser.add_argument("--candidate", type=Path, required=True)
    plan_compare_parser.add_argument("--policy", type=Path)
    plan_compare_parser.add_argument("--output", type=Path)

    knowledge_parser = subparsers.add_parser(
        "knowledge",
        help="inspect the local project knowledge, research archive, and run memory",
    )
    knowledge_parser.add_argument("--data-root", type=Path, default=_app_data_root())
    knowledge_parser.add_argument("--project-id", default="")
    knowledge_parser.add_argument("--query", default="")
    knowledge_parser.add_argument("--limit", type=int, default=12)
    knowledge_parser.add_argument("--archive", action="store_true")
    knowledge_parser.add_argument("--memory", action="store_true")
    knowledge_parser.add_argument("--json", action="store_true")

    skills_parser = subparsers.add_parser(
        "skills",
        help="extract, evaluate, and publish governed skills from v1.8 memory episodes",
    )
    skills_parser.add_argument("--json", action="store_true")

    adapter_parser = subparsers.add_parser(
        "file-adapter",
        help="inspect or validate files through the v1.8 core adapter registry",
    )
    adapter_parser.add_argument("path", nargs="?", default="")
    adapter_parser.add_argument("--json", action="store_true")

    project_parser = subparsers.add_parser(
        "project",
        help="run Project Manager 2 status, actions, managed Run, and Stop",
    )
    project_parser.add_argument("project_args", nargs=argparse.REMAINDER)

    intelligence_parser = subparsers.add_parser(
        "intelligence",
        help="run deterministic v1.7 routing, progress, convergence, verification, or compaction",
    )
    intelligence_parser.add_argument("intelligence_args", nargs=argparse.REMAINDER)

    interoperability_parser = subparsers.add_parser(
        "interoperability",
        help="inspect v1.9 policy profiles, signed manifests, audit verification, and update policy",
    )
    interoperability_parser.add_argument("--json", action="store_true")
    interoperability_parser.add_argument("--self-test", action="store_true")
    interoperability_parser.add_argument("--policy", default="strict_local")

    report_parser = subparsers.add_parser("report", help="create a combined doctor and quick-test report")
    report_parser.add_argument("--project", nargs="?", const=".", default=str(Path.cwd()))
    report_parser.add_argument("--output", type=Path)
    report_parser.add_argument("--json", action="store_true")
    return parser


def _print_onboarding(parser: argparse.ArgumentParser) -> None:
    parser.print_help()
    print("\nCommon commands:")
    if os.name == "nt":
        print(r"  .\kristin.cmd doctor --project .")
        print(r"  .\kristin.cmd test --quick --project .")
        print(r"  .\kristin.cmd test --system --project .")
        print(r"  .\kristin.cmd test --replay-all --project .")
        print(r"  .\kristin.cmd test --workflow-kernel --project .")
        print(r"  .\kristin.cmd analyze --project .")
        print(r"  .\kristin.cmd build --project .")
        print(r"  .\kristin.cmd run --project . --execute")
        print(r"  .\kristin.cmd workflow")
        print(r"  .\kristin.cmd plan-compile --spec spec.json --plan plan.json --fail-on-errors")
        print(r"  .\RUN_WINDOWS.bat")
    else:
        print("  ./kristin doctor --project .")
        print("  ./kristin test --quick --project .")
        print("  ./kristin test --system --project .")
        print("  ./kristin test --replay-all --project .")
        print("  ./kristin test --workflow-kernel --project .")
        print("  ./kristin analyze --project .")
        print("  ./kristin build --project .")
        print("  ./kristin run --project . --execute")
        print("  ./kristin workflow")
        print("  ./kristin plan-compile --spec spec.json --plan plan.json --fail-on-errors")
        print("  ./RUN_LINUX.sh  # or ./RUN_MAC.command")


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command is None:
        _print_onboarding(parser)
        return 0
    if args.command == "doctor":
        return print_report(doctor(_project(args.project)), json_output=args.json, output=args.output)
    if args.command == "test":
        if args.replay_all:
            return print_report(
                replay_all(_project(args.project)),
                json_output=args.json,
                output=args.output,
            )
        if args.execution_intelligence:
            project = _project(args.project)
            report = Report(command="test --execution-intelligence", project=str(project))
            report.profile = detect_profile(project).kind if project.is_dir() else "Unknown"
            if not _is_kristin_tree(project):
                report.add("Execution intelligence", "FAIL", "--execution-intelligence must target a Kristin source checkout.")
            else:
                _append_check(report, run_bounded(CommandSpec(
                    "Execution intelligence",
                    (sys.executable, "tool/execution_intelligence_test.py"),
                    execution_mode="host",
                ), project, timeout=5 * 60))
            return print_report(report, json_output=args.json, output=args.output)
        if args.project_manager:
            project = _project(args.project)
            report = Report(command="test --project-manager", project=str(project))
            report.profile = detect_profile(project).kind if project.is_dir() else "Unknown"
            if not _is_kristin_tree(project):
                report.add("Project Manager 2", "FAIL", "--project-manager must target a Kristin source checkout.")
            else:
                _append_check(report, run_bounded(CommandSpec(
                    "Project Manager 2",
                    (sys.executable, "tool/project_manager_v2_test.py"),
                    execution_mode="host",
                ), project, timeout=8 * 60))
            return print_report(report, json_output=args.json, output=args.output)
        if args.workflow_kernel:
            project = _project(args.project)
            report = Report(command="test --workflow-kernel", project=str(project))
            report.profile = detect_profile(project).kind if project.is_dir() else "Unknown"
            if not _is_kristin_tree(project):
                report.add(
                    "Durable SQLite workflow kernel",
                    "FAIL",
                    "--workflow-kernel must target a Kristin source checkout.",
                )
            else:
                _append_check(
                    report,
                    run_bounded(
                        CommandSpec(
                            "Generated workflow migration registry",
                            (sys.executable, "tool/generate_workflow_migrations.py", "--check"),
                        ),
                        project,
                        timeout=5 * 60,
                    ),
                )
                if not report.failed:
                    _append_check(
                        report,
                        run_bounded(
                            CommandSpec(
                                "Durable SQLite workflow kernel",
                                (sys.executable, "tool/workflow_kernel_test.py"),
                            ),
                            project,
                            timeout=5 * 60,
                        ),
                    )
            return print_report(report, json_output=args.json, output=args.output)
        return print_report(
            test_project(
                _project(args.project),
                level=(
                    "release"
                    if args.release
                    else "system"
                    if args.system
                    else "full"
                    if args.full
                    else "quick"
                ),
            ),
            json_output=args.json,
            output=args.output,
        )
    if args.command in {"analyze", "build"}:
        project = _project(args.project)
        return execute_profile_commands(
            detect_profile(project),
            project,
            args.command,
        )
    if args.command == "run":
        project = _project(args.project)
        return execute_run(detect_profile(project), project, args.execute)
    if args.command == "logs":
        data_root = args.data_root.expanduser().resolve()
        if args.export:
            return export_logs(data_root, args.output, args.run_id.strip())
        return show_logs(data_root, max(1, min(args.tail, 5000)))
    if args.command == "workflow":
        return verify_workflow(
            args.data_root.expanduser().resolve(),
            args.run_id.strip(),
            args.json,
        )
    if args.command == "sandbox":
        report = sandbox_capabilities()
        if args.json:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if report.get("available") else 1
    if args.command == "project":
        return project_manager_v2.main(args.project_args)
    if args.command == "intelligence":
        return execution_intelligence.main(args.intelligence_args)
    if args.command == "interoperability":
        if args.self_test:
            first = subprocess.call([sys.executable, str(ROOT / "tool" / "interoperability_admin_v19_test.py")])
            second = subprocess.call([sys.executable, str(ROOT / "tool" / "release_ops_v19_test.py")])
            return 0 if first == 0 and second == 0 else 1
        policy = interoperability_admin_v19.built_in_policy(args.policy)
        sample = interoperability_admin_v19.sign_manifest(
            interoperability_admin_v19.CapabilityManifest.create(
                kind="skill",
                identifier="sample.release",
                title="Sample signed release skill",
                version=1,
                purpose="Demonstrate manifest verification.",
                input_schema="schemas/product_specification.v2.json",
                output_schema="schemas/published_skill.v1.json",
                capabilities=["archive_manifest", "verify_project"],
                data_boundary="local",
                model_requirements=["executor"],
                approval_policy="explicit",
                evaluation_results=["replay:pass"],
                provenance=["episode:sample"],
                compatibility=[">=1.8.0", "<2.0.0"],
            ),
            signer_id="openai-local-release",
            secret="demo-secret",
            signed_at="2026-07-22T00:00:00+00:00",
        )
        audit = interoperability_admin_v19.AuditChain(signer_id="openai-local-release", secret="demo-secret")
        audit.append("manifest.sample", sample.manifest.id, sample.manifest.to_payload())
        verified, reason = audit.verify()
        payload = {
            "version": VERSION,
            "policy": policy.to_json(),
            "sampleManifest": sample.to_json(),
            "auditVerified": verified,
            "auditReason": reason,
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0 if verified else 1
    if args.command in {"plan-compile", "prompt-evaluate", "plan-compare"}:
        return prompt_studio_command(args)
    if args.command == "knowledge":
        return inspect_knowledge(
            args.data_root.expanduser().resolve(),
            args.project_id,
            query=args.query,
            limit=max(1, min(args.limit, 200)),
            show_archive=args.archive,
            show_memory=args.memory,
            json_output=args.json,
        )

    if args.command == "skills":
        episode = knowledge_memory_v2.Episode(
            id='synthetic',
            project_id='project',
            run_id='run',
            request='Repair the build pipeline and package the app',
            outcome='succeeded',
            summary='Synthetic governed summary for source CLI inspection.',
            failure='',
            lessons='Use the retained snapshot and verify the package output.',
            files_changed=('kristin.project.json',),
            evidence_hashes=('a' * 64,),
            completed_items=('Build', 'Package'),
            mutations=1,
            tool_calls=3,
        )
        decision = knowledge_memory_v2.MemoryAdmissionPolicy().evaluate(episode)
        candidate = knowledge_memory_v2.extract_skill_candidate(episode, decision)
        payload = {
            'version': VERSION,
            'decision': dataclasses.asdict(decision) if hasattr(decision, '__dataclass_fields__') else decision.to_json(),
            'candidate': None if candidate is None else candidate.to_json(),
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0
    if args.command == "file-adapter":
        path = Path(args.path).expanduser().resolve()
        if not path.is_file():
            print(json.dumps({'error': 'file_missing', 'path': str(path)}, indent=2, sort_keys=True))
            return 1
        payload = {'inspect': file_adapters.inspect(path), 'validation': dict(zip(('passed', 'detail'), file_adapters.validate(path)))}
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    if args.command == "report":
        project = _project(args.project)
        combined = doctor(project)
        test_report = test_project(project, level="quick")
        combined.command = "report"
        combined.checks.extend(test_report.checks)
        return print_report(combined, json_output=args.json, output=args.output)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
