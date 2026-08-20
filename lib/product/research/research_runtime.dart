import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../crypto_utils.dart';

final class P4ResearchException implements Exception {
  const P4ResearchException(this.code, [this.message = '']);
  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : '$code: $message';
}

final class P4StoredObject {
  const P4StoredObject({
    required this.sha256,
    required this.bytes,
    required this.mediaType,
    required this.path,
  });
  final String sha256;
  final int bytes;
  final String mediaType;
  final String path;
}

final class P4FetchVersion {
  const P4FetchVersion({
    required this.id,
    required this.url,
    required this.canonicalUrl,
    required this.fetchedAt,
    required this.rawObjectSha256,
    required this.extractionObjectSha256,
    required this.extractionHash,
    required this.title,
    required this.trustLabel,
    this.renderedObjectSha256,
    this.screenshotObjectSha256,
  });

  final String id;
  final String url;
  final String canonicalUrl;
  final DateTime fetchedAt;
  final String rawObjectSha256;
  final String? renderedObjectSha256;
  final String? screenshotObjectSha256;
  final String extractionObjectSha256;
  final String extractionHash;
  final String title;
  final String trustLabel;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '1.0.0',
        'id': id,
        'url': url,
        'canonicalUrl': canonicalUrl,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'rawObjectSha256': rawObjectSha256,
        'renderedObjectSha256': renderedObjectSha256,
        'screenshotObjectSha256': screenshotObjectSha256,
        'extractionObjectSha256': extractionObjectSha256,
        'extractionHash': extractionHash,
        'title': title,
        'trustLabel': trustLabel,
      };
}

final class P4CitationSpan {
  const P4CitationSpan({
    required this.id,
    required this.fetchVersionId,
    required this.extractionHash,
    required this.claim,
    required this.start,
    required this.end,
    required this.quoteHash,
  });

  final String id;
  final String fetchVersionId;
  final String extractionHash;
  final String claim;
  final int start;
  final int end;
  final String quoteHash;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '1.0.0',
        'id': id,
        'fetchVersionId': fetchVersionId,
        'extractionHash': extractionHash,
        'claim': claim,
        'start': start,
        'end': end,
        'quoteHash': quoteHash,
      };
}

