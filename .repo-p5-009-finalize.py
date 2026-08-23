from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


def replace_span(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{path}: start marker missing')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{path}: end marker missing')
    target.write_text(text[:start] + replacement + text[end:], encoding='utf-8', newline='\n')


models_path = 'lib/product/p5_information_architecture/p5_models.dart'
replace_once(
    models_path,
    """class P5TimelineEvent {
  const P5TimelineEvent({
    required this.runId,
    required this.sequence,
    required this.category,
    required this.timestampLabel,
    required this.title,
    required this.detail,
  });

  final String runId;
  final int sequence;
  final P5TimelineCategory category;
  final String timestampLabel;
  final String title;
  final String detail;
}

extension P5ComposerProfileLabel on P5ComposerProfile {
""",
    """class P5TimelineEvent {
  const P5TimelineEvent({
    required this.runId,
    required this.sequence,
    required this.category,
    required this.timestampLabel,
    required this.title,
    required this.detail,
  });

  final String runId;
  final int sequence;
  final P5TimelineCategory category;
  final String timestampLabel;
  final String title;
  final String detail;
}

enum P5EvidenceViewKind {
  text,
  binaryMetadata,
  image,
  markdown,
  json,
  table,
  diff,
  citation,
  receipt,
}

extension P5EvidenceViewKindLabel on P5EvidenceViewKind {
  String get label => switch (this) {
        P5EvidenceViewKind.text => 'Text',
        P5EvidenceViewKind.binaryMetadata => 'Binary metadata',
        P5EvidenceViewKind.image => 'Image',
        P5EvidenceViewKind.markdown => 'Markdown',
        P5EvidenceViewKind.json => 'JSON',
        P5EvidenceViewKind.table => 'Table',
        P5EvidenceViewKind.diff => 'Diff',
        P5EvidenceViewKind.citation => 'Citation',
        P5EvidenceViewKind.receipt => 'Receipt',
      };
}

@immutable
class P5EvidenceArtifactFixture {
  const P5EvidenceArtifactFixture({
    required this.id,
    required this.runId,
    required this.kind,
    required this.title,
    required this.mediaType,
    required this.content,
    this.metadata = const <String, String>{},
  });

  final String id;
  final String runId;
  final P5EvidenceViewKind kind;
  final String title;
  final String mediaType;
  final String content;
  final Map<String, String> metadata;
}

extension P5ComposerProfileLabel on P5ComposerProfile {
""",
)

fixtures_path = 'lib/product/p5_information_architecture/p5_fixtures.dart'
replace_once(
    fixtures_path,
    """  static const List<P5VerificationFixture> verificationResults =
      <P5VerificationFixture>[
""",
    """  static List<P5EvidenceArtifactFixture> evidenceArtifactsForRun(
    String runId,
  ) {
    if (!runs.any((run) => run.id == runId)) {
      return const <P5EvidenceArtifactFixture>[];
    }
    const fixtureOrigin = <String, String>{
      'origin': 'deterministic saved-run fixture',
      'authority': 'presentation only',
    };
    return <P5EvidenceArtifactFixture>[
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.text',
        runId: runId,
        kind: P5EvidenceViewKind.text,
        title: 'Planner notes',
        mediaType: 'text/plain',
        content:
            'Deterministic saved-run text fixture. No live file or evidence store is read.',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.binary-metadata',
        runId: runId,
        kind: P5EvidenceViewKind.binaryMetadata,
        title: 'Binary attachment metadata',
        mediaType: 'application/octet-stream',
        content:
            'Binary payload is intentionally not embedded in this presentation fixture.',
        metadata: <String, String>{
          ...fixtureOrigin,
          'size': '4096 bytes (fixture)',
          'content': 'metadata only',
        },
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.image',
        runId: runId,
        kind: P5EvidenceViewKind.image,
        title: 'Screenshot fixture',
        mediaType: 'image/png',
        content:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.markdown',
        runId: runId,
        kind: P5EvidenceViewKind.markdown,
        title: 'Markdown summary',
        mediaType: 'text/markdown',
        content:
            '# Saved run evidence\\n\\n- deterministic fixture\\n- no live side effect\\n- no production claim',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.json',
        runId: runId,
        kind: P5EvidenceViewKind.json,
        title: 'Structured result',
        mediaType: 'application/json',
        content:
            '{"runId":"$runId","fixture":true,"state":"NOT_PRODUCTION_EVIDENCE"}',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.table',
        runId: runId,
        kind: P5EvidenceViewKind.table,
        title: 'Verification table',
        mediaType: 'application/vnd.kristin.table+json',
        content:
            '[["Check","State"],["Navigation","PASS"],["Certification","NOT_EVALUATED"]]',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.diff',
        runId: runId,
        kind: P5EvidenceViewKind.diff,
        title: 'Fixture diff',
        mediaType: 'text/x-diff',
        content:
            '@@ -1 +1 @@\\n-old fixture label\\n+new fixture label',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.citation',
        runId: runId,
        kind: P5EvidenceViewKind.citation,
        title: 'Citation fixture',
        mediaType: 'application/vnd.kristin.citation+json',
        content:
            '{"title":"Fixture source","locator":"fixture://source/p5-009","span":"deterministic citation span"}',
        metadata: fixtureOrigin,
      ),
      P5EvidenceArtifactFixture(
        id: '$runId.evidence.receipt',
        runId: runId,
        kind: P5EvidenceViewKind.receipt,
        title: 'Effect receipt fixture',
        mediaType: 'application/vnd.kristin.receipt+json',
        content:
            '{"runId":"$runId","effectId":"fixture-effect-001","status":"SIMULATED","authority":"none"}',
        metadata: fixtureOrigin,
      ),
    ];
  }

  static const List<P5VerificationFixture> verificationResults =
      <P5VerificationFixture>[
""",
)

