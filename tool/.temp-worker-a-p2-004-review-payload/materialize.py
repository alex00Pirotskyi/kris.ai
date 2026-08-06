#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import shutil
import zlib


CHUNKS = {
    "part-00.b64": "6de3070687fbb5055249b238c511c14a03782840654f0bb910e3ddbf80eb0305",
    "part-01.b64": "951edcdf63981e51b3610a1657e10db139f440f32a8286a48a3a02d46624f63e",
    "part-02.b64": "fdbfe2afbd0148f5cd29e2463178efab975fdffb9c78d23db5e41a9b29003491",
    "part-03.b64": "c6c70cfe1c1be30adab030934899bf08285816c934da4d43e74e7c260b884557",
}
ENCODED_LENGTH = 18100
PAYLOAD_SHA256 = "1dba9b1f796145597044021a03d603dc29a7c712527a7b4db8c7f11f33fa17b0"
PERMANENT_WORKFLOW = ".github/workflows/worker-a-p2-004-measurement-contract.yml"


def _replace_once(text: str, old: str, new: str, *, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one source marker, found {text.count(old)}")
    return text.replace(old, new, 1)


def _direct_head_workflow(root: pathlib.Path) -> str:
    path = root / PERMANENT_WORKFLOW
    text = path.read_text(encoding="utf-8")
    text = _replace_once(
        text,
        "  pull_request:\n"
        "    branches:\n"
        "      - agent/a/p1-p2-new-roadmap-execution\n",
        "",
        label="pull-request trigger removal",
    )
    text = _replace_once(
        text,
        "        with:\n"
        "          persist-credentials: false\n",
        "        with:\n"
        "          persist-credentials: false\n"
        "          fetch-depth: 1\n"
        "          ref: ${{ github.sha }}\n",
        label="exact-head checkout",
    )
    setup = (
        "      - uses: actions/setup-python@"
        "5fda3b95a4ea91299a34e894583c3862153e4b97\n"
    )
    assert_step = (
        "      - name: Assert exact direct head\n"
        "        shell: bash\n"
        "        env:\n"
        "          EXPECTED_SHA: ${{ github.sha }}\n"
        "        run: |\n"
        '          test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"\n'
        '          test -z "$(git status --porcelain=v1)"\n'
    )
    text = _replace_once(
        text,
        setup,
        assert_step + setup,
        label="exact-head assertion",
    )
    old_validation = (
        "      - name: Validate P2-004 receipt bridge and fail-closed behavior\n"
        "        shell: bash\n"
        "        run: python tool/p2_task_assertion_cli_test.py --project . "
        "--max-command-seconds 15\n"
    )
    new_validation = (
        "      - name: Validate P2-004 trusted receipt and bridge contracts\n"
        "        shell: bash\n"
        "        run: |\n"
        "          python tool/p2_technology_spike_contract_test.py --project .\n"
        "          python tool/p2_task_assertion_cli_test.py --project . "
        "--max-command-seconds 15\n"
    )
    text = _replace_once(
        text,
        old_validation,
        new_validation,
        label="focused contract invocation",
    )
    return text


def _load_payload(root: pathlib.Path) -> tuple[dict[str, object], pathlib.Path]:
    payload_root = root / "tool/.temp-worker-a-p2-004-review-payload"
    encoded_parts: list[str] = []
    for name, expected_sha in CHUNKS.items():
        path = payload_root / name
        if not path.is_file():
            raise SystemExit(f"missing payload chunk: {name}")
        raw = path.read_bytes()
        actual = hashlib.sha256(raw).hexdigest()
        if actual != expected_sha:
            raise SystemExit(
                f"payload chunk digest mismatch: {name}: expected {expected_sha}, got {actual}"
            )
        encoded_parts.append(raw.decode("ascii"))
    encoded = "".join(encoded_parts)
    if len(encoded) != ENCODED_LENGTH:
        raise SystemExit(
            f"unexpected payload length: expected {ENCODED_LENGTH}, got {len(encoded)}"
        )
    raw_payload = zlib.decompress(base64.b64decode(encoded, validate=True))
    actual_payload_sha = hashlib.sha256(raw_payload).hexdigest()
    if actual_payload_sha != PAYLOAD_SHA256:
        raise SystemExit(
            "payload digest mismatch: "
            f"expected {PAYLOAD_SHA256}, got {actual_payload_sha}"
        )
    payload = json.loads(raw_payload.decode("utf-8"))
    if set(payload) != {
        "files",
        "validateFunction",
        "boundPaths",
        "progressAppendix",
    }:
        raise SystemExit("unexpected payload shape")
    if not isinstance(payload["files"], dict):
        raise SystemExit("payload files must be an object")
    return payload, payload_root


def _patch_runner(root: pathlib.Path, validate_function: object) -> None:
    if not isinstance(validate_function, str) or not validate_function.strip():
        raise SystemExit("validateFunction must be non-empty text")
    path = root / "tool/p2_task_platform_assertions.py"
    text = path.read_text(encoding="utf-8")
    marker = '        "KRISTIN_P2_TECH_DART_RECEIPT",\n'
    additions = (
        marker
        + '        "KRISTIN_P2_TECH_AUTHORIZED_ROOT",\n'
        + '        "KRISTIN_P2_TECH_TRUST_MANIFEST",\n'
        + '        "KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256",\n'
        + '        "KRISTIN_P2_TECH_SESSION_ID",\n'
        + '        "KRISTIN_P2_TECH_NONCE",\n'
    )
    if "KRISTIN_P2_TECH_AUTHORIZED_ROOT" not in text:
        text = _replace_once(
            text,
            marker,
            additions,
            label="P2 receipt environment allowlist",
        )
    start = text.index("def validate_technology_spike(data: dict) -> dict:")
    end = text.index("\n\ndef main() -> int:", start)
    text = text[:start] + validate_function.rstrip() + text[end:]
    path.write_text(text, encoding="utf-8")


def _patch_registry(root: pathlib.Path, bound_paths: object) -> None:
    if not isinstance(bound_paths, list) or not all(
        isinstance(value, str) and value for value in bound_paths
    ):
        raise SystemExit("boundPaths must be a non-empty string list")
    path = root / "config/test_center_registry.v1.json"
    registry = json.loads(path.read_text(encoding="utf-8"))
    mapping = next(
        (
            row
            for row in registry.get("affectedTestMappings", [])
            if isinstance(row, dict)
            and row.get("mappingId") == "affected.p2.owner-mode-source"
        ),
        None,
    )
    if not isinstance(mapping, dict):
        raise SystemExit("affected.p2.owner-mode-source mapping missing")
    mapping_paths = mapping.setdefault("pathPatterns", [])
    for relative in bound_paths:
        if relative not in mapping_paths:
            mapping_paths.append(relative)
    profile = next(
        (
            row
            for row in registry.get("projectTestProfiles", [])
            if isinstance(row, dict)
            and row.get("stableCheckId") == "tc.p2.acceptance-contract"
        ),
        None,
    )
    if not isinstance(profile, dict):
        raise SystemExit("tc.p2.acceptance-contract profile missing")
    for field in ("affectedPaths", "inputPaths"):
        values = profile.setdefault(field, [])
        for relative in bound_paths:
            if relative not in values:
                values.append(relative)
    path.write_text(json.dumps(registry, indent=2) + "\n", encoding="utf-8")


def _append_progress(root: pathlib.Path, appendix: object) -> None:
    if not isinstance(appendix, str):
        raise SystemExit("progressAppendix must be text")
    path = (
        root
        / "docs/roadmap/progress/"
        "2026-08-06-worker-a-p2-004-measurement-contract-repair.md"
    )
    text = path.read_text(encoding="utf-8")
    if "## Exact-review hardening" not in text:
        text += appendix
    path.write_text(text, encoding="utf-8")


def materialize(root: pathlib.Path) -> None:
    payload, payload_root = _load_payload(root)
    files = payload["files"]
    assert isinstance(files, dict)
    files[PERMANENT_WORKFLOW] = _direct_head_workflow(root)
    for relative, content in files.items():
        if not isinstance(relative, str) or not isinstance(content, str):
            raise SystemExit("payload file entries must map strings to strings")
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _patch_runner(root, payload["validateFunction"])
    _patch_registry(root, payload["boundPaths"])
    _append_progress(root, payload["progressAppendix"])
    shutil.rmtree(payload_root)
    for relative in (
        ".github/workflows/temp-worker-a-p2-004-review-diagnostic.yml",
        ".github/workflows/temp-worker-a-p2-004-review-repair.yml",
    ):
        (root / relative).unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    materialize(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
