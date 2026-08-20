#!/usr/bin/env python3
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, got {count}")
    return text.replace(old, new, 1)


def write(relative: str, text: str) -> None:
    (ROOT / relative).write_text(text, encoding="utf-8", newline="\n")


def materialize_controller() -> None:
    # Keep the canonical controller module identity intact. Existing controller
    # tests and controller 2.2 monkey-patch globals on this module directly.
    # Only remove the one unsafe bearer-token print from the retained 2.1 base.
    path = ROOT / "tool/kris_qwen_control.py"
    text = path.read_text(encoding="utf-8")
    text = one(
        text,
        '        print("\\nPHONE CONTROL TOKEN (keep private):", controller.token, flush=True)\n',
        '        print(\n            "\\nPhone control token value omitted from logs; read it from configured token file:",\n            controller.token_path,\n            flush=True,\n        )\n',
        "controller token redaction",
    )
    text = text.replace(
        'placeholder="Paste token from server terminal"',
        'placeholder="Paste token from controller token file"',
    )
    write("tool/kris_qwen_control.py", text)


def materialize_worker() -> None:
    write(
        "tool/kris_qwen_worker_v53.py",
        '''#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import runpy

TARGET_VERSION = "5.4.1"
HERE = pathlib.Path(__file__).resolve().parent
ENTRY = HERE / "kris_qwen_worker_v541.py"
ENGINEERING = HERE / "kris_qwen_engineering_env.py"
CATALOG = HERE.parent / "config/qwen_engineering_skills.v1.json"


def validate_dependencies() -> None:
    for path, label in (
        (ENTRY, "deterministic 5.4.1 worker entry"),
        (ENGINEERING, "5.4 engineering environment"),
        (CATALOG, "5.4 engineering skill catalog"),
    ):
        if not path.is_file():
            raise SystemExit(f"KRIS_QWEN_V53_FORWARD_ERROR: {label} is missing: {path}")
    try:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"KRIS_QWEN_V53_FORWARD_ERROR: engineering skill catalog is invalid: {exc}") from exc
    if catalog.get("schemaVersion") != "1.0.0" or not isinstance(catalog.get("skills"), list) or not catalog["skills"]:
        raise SystemExit("KRIS_QWEN_V53_FORWARD_ERROR: engineering skill catalog contract is invalid")


def main() -> None:
    validate_dependencies()
    runpy.run_path(str(ENTRY), run_name="__main__")


if __name__ == "__main__":
    main()
''',
    )


def update_launcher() -> None:
    path = ROOT / "run_my_server.py"
    text = path.read_text(encoding="utf-8").replace("5.3.1", "5.4.1")
    text = one(
        text,
        '    print("The controller will print the control token below.")\n',
        '    print("The control token value is never printed; read it from the controller token file.")\n',
        "launcher token guidance",
    )
    write("run_my_server.py", text)