prototype_path = 'lib/product/p5_information_architecture/p5_prototype.dart'
replace_once(
    prototype_path,
    """part 'p5_verification_workspaces.dart';
part 'p5_support_workspaces.dart';
""",
    """part 'p5_verification_workspaces.dart';
part 'p5_evidence_viewers.dart';
part 'p5_support_workspaces.dart';
""",
)

verification_path = 'lib/product/p5_information_architecture/p5_verification_workspaces.dart'
replace_span(
    verification_path,
    "  Widget _evidenceWorkspace(BuildContext context) {",
    "  Widget _ownerModeWorkspace(BuildContext context) {",
    """  Widget _evidenceWorkspace(BuildContext context) {
    final state = controller.state;
    final selectedSavedRun = P5PrototypeFixtures.runs
        .where((run) => run.id == state.selectedRunId)
        .firstOrNull;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Evidence',
          subtitle:
              'Reopen deterministic saved-run artifacts without changing runtime authority.',
          icon: Icons.receipt_long_outlined,
        ),
        if (selectedSavedRun == null)
          _RecoveryCard(
            key: const Key('evidence-saved-run-required'),
            state: 'EMPTY',
            title: 'Select a saved run',
            message:
                'Artifact viewers open only from deterministic saved-run evidence. Current in-memory runs do not fabricate saved evidence.',
            actionLabel: 'Open saved runs',
            onAction: () =>
                controller.selectWorkspace(P5WorkspaceId.runsActivity),
          )
        else
          _P5EvidenceBrowser(
            key: ValueKey<String>('p5-evidence-browser-${selectedSavedRun.id}'),
            run: selectedSavedRun,
            artifacts:
                P5PrototypeFixtures.evidenceArtifactsForRun(selectedSavedRun.id),
          ),
        const _BoundaryNotice(
          message:
              'All viewer content is deterministic prototype data. No live file, network, evidence-store, or certification claim is implied.',
        ),
      ],
    );
  }

""",
)

viewer_path = Path('lib/product/p5_information_architecture/p5_evidence_viewers.dart')
if viewer_path.exists():
    raise SystemExit(f'{viewer_path}: already exists')
