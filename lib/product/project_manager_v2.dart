import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';

class ProjectManagerV2Exception implements Exception {
  const ProjectManagerV2Exception(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class ProjectManagerV2Service {
  ProjectManagerV2Service({
    required this.dataRoot,
    required this.redactor,
    this.pythonExecutable = 'python3',
    this.helperPath,
  });

  final String dataRoot;
  final SecretRedactor redactor;
  final String pythonExecutable;
  final String? helperPath;

  String? _discoverHelper() {
    final explicit = helperPath?.trim() ?? '';
    if (explicit.isNotEmpty && File(explicit).existsSync()) return explicit;
    final candidates = <String>[
      '${Directory.current.path}${Platform.pathSeparator}tool${Platform.pathSeparator}project_manager_v2.py',
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tool${Platform.pathSeparator}project_manager_v2.py',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<Map<String, dynamic>> status(String projectRoot) => _invoke(<String>[
    'status',
    '--project',
    projectRoot,
    '--data-root',
    dataRoot,
    '--json',
  ]);

  Future<Map<String, dynamic>> execute(
    String projectRoot,
    String action, {
    String? runId,
  }) => _invoke(<String>[
    'action',
    action,
    '--project',
    projectRoot,
    '--data-root',
    dataRoot,
    if (runId != null) ...<String>['--run-id', runId],
    '--json',
  ]);

  Future<Map<String, dynamic>> start(String projectRoot, {String? runId}) =>
      _invoke(<String>[
        'start',
        '--project',
        projectRoot,
        '--data-root',
        dataRoot,
        if (runId != null) ...<String>['--run-id', runId],
        '--json',
      ]);

  Future<Map<String, dynamic>> processStatus(String processId) => _invoke(
    <String>['process-status', processId, '--data-root', dataRoot, '--json'],
  );

  Future<Map<String, dynamic>> stop(String processId) =>
      _invoke(<String>['stop', processId, '--data-root', dataRoot, '--json']);

  Future<Map<String, dynamic>> _invoke(List<String> arguments) async {
    final helper = _discoverHelper();
    if (helper == null) {
      throw const ProjectManagerV2Exception(
        'project_manager_helper_unavailable',
        'The sandboxed Project Manager helper is not installed. Host execution is disabled.',
      );
    }
    final result = await Process.run(
      pythonExecutable,
      <String>[helper, ...arguments],
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final stdout = redactor.redact(result.stdout?.toString() ?? '');
    final stderr = redactor.redact(result.stderr?.toString() ?? '');
    Object? decoded;
    try {
      decoded = jsonDecode(stdout.trim().isEmpty ? stderr : stdout);
    } on FormatException {
      throw ProjectManagerV2Exception(
        'project_manager_response_invalid',
        'The Project Manager helper returned an invalid response (${Sha256.text(stdout + stderr)}).',
      );
    }
    final response = decoded is Map
        ? <String, dynamic>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          }
        : <String, dynamic>{};
    if (result.exitCode != 0) {
      throw ProjectManagerV2Exception(
        response['errorCode']?.toString() ?? 'project_manager_failed',
        response['message']?.toString() ??
            'The Project Manager operation failed.',
      );
    }
    return response;
  }
}
