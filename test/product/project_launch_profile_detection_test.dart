import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/project_diagnostics.dart';
import 'package:kristin_local_agent/product/project_launch_profile_detection.dart';

void main() {
  group('end-to-end detection from real project fixtures', () {
    late Directory root;
    late ProjectDiagnosticsService diagnostics;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-launch-detect-');
      diagnostics = ProjectDiagnosticsService(redactor: SecretRedactor());
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    ProjectRecord projectAt(Directory dir) {
      final now = DateTime.utc(2026, 8, 26);
      return ProjectRecord(
        id: 'fixture',
        name: 'fixture',
        rootPath: dir.path,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('a Flutter project (pubspec.yaml) detects as a desktop launch kind',
        () async {
      await File(
        '${root.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsString('name: fixture\nflutter:\n  sdk: flutter\n');
      final profile = await diagnostics.executionProfile(projectAt(root));
      expect(profile.type, 'Flutter');
      expect(profile.runCommand, isNotNull);
      expect(
        detectProjectLaunchKind(profile.type),
        ProjectLaunchKind.desktop,
      );
    });

    test(
      'a Node project (package.json with a dev script) detects as a web '
      'launch kind',
      () async {
        await File(
          '${root.path}${Platform.pathSeparator}package.json',
        ).writeAsString(
          '{"name": "fixture", "scripts": {"dev": "vite"}}',
        );
        final profile = await diagnostics.executionProfile(projectAt(root));
        expect(profile.type, 'Node.js / JavaScript');
        expect(profile.runCommand, isNotNull);
        expect(
          detectProjectLaunchKind(profile.type),
          ProjectLaunchKind.web,
        );
      },
    );

    test('an unrecognized project produces no preferred launch profile',
        () async {
      final profile = await diagnostics.executionProfile(projectAt(root));
      expect(profile.type, 'Unknown');
      expect(profile.runCommand, isNull);
    });
  });
  group('detectProjectLaunchKind', () {
    test('Flutter projects are desktop', () {
      expect(detectProjectLaunchKind('Flutter'), ProjectLaunchKind.desktop);
    });

    test('Node.js / JavaScript projects are web', () {
      expect(
        detectProjectLaunchKind('Node.js / JavaScript'),
        ProjectLaunchKind.web,
      );
    });

    test('Static website projects are web', () {
      expect(
        detectProjectLaunchKind('Static website'),
        ProjectLaunchKind.web,
      );
    });

    test(
        'unrecognized/unknown project types fall back to command, never '
        'a guessed web/server kind', () {
      expect(detectProjectLaunchKind('Unknown'), ProjectLaunchKind.command);
      expect(detectProjectLaunchKind('Dart'), ProjectLaunchKind.command);
      expect(detectProjectLaunchKind('Python'), ProjectLaunchKind.command);
      expect(detectProjectLaunchKind('Go'), ProjectLaunchKind.command);
      expect(detectProjectLaunchKind('Rust'), ProjectLaunchKind.command);
      expect(
        detectProjectLaunchKind('Invalid custom profile'),
        ProjectLaunchKind.command,
      );
    });
  });

  group('openBehaviorForLaunchKind', () {
    test('desktop opens by focusing the native app', () {
      expect(
        openBehaviorForLaunchKind(ProjectLaunchKind.desktop),
        ProjectLaunchOpenBehavior.focusNativeApp,
      );
    });

    test('web and server open in Web Studio', () {
      expect(
        openBehaviorForLaunchKind(ProjectLaunchKind.web),
        ProjectLaunchOpenBehavior.openWebStudio,
      );
      expect(
        openBehaviorForLaunchKind(ProjectLaunchKind.server),
        ProjectLaunchOpenBehavior.openWebStudio,
      );
    });

    test('command and other have no automatic open behavior', () {
      expect(
        openBehaviorForLaunchKind(ProjectLaunchKind.command),
        ProjectLaunchOpenBehavior.none,
      );
      expect(
        openBehaviorForLaunchKind(ProjectLaunchKind.other),
        ProjectLaunchOpenBehavior.none,
      );
    });
  });
}
