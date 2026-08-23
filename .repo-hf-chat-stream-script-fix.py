from pathlib import Path

path = Path('.repo-hf-chat-stream-final.py')
text = path.read_text(encoding='utf-8')
old = (
    "replace_once(\n"
    "    'lib/product/chat_studio.dart',\n"
    "    '''      liveAssistantText = '';\\n"
    "      liveAssistantStage = '';\\n"
    "      liveAssistantMessage = '';\\n"
    "''',\n"
    "    '''      liveAssistantText = '';\\n"
    "      liveAssistantProtocolText = '';\\n"
    "      liveAssistantStage = '';\\n"
    "      liveAssistantMessage = '';\\n"
    "''',\n"
    ")\n"
)
new = (
    "replace_once(\n"
    "    'lib/product/chat_studio.dart',\n"
    "    '''      conversationUserRequest = request;\\n"
    "      conversationIntent = intent;\\n"
    "      liveAssistantText = '';\\n"
    "      liveAssistantStage = '';\\n"
    "      liveAssistantMessage = '';\\n"
    "''',\n"
    "    '''      conversationUserRequest = request;\\n"
    "      conversationIntent = intent;\\n"
    "      liveAssistantText = '';\\n"
    "      liveAssistantProtocolText = '';\\n"
    "      liveAssistantStage = '';\\n"
    "      liveAssistantMessage = '';\\n"
    "''',\n"
    ")\n"
)
if text.count(old) != 1:
    raise SystemExit(f'script repair anchor mismatch: {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