final class P4ResearchContentStore {
  P4ResearchContentStore(this.root, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Directory root;
  final DateTime Function() _clock;

  Directory get _objects => Directory(
        '${root.path}${Platform.pathSeparator}objects',
      );
  Directory get _fetches => Directory(
        '${root.path}${Platform.pathSeparator}fetches',
      );
  Directory get _citations => Directory(
        '${root.path}${Platform.pathSeparator}citations',
      );

  Future<void> initialize() async {
    await _objects.create(recursive: true);
    await _fetches.create(recursive: true);
    await _citations.create(recursive: true);
  }

  String _objectPath(String sha) =>
      '${_objects.path}${Platform.pathSeparator}${sha.substring(0, 2)}'
      '${Platform.pathSeparator}$sha.bin';

  Future<P4StoredObject> putObject(
    List<int> bytes, {
    required String mediaType,
  }) async {
    if (bytes.isEmpty || bytes.length > 128 * 1024 * 1024) {
      throw const P4ResearchException('research_object_budget_invalid');
    }
    final sha = Sha256.hex(bytes);
    final file = File(_objectPath(sha));
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (existing.length != bytes.length || Sha256.hex(existing) != sha) {
        throw const P4ResearchException('research_object_collision');
      }
    } else {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    return P4StoredObject(
      sha256: sha,
      bytes: bytes.length,
      mediaType: mediaType,
      path: file.path,
    );
  }

  Future<List<int>> readObject(String sha256) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const P4ResearchException('research_object_hash_invalid');
    }
    final file = File(_objectPath(sha256));
    if (!await file.exists()) {
      throw const P4ResearchException('research_object_missing');
    }
    final bytes = await file.readAsBytes();
    if (Sha256.hex(bytes) != sha256) {
      throw const P4ResearchException('research_object_integrity_failed');
    }
    return bytes;
  }

  Future<P4FetchVersion> saveFetch({
    required String url,
    required String canonicalUrl,
    required List<int> rawBytes,
    required Map<String, Object?> extraction,
    required String title,
    required String trustLabel,
    List<int>? renderedBytes,
    List<int>? screenshotBytes,
  }) async {
    await initialize();
    final raw =
        await putObject(rawBytes, mediaType: 'application/octet-stream');
    final extractionBytes = utf8.encode(canonicalJson(extraction));
    final extracted = await putObject(
      extractionBytes,
      mediaType: 'application/json',
    );
    final rendered = renderedBytes == null
        ? null
        : await putObject(renderedBytes, mediaType: 'text/html');
    final screenshot = screenshotBytes == null
        ? null
        : await putObject(screenshotBytes, mediaType: 'image/jpeg');
    final fetchedAt = _clock().toUtc();
    final identity = canonicalJson(<String, Object?>{
      'canonicalUrl': canonicalUrl,
      'raw': raw.sha256,
      'extraction': extracted.sha256,
      'fetchedAt': fetchedAt.toIso8601String(),
    });
    final id = 'fetch_${Sha256.text(identity).substring(0, 32)}';
    final version = P4FetchVersion(
      id: id,
      url: url,
      canonicalUrl: canonicalUrl,
      fetchedAt: fetchedAt,
      rawObjectSha256: raw.sha256,
      renderedObjectSha256: rendered?.sha256,
      screenshotObjectSha256: screenshot?.sha256,
      extractionObjectSha256: extracted.sha256,
      extractionHash: Sha256.text(canonicalJson(extraction)),
      title: title,
      trustLabel: trustLabel,
    );
    await _writeCanonicalJson(
      File('${_fetches.path}${Platform.pathSeparator}$id.json'),
      version.toJson(),
    );
    return version;
  }

  Future<P4CitationSpan> createCitation({
    required P4FetchVersion fetch,
    required String extractedText,
    required String claim,
    required int start,
    required int end,
  }) async {
    if (start < 0 || end <= start || end > extractedText.length) {
      throw const P4ResearchException('citation_span_invalid');
    }
    final quote = extractedText.substring(start, end);
    final id = 'cite_${Sha256.text(canonicalJson(<String, Object?>{
          'fetch': fetch.id,
          'extractionHash': fetch.extractionHash,
          'start': start,
          'end': end,
          'claim': claim,
        })).substring(0, 32)}';
    final citation = P4CitationSpan(
      id: id,
      fetchVersionId: fetch.id,
      extractionHash: fetch.extractionHash,
      claim: claim,
      start: start,
      end: end,
      quoteHash: Sha256.text(quote),
    );
    await _writeCanonicalJson(
      File('${_citations.path}${Platform.pathSeparator}$id.json'),
      citation.toJson(),
    );
    return citation;
  }

  Future<List<P4FetchVersion>> listFetches() async {
    if (!await _fetches.exists()) return const <P4FetchVersion>[];
    final output = <P4FetchVersion>[];
    await for (final entity in _fetches.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final raw = jsonDecode(await entity.readAsString());
      if (raw is! Map) continue;
      final value = raw.map((key, item) => MapEntry(key.toString(), item));
      output.add(P4FetchVersion(
        id: value['id']!.toString(),
        url: value['url']!.toString(),
        canonicalUrl: value['canonicalUrl']!.toString(),
        fetchedAt: DateTime.parse(value['fetchedAt']!.toString()).toUtc(),
        rawObjectSha256: value['rawObjectSha256']!.toString(),
        renderedObjectSha256: value['renderedObjectSha256']?.toString(),
        screenshotObjectSha256: value['screenshotObjectSha256']?.toString(),
        extractionObjectSha256: value['extractionObjectSha256']!.toString(),
        extractionHash: value['extractionHash']!.toString(),
        title: value['title']!.toString(),
        trustLabel: value['trustLabel']!.toString(),
      ));
    }
    output.sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
    return List<P4FetchVersion>.unmodifiable(output);
  }
}

