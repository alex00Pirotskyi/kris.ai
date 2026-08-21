#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
V54_ENTRY = pathlib.Path(__file__).with_name("kris_qwen_worker_v54.py")
TARGET_VERSION = "5.4.1"


def load_module(path: pathlib.Path, name: str, label: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"KRIS_QWEN_V541_ERROR: cannot load {label}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"KRIS_QWEN_V541_ERROR: {label} expected exactly one source anchor, got {count}"
        )
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    v54 = load_module(V54_ENTRY, "kris_qwen_v54_transform_for_541", "5.4.0 worker transformer")
    text = v54.transform(text)

    text = replace_exact(
        text,
        'SCRIPT_VERSION = "5.4.0"',
        'SCRIPT_VERSION = "5.4.1"',
        "worker version",
    )

    old_catalog = '''def _engineering_catalog_path(cfg: Config) -> pathlib.Path:\n    return cfg.anchor / QWEN_ENGINEERING_SKILLS_V1\n'''
    new_catalog = '''def _engineering_execution_root() -> pathlib.Path:\n    # Engineering policy belongs to the exact worker checkout whose bytes were\n    # candidate-probed by controller 2.2. It must never be sourced from the\n    # mutable authority/Product clone under cfg.anchor.\n    return pathlib.Path(__file__).resolve().parents[1]\n\n\ndef _engineering_catalog_path(cfg: Config) -> pathlib.Path:\n    del cfg\n    return _engineering_execution_root() / QWEN_ENGINEERING_SKILLS_V1\n\n\ndef validate_engineering_environment(cfg: Config) -> dict[str, Any]:\n    catalog_path = _engineering_catalog_path(cfg)\n    catalog = load_engineering_skill_catalog(cfg)\n    execution_root = _engineering_execution_root()\n    manifest_path = execution_root / "SOURCE_MANIFEST.sha256"\n    if not manifest_path.is_file():\n        raise WorkerError(f"Qwen engineering source manifest is missing: {manifest_path}")\n    expected = None\n    for line in manifest_path.read_text(encoding="utf-8").splitlines():\n        if "  " not in line:\n            continue\n        digest, relative = line.split("  ", 1)\n        if relative == QWEN_ENGINEERING_SKILLS_V1:\n            expected = digest.strip().lower()\n            break\n    if expected is None:\n        raise WorkerError("Qwen engineering skill catalog is not bound by SOURCE_MANIFEST.sha256")\n    data = catalog_path.read_bytes()\n    try:\n        data.decode("utf-8")\n    except UnicodeDecodeError as exc:\n        raise WorkerError("Qwen engineering skill catalog is not UTF-8") from exc\n    actual = hashlib.sha256(data.replace(b"\\r\\n", b"\\n")).hexdigest()\n    if actual != expected:\n        raise WorkerError(\n            "Qwen engineering skill catalog source identity mismatch: "\n            f"manifest={expected} actual={actual}"\n        )\n    return {\n        "catalogPath": str(catalog_path),\n        "catalogSha256": actual,\n        "skillCount": len(catalog.get("skills", [])),\n        "executionRoot": str(execution_root),\n    }\n'''
    text = replace_exact(text, old_catalog, new_catalog, "validated execution-checkout catalog root")

    text = replace_exact(
        text,
        '        lease = reserve_work(cfg, worker_identity, work_execution_id)\n',
        '        validate_engineering_environment(cfg)\n        lease = reserve_work(cfg, worker_identity, work_execution_id)\n',
        "engineering validation before semaphore reservation",
    )

    required = (
        'SCRIPT_VERSION = "5.4.1"',
        'def _engineering_execution_root',
        'return pathlib.Path(__file__).resolve().parents[1]',
        'def validate_engineering_environment',
        'SOURCE_MANIFEST.sha256',
        'validate_engineering_environment(cfg)\n        lease = reserve_work',
        'TEXTUAL_UI_STRUCTURE_ONLY',
        'RED_ALERT_PRODUCT_DIVERGENCE',
        'RED_ALERT_HARD_ERROR',
        'RED_ALERT_MODEL_SERVER',
        'engineeringRecipe',
    )
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"KRIS_QWEN_V541_ERROR: transformed worker missing markers: {missing}")
    compile(text, str(SOURCE), "exec")
    return text


def main() -> None:
    transformed = transform(SOURCE.read_text(encoding="utf-8"))
    namespace = {
        "__name__": "__main__",
        "__file__": str(pathlib.Path(__file__).resolve()),
        "__package__": None,
        "__cached__": None,
    }
    exec(compile(transformed, str(SOURCE), "exec"), namespace, namespace)


if __name__ == "__main__":
    main()
