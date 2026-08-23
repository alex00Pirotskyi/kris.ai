import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'crypto_utils.dart';
import 'domain.dart';
import 'storage_security.dart';

class ZipEntryData {
  const ZipEntryData(this.name, this.bytes);
  final String name;
  final List<int> bytes;
}

class DeterministicZipWriter {
  const DeterministicZipWriter();

  Future<String> write(File output, Iterable<ZipEntryData> inputEntries) async {
    final entries = inputEntries.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final body = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var offset = 0;
    for (final entry in entries) {
      final normalized = _safeName(entry.name);
      final nameBytes = utf8.encode(normalized);
      final data = Uint8List.fromList(entry.bytes);
      final crc = Crc32.of(data);
      final local = BytesBuilder(copy: false)
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800)) // UTF-8
        ..add(_u16(0)) // stored
        ..add(_u16(0)) // fixed DOS time
        ..add(_u16(33)) // 1980-01-01
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(nameBytes)
        ..add(data);
      final localBytes = local.takeBytes();
      body.add(localBytes);

      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(33))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(offset))
        ..add(nameBytes);
      offset += localBytes.length;
    }
    final centralBytes = central.takeBytes();
    final archive = BytesBuilder(copy: false)
      ..add(body.takeBytes())
      ..add(centralBytes)
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(entries.length))
      ..add(_u16(entries.length))
      ..add(_u32(centralBytes.length))
      ..add(_u32(offset))
      ..add(_u16(0));
    await output.parent.create(recursive: true);
    final temporary = File(
      '${output.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsBytes(archive.takeBytes(), flush: true);
    if (Platform.isWindows && await output.exists()) {
      await output.delete();
    }
    await temporary.rename(output.path);
    return Sha256.hex(await output.readAsBytes());
  }

  String _safeName(String input) {
    final normalized = input
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty ||
        normalized
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw ProductException(
        'zip_entry_invalid',
        'Invalid ZIP entry name: $input',
      );
    }
    return normalized;
  }

  Uint8List _u16(int value) => (ByteData(
    2,
  )..setUint16(0, value & 0xffff, Endian.little)).buffer.asUint8List();
  Uint8List _u32(int value) => (ByteData(
    4,
  )..setUint32(0, value & 0xffffffff, Endian.little)).buffer.asUint8List();
}

class DeploymentPackage {
  const DeploymentPackage({
    required this.archivePath,
    required this.sha256,
    required this.profile,
    required this.fileCount,
    required this.totalBytes,
    required this.sbom,
    required this.secretScanFindings,
  });

  final String archivePath;
  final String sha256;
  final String profile;
  final int fileCount;
  final int totalBytes;
  final List<Map<String, String>> sbom;
  final List<Map<String, dynamic>> secretScanFindings;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'archivePath': archivePath,
    'sha256': sha256,
    'profile': profile,
    'fileCount': fileCount,
    'totalBytes': totalBytes,
    'sbom': sbom,
    'secretScanFindings': secretScanFindings,
  };
}

class DeploymentService {
  DeploymentService({required this.outputDirectory, required this.redactor});

  final Directory outputDirectory;
  final SecretRedactor redactor;
  final DeterministicZipWriter zipWriter = const DeterministicZipWriter();

