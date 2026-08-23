part of 'p5_prototype.dart';

extension _P5SupportWorkspaces on _P5InformationArchitecturePrototypeState {
  Widget _modelsWorkspace(BuildContext context) {
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Models and Providers',
          subtitle:
              'Provider and model readiness is visible without exposing credentials.',
          icon: Icons.memory_outlined,
        ),
        const Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.memory),
                title: Text('Local fixture model'),
                subtitle: Text('Deterministic presentation data'),
                trailing: _StatusChip(
                  label: 'READY',
                  icon: Icons.check_circle_outline,
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('OpenAI-compatible provider'),
                subtitle: Text('No network request is made by this prototype'),
                trailing: _StatusChip(
                  label: 'OFFLINE',
                  icon: Icons.cloud_off_outlined,
                ),
              ),
            ],
          ),
        ),
        _RecoveryCard(
          key: const Key('no-model-recovery'),
          state: 'BLOCKED',
          title: 'Representative no-model state',
          message: 'Planning is blocked until a model becomes available.',
          actionLabel: 'Use local fixture model',
          onAction: () =>
              controller.apply(P5PrototypeAction.restoreModelFixture),
        ),
      ],
    );
  }

  Widget _capabilitiesWorkspace(BuildContext context) {
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Capabilities and Integrations',
          subtitle:
              'Unavailable foundations stay visible with exact state and next requirement.',
          icon: Icons.extension_outlined,
        ),
        for (final capability in P5PrototypeFixtures.capabilities)
          Semantics(
            label:
                '${capability.workspace.label}: ${capability.state.label}. ${capability.reason}',
            child: Card(
              child: ListTile(
                key: Key('capability-${capability.workspace.name}'),
                leading: Icon(_workspaceIcon(capability.workspace)),
                title: Text(capability.workspace.label),
                subtitle: Text(
                  '${capability.reason}\nNext: ${capability.nextRequirement}',
                ),
                trailing: _StatusChip(
                  label: capability.state.label,
                  icon: Icons.info_outline,
                ),
                onTap: () => controller.selectWorkspace(capability.workspace),
              ),
            ),
          ),
      ],
    );
  }

  Widget _settingsWorkspace(BuildContext context) {
    final state = controller.state;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Settings and Diagnostics',
          subtitle:
              'Experience level affects disclosure only. Failure fixtures provide one clear recovery action.',
          icon: Icons.settings_outlined,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Experience level'),
                      Text(
                        'No authority, permission, or runtime behavior changes.',
                      ),
                    ],
                  ),
                ),
                DropdownButton<P5ExperienceLevel>(
                  key: const Key('settings-experience-selector'),
                  value: state.experienceLevel,
                  items: P5ExperienceLevel.values
                      .map(
                        (level) => DropdownMenuItem<P5ExperienceLevel>(
                          value: level,
                          child: Text(level.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (level) {
                    if (level != null) {
                      controller.changeExperienceLevel(level);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        Text(
          'Failure and recovery fixtures',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final failure in P5PrototypeFixtures.failures)
          Card(
            key: Key(failure.id),
            child: ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: Text('${failure.title} — ${failure.state}'),
              subtitle: Text(failure.message),
              trailing: TextButton(
                onPressed: () {
                  if (failure.id == 'failure.no-project') {
                    controller.apply(P5PrototypeAction.createSampleProject);
                  } else if (failure.id == 'failure.no-model') {
                    controller.selectWorkspace(P5WorkspaceId.modelsProviders);
                  } else if (failure.id == 'failure.interrupted-run') {
                    controller.selectRun('run.p5-existing-001');
                    controller.apply(P5PrototypeAction.retryInterruptedRun);
                  } else if (failure.id == 'failure.offline') {
                    controller.apply(
                      P5PrototypeAction.acknowledgeOfflineFixture,
                    );
                  } else if (failure.id == 'failure.permission-denied') {
                    controller.showRecoveryMessage(
                      'Permission review is not implemented in P5-001. P5-007 is required before requested access can be reviewed.',
                    );
                  } else if (failure.id == 'failure.capability-blocked') {
                    controller.selectWorkspace(
                      P5WorkspaceId.capabilitiesIntegrations,
                    );
                  } else if (failure.id == 'failure.test-fail') {
                    controller.selectWorkspace(P5WorkspaceId.evidence);
                  } else {
                    controller.selectWorkspace(
                      P5WorkspaceId.verificationCenter,
                    );
                  }
                },
                child: Text(failure.recoveryAction),
              ),
            ),
          ),
        const _BoundaryNotice(
          message:
              'Accessibility certification, performance certification, and human usability certification remain future P5 work.',
        ),
      ],
    );
  }

  Widget _webStudioWorkspace(BuildContext context) {
    const panels = <String>[
      'Files',
      'Editor',
      'Preview',
      'Browser',
      'Inspector',
      'Console',
      'Network',
      'Terminal',
      'Activity',
      'Tests & Evidence',
    ];
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Web Studio',
          subtitle:
              'Live P3 browser integration with explicit dependency boundaries for the editor, preview, inspector, and terminal slices owned elsewhere.',
          icon: Icons.web_asset_outlined,
        ),
        Card(
          key: const Key('web-studio-runtime-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _StatusChip(
                  label: widget.browserRuntimeAvailable
                      ? 'P3 runtime available'
                      : 'P3 ${widget.browserRuntimeStatusCode}',
                  icon: widget.browserRuntimeAvailable
                      ? Icons.check_circle_outline
                      : Icons.report_problem_outlined,
                ),
                _StatusChip(
                  label: _webBrowser == null
                      ? 'Browser service stopped'
                      : 'Browser service running',
                  icon: _webBrowser == null
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                if (_webBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                FilledButton.tonalIcon(
                  key: const Key('web-browser-start-stop'),
                  onPressed: _webBusy
                      ? null
                      : _webBrowser == null
                      ? _startWebBrowser
                      : _stopWebBrowser,
                  icon: Icon(
                    _webBrowser == null ? Icons.play_arrow : Icons.stop,
                  ),
                  label: Text(
                    _webBrowser == null
                        ? 'Start browser service'
                        : 'Stop browser service',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_webError != null)
          _RecoveryCard(
            key: const Key('web-studio-runtime-error'),
            state: 'ERROR',
            title: 'Web Studio runtime action failed',
            message: _webError!,
            actionLabel: 'Clear error',
            onAction: () => mutatePresentation(() => _webError = null),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final panel in panels)
              ChoiceChip(
                label: Text(panel),
                selected: _webPanel == panel,
                onSelected: (_) => mutatePresentation(() => _webPanel = panel),
              ),
          ],
        ),
        _webPanelContent(context),
      ],
    );
  }

  Widget _webPanelContent(BuildContext context) {
    return switch (_webPanel) {
      'Files' => _webDependencyPanel(
        context,
        'Files / project tree',
        'P3-012 owns the transactional project tree/editor authority. This P5 slice does not fork it.',
        Icons.account_tree_outlined,
      ),
      'Editor' => _webDependencyPanel(
        context,
        'Code editor',
        'P3-012 owns editor diagnostics, formatting, search, diff, and source-control hooks.',
        Icons.code_outlined,
      ),
      'Preview' => _webPreviewPanel(context),
      'Browser' => _webBrowserPanel(context),
      'Inspector' => _webInspectorPanel(context),
      'Console' => _webJsonPanel(
        context,
        'Console',
        _observationMap('console'),
        'Observe a page to capture bounded console telemetry.',
      ),
      'Network' => _webJsonPanel(
        context,
        'Network',
        _observationMap('network'),
        'Observe a page to capture sanitized network telemetry.',
      ),
      'Terminal' => _webTerminalPanel(context),
      'Activity' => _webActivityPanel(context),
      'Tests & Evidence' => _webEvidencePanel(context),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _webDependencyPanel(
    BuildContext context,
    String title,
    String detail,
    IconData icon,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(detail),
        trailing: const _StatusChip(
          label: 'DEPENDENCY OWNED',
          icon: Icons.merge_type_outlined,
        ),
      ),
    );
  }

  Widget _webBrowserPanel(BuildContext context) {
    final process = _webBrowser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Sessions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    DropdownButton<P3BrowserSessionKind>(
                      value: _webSessionKind,
                      items: P3BrowserSessionKind.values
                          .map(
                            (kind) => DropdownMenuItem(
                              value: kind,
                              child: Text(kind.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: process == null || _webBusy
                          ? null
                          : (value) => mutatePresentation(
                              () => _webSessionKind = value ?? _webSessionKind,
                            ),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _webProfileController,
                        enabled:
                            _webSessionKind ==
                                P3BrowserSessionKind.persistent &&
                            process != null &&
                            !_webBusy,
                        decoration: const InputDecoration(
                          labelText: 'Persistent profile ID',
                        ),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Downloads'),
                      selected: _webDownloadsEnabled,
                      onSelected: process == null || _webBusy
                          ? null
                          : (value) => mutatePresentation(
                              () => _webDownloadsEnabled = value,
                            ),
                    ),
                    FilterChip(
                      label: const Text('Uploads'),
                      selected: _webUploadsEnabled,
                      onSelected: process == null || _webBusy
                          ? null
                          : (value) => mutatePresentation(
                              () => _webUploadsEnabled = value,
                            ),
                    ),
                    FilledButton.icon(
                      key: const Key('web-open-session'),
                      onPressed: process == null || _webBusy
                          ? null
                          : _openWebSession,
                      icon: const Icon(Icons.add),
                      label: const Text('New session'),
                    ),
                    OutlinedButton.icon(
                      onPressed: process == null || _webBusy
                          ? null
                          : _refreshWebState,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                for (final session in _webSessions)
                  ListTile(
                    dense: true,
                    selected: session.sessionId == _webSelectedSessionId,
                    leading: Icon(
                      session.kind == P3BrowserSessionKind.persistent
                          ? Icons.person_outline
                          : Icons.lock_outline,
                    ),
                    title: Text(
                      session.profileId == null
                          ? session.sessionId
                          : '${session.profileId} • ${session.sessionId}',
                    ),
                    subtitle: Text(
                      '${session.kind.name} • ${session.pageCount} pages • '
                      'download ${session.downloadsEnabled ? 'on' : 'off'} • '
                      'upload ${session.uploadsEnabled ? 'on' : 'off'}',
                    ),
                    onTap: () => _selectWebSession(session.sessionId),
                    trailing: IconButton(
                      tooltip: 'Close session',
                      onPressed: _webBusy
                          ? null
                          : () => _closeWebSession(session.sessionId),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Pages',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('web-open-page'),
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webBusy
                          ? null
                          : _openWebPage,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Open page'),
                    ),
                  ],
                ),
                for (final page in _webPages)
                  ListTile(
                    dense: true,
                    selected: page.pageId == _webSelectedPageId,
                    leading: const Icon(Icons.tab_outlined),
                    title: Text(page.pageId),
                    onTap: () => _selectWebPage(page.pageId),
                    trailing: IconButton(
                      tooltip: 'Close page',
                      onPressed: _webBusy
                          ? null
                          : () => _closeWebPage(page.pageId),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const Key('web-local-url'),
                        controller: _webUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Local preview URL',
                          helperText:
                              'Only localhost / 127.0.0.1 / ::1 or about:blank',
                        ),
                        onSubmitted: (_) => _navigateWebPage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('web-navigate-local'),
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webSelectedPageId == null ||
                              _webBusy
                          ? null
                          : _navigateWebPage,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Go'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webSelectedPageId == null ||
                              _webBusy
                          ? null
                          : _observeWebPage,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Observe'),
                    ),
                  ],
                ),
                if (_webObservation != null) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectableText(
                    '${_webObservation!.observation['title']}\n'
                    '${_webObservation!.observation['url']}\n'
                    'observation ${_webObservation!.observationHash}',
                  ),
                ],
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Structured browser action',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    DropdownButton<String>(
                      value: _webLocatorStrategy,
                      items:
                          const <String>[
                                'role',
                                'label',
                                'placeholder',
                                'text',
                                'testId',
                                'css',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: _webBusy
                          ? null
                          : (value) => mutatePresentation(
                              () => _webLocatorStrategy =
                                  value ?? _webLocatorStrategy,
                            ),
                    ),
                    if (_webLocatorStrategy == 'role')
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _webRoleController,
                          decoration: const InputDecoration(
                            labelText: 'ARIA role',
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 230,
                      child: TextField(
                        controller: _webLocatorController,
                        decoration: InputDecoration(
                          labelText: _webLocatorStrategy == 'role'
                              ? 'Accessible name'
                              : 'Locator',
                        ),
                      ),
                    ),
                    DropdownButton<P3BrowserActionKind>(
                      value: _webAction,
                      items: P3BrowserActionKind.values
                          .map(
                            (action) => DropdownMenuItem(
                              value: action,
                              child: Text(action.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _webBusy
                          ? null
                          : (value) => mutatePresentation(
                              () => _webAction = value ?? _webAction,
                            ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _webActionValueController,
                        decoration: const InputDecoration(
                          labelText: 'Action value',
                        ),
                      ),
                    ),
                    if (_webAction == P3BrowserActionKind.drag)
                      SizedBox(
                        width: 210,
                        child: TextField(
                          controller: _webTargetController,
                          decoration: const InputDecoration(
                            labelText: 'Target locator',
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('web-perform-action'),
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webSelectedPageId == null ||
                              _webBusy
                          ? null
                          : _performWebAction,
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: const Text('Run action'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Controlled transfers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const Key('web-download'),
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webSelectedPageId == null ||
                              _webBusy
                          ? null
                          : _downloadWebPage,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download via locator'),
                    ),
                    SizedBox(
                      width: 270,
                      child: TextField(
                        controller: _webUploadPathController,
                        decoration: const InputDecoration(
                          labelText: 'Absolute upload source path',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: TextField(
                        controller: _webUploadNameController,
                        decoration: const InputDecoration(
                          labelText: 'Upload filename',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _webUploadMimeController,
                        decoration: const InputDecoration(
                          labelText: 'MIME type',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('web-upload'),
                      onPressed:
                          process == null ||
                              _webSelectedSessionId == null ||
                              _webSelectedPageId == null ||
                              _webBusy
                          ? null
                          : _uploadWebPage,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Stage + upload'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _webPreviewPanel(BuildContext context) {
    final screenshot = _observationMap('screenshot');
    final encoded = screenshot?['base64'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Live browser preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (encoded is String && encoded.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: Image.memory(
                  base64Decode(encoded),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              )
            else
              const Text('Observe a page to display its bounded JPEG capture.'),
            const SizedBox(height: 8),
            const _BoundaryNotice(
              message:
                  'This is the canonical P3 observation screenshot. P3-013 hot reload/dev-server preview remains independently owned.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _webInspectorPanel(BuildContext context) {
    if (_webObservation == null) {
      return _webDependencyPanel(
        context,
        'DOM / accessibility inspector',
        'Observe a page to expose the already-landed bounded DOM, visible-text, accessibility, forms, console, and network observations.',
        Icons.account_tree_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _webTextCard(context, 'DOM', _observationText('dom')),
        _webTextCard(
          context,
          'Accessibility',
          _observationText('accessibility'),
        ),
        _webTextCard(context, 'Visible text', _observationText('visibleText')),
        _webJsonPanel(context, 'Forms', <String, Object?>{
          'forms': _webObservation!.observation['forms'],
          'formsTruncated': _webObservation!.observation['formsTruncated'],
        }, 'No forms captured.'),
        const _BoundaryNotice(
          message:
              'The snapshot is live P3 evidence. DOM-to-source mapping remains P3-014 and is not claimed here.',
        ),
      ],
    );
  }

  Widget _webTerminalPanel(BuildContext context) {
    final handle = widget.ownerMode;
    final active = handle?.runtime;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.terminal_outlined),
        title: const Text('Terminal'),
        subtitle: Text(
          handle == null
              ? 'Owner Mode runtime is not bound in this standalone view.'
              : handle.available
              ? '${active!.terminalModel.tabs.length} real Owner Mode terminal tab(s).'
              : handle.recoveryMessage,
        ),
        trailing: widget.onOpenOwnerMode == null
            ? null
            : FilledButton.tonal(
                onPressed: widget.onOpenOwnerMode,
                child: const Text('Open Owner Mode'),
              ),
      ),
    );
  }

  Widget _webActivityPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Browser activity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_webActivity.isEmpty)
              const Text('No Web Studio runtime actions yet.')
            else
              for (final entry in _webActivity)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(entry),
                ),
          ],
        ),
      ),
    );
  }

  Widget _webEvidencePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _webJsonPanel(
          context,
          'P3 runtime provenance',
          widget.browserRuntimeProvenance,
          'No P3 runtime provenance is bound.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Download quarantine receipts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_webDownloads.isEmpty)
                  const Text('No controlled downloads.')
                else
                  for (final receipt in _webDownloads)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.download_done_outlined),
                      title: Text(receipt.suggestedFilename),
                      subtitle: Text(
                        '${receipt.bytes} bytes • ${receipt.sha256}\n'
                        '${receipt.payloadRelativePath}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Discard quarantined download',
                        onPressed: _webBusy
                            ? null
                            : () => _discardWebDownload(receipt),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Upload receipts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_webUploads.isEmpty)
                  const Text('No controlled uploads.')
                else
                  for (final receipt in _webUploads)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.upload_file_outlined),
                      title: Text(receipt.fileName),
                      subtitle: Text(
                        '${receipt.mimeType} • ${receipt.bytes} bytes • '
                        '${receipt.sha256}',
                      ),
                    ),
              ],
            ),
          ),
        ),
        const _BoundaryNotice(
          message:
              'Transfer receipts and observation hashes are canonical P3 evidence. Activity shown here is presentation history only.',
        ),
      ],
    );
  }

  Widget _webJsonPanel(
    BuildContext context,
    String title,
    Map<String, Object?>? value,
    String empty,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (value == null || value.isEmpty)
              Text(empty)
            else
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(value),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _webTextCard(BuildContext context, String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              value.isEmpty ? 'No captured content.' : value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?>? _observationMap(String key) {
    final raw = _webObservation?.observation[key];
    return raw is Map ? Map<String, Object?>.from(raw) : null;
  }

  String _observationText(String key) =>
      _observationMap(key)?['text']?.toString() ?? '';

  Future<void> _runWeb(String label, Future<void> Function() action) async {
    if (_webBusy) return;
    mutatePresentation(() {
      _webBusy = true;
      _webError = null;
    });
    try {
      await action();
      _recordWebActivity(label);
    } catch (error) {
      if (mounted) {
        mutatePresentation(
          () => _webError = error is P3BrowserRuntimeException
              ? error.code
              : 'web_studio_runtime_error',
        );
      }
    } finally {
      if (mounted) mutatePresentation(() => _webBusy = false);
    }
  }

  void _recordWebActivity(String value) {
    if (!mounted) return;
    mutatePresentation(() {
      _webActivity.insert(
        0,
        '${DateTime.now().toUtc().toIso8601String()} • $value',
      );
      if (_webActivity.length > 200) {
        _webActivity.removeRange(200, _webActivity.length);
      }
    });
  }

  Future<void> _startWebBrowser() =>
      _runWeb('browser service started', () async {
        if (!widget.browserRuntimeAvailable) {
          throw StateError(widget.browserRuntimeStatusCode);
        }
        final starter = widget.browserSessionStarter;
        if (starter == null) {
          throw StateError('p5_browser_session_starter_not_bound');
        }
        _webBrowser = await starter();
        await _refreshWebStateImpl();
      });

  Future<void> _stopWebBrowser() =>
      _runWeb('browser service stopped', _p5EmergencyStopBrowser);

  Future<void> _refreshWebState() =>
      _runWeb('browser state refreshed', _refreshWebStateImpl);

  Future<void> _refreshWebStateImpl() async {
    final process = _webBrowser;
    if (process == null) return;
    final sessions = await process.listSessions();
    var selectedSession = _webSelectedSessionId;
    if (!sessions.any((item) => item.sessionId == selectedSession)) {
      selectedSession = sessions.firstOrNull?.sessionId;
    }
    var pages = <P3BrowserPageInfo>[];
    var selectedPage = _webSelectedPageId;
    var uploads = <P3BrowserUploadReceipt>[];
    if (selectedSession != null) {
      pages = await process.listPages(selectedSession);
      if (!pages.any((item) => item.pageId == selectedPage)) {
        selectedPage = pages.firstOrNull?.pageId;
      }
      final session = sessions
          .where((item) => item.sessionId == selectedSession)
          .firstOrNull;
      if (session?.uploadsEnabled == true) {
        uploads = await process.listUploadReceipts(selectedSession);
      }
    } else {
      selectedPage = null;
    }
    final downloads = await process.listDownloads();
    if (!mounted) return;
    mutatePresentation(() {
      _webSessions = sessions;
      _webSelectedSessionId = selectedSession;
      _webPages = pages;
      _webSelectedPageId = selectedPage;
      _webDownloads = downloads;
      _webUploads = uploads;
    });
    widget.globalAutonomy?.updateBrowserSessionCount(sessions.length);
  }

  Future<void> _openWebSession() => _runWeb('browser session opened', () async {
    final session = await _webBrowser!.openSession(
      kind: _webSessionKind,
      profileId: _webSessionKind == P3BrowserSessionKind.persistent
          ? _webProfileController.text.trim()
          : null,
      downloadsEnabled: _webDownloadsEnabled,
      uploadsEnabled: _webUploadsEnabled,
    );
    final page = await _webBrowser!.openPage(session.sessionId);
    if (!mounted) return;
    mutatePresentation(() {
      _webSelectedSessionId = session.sessionId;
      _webSelectedPageId = page.pageId;
      _webObservation = null;
    });
    await _refreshWebStateImpl();
  });

  Future<void> _selectWebSession(String sessionId) async {
    mutatePresentation(() {
      _webSelectedSessionId = sessionId;
      _webSelectedPageId = null;
      _webObservation = null;
    });
    await _runWeb('browser session selected', _refreshWebStateImpl);
  }

  Future<void> _closeWebSession(String sessionId) =>
      _runWeb('browser session closed', () async {
        await _webBrowser!.closeSession(sessionId);
        if (_webSelectedSessionId == sessionId) {
          _webSelectedSessionId = null;
          _webSelectedPageId = null;
          _webObservation = null;
        }
        await _refreshWebStateImpl();
      });

  Future<void> _openWebPage() => _runWeb('browser page opened', () async {
    final page = await _webBrowser!.openPage(_webSelectedSessionId!);
    if (!mounted) return;
    mutatePresentation(() {
      _webSelectedPageId = page.pageId;
      _webObservation = null;
    });
    await _refreshWebStateImpl();
  });

  Future<void> _selectWebPage(String pageId) async {
    mutatePresentation(() {
      _webSelectedPageId = pageId;
      _webObservation = null;
    });
    await _observeWebPage();
  }

  Future<void> _closeWebPage(String pageId) =>
      _runWeb('browser page closed', () async {
        await _webBrowser!.closePage(_webSelectedSessionId!, pageId);
        if (_webSelectedPageId == pageId) {
          _webSelectedPageId = null;
          _webObservation = null;
        }
        await _refreshWebStateImpl();
      });

  Future<void> _navigateWebPage() =>
      _runWeb('local preview navigation completed', () async {
        final observation = await _webBrowser!.navigateLocalPage(
          _webSelectedSessionId!,
          _webSelectedPageId!,
          P3BrowserLocalNavigationRequest(url: _webUrlController.text.trim()),
        );
        if (!mounted) return;
        mutatePresentation(() {
          _webObservation = observation;
          _webUrlController.text = observation.observation['url'].toString();
        });
      });

  Future<void> _observeWebPage() =>
      _runWeb('page observation captured', () async {
        final observation = await _webBrowser!.observePage(
          _webSelectedSessionId!,
          _webSelectedPageId!,
        );
        if (!mounted) return;
        mutatePresentation(() {
          _webObservation = observation;
          _webUrlController.text = observation.observation['url'].toString();
        });
      });

  P3BrowserLocator _webLocator({bool target = false}) {
    final value = target
        ? _webTargetController.text.trim()
        : _webLocatorController.text.trim();
    return switch (_webLocatorStrategy) {
      'role' => P3BrowserLocator.role(
        _webRoleController.text.trim(),
        value,
        exact: true,
      ),
      'label' => P3BrowserLocator.label(value, exact: true),
      'placeholder' => P3BrowserLocator.placeholder(value, exact: true),
      'text' => P3BrowserLocator.text(value, exact: true),
      'testId' => P3BrowserLocator.testId(value),
      _ => P3BrowserLocator.css(value),
    };
  }

  P3BrowserActionRequest _webActionRequest() {
    final locator = _webLocator();
    final raw = _webActionValueController.text;
    return switch (_webAction) {
      P3BrowserActionKind.fill => P3BrowserActionRequest(
        action: P3BrowserActionKind.fill,
        locators: <P3BrowserLocator>[locator],
        value: raw,
      ),
      P3BrowserActionKind.type => P3BrowserActionRequest(
        action: P3BrowserActionKind.type,
        locators: <P3BrowserLocator>[locator],
        value: raw,
      ),
      P3BrowserActionKind.select => P3BrowserActionRequest(
        action: _webAction,
        locators: <P3BrowserLocator>[locator],
        options: raw
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false),
      ),
      P3BrowserActionKind.press => P3BrowserActionRequest(
        action: _webAction,
        locators: <P3BrowserLocator>[locator],
        key: raw.trim(),
      ),
      P3BrowserActionKind.drag => P3BrowserActionRequest(
        action: _webAction,
        locators: <P3BrowserLocator>[locator],
        targetLocators: <P3BrowserLocator>[_webLocator(target: true)],
      ),
      P3BrowserActionKind.scroll => P3BrowserActionRequest(
        action: _webAction,
        locators: <P3BrowserLocator>[locator],
        deltaY: int.tryParse(raw.trim()) ?? 600,
      ),
      _ => P3BrowserActionRequest(
        action: _webAction,
        locators: <P3BrowserLocator>[locator],
      ),
    };
  }

  Future<void> _performWebAction() =>
      _runWeb('structured browser action ${_webAction.name}', () async {
        final result = await _webBrowser!.performAction(
          _webSelectedSessionId!,
          _webSelectedPageId!,
          _webActionRequest(),
        );
        final observation = await _webBrowser!.observePage(
          _webSelectedSessionId!,
          _webSelectedPageId!,
        );
        if (!mounted) return;
        mutatePresentation(() => _webObservation = observation);
        _recordWebActivity(
          'action ${result.action.name} via ${result.locatorStrategy} '
          'changed=${result.observationChanged}',
        );
      });

  Future<void> _downloadWebPage() =>
      _runWeb('controlled download quarantined', () async {
        await _webBrowser!.downloadPage(
          _webSelectedSessionId!,
          _webSelectedPageId!,
          P3BrowserDownloadRequest(locators: <P3BrowserLocator>[_webLocator()]),
        );
        await _refreshWebStateImpl();
      });

  Future<void> _uploadWebPage() =>
      _runWeb('controlled upload completed', () async {
        final stage = await _webBrowser!.stageUpload(
          _webSelectedSessionId!,
          P3BrowserUploadStageRequest(
            sourcePath: _webUploadPathController.text.trim(),
            fileName: _webUploadNameController.text.trim(),
            mimeType: _webUploadMimeController.text.trim(),
          ),
        );
        await _webBrowser!.uploadPage(
          _webSelectedSessionId!,
          _webSelectedPageId!,
          P3BrowserUploadRequest(
            locators: <P3BrowserLocator>[_webLocator()],
            stage: stage,
          ),
        );
        await _refreshWebStateImpl();
      });

  Future<void> _discardWebDownload(P3BrowserDownloadReceipt receipt) =>
      _runWeb('quarantined download discarded', () async {
        await _webBrowser!.discardDownload(
          receipt.downloadId,
          receipt.receiptHash,
        );
        await _refreshWebStateImpl();
      });

  Widget _futureCapabilityWorkspace(
    BuildContext context,
    P5WorkspaceId workspace,
  ) {
    final capability = P5PrototypeFixtures.capabilities
        .where((item) => item.workspace == workspace)
        .first;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        _WorkspaceHeader(
          title: workspace.label,
          subtitle: 'Honest future-capability placeholder',
          icon: _workspaceIcon(workspace),
        ),
        Semantics(
          liveRegion: true,
          label:
              '${workspace.label} is ${capability.state.label}. ${capability.reason}',
          child: _RecoveryCard(
            key: Key('future-capability-${workspace.name}'),
            state: capability.state.label,
            title: '${workspace.label} is not usable',
            message:
                '${capability.reason}\nRequired next: ${capability.nextRequirement}',
            actionLabel: 'Back to Capabilities',
            onAction: () => controller.selectWorkspace(
              P5WorkspaceId.capabilitiesIntegrations,
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrollWorkspace(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Scrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }
}
