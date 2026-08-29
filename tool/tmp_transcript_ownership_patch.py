from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CHAT = ROOT / 'lib/product/chat_control_plane_studio.dart'
ACTIONS = ROOT / 'lib/product/chat_control_plane_studio_actions.dart'
VIEW = ROOT / 'lib/product/chat_control_plane_studio_view.dart'
TEST = ROOT / 'test/product/chat_deferred_takeover_bridge_test.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def matching_paren(text: str, open_index: int) -> int:
    depth = 0
    quote = None
    triple = False
    escaped = False
    i = open_index
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
                i += 1
                continue
            if ch == '\\':
                escaped = True
                i += 1
                continue
            if triple:
                marker = quote * 3
                if text.startswith(marker, i):
                    quote = None
                    triple = False
                    i += 3
                    continue
                i += 1
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            if text.startswith(ch * 3, i):
                quote = ch
                triple = True
                i += 3
            else:
                quote = ch
                triple = False
                i += 1
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise SystemExit(f'unmatched parenthesis at offset {open_index}')


def unwrap_chat_line(expr: str):
    stripped = expr.strip()
    if stripped.endswith(','):
        stripped = stripped[:-1].rstrip()
    for kind in ('user', 'assistant'):
        prefix = f'_ChatLine.{kind}('
        if stripped.startswith(prefix):
            open_index = stripped.index('(')
            close_index = matching_paren(stripped, open_index)
            if stripped[close_index + 1:].strip():
                raise SystemExit(f'unexpected trailing content in {kind} line: {stripped}')
            return kind, stripped[open_index + 1:close_index]
    return None


def rewrite_transcript_adds(text: str, label: str) -> str:
    pattern = re.compile(r'transcript\s*\.\s*add\s*\(')
    replacements = []
    for match in pattern.finditer(text):
        open_index = text.find('(', match.start(), match.end())
        close_index = matching_paren(text, open_index)
        parsed = unwrap_chat_line(text[open_index + 1:close_index])
        if parsed is None:
            raise SystemExit(
                f'{label}: transcript.add at {match.start()} does not wrap _ChatLine.user/assistant'
            )
        kind, argument = parsed
        end = close_index + 1
        while end < len(text) and text[end].isspace() and text[end] != '\n':
            end += 1
        if end >= len(text) or text[end] != ';':
            raise SystemExit(f'{label}: transcript.add at {match.start()} is not terminated by ;')
        method = 'addUserMessage' if kind == 'user' else 'addAssistantMessage'
        replacement = f'conversationSession.{method}({argument});'
        replacements.append((match.start(), end + 1, replacement))
    if not replacements:
        raise SystemExit(f'{label}: expected transcript.add calls')
    for start, end, replacement in reversed(replacements):
        text = text[:start] + replacement + text[end:]
    return text


chat = CHAT.read_text()
chat = replace_once(
    chat,
    '  final List<_ChatLine> transcript = <_ChatLine>[];\n',
    '  List<KristinConversationMessage> get transcript => conversationSession.messages;\n',
    'canonical transcript getter',
)
chat = rewrite_transcript_adds(chat, 'chat')
chat = replace_once(
    chat,
    "\nclass _ChatLine {\n  const _ChatLine({required this.assistant, required this.text});\n\n  factory _ChatLine.user(String text) =>\n      _ChatLine(assistant: false, text: text);\n  factory _ChatLine.assistant(String text) =>\n      _ChatLine(assistant: true, text: text);\n\n  final bool assistant;\n  final String text;\n}\n",
    '',
    '_ChatLine class removal',
)
CHAT.write_text(chat)

actions = ACTIONS.read_text()
actions = rewrite_transcript_adds(actions, 'actions')
clear_pattern = re.compile(r'^\s*transcript\s*\.\s*clear\s*\(\s*\)\s*;\s*\n', re.MULTILINE)
actions, clear_count = clear_pattern.subn('', actions)
if clear_count != 1:
    raise SystemExit(f'actions transcript.clear: expected 1, found {clear_count}')
ACTIONS.write_text(actions)

view = VIEW.read_text()
view = replace_once(
    view,
    '  Widget _messageBubble(_ChatLine line) {',
    '  Widget _messageBubble(KristinConversationMessage line) {',
    'message bubble canonical type',
)
VIEW.write_text(view)

test = TEST.read_text()
anchor = "  test('Chat live execution projection is owned by the canonical session', () {\n"
insert = r'''  test('Chat visible transcript is owned by the canonical session', () {
    expect(chat, isNot(contains('final List<_ChatLine> transcript')));
    expect(chat, isNot(contains('class _ChatLine')));
    expect(
      chat,
      contains(
        'List<KristinConversationMessage> get transcript => conversationSession.messages;',
      ),
    );
    final mutationPattern = RegExp(r'transcript\s*\.\s*(?:add|clear)\s*\(');
    expect(mutationPattern.hasMatch(chat), isFalse);
    expect(mutationPattern.hasMatch(actions), isFalse);
    expect(chat, contains('conversationSession.addUserMessage(request);'));
    expect(chat, contains('conversationSession.addAssistantMessage('));
    expect(actions, contains('conversationSession.addAssistantMessage('));
    expect(
      view,
      contains('Widget _messageBubble(KristinConversationMessage line)'),
    );
  });

'''
if test.count(anchor) != 1:
    raise SystemExit(f'transcript contract anchor: expected 1, found {test.count(anchor)}')
test = test.replace(anchor, insert + anchor, 1)
TEST.write_text(test)

for path in (CHAT, ACTIONS, VIEW, TEST):
    content = path.read_text()
    if '_ChatLine' in content and path != TEST:
        raise SystemExit(f'{path}: stale _ChatLine remains')
    if re.search(r'transcript\s*\.\s*(?:add|clear)\s*\(', content) and path in (CHAT, ACTIONS):
        raise SystemExit(f'{path}: stale transcript mutation remains')

print('transcript ownership patch applied')
