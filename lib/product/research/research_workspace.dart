import 'dart:convert';

import 'package:flutter/material.dart';

import 'research_runtime.dart';

enum P4ResearchView {
  search,
  results,
  source,
  extraction,
  citations,
  crawl,
  collections,
  changes,
  export,
}

final class P4ResearchWorkspaceController extends ChangeNotifier {
  final List<P4FetchVersion> _sources = <P4FetchVersion>[];
  final List<P4CitationSpan> _citations = <P4CitationSpan>[];
  final List<P4ChangeRecord> _changes = <P4ChangeRecord>[];
  String _query = '';
  String _status = 'Ready';
  String? _selectedFetchId;

  List<P4FetchVersion> get sources =>
      List<P4FetchVersion>.unmodifiable(_sources);
  List<P4CitationSpan> get citations =>
      List<P4CitationSpan>.unmodifiable(_citations);
  List<P4ChangeRecord> get changes =>
      List<P4ChangeRecord>.unmodifiable(_changes);
  String get query => _query;
  String get status => _status;
  String? get selectedFetchId => _selectedFetchId;

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void replaceSources(Iterable<P4FetchVersion> values) {
    _sources
      ..clear()
      ..addAll(values);
    if (_selectedFetchId != null &&
        !_sources.any((item) => item.id == _selectedFetchId)) {
      _selectedFetchId = null;
    }
    notifyListeners();
  }

  void replaceCitations(Iterable<P4CitationSpan> values) {
    _citations
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void replaceChanges(Iterable<P4ChangeRecord> values) {
    _changes
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void selectSource(String? id) {
    _selectedFetchId = id;
    notifyListeners();
  }

  void setStatus(String value) {
    _status = value.trim().isEmpty ? 'Ready' : value.trim();
    notifyListeners();
  }
}

final class P4ResearchWorkspace extends StatelessWidget {
  const P4ResearchWorkspace({
    super.key,
    required this.controller,
    this.onSearch,
    this.onCrawl,
    this.onExport,
  });

  final P4ResearchWorkspaceController controller;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onCrawl;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => DefaultTabController(
        length: P4ResearchView.values.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ResearchToolbar(
              controller: controller,
              onSearch: onSearch,
              onCrawl: onCrawl,
              onExport: onExport,
            ),
            const TabBar(
              isScrollable: true,
              tabs: <Widget>[
                Tab(text: 'Search'),
                Tab(text: 'Results'),
                Tab(text: 'Source'),
                Tab(text: 'Extraction'),
                Tab(text: 'Citations'),
                Tab(text: 'Crawl jobs'),
                Tab(text: 'Collections'),
                Tab(text: 'Changes'),
                Tab(text: 'Export'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _ResearchSearchPanel(
                    controller: controller,
                    onSearch: onSearch,
                  ),
                  _ResearchResults(controller: controller),
                  _ResearchSource(controller: controller),
                  _ResearchExtraction(controller: controller),
                  _ResearchCitations(controller: controller),
                  _ResearchCrawl(controller: controller, onCrawl: onCrawl),
                  _ResearchCollections(controller: controller),
                  _ResearchChanges(controller: controller),
                  _ResearchExport(controller: controller, onExport: onExport),
                ],
              ),
            ),
            Semantics(
              liveRegion: true,
              label: 'Research activity status',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(controller.status),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResearchToolbar extends StatelessWidget {
  const _ResearchToolbar({
    required this.controller,
    required this.onSearch,
    required this.onCrawl,
    required this.onExport,
  });
  final P4ResearchWorkspaceController controller;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onCrawl;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          onPressed: controller.query.trim().isEmpty
              ? null
              : () => onSearch?.call(controller.query),
          icon: const Icon(Icons.search),
          label: const Text('Search'),
        ),
        OutlinedButton.icon(
          onPressed: onCrawl,
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Crawl'),
        ),
        OutlinedButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export'),
        ),
        Chip(label: Text('${controller.sources.length} immutable sources')),
        Chip(label: Text('${controller.citations.length} citations')),
      ],
    ),
  );
}

final class _ResearchSearchPanel extends StatelessWidget {
  const _ResearchSearchPanel({
    required this.controller,
    required this.onSearch,
  });
  final P4ResearchWorkspaceController controller;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: TextFormField(
            key: const ValueKey<String>('p4-research-query'),
            initialValue: controller.query,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Research question',
              hintText:
                  'Describe the question, freshness, sources, and constraints.',
              border: OutlineInputBorder(),
            ),
            onChanged: controller.setQuery,
            onFieldSubmitted: (value) => onSearch?.call(value),
          ),
        ),
      ),
    );
  }
}