Future<void> _writeCanonicalJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString('${canonicalJson(value)}\n', flush: true);
  if (await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

final class P4LexicalDocument {
  const P4LexicalDocument({
    required this.id,
    required this.scope,
    required this.title,
    required this.text,
    required this.metadata,
  });
  final String id;
  final String scope;
  final String title;
  final String text;
  final Map<String, Object?> metadata;
}

final class P4LexicalHit {
  const P4LexicalHit(this.document, this.score);
  final P4LexicalDocument document;
  final double score;
}

abstract interface class P4SemanticIndex {
  Future<List<String>> searchIds(String query,
      {required String scope, int limit});
}

final class P4LexicalIndex {
  final Map<String, P4LexicalDocument> _documents =
      <String, P4LexicalDocument>{};
  P4SemanticIndex? semantic;

  void upsert(P4LexicalDocument document) {
    if (document.id.trim().isEmpty || document.scope.trim().isEmpty) {
      throw const P4ResearchException('research_index_document_invalid');
    }
    _documents[document.id] = document;
  }

  void remove(String id) => _documents.remove(id);

  void rebuild(Iterable<P4LexicalDocument> documents) {
    _documents.clear();
    for (final document in documents) {
      upsert(document);
    }
  }

  Future<List<P4LexicalHit>> search(
    String query, {
    required String scope,
    int limit = 20,
    bool semanticPreferred = false,
  }) async {
    final terms = RegExp(r'[A-Za-z0-9]{2,}')
        .allMatches(query.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    if (terms.isEmpty || limit < 1 || limit > 200) {
      throw const P4ResearchException('research_index_query_invalid');
    }
    final semanticIds = semanticPreferred && semantic != null
        ? await semantic!.searchIds(query, scope: scope, limit: limit)
        : const <String>[];
    final semanticRank = <String, int>{
      for (var index = 0; index < semanticIds.length; index++)
        semanticIds[index]: index,
    };
    final hits = <P4LexicalHit>[];
    for (final document in _documents.values) {
      if (document.scope != scope) continue;
      final haystack = '${document.title}\n${document.text}'.toLowerCase();
      var lexical = 0.0;
      for (final term in terms) {
        final titleCount = term.allMatches(document.title.toLowerCase()).length;
        final bodyCount = term.allMatches(haystack).length;
        lexical += titleCount * 3.0 + bodyCount.toDouble();
      }
      final semanticPosition = semanticRank[document.id];
      final semanticScore =
          semanticPosition == null ? 0.0 : 2.0 / (1.0 + semanticPosition);
      final score = lexical + semanticScore;
      if (score > 0) hits.add(P4LexicalHit(document, score));
    }
    hits.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.document.id.compareTo(b.document.id);
    });
    return List<P4LexicalHit>.unmodifiable(hits.take(limit));
  }
}

enum P4DatasetTransformKind {
  select,
  rename,
  cast,
  filterEquals,
  sort,
  dedupe,
  normalizeText,
  annotate,
  validateRequired,
}

final class P4DatasetTransform {
  const P4DatasetTransform(this.kind, this.arguments);
  final P4DatasetTransformKind kind;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'arguments': arguments,
      };
}

final class P4DatasetVersion {
  const P4DatasetVersion({
    required this.id,
    required this.datasetId,
    required this.createdAt,
    required this.schema,
    required this.rows,
    required this.sourceHashes,
    required this.transforms,
    required this.manifestHash,
    this.parentVersionId,
  });

  final String id;
  final String datasetId;
  final String? parentVersionId;
  final DateTime createdAt;
  final Map<String, String> schema;
  final List<Map<String, Object?>> rows;
  final List<String> sourceHashes;
  final List<P4DatasetTransform> transforms;
  final String manifestHash;
}

