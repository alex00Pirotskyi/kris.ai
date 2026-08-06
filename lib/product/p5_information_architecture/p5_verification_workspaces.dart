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
    final advanced = controller.state.experienceLevel.index >=
        P5ExperienceLevel.advanced.index;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Evidence',
          subtitle:
              'Receipts stay understandable in Simple while exact identity is progressively disclosed.',
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
        const _BoundaryNotice(
          message:
              'Evidence shown here is deterministic prototype data and never asserts production behavior.',
        ),
      ],
    );
  }

  Widget _ownerModeWorkspace(BuildContext context) {
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
