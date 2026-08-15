#!/usr/bin/env python3
"""One-shot pinning materializer for runtime-control GitHub Actions."""
from __future__ import annotations

from pathlib import Path
import re
import sys

PINS = {
    "actions/checkout": "3d3c42e5aac5ba805825da76410c181273ba90b1",  # v7.0.1
    "actions/setup-python": "5fda3b95a4ea91299a34e894583c3862153e4b97",  # v7.0.0
    "actions/setup-node": "48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e",  # pinned current
    "actions/upload-artifact": "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",  # v7.0.1
    "actions/download-artifact": "3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",  # v8.0.1
    "subosito/flutter-action": "1a449444c387b1966244ae4d4f8c696479add0b2",  # v2.23.0
}
USE_RE = re.compile(r"^(?P<prefix>\s*(?:-\s*)?uses:\s*)(?P<ref>[^\s#]+)(?P<suffix>\s*(?:#.*)?)$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def main() -> int:
    project = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    workflow_dir = project / ".github" / "workflows"
    changed: list[str] = []
    unresolved: list[str] = []

    for path in sorted(workflow_dir.glob("*.y*ml")):
        lines = path.read_text(encoding="utf-8").splitlines()
        output: list[str] = []
        path_changed = False
        for number, line in enumerate(lines, start=1):
            match = USE_RE.match(line)
            if match is None:
                output.append(line)
                continue
            reference = match.group("ref").strip("'\"")
            if reference.startswith("./") or reference.startswith("docker://"):
                output.append(line)
                continue
            if "@" not in reference:
                unresolved.append(f"{path.relative_to(project)}:{number}: {reference}")
                output.append(line)
                continue
            action, revision = reference.rsplit("@", 1)
            if SHA_RE.fullmatch(revision):
                output.append(line)
                continue
            pin = PINS.get(action)
            if pin is None:
                unresolved.append(f"{path.relative_to(project)}:{number}: {reference}")
                output.append(line)
                continue
            replacement = f"{match.group('prefix')}{action}@{pin}{match.group('suffix')}"
            output.append(replacement)
            path_changed = True
        if path_changed:
            path.write_text("\n".join(output) + "\n", encoding="utf-8", newline="\n")
            changed.append(path.relative_to(project).as_posix())

    if unresolved:
        raise SystemExit("unresolved mutable actions:\n" + "\n".join(unresolved))
    if not changed:
        raise SystemExit("no mutable runtime Action references found")
    print("GS004A_PINNED_ACTIONS files=" + str(len(changed)))
    for relative in changed:
        print(relative)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
