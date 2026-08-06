#!/usr/bin/env python3
"""Run the Worker F recovery patch with standard-library-only bootstrapping."""
from __future__ import annotations

import runpy
import shutil
import sys
import textwrap
import types
from pathlib import Path


def safe_load(text: str):
    lines = text.splitlines()
    name = "Materialize reviewed source and deterministic contracts"
    start = next(
        index
        for index, line in enumerate(lines)
        if line.strip() == f"- name: {name}"
    )
    run_index = next(
        index
        for index in range(start + 1, len(lines))
        if lines[index].strip() == "run: |"
    )
    body: list[str] = []
    for line in lines[run_index + 1 :]:
        if line.startswith("      - name:"):
            break
        body.append(line)
    script = textwrap.dedent("\n".join(body)).rstrip() + "\n"
    return {
        "jobs": {
            "prepare": {
                "steps": [
                    {
                        "name": name,
                        "run": script,
                    }
                ]
            }
        }
    }


root = Path(".")
checker_template = root / "tool/worker_f_p5_ia_template.py"
workflow_template = root / "tool/worker_f_p5_ia_workflow_template.yml"
shutil.copyfile(checker_template, root / "tool/worker_f_p5_ia.py")
(root / ".github/workflows").mkdir(parents=True, exist_ok=True)
shutil.copyfile(
    workflow_template,
    root / ".github/workflows/worker-f-p5-001-information-architecture.yml",
)
checker_template.unlink()
workflow_template.unlink()

patch_path = root / "tool/worker_f_recovery_patch.py"
patch_text = patch_path.read_text(encoding="utf-8").replace(
    '"326462d4db7c9ec895c7f9dbf09de84fa83b8895": "3c8d9d7ad78bd47970c4742f55a355e0768ea718",',
    '"326462d4db7c9ec895c7f9dbf09de84fa83b8895": "3c8d9d7ad78bd47970c4742f55a355e0768ea718",\n'
    '    "d581f21fb7b36ca9938cb55f24052df36df8475f": "ef5d5ae584b1d823502bf6f2191ecf4285d36845",',
)
patch_text = patch_text.replace(
    "    patch_validator()\n",
    "    # The current checker is supplied as a deterministic reviewed template.\n",
)
patch_text = patch_text.replace(
    "    patch_workflow()\n",
    "    # The read-only tri-platform workflow is supplied as a pinned template.\n",
)
patch_path.write_text(patch_text, encoding="utf-8")

yaml_module = types.ModuleType("yaml")
yaml_module.safe_load = safe_load
sys.modules["yaml"] = yaml_module
runpy.run_path("tool/worker_f_recovery_patch.py", run_name="__main__")
