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
text = controller.read_text(encoding='utf-8')
needle = '        selectedRunId: null,\n'
count = text.count(needle)
if count != 10:
    raise SystemExit(f'{controller}: expected 10 run-context clear anchors, found {count}')
controller.write_text(
    text.replace(
        needle,
        needle + '        selectedEvidenceId: null,\n',
    ),
    encoding='utf-8',
    newline='\n',
)
