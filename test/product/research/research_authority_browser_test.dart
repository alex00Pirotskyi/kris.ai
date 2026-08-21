import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_runtime.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/research/research_authority.dart';
import 'package:kristin_local_agent/product/research/research_browser_adapter.dart';
import 'package:kristin_local_agent/product/research/research_runtime.dart';

void main() {
  test('research authority migrates, backs up, and detects corruption',
      () async {
    final root = await Directory.systemTemp.createTemp('p4-authority-');
    final backup = Directory('${root.path}-backup');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await backup.exists()) await backup.delete(recursive: true);
    });
    final store = P4JsonResearchAuthorityStore(root);
    await P4ResearchAuthorityMigrator.initial().migrate(store);
    expect(await store.schemaVersion(), p4ResearchAuthorityVersion);
    await store.put('web_sources', 'source-1', <String, Object?>{
      'canonicalUrl': 'https://example.com/source',
      'contentHash': 'a' * 64,
    });
    expect(
        (await store.get('web_sources', 'source-1'))?['entity'], 'web_sources');
    final receipt = await p4BackupAuthority(store, backup);
    expect(receipt.files, greaterThanOrEqualTo(2));
    expect(receipt.manifestSha256, matches(RegExp(r'^[0-9a-f]{64}$')));

    final record = File(
      '${root.path}${Platform.pathSeparator}web_sources'
      '${Platform.pathSeparator}source-1.json',
    );
    await record.writeAsString('{bad-json', flush: true);
    await expectLater(
        store.verifyIntegrity(), throwsA(isA<P4ResearchException>()));
  });

  test('rendered fetch distinguishes browser evidence and always closes page',
      () async {
    final backend = _RenderedBackend(_observation());
    final result = await P4RenderedResearchFetcher(backend).fetch(
      Uri.parse('https://example.com/rendered'),
    );
    expect(result.rendered, isTrue);
    expect(result.finalUrl.toString(), 'https://example.com/rendered');
    expect(result.dom, contains('<main>Rendered</main>'));
    expect(backend.closeCalls, 1);
  });

  test('dataset join and version diff preserve deterministic lineage', () {
    final join = P4DatasetJoiner.leftJoin(
      left: <Map<String, Object?>>[
        <String, Object?>{'id': '1', 'name': 'A'},
        <String, Object?>{'id': '2', 'name': 'B'},
      ],
      right: <Map<String, Object?>>[
        <String, Object?>{'key': '1', 'score': 9},
      ],
      leftKey: 'id',
      rightKey: 'key',
    );
    expect(join.matched, 1);
    expect(join.leftOnly, 1);
    expect(join.rows.first['right_score'], 9);

    final engine = P4DatasetEngine();
    final before = engine.create(
      datasetId: 'fixture',
      rows: <Map<String, Object?>>[
        <String, Object?>{'id': 1},
      ],
      schema: const <String, String>{'id': 'int'},
      sourceHashes: <String>['a' * 64],
      createdAt: DateTime.utc(2026, 8, 20),
    );
    final after = engine.create(
      datasetId: 'fixture',
      rows: <Map<String, Object?>>[
        <String, Object?>{'id': 1},
        <String, Object?>{'id': 2},
      ],
      schema: const <String, String>{'id': 'int'},
      sourceHashes: <String>['a' * 64],
      parent: before,
      createdAt: DateTime.utc(2026, 8, 21),
    );
    final diff = p4DiffDatasetVersions(before, after);
    expect(diff.addedRowHashes, hasLength(1));
    expect(diff.removedRowHashes, isEmpty);
    expect(diff.schemaChanged, isFalse);
  });
}

P3BrowserPageObservation _observation() {
  final screenshot = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==',
  );
  final observation = <String, Object?>{
    'schemaVersion': '1.0.0',
    'url': 'https://example.com/rendered',
    'title': 'Rendered fixture',
    'dom': <String, Object?>{
      'text': '<main>Rendered</main>',
      'bytes': 21,
      'truncated': false,
    },
    'visibleText': <String, Object?>{
      'text': 'Rendered',
      'bytes': 8,
      'truncated': false,
    },
    'accessibility': <String, Object?>{
      'text': 'main Rendered',
      'bytes': 13,
      'truncated': false,
    },
    'forms': const <Object?>[],
    'console': <String, Object?>{'entries': const <Object?>[]},
    'network': <String, Object?>{'entries': const <Object?>[]},
    'screenshot': <String, Object?>{
      'mediaType': 'image/jpeg',
      'bytes': screenshot.length,
      'sha256': Sha256.hex(screenshot),
      'base64': base64Encode(screenshot),
    },
  };
  return P3BrowserPageObservation.fromJson(<String, Object?>{
    'sessionId': 'render-session',
    'pageId': 'render-page',
    'observationHash': Sha256.text(canonicalJson(observation)),
    'observation': observation,
  });
}

final class _RenderedBackend implements P4RenderedBrowserBackend {
  _RenderedBackend(this.observation);
  final P3BrowserPageObservation observation;
  int closeCalls = 0;

  @override
  Future<P3BrowserPageObservation> render(Uri url) async => observation;

  @override
  Future<void> closeRenderedPage(P3BrowserPageObservation observation) async {
    closeCalls += 1;
  }
}
