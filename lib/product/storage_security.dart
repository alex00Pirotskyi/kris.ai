import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'knowledge_memory_v2.dart';
import 'durable_workflow.dart';
import 'repository.dart';

class ProductException implements Exception {
  ProductException(this.code, this.message,
      {this.details = const <String, dynamic>{}});

  final String code;
  final String message;
  final Map<String, dynamic> details;

  @override
  String toString() => '$code: $message';
}

class AppDirectories {
  AppDirectories._(this.root)
      : state = Directory('${root.path}${Platform.pathSeparator}state'),
        logs = Directory('${root.path}${Platform.pathSeparator}logs'),
        cache = Directory('${root.path}${Platform.pathSeparator}cache'),
        support = Directory('${root.path}${Platform.pathSeparator}support');

  final Directory root;
  final Directory state;
  final Directory logs;
  final Directory cache;
  final Directory support;

  static Future<AppDirectories> create({String? overrideRoot}) async {
    String base;
    if (overrideRoot != null && overrideRoot.trim().isNotEmpty) {
      base = overrideRoot;
    } else if (Platform.isWindows) {
      base = Platform.environment['APPDATA'] ??
          Platform.environment['LOCALAPPDATA'] ??
          Directory.current.path;
      base = '$base${Platform.pathSeparator}KristinLocalAgent';
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      base =
          '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}KristinLocalAgent';
    } else {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final xdg = Platform.environment['XDG_STATE_HOME'];
      base = xdg == null || xdg.isEmpty
          ? '$home${Platform.pathSeparator}.local${Platform.pathSeparator}state${Platform.pathSeparator}kristin-local-agent'
          : '$xdg${Platform.pathSeparator}kristin-local-agent';
    }
    final directories = AppDirectories._(Directory(base));
    await Future.wait(<Future<void>>[
      directories.root.create(recursive: true),
      directories.state.create(recursive: true),
      directories.logs.create(recursive: true),
      directories.cache.create(recursive: true),
      directories.support.create(recursive: true),
    ]);
    return directories;
  }
}

class AtomicJsonFile implements JsonDocumentRepository {
  AtomicJsonFile(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<Object?> read({Object? fallback}) => synchronized(
        () => _readUnlocked(fallback: fallback),
      );

  @override
  Future<void> write(Object? value) => synchronized(
        () => _writeUnlocked(value),
      );

  Future<void> updateList(
    List<Object?> Function(List<Object?> current) update,
  ) =>
      synchronized(() async {
        final raw = await _readUnlocked(fallback: const <Object>[]);
        final current = raw is List ? List<Object?>.from(raw) : <Object?>[];
        final next = update(current);
        await _writeUnlocked(next);
      });

  Future<Object?> _readUnlocked({Object? fallback}) async {
    if (!await file.exists()) {
      return fallback;
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return fallback;
    }
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw ProductException(
        'storage_corrupt',
        'Invalid JSON in ${file.path}.',
        details: <String, dynamic>{'error': '$error'},
      );
    }
  }

  Future<void> _writeUnlocked(Object? value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp-${newId('write')}');
    final encoder = const JsonEncoder.withIndent('  ');
    await temporary.writeAsString('${encoder.convert(value)}\n', flush: true);
    if (await file.exists()) {
      final backup = File('${file.path}.bak');
      try {
        await file.copy(backup.path);
      } catch (_) {
        // A backup is best-effort; atomic replacement remains the safety boundary.
      }
    }
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}

class PersistentCollection<T> implements EntityRepository<T> {
  PersistentCollection({
    required File file,
    required this.fromJson,
    required this.toJson,
    required this.idOf,
  }) : _store = AtomicJsonFile(file);

  final AtomicJsonFile _store;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final String Function(T) idOf;

  @override
  Future<List<T>> all() async {
    final raw = await _store.read(fallback: const <Object>[]);
    if (raw is! List) {
      return <T>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => fromJson(mapValue(item)))
        .toList();
  }

