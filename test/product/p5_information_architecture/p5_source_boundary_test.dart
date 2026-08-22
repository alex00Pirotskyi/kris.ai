import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Experience binds only through governed P2/P3 runtime adapters', () {
    final sources = <File>[
      ...Directory('lib/product/p5_information_architecture')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    const forbidden = <String>[
      "import 'dart:io'",
      "import 'dart:html'",
      'package:http/',
      'HttpClient',
      'Process.',
      'Socket(',
      'File(',
      'Directory(',
      "../product_runtime.dart",
      'P2OwnerWorkspace',
      'p2_owner_mode.dart',
      'workspace_tools.dart',
      'api_server.dart',
    ];

    for (final source in sources) {
      final text = source.readAsStringSync();
      for (final token in forbidden) {
        expect(
          text.contains(token),
          isFalse,
          reason: '${source.path} contains forbidden prototype token $token',
        );
      }
    }

    final prototype = File(
      'lib/product/p5_information_architecture/p5_prototype.dart',
    ).readAsStringSync();
    final support = File(
      'lib/product/p5_information_architecture/p5_support_workspaces.dart',
    ).readAsStringSync();
    expect(prototype, contains("../browser/browser_runtime.dart"));
    expect(prototype, contains("../p2_product_runtime_bootstrap.dart"));
    expect(prototype, isNot(contains("product_runtime.dart")));
    expect(prototype, contains('P3BrowserSessionProcess'));
    expect(support, contains('navigateLocalPage'));
    expect(support, contains('stageUpload'));
    expect(support, contains('downloadPage'));

    final productionMain = File('lib/main.dart').readAsStringSync();
    expect(productionMain.contains('p5_ia_preview.dart'), isFalse);
    expect(productionMain.contains('P5InformationArchitectureApp'), isFalse);
  });
}
