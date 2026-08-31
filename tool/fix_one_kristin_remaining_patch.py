#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'lib/product/chat_control_plane_studio_actions.dart'
text = path.read_text(encoding='utf-8')
old = """    final natural = RegExp(\n      r'\\\\bwhat(?:\\\\s+is|\\\\\\'s)?\\\\s+(?:the\\\\s+)?(?:local\\\\s+)?time\\\\s+(?:in|at)\\\\s+(.+?)(?:[?.!,;]|$)',\n      caseSensitive: false,\n    ).firstMatch(text.trim());\n"""
new = """    final natural = RegExp(\n      r\"\\bwhat(?:\\s+is|'s)?\\s+(?:the\\s+)?(?:local\\s+)?time\\s+(?:in|at)\\s+(.+?)(?:[?.!,;]|$)\",\n      caseSensitive: false,\n    ).firstMatch(text.trim());\n"""
if old not in text:
    raise SystemExit('quoted natural-time regex marker not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Fixed generated natural-time regex quoting.')
