#!/usr/bin/env python3
"""Run the Worker F recovery patch without adding a YAML dependency."""
from __future__ import annotations

import runpy
import sys
import textwrap
import types


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


yaml_module = types.ModuleType("yaml")
yaml_module.safe_load = safe_load
sys.modules["yaml"] = yaml_module
runpy.run_path("tool/worker_f_recovery_patch.py", run_name="__main__")
