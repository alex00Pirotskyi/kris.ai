import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_command_palette.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';

class _PaletteBinding extends P5GlobalAutonomyBinding {
  @override
  P5GlobalAutonomySnapshot get snapshot => P5GlobalAutonomySnapshot.initial();

  @override
  Future<void> emergencyKill() async {}

  @override
  Future<void> pauseActiveRuns() async {}

  @override
  void registerBrowserEmergencyStop(Future<void> Function()? stop) {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> stopActiveRuns() async {}

  @override
  void updateBrowserSessionCount(int count) {}
}

void main() {
  test('P5-010 catalog is searchable and shortcut-conflict free', () {
    P5CommandCatalog.validate(P5CommandCatalog.primary);
    expect(P5CommandCatalog.search('owner mode').first.id, 'shell.owner');
    expect(P5CommandCatalog.search('saved runs').first.id, 'experience.runs');
    expect(P5CommandCatalog.search('receipt').first.id, 'experience.evidence');
    expect(P5CommandCatalog.search('Ctrl/Cmd+Enter').single.id,
        'experience.launch-task');
    expect(P5CommandCatalog.search('no-such-command'), isEmpty);
  });

  test('P5-010 rejects duplicate command ids and shortcut signatures', () {
    const duplicateShortcut = <P5CommandDefinition>[
      P5CommandDefinition(
        id: 'one',
        label: 'One',
        description: 'One',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 0,
        shortcutSignature: 'primary+1',
      ),
      P5CommandDefinition(
        id: 'two',
        label: 'Two',
        description: 'Two',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 1,
        shortcutSignature: 'primary+1',
      ),
    ];
    expect(
      () => P5CommandCatalog.validate(duplicateShortcut),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'p5_command_shortcut_conflict:primary+1',
        ),
      ),
    );

    const duplicateId = <P5CommandDefinition>[
      P5CommandDefinition(
        id: 'same',
        label: 'One',
        description: 'One',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 0,
      ),
      P5CommandDefinition(
        id: 'same',
        label: 'Two',
        description: 'Two',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 1,
      ),
    ];
    expect(
      () => P5CommandCatalog.validate(duplicateId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'p5_command_id_conflict:same',
        ),
      ),
    );
  });

  testWidgets('P5-010 palette search launches first result with Enter',
      (tester) async {
    P5CommandDefinition? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5CommandPaletteDialog(
            commands: P5CommandCatalog.primary,
            onSelected: (command) => selected = command,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('p5-command-query')),
      'owner mode',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(selected?.id, 'shell.owner');
    expect(find.text('Ctrl/Cmd+3'), findsOneWidget);
  });

  testWidgets('P5-010 global shortcuts open palette and switch shell',
      (tester) async {
    var paletteOpenCount = 0;
    var selectedShell = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: P5CommandPaletteShortcutScope(
          onOpenPalette: () => paletteOpenCount++,
          onSelectShellDestination: (index) => selectedShell = index,
          child: const Focus(
            autofocus: true,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(paletteOpenCount, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedShell, 1);
  });

  testWidgets('P5-010 palette is discoverable without hiding autonomy controls',
      (tester) async {
    final binding = _PaletteBinding();
    addTearDown(binding.dispose);
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5GlobalAutonomyBar(
            binding: binding,
            onOpenCommands: () => opens++,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('p5-command-palette-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('p5-global-status-scroll')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-kill')), findsOneWidget);
    await tester.tap(find.byKey(const Key('p5-command-palette-button')));
    expect(opens, 1);
  });
}
