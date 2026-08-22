from pathlib import Path

path = Path('lib/product/p5_global_autonomy.dart')
text = path.read_text(encoding='utf-8')
replacements = {
    "    if (_disposed || _refreshing) return;\n": "    if (_disposed || _refreshing) {\n      return;\n    }\n",
    "      if (_disposed) return;\n": "      if (_disposed) {\n        return;\n      }\n",
    "    if (failures > 0) throw StateError('global_pause_partial_failure:$failures');\n": "    if (failures > 0) {\n      throw StateError('global_pause_partial_failure:$failures');\n    }\n",
    "    if (failures > 0) throw StateError('global_stop_partial_failure:$failures');\n": "    if (failures > 0) {\n      throw StateError('global_stop_partial_failure:$failures');\n    }\n",
    "    if (!attempted) throw StateError('no_active_session_to_kill');\n": "    if (!attempted) {\n      throw StateError('no_active_session_to_kill');\n    }\n",
    "    if (_browserSessionCount == bounded) return;\n": "    if (_browserSessionCount == bounded) {\n      return;\n    }\n",
    "    if (events != null) unawaited(events.cancel());\n": "    if (events != null) {\n      unawaited(events.cancel());\n    }\n",
    "    if (_busy) return;\n": "    if (_busy) {\n      return;\n    }\n",
}
for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one analyzer anchor {old!r}, found {count}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')
print('P5_005_ANALYZER_FIX_APPLIED')
