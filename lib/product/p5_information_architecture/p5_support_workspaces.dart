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
                          'No authority, permission, or runtime behavior changes.'),
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
                  } else if (failure.id == 'failure.interrupted-run') {
                    controller.apply(P5PrototypeAction.retryInterruptedRun);
                  } else if (failure.id == 'failure.offline') {
                    controller
                        .apply(P5PrototypeAction.acknowledgeOfflineFixture);
                  } else {
                    controller.selectWorkspace(
                      failure.id.contains('test')
                          ? P5WorkspaceId.verificationCenter
                          : P5WorkspaceId.capabilitiesIntegrations,
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
            onAction: () => controller
                .selectWorkspace(P5WorkspaceId.capabilitiesIntegrations),
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
