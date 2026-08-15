#!/usr/bin/env python3
"""Patch the one-shot P5 materializer before it resets to protected main."""
from pathlib import Path

path = Path("tool/temp_p5_main_delivery_20260815.py")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    '    run("dart", "format", *format_paths)\n'
    '    run("python3", "tool/p1a_refresh_source_manifest.py", ".")\n',
    '    run("flutter", "pub", "get")\n'
    '    run("dart", "format", *format_paths)\n'
    '    run("python3", "tool/p1a_refresh_source_manifest.py", ".")\n',
    "dependency-aware formatting order",
)
replace_once(
    '    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")\n'
    '    run("flutter", "pub", "get")\n'
    '    run("python3", "tool/dart_format_scope.py", "--check")\n',
    '    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")\n'
    '    run("python3", "tool/dart_format_scope.py", "--check")\n',
    "deduplicate dependency resolution",
)
replace_once(
    "import 'p5_information_architecture/p5_controller.dart';\n",
    "import 'p5_information_architecture/p5_controller.dart'\n"
    "    hide P5IterableFirstOrNull;\n",
    "controller-only iterable extension isolation",
)
replace_once(
    "Install or start it, then restart Kristin.",
    "Please install or start it, then restart Kristin.",
    "actionable Owner Mode recovery copy",
)

marker = "\ndef write_regressions() -> None:\n"
if text.count(marker) != 1:
    raise SystemExit("P2 inventory insertion point is not unique")
inventory_function = r'''

def update_p2_test_inventory() -> None:
    path = REPO_ROOT / "config/p2_source_inventory.v1.json"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '    "test/product/p2_owner_mode_test.dart",\n',
        '    "test/product/p2_owner_mode_failure_presentation_test.dart",\n'
        '    "test/product/p2_owner_mode_test.dart",\n',
        "P2 Owner Mode recovery test inventory",
    )
    path.write_text(text, encoding="utf-8", newline="\n")
'''
text = text.replace(marker, inventory_function + marker, 1)
replace_once(
    "    update_source_contract()\n    write_regressions()\n",
    "    update_source_contract()\n"
    "    update_p2_test_inventory()\n"
    "    write_regressions()\n",
    "P2 inventory update call",
)
replace_once(
    '        "SOURCE_MANIFEST.sha256",\n'
    '        "lib/product/ui.dart",\n',
    '        "SOURCE_MANIFEST.sha256",\n'
    '        "config/p2_source_inventory.v1.json",\n'
    '        "lib/product/ui.dart",\n',
    "candidate scope for governed P2 inventory",
)

path.write_text(text, encoding="utf-8", newline="\n")
