import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto_utils.dart';
import 'domain.dart';
import 'repository.dart';

class StoredObjectRecord {
  const StoredObjectRecord({
    required this.sha256,
    required this.relativePath,
    required this.mediaType,
    required this.sizeBytes,
    required this.createdAt,
    this.labels = const <String, String>{},
  });

  final String sha256;
  final String relativePath;
  final String mediaType;
  final int sizeBytes;
  final DateTime createdAt;
  final Map<String, String> labels;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': '1.0.0',
    'sha256': sha256,
    'relativePath': relativePath,
    'mediaType': mediaType,
    'sizeBytes': sizeBytes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'labels': labels,
  };

  factory StoredObjectRecord.fromJson(Map<String, dynamic> json) =>
      StoredObjectRecord(
        sha256: json['sha256']?.toString() ?? '',
        relativePath: json['relativePath']?.toString() ?? '',
        mediaType: json['mediaType']?.toString() ?? 'application/octet-stream',
        sizeBytes: int.tryParse(json['sizeBytes']?.toString() ?? '') ?? 0,
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        labels: mapValue(
          json['labels'],
        ).map((key, value) => MapEntry(key, value.toString())),
      );
}

class ContentAddressedObjectStore {
  ContentAddressedObjectStore(this.root);

  final Directory root;

  Future<void> initialize() => root.create(recursive: true);

  String relativePathForHash(String sha256, {String extension = ''}) {
    final clean = sha256.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toLowerCase();
    final safe = clean.length >= 4 ? clean : clean.padRight(4, '0');
    final suffix = extension.trim().isEmpty
        ? ''
        : '.${extension.replaceAll('.', '').toLowerCase()}';
    return 'sha256/${safe.substring(0, 2)}/${safe.substring(2, 4)}/$safe$suffix';
  }

  File fileForRelativePath(String relativePath) {
    final clean = relativePath.replaceAll('\\', '/');
    if (clean.startsWith('/') ||
        clean.split('/').any((segment) => segment.isEmpty || segment == '..')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Invalid object-store path.',
      );
    }
    final file = File(
      '${root.path}${Platform.pathSeparator}${clean.replaceAll('/', Platform.pathSeparator)}',
    ).absolute;
    final rootPath = root.absolute.path.replaceAll('\\', '/');
    final candidate = file.path.replaceAll('\\', '/');
    final normalizedRoot = Platform.isWindows
        ? rootPath.toLowerCase()
        : rootPath;
    final normalizedCandidate = Platform.isWindows
        ? candidate.toLowerCase()
        : candidate;
    if (normalizedCandidate != normalizedRoot &&
        !normalizedCandidate.startsWith('$normalizedRoot/')) {
      throw StateError('Object-store path escapes the object root.');
    }
    return file;
  }

  Future<StoredObjectRecord> putBytes(
    List<int> bytes, {
    required String mediaType,
    String extension = '',
    Map<String, String> labels = const <String, String>{},
  }) async {
    await initialize();
    final digest = Sha256.hex(bytes);
    final relative = relativePathForHash(digest, extension: extension);
    final file = fileForRelativePath(relative);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    final manifest = StoredObjectRecord(
      sha256: digest,
      relativePath: relative,
      mediaType: mediaType,
      sizeBytes: bytes.length,
      createdAt: DateTime.now().toUtc(),
      labels: labels,
    );
    final envelope = File('${file.path}.json');
    if (!await envelope.exists()) {
      await envelope.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
        flush: true,
      );
    }
    return manifest;
  }

  Future<StoredObjectRecord> putText(
    String text, {
    String mediaType = 'text/plain',
    String extension = 'txt',
    Map<String, String> labels = const <String, String>{},
  }) {
    return putBytes(
      utf8.encode(text),
      mediaType: mediaType,
      extension: extension,
      labels: labels,
    );
  }

  Future<Uint8List> readBytes(String relativePath) async {
    final file = fileForRelativePath(relativePath);
    return Uint8List.fromList(await file.readAsBytes());
  }
}

