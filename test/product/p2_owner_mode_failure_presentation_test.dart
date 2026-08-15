import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';

void main() {
  test('missing merged P1A service returns a stable diagnostic', () async {
    final root = await Directory.systemTemp.createTemp('kristin-p1a-missing-');
    addTearDown(() => root.delete(recursive: true));

    final handle = await P2ProductRuntimeBootstrap.start(
      dataRoot: root,
      p1AuthorityService: null,
    );

    expect(handle.available, isFalse);
    expect(handle.failureCode, 'merged_p1a_service_unavailable');
    expect(
      handle.runtimeProvenance['failureCode'],
      'merged_p1a_service_unavailable',
    );
  });

  testWidgets('blocked Owner Mode explains recovery without raw Dart text',
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
