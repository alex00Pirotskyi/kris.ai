import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';

void main() {
  test('raw build without bundled Owner runtime fails with stable diagnostic',
      () async {
    final root = await Directory.systemTemp.createTemp('kristin-owner-missing-');
    addTearDown(() => root.delete(recursive: true));

    final handle = await P2ProductRuntimeBootstrap.start(
      dataRoot: root,
      p1AuthorityService: null,
    );

    expect(handle.available, isFalse);
    expect(handle.failureCode, 'p2_application_runtime_bundle_missing');
    expect(
      handle.runtimeProvenance['failureCode'],
      'p2_application_runtime_bundle_missing',
    );
  });

  testWidgets('blocked secure P1A Owner Mode explains recovery without raw text',
      (tester) async {
    final handle = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad_state:_merged_p1a_service_unavailable',
    );
    await tester.pumpWidget(MaterialApp(home: handle.buildWorkspace()));

    expect(find.textContaining('install or start it'), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('Bad_state'), findsNothing);
  });
}
