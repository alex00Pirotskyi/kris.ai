import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prototype performs no runtime side effect or external network request',
      () {
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
      'ProductRuntime',
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

    final productionMain = File('lib/main.dart').readAsStringSync();
    expect(productionMain.contains('p5_ia_preview.dart'), isFalse);
    expect(productionMain.contains('P5InformationArchitectureApp'), isFalse);
  });
}
