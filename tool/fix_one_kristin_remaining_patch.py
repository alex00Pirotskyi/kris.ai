#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]

# Normalize the generated natural-time regex method after the larger patch.
actions_path = root / 'lib/product/chat_control_plane_studio_actions.dart'
text = actions_path.read_text(encoding='utf-8')
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
actions_path.write_text(text[:start_at] + method + text[end_at:], encoding='utf-8')

# ProductException is defined in storage_security.dart. Because actions is a
# `part` file, the import belongs on the parent library, not in the part.
studio_path = root / 'lib/product/chat_control_plane_studio.dart'
studio = studio_path.read_text(encoding='utf-8')
storage_import = "import 'storage_security.dart';\n"
if storage_import not in studio:
    marker = "import 'run_live_signals.dart';\n"
    if studio.count(marker) != 1:
        raise SystemExit('chat studio storage import marker is not unique')
    studio = studio.replace(marker, marker + storage_import, 1)
studio_path.write_text(studio, encoding='utf-8')

# The coordinator only needs the classifier through task_specification_patch.dart,
# which already defines the interface. Keep the export, remove the redundant
# direct import so fatal-warnings stays clean.
semantic_path = root / 'lib/product/task_kernel/semantic_steering.dart'
semantic = semantic_path.read_text(encoding='utf-8')
unused_import = "import 'task_specification_patch_classifier.dart';\n"
if unused_import in semantic:
    semantic = semantic.replace(unused_import, '', 1)
semantic_path.write_text(semantic, encoding='utf-8')

print('Normalized time regex and cleared focused analyzer findings.')
