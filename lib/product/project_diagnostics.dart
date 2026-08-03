import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'storage_security.dart';

class ProjectDiagnosticsService {
  ProjectDiagnosticsService({required this.redactor});

  final SecretRedactor redactor;

  Future<ProjectDiagnosticReport> inspect(
    ProjectRecord project, {
    bool modelReady = false,
  }) async {
    final root = Directory(project.rootPath).absolute;
    final checks = <DiagnosticCheck>[];
    if (!await root.exists()) {
      return ProjectDiagnosticReport(
        projectId: project.id,
        projectType: 'Missing project',
        testCommand: '',
        buildCommand: '',
        runCommand: '',
        checks: <DiagnosticCheck>[
          const DiagnosticCheck(
            id: 'project-root',
            title: 'Project folder',
            status: DiagnosticStatus.failed,
            message: 'The registered project folder no longer exists.',
          ),
        ],
        generatedAt: DateTime.now().toUtc(),
      );
    }

    checks.add(
      const DiagnosticCheck(
        id: 'project-root',
        title: 'Project folder',
        status: DiagnosticStatus.passed,
        message: 'The project folder is available.',
      ),
    );

    final profile = await _detectProfile(root);
    final profileWarning =
        profile.type == 'Unknown' || profile.type == 'Invalid custom profile';
    checks.add(
      DiagnosticCheck(
        id: 'project-type',
        title: 'Project type',
        status: profileWarning
            ? DiagnosticStatus.warning
            : DiagnosticStatus.passed,
        message: profile.type == 'Unknown'
            ? 'No supported project profile was detected. Add kristin.project.json or use an agent task to inspect it.'
            : profile.type == 'Invalid custom profile'
            ? 'kristin.project.json could not be parsed. Fix or remove the custom profile.'
            : '${profile.type} project detected.',
      ),
    );

    if (profile.requiredExecutable.isNotEmpty) {
      final resolved = await _findExecutable(
        profile.requiredExecutable,
        workingDirectory: root.path,
      );
      checks.add(
        DiagnosticCheck(
          id: 'toolchain',
          title: 'Required toolchain',
          status: resolved == null
              ? DiagnosticStatus.failed
              : DiagnosticStatus.passed,
          message: resolved == null
              ? '${profile.requiredExecutable} was not found on PATH.'
              : '${profile.requiredExecutable} is available.',
          command: profile.requiredExecutable,
        ),
      );
    }

    checks.add(
      DiagnosticCheck(
        id: 'model',
        title: 'AI model',
        status: modelReady ? DiagnosticStatus.passed : DiagnosticStatus.warning,
        message: modelReady
            ? 'At least one AI model is ready.'
            : 'No AI model is currently discovered. Doctor and project tests still work without a model.',
      ),
    );

    if (profile.analysisCommands.isEmpty) {
      checks.add(
        const DiagnosticCheck(
          id: 'analysis-profile',
          title: 'Analyze command',
          status: DiagnosticStatus.warning,
          message: 'No automatic static-analysis command was detected.',
        ),
      );
    } else {
      checks.add(
        DiagnosticCheck(
          id: 'analysis-profile',
          title: 'Analyze command',
          status: DiagnosticStatus.passed,
          message:
              '${profile.analysisCommands.length} safe analysis command(s) detected.',
          command: profile.analysisCommands
              .map((item) => item.display)
              .join(' && '),
        ),
      );
    }

    if (profile.testCommands.isEmpty) {
      checks.add(
        const DiagnosticCheck(
          id: 'tests',
          title: 'Test command',
          status: DiagnosticStatus.warning,
          message: 'No automatic test command was detected.',
        ),
      );
    } else {
      checks.add(
        DiagnosticCheck(
          id: 'tests',
          title: 'Test command',
          status: DiagnosticStatus.passed,
          message:
              '${profile.testCommands.length} safe test command(s) detected.',
          command: profile.testCommands
              .map((item) => item.display)
              .join(' && '),
        ),
      );
    }

    checks.add(
      DiagnosticCheck(
        id: 'build-profile',
        title: 'Build command',
        status: profile.buildCommand == null
            ? DiagnosticStatus.warning
            : DiagnosticStatus.passed,
        message: profile.buildCommand == null
            ? 'No automatic build command was detected.'
            : 'A safe build command was detected.',
        command: profile.buildCommand?.display ?? '',
      ),
    );
    checks.add(
      DiagnosticCheck(
        id: 'run-profile',
        title: 'Run command',
        status: profile.runCommand == null
            ? DiagnosticStatus.warning
            : DiagnosticStatus.passed,
        message: profile.runCommand == null
            ? 'No automatic run command was detected.'
            : 'A managed run command was detected.',
        command: profile.runCommand?.display ?? '',
      ),
    );

    return _report(project.id, profile, checks);
  }

