#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'lib/product/chat_control_plane_studio_actions.dart'
text = path.read_text(encoding='utf-8')
start = '  String? _timeLocationFromText(String text) {'
end = '  String _formatUtilityTime(UtilityTimeResult result) {'
start_at = text.find(start)
end_at = text.find(end, start_at)
if start_at < 0 or end_at < 0:
    raise SystemExit('time-location method boundary not found')
method = r'''  String? _timeLocationFromText(String text) {
    final match = RegExp(
      r'\b(?:time|local time)\s+(?:in|at)\s+(.+?)(?:[?.!,;]|$)',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match != null) return match.group(1)?.trim();
    final natural = RegExp(
      r"\bwhat(?:\s+is|'s)?\s+(?:the\s+)?(?:local\s+)?time\s+(?:in|at)\s+(.+?)(?:[?.!,;]|$)",
      caseSensitive: false,
    ).firstMatch(text.trim());
    return natural?.group(1)?.trim();
  }

'''
path.write_text(text[:start_at] + method + text[end_at:], encoding='utf-8')
print('Normalized generated natural-time regex method.')
