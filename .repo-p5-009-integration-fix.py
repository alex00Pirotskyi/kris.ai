from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one integration anchor, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


view = Path('lib/product/p5_information_architecture/p5_verification_workspaces.dart')
replace_once(
    view,
    """        if (savedRun == null)\n          const _BoundaryNotice(\n            key: Key('evidence-no-saved-run'),\n            message:\n                'Select a saved run in Runs / Activity to reopen typed artifact, diff, citation, and receipt viewers. Current in-memory runs do not fabricate saved evidence.',\n          )\n""",
    """        if (savedRun == null)\n          const KeyedSubtree(\n            key: Key('evidence-no-saved-run'),\n            child: _BoundaryNotice(\n              message:\n                  'Select a saved run in Runs / Activity to reopen typed artifact, diff, citation, and receipt viewers. Current in-memory runs do not fabricate saved evidence.',\n            ),\n          )\n""",
)

controller = Path('lib/product/p5_information_architecture/p5_controller.dart')
lines = controller.read_text(encoding='utf-8').splitlines(keepends=True)
targets = [
    index
    for index, line in enumerate(lines)
    if line.strip() == 'selectedRunId: null,'
]
if len(targets) != 10:
    raise SystemExit(f'{controller}: expected 10 run-context clear lines, found {len(targets)}')
already_covered = [
    index
    for index in targets
    if index + 1 < len(lines) and lines[index + 1].strip() == 'selectedEvidenceId: null,'
]
if len(already_covered) != 1:
    raise SystemExit(
        f'{controller}: expected exactly 1 already-covered evidence clear, '
        f'found {len(already_covered)}'
    )
output: list[str] = []
inserted = 0
for index, line in enumerate(lines):
    output.append(line)
    if index not in targets or index in already_covered:
        continue
    indent = line[: len(line) - len(line.lstrip())]
    output.append(f'{indent}selectedEvidenceId: null,\n')
    inserted += 1
if inserted != 9:
    raise SystemExit(f'{controller}: expected to insert 9 evidence clears, inserted {inserted}')
controller.write_text(''.join(output), encoding='utf-8', newline='\n')
