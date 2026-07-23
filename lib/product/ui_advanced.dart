import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api_server.dart';
import 'crypto_utils.dart';
import 'domain.dart';
import 'mcp.dart';
import 'product_runtime.dart';
import 'storage_security.dart';
import 'ui_components.dart';

class AdvancedSettingsResult {
  const AdvancedSettingsResult({
    required this.projectId,
    required this.modelId,
  });

  final String? projectId;
  final String? modelId;
}

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({
    super.key,
    required this.runtime,
    required this.api,
    this.startupError,
    this.initialProjectId,
    this.initialModelId,
    this.initialSection = 0,
  });

  final ProductRuntime runtime;
  final GovernedApiServer api;
  final String? startupError;
  final String? initialProjectId;
  final String? initialModelId;
  final int initialSection;

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  final TextEditingController knowledgeTitleController =
      TextEditingController();
  final TextEditingController knowledgeContentController =
      TextEditingController();
  final TextEditingController knowledgeTagsController =
      TextEditingController();
  final TextEditingController secretLabelController = TextEditingController();
  final TextEditingController secretEnvironmentController =
      TextEditingController();
  final TextEditingController sessionSecretController =
      TextEditingController();
  final TextEditingController tokenLabelController =
      TextEditingController(text: 'Kristin integration');
  final TextEditingController tokenScopesController = TextEditingController(
    text:
        'schema:read,projects:read,projects:write,models:read,commands:prepare,runs:create,runs:read,runs:execute,runs:control,events:read,knowledge:read,knowledge:write,secrets:manage,audit:read,support:create',
  );
  final TextEditingController apiPortController = TextEditingController();
  final TextEditingController originsController = TextEditingController();
  final TextEditingController ollamaController = TextEditingController();
  final TextEditingController ollamaLoadTimeoutController =
      TextEditingController();
  final TextEditingController ollamaLoadRetriesController =
      TextEditingController();
  final TextEditingController ollamaKeepAliveController =
      TextEditingController();
  final TextEditingController compatibleController = TextEditingController();
  final TextEditingController mcpLabelController = TextEditingController();
  final TextEditingController mcpExecutableController =
      TextEditingController();
  final TextEditingController mcpArgumentsController = TextEditingController();
  final TextEditingController mcpToolsController = TextEditingController();
  final TextEditingController mcpProtocolController =
      TextEditingController(text: '2024-11-05');

  int section = 0;
  bool busy = false;
  String status = 'Settings are ready';
  String? error;
  List<ProjectRecord> projects = <ProjectRecord>[];
  List<ModelIdentity> models = <ModelIdentity>[];
  List<SecretReference> secretReferences = <SecretReference>[];
  List<ApiTokenRecord> apiTokens = <ApiTokenRecord>[];
  List<McpTrustRecord> mcpTrust = <McpTrustRecord>[];
  List<KnowledgeEntry> knowledge = <KnowledgeEntry>[];
  Map<String, dynamic> auditStatus = <String, dynamic>{};
  String? selectedProjectId;
  String? selectedModelId;
  String? selectedSecretReferenceId;
  String? selectedOpenAiSecretReferenceId;
  bool localOnly = true;
  bool allowPackageNetwork = false;
  bool apiEnabled = false;

  ProductRuntime get runtime => widget.runtime;

  @override
  void initState() {
    super.initState();
    selectedProjectId = widget.initialProjectId;
    selectedModelId = widget.initialModelId;
    section = widget.initialSection.clamp(0, _settingsSections.length - 1).toInt();
    _seedSettings();
    unawaited(_load());
  }

  void _seedSettings() {
    final settings = runtime.settings;
    apiPortController.text = settings.apiPort.toString();
    originsController.text = settings.allowedOrigins.join('\n');
    ollamaController.text = settings.ollamaBaseUrl;
    ollamaLoadTimeoutController.text =
        settings.ollamaLoadTimeoutSeconds.toString();
    ollamaLoadRetriesController.text = settings.ollamaLoadRetries.toString();
    ollamaKeepAliveController.text =
        settings.ollamaKeepAliveMinutes.toString();
    compatibleController.text = settings.openAiCompatibleBaseUrl;
    selectedOpenAiSecretReferenceId =
        settings.openAiApiKeyReferenceId.isEmpty
            ? null
            : settings.openAiApiKeyReferenceId;
    localOnly = settings.localOnly;
    allowPackageNetwork = settings.allowPackageNetwork;
    apiEnabled = settings.apiEnabled;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      knowledgeTitleController,
      knowledgeContentController,
      knowledgeTagsController,
      secretLabelController,
      secretEnvironmentController,
      sessionSecretController,
      tokenLabelController,
      tokenScopesController,
      apiPortController,
      originsController,
      ollamaController,
      ollamaLoadTimeoutController,
      ollamaLoadRetriesController,
      ollamaKeepAliveController,
      compatibleController,
      mcpLabelController,
      mcpExecutableController,
      mcpArgumentsController,
      mcpToolsController,
      mcpProtocolController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<T?> _perform<T>(
    String activity,
    Future<T> Function() action, {
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() {
        busy = true;
        error = null;
        status = activity;
      });
    }
    try {
      final result = await action();
      if (!silent && mounted) {
        setState(() {
          status = '$activity completed';
        });
      }
      return result;
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact('$failure');
          status = '$activity failed';
        });
      }
      return null;
    } finally {
      if (!silent && mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> _load() async {
    await _perform<void>('Loading settings', () async {
      projects = await runtime.listProjects();
      if (selectedProjectId == null ||
          !projects.any((project) => project.id == selectedProjectId)) {
        selectedProjectId = projects.firstOrNull?.id;
      }
      secretReferences = await runtime.listSecretReferences();
      if (selectedSecretReferenceId == null ||
          !secretReferences.any(
            (reference) => reference.id == selectedSecretReferenceId,
          )) {
        selectedSecretReferenceId = secretReferences.firstOrNull?.id;
      }
      apiTokens = await runtime.listApiTokens();
      mcpTrust = await runtime.listMcpTrust();
      auditStatus = await runtime.verifyAudit();
      await _refreshModels(silent: true);
      await _refreshKnowledge(silent: true);
    });
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshModels({bool silent = false}) async {
    await _perform<void>('Finding installed AI models', () async {
      models = await runtime.discoverModels();
      if (selectedModelId == null ||
          !models.any((model) => model.exactId == selectedModelId)) {
        selectedModelId = models.firstOrNull?.exactId;
      }
    }, silent: silent);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshKnowledge({bool silent = false}) async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      knowledge = <KnowledgeEntry>[];
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await _perform<void>('Loading project sources', () async {
      knowledge = await runtime.listKnowledge(projectId);
    }, silent: silent);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveSettings() async {
    await _perform<void>('Saving settings', () async {
      final settings = runtime.settings.copyWith(
        apiEnabled: apiEnabled,
        apiPort: int.tryParse(apiPortController.text.trim()) ??
            runtime.settings.apiPort,
        allowedOrigins: originsController.text
            .split(RegExp(r'[\r\n]+'))
            .map((origin) => origin.trim())
            .where((origin) => origin.isNotEmpty)
            .toSet(),
        ollamaBaseUrl: ollamaController.text.trim(),
        ollamaLoadTimeoutSeconds:
            int.tryParse(ollamaLoadTimeoutController.text.trim()) ??
                runtime.settings.ollamaLoadTimeoutSeconds,
        ollamaLoadRetries:
            int.tryParse(ollamaLoadRetriesController.text.trim()) ??
                runtime.settings.ollamaLoadRetries,
        ollamaKeepAliveMinutes:
            int.tryParse(ollamaKeepAliveController.text.trim()) ??
                runtime.settings.ollamaKeepAliveMinutes,
        openAiCompatibleBaseUrl: compatibleController.text.trim(),
        openAiApiKeyReferenceId: selectedOpenAiSecretReferenceId ?? '',
        localOnly: localOnly,
        allowPackageNetwork: allowPackageNetwork,
      );
      await runtime.updateSettings(settings);
      _seedSettings();
    });
  }

  Future<void> _issueToken() async {
    await _perform<void>('Creating an API token', () async {
      final issued = await runtime.issueApiToken(
        label: tokenLabelController.text,
        scopes: tokenScopesController.text
            .split(',')
            .map((scope) => scope.trim())
            .where((scope) => scope.isNotEmpty)
            .toSet(),
        projectId: selectedProjectId,
      );
      apiTokens = await runtime.listApiTokens();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Copy this token now'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Kristin stores only the token hash. The plaintext will not be shown again.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    issued.plaintext,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('I stored it securely'),
              ),
            ],
          );
        },
      );
    });
  }

  void _close() {
    Navigator.of(context).pop(
      AdvancedSettingsResult(
        projectId: selectedProjectId,
        modelId: selectedModelId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 980;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Kristin',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Settings'),
            Text(
              'Advanced controls stay here, away from everyday tasks',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusPill(
                label: widget.api.isRunning
                    ? 'API running locally'
                    : 'API stopped',
                icon: widget.api.isRunning ? Icons.api : Icons.api_outlined,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _statusBar(),
          if (compact) _compactNavigation(),
          Expanded(
            child: Row(
              children: <Widget>[
                if (!compact) _settingsNavigation(),
                if (!compact) const VerticalDivider(width: 1),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    final startup = widget.startupError;
    if (!busy && error == null && startup == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: error != null || startup != null
          ? colors.errorContainer
          : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: <Widget>[
            if (busy)
              const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.error_outline,
                size: 18,
                color: colors.onErrorContainer,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                startup ?? error ?? status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (error != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () {
                  setState(() {
                    error = null;
                  });
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingsNavigation() {
    return SizedBox(
      width: 250,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: List<Widget>.generate(_settingsSections.length, (index) {
          final item = _settingsSections[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ListTile(
              selected: section == index,
              selectedTileColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Icon(item.icon),
              title: Text(item.label),
              subtitle: Text(item.description, maxLines: 2),
              onTap: () {
                setState(() {
                  section = index;
                });
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _compactNavigation() {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: _settingsSections.length,
        separatorBuilder: (context, index) {
          return const SizedBox(width: 8);
        },
        itemBuilder: (context, index) {
          final item = _settingsSections[index];
          return ChoiceChip(
            selected: section == index,
            avatar: Icon(item.icon, size: 18),
            label: Text(item.label),
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  section = index;
                });
              }
            },
          );
        },
      ),
    );
  }

  Widget _content() => switch (section) {
        0 => _generalPage(),
        1 => _modelsPage(),
        2 => _sourcesPage(),
        3 => _privacyPage(),
        4 => _integrationsPage(),
        _ => _developerPage(),
      };

  Widget _generalPage() {
    return _scroll(<Widget>[
      const StudioPageHeader(
        title: 'General',
        subtitle:
            'Choose safe defaults. Kristin still asks before any task-specific access or external effect.',
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _projectDropdown(),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: localOnly,
              title: const Text('Keep everything local'),
              subtitle: const Text(
                'Blocks web research and package downloads, even when a task requests them.',
              ),
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        localOnly = value;
                        if (value) {
                          allowPackageNetwork = false;
                        }
                      });
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: allowPackageNetwork,
              title: const Text('Allow approved package downloads'),
              subtitle: const Text(
                'Still requires a project-bound approval for every task that installs dependencies.',
              ),
              onChanged: busy || localOnly
                  ? null
                  : (value) {
                      setState(() {
                        allowPackageNetwork = value;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save defaults'),
              ),
            ),
          ],
        ),
      ),
      const StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Everyday tasks stay simple',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('Auto AI and auto mode'),
              subtitle: Text(
                'The New task screen chooses sensible defaults. Exact models and modes remain available under Advanced details.',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.shield_outlined),
              title: Text('No beginner bypass'),
              subtitle: Text(
                'The simple interface uses the same contracts, permissions, checkpoints, verification, and audit trail.',
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _modelsPage() {
    return _scroll(<Widget>[
      const StudioPageHeader(
        title: 'AI models',
        subtitle:
            'Kristin normally uses Auto AI. Here you can configure providers and inspect exact model identities.',
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: ollamaController,
              decoration: const InputDecoration(
                labelText: 'Ollama base URL',
                helperText: 'Loopback is recommended for local models.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                SizedBox(
                  width: 230,
                  child: TextField(
                    controller: ollamaLoadTimeoutController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cold-load timeout (seconds)',
                      helperText: '60–3600; default 480',
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: TextField(
                    controller: ollamaLoadRetriesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cold-load retries',
                      helperText: '0–2; default 1',
                    ),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: ollamaKeepAliveController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Keep model loaded (minutes)',
                      helperText: '1–120; default 15',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Kristin preloads Ollama models before agent work. A Stop action cancels an active load immediately.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: compatibleController,
              decoration: const InputDecoration(
                labelText: 'OpenAI-compatible base URL',
                helperText: 'Optional. Use a named secret reference for its key.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey<String?>(
                'openai-secret:$selectedOpenAiSecretReferenceId',
              ),
              initialValue: secretReferences.any(
                (reference) => reference.id == selectedOpenAiSecretReferenceId,
              )
                  ? selectedOpenAiSecretReferenceId
                  : null,
              decoration: const InputDecoration(
                labelText: 'API key secret reference',
              ),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...secretReferences.map((reference) {
                  return DropdownMenuItem<String?>(
                    value: reference.id,
                    child: Text(
                      '${reference.label} · ${reference.environmentKey}',
                    ),
                  );
                }),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        selectedOpenAiSecretReferenceId = value;
                      });
                    },
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _saveSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save provider settings'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(_refreshModels());
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Find installed models'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (models.isEmpty)
        const EmptyStateCard(
          icon: Icons.memory_outlined,
          title: 'No installed model found',
          message:
              'Start Ollama or configure a compatible provider, then find installed models again.',
        ),
      ...models.map((model) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.memory),
            title: SelectableText(model.exactId),
            subtitle: Text(
              'Parameters: ${model.parameterSize.isEmpty ? 'not reported' : model.parameterSize} · '
              'Quantization: ${model.quantization.isEmpty ? 'not reported' : model.quantization}',
            ),
            selected: model.exactId == selectedModelId,
            onTap: () {
              setState(() {
                selectedModelId = model.exactId;
              });
            },
            trailing: model.exactId == selectedModelId
                ? const Icon(Icons.check_circle)
                : null,
          ),
        );
      }),
    ]);
  }

  Widget _sourcesPage() {
    return _scroll(<Widget>[
      StudioPageHeader(
        title: 'Sources',
        subtitle:
            'Add project notes and inspect downloaded research. Sources remain separate from source code and model instructions.',
        trailing: SizedBox(width: 300, child: _projectDropdown()),
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: knowledgeTitleController,
              decoration: const InputDecoration(labelText: 'Source title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: knowledgeContentController,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Content',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: knowledgeTagsController,
              decoration: const InputDecoration(
                labelText: 'Tags, separated by commas',
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy || selectedProjectId == null
                    ? null
                    : () {
                        unawaited(
                          _perform<void>('Adding a project source', () async {
                            await runtime.addKnowledge(
                              projectId: selectedProjectId!,
                              title: knowledgeTitleController.text,
                              content: knowledgeContentController.text,
                              tags: knowledgeTagsController.text
                                  .split(',')
                                  .map((tag) => tag.trim())
                                  .where((tag) => tag.isNotEmpty)
                                  .toSet(),
                            );
                            knowledgeTitleController.clear();
                            knowledgeContentController.clear();
                            knowledgeTagsController.clear();
                            knowledge = await runtime.listKnowledge(
                              selectedProjectId!,
                            );
                          }),
                        );
                      },
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Add source'),
              ),
            ),
          ],
        ),
      ),
      if (knowledge.isEmpty)
        const EmptyStateCard(
          icon: Icons.menu_book_outlined,
          title: 'No sources yet',
          message:
              'Add a note here, or let an approved task research public documentation and store its provenance.',
        ),
      ...knowledge.map((entry) {
        return Card(
          child: ExpansionTile(
            leading: Icon(
              entry.trust == 'untrusted_external_data'
                  ? Icons.public
                  : Icons.note_outlined,
            ),
            title: Text(entry.title),
            subtitle: Text(
              '${entry.trust} · ${entry.tags.join(', ')}'
              '${entry.sourceUrl.isEmpty ? '' : '\n${entry.sourceUrl}'}',
            ),
            trailing: IconButton(
              tooltip: 'Delete source',
              onPressed: busy
                  ? null
                  : () {
                      unawaited(
                        _perform<void>('Deleting a source', () async {
                          await runtime.deleteKnowledge(entry.id);
                          if (selectedProjectId != null) {
                            knowledge = await runtime.listKnowledge(
                              selectedProjectId!,
                            );
                          }
                        }),
                      );
                    },
              icon: const Icon(Icons.delete_outline),
            ),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SelectableText(entry.content),
                    const SizedBox(height: 10),
                    SelectableText(
                      'SHA-256 ${entry.contentHash}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    ]);
  }

  Widget _privacyPage() {
    return _scroll(<Widget>[
      const StudioPageHeader(
        title: 'Privacy & access',
        subtitle:
            'Store references, not secret values. API tokens are scoped, expiring, revocable, and stored only as hashes.',
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Named secrets',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretLabelController,
              decoration: const InputDecoration(
                labelText: 'Friendly label',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secretEnvironmentController,
              decoration: const InputDecoration(
                labelText: 'Environment variable name',
                hintText: 'TELEGRAM_BOT_TOKEN',
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () {
                        unawaited(
                          _perform<void>('Registering a secret name', () async {
                            final reference =
                                await runtime.registerSecretReference(
                              label: secretLabelController.text,
                              environmentKey:
                                  secretEnvironmentController.text,
                            );
                            secretReferences =
                                await runtime.listSecretReferences();
                            selectedSecretReferenceId = reference.id;
                            secretLabelController.clear();
                            secretEnvironmentController.clear();
                          }),
                        );
                      },
                icon: const Icon(Icons.key_outlined),
                label: const Text('Register secret name'),
              ),
            ),
            const Divider(height: 34),
            DropdownButtonFormField<String>(
              key: ValueKey<String?>(
                'session-secret:$selectedSecretReferenceId',
              ),
              initialValue: secretReferences.any(
                (reference) => reference.id == selectedSecretReferenceId,
              )
                  ? selectedSecretReferenceId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Secret to load for this session',
              ),
              items: secretReferences.map((reference) {
                return DropdownMenuItem<String>(
                  value: reference.id,
                  child: Text(
                    '${reference.label} · ${reference.environmentKey}',
                  ),
                );
              }).toList(),
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        selectedSecretReferenceId = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sessionSecretController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Session-only value',
                helperText:
                    'Never written to disk. It is cleared when Kristin exits.',
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: selectedSecretReferenceId == null
                    ? null
                    : () {
                        try {
                          runtime.secrets.setSessionValue(
                            selectedSecretReferenceId!,
                            sessionSecretController.text,
                          );
                          sessionSecretController.clear();
                          setState(() {
                            status =
                                'Session secret loaded and redaction enabled';
                          });
                        } catch (failure) {
                          setState(() {
                            error = runtime.redactor.redact('$failure');
                          });
                        }
                      },
                icon: const Icon(Icons.lock_clock_outlined),
                label: const Text('Load for this session'),
              ),
            ),
          ],
        ),
      ),
      if (secretReferences.isNotEmpty)
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Registered secret names',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ...secretReferences.map((reference) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(reference.label),
                  subtitle: Text(reference.environmentKey),
                );
              }),
            ],
          ),
        ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'API tokens',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenLabelController,
              decoration: const InputDecoration(labelText: 'Token label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenScopesController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Scopes, separated by commas',
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: busy ? null : _issueToken,
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('Create scoped token'),
              ),
            ),
          ],
        ),
      ),
      ...apiTokens.map((token) {
        return Card(
          child: ListTile(
            leading: Icon(
              token.isActive ? Icons.key : Icons.key_off_outlined,
            ),
            title: Text(token.label),
            subtitle: Text(
              '${token.scopes.join(', ')}\nExpires ${token.expiresAt.toLocal()}'
              '${token.projectId == null ? '' : ' · selected project only'}',
            ),
            isThreeLine: true,
            trailing: token.isActive
                ? IconButton(
                    tooltip: 'Revoke token',
                    icon: const Icon(Icons.block),
                    onPressed: busy
                        ? null
                        : () {
                            unawaited(
                              _perform<void>('Revoking a token', () async {
                                await runtime.revokeApiToken(token.id);
                                apiTokens = await runtime.listApiTokens();
                              }),
                            );
                          },
                  )
                : null,
          ),
        );
      }),
    ]);
  }

  Widget _integrationsPage() {
    return _scroll(<Widget>[
      const StudioPageHeader(
        title: 'Integrations',
        subtitle:
            'Configure the authenticated local API and project-bound MCP servers. Both remain off until explicitly started or trusted.',
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Authenticated local API',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: apiEnabled,
              title: const Text('Remember API as enabled'),
              subtitle: const Text(
                'The server binds only to 127.0.0.1 and still requires an active scoped token.',
              ),
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        apiEnabled = value;
                      });
                    },
            ),
            TextField(
              controller: apiPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Loopback port'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: originsController,
              minLines: 2,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Allowed browser origins, one per line',
                helperText: 'Exact origins only. Wildcards are rejected.',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _saveSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save API settings'),
                ),
                FilledButton.icon(
                  onPressed: busy || widget.api.isRunning
                      ? null
                      : () {
                          unawaited(
                            _perform<void>('Starting the local API', () async {
                              if (apiTokens
                                  .where((token) => token.isActive)
                                  .isEmpty) {
                                throw ProductException(
                                  'api_token_required',
                                  'Create at least one active token before starting the API.',
                                );
                              }
                              await widget.api.start();
                            }),
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start API'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !widget.api.isRunning
                      ? null
                      : () {
                          unawaited(
                            _perform<void>(
                              'Stopping the local API',
                              widget.api.stop,
                            ),
                          );
                        },
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop API'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Endpoint: http://127.0.0.1:${runtime.settings.apiPort}/v1\n'
              'OpenAPI: GET /v1/openapi.json · Events: GET /v1/events?after=<sequence>',
            ),
          ],
        ),
      ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'MCP trust',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Servers are tied to the selected project, executable hash, protocol version, expiry, and exact tool names.',
            ),
            const SizedBox(height: 14),
            _projectDropdown(),
            const SizedBox(height: 12),
            TextField(
              controller: mcpLabelController,
              decoration: const InputDecoration(labelText: 'Server label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mcpExecutableController,
              decoration: const InputDecoration(
                labelText: 'Absolute MCP executable path',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mcpArgumentsController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Arguments, one per line',
                helperText: 'No shell command string is accepted.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mcpToolsController,
              decoration: const InputDecoration(
                labelText: 'Allowed MCP tool names, separated by commas',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mcpProtocolController,
              decoration: const InputDecoration(labelText: 'Protocol version'),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy || selectedProjectId == null
                    ? null
                    : () {
                        unawaited(
                          _perform<void>('Trusting an exact MCP server', () async {
                            await runtime.trustMcp(
                              projectId: selectedProjectId!,
                              label: mcpLabelController.text,
                              executablePath: mcpExecutableController.text,
                              arguments: mcpArgumentsController.text
                                  .split(RegExp(r'[\r\n]+'))
                                  .map((item) => item.trim())
                                  .where((item) => item.isNotEmpty)
                                  .toList(),
                              allowedTools: mcpToolsController.text
                                  .split(',')
                                  .map((item) => item.trim())
                                  .where((item) => item.isNotEmpty)
                                  .toSet(),
                              protocolVersion:
                                  mcpProtocolController.text.trim(),
                            );
                            mcpTrust = await runtime.listMcpTrust();
                            mcpLabelController.clear();
                            mcpExecutableController.clear();
                            mcpArgumentsController.clear();
                            mcpToolsController.clear();
                          }),
                        );
                      },
                icon: const Icon(Icons.hub_outlined),
                label: const Text('Trust exact server'),
              ),
            ),
          ],
        ),
      ),
      ...mcpTrust
          .where((record) => record.projectId == selectedProjectId)
          .map((record) {
        return Card(
          child: ListTile(
            leading: Icon(record.isActive ? Icons.hub : Icons.link_off),
            title: Text(record.label),
            subtitle: SelectableText(
              'SHA-256 ${record.executableHash}\n'
              'Tools: ${record.allowedTools.join(', ')}\n'
              'Expires ${record.expiresAt.toLocal()}',
            ),
            isThreeLine: true,
            trailing: record.isActive
                ? IconButton(
                    tooltip: 'Revoke MCP trust',
                    icon: const Icon(Icons.block),
                    onPressed: busy
                        ? null
                        : () {
                            unawaited(
                              _perform<void>('Revoking MCP trust', () async {
                                await runtime.revokeMcpTrust(record.id);
                                mcpTrust = await runtime.listMcpTrust();
                              }),
                            );
                          },
                  )
                : null,
          ),
        );
      }),
    ]);
  }

  Future<bool> _confirmAllLogsExport() async {
    if (!mounted) { return false; }
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.archive_outlined),
            title: const Text('Save all diagnostic logs?'),
            content: const SizedBox(
              width: 560,
              child: Text(
                'The ZIP contains redacted retained run state, evidence metadata, events, audit records, budget counters, and bounded process output. It can still contain project names, request text, URLs, relative paths, errors, command output, and model-response previews. Review it before sharing.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Save all logs'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _developerPage() {
    return _scroll(<Widget>[
      const StudioPageHeader(
        title: 'Developer & diagnostics',
        subtitle:
            'Inspect the audit chain, release boundary, and support bundle rules. Source-like payloads are hashed and recognized secrets are redacted, but review the archive before sharing it.',
      ),
      if (widget.startupError != null)
        StudioPanel(
          child: Text(
            widget.startupError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Audit chain',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            SelectableText(auditStatus.toString()),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(
                            _perform<void>('Verifying the audit chain', () async {
                              auditStatus = await runtime.verifyAudit();
                            }),
                          );
                        },
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Verify audit chain'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(
                            _perform<void>('Saving diagnostic logs', () async {
                              if (!await _confirmAllLogsExport()) { return; }
                              final file = await runtime.createSupportBundle(
                                projectId: selectedProjectId,
                                includeAllLogs: true,
                              );
                              final hash = Sha256.hex(await file.readAsBytes());
                              status = 'Diagnostic logs: ${file.path} · SHA-256 $hash';
                            }),
                          );
                        },
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Save all logs ZIP'),
                ),
              ],
            ),
          ],
        ),
      ),
      StudioPanel(
        child: SelectableText(
          'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n'
          'Data-root fingerprint: ${Sha256.text(runtime.directories.root.path)}\n'
          'Product: Kristin Local Agent $kristinVersion\n' 'Classification: source-release preview\n' 'Owner Mode: roadmap target only in this source release\n' 'Workers: Linux reference worker when available; Windows/macOS native workers fail closed\n' 'Support boundary: reviewed source tree and source-only gates\n'
          'Active path: main.dart → ProductRuntime → PreparedCommandService → RunCoordinator → governed tools\n'
          'UI path: Simple Studio → friendly plan → grouped approval → governed runtime',
        ),
      ),
      const StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Log detail levels',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            SizedBox(height: 10),
            Text(
              'Activity → Logs provides Simple, Technical, and Raw views of the same redacted event stream. The default interface never hides execution state; it translates it into understandable language.',
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _projectDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey<String?>('settings-project:$selectedProjectId'),
      initialValue: projects.any((project) => project.id == selectedProjectId)
          ? selectedProjectId
          : null,
      decoration: const InputDecoration(labelText: 'Project'),
      items: projects.map((project) {
        return DropdownMenuItem<String>(
          value: project.id,
          child: Text(project.name),
        );
      }).toList(),
      onChanged: busy
          ? null
          : (value) {
              setState(() {
                selectedProjectId = value;
              });
              unawaited(_refreshKnowledge(silent: true));
            },
    );
  }

  Widget _scroll(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        ...children.expand((widget) {
          return <Widget>[widget, const SizedBox(height: 14)];
        }),
        const SizedBox(height: 50),
      ],
    );
  }
}

class _SettingsSection {
  const _SettingsSection(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

const List<_SettingsSection> _settingsSections = <_SettingsSection>[
  _SettingsSection(
    'General',
    'Safe everyday defaults',
    Icons.tune_outlined,
  ),
  _SettingsSection(
    'AI models',
    'Providers and exact models',
    Icons.memory_outlined,
  ),
  _SettingsSection(
    'Sources',
    'Project knowledge and research',
    Icons.menu_book_outlined,
  ),
  _SettingsSection(
    'Privacy & access',
    'Secrets and API tokens',
    Icons.shield_outlined,
  ),
  _SettingsSection(
    'Integrations',
    'Local API and MCP',
    Icons.hub_outlined,
  ),
  _SettingsSection(
    'Developer',
    'Audit, release boundary, and support',
    Icons.developer_mode_outlined,
  ),
];
