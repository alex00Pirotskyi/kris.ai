from pathlib import Path

chat = Path('lib/product/chat_control_plane_studio.dart')
text = chat.read_text(encoding='utf-8')
old = """  String? selectedProjectId;\n  String? selectedModelId;\n  ProjectProcessStatus? projectProcessStatus;\n"""
new = """  String? get selectedProjectId => conversationSession.selectedProjectId;\n  set selectedProjectId(String? value) {\n    conversationSession.selectProject(value);\n  }\n\n  String? get selectedModelId => conversationSession.selectedModelId;\n  set selectedModelId(String? value) {\n    conversationSession.selectModel(value);\n  }\n\n  ProjectProcessStatus? projectProcessStatus;\n"""
if text.count(old) != 1:
    raise SystemExit('unexpected selected-context source shape')
chat.write_text(text.replace(old, new), encoding='utf-8', newline='\n')

test = Path('test/product/chat_deferred_takeover_bridge_test.dart')
text = test.read_text(encoding='utf-8')
marker = """    expect(\n        chat,\n        contains(\n            'bool get hasNonterminalRun => conversationSession.hasNonterminalRun;'));\n  });\n"""
replacement = """    expect(\n        chat,\n        contains(\n            'bool get hasNonterminalRun => conversationSession.hasNonterminalRun;'));\n    expect(chat, isNot(contains('String? selectedProjectId;')));\n    expect(chat, isNot(contains('String? selectedModelId;')));\n    expect(\n      chat,\n      contains(\n        'String? get selectedProjectId => conversationSession.selectedProjectId;',\n      ),\n    );\n    expect(\n      chat,\n      contains(\n        'String? get selectedModelId => conversationSession.selectedModelId;',\n      ),\n    );\n    expect(chat, contains('conversationSession.selectProject(value);'));\n    expect(chat, contains('conversationSession.selectModel(value);'));\n  });\n"""
if text.count(marker) != 1:
    raise SystemExit('unexpected chat bridge test shape')
test.write_text(text.replace(marker, replacement), encoding='utf-8', newline='\n')