final class P4DatasetEngine {
  P4DatasetVersion create({
    required String datasetId,
    required List<Map<String, Object?>> rows,
    required Map<String, String> schema,
    required List<String> sourceHashes,
    List<P4DatasetTransform> transforms = const <P4DatasetTransform>[],
    P4DatasetVersion? parent,
    DateTime? createdAt,
  }) {
    if (datasetId.trim().isEmpty || rows.length > 500000) {
      throw const P4ResearchException('dataset_invalid');
    }
    var output = rows.map((row) => Map<String, Object?>.from(row)).toList();
    for (final transform in transforms) {
      output = _apply(output, transform);
    }
    final time = (createdAt ?? DateTime.now()).toUtc();
    final manifest = <String, Object?>{
      'schemaVersion': '1.0.0',
      'datasetId': datasetId,
      'parentVersionId': parent?.id,
      'createdAt': time.toIso8601String(),
      'schema': schema,
      'sourceHashes': sourceHashes.toList()..sort(),
      'transforms': transforms.map((value) => value.toJson()).toList(),
      'rowsHash': Sha256.text(canonicalJson(output)),
    };
    final manifestHash = Sha256.text(canonicalJson(manifest));
    return P4DatasetVersion(
      id: 'datasetv_${manifestHash.substring(0, 32)}',
      datasetId: datasetId,
      parentVersionId: parent?.id,
      createdAt: time,
      schema: Map<String, String>.unmodifiable(schema),
      rows: List<Map<String, Object?>>.unmodifiable(
        output.map(Map<String, Object?>.unmodifiable),
      ),
      sourceHashes: List<String>.unmodifiable(sourceHashes),
      transforms: List<P4DatasetTransform>.unmodifiable(transforms),
      manifestHash: manifestHash,
    );
  }