enum ResearchFreshnessState { fresh, aging, stale, unknown }

class ResearchFreshnessPolicy {
  const ResearchFreshnessPolicy({
    this.freshDays = 30,
    this.agingDays = 180,
    this.citationRequired = true,
    this.staleWarningRequired = true,
  });

  final int freshDays;
  final int agingDays;
  final bool citationRequired;
  final bool staleWarningRequired;

  ResearchFreshnessState evaluate(DateTime capturedAt, {DateTime? now}) {
    final reference = (now ?? DateTime.now().toUtc()).toUtc();
    final ageDays = reference.difference(capturedAt.toUtc()).inDays;
    if (ageDays < 0) {
      return ResearchFreshnessState.unknown;
    }
    if (ageDays <= freshDays) {
      return ResearchFreshnessState.fresh;
    }
    if (ageDays <= agingDays) {
      return ResearchFreshnessState.aging;
    }
    return ResearchFreshnessState.stale;
  }

  String labelFor(DateTime capturedAt, {DateTime? now}) =>
      evaluate(capturedAt, now: now).name;
}

class MemoryAdmissionDecision {
  const MemoryAdmissionDecision({
    required this.status,
    required this.reason,
    required this.retrievalAllowed,
    required this.candidateSkill,
    required this.diagnosticOnly,
  });

  final String status;
  final String reason;
  final bool retrievalAllowed;
  final bool candidateSkill;
  final bool diagnosticOnly;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'reason': reason,
    'retrievalAllowed': retrievalAllowed,
    'candidateSkill': candidateSkill,
    'diagnosticOnly': diagnosticOnly,
  };
}

class MemoryAdmissionPolicy {
  const MemoryAdmissionPolicy({
    this.requireEvidenceHashes = true,
    this.quarantineUnsuccessfulRuns = true,
    this.promoteSuccessfulMutations = true,
  });

  final bool requireEvidenceHashes;
  final bool quarantineUnsuccessfulRuns;
  final bool promoteSuccessfulMutations;

  MemoryAdmissionDecision evaluateEpisode(MemoryEpisode episode) {
    if (episode.pinned) {
      return const MemoryAdmissionDecision(
        status: 'admitted',
        reason: 'Pinned memory remains available.',
        retrievalAllowed: true,
        candidateSkill: false,
        diagnosticOnly: false,
      );
    }
    if (requireEvidenceHashes && episode.evidenceHashes.isEmpty) {
      return const MemoryAdmissionDecision(
        status: 'rejected',
        reason: 'Memory admission requires evidence hashes.',
        retrievalAllowed: false,
        candidateSkill: false,
        diagnosticOnly: false,
      );
    }
    final conversational =
        _looksConversational(episode.request) &&
        episode.filesChanged.isEmpty &&
        episode.completedItems.isEmpty;
    if (conversational) {
      return const MemoryAdmissionDecision(
        status: 'rejected',
        reason: 'Conversational turns do not enter semantic project memory.',
        retrievalAllowed: false,
        candidateSkill: false,
        diagnosticOnly: false,
      );
    }
    if (episode.outcome == RunState.succeeded) {
      final reusable =
          (episode.filesChanged.isNotEmpty ||
              episode.completedItems.isNotEmpty) &&
          (episode.mutations > 0 || episode.toolCalls >= 2);
      return MemoryAdmissionDecision(
        status: 'admitted',
        reason:
            'Successful governed work with evidence is eligible for retrieval.',
        retrievalAllowed: true,
        candidateSkill: promoteSuccessfulMutations && reusable,
        diagnosticOnly: false,
      );
    }
    if (quarantineUnsuccessfulRuns) {
      return const MemoryAdmissionDecision(
        status: 'quarantined',
        reason: 'Unsuccessful runs are retained only as diagnostic memory.',
        retrievalAllowed: false,
        candidateSkill: false,
        diagnosticOnly: true,
      );
    }
    return const MemoryAdmissionDecision(
      status: 'rejected',
      reason: 'Unsuccessful memory is disabled.',
      retrievalAllowed: false,
      candidateSkill: false,
      diagnosticOnly: false,
    );
  }

