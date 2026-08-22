from pathlib import Path

path = Path('tool/validate_release.py')
text = path.read_text(encoding='utf-8')
old = '''        integrated_shell_is_chat_first = (\n            "home: KristinMainShell(" in ui\n            and "chat: ChatStudio(" in ui\n            and "var _index = 0;" in ui\n            and source_contains(\n                ui,\n                "final pages = <Widget>[ widget.chat, "\n                "P5InformationArchitecturePrototype( "\n                "controller: _experienceController, ), "\n                "widget.ownerMode.buildWorkspace(",\n            )\n        )\n'''
new = '''        chat_offset = ui.find("widget.chat,")\n        experience_offset = ui.find("P5InformationArchitecturePrototype(")\n        owner_offset = ui.find("widget.ownerMode.buildWorkspace(")\n        integrated_shell_is_chat_first = (\n            "home: KristinMainShell(" in ui\n            and "chat: ChatStudio(" in ui\n            and "var _index = 0;" in ui\n            and chat_offset >= 0\n            and experience_offset > chat_offset\n            and owner_offset > experience_offset\n        )\n'''
if text.count(old) != 1:
    raise SystemExit(f'P217 validator anchor count={text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P217_VALIDATOR_ALIGNMENT_APPLIED')