  List<Map<String, Object?>> _apply(
    List<Map<String, Object?>> rows,
    P4DatasetTransform transform,
  ) {
    final args = transform.arguments;
    switch (transform.kind) {
      case P4DatasetTransformKind.select:
        final fields =
            (args['fields'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        return rows
            .map((row) => <String, Object?>{
                  for (final field in fields) field: row[field],
                })
            .toList();
      case P4DatasetTransformKind.rename:
        final from = args['from']?.toString() ?? '';
        final to = args['to']?.toString() ?? '';
        if (from.isEmpty || to.isEmpty) {
          throw const P4ResearchException('dataset_transform_invalid');
        }
        return rows.map((row) {
          final copy = Map<String, Object?>.from(row);
          if (copy.containsKey(from)) copy[to] = copy.remove(from);
          return copy;
        }).toList();
      case P4DatasetTransformKind.cast:
        final field = args['field']?.toString() ?? '';
        final type = args['type']?.toString() ?? '';
        return rows.map((row) {
          final copy = Map<String, Object?>.from(row);
          final value = copy[field];
          copy[field] = switch (type) {
            'string' => value?.toString(),
            'int' => int.tryParse(value?.toString() ?? ''),
            'double' => double.tryParse(value?.toString() ?? ''),
            'bool' => value?.toString().toLowerCase() == 'true',
            _ => throw const P4ResearchException('dataset_transform_invalid'),
          };
          return copy;
        }).toList();
      case P4DatasetTransformKind.filterEquals:
        final field = args['field']?.toString() ?? '';
        final value = args['value'];
        return rows.where((row) => row[field] == value).toList();
      case P4DatasetTransformKind.sort:
        final field = args['field']?.toString() ?? '';
        final descending = args['descending'] == true;
        final copy = rows.toList();
        copy.sort((a, b) {
          final result = '${a[field] ?? ''}'.compareTo('${b[field] ?? ''}');
          return descending ? -result : result;
        });
        return copy;
      case P4DatasetTransformKind.dedupe:
        final fields =
            (args['fields'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final seen = <String>{};
        return rows.where((row) {
          final key = canonicalJson(
              <String, Object?>{for (final field in fields) field: row[field]});
          return seen.add(key);
        }).toList();
      case P4DatasetTransformKind.normalizeText:
        final field = args['field']?.toString() ?? '';
        return rows.map((row) {
          final copy = Map<String, Object?>.from(row);
          final value = copy[field];
          if (value != null) {
            copy[field] =
                value.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
          }
          return copy;
        }).toList();
      case P4DatasetTransformKind.annotate:
        final field = args['field']?.toString() ?? '';
        return rows
            .map((row) => <String, Object?>{...row, field: args['value']})
            .toList();
      case P4DatasetTransformKind.validateRequired:
        final fields =
            (args['fields'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        for (final row in rows) {
          for (final field in fields) {
            final value = row[field];
            if (value == null || value.toString().trim().isEmpty) {
              throw P4ResearchException('dataset_validation_failed', field);
            }
          }
        }
        return rows;
    }
  }

  Future<void> export(
    P4DatasetVersion version,
    File file, {
    required String format,
  }) async {
    await file.parent.create(recursive: true);
    switch (format) {
      case 'jsonl':
        await file.writeAsString(
          version.rows.map(canonicalJson).join('\n') +
              (version.rows.isEmpty ? '' : '\n'),
          flush: true,
        );
      case 'csv':
        final fields = version.schema.keys.toList();
        String escape(Object? value) {
          final text = value?.toString() ?? '';
          return '"${text.replaceAll('"', '""')}"';
        }
        final lines = <String>[
          fields.map(escape).join(','),
          ...version.rows.map(
              (row) => fields.map((field) => escape(row[field])).join(',')),
        ];
        await file.writeAsString('${lines.join('\n')}\n', flush: true);
      case 'markdown':
        final fields = version.schema.keys.toList();
        String cell(Object? value) => (value?.toString() ?? '')
            .replaceAll('|', r'\|')
            .replaceAll('\n', ' ');
        final lines = <String>[
          '| ${fields.join(' | ')} |',
          '| ${fields.map((_) => '---').join(' | ')} |',
          ...version.rows.map((row) =>
              '| ${fields.map((field) => cell(row[field])).join(' | ')} |'),
        ];
        await file.writeAsString('${lines.join('\n')}\n', flush: true);
      case 'sqlite':
        if (await file.exists()) await file.delete();
        final db = sqlite3.open(file.path);
        try {
          final fields = version.schema.keys.toList();
          final definitions = fields
              .map((field) => '"${field.replaceAll('"', '""')}" TEXT')
              .join(', ');
          db.execute('CREATE TABLE data ($definitions)');
          if (fields.isNotEmpty) {
            final columns = fields
                .map((field) => '"${field.replaceAll('"', '""')}"')
                .join(', ');
            final placeholders = List.filled(fields.length, '?').join(', ');
            final statement = db
                .prepare('INSERT INTO data ($columns) VALUES ($placeholders)');
            try {
              for (final row in version.rows) {
                statement.execute(
                    fields.map((field) => row[field]?.toString()).toList());
              }
            } finally {
              statement.dispose();
            }
          }
          db.execute(
              'CREATE TABLE manifest (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          final statement =
              db.prepare('INSERT INTO manifest (key, value) VALUES (?, ?)');
          try {
            statement.execute(<Object?>['datasetVersionId', version.id]);
            statement.execute(<Object?>['manifestHash', version.manifestHash]);
          } finally {
            statement.dispose();
          }
        } finally {
          db.dispose();
        }
      default:
        throw const P4ResearchException('dataset_export_format_unsupported');
    }
  }
}

final class P4ChangeRecord {
  const P4ChangeRecord({
    required this.canonicalUrl,
    required this.beforeHash,
    required this.afterHash,
    required this.changed,
    required this.recordedAt,
  });
  final String canonicalUrl;
  final String? beforeHash;
  final String afterHash;
  final bool changed;
  final DateTime recordedAt;
}

final class P4FreshnessMonitor {
  final Map<String, String> _latest = <String, String>{};

  P4ChangeRecord observe({
    required String canonicalUrl,
    required String extractionHash,
    DateTime? recordedAt,
  }) {
    final before = _latest[canonicalUrl];
    _latest[canonicalUrl] = extractionHash;
    return P4ChangeRecord(
      canonicalUrl: canonicalUrl,
      beforeHash: before,
      afterHash: extractionHash,
      changed: before != null && before != extractionHash,
      recordedAt: (recordedAt ?? DateTime.now()).toUtc(),
    );
  }
}