  Future<DeploymentPackage> package({
    required ProjectRecord project,
    required String runId,
    String profile = 'auto',
  }) async {
    final root = Directory(project.rootPath).absolute;
    if (!await root.exists()) {
      throw ProductException(
        'project_missing',
        'Project root no longer exists.',
      );
    }
    final canonicalRoot = (await root.resolveSymbolicLinks()).replaceAll(
      '\\',
      '/',
    );
    final detected = profile == 'auto' ? await _detectProfile(root) : profile;
    final entries = <ZipEntryData>[];
    final findings = <Map<String, dynamic>>[];
    final sbom = <Map<String, String>>[];
    var totalBytes = 0;
    var filesScanned = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final canonical = (await entity.resolveSymbolicLinks()).replaceAll(
        '\\',
        '/',
      );
      if (!(canonical == canonicalRoot ||
          canonical.startsWith('$canonicalRoot/'))) {
        throw ProductException(
          'deployment_symlink_escape',
          'A file resolves outside the project boundary.',
        );
      }
      final relative = canonical
          .substring(canonicalRoot.length)
          .replaceFirst(RegExp(r'^/+'), '');
      if (_excluded(relative)) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.size > 32 * 1024 * 1024) {
        throw ProductException(
          'deployment_file_too_large',
          '$relative exceeds the 32 MiB source-package limit.',
        );
      }
      final bytes = await entity.readAsBytes();
      totalBytes += bytes.length;
      filesScanned++;
      if (totalBytes > 256 * 1024 * 1024 || filesScanned > 25000) {
        throw ProductException(
          'deployment_package_too_large',
          'Deployment package exceeds configured source limits.',
        );
      }
      if (!_looksBinary(bytes)) {
        final text = utf8.decode(bytes, allowMalformed: true);
        findings.addAll(_scanSecrets(relative, text));
        _collectDependencies(relative, text, sbom);
      }
      entries.add(ZipEntryData(relative, bytes));
    }
    if (findings.isNotEmpty) {
      throw ProductException(
        'deployment_secret_scan_failed',
        'Potential plaintext secrets were detected. Resolve them before packaging.',
        details: <String, dynamic>{'findings': findings.take(50).toList()},
      );
    }
    final now = DateTime.now().toUtc();
    final manifest = <String, dynamic>{
      'schemaVersion': 1,
      'product': 'Kristin Local Agent',
      'productVersion': kristinVersion,
      'projectId': project.id,
      'projectName': project.name,
      'runId': runId,
      'profile': detected,
      'createdAt': now.toIso8601String(),
      'sourceFiles': entries.length,
      'sourceBytes': totalBytes,
      'secretScan': 'passed',
      'secretsPolicy':
          'Runtime secrets must be supplied through environment variables or a platform secret manager; no values are included.',
    };
    entries.add(
      ZipEntryData(
        'KRISTIN_DEPLOYMENT_MANIFEST.json',
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        ),
      ),
    );
    entries.add(
      ZipEntryData(
        'KRISTIN_SBOM.json',
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'format': 'Kristin-SBOM-1', 'components': sbom})}\n',
        ),
      ),
    );
    entries.add(
      ZipEntryData(
        'DEPLOYMENT_README.md',
        utf8.encode(_readme(detected, project.name)),
      ),
    );
    await outputDirectory.create(recursive: true);
    final safeName = project.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final archive = File(
      '${outputDirectory.path}${Platform.pathSeparator}${safeName.isEmpty ? 'project' : safeName}-$runId-deployment.zip',
    );
    final hash = await zipWriter.write(archive, entries);
    return DeploymentPackage(
      archivePath: archive.path,
      sha256: hash,
      profile: detected,
      fileCount: entries.length,
      totalBytes: totalBytes,
      sbom: sbom,
      secretScanFindings: findings,
    );
  }

  Future<String> _detectProfile(Directory root) async {
    Future<bool> file(String path) => File(
      '${root.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
    ).exists();
    if (await file('pubspec.yaml')) {
      return 'flutter';
    }
    if (await file('package.json')) {
      final text = await File(
        '${root.path}${Platform.pathSeparator}package.json',
      ).readAsString();
      if (text.toLowerCase().contains('telegraf') ||
          text.toLowerCase().contains('telegram')) {
        return 'telegram-node';
      }
      return 'node-web';
    }
    if (await file('pyproject.toml') || await file('requirements.txt')) {
      final candidates = <File>[
        File('${root.path}${Platform.pathSeparator}pyproject.toml'),
        File('${root.path}${Platform.pathSeparator}requirements.txt'),
      ];
      final text = (await Future.wait(
        candidates
            .where((item) => item.existsSync())
            .map((item) => item.readAsString()),
      )).join('\n').toLowerCase();
      if (text.contains('python-telegram-bot') ||
          text.contains('aiogram') ||
          text.contains('telebot')) {
        return 'telegram-python';
      }
      return 'python-application';
    }
    if (await file('index.html')) {
      return 'static-website';
    }
    if (await file('CMakeLists.txt')) {
      return 'cmake-application';
    }
    return 'generic-source';
  }

  bool _excluded(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.any(
      const <String>{
        '.git',
        '.dart_tool',
        'build',
        'node_modules',
        '.venv',
        'venv',
        '__pycache__',
        '.pytest_cache',
        '.idea',
        '.vscode',
        '.kristin',
        'coverage',
        'dist',
        'target',
      }.contains,
    )) {
      return true;
    }
    final name = parts.last.toLowerCase();
    if (name == '.env' || name.startsWith('.env.') && name != '.env.example') {
      return true;
    }
    if (name.endsWith('.pem') ||
        name.endsWith('.key') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx')) {
      return true;
    }
    if (name == 'id_rsa' || name == 'id_ed25519') {
      return true;
    }
    return false;
  }

  bool _looksBinary(List<int> bytes) =>
      bytes.take(min(bytes.length, 8192)).contains(0);

  List<Map<String, dynamic>> _scanSecrets(String path, String text) {
    final patterns = <String, RegExp>{
      'private_key': RegExp(r'-----BEGIN [A-Z ]+PRIVATE KEY-----'),
      'openai_style_key': RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
      'telegram_bot_token': RegExp(r'\b\d{6,12}:[A-Za-z0-9_-]{25,}\b'),
      'aws_access_key': RegExp(r'\bAKIA[A-Z0-9]{16}\b'),
      'generic_assignment': RegExp(
        r'''\b(?:api[_-]?key|secret|password|access[_-]?token)\s*[:=]\s*["'](?!\$\{|process\.env|os\.environ|getenv|env\.)[^"']{8,}["']''',
        caseSensitive: false,
      ),
    };
    final findings = <Map<String, dynamic>>[];
    for (final entry in patterns.entries) {
      for (final match in entry.value.allMatches(text)) {
        final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
        findings.add(<String, dynamic>{
          'path': path,
          'line': line,
          'rule': entry.key,
        });
        if (findings.length >= 20) {
          return findings;
        }
      }
    }
    return findings;
  }

  void _collectDependencies(
    String path,
    String text,
    List<Map<String, String>> output,
  ) {
    if (path.endsWith('requirements.txt')) {
      for (final raw in const LineSplitter().convert(text)) {
        final line = raw.split('#').first.trim();
        if (line.isEmpty || line.startsWith('-')) {
          continue;
        }
        final match = RegExp(
          r'^([A-Za-z0-9_.-]+)\s*(?:==|~=|>=|<=|>|<)?\s*([^;\s]+)?',
        ).firstMatch(line);
        if (match != null) {
          output.add(<String, String>{
            'ecosystem': 'pypi',
            'name': match.group(1)!,
            'version': match.group(2) ?? 'unspecified',
          });
        }
      }
    } else if (path.endsWith('pubspec.yaml')) {
      var section = '';
      for (final raw in const LineSplitter().convert(text)) {
        if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*:\s*$').hasMatch(raw)) {
          section = raw.trim().replaceAll(':', '');
        }
        final match = RegExp(
          r'^  ([A-Za-z0-9_.-]+):\s*([^#\s]+)?',
        ).firstMatch(raw);
        if (match != null &&
            const <String>{
              'dependencies',
              'dev_dependencies',
            }.contains(section)) {
          final name = match.group(1)!;
          if (name != 'flutter') {
            output.add(<String, String>{
              'ecosystem': 'pub',
              'name': name,
              'version': match.group(2) ?? 'unspecified',
            });
          }
        }
      }
    } else if (path.endsWith('package-lock.json')) {
      try {
        final decoded = jsonDecode(text);
        final packages = decoded is Map ? decoded['packages'] : null;
        if (packages is Map) {
          packages.forEach((key, value) {
            if (key.toString().isEmpty || value is! Map) {
              return;
            }
            final name =
                value['name']?.toString() ??
                key.toString().split('node_modules/').last;
            final version = value['version']?.toString() ?? 'unspecified';
            output.add(<String, String>{
              'ecosystem': 'npm',
              'name': name,
              'version': version,
            });
          });
        }
      } catch (_) {
        // Invalid lockfiles are handled by project verification; SBOM extraction remains best-effort.
      }
    }
    final unique = <String, Map<String, String>>{};
    for (final component in output) {
      unique['${component['ecosystem']}/${component['name']}@${component['version']}'] =
          component;
    }
    output
      ..clear()
      ..addAll(unique.values);
    output.sort(
      (a, b) => '${a['ecosystem']}/${a['name']}'.compareTo(
        '${b['ecosystem']}/${b['name']}',
      ),
    );
  }

  String _readme(String profile, String projectName) =>
      '''
# $projectName — governed deployment package

This source package was created by Kristin Local Agent $kristinVersion after a bounded secret scan.

Profile: `$profile`

## Required release steps

1. Review `KRISTIN_DEPLOYMENT_MANIFEST.json` and `KRISTIN_SBOM.json`.
2. Supply runtime secrets through environment variables or your deployment platform's secret manager. Never commit `.env` values.
3. Re-run the project's analyzer, tests, and production build in a clean CI environment.
4. Pin dependency versions and verify artifact provenance before deployment.
5. Deploy with a least-privilege service identity, HTTPS, health checks, logging, backups, and rollback configured.

The archive is a deployment input, not proof that a third-party hosting account has accepted or activated the release.
''';
}

