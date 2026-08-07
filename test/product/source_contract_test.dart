import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String relativePath) => File(relativePath).readAsStringSync();

Map<String, Object?> sourceJsonObject(String relativePath) {
  final decoded = jsonDecode(source(relativePath));
  if (decoded is! Map) {
    throw StateError('$relativePath must contain a JSON object.');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> jsonObject(Object? value, String label) {
  if (value is! Map) {
    throw StateError('$label must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, Object?>> jsonObjectList(Object? value, String label) {
  if (value is! List) {
    throw StateError('$label must be a JSON array.');
  }
  return value
      .map((item) => jsonObject(item, '$label entry'))
      .toList(growable: false);
}

Iterable<File> activeDartFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

Iterable<int> unconvertedClampOffsets(String content) sync* {
  const marker = '.clamp(';
  var searchFrom = 0;

  while (true) {
    final start = content.indexOf(marker, searchFrom);
    if (start < 0) {
      return;
    }

    var cursor = start + marker.length;
    var depth = 1;
    String? quote;
    var escaped = false;

    while (cursor < content.length && depth > 0) {
      final character = content[cursor];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (character == '\\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
      } else if (character == "'" || character == '"') {
        quote = character;
      } else if (character == '(') {
        depth++;
      } else if (character == ')') {
        depth--;
      }
      cursor++;
    }

    if (depth != 0) {
      yield start;
      searchFrom = start + marker.length;
      continue;
    }

    while (cursor < content.length &&
        const <String>{' ', '\t', '\r', '\n'}.contains(content[cursor])) {
      cursor++;
    }

    final converted = <String>[
      '.toInt(',
      '.toDouble(',
      '.toString(',
    ].any((conversion) => content.startsWith(conversion, cursor));
    if (!converted) {
      yield start;
    }
    searchFrom = cursor > start ? cursor : start + marker.length;
  }
}

String sourceLineAt(String content, int offset) {
  final start = content.lastIndexOf('\n', offset - 1) + 1;
  final nextNewline = content.indexOf('\n', offset);
  final end = nextNewline < 0 ? content.length : nextNewline;
  return content.substring(start, end).trim();
}

void main() {
  group('active architecture', () {
    test('main uses only the governed product runtime', () {
      final mainSource = source('lib/main.dart');
      expect(mainSource, contains('ProductRuntime'));
      expect(mainSource, contains('KristinApp'));
      expect(mainSource, isNot(contains('HomeScreen')));
      expect(mainSource, isNot(contains('AgentEngine')));
      expect(mainSource, isNot(contains('Orchestrator')));
    });

    test('active source never imports the legacy archive', () {
      for (final file in activeDartFiles()) {
        expect(
          file.readAsStringSync(),
          isNot(contains('archive/legacy')),
          reason: file.path,
        );
      }
    });

    test('only the governed library source is analyzer-visible', () {
      const expected = <String>{
        'lib/main.dart',
        'lib/product/agent_decision.dart',
        'lib/product/agent_protocol.dart',
        'lib/product/api_server.dart',
        'lib/product/chat_studio.dart',
        'lib/product/crypto_utils.dart',
        'lib/product/deployment_support.dart',
        'lib/product/domain.dart',
        'lib/product/durable_workflow.dart',
        'lib/product/execution_intelligence.dart',
        'lib/product/extensions_index.dart',
        'lib/product/file_adapters.dart',
        'lib/product/generated/prompt_studio_contracts.g.dart',
        'lib/product/generated/protocol_contracts.g.dart',
        'lib/product/generated/v170_contracts.g.dart',
        'lib/product/generated/v180_contracts.g.dart',
        'lib/product/generated/v190_contracts.g.dart',
        'lib/product/generated/workflow_migrations.g.dart',
        'lib/product/interoperability_v19.dart',
        'lib/product/knowledge_memory_v2.dart',
        'lib/product/mcp.dart',
        'lib/product/mcp_protocol.dart',
        'lib/product/models_research.dart',
        'lib/product/planning_runtime.dart',
        'lib/product/product_runtime.dart',
        'lib/product/project_diagnostics.dart',
        'lib/product/project_manager_v2.dart',
        'lib/product/prompt_planning.dart',
        'lib/product/prompt_studio_v2.dart',
        'lib/product/protocol_types.dart',
        'lib/product/release_operations_v19.dart',
        'lib/product/repository.dart',
        'lib/product/retry_policy.dart',
        'lib/product/storage_security.dart',
        'lib/product/tool_schema.dart',
        'lib/product/ui.dart',
        'lib/product/ui_advanced.dart',
        'lib/product/ui_components.dart',
        'lib/product/workspace_tools.dart',
        'lib/product/access_profile_v2.dart',
        'lib/product/capability_grant_v2.dart',
        'lib/product/deterministic_policy_engine.dart',
        'lib/product/signed_manifest_v2.dart',
        'lib/product/manifest_compatibility_v2.dart',
        'lib/product/key_registry_v2.dart',
        'lib/product/signed_audit_checkpoint_v1.dart',
        'lib/product/local_authenticated_ipc_v1.dart',
        'lib/product/p1_authority_service_contract_v1.dart',
        'lib/product/p1_authority_service_native_connector_v2.dart',
        'lib/product/p1_authority_service_product_runtime_v1.dart',
        'lib/product/p2_app_shell.dart',
        'lib/product/p2_automation_command_service.dart',
        'lib/product/p2_automation_host.dart',
        'lib/product/p2_automation_host_operations.dart',
        'lib/product/p2_automation_host_process_client.dart',
        'lib/product/p2_desktop_effect_authorizers.dart',
        'lib/product/p2_effect_boundary.dart',
        'lib/product/p2_effect_journal.dart',
        'lib/product/p2_emergency_watchdog.dart',
        'lib/product/p2_filesystem_service.dart',
        'lib/product/p2_finite_command_service.dart',
        'lib/product/p2_host_operations.dart',
        'lib/product/p2_managed_authorization_registry.dart',
        'lib/product/p2_owner_mode.dart',
        'lib/product/p2_owner_risk_authority.dart',
        'lib/product/p2_owner_workspace.dart',
        'lib/product/p2_p1_authority_adapter.dart',
        'lib/product/p2_process_tree.dart',
        'lib/product/p2_product_binding_context.dart',
        'lib/product/p2_product_evidence.dart',
        'lib/product/p2_product_runtime_bootstrap.dart',
        'lib/product/p2_product_runtime_integration.dart',
        'lib/product/p2_pty_service.dart',
        'lib/product/p2_runtime_composition.dart',
        'lib/product/p2_runtime_resource_resolver.dart',
        'lib/product/p2_snapshot_undo.dart',
        'lib/product/p2_terminal_model.dart',
      };
      final actual = activeDartFiles()
          .map((file) => file.path.replaceAll('\\', '/'))
          .toSet();
      expect(actual, containsAll(expected));
      expect(actual.length, expected.length);
    });

    test('application opens chat-first through the governed P2 shell', () {
      final ui = source('lib/product/ui.dart');
      final shell = source('lib/product/p2_app_shell.dart');
      expect(ui, contains('home: P2KristinShell('));
      expect(ui, contains('chat: ChatStudio('));
      expect(shell, contains('var _index = 0;'));
      final chatOffset = shell.indexOf('widget.chat,');
      final ownerOffset = shell.indexOf(
        'widget.ownerMode.buildWorkspace(',
      );
      expect(chatOffset, greaterThanOrEqualTo(0));
      expect(ownerOffset, greaterThan(chatOffset));
    });

    test('stale-source migration consumes governed inventories', () {
      final migration = source('tool/prune_stale_legacy.dart');
      expect(migration, contains('SOURCE_MANIFEST.sha256'));
      expect(
        migration,
        contains('config/p2_source_inventory.v1.json'),
      );
      expect(migration, contains('_governedDartFiles(root)'));
      expect(
        migration,
        contains('allowedDartFiles.contains(relative)'),
      );
      expect(migration, contains('refusing stale-source migration'));
      expect(migration, contains('throw FormatException'));
      expect(migration, isNot(contains('deleteSync')));
    });
  });

  group('security invariants', () {
    test('loopback API has no wildcard CORS grant', () {
      final api = source('lib/product/api_server.dart').toLowerCase();
      expect(api, isNot(contains("access-control-allow-origin', '*'")));
      expect(api, isNot(contains('access-control-allow-origin: *')));
      expect(api, contains('loopback'));
      expect(api, contains('bearer'));
    });

    test('Dart regular expressions do not use inline modifiers', () {
      for (final file in activeDartFiles()) {
        expect(
          file.readAsStringSync(),
          isNot(contains('(?i)')),
          reason: file.path,
        );
      }
    });

    test('active source uses the current dropdown form API', () {
      for (final path in <String>[
        'lib/product/ui.dart',
        'lib/product/chat_studio.dart',
        'lib/product/ui_advanced.dart',
      ]) {
        final ui = source(path);
        expect(
          RegExp(r'DropdownButtonFormField<[^>]+>\(\s*value:').hasMatch(ui),
          isFalse,
          reason: path,
        );
        expect(
          'initialValue:'.allMatches(ui).length,
          greaterThanOrEqualTo('DropdownButtonFormField'.allMatches(ui).length),
          reason: path,
        );
      }
    });

    test('Windows verification migrates stale legacy code safely', () {
      final verify = source('tool/verify.cmd').toLowerCase();
      final launcher = source('tool/prune_stale_legacy.cmd').toLowerCase();
      final migration = source('tool/prune_stale_legacy.dart').toLowerCase();
      expect(verify, contains('prune_stale_legacy.cmd'));
      expect(launcher, contains(r'dart run tool\prune_stale_legacy.dart'));
      expect(launcher, isNot(contains('powershell'));
      expect(migration, contains('_alloweddartfiles'));
      expect(migration, contains('archive/legacy_pre_v070_'));
      final sourceManifest = source('SOURCE_MANIFEST.sha256');
      expect(sourceManifest, contains('  lib/product/ui_advanced.dart'));
      expect(sourceManifest, contains('  lib/product/ui_components.dart'));
      expect(migration, contains('_moveentity'));
      expect(migration, contains('quarantinedpaths'));
      expect(migration, contains("'discardedpaths': 0"));
      expect(migration, contains('renamesync'));
      expect(migration, isNot(contains('deletesync')));
    });
  });

  group('chat workspace experience', () {
    test('the application opens in the chat-first workspace', () {
      final ui = source('lib/product/ui.dart');
      final chat = source('lib/product/chat_studio.dart');
      final p2Shell = source('lib/product/p2_app_shell.dart');
      expect(ui, contains('home: P2KristinShell('));
      expect(ui, contains('chat: ChatStudio('));
      expect(p2Shell, contains('var _index = 0;'));
      expect(p2Shell, contains('widget.chat,'));
      expect(chat, contains("label: 'Chats'"));
      expect(chat, contains("label: 'Project Manager'"));
      expect(chat, contains("'BUILD & DEBUG'"));
    });
  });
}
