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

# The earlier hand-carried timezone lock repair truncated http_parser's
# hosted package SHA. Restore the exact pub-generated checksum so `pub get`
# can validate the lock and then own any remaining dependency normalization.
lock_path = root / 'pubspec.lock'
lock = lock_path.read_text(encoding='utf-8')
bad = '178d74305e786601377d3d8726205dc5a4dd935297175b19a23a2e66571'
good = '178d74305e7866013777bab2c3d8726205dc5a4dd935297175b19a23a2e66571'
if bad in lock:
    lock = lock.replace(bad, good, 1)
elif good not in lock:
    raise SystemExit('http_parser 4.1.2 checksum was neither expected bad nor canonical value')
lock_path.write_text(lock, encoding='utf-8')

print('Prepared unique Advanced marker, utility.time handler, and canonical package checksum.')