final class _ResearchResults extends StatelessWidget {
  const _ResearchResults({required this.controller});
  final P4ResearchWorkspaceController controller;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: controller.sources.length,
    itemBuilder: (context, index) {
      final source = controller.sources[index];
      final citationCount = controller.citations
          .where((item) => item.fetchVersionId == source.id)
          .length;
      return ListTile(
        selected: controller.selectedFetchId == source.id,
        leading: const Icon(Icons.article_outlined),
        title: Text(source.title),
        subtitle: Text(
          '${source.canonicalUrl}\n'
          '${source.fetchedAt.toLocal()} · ${source.trustLabel} · '
          '${source.extractionHash.substring(0, 12)} · $citationCount citations',
        ),
        isThreeLine: true,
        onTap: () => controller.selectSource(source.id),
      );
    },
  );
}

P4FetchVersion? _selected(P4ResearchWorkspaceController controller) {
  final id = controller.selectedFetchId;
  if (id == null) return controller.sources.firstOrNull;
  return controller.sources.where((item) => item.id == id).firstOrNull;
}

final class _ResearchSource extends StatelessWidget {
  const _ResearchSource({required this.controller});
  final P4ResearchWorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final source = _selected(controller);
    if (source == null) return const Center(child: Text('Select a source.'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        const JsonEncoder.withIndent('  ').convert(source.toJson()),
      ),
    );
  }
}

final class _ResearchExtraction extends StatelessWidget {
  const _ResearchExtraction({required this.controller});
  final P4ResearchWorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final source = _selected(controller);
    return Center(
      child: SelectableText(
        source == null
            ? 'Select a source.'
            : 'Immutable extraction ${source.extractionHash}\n'
                  'Object ${source.extractionObjectSha256}',
      ),
    );
  }
}

final class _ResearchCitations extends StatelessWidget {
  const _ResearchCitations({required this.controller});
  final P4ResearchWorkspaceController controller;
  @override
  Widget build(BuildContext context) => ListView(
    children: <Widget>[
      for (final citation in controller.citations)
        ListTile(
          leading: const Icon(Icons.format_quote),
          title: Text(citation.claim),
          subtitle: Text(
            '${citation.fetchVersionId} · ${citation.start}:${citation.end}\n'
            'quote ${citation.quoteHash.substring(0, 12)}',
          ),
          isThreeLine: true,
        ),
    ],
  );
}

final class _ResearchCrawl extends StatelessWidget {
  const _ResearchCrawl({required this.controller, required this.onCrawl});
  final P4ResearchWorkspaceController controller;
  final VoidCallback? onCrawl;
  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.tonalIcon(
      onPressed: onCrawl,
      icon: const Icon(Icons.play_arrow),
      label: const Text('Start bounded crawl'),
    ),
  );
}

final class _ResearchCollections extends StatelessWidget {
  const _ResearchCollections({required this.controller});
  final P4ResearchWorkspaceController controller;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      '${controller.sources.length} sources available for collections',
    ),
  );
}

final class _ResearchChanges extends StatelessWidget {
  const _ResearchChanges({required this.controller});
  final P4ResearchWorkspaceController controller;
  @override
  Widget build(BuildContext context) => ListView(
    children: <Widget>[
      for (final change in controller.changes)
        ListTile(
          leading: Icon(
            change.changed
                ? Icons.change_circle_outlined
                : Icons.check_circle_outline,
          ),
          title: Text(change.canonicalUrl),
          subtitle: Text(
            change.changed
                ? '${change.beforeHash?.substring(0, 12)} → ${change.afterHash.substring(0, 12)}'
                : 'No content change',
          ),
        ),
    ],
  );
}

final class _ResearchExport extends StatelessWidget {
  const _ResearchExport({required this.controller, required this.onExport});
  final P4ResearchWorkspaceController controller;
  final VoidCallback? onExport;
  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: controller.sources.isEmpty ? null : onExport,
      icon: const Icon(Icons.archive_outlined),
      label: const Text('Export provenance bundle'),
    ),
  );
}

final class P4DataWorkspaceController extends ChangeNotifier {
  final List<P4DatasetVersion> _versions = <P4DatasetVersion>[];
  String? _selectedVersionId;