def update_installer() -> None:
    path = ROOT / "tool/install_kris_qwen_control_systemd.sh"
    text = path.read_text(encoding="utf-8")
    text = text.replace("engineering worker 5.4 / controller 2.2", "engineering worker 5.4.1 / controller 2.2")
    text = one(
        text,
        '  "${REPO_DIR}/tool/kris_qwen_worker_v54.py"\n  "${REPO_DIR}/tool/kris_qwen_v53_policy.py"\n',
        '  "${REPO_DIR}/tool/kris_qwen_worker_v54.py"\n  "${REPO_DIR}/tool/kris_qwen_worker_v541.py"\n  "${REPO_DIR}/tool/kris_qwen_v53_policy.py"\n',
        "installer required v541",
    )
    text = one(
        text,
        '  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py"\n)\n',
        '  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py"\n  "${REPO_DIR}/tool/kris_qwen_v541_test.py"\n  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n  "${REPO_DIR}/tool/rotate_kris_qwen_control_token.sh"\n)\n',
        "installer required incident files",
    )
    text = one(
        text,
        '  "${REPO_DIR}/tool/kris_qwen_worker_v54.py" \\\n  "${REPO_DIR}/tool/kris_qwen_v53_policy.py" \\\n',
        '  "${REPO_DIR}/tool/kris_qwen_worker_v54.py" \\\n  "${REPO_DIR}/tool/kris_qwen_worker_v541.py" \\\n  "${REPO_DIR}/tool/kris_qwen_v53_policy.py" \\\n',
        "installer compile v541",
    )
    text = one(
        text,
        '  "${REPO_DIR}/tool/kris_qwen_v531_test.py" \\\n  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py"\n',
        '  "${REPO_DIR}/tool/kris_qwen_v531_test.py" \\\n  "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py" \\\n  "${REPO_DIR}/tool/kris_qwen_v541_test.py" \\\n  "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py"\n',
        "installer compile incident tests",
    )
    text = text.replace('"scriptVersion": "5.4.0"', '"scriptVersion": "5.4.1"')
    text = text.replace("Qwen worker 5.4 preflight failed", "Qwen worker 5.4.1 preflight failed")
    marker = 'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_engineering_env_test.py" >/dev/null; then\n  echo "Qwen worker 5.4 engineering-environment regression preflight failed." >&2\n  exit 2\nfi\n'
    text = one(
        text,
        marker,
        marker
        + 'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_v541_test.py" >/dev/null; then\n  echo "Qwen worker 5.4.1 deployment regression preflight failed." >&2\n  exit 2\nfi\n'
        + 'if ! as_service_user "${PYTHON_BIN}" "${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py" >/dev/null; then\n  echo "Qwen controller token-redaction regression preflight failed." >&2\n  exit 2\nfi\n',
        "installer incident tests",
    )
    text = text.replace("forwards to deterministic 5.4.", "forwards to deterministic 5.4.1.")
    text = one(
        text,
        'ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_engineering_env_test.py\n',
        'ExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_engineering_env_test.py\nExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_v541_test.py\nExecStartPre=${PYTHON_BIN} ${REPO_DIR}/tool/kris_qwen_control_token_redaction_test.py\n',
        "systemd incident tests",
    )
    text = text.replace("Worker:       5.4.0", "Worker:       5.4.1")
    text = text.replace("controller 2.2 / worker 5.4,", "controller 2.2 / worker 5.4.1,")
    text = text.replace("and the 5.4 engineering environment", "and the 5.4.1 engineering environment")
    write("tool/install_kris_qwen_control_systemd.sh", text)


def update_ci() -> None:
    path = ROOT / ".github/workflows/ci.yml"
    text = path.read_text(encoding="utf-8")
    text = text.replace("Qwen 5.4 engineering worker regression", "Qwen 5.4.1 engineering worker regression")
    text = one(
        text,
        '            tool/kris_qwen_worker_v54.py \\\n',
        '            tool/kris_qwen_worker_v54.py \\\n            tool/kris_qwen_worker_v541.py \\\n',
        "ci v541 compile",
    )
    text = one(
        text,
        '            tool/kris_qwen_engineering_env_test.py\n',
        '            tool/kris_qwen_engineering_env_test.py \\\n            tool/kris_qwen_v541_test.py \\\n            tool/kris_qwen_control_token_redaction_test.py\n',
        "ci incident compile",
    )
    text = one(
        text,
        '          python tool/kris_qwen_engineering_env_test.py\n',
        '          python tool/kris_qwen_engineering_env_test.py\n          python tool/kris_qwen_v541_test.py\n          python tool/kris_qwen_control_token_redaction_test.py\n',
        "ci incident run",
    )
    text = text.replace("kris-qwen-v54-version.json", "kris-qwen-v541-version.json")
    text = text.replace("value.get('scriptVersion') == '5.4.0'", "value.get('scriptVersion') == '5.4.1'")
    text = text.replace("endswith('kris_qwen_worker_v54.py')", "endswith('kris_qwen_worker_v541.py')")
    write(".github/workflows/ci.yml", text)


def cleanup_transports() -> None:
    for relative in (
        "tool/kris_qwen_control_secure.py",
        "tool/kris_qwen_control_secure_test.py",
        "tool/kris_qwen_control_v21_base.py",
        ".github/workflows/qwen-v541-hotfix-validation.yml",
        ".github/workflows/qwen-v541-finalize.yml",
        ".github/workflows/qwen-v541-pr-finalize.yml",
        ".github/workflows/qwen-v541-pr-finalize-v2.yml",
        ".github/workflows/qwen-v541-pr-finalize-v3.yml",
        "tool/qwen_v541_finalize.py",
    ):
        try:
            (ROOT / relative).unlink()
        except FileNotFoundError:
            pass


def main() -> None:
    materialize_controller()
    materialize_worker()
    update_launcher()
    update_installer()
    update_ci()
    cleanup_transports()


if __name__ == "__main__":
    main()
