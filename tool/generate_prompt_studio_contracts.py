#!/usr/bin/env python3
"""Generate deterministic Dart JSON contract constants for Prompt Studio 2."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "lib" / "product" / "generated" / "prompt_studio_contracts.g.dart"
FILES = [
    ("productSpecificationV2SchemaJson", "product_specification.v2.json"),
    ("taskPlanV2SchemaJson", "task_plan.v2.json"),
    ("promptEvaluationDatasetV1SchemaJson", "prompt_evaluation_dataset.v1.json"),
    ("planCapabilityCatalogV1Json", "plan_capability_catalog.v1.json"),
    ("planCompilationReportV1SchemaJson", "plan_compilation_report.v1.json"),
]


def generated() -> str:
    payloads: list[tuple[str, str, str]] = []
    digest = hashlib.sha256()
    for constant, filename in FILES:
        path = ROOT / "schemas" / filename
        text = path.read_text(encoding="utf-8").rstrip() + "\n"
        if "'''" in text:
            raise RuntimeError(f"{filename} cannot be embedded as a raw triple-quoted Dart string")
        digest.update(filename.encode("utf-8"))
        digest.update(b"\0")
        digest.update(text.encode("utf-8"))
        digest.update(b"\0")
        payloads.append((constant, filename, text))
    lines = [
        "// GENERATED FILE. DO NOT EDIT.",
        "// Source: tool/generate_prompt_studio_contracts.py",
        "",
        f"const promptStudioContractDigest = '{digest.hexdigest()}';",
        "const promptStudioSpecificationSchemaVersion = '2.0.0';",
        "const promptStudioTaskPlanSchemaVersion = '2.0.0';",
        "const promptStudioEvaluationSchemaVersion = '1.0.0';",
        "const promptStudioCompilerVersion = '1.0.0';",
        "",
    ]
    for constant, filename, text in payloads:
        lines.append(f"// {filename}")
        lines.append(f"const {constant} = r'''{text}''';")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = generated()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != expected:
            print(f"stale generated file: {OUTPUT.relative_to(ROOT)}")
            return 1
        print(f"generated Prompt Studio contracts are current: {OUTPUT.relative_to(ROOT)}")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(expected, encoding="utf-8")
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