  List<P4DatasetVersion> get versions =>
      List<P4DatasetVersion>.unmodifiable(_versions);
  String? get selectedVersionId => _selectedVersionId;
  P4DatasetVersion? get selected =>
      _versions.where((item) => item.id == _selectedVersionId).firstOrNull ??
      _versions.firstOrNull;

  void replaceVersions(Iterable<P4DatasetVersion> values) {
    _versions
      ..clear()
      ..addAll(values);
    if (_selectedVersionId != null &&
        !_versions.any((item) => item.id == _selectedVersionId)) {
      _selectedVersionId = null;
    }
    notifyListeners();
  }

  void select(String id) {
    _selectedVersionId = id;
    notifyListeners();
  }
}

final class P4DataWorkspace extends StatelessWidget {
  const P4DataWorkspace({super.key, required this.controller, this.onExport});
  final P4DataWorkspaceController controller;
  final ValueChanged<String>? onExport;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final selected = controller.selected;
      return DefaultTabController(
        length: 7,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: <Widget>[
                  for (final version in controller.versions)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                        label: Text(version.id.substring(0, 18)),
                        selected: selected?.id == version.id,
                        onSelected: (_) => controller.select(version.id),
                      ),
                    ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: <Widget>[
                Tab(text: 'Table'),
                Tab(text: 'Schema'),
                Tab(text: 'Recipe'),
                Tab(text: 'Quality'),
                Tab(text: 'Provenance'),
                Tab(text: 'Version diff'),
                Tab(text: 'Export'),
              ],
            ),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('No dataset selected.'))
                  : TabBarView(
                      children: <Widget>[
                        _VirtualTable(version: selected),
                        _JsonValue(value: selected.schema),
                        _JsonValue(
                          value: selected.transforms
                              .map((e) => e.toJson())
                              .toList(),
                        ),
                        _QualityPanel(version: selected),
                        _JsonValue(
                          value: <String, Object?>{
                            'sourceHashes': selected.sourceHashes,
                            'manifestHash': selected.manifestHash,
                          },
                        ),
                        _JsonValue(
                          value: <String, Object?>{
                            'parentVersionId': selected.parentVersionId,
                            'versionId': selected.id,
                          },
                        ),
                        _DatasetExport(version: selected, onExport: onExport),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

final class _VirtualTable extends StatelessWidget {
  const _VirtualTable({required this.version});
  final P4DatasetVersion version;
  @override
  Widget build(BuildContext context) {
    final fields = version.schema.keys.toList();
    return Scrollbar(
      child: ListView.builder(
        itemCount: version.rows.length + 1,
        itemExtent: 44,
        itemBuilder: (context, index) {
          final values = index == 0
              ? fields
              : fields
                    .map(
                      (field) =>
                          version.rows[index - 1][field]?.toString() ?? '',
                    )
                    .toList();
          return Row(
            children: <Widget>[
              for (final value in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: index == 0
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _JsonValue extends StatelessWidget {
  const _JsonValue({required this.value});
  final Object value;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(12),
    child: SelectableText(const JsonEncoder.withIndent('  ').convert(value)),
  );
}

final class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.version});
  final P4DatasetVersion version;
  @override
  Widget build(BuildContext context) {
    final missing = <String, int>{
      for (final field in version.schema.keys) field: 0,
    };
    for (final row in version.rows) {
      for (final field in version.schema.keys) {
        if (row[field] == null || row[field].toString().trim().isEmpty) {
          missing[field] = missing[field]! + 1;
        }
      }
    }
    return ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Rows'),
          trailing: Text('${version.rows.length}'),
        ),
        for (final entry in missing.entries)
          ListTile(
            title: Text(entry.key),
            trailing: Text('${entry.value} missing'),
          ),
      ],
    );
  }
}

final class _DatasetExport extends StatelessWidget {
  const _DatasetExport({required this.version, required this.onExport});
  final P4DatasetVersion version;
  final ValueChanged<String>? onExport;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      for (final format in const <String>['jsonl', 'csv', 'markdown', 'sqlite'])
        ListTile(
          leading: const Icon(Icons.download),
          title: Text(format.toUpperCase()),
          subtitle: Text('Manifest ${version.manifestHash.substring(0, 12)}'),
          onTap: () => onExport?.call(format),
        ),
    ],
  );
}