viewer_path.write_text(
    """part of 'p5_prototype.dart';

class _P5EvidenceBrowser extends StatefulWidget {
  const _P5EvidenceBrowser({
    super.key,
    required this.run,
    required this.artifacts,
  });

  final P5RunFixture run;
  final List<P5EvidenceArtifactFixture> artifacts;

  @override
  State<_P5EvidenceBrowser> createState() => _P5EvidenceBrowserState();
}

class _P5EvidenceBrowserState extends State<_P5EvidenceBrowser> {
  String? _selectedArtifactId;

  @override
  void didUpdateWidget(covariant _P5EvidenceBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.id != widget.run.id) {
      _selectedArtifactId = null;
    }
  }

  P5EvidenceArtifactFixture? get _selectedArtifact {
    final selectedId = _selectedArtifactId;
    if (selectedId == null) {
      return null;
    }
    return widget.artifacts
        .where((artifact) => artifact.id == selectedId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('p5-evidence-artifact-browser'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.run.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.run.updatedAtLabel} • ${widget.artifacts.length} supported viewer types',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final list = _artifactList();
                final viewer = _viewerPane(context);
                if (constraints.maxWidth >= 720) {
                  return SizedBox(
                    height: 480,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(width: 285, child: list),
                        const VerticalDivider(width: 24),
                        Expanded(child: viewer),
                      ],
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    SizedBox(height: 260, child: list),
                    const Divider(height: 24),
                    SizedBox(height: 360, child: viewer),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _artifactList() {
    return ListView.builder(
      key: const Key('p5-evidence-artifact-list'),
      itemCount: widget.artifacts.length,
      itemBuilder: (context, index) {
        final artifact = widget.artifacts[index];
        final selected = artifact.id == _selectedArtifactId;
        return ListTile(
          key: Key('p5-evidence-artifact-${artifact.kind.name}'),
          selected: selected,
          leading: Icon(_evidenceKindIcon(artifact.kind)),
          title: Text(artifact.kind.label),
          subtitle: Text(artifact.title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _selectedArtifactId = artifact.id),
        );
      },
    );
  }

  Widget _viewerPane(BuildContext context) {
    final artifact = _selectedArtifact;
    if (artifact == null) {
      return const Center(
        key: Key('p5-evidence-viewer-empty'),
        child: Text('Choose an artifact to open its deterministic viewer.'),
      );
    }
    return Card(
      key: Key('p5-evidence-viewer-${artifact.kind.name}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                artifact.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('${artifact.kind.label} • ${artifact.mediaType}'),
              const SizedBox(height: 8),
              for (final entry in artifact.metadata.entries)
                Text('${entry.key}: ${entry.value}'),
              const Divider(height: 24),
              _artifactBody(context, artifact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artifactBody(
    BuildContext context,
    P5EvidenceArtifactFixture artifact,
  ) {
    return switch (artifact.kind) {
      P5EvidenceViewKind.text => SelectableText(artifact.content),
      P5EvidenceViewKind.binaryMetadata => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _StatusChip(
              label: 'METADATA ONLY',
              icon: Icons.data_object_outlined,
            ),
            const SizedBox(height: 8),
            Text(artifact.content),
          ],
        ),
      P5EvidenceViewKind.image => Center(
          child: Column(
            children: <Widget>[
              Image.memory(
                base64Decode(artifact.content),
                key: const Key('p5-evidence-image-bytes'),
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, error, stackTrace) => const Text(
                  'Fixture image could not be decoded.',
                ),
              ),
              const SizedBox(height: 8),
              const Text('Deterministic 1×1 PNG fixture preview'),
            ],
          ),
        ),
      P5EvidenceViewKind.markdown => _markdownView(context, artifact.content),
      P5EvidenceViewKind.json => SelectableText(
          JsonEncoder.withIndent('  ').convert(jsonDecode(artifact.content)),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      P5EvidenceViewKind.table => _tableView(artifact.content),
      P5EvidenceViewKind.diff => SelectableText(
          artifact.content,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      P5EvidenceViewKind.citation => _citationView(artifact.content),
      P5EvidenceViewKind.receipt => _receiptView(artifact.content),
    };
  }

  Widget _markdownView(BuildContext context, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content.split('\\n').map((line) {
        if (line.startsWith('# ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.substring(2),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }
        if (line.startsWith('- ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${line.substring(2)}'),
          );
        }
        return Text(line);
      }).toList(growable: false),
    );
  }

  Widget _tableView(String content) {
    final decoded = (jsonDecode(content) as List<dynamic>)
        .map((row) => (row as List<dynamic>).map((cell) => '$cell').toList())
        .toList(growable: false);
    return Table(
      border: TableBorder.all(),
      children: <TableRow>[
        for (final row in decoded)
          TableRow(
            children: <Widget>[
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(cell),
                ),
            ],
          ),
      ],
    );
  }

  Widget _citationView(String content) {
    final citation = Map<String, dynamic>.from(jsonDecode(content) as Map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${citation['title']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        SelectableText('${citation['locator']}'),
        const SizedBox(height: 8),
        Text('Span: ${citation['span']}'),
        const SizedBox(height: 8),
        const _BoundaryNotice(
          message:
              'Citation locator is fixture provenance only; no external navigation occurs.',
        ),
      ],
    );
  }

  Widget _receiptView(String content) {
    final receipt = Map<String, dynamic>.from(jsonDecode(content) as Map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final entry in receipt.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${entry.key}: ${entry.value}'),
          ),
        const _BoundaryNotice(
          message:
              'SIMULATED receipt data is not a runtime effect or certification receipt.',
        ),
      ],
    );
  }

  IconData _evidenceKindIcon(P5EvidenceViewKind kind) {
    return switch (kind) {
      P5EvidenceViewKind.text => Icons.subject_outlined,
      P5EvidenceViewKind.binaryMetadata => Icons.data_object_outlined,
      P5EvidenceViewKind.image => Icons.image_outlined,
      P5EvidenceViewKind.markdown => Icons.article_outlined,
      P5EvidenceViewKind.json => Icons.code_outlined,
      P5EvidenceViewKind.table => Icons.table_chart_outlined,
      P5EvidenceViewKind.diff => Icons.difference_outlined,
      P5EvidenceViewKind.citation => Icons.link_outlined,
      P5EvidenceViewKind.receipt => Icons.receipt_long_outlined,
    };
  }
}
""",
    encoding='utf-8',
    newline='\n',
)

