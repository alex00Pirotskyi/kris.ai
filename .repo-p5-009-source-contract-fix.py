from pathlib import Path

path = Path('test/product/source_contract_test.dart')
text = path.read_text(encoding='utf-8')
old = """        'lib/product/p5_information_architecture/p5_controller.dart',
        'lib/product/p5_information_architecture/p5_fixtures.dart',
"""
new = """        'lib/product/p5_information_architecture/p5_controller.dart',
        'lib/product/p5_information_architecture/p5_evidence_viewers.dart',
        'lib/product/p5_information_architecture/p5_fixtures.dart',
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one governed P5 source anchor, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P5_009_GOVERNED_SOURCE_CONTRACT_FIX_APPLIED')