  @override
  Future<T?> get(String id) async {
    for (final item in await all()) {
      if (idOf(item) == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> put(T item) => _mutate((items) {
        final index = items.indexWhere(
          (candidate) => idOf(candidate) == idOf(item),
        );
        if (index < 0) {
          items.add(item);
        } else {
          items[index] = item;
        }
      });

  @override
  Future<void> putAll(Iterable<T> values) => _mutate((items) {
        final current = <String, T>{for (final item in items) idOf(item): item};
        for (final item in values) {
          current[idOf(item)] = item;
        }
        items
          ..clear()
          ..addAll(current.values.toList()
            ..sort((a, b) => idOf(a).compareTo(idOf(b))));
      });

  @override
  Future<void> remove(String id) => _mutate(
        (items) => items.removeWhere((item) => idOf(item) == id),
      );

  @override
  Future<void> removeWhere(bool Function(T item) predicate) => _mutate(
        (items) => items.removeWhere(predicate),
      );

  @override
  Future<void> replaceAll(Iterable<T> values) =>
      _store.write(values.map(toJson).toList());

  Future<void> _mutate(void Function(List<T> items) update) =>
      _store.updateList((raw) {
        final items = raw
            .whereType<Map>()
            .map((item) => fromJson(mapValue(item)))
            .toList();
        update(items);
        return items.map<Object?>((item) => toJson(item)).toList();
      });
}

class ProductSettings {
  const ProductSettings({
    this.apiEnabled = false,
    this.apiPort = 47831,
    this.allowedOrigins = const <String>{
      'http://127.0.0.1',
      'http://localhost'
    },
    this.ollamaBaseUrl = 'http://127.0.0.1:11434',
    this.ollamaLoadTimeoutSeconds = 480,
    this.ollamaLoadRetries = 1,
    this.ollamaKeepAliveMinutes = 15,
    this.openAiCompatibleBaseUrl = '',
    this.openAiApiKeyReferenceId = '',
    this.localOnly = true,
    this.allowPackageNetwork = false,
    this.maxResearchBytes = 2097152,
    this.maxResearchRedirects = 3,
    this.researchTimeoutSeconds = 20,
  });

  final bool apiEnabled;
  final int apiPort;
  final Set<String> allowedOrigins;
  final String ollamaBaseUrl;
  final int ollamaLoadTimeoutSeconds;
  final int ollamaLoadRetries;
  final int ollamaKeepAliveMinutes;
  final String openAiCompatibleBaseUrl;
  final String openAiApiKeyReferenceId;
  final bool localOnly;
  final bool allowPackageNetwork;
  final int maxResearchBytes;
  final int maxResearchRedirects;
  final int researchTimeoutSeconds;

  ProductSettings copyWith({
    bool? apiEnabled,
    int? apiPort,
    Set<String>? allowedOrigins,
    String? ollamaBaseUrl,
    int? ollamaLoadTimeoutSeconds,
    int? ollamaLoadRetries,
    int? ollamaKeepAliveMinutes,
    String? openAiCompatibleBaseUrl,
    String? openAiApiKeyReferenceId,
    bool? localOnly,
    bool? allowPackageNetwork,
    int? maxResearchBytes,
    int? maxResearchRedirects,
    int? researchTimeoutSeconds,
  }) =>
      ProductSettings(
        apiEnabled: apiEnabled ?? this.apiEnabled,
        apiPort: apiPort ?? this.apiPort,
        allowedOrigins: allowedOrigins ?? this.allowedOrigins,
        ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
        ollamaLoadTimeoutSeconds:
            ollamaLoadTimeoutSeconds ?? this.ollamaLoadTimeoutSeconds,
        ollamaLoadRetries: ollamaLoadRetries ?? this.ollamaLoadRetries,
        ollamaKeepAliveMinutes:
            ollamaKeepAliveMinutes ?? this.ollamaKeepAliveMinutes,
        openAiCompatibleBaseUrl:
            openAiCompatibleBaseUrl ?? this.openAiCompatibleBaseUrl,
        openAiApiKeyReferenceId:
            openAiApiKeyReferenceId ?? this.openAiApiKeyReferenceId,
        localOnly: localOnly ?? this.localOnly,
        allowPackageNetwork: allowPackageNetwork ?? this.allowPackageNetwork,
        maxResearchBytes: maxResearchBytes ?? this.maxResearchBytes,
        maxResearchRedirects: maxResearchRedirects ?? this.maxResearchRedirects,
        researchTimeoutSeconds:
            researchTimeoutSeconds ?? this.researchTimeoutSeconds,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiEnabled': apiEnabled,
        'apiPort': apiPort,
        'allowedOrigins': allowedOrigins.toList()..sort(),
        'ollamaBaseUrl': ollamaBaseUrl,
        'ollamaLoadTimeoutSeconds': ollamaLoadTimeoutSeconds,
        'ollamaLoadRetries': ollamaLoadRetries,
        'ollamaKeepAliveMinutes': ollamaKeepAliveMinutes,
        'openAiCompatibleBaseUrl': openAiCompatibleBaseUrl,
        'openAiApiKeyReferenceId': openAiApiKeyReferenceId,
        'localOnly': localOnly,
        'allowPackageNetwork': allowPackageNetwork,
        'maxResearchBytes': maxResearchBytes,
        'maxResearchRedirects': maxResearchRedirects,
        'researchTimeoutSeconds': researchTimeoutSeconds,
      };

  factory ProductSettings.fromJson(Map<String, dynamic> json) =>
      ProductSettings(
        apiEnabled: json['apiEnabled'] == true,
        apiPort: int.tryParse(json['apiPort']?.toString() ?? '') ?? 47831,
        allowedOrigins: stringList(json['allowedOrigins']).toSet().isEmpty
            ? const <String>{'http://127.0.0.1', 'http://localhost'}
            : stringList(json['allowedOrigins']).toSet(),
        ollamaBaseUrl:
            json['ollamaBaseUrl']?.toString() ?? 'http://127.0.0.1:11434',
        ollamaLoadTimeoutSeconds:
            (int.tryParse(json['ollamaLoadTimeoutSeconds']?.toString() ?? '') ??
                    480)
                .clamp(60, 3600)
                .toInt(),
        ollamaLoadRetries:
            (int.tryParse(json['ollamaLoadRetries']?.toString() ?? '') ?? 1)
                .clamp(0, 2)
                .toInt(),
        ollamaKeepAliveMinutes:
            (int.tryParse(json['ollamaKeepAliveMinutes']?.toString() ?? '') ??
                    15)
                .clamp(1, 120)
                .toInt(),
        openAiCompatibleBaseUrl:
            json['openAiCompatibleBaseUrl']?.toString() ?? '',
        openAiApiKeyReferenceId:
            json['openAiApiKeyReferenceId']?.toString() ?? '',
        localOnly: json['localOnly'] != false,
        allowPackageNetwork: json['allowPackageNetwork'] == true,
        maxResearchBytes:
            int.tryParse(json['maxResearchBytes']?.toString() ?? '') ?? 2097152,
        maxResearchRedirects:
            int.tryParse(json['maxResearchRedirects']?.toString() ?? '') ?? 3,
        researchTimeoutSeconds:
            int.tryParse(json['researchTimeoutSeconds']?.toString() ?? '') ??
                20,
      );
}

class ProductRepositories {
  ProductRepositories._({
    required this.workflow,
    required this.projects,
    required this.commands,
    required this.runs,
    required this.knowledge,
    required this.researchArchive,
    required this.memoryEpisodes,
    required this.skillCandidates,
    required this.publishedSkills,
    required this.prompts,
    required this.promptVersions,
    required this.taskPlans,
    required this.grants,
    required this.secretReferences,
    required this.tokens,
    required this.evidence,
    required this.settingsFile,
    required this.eventFile,
    required this.auditFile,
  });

  final DurableWorkflowStore workflow;
  final EntityRepository<ProjectRecord> projects;
  final EntityRepository<PreparedCommand> commands;
  final EntityRepository<RunRecord> runs;
  final EntityRepository<KnowledgeEntry> knowledge;
  final EntityRepository<ResearchArchiveRecord> researchArchive;
  final EntityRepository<MemoryEpisode> memoryEpisodes;
  final EntityRepository<SkillCandidateRecord> skillCandidates;
  final EntityRepository<PublishedSkillRecord> publishedSkills;
  final EntityRepository<PromptTemplateRecord> prompts;
  final EntityRepository<PromptVersionRecord> promptVersions;
  final EntityRepository<TaskPlanRecord> taskPlans;
  final EntityRepository<PermissionGrant> grants;
  final EntityRepository<SecretReference> secretReferences;
  final EntityRepository<ApiTokenRecord> tokens;
  final EntityRepository<EvidenceRecord> evidence;
  final JsonDocumentRepository settingsFile;
  final File eventFile;
  final File auditFile;

  static Future<ProductRepositories> open(AppDirectories directories) async {
    File legacy(String name) => File(
          '${directories.state.path}${Platform.pathSeparator}$name.json',
        );
    final eventFile = File(
      '${directories.logs.path}${Platform.pathSeparator}events.jsonl',
    );
    final workflow = await DurableWorkflowStore.open(
      databaseFile: File(
        '${directories.state.path}${Platform.pathSeparator}workflow.sqlite3',
      ),
      migrationBackupDirectory: Directory(
        '${directories.support.path}${Platform.pathSeparator}migration-backups',
      ),
      legacyCollections: <String, File>{
        'projects': legacy('projects'),
        'commands': legacy('commands'),
        'knowledge': legacy('knowledge'),
        'research_archive': legacy('research_archive'),
        'memory_episodes': legacy('memory_episodes'),
        'skill_candidates': legacy('skill_candidates'),
        'published_skills': legacy('published_skills'),
        'prompts': legacy('prompts'),
        'prompt_versions': legacy('prompt_versions'),
        'task_plans': legacy('task_plans'),
        'permission_grants': legacy('permission_grants'),
        'secret_references': legacy('secret_references'),
        'api_tokens': legacy('api_tokens'),
        'evidence': legacy('evidence'),
        'mcp_trust': legacy('mcp_trust'),
      },
      legacyDocuments: <String, File>{'settings': legacy('settings')},
      legacyRunsFile: legacy('runs'),
      legacyEventsFile: eventFile,
    );

    SqliteEntityRepository<T> collection<T>({
      required String name,
      required T Function(Map<String, dynamic>) fromJson,
      required Map<String, dynamic> Function(T value) toJson,
      required String Function(T value) idOf,
    }) =>
        SqliteEntityRepository<T>(
          store: workflow,
          collection: name,
          fromJson: fromJson,
          toJson: toJson,
          idOf: idOf,
        );

    return ProductRepositories._(
      workflow: workflow,
      projects: collection<ProjectRecord>(
        name: 'projects',
        fromJson: ProjectRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      commands: collection<PreparedCommand>(
        name: 'commands',
        fromJson: PreparedCommand.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      runs: SqliteRunRepository(workflow),
      knowledge: collection<KnowledgeEntry>(
        name: 'knowledge',
        fromJson: KnowledgeEntry.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      researchArchive: collection<ResearchArchiveRecord>(
        name: 'research_archive',
        fromJson: ResearchArchiveRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      memoryEpisodes: collection<MemoryEpisode>(
        name: 'memory_episodes',
        fromJson: MemoryEpisode.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      skillCandidates: collection<SkillCandidateRecord>(
        name: 'skill_candidates',
        fromJson: SkillCandidateRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      publishedSkills: collection<PublishedSkillRecord>(
        name: 'published_skills',
        fromJson: PublishedSkillRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      prompts: collection<PromptTemplateRecord>(
        name: 'prompts',
        fromJson: PromptTemplateRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      promptVersions: collection<PromptVersionRecord>(
        name: 'prompt_versions',
        fromJson: PromptVersionRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      taskPlans: collection<TaskPlanRecord>(
        name: 'task_plans',
        fromJson: TaskPlanRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      grants: collection<PermissionGrant>(
        name: 'permission_grants',
        fromJson: PermissionGrant.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      secretReferences: collection<SecretReference>(
        name: 'secret_references',
        fromJson: SecretReference.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      tokens: collection<ApiTokenRecord>(
        name: 'api_tokens',
        fromJson: ApiTokenRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      evidence: collection<EvidenceRecord>(
        name: 'evidence',
        fromJson: EvidenceRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ),
      settingsFile: SqliteJsonDocument(workflow, 'settings'),
      eventFile: eventFile,
      auditFile: File(
        '${directories.logs.path}${Platform.pathSeparator}audit.jsonl',
      ),
    );
  }

  Future<ProductSettings> loadSettings() async {
    final raw = await settingsFile.read(fallback: <String, dynamic>{});
    return ProductSettings.fromJson(mapValue(raw));
  }

  Future<void> saveSettings(ProductSettings settings) =>
      settingsFile.write(settings.toJson());
}

class EventJournal {
  EventJournal(
    this.file, {
    this.workflow,
    this.maxRetained = 5000,
  });

  final File file;
  final DurableWorkflowStore? workflow;
  final int maxRetained;
  final StreamController<EventEnvelope> _controller =
      StreamController<EventEnvelope>.broadcast();
  Future<void> _tail = Future<void>.value();
  int _sequence = 0;

  Stream<EventEnvelope> get stream => _controller.stream;

  Future<void> open() async {
    await file.parent.create(recursive: true);
    final durable = workflow;
    if (durable != null) {
      _sequence = await durable.lastEventSequence();
      return;
    }
    if (!await file.exists()) {
      return;
    }
    final lines = await file.readAsLines();
    for (final line in lines.reversed) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          _sequence = EventEnvelope.fromJson(mapValue(decoded)).sequence;
          return;
        }
      } catch (_) {
        // Skip malformed trailing lines and continue to the preceding event.
      }
    }
  }

  Future<EventEnvelope> publish(
    String type,
    String correlationId,
    Map<String, dynamic> data,
  ) {
    final completer = Completer<EventEnvelope>();
    _tail = _tail.then((_) async {
      final id = newId('event');
      final timestamp = DateTime.now().toUtc();
      final durable = workflow;
      late EventEnvelope event;
      if (durable != null) {
        final stored = await durable.appendEvent(
          id: id,
          type: type,
          correlationId: correlationId,
          timestamp: timestamp,
          data: data,
        );
        _sequence = stored.sequence;
        event = stored.toEnvelope();
      } else {
        event = EventEnvelope(
          sequence: ++_sequence,
          id: id,
          type: type,
          correlationId: correlationId,
          timestamp: timestamp,
          data: data,
        );
      }
      // JSONL remains a bounded compatibility mirror for existing support
      // tooling. SQLite is the authoritative append-only event history, so a
      // mirror failure must not make callers retry an event that is already
      // durable and thereby create a duplicate logical transition.
      try {
        await file.writeAsString(
          '${jsonEncode(event.toJson())}\n',
          mode: FileMode.append,
          flush: true,
        );
        if (_sequence % 250 == 0) {
          await _compactMirror();
        }
      } catch (_) {
        // Support export can rebuild the mirror from SQLite. The authoritative
        // event has already committed and remains safe to acknowledge.
      }
      _controller.add(event);
      completer.complete(event);
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<EventEnvelope>> after(
    int sequence, {
    int limit = 500,
  }) async {
    final durable = workflow;
    if (durable != null) {
      return (await durable.eventsAfter(sequence, limit: limit))
          .map((event) => event.toEnvelope())
          .toList(growable: false);
    }
    if (!await file.exists()) {
      return <EventEnvelope>[];
    }
    final events = <EventEnvelope>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) {
          continue;
        }
        final event = EventEnvelope.fromJson(mapValue(decoded));
        if (event.sequence > sequence) {
          events.add(event);
        }
        if (events.length >= limit) {
          break;
        }
      } catch (_) {
        // A corrupt mirror line is isolated from later valid records.
      }
    }
    return events;
  }

  Future<void> _compactMirror() async {
    if (!await file.exists()) {
      return;
    }
    final lines = await file.readAsLines();
    if (lines.length <= maxRetained) {
      return;
    }
    final kept = lines.sublist(lines.length - maxRetained);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString('${kept.join('\n')}\n', flush: true);
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  Future<void> close() async {
    await _tail;
    await _controller.close();
  }
}

class AuditChain {
  AuditChain(this.file, this.redactor);

  final File file;
  final SecretRedactor redactor;
  Future<void> _tail = Future<void>.value();
  String _lastHash = '';

  Future<void> open() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      return;
    }
    final lines = await file.readAsLines();
    for (final line in lines.reversed) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          _lastHash = decoded['hash']?.toString() ?? '';
          return;
        }
      } catch (_) {
        // Ignore malformed trailing records; verify() will report chain damage.
      }
    }
  }

  Future<void> append(
      String action, String correlationId, Map<String, dynamic> data) {
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      final payload = <String, dynamic>{
        'id': newId('audit'),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'action': action,
        'correlationId': correlationId,
        'data': redactor.redactJson(data),
        'previousHash': _lastHash,
      };
      final hash = Sha256.text(canonicalJson(payload));
      final record = <String, dynamic>{...payload, 'hash': hash};
      await file.writeAsString('${jsonEncode(record)}\n',
          mode: FileMode.append, flush: true);
      _lastHash = hash;
      completer.complete();
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> verify() async {
    if (!await file.exists()) {
      return <String, dynamic>{'valid': true, 'records': 0, 'lastHash': ''};
    }
    var previous = '';
    var records = 0;
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) {
        continue;
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return <String, dynamic>{
          'valid': false,
          'records': records,
          'error': 'non_object_record'
        };
      }
      final record = mapValue(decoded);
      final hash = record.remove('hash')?.toString() ?? '';
      if (record['previousHash']?.toString() != previous) {
        return <String, dynamic>{
          'valid': false,
          'records': records,
          'error': 'previous_hash_mismatch'
        };
      }
      final expected = Sha256.text(canonicalJson(record));
      if (!constantTimeEquals(hash, expected)) {
        return <String, dynamic>{
          'valid': false,
          'records': records,
          'error': 'hash_mismatch'
        };
      }
      previous = hash;
      records++;
    }
    return <String, dynamic>{
      'valid': true,
      'records': records,
      'lastHash': previous
    };
  }
}

class PermissionService {
  PermissionService(this.repository, this.audit);

  final EntityRepository<PermissionGrant> repository;
  final AuditChain audit;

  Future<PermissionGrant> grant({
    required String projectId,
    required String commandId,
    required Set<PermissionScope> scopes,
    Duration validity = const Duration(minutes: 30),
    int uses = 1000,
  }) async {
    // A zero-scope grant is valid for model-only conversational work. It
    // cannot satisfy any ToolContext permission check.
    final now = DateTime.now().toUtc();
    final grant = PermissionGrant(
      id: newId('grant'),
      projectId: projectId,
      commandId: commandId,
      scopes: Set<PermissionScope>.unmodifiable(scopes),
      createdAt: now,
      expiresAt: now.add(validity),
      remainingUses: uses,
    );
    await repository.put(grant);
    await audit.append('permission.granted', commandId, grant.toJson());
    return grant;
  }

  Future<void> require({
    required String projectId,
    required String commandId,
    required PermissionScope scope,
  }) async {
    final grants = await repository.all();
    final candidates = grants.where((grant) =>
        grant.projectId == projectId &&
        grant.commandId == commandId &&
        grant.allows(scope));
    final grant = candidates.firstOrNull;
    if (grant == null) {
      throw ProductException(
          'permission_required', 'Permission ${scope.name} is required.',
          details: <String, dynamic>{
            'projectId': projectId,
            'commandId': commandId,
            'scope': scope.name,
          });
    }
    await repository.put(grant.consume());
    await audit.append('permission.consumed', commandId, <String, dynamic>{
      'grantId': grant.id,
      'scope': scope.name,
      'remainingUses': grant.remainingUses - 1,
    });
  }

  Future<void> revokeForCommand(String commandId) async {
    await repository.removeWhere((grant) => grant.commandId == commandId);
    await audit.append('permission.revoked', commandId,
        <String, dynamic>{'commandId': commandId});
  }
}

class SecretVault {
  SecretVault(this.repository, this.redactor, this.audit);

  final EntityRepository<SecretReference> repository;
  final SecretRedactor redactor;
  final AuditChain audit;
  final Map<String, String> _sessionValues = <String, String>{};

  Future<SecretReference> registerReference({
    required String label,
    required String environmentKey,
    String description = '',
  }) async {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(environmentKey)) {
      throw ProductException(
          'secret_reference_invalid', 'Environment key is invalid.');
    }
    final reference = SecretReference(
      id: newId('secret'),
      label: label.trim(),
      environmentKey: environmentKey,
      description: description.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    await repository.put(reference);
    await audit.append(
        'secret.reference_registered', reference.id, reference.toJson());
    return reference;
  }

  void setSessionValue(String referenceId, String value) {
    if (value.isEmpty) {
      throw ProductException('secret_empty', 'A secret value cannot be empty.');
    }
    _sessionValues[referenceId] = value;
    redactor.register(value);
  }

  Future<String> resolve(String referenceId,
      {required String commandId}) async {
    final reference = await repository.get(referenceId);
    if (reference == null) {
      throw ProductException(
          'secret_reference_missing', 'Unknown secret reference.');
    }
    final value = _sessionValues[referenceId] ??
        Platform.environment[reference.environmentKey];
    if (value == null || value.isEmpty) {
      throw ProductException('secret_unavailable',
          'Secret "${reference.label}" is not available in this session or environment.');
    }
    redactor.register(value);
    await audit.append('secret.resolved', commandId, <String, dynamic>{
      'referenceId': reference.id,
      'environmentKey': reference.environmentKey,
    });
    return value;
  }

  void clearSession() {
    _sessionValues.clear();
  }
}

class IssuedToken {
  const IssuedToken(this.record, this.plaintext);
  final ApiTokenRecord record;
  final String plaintext;
}

class ApiTokenService {
  ApiTokenService(this.repository, this.audit);

  final EntityRepository<ApiTokenRecord> repository;
  final AuditChain audit;

  Future<IssuedToken> issue({
    required String label,
    required Set<String> scopes,
    String? projectId,
    Duration validity = const Duration(days: 30),
  }) async {
    final plaintext = 'kla_${secureToken(bytes: 36)}';
    final now = DateTime.now().toUtc();
    final record = ApiTokenRecord(
      id: newId('token'),
      label: label.trim().isEmpty ? 'API token' : label.trim(),
      hash: Sha256.text(plaintext),
      scopes: Set<String>.unmodifiable(scopes),
      projectId: projectId,
      createdAt: now,
      expiresAt: now.add(validity),
    );
    await repository.put(record);
    await audit.append('api_token.issued', record.id, <String, dynamic>{
      'id': record.id,
      'label': record.label,
      'scopes': record.scopes.toList(),
      'projectId': projectId,
      'expiresAt': record.expiresAt.toIso8601String(),
    });
    return IssuedToken(record, plaintext);
  }

  Future<ApiTokenRecord?> authenticate(String plaintext,
      {String? requiredScope, String? projectId}) async {
    if (plaintext.isEmpty) {
      return null;
    }
    final candidateHash = Sha256.text(plaintext);
    for (final record in await repository.all()) {
      if (!record.isActive || !constantTimeEquals(candidateHash, record.hash)) {
        continue;
      }
      if (requiredScope != null &&
          !record.scopes.contains(requiredScope) &&
          !record.scopes.contains('*')) {
        return null;
      }
      if (record.projectId != null &&
          projectId != null &&
          record.projectId != projectId) {
        return null;
      }
      if (record.projectId != null && projectId == null) {
        return null;
      }
      return record;
    }
    return null;
  }

  Future<void> revoke(String id) async {
    final record = await repository.get(id);
    if (record == null) {
      return;
    }
    await repository.put(ApiTokenRecord(
      id: record.id,
      label: record.label,
      hash: record.hash,
      scopes: record.scopes,
      projectId: record.projectId,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
      revokedAt: DateTime.now().toUtc(),
    ));
    await audit.append('api_token.revoked', id, <String, dynamic>{'id': id});
  }
}

class RateLimiter {
  RateLimiter({this.capacity = 60, this.refillPerMinute = 60});

  final int capacity;
  final int refillPerMinute;
  final Map<String, _RateBucket> _buckets = <String, _RateBucket>{};

  bool allow(String key, {int cost = 1}) {
    final now = DateTime.now().toUtc();
    final bucket =
        _buckets.putIfAbsent(key, () => _RateBucket(capacity.toDouble(), now));
    final elapsed = now.difference(bucket.updatedAt).inMilliseconds / 60000.0;
    bucket.tokens = (bucket.tokens + elapsed * refillPerMinute)
        .clamp(0, capacity)
        .toDouble();
    bucket.updatedAt = now;
    if (bucket.tokens < cost) {
      return false;
    }
    bucket.tokens -= cost;
    if (_buckets.length > 10000) {
      _buckets.removeWhere((_, value) =>
          now.difference(value.updatedAt) > const Duration(hours: 1));
    }
    return true;
  }
}

class _RateBucket {
  _RateBucket(this.tokens, this.updatedAt);
  double tokens;
  DateTime updatedAt;
}