test_path = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')
if test_path.exists():
    raise SystemExit(f'{test_path}: already exists')
test_path.write_text(
    """import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_fixtures.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: P5InformationArchitecturePrototype(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('P5-009 every saved run exposes all nine deterministic viewer kinds', () {
    expect(P5EvidenceViewKind.values.length, 9);
    for (final run in P5PrototypeFixtures.runs) {
      final artifacts = P5PrototypeFixtures.evidenceArtifactsForRun(run.id);
      expect(artifacts.length, P5EvidenceViewKind.values.length);
      expect(
        artifacts.map((artifact) => artifact.kind).toSet(),
        P5EvidenceViewKind.values.toSet(),
      );
      expect(artifacts.every((artifact) => artifact.runId == run.id), isTrue);
    }
    expect(
      P5PrototypeFixtures.evidenceArtifactsForRun(
        'run.p5-simulated-current',
      ),
      isEmpty,
    );
  });

  testWidgets('P5-009 all supported evidence viewers reopen from a saved run',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(
      find.byKey(const Key('p5-evidence-artifact-browser')),
      findsOneWidget,
    );

    for (final kind in P5EvidenceViewKind.values) {
      await _tapKey(tester, Key('p5-evidence-artifact-${kind.name}'));
      expect(
        find.byKey(Key('p5-evidence-viewer-${kind.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('P5-009 saved-run provenance survives workspace reopen',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-existing-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(find.text('Review navigation accessibility'), findsOneWidget);
    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));
    expect(find.textContaining('run.p5-existing-001'), findsWidgets);

    controller.selectWorkspace(P5WorkspaceId.runsActivity);
    await tester.pumpAndSettle();
    await _tapKey(tester, const Key('existing-run-evidence-button'));
    expect(find.text('Review navigation accessibility'), findsOneWidget);
    expect(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      findsOneWidget,
    );
  });

  testWidgets('P5-009 current in-memory run never fabricates saved artifacts',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..apply(P5PrototypeAction.reviewPlan)
      ..apply(P5PrototypeAction.startRun)
      ..apply(P5PrototypeAction.completeRun)
      ..selectWorkspace(P5WorkspaceId.evidence);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(
      find.byKey(const Key('evidence-saved-run-required')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('p5-evidence-artifact-browser')),
      findsNothing,
    );
    expect(
      find.textContaining('do not fabricate saved evidence'),
      findsOneWidget,
    );
  });

  testWidgets('P5-009 binary view exposes metadata without raw payload',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.runsActivity)
      ..selectRun('run.p5-complete-001');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapKey(tester, const Key('existing-run-evidence-button'));
    await _tapKey(tester, const Key('p5-evidence-artifact-binaryMetadata'));

    expect(find.text('METADATA ONLY'), findsOneWidget);
    expect(find.textContaining('metadata only'), findsWidgets);
    expect(
      find.textContaining('Binary payload is intentionally not embedded'),
      findsOneWidget,
    );
  });
}
""",
    encoding='utf-8',
    newline='\n',
)

print('P5_009_ARTIFACT_VIEWERS_PATCH_APPLIED')
