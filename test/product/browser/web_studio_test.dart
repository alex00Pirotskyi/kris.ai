import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/web_studio.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/storage_security.dart'
    show ProductException;
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  late Directory root;
  late WorkspaceBoundary boundary;
  late _FixtureMutationWriter mutations;
  late P3WebStudioEditor editor;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('p3-web-studio-');
    await File('${root.path}/index.html').writeAsString(
      '<main>hello studio</main>\n',
      flush: true,
    );
    await Directory('${root.path}/src').create();
    await File('${root.path}/src/app.js').writeAsString(
      'const message = "hello studio";\n',
      flush: true,
    );
    await File('${root.path}/src/styles.css').writeAsString(
      'main { display: grid; }\n',
      flush: true,
    );
    await Directory('${root.path}/node_modules/pkg').create(recursive: true);
    await File('${root.path}/node_modules/pkg/ignored.js').writeAsString(
      'const secretNoise = "hello studio";\n',
      flush: true,
    );
    await File('${root.path}/binary.dat').writeAsBytes(<int>[0, 1, 2, 3]);

    boundary = await WorkspaceBoundary.open(root.path);
    mutations = _FixtureMutationWriter(boundary);
    editor = P3WebStudioEditor(
      boundary: boundary,
      mutations: mutations,
      formatter: const _FixtureFormatter(),
      diagnostics: const _FixtureDiagnostics(),
      sourceControl: const _FixtureSourceControl(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('file tree is bounded to project and skips generated dependency trees',
      () async {
    final tree = await editor.fileTree();
    final paths = tree.map((item) => item.path).toSet();

    expect(paths, containsAll(<String>['index.html', 'src', 'src/app.js']));
    expect(paths.any((path) => path.contains('node_modules')), isFalse);
    expect(
      tree.singleWhere((item) => item.path == 'src/app.js').language,
      P3WebStudioLanguage.javascript,
    );
  });

  test('open, diff and save preserve optimistic concurrency', () async {
    final opened = await editor.open('index.html');
    expect(opened.language, P3WebStudioLanguage.html);
    expect(opened.sha256, Sha256.text(opened.content));

    final changed = '<main>updated studio</main>\n';
    final diff = editor.diff(opened, changed);
    expect(diff.changed, isTrue);
    expect(diff.hunks, hasLength(1));
    expect(diff.hunks.single.removed, <String>['<main>hello studio</main>']);
    expect(diff.hunks.single.added, <String>['<main>updated studio</main>']);

    final saved = await editor.save(opened, changed);
    expect(saved.content, changed);
    expect(saved.sha256, Sha256.text(changed));
    expect(await File('${root.path}/index.html').readAsString(), changed);

    await File('${root.path}/index.html').writeAsString('external change\n');
    await expectLater(
      editor.save(opened, 'stale overwrite\n'),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'stale_content',
        ),
      ),
    );
  });

  test('new HTML CSS and JavaScript files save through mutation boundary',
      () async {
    final documents = <P3WebStudioDocument>[
      editor.newDocument('new/page.html'),
      editor.newDocument('new/theme.css'),
      editor.newDocument('new/client.js'),
    ];
    final content = <String>[
      '<p>new</p>\n',
      'p { color: red; }\n',
      'boot();\n'
    ];

    for (var index = 0; index < documents.length; index += 1) {
      final saved = await editor.save(documents[index], content[index]);
      expect(saved.content, content[index]);
      expect(saved.exists, isTrue);
    }

    expect(
      documents.map((item) => item.language),
      <P3WebStudioLanguage>[
        P3WebStudioLanguage.html,
        P3WebStudioLanguage.css,
        P3WebStudioLanguage.javascript,
      ],
    );
  });

  test('search is bounded, line-aware and excludes generated directories',
      () async {
    final result = await editor.search('hello studio');
    final paths = result.matches.map((item) => item.path).toSet();

    expect(paths, unorderedEquals(<String>['index.html', 'src/app.js']));
    expect(result.matches.every((item) => item.line == 1), isTrue);
    expect(paths.any((path) => path.contains('node_modules')), isFalse);
  });

  test('formatter diagnostics and source-control hooks are editor-facing',
      () async {
    final source = await editor.open('src/app.js');
    final formatted = await editor.format(source, 'const x=1;   ');
    final diagnostics = await editor.inspect(source);
    final sourceState = await editor.sourceState('src/app.js');

    expect(formatted, 'const x=1;\n');
    expect(diagnostics.single.severity, P3WebStudioDiagnosticSeverity.warning);
    expect(diagnostics.single.path, 'src/app.js');
    expect(sourceState.status, 'modified');
    expect(sourceState.diff, contains('src/app.js'));
  });

  test('binary and project-escape paths are rejected', () async {
    await expectLater(
      editor.open('binary.dat'),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'web_studio_binary_file_rejected',
        ),
      ),
    );
    await expectLater(
      editor.open('../outside.html'),
      throwsA(isA<ProductException>()),
    );
  });
}

final class _FixtureMutationWriter implements P3WebStudioMutationWriter {
  _FixtureMutationWriter(this.boundary);

  final WorkspaceBoundary boundary;

  @override
  Future<P3WebStudioSaveResult> write({
    required String path,
    required String content,
    required String expectedHash,
    required bool expectedExists,
  }) async {
    final file = await boundary.file(path, allowMissing: true);
    final exists = await file.exists();
    if (exists != expectedExists) {
      throw ProductException('stale_existence', 'fixture stale existence');
    }
    final beforeBytes = exists ? await file.readAsBytes() : <int>[];
    final beforeHash = exists ? Sha256.hex(beforeBytes) : '';
    if (expectedHash.isNotEmpty && expectedHash != beforeHash) {
      throw ProductException('stale_content', 'fixture stale content');
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(utf8.encode(content), flush: true);
    final afterHash = Sha256.text(content);
    return P3WebStudioSaveResult(
      path: path,
      beforeHash: beforeHash,
      afterHash: afterHash,
      operation: exists ? 'replace' : 'create',
    );
  }
}

final class _FixtureFormatter implements P3WebStudioFormatter {
  const _FixtureFormatter();

  @override
  Future<String> format({
    required String path,
    required P3WebStudioLanguage language,
    required String content,
  }) async =>
      '${content.trimRight()}\n';
}

final class _FixtureDiagnostics implements P3WebStudioDiagnosticsProvider {
  const _FixtureDiagnostics();

  @override
  Future<List<P3WebStudioDiagnostic>> inspect(
    P3WebStudioDocument document,
  ) async =>
      <P3WebStudioDiagnostic>[
        P3WebStudioDiagnostic(
          path: document.path,
          message: 'fixture warning',
          severity: P3WebStudioDiagnosticSeverity.warning,
          line: 1,
          column: 1,
          code: 'fixture',
        ),
      ];
}

final class _FixtureSourceControl implements P3WebStudioSourceControl {
  const _FixtureSourceControl();

  @override
  Future<P3WebStudioSourceState> inspect(String path) async =>
      P3WebStudioSourceState(
        path: path,
        status: 'modified',
        diff: 'diff -- $path',
      );
}
