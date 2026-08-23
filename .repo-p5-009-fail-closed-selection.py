from pathlib import Path

CONTROLLER = Path('lib/product/p5_information_architecture/p5_controller.dart')
VIEWERS = Path('lib/product/p5_information_architecture/p5_verification_workspaces.dart')
TEST = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')

controller = CONTROLLER.read_text(encoding='utf-8')
old = '''    if (evidence == null) {
      _state = _state.copyWith(
        recoveryMessage:
            'Evidence "$evidenceId" is not part of saved run "$runId".',
      );
'''
new = '''    if (evidence == null) {
      _state = _state.copyWith(
        selectedEvidenceId: null,
        recoveryMessage:
            'Evidence "$evidenceId" is not part of saved run "$runId".',
      );
'''
if controller.count(old) != 1:
    raise SystemExit('controller evidence rejection contract drifted')
controller = controller.replace(old, new)
CONTROLLER.write_text(controller, encoding='utf-8', newline='\n')

viewers = VIEWERS.read_text(encoding='utf-8')
old = '''    final selected = savedRun == null
        ? null
        : evidence
                .where((item) => item.id == state.selectedEvidenceId)
                .firstOrNull ??
            evidence.firstOrNull;
'''
new = '''    final selected = savedRun == null || state.selectedEvidenceId == null
        ? null
        : evidence
            .where((item) => item.id == state.selectedEvidenceId)
            .firstOrNull;
'''
if viewers.count(old) != 1:
    raise SystemExit('viewer selection fallback contract drifted')
viewers = viewers.replace(old, new)
VIEWERS.write_text(viewers, encoding='utf-8', newline='\n')

test = TEST.read_text(encoding='utf-8')
old = '''    controller.selectRun('run.p5-complete-001');
    controller.selectEvidence('evidence.run.other.json');
    expect(controller.state.selectedEvidenceId, isNull);
    expect(
        controller.state.recoveryMessage, contains('is not part of saved run'));
'''
new = '''    controller.selectRun('run.p5-complete-001');
    final jsonEvidence = P5PrototypeFixtures.evidenceForRun(
      'run.p5-complete-001',
    ).singleWhere((item) => item.kind == P5EvidenceKind.json);
    controller.selectEvidence(jsonEvidence.id);
    expect(controller.state.selectedEvidenceId, jsonEvidence.id);

    controller.selectEvidence('evidence.run.other.json');
    expect(controller.state.selectedEvidenceId, isNull);
    expect(
        controller.state.recoveryMessage, contains('is not part of saved run'));
'''
if test.count(old) != 1:
    raise SystemExit('negative evidence selection test contract drifted')
test = test.replace(old, new)
old = '''    expect(find.byKey(const Key('saved-run-evidence-index')), findsOneWidget);
    for (final kind in P5EvidenceKind.values) {
'''
new = '''    expect(find.byKey(const Key('saved-run-evidence-index')), findsOneWidget);
    expect(
      find.byKey(const Key('evidence-viewer-textMetadata')),
      findsNothing,
    );
    expect(
      find.text(
        'Choose a supported saved-run evidence type to open its viewer.',
      ),
      findsOneWidget,
    );
    for (final kind in P5EvidenceKind.values) {
'''
if test.count(old) != 1:
    raise SystemExit('viewer initial selection test contract drifted')
test = test.replace(old, new)
TEST.write_text(test, encoding='utf-8', newline='\n')
