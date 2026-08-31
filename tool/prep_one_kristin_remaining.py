#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'lib/product/chat_control_plane_studio_actions.dart'
text = path.read_text(encoding='utf-8')

settings_old = '''        builder: (context) => AdvancedSettingsPage(
          runtime: runtime,
          api: widget.api,
          startupError: widget.startupError,
          initialProjectId: selectedProjectId,
          initialModelId: selectedModelId,
          initialSection: initialSection,
'''
settings_new = '''        builder: (context) => AdvancedSettingsPage(
          runtime: runtime,
          api: widget.api,
          startupError: widget.startupError,
          initialProjectId: conversationSession.selectedProjectId,
          initialModelId: conversationSession.selectedModelId,
          initialSection: initialSection,
'''
if text.count(settings_old) != 1:
    raise SystemExit(f'AdvancedSettings marker count={text.count(settings_old)}')
text = text.replace(settings_old, settings_new, 1)

help_marker = '''    if (id == 'system.help') {
'''
time_handler = '''    if (id == 'utility.time') {
      await _runUtilityTime(decision);
      return;
    }
'''
if time_handler not in text:
    if text.count(help_marker) != 1:
        raise SystemExit(f'help handler marker count={text.count(help_marker)}')
    text = text.replace(help_marker, time_handler + help_marker, 1)

path.write_text(text, encoding='utf-8')
print('Prepared unique Advanced marker and deterministic utility.time handler.')
