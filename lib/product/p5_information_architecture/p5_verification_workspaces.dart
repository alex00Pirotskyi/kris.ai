part of 'p5_prototype.dart';

extension _P5VerificationWorkspaces
    on _P5InformationArchitecturePrototypeState {
  Widget _verificationWorkspace(BuildContext context) {
    final state = controller.state;
    final advanced =
        state.experienceLevel.index >= P5ExperienceLevel.advanced.index;
    final developer = state.experienceLevel == P5ExperienceLevel.developer;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Verification Center',
          subtitle:
              'Test Center definitions and Development Verification records are presented without changing their authority.',
          icon: Icons.verified_outlined,
        ),
        const _BoundaryNotice(
          message:
              'A green test result is not an independent review, certification, platform-support, or release-support decision.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const <Widget>[
            _DomainCard(
              key: Key('domain-test-execution'),
              title: 'Test execution',
              value: 'PASS',
              detail: 'Fixture result only',
              icon: Icons.check_circle_outline,
            ),
            _DomainCard(
              key: Key('domain-independent-review'),
              title: 'Independent review',
              value: 'NOT_REVIEWED',
              detail: 'Worker B decision required',
              icon: Icons.rate_review_outlined,
            ),
            _DomainCard(
              key: Key('domain-certification'),
              title: 'Certification',
              value: 'NOT_EVALUATED',
              detail: 'No certification PASS inferred',
              icon: Icons.workspace_premium_outlined,
            ),
            _DomainCard(
              key: Key('domain-capability-support'),
              title: 'Capability support',
              value: 'SOURCE_FOUNDATION',
              detail: 'Prototype scope only',
              icon: Icons.extension_outlined,
            ),
            _DomainCard(
              key: Key('domain-platform-support'),
              title: 'Platform support',
              value: 'UNSUPPORTED',
              detail: 'No product behavior claim',
              icon: Icons.desktop_windows_outlined,
            ),
            _DomainCard(
              key: Key('domain-release-support'),
              title: 'Release support',
              value: 'UNSUPPORTED',
              detail: 'No release readiness claim',
              icon: Icons.rocket_launch_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Affected tests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Changed paths: lib/product/p5_information_architecture/**, test/product/p5_information_architecture/**',
                ),
                if (state.verificationRequested)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: _StatusChip(
                      key: Key('affected-tests-selected'),
                      label: 'Affected tests selected deterministically',
                      icon: Icons.rule_folder_outlined,
                    ),
                  ),
                const SizedBox(height: 12),
                for (final result in P5PrototypeFixtures.verificationResults)
                  Semantics(
                    label:
                        '${result.title}: ${result.state.label}. Test execution result only.',
                    child: ListTile(
                      key: Key('verification-result-${result.testId}'),
                      leading: Icon(_resultIcon(result.state)),
                      title: Text(result.title),
                      subtitle: Text(<String>[
                        if (advanced) result.evidenceLabel,
                        if (developer) result.testId,
                      ].join('\n')),
                      trailing: _StatusChip(
                        label: result.state.label,
                        icon: _resultIcon(result.state),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!advanced)
          _RecoveryCard(
            state: 'READY',
            title: 'Need receipts and stable IDs?',
            message:
                'Advanced reveals evidence summaries. Developer additionally reveals raw Test Center identity.',
            actionLabel: 'Switch to Advanced',
            onAction: () =>
                controller.changeExperienceLevel(P5ExperienceLevel.advanced),
          ),
        if (developer)
          Card(
            key: const Key('developer-verification-record'),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: SelectableText(
                '{"moduleId":"tm.p5-information-architecture","resultState":"PASS","certificationStatus":"NOT_EVALUATED","capabilitySupport":"SOURCE_FOUNDATION"}',
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _evidenceWorkspace(BuildContext context) {
    final state = controller.state;
    final advanced =
        state.experienceLevel.index >= P5ExperienceLevel.advanced.index;
    final savedRun = P5PrototypeFixtures.runs
        .where((run) => run.id == state.selectedRunId)
        .firstOrNull;
    final evidence = savedRun == null
        ? const <P5EvidenceFixture>[]
        : P5PrototypeFixtures.evidenceForRun(savedRun.id);
    final selected = savedRun == null
        ? null
        : evidence
                .where((item) => item.id == state.selectedEvidenceId)
                .firstOrNull ??
            evidence.firstOrNull;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Evidence',
          subtitle:
              'Reopen typed saved-run evidence without turning presentation fixtures into production claims.',
          icon: Icons.receipt_long_outlined,
        ),
        for (final item in const <(String, String, String)>[
          (
            'evidence.plan-receipt',
            'Plan receipt',
            'Goals, bounded steps, and requested access',
          ),
          (
            'evidence.run-timeline',
            'Run timeline',
            'Deterministic fixture events with retained context',
          ),
          (
            'evidence.verification-summary',
            'Verification summary',
            'Test states separated from certification and support',
          ),
        ])
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(item.$2),
              subtitle: Text(advanced ? '${item.$3}\n${item.$1}' : item.$3),
              trailing: const Icon(Icons.open_in_new),
            ),
          ),
        const SizedBox(height: 12),
        if (savedRun == null)
          const KeyedSubtree(
            key: Key('evidence-no-saved-run'),
            child: _BoundaryNotice(
              message:
                  'Select a saved run in Runs / Activity to reopen typed artifact, diff, citation, and receipt viewers. Current in-memory runs do not fabricate saved evidence.',
            ),
          )
        else ...<Widget>[
          Card(
            key: const Key('saved-run-evidence-index'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Saved evidence • ${savedRun.title}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('${evidence.length} supported viewer types'),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final index = SizedBox(
                        height: 420,
                        child: SingleChildScrollView(
                          key: const Key('saved-run-evidence-scroll'),
                          child: Column(
                            children: <Widget>[
                              for (final item in evidence)
                                ListTile(
                                  key: Key('evidence-item-${item.kind.name}'),
                                  selected: item.id == selected?.id,
                                  leading: Icon(_evidenceKindIcon(item.kind)),
                                  title: Text(item.kind.label),
                                  subtitle: Text(
                                    advanced
                                        ? '${item.summary}\n${item.mediaType} • ${item.byteLength} bytes'
                                        : item.summary,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () =>
                                      controller.selectEvidence(item.id),
                                ),
                            ],
                          ),
                        ),
                      );
                      final viewer = selected == null
                          ? const _BoundaryNotice(
                              message:
                                  'Choose a supported saved-run evidence type to open its viewer.',
                            )
                          : _evidenceViewer(context, selected);
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(width: 360, child: index),
                            const SizedBox(width: 16),
                            Expanded(child: viewer),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          index,
                          const SizedBox(height: 12),
                          viewer,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        const _BoundaryNotice(
          message:
              'Evidence shown here is deterministic saved-run fixture data. It does not claim a live evidence-store read, independent certification, or production support.',
        ),
      ],
    );
  }

  Widget _evidenceViewer(BuildContext context, P5EvidenceFixture fixture) {
    return Card(
      key: Key('evidence-viewer-${fixture.kind.name}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_evidenceKindIcon(fixture.kind)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fixture.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${fixture.mediaType} • ${fixture.byteLength} bytes'),
            const SizedBox(height: 12),
            _evidenceViewerBody(context, fixture),
          ],
        ),
      ),
    );
  }

  Widget _evidenceViewerBody(
    BuildContext context,
    P5EvidenceFixture fixture,
  ) {
    switch (fixture.kind) {
      case P5EvidenceKind.image:
        try {
          final imageBytes = base64Decode(fixture.content);
          return Container(
            key: const Key('evidence-image-preview'),
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Semantics(
                  image: true,
                  label: 'Deterministic saved-run image preview',
                  child: Image.memory(
                    imageBytes,
                    key: const Key('p5-evidence-image-bytes'),
                    width: 160,
                    height: 90,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => const Text(
                      'Saved image bytes could not be decoded.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('64 × 36 deterministic PNG fixture preview'),
              ],
            ),
          );
        } on FormatException {
          return const _BoundaryNotice(
            message:
                'Saved image evidence is malformed and cannot be previewed.',
          );
        }
      case P5EvidenceKind.markdown:
        return Column(
          key: const Key('evidence-markdown-preview'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fixture.content.split('\n').map((line) {
            if (line.startsWith('# ')) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  line.substring(2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }
            return SelectableText(line);
          }).toList(growable: false),
        );
      case P5EvidenceKind.table:
        final rows = fixture.content
            .split('\n')
            .map((line) => line.split('|'))
            .toList(growable: false);
        final header = rows.first;
        return SingleChildScrollView(
          key: const Key('evidence-table-preview'),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: header
                .map((cell) => DataColumn(label: Text(cell)))
                .toList(growable: false),
            rows: rows
                .skip(1)
                .map(
                  (row) => DataRow(
                    cells: row
                        .map((cell) => DataCell(Text(cell)))
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
          ),
        );
      case P5EvidenceKind.citation:
        return Container(
          key: const Key('evidence-citation-preview'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(fixture.content),
        );
      case P5EvidenceKind.textMetadata:
      case P5EvidenceKind.binaryMetadata:
      case P5EvidenceKind.json:
      case P5EvidenceKind.diff:
      case P5EvidenceKind.receipt:
        return SelectableText(
          fixture.content,
          key: Key('evidence-${fixture.kind.name}-preview'),
          style: const TextStyle(fontFamily: 'monospace'),
        );
    }
  }

  IconData _evidenceKindIcon(P5EvidenceKind kind) {
    return switch (kind) {
      P5EvidenceKind.textMetadata => Icons.text_snippet_outlined,
      P5EvidenceKind.binaryMetadata => Icons.data_object_outlined,
      P5EvidenceKind.image => Icons.image_outlined,
      P5EvidenceKind.markdown => Icons.article_outlined,
      P5EvidenceKind.json => Icons.code_outlined,
      P5EvidenceKind.table => Icons.table_chart_outlined,
      P5EvidenceKind.diff => Icons.difference_outlined,
      P5EvidenceKind.citation => Icons.format_quote_outlined,
      P5EvidenceKind.receipt => Icons.receipt_long_outlined,
    };
  }

  Widget _ownerModeWorkspace(BuildContext context) {
    final liveHandle = widget.ownerMode;
    if (liveHandle != null) {
      final active = liveHandle.runtime;
      final available = liveHandle.available;
      final settings = active?.controller.current;
      final supervision = active?.supervisionSnapshot();
      final terminalCount = active?.terminalModel.tabs.length ?? 0;
      final status = !available
          ? 'Unavailable'
          : settings!.enabled
              ? (settings.unattended ? 'Enabled unattended' : 'Enabled')
              : 'Available, off';
      return _scrollWorkspace(
        context,
        children: <Widget>[
          const _WorkspaceHeader(
            title: 'Owner Mode',
            subtitle:
                'Live status from the shipped P2 runtime. Authority-changing controls remain in the top-level Owner Mode workspace.',
            icon: Icons.admin_panel_settings_outlined,
          ),
          Card(
            key: const Key('owner-mode-live-state-card'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    status,
                    key: const Key('owner-mode-live-state-label'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    available
                        ? 'Approval: ${settings!.approvalPolicy.name} • '
                            'terminals: $terminalCount • supervised trees: '
                            '${(supervision?['watchdogIds'] as List?)?.length ?? 0}'
                        : liveHandle.recoveryMessage,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _StatusChip(
                        label: liveHandle.completionEligible
                            ? 'P1 authority eligible'
                            : 'No production completion claim',
                        icon: Icons.verified_user_outlined,
                      ),
                      _StatusChip(
                        label: 'Runtime: '
                            '${available ? 'available' : liveHandle.diagnosticCode}',
                        icon: available
                            ? Icons.check_circle_outline
                            : Icons.gpp_bad_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _BoundaryNotice(
                    message:
                        'Experience reads P2 state only. Enabling, disabling, terminal control, emergency kill, and approvals continue through the existing real Owner Mode workspace.',
                  ),
                  if (widget.onOpenOwnerMode != null) ...<Widget>[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('open-real-owner-mode'),
                      onPressed: widget.onOpenOwnerMode,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open real Owner Mode'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final state = controller.state.ownerModeState;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Owner Mode',
          subtitle:
              'Truthful presentation states only. The current controlled behavior remains BLOCKED_EXTERNAL.',
          icon: Icons.admin_panel_settings_outlined,
        ),
        Semantics(
          liveRegion: true,
          label:
              'Owner Mode is ${state.label}. Simulation only. Runtime semantics are unchanged.',
          child: Card(
            key: const Key('owner-mode-state-card'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    state.label,
                    key: const Key('owner-mode-state-label'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Source implementation, hosted source validation, controlled behavioral certification, platform support, and release support remain separate.',
                  ),
                  const SizedBox(height: 12),
                  const _BoundaryNotice(
                    message:
                        'No capability grant, process, terminal, emergency-stop, or Owner Mode service is invoked by this prototype.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        key: const Key('owner-preview-unavailable'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.unavailable,
                        ),
                        child: const Text('Preview unavailable'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-disabled'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.disabled,
                        ),
                        child: const Text('Preview disabled'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-available'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.availableNotEnabled,
                        ),
                        child: const Text('Preview available'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-enabled'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.enabled,
                        ),
                        child: const Text('Preview enabled'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-running'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.running,
                        ),
                        child: const Text('Preview running'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-paused'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.paused,
                        ),
                        child: const Text('Preview paused'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-stopping'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.stopping,
                        ),
                        child: const Text('Preview stopping'),
                      ),
                      FilledButton.tonal(
                        key: const Key('owner-preview-blocked'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.blockedByEnvironment,
                        ),
                        child: const Text('Preview controlled blocker'),
                      ),
                      OutlinedButton(
                        key: const Key('owner-preview-error'),
                        onPressed: () => controller.setOwnerModePresentation(
                          P5OwnerModePresentationState.error,
                        ),
                        child: const Text('Preview error'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