  bool _looksConversational(String request) {
    final lower = request.toLowerCase();
    return const <String>[
      'what is',
      'tell me',
      'who is',
      'summarize',
      'explain',
    ].any(lower.contains);
  }
}

class SkillCandidateRecord {
  const SkillCandidateRecord({
    required this.id,
    required this.projectId,
    required this.sourceEpisodeId,
    required this.title,
    required this.instructions,
    required this.triggers,
    required this.recommendedTools,
    required this.evidenceHashes,
    required this.candidateHash,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String sourceEpisodeId;
  final String title;
  final String instructions;
  final Set<String> triggers;
  final Set<String> recommendedTools;
  final List<String> evidenceHashes;
  final String candidateHash;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': '1.0.0',
    'id': id,
    'projectId': projectId,
    'sourceEpisodeId': sourceEpisodeId,
    'title': title,
    'instructions': instructions,
    'triggers': triggers.toList()..sort(),
    'recommendedTools': recommendedTools.toList()..sort(),
    'evidenceHashes': evidenceHashes,
    'candidateHash': candidateHash,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory SkillCandidateRecord.fromJson(Map<String, dynamic> json) =>
      SkillCandidateRecord(
        id: json['id']?.toString() ?? newId('skill_candidate'),
        projectId: json['projectId']?.toString() ?? '',
        sourceEpisodeId: json['sourceEpisodeId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        triggers: stringList(json['triggers']).toSet(),
        recommendedTools: stringList(json['recommendedTools']).toSet(),
        evidenceHashes: stringList(json['evidenceHashes']),
        candidateHash: json['candidateHash']?.toString() ?? '',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}

class PublishedSkillRecord {
  const PublishedSkillRecord({
    required this.id,
    required this.candidateId,
    required this.version,
    required this.title,
    required this.instructions,
    required this.recommendedTools,
    required this.approvalNote,
    required this.manifestHash,
    required this.publishedAt,
  });

  final String id;
  final String candidateId;
  final int version;
  final String title;
  final String instructions;
  final Set<String> recommendedTools;
  final String approvalNote;
  final String manifestHash;
  final DateTime publishedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': '1.0.0',
    'id': id,
    'candidateId': candidateId,
    'version': version,
    'title': title,
    'instructions': instructions,
    'recommendedTools': recommendedTools.toList()..sort(),
    'approvalNote': approvalNote,
    'manifestHash': manifestHash,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
  };

  factory PublishedSkillRecord.fromJson(Map<String, dynamic> json) =>
      PublishedSkillRecord(
        id: json['id']?.toString() ?? newId('published_skill'),
        candidateId: json['candidateId']?.toString() ?? '',
        version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
        title: json['title']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        recommendedTools: stringList(json['recommendedTools']).toSet(),
        approvalNote: json['approvalNote']?.toString() ?? '',
        manifestHash: json['manifestHash']?.toString() ?? '',
        publishedAt: parseUtc(json['publishedAt'], fallback: DateTime.now()),
      );
}

class SkillPublicationService {
  const SkillPublicationService({
    required this.candidateRepository,
    required this.publishedRepository,
    required this.objectStore,
  });

  final EntityRepository<SkillCandidateRecord> candidateRepository;
  final EntityRepository<PublishedSkillRecord> publishedRepository;
  final ContentAddressedObjectStore objectStore;

  Future<SkillCandidateRecord?> extractFromEpisode(
    MemoryEpisode episode,
  ) async {
    final decision = const MemoryAdmissionPolicy().evaluateEpisode(episode);
    if (!decision.candidateSkill) {
      return null;
    }
    final tokens = _terms(episode.request).take(8).toSet();
    final tools = <String>{'read_file', 'inspect_file', 'verify_project'};
    if (episode.mutations > 0) {
      tools.add('write_file');
    }
    if (episode.toolCalls >= 2) {
      tools.add('run_command');
    }
    final instructions = <String>[
      'Objective: ${episode.request.trim()}',
      if (episode.summary.trim().isNotEmpty)
        'Summary: ${episode.summary.trim()}',
      if (episode.lessons.trim().isNotEmpty)
        'Lessons: ${episode.lessons.trim()}',
      if (episode.filesChanged.isNotEmpty)
        'Changed files: ${episode.filesChanged.join(', ')}',
    ].join('\n');
    final payload = <String, dynamic>{
      'projectId': episode.projectId,
      'sourceEpisodeId': episode.id,
      'title': episode.request.trim(),
      'instructions': instructions,
      'triggers': tokens.toList()..sort(),
      'recommendedTools': tools.toList()..sort(),
      'evidenceHashes': episode.evidenceHashes,
    };
    final candidate = SkillCandidateRecord(
      id: newId('skill_candidate'),
      projectId: episode.projectId,
      sourceEpisodeId: episode.id,
      title: episode.request.trim().isEmpty
          ? 'Governed procedure'
          : episode.request.trim(),
      instructions: instructions,
      triggers: tokens,
      recommendedTools: tools,
      evidenceHashes: episode.evidenceHashes,
      candidateHash: Sha256.text(canonicalJson(payload)),
      createdAt: DateTime.now().toUtc(),
    );
    await candidateRepository.put(candidate);
    await objectStore.putText(
      canonicalJson(candidate.toJson()),
      mediaType: 'application/json',
      extension: 'json',
      labels: const <String, String>{'kind': 'skill-candidate'},
    );
    return candidate;
  }

  Future<List<SkillCandidateRecord>> listCandidates() async {
    final values = await candidateRepository.all();
    values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  Future<List<PublishedSkillRecord>> listPublished() async {
    final values = await publishedRepository.all();
    values.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return values;
  }

  Future<PublishedSkillRecord> publishCandidate(
    SkillCandidateRecord candidate, {
    required String approvalNote,
    required bool replayPassed,
  }) async {
    if (!replayPassed) {
      throw StateError(
        'A candidate skill requires a passing replay evaluation.',
      );
    }
    if (approvalNote.trim().isEmpty) {
      throw ArgumentError.value(
        approvalNote,
        'approvalNote',
        'Publishing a skill requires an explicit approval note.',
      );
    }
    final existing = (await publishedRepository.all())
        .where((item) => item.candidateId == candidate.id)
        .toList();
    final version = existing.length + 1;
    final manifest = <String, dynamic>{
      'candidateId': candidate.id,
      'title': candidate.title,
      'instructions': candidate.instructions,
      'recommendedTools': candidate.recommendedTools.toList()..sort(),
      'approvalNote': approvalNote.trim(),
      'version': version,
    };
    final published = PublishedSkillRecord(
      id: newId('published_skill'),
      candidateId: candidate.id,
      version: version,
      title: candidate.title,
      instructions: candidate.instructions,
      recommendedTools: candidate.recommendedTools,
      approvalNote: approvalNote.trim(),
      manifestHash: Sha256.text(canonicalJson(manifest)),
      publishedAt: DateTime.now().toUtc(),
    );
    await publishedRepository.put(published);
    await objectStore.putText(
      canonicalJson(published.toJson()),
      mediaType: 'application/json',
      extension: 'json',
      labels: const <String, String>{'kind': 'published-skill'},
    );
    return published;
  }

  Iterable<String> _terms(String value) sync* {
    final matches = RegExp(r'[a-z0-9_./-]+').allMatches(value.toLowerCase());
    for (final match in matches) {
      final token = match.group(0);
      if (token != null && token.isNotEmpty) {
        yield token;
      }
    }
  }
}
