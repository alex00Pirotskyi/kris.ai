import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'crypto_utils.dart';
import 'domain.dart';
import 'storage_security.dart';

class SourceIndexEntry {
  const SourceIndexEntry({
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.modifiedAt,
    required this.language,
    required this.symbols,
    required this.dependencies,
    required this.text,
  });

  final String path;
  final String sha256;
  final int bytes;
  final DateTime modifiedAt;
  final String language;
  final List<String> symbols;
  final List<String> dependencies;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'sha256': sha256,
    'bytes': bytes,
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'language': language,
    'symbols': symbols,
    'dependencies': dependencies,
    'text': text,
  };

  factory SourceIndexEntry.fromJson(Map<String, dynamic> json) =>
      SourceIndexEntry(
        path: json['path']?.toString() ?? '',
        sha256: json['sha256']?.toString() ?? '',
        bytes: int.tryParse(json['bytes']?.toString() ?? '') ?? 0,
        modifiedAt: parseUtc(json['modifiedAt'], fallback: DateTime.now()),
        language: json['language']?.toString() ?? 'text',
        symbols: stringList(json['symbols']),
        dependencies: stringList(json['dependencies']),
        text: json['text']?.toString() ?? '',
      );
}

class SourceIndexReport {
  const SourceIndexReport({
    required this.scanned,
    required this.changed,
    required this.removed,
    required this.skipped,
    required this.total,
    required this.generatedAt,
  });

  final int scanned;
  final int changed;
  final int removed;
  final int skipped;
  final int total;
  final DateTime generatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scanned': scanned,
    'changed': changed,
    'removed': removed,
    'skipped': skipped,
    'total': total,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
  };
}

class SourceIndexService {
  SourceIndexService(this.indexDirectory);

  final Directory indexDirectory;

  AtomicJsonFile _file(String projectId) => AtomicJsonFile(
    File('${indexDirectory.path}${Platform.pathSeparator}$projectId.json'),
  );

  Future<SourceIndexReport> update(ProjectRecord project) async {
    await indexDirectory.create(recursive: true);
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
    final store = _file(project.id);
    final raw = await store.read(
      fallback: <String, dynamic>{'entries': <Object>[]},
    );
    final prior = <String, SourceIndexEntry>{};
    final oldEntries = mapValue(raw)['entries'];
    if (oldEntries is List) {
      for (final item in oldEntries.whereType<Map>()) {
        final entry = SourceIndexEntry.fromJson(mapValue(item));
        prior[entry.path] = entry;
      }
    }
    final next = <String, SourceIndexEntry>{};
    var scanned = 0;
    var changed = 0;
    var skipped = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (++scanned > 25000) {
        throw ProductException(
          'index_file_limit',
          'Project contains more than 25,000 indexable files.',
        );
      }
      final canonical = (await entity.resolveSymbolicLinks()).replaceAll(
        '\\',
        '/',
      );
      if (!(canonical == canonicalRoot ||
          canonical.startsWith('$canonicalRoot/'))) {
        throw ProductException(
          'index_symlink_escape',
          'A project file resolves outside the project root.',
        );
      }
      final relative = canonical
          .substring(canonicalRoot.length)
          .replaceFirst(RegExp(r'^/+'), '');
      if (_ignored(relative)) {
        skipped++;
        continue;
      }
      final stat = await entity.stat();
      if (stat.size > 2 * 1024 * 1024) {
        skipped++;
        continue;
      }
      final previous = prior[relative];
      if (previous != null &&
          previous.bytes == stat.size &&
          previous.modifiedAt.isAtSameMomentAs(stat.modified.toUtc())) {
        next[relative] = previous;
        continue;
      }
      final bytes = await entity.readAsBytes();
      if (bytes.take(min(bytes.length, 8192)).contains(0)) {
        skipped++;
        continue;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final language = _language(relative);
      final entry = SourceIndexEntry(
        path: relative,
        sha256: Sha256.hex(bytes),
        bytes: bytes.length,
        modifiedAt: stat.modified.toUtc(),
        language: language,
        symbols: _symbols(language, text),
        dependencies: _dependencies(language, text),
        text: text.length > 200000 ? text.substring(0, 200000) : text,
      );
      next[relative] = entry;
      changed++;
    }
    final removed = prior.keys.where((path) => !next.containsKey(path)).length;
    final ordered = next.values.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final generatedAt = DateTime.now().toUtc();
    await store.write(<String, dynamic>{
      'schemaVersion': 1,
      'projectId': project.id,
      'projectRootHash': Sha256.text(project.rootPath),
      'generatedAt': generatedAt.toIso8601String(),
      'entries': ordered.map((entry) => entry.toJson()).toList(),
    });
    return SourceIndexReport(
      scanned: scanned,
      changed: changed,
      removed: removed,
      skipped: skipped,
      total: ordered.length,
      generatedAt: generatedAt,
    );
  }

