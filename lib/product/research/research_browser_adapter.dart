import '../browser/browser_runtime.dart';
import '../crypto_utils.dart';
import 'research_runtime.dart';

abstract interface class P4RenderedBrowserBackend {
  Future<P3BrowserPageObservation> render(Uri url);
  Future<void> closeRenderedPage(P3BrowserPageObservation observation);
}

final class P4RenderedResearchEvidence {
  const P4RenderedResearchEvidence({
    required this.finalUrl,
    required this.title,
    required this.dom,
    required this.visibleText,
    required this.observationHash,
    required this.screenshotSha256,
    required this.rendered,
  });

  final Uri finalUrl;
  final String title;
  final String dom;
  final String visibleText;
  final String observationHash;
  final String screenshotSha256;
  final bool rendered;

  Map<String, Object?> toExtractionSeed() => <String, Object?>{
    'sourceKind': 'rendered-browser',
    'rendered': rendered,
    'url': finalUrl.toString(),
    'title': title,
    'dom': dom,
    'visibleText': visibleText,
    'observationHash': observationHash,
    'screenshotSha256': screenshotSha256,
  };
}

final class P4RenderedResearchFetcher {
  const P4RenderedResearchFetcher(this.backend);
  final P4RenderedBrowserBackend backend;

  Future<P4RenderedResearchEvidence> fetch(Uri url) async {
    if (url.scheme != 'https' ||
        url.host.trim().isEmpty ||
        url.userInfo.isNotEmpty) {
      throw const P4ResearchException('research_rendered_url_invalid');
    }
    final observation = await backend.render(url);
    try {
      final payload = observation.observation;
      final observedUrl = Uri.tryParse(payload['url']?.toString() ?? '');
      final dom = payload['dom'];
      final visible = payload['visibleText'];
      final screenshot = payload['screenshot'];
      if (observedUrl == null ||
          observedUrl.scheme != 'https' ||
          dom is! Map ||
          visible is! Map ||
          screenshot is! Map ||
          dom['text'] is! String ||
          visible['text'] is! String ||
          screenshot['sha256'] is! String ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch(screenshot['sha256']! as String)) {
        throw const P4ResearchException(
          'research_rendered_observation_invalid',
        );
      }
      final title = payload['title']?.toString() ?? '';
      final domText = dom['text']! as String;
      final visibleText = visible['text']! as String;
      final canonical = canonicalJson(<String, Object?>{
        'url': observedUrl.toString(),
        'title': title,
        'dom': domText,
        'visibleText': visibleText,
        'observationHash': observation.observationHash,
        'screenshotSha256': screenshot['sha256'],
      });
      if (canonical.length > 1024 * 1024) {
        throw const P4ResearchException('research_rendered_evidence_too_large');
      }
      return P4RenderedResearchEvidence(
        finalUrl: observedUrl,
        title: title,
        dom: domText,
        visibleText: visibleText,
        observationHash: observation.observationHash,
        screenshotSha256: screenshot['sha256']! as String,
        rendered: true,
      );
    } finally {
      await backend.closeRenderedPage(observation);
    }
  }
}

final class P4DatasetJoinResult {
  const P4DatasetJoinResult({
    required this.rows,
    required this.matched,
    required this.leftOnly,
  });
  final List<Map<String, Object?>> rows;
  final int matched;
  final int leftOnly;
}

final class P4DatasetJoiner {
  const P4DatasetJoiner._();

  static P4DatasetJoinResult leftJoin({
    required List<Map<String, Object?>> left,
    required List<Map<String, Object?>> right,
    required String leftKey,
    required String rightKey,
    String rightPrefix = 'right_',
  }) {
    if (leftKey.trim().isEmpty ||
        rightKey.trim().isEmpty ||
        rightPrefix.contains(RegExp(r'[^A-Za-z0-9_]'))) {
      throw const P4ResearchException('dataset_join_invalid');
    }
    final byKey = <String, Map<String, Object?>>{};
    for (final row in right) {
      final key = row[rightKey]?.toString();
      if (key == null || key.isEmpty) continue;
      if (byKey.containsKey(key)) {
        throw const P4ResearchException('dataset_join_right_key_not_unique');
      }
      byKey[key] = row;
    }
    var matched = 0;
    var leftOnly = 0;
    final output = <Map<String, Object?>>[];
    for (final row in left) {
      final joined = Map<String, Object?>.from(row);
      final rightRow = byKey[row[leftKey]?.toString()];
      if (rightRow == null) {
        leftOnly += 1;
      } else {
        matched += 1;
        for (final entry in rightRow.entries) {
          if (entry.key == rightKey) continue;
          joined['$rightPrefix${entry.key}'] = entry.value;
        }
      }
      output.add(joined);
    }
    return P4DatasetJoinResult(
      rows: List<Map<String, Object?>>.unmodifiable(
        output.map(Map<String, Object?>.unmodifiable),
      ),
      matched: matched,
      leftOnly: leftOnly,
    );
  }
}

final class P4DatasetVersionDiff {
  const P4DatasetVersionDiff({
    required this.beforeId,
    required this.afterId,
    required this.addedRowHashes,
    required this.removedRowHashes,
    required this.schemaChanged,
  });
  final String beforeId;
  final String afterId;
  final List<String> addedRowHashes;
  final List<String> removedRowHashes;
  final bool schemaChanged;
}

P4DatasetVersionDiff p4DiffDatasetVersions(
  P4DatasetVersion before,
  P4DatasetVersion after,
) {
  final beforeRows = before.rows
      .map((row) => Sha256.text(canonicalJson(row)))
      .toSet();
  final afterRows = after.rows
      .map((row) => Sha256.text(canonicalJson(row)))
      .toSet();
  final added = afterRows.difference(beforeRows).toList()..sort();
  final removed = beforeRows.difference(afterRows).toList()..sort();
  return P4DatasetVersionDiff(
    beforeId: before.id,
    afterId: after.id,
    addedRowHashes: List<String>.unmodifiable(added),
    removedRowHashes: List<String>.unmodifiable(removed),
    schemaChanged: canonicalJson(before.schema) != canonicalJson(after.schema),
  );
}
