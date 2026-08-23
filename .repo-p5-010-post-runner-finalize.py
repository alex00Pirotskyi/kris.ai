from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


source_contract = 'test/product/source_contract_test.dart'
replace_once(
    source_contract,
    """        'lib/product/p5_design_tokens.dart',
        'lib/product/p5_global_autonomy.dart',
""",
    """        'lib/product/p5_command_palette.dart',
        'lib/product/p5_design_tokens.dart',
        'lib/product/p5_global_autonomy.dart',
""",
)
replace_once(
    source_contract,
    """      expect(ui, contains('P5GlobalAutonomyBar(binding: _autonomyBinding)'));
      expect(ui, contains('globalAutonomy: _autonomyBinding'));
""",
    """      expect(ui, contains('P5GlobalAutonomyBar('));
      expect(ui, contains('binding: _autonomyBinding'));
      expect(ui, contains('onOpenCommands: _openCommandPalette'));
      expect(ui, contains('globalAutonomy: _autonomyBinding'));
""",
)