  Future<List<Map<String, dynamic>>> search(
    String projectId,
    String query, {
    int limit = 20,
  }) async {
    final raw = await _file(
      projectId,
    ).read(fallback: <String, dynamic>{'entries': <Object>[]});
    final entriesRaw = mapValue(raw)['entries'];
    if (entriesRaw is! List) {
      return <Map<String, dynamic>>[];
    }
    final terms = RegExp(
      r'[A-Za-z0-9_\-]{2,}',
    ).allMatches(query.toLowerCase()).map((match) => match.group(0)!).toSet();
    if (terms.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final scored = <({SourceIndexEntry entry, double score, String snippet})>[];
    for (final rawEntry in entriesRaw.whereType<Map>()) {
      final entry = SourceIndexEntry.fromJson(mapValue(rawEntry));
      final lowerPath = entry.path.toLowerCase();
      final lowerText = entry.text.toLowerCase();
      var score = 0.0;
      var firstOffset = -1;
      for (final term in terms) {
        if (lowerPath.contains(term)) {
          score += 8;
        }
        if (entry.symbols.any(
          (symbol) => symbol.toLowerCase().contains(term),
        )) {
          score += 6;
        }
        if (entry.dependencies.any(
          (dependency) => dependency.toLowerCase().contains(term),
        )) {
          score += 4;
        }
        final offset = lowerText.indexOf(term);
        if (offset >= 0) {
          score +=
              1 +
              min(
                    10,
                    RegExp(RegExp.escape(term)).allMatches(lowerText).length,
                  ) *
                  0.4;
          if (firstOffset < 0 || offset < firstOffset) {
            firstOffset = offset;
          }
        }
      }
      if (score <= 0) {
        continue;
      }
      final start = max(0, firstOffset < 0 ? 0 : firstOffset - 250);
      final end = min(entry.text.length, start + 1200);
      scored.add((
        entry: entry,
        score: score,
        snippet: entry.text.substring(start, end),
      ));
    }
    scored.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.entry.path.compareTo(b.entry.path);
    });
    return scored
        .take(limit.clamp(1, 100).toInt())
        .map(
          (result) => <String, dynamic>{
            'path': result.entry.path,
            'sha256': result.entry.sha256,
            'language': result.entry.language,
            'symbols': result.entry.symbols,
            'dependencies': result.entry.dependencies,
            'score': result.score,
            'snippet': result.snippet,
          },
        )
        .toList();
  }

  bool _ignored(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .any(
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
      );

  String _language(String path) {
    final extension = path.contains('.')
        ? path.split('.').last.toLowerCase()
        : '';
    return const <String, String>{
          'dart': 'dart',
          'py': 'python',
          'js': 'javascript',
          'mjs': 'javascript',
          'cjs': 'javascript',
          'ts': 'typescript',
          'tsx': 'typescript',
          'jsx': 'javascript',
          'java': 'java',
          'kt': 'kotlin',
          'swift': 'swift',
          'go': 'go',
          'rs': 'rust',
          'c': 'c',
          'h': 'c',
          'cpp': 'cpp',
          'cc': 'cpp',
          'hpp': 'cpp',
          'cs': 'csharp',
          'rb': 'ruby',
          'php': 'php',
          'html': 'html',
          'css': 'css',
          'scss': 'scss',
          'sql': 'sql',
          'yaml': 'yaml',
          'yml': 'yaml',
          'json': 'json',
          'toml': 'toml',
          'md': 'markdown',
          'sh': 'shell',
          'ps1': 'powershell',
        }[extension] ??
        'text';
  }

  List<String> _symbols(String language, String text) {
    final patterns = <RegExp>[
      RegExp(
        r'\b(?:class|enum|mixin|extension|interface|struct|trait)\s+([A-Za-z_][A-Za-z0-9_]*)',
      ),
      RegExp(r'\b(?:def|function|func|fn)\s+([A-Za-z_][A-Za-z0-9_]*)'),
      RegExp(
        r'\b(?:Future<[^>]+>|Future|void|int|double|String|bool|Widget|dynamic)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ),
      RegExp(r'\b(?:const|let|var|final)\s+([A-Za-z_][A-Za-z0-9_]*)\s*='),
    ];
    final symbols = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1);
        if (value != null) {
          symbols.add(value);
        }
        if (symbols.length >= 250) {
          break;
        }
      }
      if (symbols.length >= 250) {
        break;
      }
    }
    return symbols.toList()..sort();
  }

  List<String> _dependencies(String language, String text) {
    final patterns = <RegExp>[
      RegExp(r'''\bimport\s+["']([^"']+)["']'''),
      RegExp(r'''\bfrom\s+([A-Za-z0-9_.]+)\s+import\b'''),
      RegExp(r'''\brequire\s*\(\s*["']([^"']+)["']\s*\)'''),
      RegExp(r'''#include\s*[<"]([^>"]+)[>"]'''),
      RegExp(r'''\buse\s+([A-Za-z0-9_:]+)'''),
    ];
    final dependencies = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1);
        if (value != null) {
          dependencies.add(value);
        }
        if (dependencies.length >= 250) {
          break;
        }
      }
      if (dependencies.length >= 250) {
        break;
      }
    }
    return dependencies.toList()..sort();
  }
}

