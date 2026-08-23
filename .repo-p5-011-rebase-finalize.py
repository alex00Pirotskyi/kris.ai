from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'anchor mismatch {path}: expected 1 got {count}: {old[:120]!r}'
        )
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/product/chat_studio.dart',
    '''        const SizedBox(height: 18),
        if ((promptGenerationActive || embeddedClarificationActive) &&
            command == null)
''',
    '''        const SizedBox(height: 18),
        if (capabilityDoctorReport?.depth == CapabilityDoctorDepth.full) ...<Widget>[
          _capabilityDoctorCard(capabilityDoctorReport!),
          const SizedBox(height: 18),
        ],
        if ((promptGenerationActive || embeddedClarificationActive) &&
            command == null)
''',
)

replace_once(
    'test/product/p5_capability_doctor_test.dart',
    "    expect(chat, contains('_capabilityDoctorCard('));\n",
    "    expect(chat, contains('_capabilityDoctorCard('));\n    expect(\n      chat,\n      matches(\n        RegExp(\n          r'capabilityDoctorReport\\?\\.depth\\s*==\\s*CapabilityDoctorDepth\\.full',\n        ),\n      ),\n    );\n",
)

replace_once(
    'test/product/source_contract_test.dart',
    "        'lib/product/browser/web_studio.dart',\n        'lib/product/chat_studio.dart',\n",
    "        'lib/product/browser/web_studio.dart',\n        'lib/product/capability_doctor.dart',\n        'lib/product/chat_studio.dart',\n",
)
