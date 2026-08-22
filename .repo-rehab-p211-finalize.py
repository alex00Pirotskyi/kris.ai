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

contract_path = Path('test/product/source_contract_test.dart')
contract = contract_path.read_text(encoding='utf-8')
replacements = {
    "      expect(studio, contains(\"'Generate prompt'\"));\n":
        "      expect(studio, contains(\"'Generate final prompt'\"));\n",
    "      expect(studio, contains(\"'Generate task list'\"));\n":
        "      expect(studio, contains(\"'Review execution plan'\"));\n",
}
for old_label, new_label in replacements.items():
    if contract.count(old_label) != 1:
        raise SystemExit(f'P211 Prompt Studio label anchor mismatch: {old_label.strip()}')
    contract = contract.replace(old_label, new_label)
contract_path.write_text(contract, encoding='utf-8')

print('Applied the bounded P211 retry and source-contract repair.')
