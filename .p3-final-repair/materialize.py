from pathlib import Path

adr = Path('docs/adr/ADR-0005-browser-storage.md')
adr_text = adr.read_text(encoding='utf-8')
old_status = '**Status:** ACCEPTED  '
new_status = '**Status:** PROPOSED  '
if old_status not in adr_text:
    raise SystemExit('ADR-0005 accepted status anchor missing')
adr.write_text(adr_text.replace(old_status, new_status, 1), encoding='utf-8', newline='\n')

test_path = Path('test/product/browser/web_preview_test.dart')
test_text = test_path.read_text(encoding='utf-8')
old = '''    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    await lines
        .firstWhere((line) => line == 'retry: 500')
        .timeout(const Duration(seconds: 2));
    final firstReload = lines
        .firstWhere((line) => line.startsWith('data:'))
        .timeout(const Duration(seconds: 2));

    final changed = await service.sourceChanged(preview.id);
    expect(changed.revision, 1);
    expect(await firstReload, 'data: 1');
    client.close(force: true);
'''
new = '''    final lines = StreamIterator<String>(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );

    Future<String> nextLineWhere(bool Function(String line) matches) async {
      while (await lines.moveNext().timeout(const Duration(seconds: 10))) {
        if (matches(lines.current)) return lines.current;
      }
      throw StateError('live_reload_stream_closed');
    }

    try {
      expect(
        await nextLineWhere((line) => line == 'retry: 500'),
        'retry: 500',
      );
      final firstReload = nextLineWhere((line) => line.startsWith('data:'));

      final changed = await service.sourceChanged(preview.id);
      expect(changed.revision, 1);
      expect(await firstReload, 'data: 1');
    } finally {
      await lines.cancel();
      client.close(force: true);
    }
'''
if old not in test_text:
    raise SystemExit('P3 SSE test anchor missing')
test_path.write_text(test_text.replace(old, new, 1), encoding='utf-8', newline='\n')
