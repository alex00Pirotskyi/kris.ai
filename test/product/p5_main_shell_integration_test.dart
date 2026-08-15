import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/ui.dart';

void main() {
  testWidgets('main shell exposes chat, experience, and Owner Mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ownerMode = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad state: merged_p1a_service_unavailable',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KristinMainShell(
          ownerMode: ownerMode,
          chat: const Center(child: Text('Chat surface')),
        ),
      ),
    );

    expect(find.text('Chat surface'), findsOneWidget);
    await tester.tap(find.text('Experience'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-title')), findsOneWidget);

    await tester.tap(find.text('Owner Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Owner Mode is unavailable'), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
  });
}
