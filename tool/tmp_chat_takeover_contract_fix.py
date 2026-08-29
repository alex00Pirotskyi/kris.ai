from pathlib import Path

path = Path('test/product/chat_deferred_takeover_bridge_test.dart')
text = path.read_text(encoding='utf-8')
old = """    expect(chat, contains('RunState.prepared'));
    expect(chat, contains('RunState.queued'));
    expect(chat, contains('RunState.cancelling'));
"""
new = """    expect(chat, contains('return !const <RunState>{'));
    expect(chat, contains('RunState.succeeded,'));
    expect(chat, contains('RunState.failed,'));
    expect(chat, contains('RunState.cancelled,'));
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected durable restore contract shape: {text.count(old)} matches')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
