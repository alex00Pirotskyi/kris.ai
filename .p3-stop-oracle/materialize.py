from pathlib import Path

product = Path('lib/product/browser/web_preview.dart')
text = product.read_text()
old = """    final devPreview = _dev.remove(previewId);\n    if (devPreview == null) return;\n    devPreview.lifecycle = P3PreviewLifecycle.stopping;\n    try {\n      await processHost.stop(devPreview.process, limits.stopGrace);\n      devPreview.lifecycle = P3PreviewLifecycle.stopped;\n    } catch (_) {\n      devPreview.lifecycle = P3PreviewLifecycle.failed;\n      devPreview.failureCode = 'web_preview_stop_failed';\n      rethrow;\n    }"""
new = """    final devPreview = _dev[previewId];\n    if (devPreview == null) return;\n    devPreview.lifecycle = P3PreviewLifecycle.stopping;\n    try {\n      await processHost.stop(devPreview.process, limits.stopGrace);\n      devPreview.lifecycle = P3PreviewLifecycle.stopped;\n      _dev.remove(previewId);\n    } catch (_) {\n      devPreview.lifecycle = P3PreviewLifecycle.failed;\n      devPreview.failureCode = 'web_preview_stop_failed';\n      rethrow;\n    }"""
if old not in text:
    raise SystemExit('preview stop anchor missing')
product.write_text(text.replace(old, new, 1))

test = Path('test/product/browser/web_preview_test.dart')
t = test.read_text()
main_end = '\n}\n\nFuture<void> _serveReadiness'
if main_end not in t:
    raise SystemExit('test main anchor missing')
case = r'''

  test('failed dev-server stop remains observable and retryable', () async {
    final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    processHost
      ..fixtureServer = fixture
      ..ready = true;
    unawaited(_serveReadiness(fixture, processHost));

    final preview = await service.startDevServer(
      P3DevServerConfig(
        command: 'fixture-dev',
        cwd: '.',
        url: Uri.parse('http://127.0.0.1:${fixture.port}/'),
      ),
    );
    processHost.stopFailures = 1;

    await expectLater(service.stop(preview.id), throwsStateError);
    final failed = service.snapshot(preview.id);
    expect(failed.lifecycle, P3PreviewLifecycle.failed);
    expect(failed.failureCode, 'web_preview_stop_failed');

    await service.stop(preview.id);
    expect(processHost.stops, 2);
    expect(() => service.snapshot(preview.id), throwsStateError);
  });
'''
t = t.replace(main_end, case + main_end, 1)
field_anchor = "  HttpServer? fixtureServer;\n"
if field_anchor not in t:
    raise SystemExit('fixture field anchor missing')
t = t.replace(field_anchor, field_anchor + '  int stopFailures = 0;\n', 1)
stop_anchor = """    stops += 1;\n    lastGrace = grace;\n    final server = fixtureServer;"""
stop_new = """    stops += 1;\n    lastGrace = grace;\n    if (stopFailures > 0) {\n      stopFailures -= 1;\n      throw StateError('fixture_stop_failed');\n    }\n    final server = fixtureServer;"""
if stop_anchor not in t:
    raise SystemExit('fixture stop anchor missing')
t = t.replace(stop_anchor, stop_new, 1)
test.write_text(t)