  Future<ProjectDiagnosticReport> runQuickTests(
    ProjectRecord project, {
    Duration timeoutPerCommand = const Duration(minutes: 8),
  }) async {
    final root = Directory(project.rootPath).absolute;
    final initial = await inspect(project);
    if (!await root.exists() || initial.hasBlockingFailure) {
      return initial;
    }

    final profile = await _detectProfile(root);
    final checks = <DiagnosticCheck>[];
    if (profile.testCommands.isEmpty) {
      checks.add(
        const DiagnosticCheck(
          id: 'tests-unavailable',
          title: 'Quick tests',
          status: DiagnosticStatus.warning,
          message:
              'No safe quick-test profile is available for this project type.',
        ),
      );
      return _report(project.id, profile, <DiagnosticCheck>[
        ...initial.checks.where((check) => check.id != 'tests'),
        ...checks,
      ]);
    }

    for (var index = 0; index < profile.testCommands.length; index++) {
      final command = profile.testCommands[index];
      final started = DateTime.now().toUtc();
      final executable = await _findExecutable(
        command.executable,
        workingDirectory: root.path,
      );
      if (executable == null) {
        checks.add(
          DiagnosticCheck(
            id: 'quick-test-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message: '${command.executable} was not found.',
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      }
      try {
        final result = await _runBounded(
          executable: executable,
          arguments: command.arguments,
          workingDirectory: root.path,
          timeout: timeoutPerCommand,
        );
        final passed = result.exitCode == 0;
        checks.add(
          DiagnosticCheck(
            id: 'quick-test-${index + 1}',
            title: command.label,
            status: passed ? DiagnosticStatus.passed : DiagnosticStatus.failed,
            message: passed
                ? 'Command completed successfully.'
                : 'Command exited with code ${result.exitCode}.',
            command: command.display,
            output: redactor.redact(result.output),
            exitCode: result.exitCode,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        if (!passed) {
          break;
        }
      } on TimeoutException {
        checks.add(
          DiagnosticCheck(
            id: 'quick-test-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message:
                'Command exceeded the ${timeoutPerCommand.inMinutes}-minute limit.',
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      } catch (error) {
        checks.add(
          DiagnosticCheck(
            id: 'quick-test-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message: redactor.redact('$error'),
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      }
    }

    return _report(project.id, profile, <DiagnosticCheck>[
      ...initial.checks.where((check) => check.id != 'tests'),
      ...checks,
    ]);
  }

  Future<ProjectDiagnosticReport> runAnalysis(
    ProjectRecord project, {
    Duration timeoutPerCommand = const Duration(minutes: 8),
  }) async {
    final root = Directory(project.rootPath).absolute;
    final initial = await inspect(project);
    if (!await root.exists() || initial.hasBlockingFailure) {
      return initial;
    }
    final profile = await _detectProfile(root);
    return _runProfileCommands(
      project: project,
      root: root,
      profile: profile,
      initial: initial,
      commands: profile.analysisCommands,
      checkPrefix: 'analysis',
      unavailableTitle: 'Project analysis',
      unavailableMessage:
          'No safe static-analysis command was detected. Add an analyze entry to kristin.project.json to define one.',
      timeoutPerCommand: timeoutPerCommand,
    );
  }

  Future<ProjectDiagnosticReport> runBuild(
    ProjectRecord project, {
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final root = Directory(project.rootPath).absolute;
    final initial = await inspect(project);
    if (!await root.exists() || initial.hasBlockingFailure) {
      return initial;
    }
    final profile = await _detectProfile(root);
    final build = profile.buildCommand;
    return _runProfileCommands(
      project: project,
      root: root,
      profile: profile,
      initial: initial,
      commands: build == null
          ? const <ProjectCommandSpec>[]
          : <ProjectCommandSpec>[build],
      checkPrefix: 'build',
      unavailableTitle: 'Project build',
      unavailableMessage:
          'No safe build command was detected. Add a build entry to kristin.project.json to define one.',
      timeoutPerCommand: timeout,
    );
  }

  Future<ProjectExecutionProfile> executionProfile(
    ProjectRecord project,
  ) async {
    final root = Directory(project.rootPath).absolute;
    if (!await root.exists()) {
      throw ProductException(
        'project_missing',
        'The registered project folder no longer exists.',
      );
    }
    return _detectProfile(root);
  }

  Future<String?> resolveCommandExecutable(
    ProjectRecord project,
    ProjectCommandSpec command,
  ) => _findExecutable(command.executable, workingDirectory: project.rootPath);

  Map<String, String> commandEnvironment(ProjectCommandSpec command) =>
      _safeEnvironment(executable: command.executable);

  Future<ProjectDiagnosticReport> _runProfileCommands({
    required ProjectRecord project,
    required Directory root,
    required ProjectExecutionProfile profile,
    required ProjectDiagnosticReport initial,
    required List<ProjectCommandSpec> commands,
    required String checkPrefix,
    required String unavailableTitle,
    required String unavailableMessage,
    required Duration timeoutPerCommand,
  }) async {
    if (commands.isEmpty) {
      return _report(project.id, profile, <DiagnosticCheck>[
        ...initial.checks,
        DiagnosticCheck(
          id: '$checkPrefix-unavailable',
          title: unavailableTitle,
          status: DiagnosticStatus.warning,
          message: unavailableMessage,
        ),
      ]);
    }

    final checks = <DiagnosticCheck>[];
    for (var index = 0; index < commands.length; index++) {
      final command = commands[index];
      final started = DateTime.now().toUtc();
      final executable = await _findExecutable(
        command.executable,
        workingDirectory: root.path,
      );
      if (executable == null) {
        checks.add(
          DiagnosticCheck(
            id: '$checkPrefix-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message: '${command.executable} was not found.',
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      }
      try {
        final result = await _runBounded(
          executable: executable,
          arguments: command.arguments,
          workingDirectory: root.path,
          timeout: timeoutPerCommand,
        );
        final passed = result.exitCode == 0;
        checks.add(
          DiagnosticCheck(
            id: '$checkPrefix-${index + 1}',
            title: command.label,
            status: passed ? DiagnosticStatus.passed : DiagnosticStatus.failed,
            message: passed
                ? 'Command completed successfully.'
                : 'Command exited with code ${result.exitCode}.',
            command: command.display,
            output: redactor.redact(result.output),
            exitCode: result.exitCode,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        if (!passed) {
          break;
        }
      } on TimeoutException {
        checks.add(
          DiagnosticCheck(
            id: '$checkPrefix-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message:
                'Command exceeded the ${timeoutPerCommand.inMinutes}-minute limit.',
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      } catch (error) {
        checks.add(
          DiagnosticCheck(
            id: '$checkPrefix-${index + 1}',
            title: command.label,
            status: DiagnosticStatus.failed,
            message: redactor.redact('$error'),
            command: command.display,
            durationMs: DateTime.now()
                .toUtc()
                .difference(started)
                .inMilliseconds,
          ),
        );
        break;
      }
    }
    return _report(project.id, profile, <DiagnosticCheck>[
      ...initial.checks,
      ...checks,
    ]);
  }

  Future<String?> pickFolder({
    String prompt = 'Choose a project folder',
  }) async {
    try {
      if (Platform.isWindows) {
        final executable = await _findExecutable('powershell');
        if (executable == null) {
          return null;
        }
        final escaped = prompt.replaceAll("'", "''");
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
\$dialog.Description = '$escaped'
\$dialog.ShowNewFolderButton = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write(\$dialog.SelectedPath)
}
''';
        final result = await Process.run(executable, <String>[
          '-NoProfile',
          '-STA',
          '-Command',
          script,
        ], runInShell: false);
        return _cleanFolderResult(result.stdout?.toString() ?? '');
      }
      if (Platform.isMacOS) {
        final result = await Process.run('osascript', <String>[
          '-e',
          'POSIX path of (choose folder with prompt "${prompt.replaceAll('"', '\\"')}")',
        ], runInShell: false);
        return result.exitCode == 0
            ? _cleanFolderResult(result.stdout?.toString() ?? '')
            : null;
      }

      final zenity = await _findExecutable('zenity');
      if (zenity != null) {
        final result = await Process.run(zenity, <String>[
          '--file-selection',
          '--directory',
          '--title=$prompt',
        ], runInShell: false);
        return result.exitCode == 0
            ? _cleanFolderResult(result.stdout?.toString() ?? '')
            : null;
      }
      final kdialog = await _findExecutable('kdialog');
      if (kdialog != null) {
        final result = await Process.run(kdialog, <String>[
          '--getexistingdirectory',
          Directory.current.path,
          '--title',
          prompt,
        ], runInShell: false);
        return result.exitCode == 0
            ? _cleanFolderResult(result.stdout?.toString() ?? '')
            : null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _cleanFolderResult(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    var end = trimmed.length;
    while (end > 1) {
      final codeUnit = trimmed.codeUnitAt(end - 1);
      final isSeparator = codeUnit == 0x2f || codeUnit == 0x5c;
      if (!isSeparator || _isWindowsDriveRoot(trimmed, end)) {
        break;
      }
      end -= 1;
    }
    return trimmed.substring(0, end);
  }

  bool _isWindowsDriveRoot(String value, int end) {
    if (end != 3 || value.codeUnitAt(1) != 0x3a) {
      return false;
    }
    final drive = value.codeUnitAt(0);
    final isAsciiLetter =
        (drive >= 0x41 && drive <= 0x5a) || (drive >= 0x61 && drive <= 0x7a);
    return isAsciiLetter;
  }

  ProjectDiagnosticReport _report(
    String projectId,
    ProjectExecutionProfile profile,
    List<DiagnosticCheck> checks,
  ) => ProjectDiagnosticReport(
    projectId: projectId,
    projectType: profile.type,
    analyzeCommand: profile.analysisCommands
        .map((item) => item.display)
        .join(' && '),
    testCommand: profile.testCommands.map((item) => item.display).join(' && '),
    buildCommand: profile.buildCommand?.display ?? '',
    runCommand: profile.runCommand?.display ?? '',
    checks: List<DiagnosticCheck>.unmodifiable(checks),
    generatedAt: DateTime.now().toUtc(),
  );

  Future<ProjectExecutionProfile> _detectProfile(Directory root) async {
    bool exists(String relative) =>
        File('${root.path}${Platform.pathSeparator}$relative').existsSync();

    final custom = await _customProfile(root);
    if (custom != null) {
      return custom;
    }

    if (exists('pubspec.yaml')) {
      final pubspec = await File(
        '${root.path}${Platform.pathSeparator}pubspec.yaml',
      ).readAsString();
      final isFlutter =
          RegExp(r'sdk:\s*flutter').hasMatch(pubspec) ||
          RegExp(r'^flutter:\s*$', multiLine: true).hasMatch(pubspec);
      if (!isFlutter) {
        return const ProjectExecutionProfile(
          type: 'Dart',
          requiredExecutable: 'dart',
          analysisCommands: <ProjectCommandSpec>[
            ProjectCommandSpec('Dart analysis', 'dart', <String>['analyze']),
          ],
          testCommands: <ProjectCommandSpec>[
            ProjectCommandSpec('Dart analysis', 'dart', <String>['analyze']),
            ProjectCommandSpec('Dart tests', 'dart', <String>['test']),
          ],
          runCommand: ProjectCommandSpec('Dart application', 'dart', <String>[
            'run',
          ]),
        );
      }
      final desktopTarget = Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'linux';
      return ProjectExecutionProfile(
        type: 'Flutter',
        requiredExecutable: 'flutter',
        analysisCommands: const <ProjectCommandSpec>[
          ProjectCommandSpec('Flutter analysis', 'flutter', <String>[
            'analyze',
          ]),
        ],
        testCommands: const <ProjectCommandSpec>[
          ProjectCommandSpec('Flutter analysis', 'flutter', <String>[
            'analyze',
          ]),
          ProjectCommandSpec('Flutter tests', 'flutter', <String>['test']),
        ],
        buildCommand: ProjectCommandSpec(
          'Flutter desktop build',
          'flutter',
          <String>['build', desktopTarget],
        ),
        runCommand: ProjectCommandSpec(
          'Flutter desktop run',
          'flutter',
          <String>['run', '-d', desktopTarget],
        ),
      );
    }

    if (exists('package.json')) {
      final scripts = await _packageScripts(root);
      final tests = <ProjectCommandSpec>[];
      final analysis = <ProjectCommandSpec>[];
      if (scripts.contains('test')) {
        tests.add(
          const ProjectCommandSpec('JavaScript tests', 'npm', <String>['test']),
        );
      }
      if (scripts.contains('lint')) {
        const lint = ProjectCommandSpec('JavaScript lint', 'npm', <String>[
          'run',
          'lint',
        ]);
        analysis.add(lint);
        tests.insert(0, lint);
      }
      if (scripts.contains('typecheck')) {
        analysis.add(
          const ProjectCommandSpec('JavaScript typecheck', 'npm', <String>[
            'run',
            'typecheck',
          ]),
        );
      }
      final build = scripts.contains('build')
          ? const ProjectCommandSpec('JavaScript build', 'npm', <String>[
              'run',
              'build',
            ])
          : null;
      final runScript = scripts.contains('dev')
          ? 'dev'
          : scripts.contains('start')
          ? 'start'
          : '';
      return ProjectExecutionProfile(
        type: 'Node.js / JavaScript',
        requiredExecutable: 'npm',
        analysisCommands: analysis,
        testCommands: tests,
        buildCommand: build,
        runCommand: runScript.isEmpty
            ? null
            : ProjectCommandSpec('Node application', 'npm', <String>[
                'run',
                runScript,
              ]),
      );
    }

    if (exists('pyproject.toml') ||
        exists('requirements.txt') ||
        exists('setup.py')) {
      final runFile = <String>[
        'main.py',
        'app.py',
        'server.py',
      ].where(exists).firstOrNull;
      final pythonExecutable = Platform.isWindows ? 'python' : 'python3';
      return ProjectExecutionProfile(
        type: 'Python',
        requiredExecutable: pythonExecutable,
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec(
            'Python compile check',
            pythonExecutable,
            const <String>['-m', 'compileall', '-q', '.'],
          ),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Python tests', pythonExecutable, const <String>[
            '-m',
            'pytest',
            '-q',
          ]),
        ],
        buildCommand: ProjectCommandSpec(
          'Python package build',
          pythonExecutable,
          const <String>['-m', 'build'],
        ),
        runCommand: runFile == null
            ? null
            : ProjectCommandSpec(
                'Python application',
                pythonExecutable,
                <String>[runFile],
              ),
      );
    }

    if (exists('go.mod')) {
      return const ProjectExecutionProfile(
        type: 'Go',
        requiredExecutable: 'go',
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Go vet', 'go', <String>['vet', './...']),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Go tests', 'go', <String>['test', './...']),
        ],
        buildCommand: ProjectCommandSpec('Go build', 'go', <String>[
          'build',
          './...',
        ]),
        runCommand: ProjectCommandSpec('Go run', 'go', <String>['run', '.']),
      );
    }

    if (exists('Cargo.toml')) {
      return const ProjectExecutionProfile(
        type: 'Rust',
        requiredExecutable: 'cargo',
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Rust check', 'cargo', <String>['check']),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Rust tests', 'cargo', <String>['test']),
        ],
        buildCommand: ProjectCommandSpec('Rust build', 'cargo', <String>[
          'build',
        ]),
        runCommand: ProjectCommandSpec('Rust run', 'cargo', <String>['run']),
      );
    }

    var dotnetProject = false;
    try {
      dotnetProject = root
          .listSync(followLinks: false)
          .whereType<File>()
          .any(
            (file) =>
                file.path.toLowerCase().endsWith('.sln') ||
                file.path.toLowerCase().endsWith('.csproj'),
          );
    } on FileSystemException {
      // The root availability check already reports access problems. Profile
      // detection should degrade to Unknown instead of crashing Doctor.
    }
    if (dotnetProject) {
      return const ProjectExecutionProfile(
        type: '.NET',
        requiredExecutable: 'dotnet',
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('.NET build analysis', 'dotnet', <String>[
            'build',
            '--nologo',
          ]),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('.NET tests', 'dotnet', <String>[
            'test',
            '--nologo',
          ]),
        ],
        buildCommand: ProjectCommandSpec('.NET build', 'dotnet', <String>[
          'build',
          '--nologo',
        ]),
        runCommand: ProjectCommandSpec('.NET run', 'dotnet', <String>['run']),
      );
    }

    if (exists('pom.xml')) {
      return const ProjectExecutionProfile(
        type: 'Java / Maven',
        requiredExecutable: 'mvn',
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Maven compile analysis', 'mvn', <String>[
            '-q',
            '-DskipTests',
            'compile',
          ]),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Maven tests', 'mvn', <String>['test']),
        ],
        buildCommand: ProjectCommandSpec('Maven package', 'mvn', <String>[
          'package',
          '-DskipTests',
        ]),
      );
    }

    if (exists('gradlew') ||
        exists('gradlew.bat') ||
        exists('build.gradle') ||
        exists('build.gradle.kts')) {
      final wrapper = Platform.isWindows && exists('gradlew.bat')
          ? r'.\gradlew.bat'
          : exists('gradlew')
          ? './gradlew'
          : 'gradle';
      return ProjectExecutionProfile(
        type: 'Java / Gradle',
        requiredExecutable: wrapper,
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Gradle classes analysis', wrapper, const <String>[
            'classes',
          ]),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('Gradle tests', wrapper, const <String>['test']),
        ],
        buildCommand: ProjectCommandSpec(
          'Gradle build',
          wrapper,
          const <String>['build'],
        ),
      );
    }

    if (exists('CMakeLists.txt')) {
      return const ProjectExecutionProfile(
        type: 'CMake / native',
        requiredExecutable: 'cmake',
        analysisCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('CMake configure analysis', 'cmake', <String>[
            '-S',
            '.',
            '-B',
            'build',
          ]),
        ],
        testCommands: <ProjectCommandSpec>[
          ProjectCommandSpec('CMake configure', 'cmake', <String>[
            '-S',
            '.',
            '-B',
            'build',
          ]),
          ProjectCommandSpec('CMake build', 'cmake', <String>[
            '--build',
            'build',
          ]),
        ],
        buildCommand: ProjectCommandSpec('CMake build', 'cmake', <String>[
          '--build',
          'build',
        ]),
      );
    }

    if (exists('index.html')) {
      final pythonExecutable = Platform.isWindows ? 'python' : 'python3';
      return ProjectExecutionProfile(
        type: 'Static website',
        requiredExecutable: pythonExecutable,
        testCommands: const <ProjectCommandSpec>[],
        runCommand: ProjectCommandSpec(
          'Static preview',
          pythonExecutable,
          const <String>['-m', 'http.server', '8080'],
        ),
      );
    }

    return const ProjectExecutionProfile(
      type: 'Unknown',
      requiredExecutable: '',
      testCommands: <ProjectCommandSpec>[],
    );
  }

  Future<ProjectExecutionProfile?> _customProfile(Directory root) async {
    final file = File(
      '${root.path}${Platform.pathSeparator}kristin.project.json',
    );
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final json = mapValue(decoded);
      ProjectCommandSpec? command(String key, String label) {
        final value = json[key];
        if (value is! Map) {
          return null;
        }
        final data = mapValue(value);
        final executable = data['executable']?.toString().trim() ?? '';
        if (executable.isEmpty) {
          return null;
        }
        return ProjectCommandSpec(
          label,
          executable,
          stringList(data['arguments']),
        );
      }

      final analyze = command('analyze', 'Custom project analysis');
      final test = command('test', 'Custom project tests');
      final build = command('build', 'Custom project build');
      final run = command('run', 'Custom project run');
      final required =
          analyze?.executable ??
          test?.executable ??
          build?.executable ??
          run?.executable ??
          '';
      return ProjectExecutionProfile(
        type: json['type']?.toString().trim().isNotEmpty == true
            ? json['type'].toString().trim()
            : 'Custom',
        requiredExecutable: required,
        analysisCommands: analyze == null
            ? const <ProjectCommandSpec>[]
            : <ProjectCommandSpec>[analyze],
        testCommands: test == null
            ? const <ProjectCommandSpec>[]
            : <ProjectCommandSpec>[test],
        buildCommand: build,
        runCommand: run,
      );
    } catch (_) {
      return const ProjectExecutionProfile(
        type: 'Invalid custom profile',
        requiredExecutable: '',
        testCommands: <ProjectCommandSpec>[],
      );
    }
  }

  Future<Set<String>> _packageScripts(Directory root) async {
    try {
      final file = File('${root.path}${Platform.pathSeparator}package.json');
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return <String>{};
      }
      return mapValue(decoded['scripts']).keys.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<String?> _findExecutable(
    String executable, {
    String? workingDirectory,
  }) async {
    if (executable.isEmpty) {
      return null;
    }
    final hasPath =
        executable.startsWith('./') ||
        executable.startsWith('../') ||
        executable.contains('/') ||
        executable.contains('\\');
    if (hasPath) {
      final base = workingDirectory == null
          ? Directory.current
          : Directory(workingDirectory).absolute;
      final file = File(
        executable.startsWith('/') ||
                (Platform.isWindows &&
                    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(executable))
            ? executable
            : '${base.path}${Platform.pathSeparator}$executable',
      ).absolute;
      return await file.exists() ? file.path : null;
    }
    final candidates = <String>[
      executable,
      if (Platform.isWindows && !executable.toLowerCase().endsWith('.cmd'))
        '$executable.cmd',
      if (Platform.isWindows && !executable.toLowerCase().endsWith('.exe'))
        '$executable.exe',
    ];
    final path = Platform.environment['PATH'] ?? '';
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.trim().isEmpty) {
        continue;
      }
      for (final candidate in candidates) {
        final file = File('$directory${Platform.pathSeparator}$candidate');
        if (await file.exists()) {
          return file.path;
        }
      }
    }
    return null;
  }

  Future<_ProcessOutput> _runBounded({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Duration timeout,
    int maxOutputBytes = 2 * 1024 * 1024,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: _safeEnvironment(executable: executable),
    );
    final output = StringBuffer();
    var bytes = 0;

    Future<void> pump(Stream<List<int>> stream, String name) async {
      await for (final chunk in stream) {
        if (bytes >= maxOutputBytes) {
          continue;
        }
        final remaining = maxOutputBytes - bytes;
        final accepted = chunk.length > remaining
            ? chunk.sublist(0, remaining)
            : chunk;
        bytes += accepted.length;
        output.write('[$name] ${utf8.decode(accepted, allowMalformed: true)}');
      }
    }

    final stdoutPump = pump(process.stdout, 'stdout');
    final stderrPump = pump(process.stderr, 'stderr');
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
    await Future.wait(<Future<void>>[stdoutPump, stderrPump]);
    if (bytes >= maxOutputBytes) {
      output.write('\n[output truncated at $maxOutputBytes bytes]');
    }
    return _ProcessOutput(exitCode, output.toString());
  }

  Map<String, String> _safeEnvironment({required String executable}) {
    const baseAllowed = <String>{
      'PATH',
      'PATHEXT',
      'SYSTEMROOT',
      'SYSTEMDRIVE',
      'WINDIR',
      'COMSPEC',
      'HOME',
      'USERPROFILE',
      'HOMEDRIVE',
      'HOMEPATH',
      'APPDATA',
      'LOCALAPPDATA',
      'PROGRAMDATA',
      'TMP',
      'TEMP',
      'LANG',
      'LC_ALL',
      'CI',
      'OS',
      'PROCESSOR_ARCHITECTURE',
      'PROCESSOR_IDENTIFIER',
      'NUMBER_OF_PROCESSORS',
    };
    const sdkAllowed = <String>{
      'PUB_CACHE',
      'PUB_HOSTED_URL',
      'PUB_ENVIRONMENT',
      'FLUTTER_ROOT',
      'FLUTTER_STORAGE_BASE_URL',
      'DART_SDK',
      'ANDROID_HOME',
      'ANDROID_SDK_ROOT',
      'JAVA_HOME',
      'HTTP_PROXY',
      'HTTPS_PROXY',
      'NO_PROXY',
      'ALL_PROXY',
      'SSL_CERT_FILE',
      'SSL_CERT_DIR',
      'CURL_CA_BUNDLE',
      'REQUESTS_CA_BUNDLE',
      'GIT_SSL_CAINFO',
      'GIT_CONFIG_GLOBAL',
      'GIT_CONFIG_SYSTEM',
      'GIT_SSH',
      'GIT_SSH_COMMAND',
      'SSH_AUTH_SOCK',
      'XDG_CACHE_HOME',
      'XDG_CONFIG_HOME',
      'XDG_DATA_HOME',
    };
    final leaf = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
    final isSdkCommand =
        leaf == 'dart' ||
        leaf == 'dart.exe' ||
        leaf == 'flutter' ||
        leaf == 'flutter.bat';
    final allowed = <String>{...baseAllowed, if (isSdkCommand) ...sdkAllowed};
    return <String, String>{
      for (final entry in Platform.environment.entries)
        if (allowed.contains(entry.key.toUpperCase())) entry.key: entry.value,
    };
  }
}

class ProjectExecutionProfile {
  const ProjectExecutionProfile({
    required this.type,
    required this.requiredExecutable,
    required this.testCommands,
    this.analysisCommands = const <ProjectCommandSpec>[],
    this.buildCommand,
    this.runCommand,
  });

  final String type;
  final String requiredExecutable;
  final List<ProjectCommandSpec> analysisCommands;
  final List<ProjectCommandSpec> testCommands;
  final ProjectCommandSpec? buildCommand;
  final ProjectCommandSpec? runCommand;
}

class ProjectCommandSpec {
  const ProjectCommandSpec(this.label, this.executable, this.arguments);

  final String label;
  final String executable;
  final List<String> arguments;

  String get display => <String>[
    executable,
    ...arguments,
  ].map((value) => value.contains(' ') ? '"$value"' : value).join(' ');
}

class _ProcessOutput {
  const _ProcessOutput(this.exitCode, this.output);

  final int exitCode;
  final String output;
}
