from pathlib import Path

path = Path('lib/product/p5_information_architecture/p5_task_workspaces.dart')
text = path.read_text(encoding='utf-8')
replacements = {
    """                      FilledButton.tonalIcon(
                        key: const Key('review-plan-button'),
""": """                      FilledButton.icon(
                        key: const Key('review-plan-button'),
""",
    """                      FilledButton.icon(
                        key: const Key('start-run-button'),
""": """                      OutlinedButton.icon(
                        key: const Key('start-run-button'),
""",
}
for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one P5-006 compatibility anchor, found {count}: {old!r}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')
print('P5_006_COMPAT_FIX_APPLIED')
