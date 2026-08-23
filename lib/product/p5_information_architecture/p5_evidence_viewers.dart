part of 'p5_prototype.dart';

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
      children: content.split('\n').map((line) {
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
