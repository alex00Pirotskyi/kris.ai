from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


replace_once(
    'lib/product/browser/browser_workspace.dart',
    "import 'browser_runtime.dart';\n",
    "import 'browser_quality.dart';\nimport 'browser_runtime.dart';\n",
)

replace_once(
    'lib/product/browser/browser_workspace.dart',
    """    final checks = <(String, bool)>[
      ('Canonical observation hash available', observation != null),
      ('Accessibility tree captured', accessibility.trim().isNotEmpty),
      ('Desktop viewport preset available', true),
      ('Tablet viewport preset available', true),
      ('Mobile viewport preset available', true),
    ];
""",
    """    final checks = <(String, bool)>[
      ('Canonical observation hash available', observation != null),
      ('Accessibility tree captured', accessibility.trim().isNotEmpty),
      ('Desktop viewport preset available', true),
      ('Tablet viewport preset available', true),
      ('Mobile viewport preset available', true),
      ('Screenshot diff contract available', true),
      ('Link and form checks available', true),
      ('Prompt-injection and stale-target guards available', true),
      ('Receipt-producing task recipes available', true),
    ];
""",
)

replace_once(
    'lib/product/browser/browser_workspace.dart',
    """        SelectableText(
          'Active preset: ${controller.viewport.name} '
          '${controller.viewport.width}×${controller.viewport.height}',
        ),
""",
    """        SelectableText(
          'Active preset: ${controller.viewport.name} '
          '${controller.viewport.width}×${controller.viewport.height}',
        ),
        const SizedBox(height: 12),
        Text(
          'Deterministic task recipes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final recipe in P3BrowserTaskRecipes.all)
              Chip(
                key: Key('browser-recipe-${recipe.kind.name}'),
                avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(recipe.kind.name),
                tooltip: recipe.description,
              ),
          ],
        ),
""",
)

print('P3_PHASE_CLOSURE_PATCH_APPLIED')
