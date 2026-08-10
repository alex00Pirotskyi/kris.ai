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
        'lib/product/model/model.dart',
        'lib/product/model/model_registry.dart',
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
        'lib/product/mcp_protocol.dart',
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
      expect(launcher, isNot(contains('powershell')));
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

    test('process streams and BytesBuilder imports remain analyzer-clean', () {
      final workspace = source('lib/product/workspace_tools.dart');
      final research = source('lib/product/models_research.dart');
      expect(workspace, contains("import 'dart:typed_data';"));
      expect(research, contains("import 'dart:typed_data';"));
      final start = workspace.indexOf('class ManagedProcessService');
      final end = workspace.indexOf('class ToolContext', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      expect(workspace.substring(start, end), isNot(contains('.listen(')));
    });

    test('workspace tools implement symlink-aware rollback', () {
      final tools = source('lib/product/workspace_tools.dart');
      expect(tools, contains('resolveSymbolicLinks'));
      expect(tools.toLowerCase(), contains('rollback'));
      expect(tools.toLowerCase(), contains('checkpoint'));
      expect(tools.toLowerCase(), contains('expected'));
    });

    test('persistent security uses references and token hashes', () {
      final domain = source('lib/product/domain.dart');
      final security = source('lib/product/storage_security.dart');
      expect(security, contains('SecretReference'));

      final recordStart = domain.indexOf('class ApiTokenRecord');
      final recordEnd = domain.indexOf('class ModelIdentity', recordStart);
      expect(recordStart, greaterThanOrEqualTo(0));
      expect(recordEnd, greaterThan(recordStart));
      final tokenRecord = domain.substring(recordStart, recordEnd);
      expect(tokenRecord, contains('required this.hash'));
      expect(tokenRecord, contains('final String hash;'));
      expect(tokenRecord, contains("'hash': hash"));
      expect(tokenRecord.toLowerCase(), isNot(contains('plaintext')));

      expect(
        RegExp(r'hash:\s*Sha256\.text\(plaintext\)').hasMatch(security),
        isTrue,
      );
      expect(
        RegExp(
          r'constantTimeEquals\(\s*candidateHash,\s*record\.hash\s*\)',
        ).hasMatch(security),
        isTrue,
      );
      expect(security.toLowerCase(), contains('expires'));
    });

    test('research boundary includes SSRF and content limits', () {
      final research = source('lib/product/models_research.dart').toLowerCase();
      expect(research, contains('https'));
      expect(research, contains('redirect'));
      expect(research, contains('content'));
      expect(research, contains('timeout'));
      expect(research, anyOf(contains('loopback'), contains('private')));
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
      for (final label in <String>[
        "label: 'Runs'",
        "label: 'Prompt Studio'",
        "label: 'Knowledge'",
        "label: 'Skills'",
        "label: 'Logs'",
      ]) {
        expect(chat, contains(label), reason: label);
      }
    });

    test('chat journey keeps plans, approvals, and progress inline', () {
      final chat = source('lib/product/chat_studio.dart');
      for (final marker in <String>[
        'Ask Kristin anything about this project',
        'Access needed for this run',
        'Start task',
        'View run',
        'Open logs',
        'InteractiveViewer(',
      ]) {
        expect(chat, contains(marker), reason: marker);
      }
      for (final governedCall in <String>[
        'runtime.prepare(',
        'runtime.createRun(',
        'runtime.approve(',
        'runtime.execute(',
      ]) {
        expect(chat, contains(governedCall), reason: governedCall);
      }
    });

    test(
      'project diagnostics, prompts, knowledge, skills, and logs are wired',
      () {
        final chat = source('lib/product/chat_studio.dart');
        for (final marker in <String>[
          'runtime.inspectProject(',
          'runtime.testProject(',
          'runtime.savePrompt(',
          'runtime.listKnowledge(',
          'runtime.listBuiltInSkills()',
          '_LogView.raw',
          'runtime.verifyAudit',
          'runtime.createSupportBundle',
        ]) {
          expect(chat, contains(marker), reason: marker);
        }
      },
    );

    test(
      'advanced capabilities stay available behind progressive disclosure',
      () {
        final advanced = source('lib/product/ui_advanced.dart');
        for (final marker in <String>[
          "'AI models'",
          "'Sources'",
          "'Privacy & access'",
          "'Integrations'",
          "'Developer'",
          'ApiTokenRecord',
          'McpTrustRecord',
          'verifyAudit',
          'createSupportBundle',
        ]) {
          expect(advanced, contains(marker), reason: marker);
        }
      },
    );
  });

  group('product completeness', () {
    test('governed subsystems are active', () {
      const required = <String>[
        'lib/product/domain.dart',
        'lib/product/repository.dart',
        'lib/product/durable_workflow.dart',
        'lib/product/retry_policy.dart',
        'lib/product/generated/workflow_migrations.g.dart',
        'lib/product/storage_security.dart',
        'lib/product/models_research.dart',
        'lib/product/workspace_tools.dart',
        'lib/product/planning_runtime.dart',
        'lib/product/deployment_support.dart',
        'lib/product/extensions_index.dart',
        'lib/product/mcp.dart',
        'lib/product/api_server.dart',
        'lib/product/chat_studio.dart',
        'lib/product/project_diagnostics.dart',
        'lib/product/product_runtime.dart',
        'lib/product/ui.dart',
        'lib/product/ui_advanced.dart',
        'lib/product/ui_components.dart',
      ];
      for (final path in required) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('planning contains contracts, DAGs, budgets, and verification', () {
      final planning = source(
        'lib/product/planning_runtime.dart',
      ).toLowerCase();
      for (final marker in <String>[
        'taskcontract',
        'executionplan',
        'dependency',
        'budget',
        'cancel',
        'permission',
        'evidence',
        'verification',
      ]) {
        expect(planning, contains(marker), reason: marker);
      }
    });

    test(
      'v0.9 foundations persist prompts, research, memory, diagnostics, and binary tools',
      () {
        final domain = source('lib/product/domain.dart');
        final storage = source('lib/product/storage_security.dart');
        final runtime = source('lib/product/product_runtime.dart');
        final research = source('lib/product/models_research.dart');
        final diagnostics = source('lib/product/project_diagnostics.dart');
        final tools = source('lib/product/workspace_tools.dart');

        expect(domain, contains("const String kristinVersion = '1.9.0+190'"));
        expect(
          source('tool/kristin_cli.py'),
          contains('(("SOURCE_DATE_EPOCH", "1784678400"),)'),
        );
        expect(
          source('tool/release.py'),
          contains('env["SOURCE_DATE_EPOCH"] = "1784678400"'),
        );
        expect(domain, contains('class PromptTemplateRecord'));
        expect(domain, contains('class ProjectDiagnosticReport'));
        expect(storage, contains("name: 'prompts'"));
        expect(storage, contains('updateList('));
        expect(runtime, contains('ProjectDiagnosticsService'));
        expect(runtime, contains('research-archive'));
        expect(research, contains('rawContent'));
        expect(diagnostics, contains('kristin.project.json'));
        expect(tools, contains("schemas.require('inspect_file')"));
        expect(tools, contains("schemas.require('write_binary_file')"));
      },
    );

    test(
      'v0.9 knowledge archive, cited retrieval, and episodic memory stay wired',
      () {
        final domain = source('lib/product/domain.dart');
        final storage = source('lib/product/storage_security.dart');
        final research = source('lib/product/models_research.dart');
        final planning = source('lib/product/planning_runtime.dart');
        final runtime = source('lib/product/product_runtime.dart');
        final tools = source('lib/product/workspace_tools.dart');
        final api = source('lib/product/api_server.dart');
        final chat = source('lib/product/chat_studio.dart');
        final cli = source('tool/kristin_cli.py');

        expect(domain, contains('class ResearchArchiveRecord'));
        expect(domain, contains('class MemoryEpisode'));
        expect(domain, contains('class KnowledgeRetrieval'));
        expect(domain, contains('class KnowledgeSearchHit'));
        expect(storage, contains("name: 'research_archive'"));
        expect(storage, contains("name: 'memory_episodes'"));
        expect(research, contains('Future<KnowledgeRetrieval> retrieve('));
        expect(research, contains('Future<MemoryEpisode> recordEpisode('));
        expect(research, contains('Future<File> exportPackage('));
        expect(research, contains('Future<void> _migrateV08ArchiveFiles()'));
        expect(research, contains('legacy-v0.8-knowledge-recovery'));
        expect(research, contains('_storeObject('));
        expect(research, contains('_semanticVector('));
        expect(planning, contains('CITED PROJECT KNOWLEDGE AND RUN MEMORY'));
        expect(planning, contains('reconcileMemoryEpisodes'));
        expect(runtime, contains('searchKnowledge('));
        expect(runtime, contains('exportKnowledge('));
        expect(tools, contains("schemas.require('knowledge_search')"));
        expect(tools, contains('retrieval.toJson()'));
        expect(api, contains("action == 'search'"));
        expect(api, contains("action == 'export'"));
        expect(api, contains("segments[3] == 'research-archive'"));
        expect(api, contains("segments[3] == 'memory'"));
        expect(chat, contains('Knowledge & memory'));
        expect(chat, contains('Research sources'));
        expect(chat, contains('Run memory'));
        expect(cli, contains('subparsers.add_parser('));
        expect(cli, contains('"knowledge"'));
      },
    );

    test(
      'v0.9.3 conversational and execution reliability guards stay wired',
      () {
        final domain = source('lib/product/domain.dart');
        final planning = source('lib/product/planning_runtime.dart');
        final protocol = source('lib/product/agent_protocol.dart');
        final research = source('lib/product/models_research.dart');
        final runtime = source('lib/product/product_runtime.dart');
        final permissions = source('lib/product/storage_security.dart');
        final tools = source('lib/product/workspace_tools.dart');
        final api = source('lib/product/api_server.dart');
        final chat = source('lib/product/chat_studio.dart');
        final behavioral = source(
          'test/product/execution_reliability_test.dart',
        );

        expect(domain, contains('bool isConversationalRequest('));
        expect(domain, contains('bool isFailureInvestigationRequest('));
        expect(domain, contains("json['tool_calls']"));
        expect(domain, contains("json['function_call']"));
        expect(domain, contains("'function_call'"));
        expect(protocol, contains('class AgentProtocolAdapter'));
        expect(protocol, contains("'tool_input'"));
        expect(protocol, contains("'action_input'"));
        expect(planning, contains('revision: 2'));
        expect(planning, contains("'Respond conversationally'"));
        expect(planning, contains('allowPlainCompletion: conversational'));
        expect(planning, contains("'model.protocol_repair_requested'"));
        expect(planning, contains('protocolRepairAttempts < 2'));
        expect(planning, contains('protocolRepairAttempts = 0'));
        expect(planning, contains("'model.protocol_fallback_applied'"));
        expect(planning, contains("'model.protocol_exhausted'"));
        expect(planning, contains("'model_protocol_exhausted'"));
        expect(planning, contains("'responsePreview'"));
        expect(planning, contains("'model_tool_not_allowed'"));
        expect(planning, contains('_cachedKnowledgeRetrieval('));
        expect(planning, contains('includeUnsuccessfulEpisodes:'));
        expect(research, contains("'stream': true"));
        expect(research, contains('StreamIterator<String>'));
        expect(research, contains("'model_first_token_timeout'"));
        expect(research, contains('static const int _indexSchema = 3'));
        expect(research, contains('final String episodeOutcome;'));
        expect(research, contains('isConversationalRequest(episode.request)'));
        expect(runtime, contains('bool includeUnsuccessfulEpisodes = false'));
        expect(runtime, contains("'permission_scope_missing'"));
        expect(permissions, contains('zero-scope grant'));
        expect(
          tools,
          contains("arguments['includeUnsuccessfulEpisodes'] == true"),
        );
        expect(api, contains("queryParameters['includeUnsuccessfulEpisodes']"));
        expect(chat, contains('result.contract.requiredPermissions.isEmpty'));
        expect(
          behavioral,
          contains('Ollama provider consumes streamed NDJSON'),
        );
        expect(
          behavioral,
          contains('accepts snake-case function_call envelopes'),
        );
        expect(
          behavioral,
          contains('normalizes safe tool and argument aliases'),
        );
        expect(behavioral, contains('unwraps double-encoded response objects'));
        expect(
          behavioral,
          contains('accepts bounded ReAct-style action output'),
        );
        expect(
          behavioral,
          contains('does not normalize a tool outside the work-item allowlist'),
        );
      },
    );

    test('clamp regression scanner handles Dart formatting', () {
      expect(
        unconvertedClampOffsets('value.clamp(1, 10)\n    .toInt()'),
        isEmpty,
      );
      expect(
        unconvertedClampOffsets('value.clamp(1, nested(10)) .toDouble()'),
        isEmpty,
      );
      expect(unconvertedClampOffsets('value.clamp(1, 10)').toList(), <int>[5]);
    });

    test('current Flutter and Dart compatibility regressions stay fixed', () {
      final runtime = source('lib/product/product_runtime.dart');
      final planning = source('lib/product/planning_runtime.dart');
      final api = source('lib/product/api_server.dart');
      final ui = <String>[
        source('lib/product/ui.dart'),
        source('lib/product/chat_studio.dart'),
        source('lib/product/ui_advanced.dart'),
        source('lib/product/ui_components.dart'),
      ].join('\n');

      expect(runtime, contains("import 'dart:math';"));
      expect(runtime, contains('uses: max('));
      expect(planning, contains('questions == 0'));
      expect(planning, isNot(contains('questions.isEmpty')));
      expect(api, contains("headers.value('origin')"));
      expect(api, isNot(contains('HttpHeaders.originHeader'));
      expect(ui, contains('CardThemeData('));
      expect(ui, isNot(contains('cardTheme: const CardTheme(')));

      for (final file in activeDartFiles()) {
        final content = file.readAsStringSync();
        final offsets = unconvertedClampOffsets(content).toList();
        final details =
            offsets.map((offset) => sourceLineAt(content, offset)).join(' | ');
        expect(
          offsets,
          isEmpty,
          reason: '${file.path}: clamp calls without explicit conversion: '
              '$details',
        );
      }
    });

    test('run event collections support reverse traversal', () {
      final ui = source('lib/product/ui.dart');
      expect(ui, contains('List<EventEnvelope> _eventsForRun'));
      final reverseTraversalCompact = ui.replaceAll(RegExp(r'\s+'), '');

      expect(reverseTraversalCompact, contains('}).toList(growable:false);'));
      expect(ui, isNot(contains('Iterable<EventEnvelope> _eventsForRun')));
    });

    test(
      'Windows launchers avoid stale overlays and PowerShell-only entry points',
      () {
        expect(File('APPLY_V070.cmd').existsSync(), isFalse);
        expect(File('APPLY_AND_RUN_V070.cmd').existsSync(), isFalse);
        for (final path in <String>[
          'kristin.cmd',
          'RUN_WINDOWS.bat',
          'tool/bootstrap_platforms.cmd',
          'tool/verify.cmd',
          'tool/run_windows.cmd',
        ]) {
          expect(File(path).existsSync(), isTrue, reason: path);
          final launcher = source(path).toLowerCase();
          expect(launcher, isNot(contains('executionpolicy')), reason: path);
        }
        expect(source('tool/verify.cmd').toLowerCase(), contains('flutter'));
        expect(
          source('tool/run_windows.cmd').toLowerCase(),
          contains('flutter'),
        );
        expect(
          source('RUN_WINDOWS.bat'),
          contains('Starting Kristin v1.0 Prompt-to-Task Product Preview'),
        );

        final diagnostics = source('lib/product/project_diagnostics.dart');
        expect(diagnostics, contains("import 'crypto_utils.dart';"));
        expect(diagnostics, contains('_isWindowsDriveRoot'));
        expect(diagnostics, isNot(contains('trimmed.replaceAll(RegExp')));
        expect(diagnostics, isNot(contains("RegExp(r'(?m)")));
        expect(diagnostics, contains('multiLine: true'));
        expect(diagnostics, isNot(contains("import 'dart:math';")));
        expect(diagnostics, contains("import 'storage_security.dart';"));

        final chat = source('lib/product/chat_studio.dart');
        expect(
          chat,
          contains('matrix.scaleByDouble(factor, factor, factor, 1.0);'),
        );
        expect(chat, isNot(contains('matrix.scale(factor);'));

        final research = source('lib/product/models_research.dart');
        expect(
          research,
          isNot(
            contains(
              'putIfAbsent(record.knowledgeId, () => <ResearchArchiveRecord>[])\n          ..add(record);',
            ),
          ),
        );
        expect(
          research,
          contains('Future<List<KnowledgeEntry>> list(String projectId)'),
        );
        expect(
          source('lib/product/product_runtime.dart'),
          contains('knowledge.list(projectId)'),
        );

        final migration = source('tool/prune_stale_legacy.dart');
        expect(
          migration,
          contains('final allowedDartFiles = _governedDartFiles(root);'),
        );
        expect(migration, contains('allowedDartFiles.contains(relative)'));
        expect(
          File('test/product/knowledge_memory_test.dart').existsSync(),
          isTrue,
        );

        final cli = source('tool/kristin_cli.py');
        expect(cli, contains('nargs="?", const="."'));
        expect(cli, contains('if args.command is None:'));

        final pubspec = source('pubspec.yaml');
        expect(pubspec, isNot(contains('flutter_markdown:'));
      },
    );

    test('v1 Prompt-to-Task and path compatibility stay wired', () {
      final domain = source('lib/product/domain.dart');
      final planning = source('lib/product/prompt_planning.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final runtime = source('lib/product/product_runtime.dart');
      final storage = source('lib/product/storage_security.dart');
      final tools = source('lib/product/workspace_tools.dart');
      final studio = source('lib/product/chat_studio.dart');
      final api = source('lib/product/api_server.dart');
      final cli = source('tool/kristin_cli.py');
      final behavioral = source('test/product/v1_product_preview_test.dart');

      expect(domain, contains('class PromptStudioDraft'));
      expect(domain, contains('class PromptVersionRecord'));
      expect(domain, contains('class TaskPlanRecord'));
      expect(
        domain,
        contains('The task plan contains a parent hierarchy cycle.'),
      );
      expect(planning, contains('class PromptPlanningService'));
      expect(planning, contains('maxLeafTasks.clamp(1, 100)'));
      expect(planning, contains('revision: plan.revision + 1'));
      expect(planning, contains('_withDependencies(selectedTaskIds, all)'));
      expect(coordinator, contains("'tool.repair_requested'"));
      expect(coordinator, contains('_isRecoverableToolInputError'));
      expect(runtime, contains('generatePromptDraft'));
      expect(runtime, contains('prepareTaskPlan'));
      expect(storage, contains('promptVersions'));
      expect(storage, contains('taskPlans'));
      expect(tools, contains('String normalizeToolPath(String input)'));
      expect(tools, contains('class WorkspacePathRecovery'));
      expect(tools, contains('recoverExternalToolPath'));
      expect(tools, contains("'path_outside_project'"));
      expect(tools, contains("'tool.path_normalized'"));
      expect(coordinator, contains("'tool.path_rebased_to_active_project'"));
      expect(studio, contains("'Generate prompt'"));
      expect(studio, contains("'Generate task list'"));
      expect(studio, contains("'Run all tasks'"));
      expect(studio, contains("'Stop all running tasks'"));
      expect(api, contains("'/v1/prompts/generate'"));
      expect(api, contains("'/v1/task-plans/generate'"));
      expect(api, contains("segments[3] == 'compile'"));
      expect(cli, contains('mode.add_argument("--system"'));
      expect(cli, contains('mode.add_argument("--release"'));
      expect(behavioral, contains('normalizes in-project absolute paths'));
      expect(
        behavioral,
        contains('rebases recognized virtual workspace paths'),
      );
      expect(behavioral, contains('blocks arbitrary external writes'));
      expect(behavioral, contains('accepts a valid 100-task plan'));
    });

    test('v1.0.2 budget-aware retries and shareable diagnostics stay wired',
        () {
      final domain = source('lib/product/domain.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final runtime = source('lib/product/product_runtime.dart');
      final deployment = source('lib/product/deployment_support.dart');
      final studio = source('lib/product/chat_studio.dart');
      final api = source('lib/product/api_server.dart');
      final cli = source('tool/kristin_cli.py');
      final behavioral = source('test/product/budget_diagnostics_test.dart');

      expect(domain, contains('factory AutonomyBudget.forPlan'));
      expect(domain, contains('maxAgentTurnsPerAttempt'));
      expect(domain, contains('minModelRequestsForRetry'));
      expect(domain, contains('maxRepeatedToolOutcomes'));
      expect(domain, contains('final String? sourceRunId;'));
      expect(coordinator, contains('Future<RunRecord> retryRun(String runId)'));
      expect(coordinator, contains("'run_retry_required'"));
      expect(coordinator, contains("'work_item.turn_budget_assigned'"));
      expect(coordinator, contains("'work_item.retry_skipped'"));
      expect(coordinator, contains("'model.request_started'"));
      expect(coordinator, contains("'model.request_completed'"));
      expect(coordinator, contains("'model.request_failed'"));
      expect(coordinator, contains("'agent.stalled_repeated_tool_outcome'"));
      expect(
        coordinator,
        contains('_enforceToolBudget(current, action.tool!)'),
      );
      expect(coordinator, contains('tools.isMutatingTool(toolName)'));
      expect(
        coordinator,
        contains(
          'The model may still complete using evidence already collected',
        ),
      );
      expect(coordinator, contains('remainingAgentTurns='));
      expect(runtime, contains('AutonomyBudget.forPlan(command.plan)'));
      expect(runtime, contains('runs.retryRun(runId)'));
      expect(deployment, contains('kristin.diagnostics.bundle.v2'));
      expect(deployment, contains('events-redacted.jsonl'));
      expect(deployment, contains('run-diagnostic-summary.md'));
      expect(deployment, contains('evidence-redacted.json'));
      expect(deployment, contains('managed-processes'));
      expect(studio, contains("Text('Save all logs')"));
      expect(studio, contains('includeAllLogs: true'));
      expect(api, contains("action == 'retry'"));
      expect(api, contains("'/runs/{runId}/retry'"));
      expect(cli, contains('logs_parser.add_argument("--export"'));
      expect(cli, contains('kristin.diagnostics.cli.v3'));
      expect(
        behavioral,
        contains(
          'tool budgets are checked only when another governed tool is dispatched',
        ),
      );
      expect(behavioral, contains('retry creates a linked run'));
      expect(behavioral, contains('all-logs bundle retains diagnostics'));
    });

    test(
      'v1.0.3 duplicate read recovery stays bounded and evidence-driven',
      () {
        final coordinator = source('lib/product/planning_runtime.dart');
        final deployment = source('lib/product/deployment_support.dart');
        final behavioral = source('test/product/budget_diagnostics_test.dart');

        expect(coordinator, contains('class AgentLoopRecoveryPolicy'));
        expect(coordinator, contains('class ToolLoopObservation'));
        expect(coordinator, contains("'agent.repeated_tool_call_blocked'"));
        expect(coordinator, contains("'agent.loop_recovery_redirected'"));
        expect(coordinator, contains("'agent.loop_recovery_completed'"));
        expect(
          coordinator,
          contains("'work_item.evidence_baseline_completed'"),
        );
        expect(coordinator, contains('_staticToolActionFingerprint'));
        expect(coordinator, contains('_loopRecoveryActionKey'));
        expect(coordinator, contains('cachedResultSummary'));
        expect(coordinator, contains(r"'inspect_file:$candidate'"));
        expect(coordinator, contains("label.contains('evidence baseline')"));
        expect(
          coordinator,
          isNot(contains("label.contains('grounded context') ||")),
        );
        expect(deployment, contains('### Agent loop recovery'));
        expect(deployment, contains("'agent.repeated_tool_call_blocked'"));
        expect(
          behavioral,
          contains('redirects a duplicate listing to safe new evidence'),
        );
        expect(
          behavioral,
          contains('completes only after diverse objective baseline evidence'),
        );
        expect(
          behavioral,
          contains('never auto-completes a general grounded answer task'),
        );
        expect(
          behavioral,
          contains("expect(decision.action?.arguments['path'], isNot('.env'))"),
        );
      },
    );

    test('v1.0.6 workspace canonicalization and path hygiene stay bounded', () {
      final workspace = source('lib/product/workspace_tools.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final deployment = source('lib/product/deployment_support.dart');
      final behavioral = source('test/product/v1_product_preview_test.dart');
      final validator = source('tool/validate_release.py');
      final release = source('tool/release.py');
      final scanner = source('tool/secret_scan.py');
      final policy = source('tool/source_tree_policy.py');

      expect(workspace, contains("normalized.startsWith('//?/')"));
      expect(workspace, contains("startsWith('UNC/')"));
      expect(
        behavioral,
        contains(
          'accepts an in-project absolute path when the project root sits',
        ),
      );
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final priorLineage = jsonObject(lineage['priorLineage'], 'priorLineage');
      final mergedUserPatch = jsonObject(
        priorLineage['mergedUserPatch'],
        'priorLineage.mergedUserPatch',
      );
      final releases = jsonObjectList(
        lineage['transitiveReleaseLineage'],
        'transitiveReleaseLineage',
      );
      final pathHygieneParent = releases.singleWhere(
        (entry) => entry['version'] == '1.0.5+105',
      );
      final workspaceBoundaryParent = releases.singleWhere(
        (entry) => entry['version'] == '1.0.6+106',
      );

      expect(
        mergedUserPatch['sha256'],
        '80e5044cf47e8f19ec2350a20f22e0b9fc3da464fac142bc67a5d6bc6231e3f3',
      );
      expect(
        pathHygieneParent['sha256'],
        '81bc8384d545cd6586696ed3b58da315b596de042785ae9918ea4b2b427f18a2',
      );
      expect(pathHygieneParent['role'], 'path-hygiene-parent');
      expect(
        workspaceBoundaryParent['sha256'],
        '9829aa2e658893279d66e96699e225aef739a791f4b1870cf749ac8349a4662d',
      );
      expect(workspaceBoundaryParent['role'], 'workspace-boundary-parent');
      expect(workspace, contains('class WorkspacePathRecovery'));
      expect(workspace, contains('recoverExternalToolPath'));
      expect(workspace, contains("'virtual_workspace_alias'"));
      expect(workspace, contains("'project_name_anchor'"));
      expect(workspace, contains('_looksSensitiveRecoveryPath'));
      expect(coordinator, contains('_recoverExternalToolPathAction'));
      expect(coordinator, contains("'tool.path_rebased_to_active_project'"));
      expect(coordinator, contains("'securityBoundaryPreserved': true"));
      expect(
        coordinator,
        contains(
          'Project scope cannot improve through a fresh work-item attempt.',
        ),
      );
      expect(deployment, contains('### Project path recovery'));
      expect(
        behavioral,
        contains('rebases recognized virtual workspace paths'),
      );
      expect(behavioral, contains('blocks arbitrary external writes'));
      expect(behavioral, contains('root-scoped read recovery falls back'));
      expect(policy, contains('windows", "flutter", "ephemeral'));
      expect(policy, contains('def is_generated_path'));
      expect(validator, contains('if is_generated_path(rel):'));
      expect(release, contains('if is_generated_path(relative)'));
      expect(scanner, contains('is_generated_path(p.relative_to(ROOT))'));
    });

    test(
      'v1.0.7 diagnostic-derived recovery remains explicit and capability-aligned',
      () {
        final domain = source('lib/product/domain.dart');
        final knowledge = source('lib/product/models_research.dart');
        final coordinator = source('lib/product/planning_runtime.dart');
        final planning = source('lib/product/prompt_planning.dart');
        final runtime = source('lib/product/product_runtime.dart');
        final workspace = source('lib/product/workspace_tools.dart');
        final deployment = source('lib/product/deployment_support.dart');
        final protocolBehavioral = source(
          'test/product/execution_reliability_test.dart',
        );
        final memoryBehavioral = source(
          'test/product/knowledge_memory_test.dart',
        );
        final planBehavioral = source(
          'test/product/v1_product_preview_test.dart',
        );
        final lineage = source('VERSION_CONTROL.json');

        expect(domain, contains('bool isFailureInvestigationRequest'));
        expect(
          knowledge,
          contains('final failureIntent = includeUnsuccessfulEpisodes;'),
        );
        expect(
          knowledge,
          contains('includeUnsuccessfulEpisodes || chunk.pinned'),
        );
        expect(knowledge, isNot(contains('_failureIntentTerms')));
        expect(
          memoryBehavioral,
          contains(
            'calculator history view, input validation, and error handling',
          ),
        );
        expect(
          protocolBehavioral,
          contains('What went wrong with calculator error handling'),
        );
        expect(
          protocolBehavioral,
          contains('inspect_project_and_establish_evidence_baseline'),
        );
        expect(coordinator, contains("'knowledge.context_policy_applied'"));
        expect(coordinator, contains("'antiCopyRule'"));
        expect(coordinator, contains("'protocolRepairAttempt'"));
        expect(planning, contains('settingsProvider'));
        expect(
          planning,
          contains('Create project-local wireframes and user flows'),
        );
        expect(
          planning,
          contains('Prepare local preview and deployment package'),
        );
        expect(planBehavioral, contains('Do not claim use of Figma'));
        expect(workspace, contains('isKristinSourceCheckout'));
        expect(
          runtime + planning + coordinator,
          contains('self_project_target_rejected'),
        );
        expect(deployment, contains('### Automatic memory policy'));
        expect(deployment, contains('### Model protocol recovery'));
        expect(lineage, contains('47bb8141259ce002'));
        expect(lineage, contains('run_hkjnl5dagrldsloYB4qnRQTS3h'));
      },
    );

    test(
      'v1.0.8 preserves the Flutter SDK environment without widening ordinary commands',
      () {
        final cli = source('tool/kristin_cli.py');
        final validator = source('tool/validate_release.py');
        final release = source('tool/release.py');
        final systemFixture = source('tool/system_test.py');
        final lineage = sourceJsonObject('VERSION_CONTROL.json');
        final releases = jsonObjectList(
          lineage['transitiveReleaseLineage'],
          'transitiveReleaseLineage',
        );
        final sdkEnvironmentParent = releases.singleWhere(
          (entry) => entry['version'] == '1.0.8+108',
        );

        expect(cli, contains('_BASE_ENVIRONMENT_KEYS'));
        expect(cli, contains('_SDK_ENVIRONMENT_KEYS'));
        expect(cli, contains('"APPDATA"'));
        expect(cli, contains('"LOCALAPPDATA"'));
        expect(cli, contains('"PUB_CACHE"'));
        expect(cli, contains('"HTTPS_PROXY"'));
        expect(cli, contains('"SSL_CERT_FILE"'));
        expect(cli, contains('_command_environment_profile'));
        expect(cli, contains('environment_profile="sdk"'));
        expect(cli, contains('"--no-pub"'));
        expect(cli, contains('"--skip-sdk"'));
        expect(cli, contains('_diagnostic_redact(output)'));
        expect(validator, contains('"--no-pub"'));
        expect(
          validator,
          allOf(
            contains('"test",'),
            contains('"--no-pub",'),
            contains('"--concurrency=1",'),
          ),
        );
        expect(release, contains('"--skip-sdk"'));
        expect(
          systemFixture,
          contains('SDK subprocess environment compatibility'),
        );
        expect(
          sdkEnvironmentParent['sha256'],
          '76bff50ca1fe0eb82b54c09cf7ecf8f35e6d2c2062490bd73d141785b4d21448',
        );
        expect(sdkEnvironmentParent['role'], 'sdk-environment-parent');
      },
    );

    test('v1.5.0 preserves the complete release lineage structurally', () {
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final contract = jsonObject(
        lineage['lineageContract'],
        'lineageContract',
      );
      final releases = jsonObjectList(
        lineage['transitiveReleaseLineage'],
        'transitiveReleaseLineage',
      );
      final versions = releases
          .map((entry) => entry['version'])
          .whereType<String>()
          .toList(growable: false);

      expect(lineage['canonicalHead'], '1.9.0+190');
      expect(
        lineage['canonicalPackageRoot'],
        'Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops',
      );
      expect(contract['preserveAcrossHeads'], isTrue);
      expect(contract['requiredAncestorVersions'], <String>[
        '1.0.5+105',
        '1.0.6+106',
        '1.0.7+107',
        '1.0.8+108',
        '1.0.9+109',
        '1.1.0+110',
        '1.1.1+111',
        '1.1.2+112',
        '1.1.3+113',
        '1.1.4+114',
        '1.1.5+115',
        '1.1.6+116',
        '1.1.7+117',
        '1.2.0+120',
        '1.3.0+130',
      ]);
      expect(
        versions,
        containsAllInOrder(<String>[
          '1.0.5+105',
          '1.0.6+106',
          '1.0.7+107',
          '1.0.8+108',
          '1.0.9+109',
          '1.1.0+110',
          '1.1.1+111',
          '1.1.2+112',
          '1.1.3+113',
          '1.1.4+114',
          '1.1.5+115',
          '1.1.6+116',
          '1.1.7+117',
          '1.2.0+120',
          '1.3.0+130',
        ]),
      );
      expect(
        source('docs/V1.0.9_LINEAGE_CONTRACT_HOTFIX.md'),
        contains('structured transitive release lineage'),
      );
      expect(source('tool/system_test.py'), contains('81bc8384d545cd65'));
      expect(source('tool/validate_release.py'), contains('76bff50ca1fe0eb'));
    });

    test('v1.5.0 preserves Project Manager and compile linkage', () {
      final domain = source('lib/product/domain.dart');
      final diagnostics = source('lib/product/project_diagnostics.dart');
      final runtime = source('lib/product/product_runtime.dart');
      final planning = source('lib/product/prompt_planning.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final studio = source('lib/product/chat_studio.dart');
      final api = source('lib/product/api_server.dart');
      final cli = source('tool/kristin_cli.py');
      final behavioral = source('test/product/v1_product_preview_test.dart');

      expect(domain, contains("const String kristinVersion = '1.9.0+190'"));
      expect(domain, contains('class ProjectProcessStatus'));
      expect(
        diagnostics,
        contains("import 'storage_security.dart';"),
        reason: 'ProjectDiagnosticsService throws ProductException',
      );
      expect(diagnostics, contains('throw ProductException('));
      expect(diagnostics, contains('class ProjectExecutionProfile'));
      expect(diagnostics, contains('analysisCommands'));
      expect(diagnostics, contains('runAnalysis('));
      expect(diagnostics, contains('runBuild('));
      expect(runtime, contains('analyzeProject('));
      expect(runtime, contains('buildProject('));
      expect(runtime, contains('startProject('));
      expect(runtime, contains('projectProcessStatus('));
      expect(runtime, contains('stopProject('));
      expect(studio, contains("label: 'Project Manager'"));
      for (final label in <String>[
        "Text('Analyze')",
        "Text('Test')",
        "Text('Build')",
        "Text('Run')",
        "Text('Stop')",
        "Text('Save logs')",
      ]) {
        expect(studio, contains(label), reason: label);
      }
      expect(api, contains("action == 'manager'"));
      expect(api, contains("'projects:execute'"));
      expect(api, contains("'/projects/{projectId}/analyze'"));
      expect(api, contains("'/projects/{projectId}/run'"));
      expect(api, contains("'/projects/{projectId}/stop'"));
      expect(cli, contains('subparsers.add_parser(\n        "analyze"'));
      expect(cli, contains('subparsers.add_parser(\n        "build"'));
      expect(planning, contains('_effectivePlanMode'));
      expect(planning, contains('_taskRequiresMutation'));
      expect(planning, contains('docs/design/wireframes.md'));
      expect(planning, contains('_deduplicateCapabilityTasks'));
      expect(coordinator, contains('implementation_stalled_read_only'));
      expect(coordinator, contains('work_item.mutation_required'));
      expect(coordinator, contains('var mutationRepairAttempts = 0;'));
      expect(coordinator, contains('mutationRepairAttempts < 2'));
      expect(
        behavioral,
        contains(
          'promotes artifact-producing plan tasks to governed build work',
        ),
      );
      expect(
        behavioral,
        contains('keeps an explicitly planning-only task read-only'),
      );
      expect(
        behavioral,
        contains('detects custom Analyze, Test, Build, and Run commands'),
      );
    });

    test('v1.1.2 cold-model recovery and capability alignment stay bounded',
        () {
      final models = source('lib/product/models_research.dart');
      final settings = source('lib/product/storage_security.dart');
      final runtime = source('lib/product/planning_runtime.dart');
      final productRuntime = source('lib/product/product_runtime.dart');
      final planning = source('lib/product/prompt_planning.dart');
      final advanced = source('lib/product/ui_advanced.dart');
      final diagnostics = source('lib/product/deployment_support.dart');
      final modelBehavioral = source(
        'test/product/execution_reliability_test.dart',
      );
      final planBehavioral = source(
        'test/product/v1_product_preview_test.dart',
      );
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final releases = jsonObjectList(
        lineage['transitiveReleaseLineage'],
        'transitiveReleaseLineage',
      );
      final compileParent = releases.singleWhere(
        (entry) => entry['version'] == '1.1.1+111',
      );

      expect(models, contains('class ModelGenerationProgress'));
      expect(models, contains("'load_started'"));
      expect(models, contains("'load_retry_started'"));
      expect(models, contains("'load_retry_scheduled'"));
      expect(models, contains("'prompt': ''"));
      expect(models, contains("'stream': false"));
      expect(
        models,
        contains('defaultLoadTimeout = const Duration(minutes: 8)'),
      );
      expect(models, contains('defaultLoadRetries = 1'));
      expect(models, contains('_closeOnCancellation'));
      expect(models, contains('_remainingUntil'));
      expect(models, contains('_shorterDuration'));
      expect(models, contains('request.cancellation'));
      expect(settings, contains('ollamaLoadTimeoutSeconds = 480'));
      expect(settings, contains('ollamaLoadRetries = 1'));
      expect(settings, contains('ollamaKeepAliveMinutes = 15'));
      expect(productRuntime, contains('ollama_load_timeout_invalid'));
      expect(runtime, contains('cancellation: control.cancellation.cancelled'));
      expect(runtime, contains("'model_load_timeout'"));
      expect(
        runtime,
        contains(
          'provider already performs its configured bounded cold-load retry',
        ),
      );
      expect(runtime, contains(r"'model.${modelProgress.stage}'"));
      expect(advanced, contains('Cold-load timeout (seconds)'));
      expect(advanced, contains('Cold-load retries'));
      expect(advanced, contains('Keep model loaded (minutes)'));
      expect(
        diagnostics,
        contains('### Model availability and cold-load recovery'),
      );
      expect(
        planning,
        contains('Run local usability and interaction verification'),
      );
      expect(planning, contains('Do not recruit participants'));
      expect(
        planning,
        contains(
          'Capability alignment replaces the unsupported human-study instruction',
        ),
      );
      expect(planning, contains('.clamp(2, 3)'));
      expect(planning, contains('manual: alignedManual'));
      expect(
        modelBehavioral,
        contains(
          'Ollama retries a transient cold-load timeout inside one model turn',
        ),
      );
      expect(
        modelBehavioral,
        contains('cancelling a run closes an in-flight Ollama cold load'),
      );
      expect(planBehavioral, contains('Do not recruit participants'));
      expect(
        compileParent['sha256'],
        '830f59d1401eab6a97b99f2f96f27dace7902f4541dfbd108ea67f20266604ee',
      );
      expect(compileParent['role'], 'project-manager-compile-parent');
      expect(
        jsonObject(
          lineage['priorLineage'],
          'priorLineage',
        )['modelResilienceDiagnostic'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('v1.1.3 workstation validation fixes are formatter resilient', () {
      final models = source('lib/product/models_research.dart');
      final planning = source('lib/product/prompt_planning.dart');
      final sourceContracts = source('test/product/source_contract_test.dart');
      final modelBehavioral = source(
        'test/product/execution_reliability_test.dart',
      );
      final planBehavioral = source(
        'test/product/v1_product_preview_test.dart',
      );
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final releases = jsonObjectList(
        lineage['transitiveReleaseLineage'],
        'transitiveReleaseLineage',
      );
      final modelResilienceParent = releases.singleWhere(
        (entry) => entry['version'] == '1.1.2+112',
      );
      final prior = jsonObject(lineage['priorLineage'], 'priorLineage');
      final transcript = jsonObject(
        prior['workstationValidationTranscript'],
        'workstationValidationTranscript',
      );

      expect(
        models,
        isNot(contains('_HttpCancellationBinding({this.subscription})')),
      );
      expect(models, contains('class _HttpCancellationBinding'));
      expect(models, contains('StreamSubscription<void>? subscription;'));
      expect(
        sourceContracts,
        isNot(contains('contains("stage: \'load_started\'")')),
      );
      expect(sourceContracts, contains('contains("\'load_started\'")'));
      expect(sourceContracts, contains('contains("\'load_retry_started\'")'));
      expect(modelBehavioral, contains('containsAllInOrder(<String>['));
      for (final stage in <String>[
        'load_started',
        'load_retry_scheduled',
        'load_retry_started',
        'load_completed',
        'generation_started',
      ]) {
        expect(modelBehavioral, contains("'$stage'"), reason: stage);
      }
      expect(
        planning,
        contains(
          'Do not deploy to an external service. Do not claim a public URL.',
        ),
      );
      expect(
        planBehavioral.toLowerCase(),
        contains('do not claim a public url'),
      );
      expect(modelResilienceParent['version'], '1.1.2+112');
      expect(
        modelResilienceParent['sha256'],
        '4300bb3c228e3d4b3502819df1cf84549a5bb2d66672362cdfd9e6d730fe34a2',
      );
      expect(
        transcript['sha256'],
        'f11139cff61ed1d7c0526e60454600de9831b330bbf2cdeb92e9adb7a4ce538b',
      );
    });

    test(
      'v1.1.4 release tests remain deterministic under repeated Windows load',
      () {
        final protocolBehavioral = source(
          'test/product/execution_reliability_test.dart',
        );
        final cli = source('tool/kristin_cli.py');
        final validator = source('tool/validate_release.py');
        final lineage = sourceJsonObject('VERSION_CONTROL.json');
        final releases = jsonObjectList(
          lineage['transitiveReleaseLineage'],
          'transitiveReleaseLineage',
        );
        final workstationParent = releases.singleWhere(
          (entry) => entry['version'] == '1.1.3+113',
        );
        final deterministicRelease = releases.singleWhere(
          (entry) => entry['version'] == '1.1.4+114',
        );

        expect(
          protocolBehavioral,
          contains('final secondWarmupStarted = Completer<void>();'),
        );
        expect(
          protocolBehavioral,
          contains('await secondWarmupStarted.future.timeout('),
        );
        expect(
          protocolBehavioral,
          contains('defaultLoadTimeout: const Duration(seconds: 2)'),
        );
        expect(
          protocolBehavioral,
          isNot(
            contains('defaultLoadTimeout: const Duration(milliseconds: 40)'),
          ),
        );
        expect(
          protocolBehavioral,
          isNot(contains('Duration(milliseconds: 90)')),
        );
        expect(
          protocolBehavioral,
          contains('final warmupRequestStarted = Completer<void>();'),
        );
        expect(
          protocolBehavioral,
          contains('final releaseWarmupResponse = Completer<void>();'),
        );
        expect(
          protocolBehavioral,
          contains('final warmupRequestFinished = Completer<void>();'),
        );
        expect(
          protocolBehavioral,
          contains('await warmupRequestStarted.future.timeout'),
        );
        expect(
          protocolBehavioral,
          contains('await releaseWarmupResponse.future'),
        );
        expect(
          protocolBehavioral,
          isNot(contains('Future<void>.delayed(const Duration(seconds: 1))')),
        );
        expect(cli, contains('"--concurrency=1"'));
        expect(validator, contains('"--concurrency=1"'));
        expect(cli, contains('if "[E]" in line'));
        expect(cli, contains('test_failures'));
        expect(deterministicRelease['version'], '1.1.4+114');
        expect(
          deterministicRelease['sha256'],
          '989ccfc9abdda31537b10b4a6a15e958d12b8209ba923457d45759c3bb5d29b3',
        );
        expect(workstationParent['role'], 'workstation-validation-parent');
        expect(
          workstationParent['sha256'],
          'fa648c05fcae9e3e89fca0ab5dfb41356c85d97b436aa05dd5974388e7148895',
        );
      },
    );

    test('v1.1.6 execution reliability fixes the supplied diagnostic path', () {
      final domain = source('lib/product/domain.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final planning = source('lib/product/prompt_planning.dart');
      final tools = source('lib/product/workspace_tools.dart');
      final diagnostics = source('lib/product/deployment_support.dart');
      final protocolBehavioral = source(
        'test/product/execution_reliability_test.dart',
      );
      final budgetBehavioral = source(
        'test/product/budget_diagnostics_test.dart',
      );
      final planBehavioral = source(
        'test/product/v1_product_preview_test.dart',
      );
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final parent = jsonObject(lineage['parentRelease'], 'parentRelease');
      final prior = jsonObject(lineage['priorLineage'], 'priorLineage');
      final executionDiagnostic = jsonObject(
        prior['executionConvergenceDiagnostic'],
        'executionConvergenceDiagnostic',
      );
      final reliabilityDiagnostic = jsonObject(
        prior['executionReliabilityDiagnostic'],
        'executionReliabilityDiagnostic',
      );
      final releases = jsonObjectList(
        lineage['transitiveReleaseLineage'],
        'transitiveReleaseLineage',
      );
      final deterministicParent = releases.singleWhere(
        (entry) => entry['version'] == '1.1.4+114',
      );
      final stabilityParent = releases.singleWhere(
        (entry) => entry['version'] == '1.1.7+117',
      );
      final executionReliabilityParent = releases.singleWhere(
        (entry) => entry['version'] == '1.1.6+116',
      );

      expect(domain, contains("const String kristinVersion = '1.9.0+190'"));
      expect(domain, contains("actionObject['command']"));
      expect(coordinator, contains('_preferredProtocolTool'));
      expect(
        coordinator,
        contains(
          'collect bounded Git status as a different structural evidence source',
        ),
      );
      expect(coordinator, contains("'argument_required'"));
      expect(coordinator, contains('ArtifactEvidencePolicy'));
      expect(coordinator, contains('artifact_scope_mismatch'));
      expect(coordinator, contains('artifact_evidence_missing'));
      expect(coordinator, contains('work_item.artifact_evidence_required'));
      expect(coordinator, contains('work_item.artifact_evidence_completed'));
      expect(coordinator, contains('requiresValidatedArtifact'));
      expect(coordinator, contains('_priorEvidenceHistory'));
      expect(coordinator, contains('toolRepairAttempt'));
      expect(tools, contains("operation: 'noop'"));
      expect(tools, contains('workspace.mutation_noop'));
      expect(tools, contains('process_scope_argument_rejected'));
      expect(tools, contains('process_path_outside_project'));
      expect(tools, contains('The selected project is not a Git repository'));
      expect(planning, contains('Approved product context'));
      expect(planning, contains('Initialize the selected project workspace'));
      expect(
        planning,
        contains(
          'Implement the client-side calculation engine and session history',
        ),
      );
      expect(planning, contains('unnecessary Express/REST backend'));
      expect(planning, contains('backendImplementationAction'));
      expect(diagnostics, contains('### Artifact scope and convergence'));
      expect(
        protocolBehavioral,
        contains('normalizes the observed nested command vector'),
      );
      expect(
        protocolBehavioral,
        contains('rejects an unrelated commerce wireframe'),
      );
      expect(
        protocolBehavioral,
        contains(
          'preserves direct nested write content from the observed failure envelope',
        ),
      );
      expect(coordinator, contains('artifact_mutation_required'));
      expect(tools, contains('Argument "content" is required'));
      expect(
        source('lib/product/tool_schema.dart'),
        contains("'argumentSchema':"),
      );
      expect(budgetBehavioral, contains('identical writes do not create'));
      expect(planBehavioral, contains('Do not install Node.js'));
      expect(planBehavioral, contains('Session calculation history'));
      expect(
        planBehavioral,
        contains('Conduct Comprehensive Testing of Calculator'),
      );
      expect(parent['version'], '1.8.0+180');
      expect(
        parent['sha256'],
        'eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc',
      );
      expect(stabilityParent['role'], 'stability-replay-parent');
      expect(
        stabilityParent['sha256'],
        '6b32cb8105dcdf6aee0aff9599eefd8552e469f0c813eb992720e84287d7e835',
      );
      expect(
        executionReliabilityParent['role'],
        'execution-reliability-parent',
      );
      expect(
        executionReliabilityParent['sha256'],
        'd4c23f7b005d7067bda06c8761f10d1cc489337300f4358b561415ebe2a6c583',
      );
      expect(deterministicParent['role'], 'deterministic-release-test-parent');
      expect(
        executionDiagnostic['sha256'],
        'af691d08567a1cad8b9593b4e502aae2415f3ded486a4567178490ee4c7c1c75',
      );
      expect(executionDiagnostic['runId'], 'run_hklfhuqkrwdoQ11swy34hvARke');
      expect(
        reliabilityDiagnostic['sha256'],
        'a2c3570a9910cf99f3f5c26388b6638bf5639796c47009277cfcd64c90dd0f9b',
      );
      expect(reliabilityDiagnostic['runId'], 'run_hklsywuyo4NMJgt9ijIxWPhBDr');
    });

    test('v1.1.7 stability baseline replays the current failure', () {
      final coordinator = source('lib/product/planning_runtime.dart');
      final tools = source('lib/product/workspace_tools.dart');
      final cli = source('tool/kristin_cli.py');
      final harness = source('tool/replay_diagnostics.py');
      final replayBehavioral = source(
        'test/product/diagnostic_replay_test.dart',
      );
      final v115 = sourceJsonObject(
        'test/product/fixtures/diagnostic_replay/v115_nested_write_content_loss.json',
      );
      final v116 = sourceJsonObject(
        'test/product/fixtures/diagnostic_replay/v116_markdown_path_repair_loop.json',
      );
      final v116Source = jsonObject(v116['source'], 'v116 source');
      final v116Expected = jsonObject(v116['expected'], 'v116 expected');
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final prior = jsonObject(lineage['priorLineage'], 'priorLineage');
      final stabilityDiagnostic = jsonObject(
        prior['stabilityReplayDiagnostic'],
        'stabilityReplayDiagnostic',
      );

      expect(tools, contains('canonicalModelPathToken'));
      expect(coordinator, contains('BoundedArtifactRecoveryPolicy'));
      expect(coordinator, contains('AutomaticArtifactVerificationPolicy'));
      expect(coordinator, contains('RunRetryBudgetPolicy'));
      expect(
        coordinator,
        contains('work_item.artifact_auto_inspection_completed'),
      );
      expect(
        coordinator,
        isNot(contains("'historyType': 'governed_correction'")),
      );
      expect(coordinator, contains("'evidenceKind': entry['kind']"));
      expect(coordinator, contains('Never copy a history entry as the action'));
      expect(cli, contains('--replay-all'));
      expect(harness, contains('canonical_path_token'));
      expect(
        replayBehavioral,
        contains(
          'all compact production diagnostics satisfy their repaired contracts',
        ),
      );
      expect(v115['id'], 'v115_nested_write_content_loss');
      expect(v116['id'], 'v116_markdown_path_repair_loop');
      expect(
        v116Source['sha256'],
        '69a6b4502607e35b9262d66de9e5be612f0fcc26a867a5242453fc9854d78895',
      );
      expect(v116Expected['minimumRemainingRepairs'], 4);
      expect(v116Expected['retryAllowedAtObservedState'], isFalse);
      expect(
        stabilityDiagnostic['sha256'],
        '69a6b4502607e35b9262d66de9e5be612f0fcc26a867a5242453fc9854d78895',
      );
      expect(stabilityDiagnostic['runId'], 'run_hklw4ohlv7ocm6ItzHe1N5AB0I');
    });

    test('v1.3.0 durable workflow kernel is schema-driven and crash-safe', () {
      final durable = source('lib/product/durable_workflow.dart');
      final storage = source('lib/product/storage_security.dart');
      final tools = source('lib/product/workspace_tools.dart');
      final coordinator = source('lib/product/planning_runtime.dart');
      final retry = source('lib/product/retry_policy.dart');
      final migrations = source(
        'lib/product/generated/workflow_migrations.g.dart',
      );
      final cli = source('tool/kristin_cli.py');
      final kernelGate = source('tool/workflow_kernel_test.py');
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final kernel = jsonObject(
        lineage['durableWorkflowKernel'],
        'durableWorkflowKernel',
      );

      expect(source('pubspec.yaml'), contains('sqlite3: 2.9.4'));
      expect(source('pubspec.yaml'), contains('sqlite3_flutter_libs: 0.5.42'));
      expect(durable, contains('class DurableWorkflowStore'));
      expect(durable, contains('PRAGMA journal_mode = WAL'));
      expect(durable, contains('PRAGMA synchronous = FULL'));
      expect(durable, contains('BEGIN IMMEDIATE'));
      expect(durable, contains('claimOperation'));
      expect(durable, contains('recoverInFlightRuns'));
      expect(durable, contains('rebuildRunProjectionFromHistory'));
      expect(durable, contains('workflow_startup_rollback_failed'));
      expect(storage, contains('workflow.sqlite3'));
      expect(storage, contains('SQLite is the authoritative'));
      expect(tools, contains("status: 'prepared'"));
      expect(tools, contains("await _setStatus(record, 'applied')"));
      expect(tools, contains('transaction_recovery_required'));
      expect(coordinator, contains('acquireRunLease'));
      expect(coordinator, contains('recordTaskAttempt'));
      expect(retry, contains('class WorkflowRetryTaxonomy'));
      expect(migrations, contains('generatedWorkflowSchemaVersion = 6'));
      expect(
        migrations,
        contains(
          'df7e693bff693d0bf649de4f26ea907ce969456adfbf342d17f40f06b22b6261',
        ),
      );
      expect(cli, contains('--workflow-kernel'));
      expect(cli, contains('workflow.sqlite3'));
      expect(
        kernelGate,
        contains('Crash after idempotent result replays once'),
      );
      expect(kernel['schemaVersion'], 6);
      expect(kernel['appendOnlyRunEvents'], isTrue);
      expect(kernel['durableIdempotency'], isTrue);
      expect(kernel['startupRollback'], isTrue);
      expect(kernel['executableKernelCases'], 14);
    });

    test('v1.5.0 Prompt Studio 2 is deterministic and fail-closed', () {
      final domain = source('lib/product/domain.dart');
      final generated = source(
        'lib/product/generated/prompt_studio_contracts.g.dart',
      );
      final studio = source('lib/product/prompt_studio_v2.dart');
      final runtime = source('lib/product/product_runtime.dart');
      final api = source('lib/product/api_server.dart');
      final cli = source('tool/kristin_cli.py');
      final compiler = source('tool/plan_compiler.py');
      final behavioral = source('test/product/prompt_studio_v2_test.dart');
      final lineage = sourceJsonObject('VERSION_CONTROL.json');
      final prompt = jsonObject(lineage['promptStudioV2'], 'promptStudioV2');
      final parent = jsonObject(lineage['parentRelease'], 'parentRelease');

      expect(domain, contains("const String kristinVersion = '1.9.0+190'"));
      expect(
        generated,
        contains(
          '4f65d0e57ee86b58b26223970c8fbfda243256a47689ce83568df88be042500a',
        ),
      );
      expect(studio, contains('class ProductSpecificationV2'));
      expect(studio, contains('class TaskPlanV2'));
      expect(studio, contains('class PromptStudioV2Compiler'));
      expect(studio, contains('class PromptStudioV2Evaluator'));
      expect(studio, contains('task_id_duplicate'));
      expect(studio, contains('criterion_validator_missing'));
      expect(studio, contains('sandbox_required'));
      expect(studio, contains('sideEffectsPerformed'));
      expect(runtime, contains('promptStudioV2'));
      expect(api, contains('/v1/prompt-studio/v2/contracts'));
      expect(api, contains('/v1/prompt-studio/v2/compile'));
      expect(api, contains('/v1/prompt-studio/v2/evaluate'));
      expect(cli, contains('plan-compile'));
      expect(cli, contains('prompt-evaluate'));
      expect(cli, contains('plan-compare'));
      expect(compiler, contains('validate_schema_contract'));
      expect(compiler, isNot(contains('import jsonschema')));
      expect(behavioral, contains('<int>[1, 10, 50, 100]'));
      expect(lineage['canonicalHead'], '1.9.0+190');
      expect(
        lineage['canonicalPackageRoot'],
        'Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops',
      );
      expect(parent['version'], '1.8.0+180');
      expect(
        parent['sha256'],
        'eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc',
      );
      expect(prompt['behavioralGateCases'], 30);
      expect(prompt['fixtureTaskCounts'], <int>[1, 10, 50, 100]);
      expect(prompt['sideEffectFreeDryRun'], isTrue);
      expect(prompt['sandboxDependentTasksFailClosed'], isTrue);
      expect(prompt['v14SandboxImplemented'], isFalse);
    });

    test('deployment support includes deterministic manifests and scans', () {
      final deployment = source(
        'lib/product/deployment_support.dart',
      ).toLowerCase();
      expect(deployment, contains('zip'));
      expect(deployment, contains('sha256'));
      expect(deployment, contains('manifest'));
      expect(deployment, contains('sbom'));
      expect(deployment, anyOf(contains('secret'), contains('credential')));
    });
  });
}