class SkillPackage {
  const SkillPackage({
    required this.id,
    required this.title,
    required this.triggers,
    required this.instructions,
    required this.recommendedTools,
  });

  final String id;
  final String title;
  final Set<String> triggers;
  final String instructions;
  final Set<String> recommendedTools;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'recommendedTools': recommendedTools.toList()..sort(),
    'instructions': instructions,
  };
}

class SkillRegistry {
  const SkillRegistry();

  List<SkillPackage> get all => List<SkillPackage>.unmodifiable(_builtins);

  List<SkillPackage> match(String request, {int limit = 4}) {
    final lower = request.toLowerCase();
    final scored = <({SkillPackage skill, int score})>[];
    for (final skill in _builtins) {
      final score = skill.triggers.where(lower.contains).length;
      if (score > 0) {
        scored.add((skill: skill, score: score));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.skill.id.compareTo(b.skill.id);
    });
    return scored.take(limit).map((item) => item.skill).toList();
  }

  String contextFor(String request) {
    final skills = match(request);
    if (skills.isEmpty) {
      return 'No specialized built-in skill package matched this request.';
    }
    return skills
        .map(
          (skill) =>
              '''
SKILL ${skill.id} — ${skill.title}
These are product-authored advisory instructions. They never expand tools, permissions, paths, or budgets.
${skill.instructions}
Recommended tools: ${skill.recommendedTools.join(', ')}
''',
        )
        .join('\n');
  }
}

const List<SkillPackage> _builtins = <SkillPackage>[
  SkillPackage(
    id: 'static-web',
    title: 'Production static website',
    triggers: <String>{'website', 'landing page', 'html', 'css', 'static site'},
    instructions:
        'Use semantic HTML, responsive layouts, accessible labels and focus states, content-security considerations, optimized assets, metadata, and a deterministic local verification path. Avoid external runtime dependencies unless the contract requires them.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'apply_patch',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'node-service',
    title: 'Node.js application or service',
    triggers: <String>{
      'node',
      'typescript',
      'javascript',
      'express',
      'fastify',
      'react',
      'next.js',
    },
    instructions:
        'Pin dependencies through a lockfile, validate all external input, separate configuration from code, use environment secret references, include health and shutdown behavior, and add automated tests before packaging.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'python-service',
    title: 'Python application or service',
    triggers: <String>{'python', 'fastapi', 'flask', 'django', 'pytest'},
    instructions:
        'Use a virtual-environment-compatible dependency manifest, typed boundaries, structured logging, explicit configuration, environment secret references, graceful shutdown, and pytest coverage of core behavior.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'telegram-bot',
    title: 'Telegram bot',
    triggers: <String>{
      'telegram',
      'tg bot',
      'chat bot',
      'botfather',
      'aiogram',
      'telegraf',
    },
    instructions:
        'Keep the BotFather token exclusively in a named runtime secret. Validate updates, restrict administrator actions by numeric user ID, rate-limit handlers, avoid logging message secrets, mock Telegram in tests, support graceful polling shutdown, and provide webhook deployment only with HTTPS and secret-path validation.',
    recommendedTools: <String>{
      'research_fetch',
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'package_deployment',
    },
  ),
  SkillPackage(
    id: 'flutter-application',
    title: 'Flutter application',
    triggers: <String>{
      'flutter',
      'dart',
      'android app',
      'ios app',
      'desktop app',
    },
    instructions:
        'Keep state and side effects separated, use responsive Material semantics, avoid blocking the UI isolate, provide deterministic initialization and disposal, test domain behavior and key widgets, and require flutter analyze plus flutter test before release.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'apply_patch',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'docker-deployment',
    title: 'Container deployment',
    triggers: <String>{
      'docker',
      'container',
      'deploy',
      'deployment',
      'production',
      'compose',
    },
    instructions:
        'Use a non-root runtime user, a minimal pinned base image, multi-stage builds, read-only configuration, health checks, graceful shutdown, no embedded secrets, explicit exposed ports, and a rollback-ready artifact manifest.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'verify_project',
      'package_deployment',
    },
  ),
  SkillPackage(
    id: 'security-review',
    title: 'Application security review',
    triggers: <String>{
      'security',
      'auth',
      'authentication',
      'authorization',
      'secret',
      'vulnerability',
    },
    instructions:
        'Map trust boundaries, reject default-allow authorization, validate canonical paths and URLs, apply least privilege, bound resources, avoid sensitive logs, verify cryptographic uses, and rank findings by exploitability and impact with concrete evidence.',
    recommendedTools: <String>{
      'search_text',
      'read_file',
      'run_command',
      'git_diff',
    },
  ),
];