class SupportBundleService {
  SupportBundleService({
    required this.directories,
    required this.repositories,
    required this.audit,
    required this.redactor,
  });

  final AppDirectories directories;
  final ProductRepositories repositories;
  final AuditChain audit;
  final SecretRedactor redactor;
  final DeterministicZipWriter zipWriter = const DeterministicZipWriter();

  Future<File> create({
    String? projectId,
    String? runId,
    bool includeAllLogs = false,
  }) async {
    final settings = await repositories.loadSettings();
    final projects = await repositories.projects.all();
    final allRuns = await repositories.runs.all();
    allRuns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final tokens = await repositories.tokens.all();
    final references = await repositories.secretReferences.all();
    final auditStatus = await audit.verify();
    final evidence = await repositories.evidence.all();
    evidence.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final focusedRuns = allRuns
        .where((run) {
          if (runId != null && runId.trim().isNotEmpty) {
            return run.id == runId;
          }
          if (projectId != null && projectId.trim().isNotEmpty) {
            return run.command.contract.projectId == projectId;
          }
          return true;
        })
        .toList(growable: false);
    final includedRunIds = (includeAllLogs ? allRuns : focusedRuns.take(200))
        .map((run) => run.id)
        .toSet();
    final includedEvidence = evidence
        .where((item) => includedRunIds.contains(item.runId))
        .take(includeAllLogs ? 5000 : 1000)
        .toList(growable: false);

    final generatedAt = DateTime.now().toUtc();
    final entries = <ZipEntryData>[];
    final inventory = <Map<String, dynamic>>[];

    void addEntry(String name, List<int> bytes, {bool truncated = false}) {
      entries.add(ZipEntryData(name, bytes));
      inventory.add(<String, dynamic>{
        'name': name,
        'bytes': bytes.length,
        'sha256': Sha256.hex(bytes),
        'truncated': truncated,
      });
    }

    void addJson(String name, Object? value) {
      addEntry(
        name,
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(_sanitize(value))}\n',
        ),
      );
    }

    addJson('diagnostics.json', <String, dynamic>{
      'schema': 'kristin.diagnostics.bundle.v2',
      'product': 'Kristin Local Agent',
      'version': kristinVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'platform': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'focus': <String, dynamic>{
        'projectId': projectId,
        'runId': runId,
        'includeAllLogs': includeAllLogs,
      },
      'settings': <String, dynamic>{
        'apiEnabled': settings.apiEnabled,
        'apiPort': settings.apiPort,
        'allowedOrigins': settings.allowedOrigins.toList()..sort(),
        'ollamaBaseUrl': _originOnly(settings.ollamaBaseUrl),
        'ollamaLoadTimeoutSeconds': settings.ollamaLoadTimeoutSeconds,
        'ollamaLoadRetries': settings.ollamaLoadRetries,
        'ollamaKeepAliveMinutes': settings.ollamaKeepAliveMinutes,
        'openAiCompatibleBaseUrl': _originOnly(
          settings.openAiCompatibleBaseUrl,
        ),
        'hasOpenAiSecretReference': settings.openAiApiKeyReferenceId.isNotEmpty,
        'localOnly': settings.localOnly,
        'allowPackageNetwork': settings.allowPackageNetwork,
      },
      'projects': projects
          .map(
            (project) => <String, dynamic>{
              'id': project.id,
              'name': project.name,
              'pathFingerprint': Sha256.text(project.rootPath),
              'pathLeaf': project.rootPath
                  .replaceAll('\\', '/')
                  .split('/')
                  .last,
              'createdAt': project.createdAt.toIso8601String(),
              'updatedAt': project.updatedAt.toIso8601String(),
            },
          )
          .toList(),
      'runCounts': <String, int>{
        for (final state in RunState.values)
          state.name: allRuns.where((run) => run.state == state).length,
      },
      'security': <String, dynamic>{
        'apiTokenRecords': tokens.length,
        'activeApiTokens': tokens.where((token) => token.isActive).length,
        'secretReferences': references
            .map(
              (reference) => <String, dynamic>{
                'id': reference.id,
                'label': reference.label,
                'environmentKey': reference.environmentKey,
              },
            )
            .toList(),
        'audit': auditStatus,
      },
      'privacy': <String, dynamic>{
        'secretRedactionApplied': true,
        'largeTextBounded': true,
        'sourceLikePayloadsReplacedByHashes': true,
        'reviewBeforeSharing': true,
      },
    });

    addJson(
      'runs-redacted.json',
      (includeAllLogs ? allRuns : focusedRuns.take(200))
          .map((run) => run.toJson())
          .toList(),
    );
    addJson(
      'evidence-redacted.json',
      includedEvidence.map((item) => item.toJson()).toList(),
    );

    final eventsResult = await _redactedJsonLines(
      repositories.eventFile,
      maxBytes: includeAllLogs ? 32 * 1024 * 1024 : 2 * 1024 * 1024,
    );
    if (eventsResult.bytes.isNotEmpty) {
      addEntry(
        'events-redacted.jsonl',
        eventsResult.bytes,
        truncated: eventsResult.truncated,
      );
    }
    final summaryRuns = (focusedRuns.isNotEmpty ? focusedRuns : allRuns)
        .take(includeAllLogs ? 50 : 20)
        .toList(growable: false);
    addEntry(
      'run-diagnostic-summary.md',
      utf8.encode(
        _buildRunDiagnosticSummary(
          summaryRuns,
          includedEvidence,
          eventsResult.bytes,
          generatedAt: generatedAt,
        ),
      ),
    );
    final auditResult = await _redactedJsonLines(
      repositories.auditFile,
      maxBytes: includeAllLogs ? 32 * 1024 * 1024 : 2 * 1024 * 1024,
    );
    if (auditResult.bytes.isNotEmpty) {
      addEntry(
        'audit-redacted.jsonl',
        auditResult.bytes,
        truncated: auditResult.truncated,
      );
    }

    await _addManagedProcessLogs(
      (name, bytes, truncated) => addEntry(name, bytes, truncated: truncated),
      includeAllLogs: includeAllLogs,
    );

    addEntry(
      'README.md',
      utf8.encode('''# Kristin diagnostic log bundle

This archive was created by Kristin Local Agent $kristinVersion at ${generatedAt.toIso8601String()}.

It contains redacted run records, evidence metadata, event logs, audit logs, and bounded managed-process output. It does not intentionally include project files or complete model-response bodies. Source-like payload fields are replaced by a hash and size summary.

Review the archive before sharing it. It can still contain project names, request text, URLs, relative paths, command output, error messages, and bounded model-response previews that are useful for debugging.

Focus project: ${projectId ?? 'all'}
Focus run: ${runId ?? 'all'}
All retained logs requested: $includeAllLogs
'''),
    );

    final manifest = <String, dynamic>{
      'schema': 'kristin.diagnostics.manifest.v2',
      'productVersion': kristinVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'entries': inventory,
      'limits': <String, dynamic>{
        'eventLogBytes': includeAllLogs ? 32 * 1024 * 1024 : 2 * 1024 * 1024,
        'auditLogBytes': includeAllLogs ? 32 * 1024 * 1024 : 2 * 1024 * 1024,
        'evidenceRecords': includeAllLogs ? 5000 : 1000,
        'largeStringPreviewCharacters': 2000,
      },
    };
    addJson('bundle-manifest.json', manifest);

    await directories.support.create(recursive: true);
    final output = File(
      '${directories.support.path}${Platform.pathSeparator}'
      'kristin-diagnostics-${generatedAt.millisecondsSinceEpoch}.zip',
    );
    await zipWriter.write(output, entries);
    return output;
  }

  String _buildRunDiagnosticSummary(
    List<RunRecord> runs,
    List<EvidenceRecord> evidence,
    List<int> eventBytes, {
    required DateTime generatedAt,
  }) {
    final runIds = runs.map((run) => run.id).toSet();
    final timeline = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(
      utf8.decode(eventBytes, allowMalformed: true),
    )) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) {
          continue;
        }
        final event = mapValue(decoded);
        final data = mapValue(event['data']);
        final correlationId = event['correlationId']?.toString() ?? '';
        final eventRunId = data['runId']?.toString() ?? '';
        if (runIds.contains(correlationId) || runIds.contains(eventRunId)) {
          timeline.add(event);
        }
      } catch (_) {
        // The complete redacted JSONL retains malformed-record hashes.
      }
    }

    String compact(Object? value, {int limit = 1200}) {
      final sanitized = _sanitize(value);
      final text = sanitized is String ? sanitized : jsonEncode(sanitized);
      final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return oneLine.length <= limit
          ? oneLine
          : '${oneLine.substring(0, limit)}…';
    }

    final output = StringBuffer()
      ..writeln('# Kristin run diagnostic summary')
      ..writeln()
      ..writeln('Generated: ${generatedAt.toIso8601String()}')
      ..writeln('Product: Kristin Local Agent $kristinVersion')
      ..writeln('Runs summarized: ${runs.length}')
      ..writeln('Related retained events: ${timeline.length}')
      ..writeln();

    if (runs.isEmpty) {
      output
        ..writeln('No run matched the selected project or run filter.')
        ..writeln();
    }

    for (final run in runs) {
      final remainingModelRequests = max(
        0,
        run.budget.maxModelRequests - run.modelRequests,
      );
      output
        ..writeln('## Run `${run.id}`')
        ..writeln()
        ..writeln('- State: `${run.state.name}`')
        ..writeln('- Source run: `${run.sourceRunId ?? 'none'}`')
        ..writeln('- Project: `${run.command.contract.projectId}`')
        ..writeln('- Mode: `${run.command.contract.mode.name}`')
        ..writeln(
          '- Model: `${compact(run.command.model.toJson(), limit: 500)}`',
        )
        ..writeln('- Created: `${run.createdAt.toIso8601String()}`')
        ..writeln('- Updated: `${run.updatedAt.toIso8601String()}`')
        ..writeln(
          '- Request: ${compact(run.command.contract.request, limit: 2000)}',
        )
        ..writeln('- Summary: ${compact(run.summary, limit: 2000)}')
        ..writeln('- Failure: ${compact(run.failure ?? '', limit: 2000)}')
        ..writeln(
          '- Model requests: `${run.modelRequests}/${run.budget.maxModelRequests}` '
          '(remaining `$remainingModelRequests`)',
        )
        ..writeln('- Tool calls: `${run.toolCalls}/${run.budget.maxToolCalls}`')
        ..writeln('- Mutations: `${run.mutations}/${run.budget.maxMutations}`')
        ..writeln('- Repairs: `${run.repairs}/${run.budget.maxRepairs}`')
        ..writeln(
          '- Agent turns per attempt: `${run.budget.maxAgentTurnsPerAttempt}`',
        )
        ..writeln();

      output.writeln('### Work items');
      for (final item in run.items) {
        output.writeln(
          '- `${item.item.id}` · **${item.state.name}** · attempts '
          '`${item.attempts}/${item.item.maxAttempts}` · '
          '${compact(item.item.title, limit: 300)}',
        );
        if ((item.lastError ?? '').trim().isNotEmpty) {
          output.writeln(
            '  - Last error: ${compact(item.lastError, limit: 1000)}',
          );
        }
      }
      output.writeln();

      final runEvidence = evidence
          .where((item) => item.runId == run.id)
          .take(200)
          .toList(growable: false);
      output.writeln('### Evidence (${runEvidence.length})');
      for (final item in runEvidence) {
        output.writeln(
          '- `${item.createdAt.toIso8601String()}` · `${item.kind.name}` · '
          '`${item.id}` · ${compact(item.summary, limit: 700)}',
        );
      }
      output.writeln();

      final runTimeline = timeline
          .where((event) {
            final data = mapValue(event['data']);
            return event['correlationId']?.toString() == run.id ||
                data['runId']?.toString() == run.id;
          })
          .take(500)
          .toList(growable: false);
      final memoryPolicyTimeline = runTimeline
          .where(
            (event) =>
                event['type']?.toString() == 'knowledge.context_policy_applied',
          )
          .toList(growable: false);
      output.writeln('### Automatic memory policy');
      if (memoryPolicyTimeline.isEmpty) {
        output.writeln(
          '- No automatic-memory policy event was retained for this run.',
        );
      } else {
        for (final event in memoryPolicyTimeline) {
          output.writeln(
            '- `${event['timestamp']}` · ${compact(event['data'], limit: 1200)}',
          );
        }
      }
      output.writeln();

      final protocolTimeline = runTimeline
          .where(
            (event) => const <String>{
              'model.protocol_repair_requested',
              'model.protocol_fallback_applied',
              'model.protocol_exhausted',
            }.contains(event['type']?.toString()),
          )
          .toList(growable: false);
      output.writeln('### Model protocol recovery');
      if (protocolTimeline.isEmpty) {
        output.writeln(
          '- No model-protocol recovery event was retained for this run.',
        );
      } else {
        for (final event in protocolTimeline) {
          output.writeln(
            '- `${event['timestamp']}` · `${event['type']}` · '
            '${compact(event['data'], limit: 1400)}',
          );
        }
      }
      output.writeln();

      final modelAvailabilityTimeline = runTimeline
          .where(
            (event) => const <String>{
              'model.load_started',
              'model.load_retry_started',
              'model.load_retry_scheduled',
              'model.load_completed',
              'model.generation_started',
              'model.request_failed',
            }.contains(event['type']?.toString()),
          )
          .toList(growable: false);
      output.writeln('### Model availability and cold-load recovery');
      if (modelAvailabilityTimeline.isEmpty) {
        output.writeln(
          '- No model-load recovery event was retained for this run.',
        );
      } else {
        for (final event in modelAvailabilityTimeline) {
          output.writeln(
            '- `${event['timestamp']}` · `${event['type']}` · '
            '${compact(event['data'], limit: 1400)}',
          );
        }
      }
      output.writeln();

      final loopTimeline = runTimeline
          .where(
            (event) => const <String>{
              'agent.repeated_tool_call_blocked',
              'agent.loop_recovery_redirected',
              'agent.loop_recovery_completed',
              'agent.stalled_repeated_tool_outcome',
            }.contains(event['type']?.toString()),
          )
          .toList(growable: false);
      output.writeln('### Agent loop recovery');
      if (loopTimeline.isEmpty) {
        output.writeln(
          '- No repeated-tool loop event was retained for this run.',
        );
      } else {
        for (final event in loopTimeline) {
          final eventTimestamp = event['timestamp']?.toString() ?? '';
          final eventType = event['type']?.toString() ?? 'unknown';
          output.writeln(
            '- `$eventTimestamp` · `$eventType` · '
            '${compact(event['data'], limit: 1400)}',
          );
        }
      }
      output.writeln();

      final artifactTimeline = runTimeline
          .where(
            (event) => const <String>{
              'work_item.artifact_scope_correction',
              'work_item.artifact_evidence_completed',
            }.contains(event['type']?.toString()),
          )
          .toList(growable: false);
      output.writeln('### Artifact scope and convergence');
      if (artifactTimeline.isEmpty) {
        output.writeln(
          '- No product-artifact scope correction was retained for this run.',
        );
      } else {
        for (final event in artifactTimeline) {
          final eventTimestamp = event['timestamp']?.toString() ?? '';
          output.writeln(
            '- `$eventTimestamp` · `${event['type']}` · '
            '${compact(event['data'], limit: 1400)}',
          );
        }
      }
      output.writeln();

      final pathTimeline = runTimeline
          .where(
            (event) => const <String>{
              'tool.path_rebased_to_active_project',
              'tool.path_recovery_rejected',
            }.contains(event['type']?.toString()),
          )
          .toList(growable: false);
      output.writeln('### Project path recovery');
      if (pathTimeline.isEmpty) {
        output.writeln('- No external tool path was rebased for this run.');
      } else {
        for (final event in pathTimeline) {
          final eventTimestamp = event['timestamp']?.toString() ?? '';
          output.writeln(
            '- `$eventTimestamp` · `${event['type']}` · '
            '${compact(event['data'], limit: 1400)}',
          );
        }
      }
      output.writeln();

      output.writeln('### Event timeline');
      for (final event in runTimeline) {
        final eventTimestamp = event['timestamp']?.toString() ?? '';
        final eventType = event['type']?.toString() ?? 'unknown';
        output.writeln(
          '- `$eventTimestamp` · `$eventType` · '
          '${compact(event['data'], limit: 1000)}',
        );
      }
      output.writeln();
    }

    output
      ..writeln('## Privacy note')
      ..writeln()
      ..writeln(
        'This summary is redacted and bounded, but it can still contain project '
        'names, request text, URLs, relative paths, error messages, command '
        'output, and model-response previews. Review the complete ZIP before sharing.',
      );
    return output.toString();
  }

  Future<_BundleFileResult> _redactedJsonLines(
    File file, {
    required int maxBytes,
  }) async {
    if (!await file.exists()) {
      return const _BundleFileResult(<int>[], false);
    }
    final bytes = await file.readAsBytes();
    final truncated = bytes.length > maxBytes;
    final selected = truncated ? bytes.sublist(bytes.length - maxBytes) : bytes;
    final output = StringBuffer();
    for (final line in const LineSplitter().convert(
      utf8.decode(selected, allowMalformed: true),
    )) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        output.writeln(jsonEncode(_sanitize(jsonDecode(line))));
      } catch (_) {
        output.writeln(
          jsonEncode(<String, dynamic>{
            'omittedMalformedRecord': true,
            'sha256': Sha256.text(line),
            'characters': line.length,
          }),
        );
      }
    }
    return _BundleFileResult(utf8.encode(output.toString()), truncated);
  }

  Future<void> _addManagedProcessLogs(
    void Function(String name, List<int> bytes, bool truncated) addEntry, {
    required bool includeAllLogs,
  }) async {
    final directory = Directory(
      '${directories.logs.path}${Platform.pathSeparator}managed-processes',
    );
    if (!await directory.exists()) {
      return;
    }
    final files = await directory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final perFileLimit = includeAllLogs ? 1024 * 1024 : 256 * 1024;
    final fileLimit = includeAllLogs ? 200 : 40;
    for (final file in files.take(fileLimit)) {
      final bytes = await file.readAsBytes();
      final truncated = bytes.length > perFileLimit;
      final selected = truncated
          ? bytes.sublist(bytes.length - perFileLimit)
          : bytes;
      final relative = file.path
          .substring(directory.path.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '')
          .replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '_');
      if (relative.isEmpty || relative.split('/').contains('..')) {
        continue;
      }
      final text = redactor.redact(utf8.decode(selected, allowMalformed: true));
      addEntry('managed-processes/$relative', utf8.encode(text), truncated);
    }
  }

  Object? _sanitize(Object? value, {String key = ''}) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _sanitize(
            entry.value,
            key: entry.key.toString(),
          ),
      };
    }
    if (value is Iterable) {
      return value.map((item) => _sanitize(item, key: key)).toList();
    }
    if (value is! String) {
      return value;
    }
    final redacted = redactor.redact(value).replaceAll('\u0000', '');
    final lowerKey = key.toLowerCase();
    final sensitiveKey = RegExp(
      r'(?:secret|token|password|credential|authorization|api.?key)',
    ).hasMatch(lowerKey);
    if (sensitiveKey) {
      return '[REDACTED]';
    }
    final sourceLike = RegExp(
      r'^(?:content|rawcontent|filecontent|source|sourcecode|oldtext|newtext|replacement|patch|base64|binary|systemprompt|userprompt|prompt)$',
    ).hasMatch(lowerKey);
    if (sourceLike) {
      return <String, dynamic>{
        'omitted': true,
        'characters': redacted.length,
        'sha256': Sha256.text(redacted),
      };
    }
    if (redacted.length <= 8000) {
      return redacted;
    }
    return <String, dynamic>{
      'truncated': true,
      'characters': redacted.length,
      'sha256': Sha256.text(redacted),
      'preview': '${redacted.substring(0, 2000)}…',
    };
  }

  String _originOnly(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return '';
    }
    return uri
        .replace(path: '', query: null, fragment: null, userInfo: '')
        .toString();
  }
}

class _BundleFileResult {
  const _BundleFileResult(this.bytes, this.truncated);

  final List<int> bytes;
  final bool truncated;
}
