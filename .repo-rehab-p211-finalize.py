from pathlib import Path

prompt_path = Path('lib/product/prompt_planning.dart')
prompt = prompt_path.read_text(encoding='utf-8')
old_retry = """          maxAttempts: alignedManual
              ? 1
              : (int.tryParse(raw['maxAttempts']?.toString() ?? '') ?? 1)
                  .clamp(1, 2)
                  .toInt(),
"""
new_retry = """          maxAttempts: alignedManual
              ? 1
              : (int.tryParse(raw['maxAttempts']?.toString() ?? '') ?? 2)
                  .clamp(2, 3)
                  .toInt(),
"""
if prompt.count(old_retry) != 1:
    raise SystemExit('P211 retry-contract anchor mismatch')
prompt_path.write_text(prompt.replace(old_retry, new_retry), encoding='utf-8')

label_replacements = {
    "'Generate prompt'": "'Generate final prompt'",
    "'Generate task list'": "'Review execution plan'",
}

contract_path = Path('test/product/source_contract_test.dart')
contract = contract_path.read_text(encoding='utf-8')
for old_label, new_label in label_replacements.items():
    old_line = f'      expect(studio, contains("{old_label}"));\n'
    new_line = f'      expect(studio, contains("{new_label}"));\n'
    if contract.count(old_line) != 1:
        raise SystemExit(f'P211 source-contract label anchor mismatch: {old_label}')
    contract = contract.replace(old_line, new_line)
contract_path.write_text(contract, encoding='utf-8')

validator_path = Path('tool/validate_release.py')
validator = validator_path.read_text(encoding='utf-8')
for old_label, new_label in label_replacements.items():
    old_line = f'                "{old_label}",\n'
    new_line = f'                "{new_label}",\n'
    if validator.count(old_line) != 1:
        raise SystemExit(f'P211 release-validator label anchor mismatch: {old_label}')
    validator = validator.replace(old_line, new_line)
validator_path.write_text(validator, encoding='utf-8')

print('Applied the bounded P211 retry and source-contract repair.')
