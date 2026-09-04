part of 'p5_prototype.dart';

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BoundaryNotice extends StatelessWidget {
  const _BoundaryNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Claim boundary: $message',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    super.key,
    required this.state,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String state;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StatusChip(label: state, icon: Icons.info_outline),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(message),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: $value. $detail',
      child: SizedBox(
        width: 230,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(detail),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _P5BackIntent extends Intent {
  const _P5BackIntent();
}

class _P5ForwardIntent extends Intent {
  const _P5ForwardIntent();
}

class _P5LaunchComposerIntent extends Intent {
  const _P5LaunchComposerIntent();
}

class _P5WorkspaceIntent extends Intent {
  const _P5WorkspaceIntent(this.workspace);

  final P5WorkspaceId workspace;
}

IconData _workspaceIcon(P5WorkspaceId workspace) => switch (workspace) {
  P5WorkspaceId.homeChat => Icons.chat_bubble_outline,
  P5WorkspaceId.projects => Icons.folder_outlined,
  P5WorkspaceId.runsActivity => Icons.timeline_outlined,
  P5WorkspaceId.verificationCenter => Icons.verified_outlined,
  P5WorkspaceId.evidence => Icons.receipt_long_outlined,
  P5WorkspaceId.ownerMode => Icons.admin_panel_settings_outlined,
  P5WorkspaceId.modelsProviders => Icons.memory_outlined,
  P5WorkspaceId.capabilitiesIntegrations => Icons.extension_outlined,
  P5WorkspaceId.settingsDiagnostics => Icons.settings_outlined,
  P5WorkspaceId.webStudio => Icons.web_outlined,
  P5WorkspaceId.searchResearch => Icons.search_outlined,
  P5WorkspaceId.nativeAutomation => Icons.desktop_windows_outlined,
  P5WorkspaceId.devices => Icons.devices_other_outlined,
};

IconData _resultIcon(P5VerificationResultState state) => switch (state) {
  P5VerificationResultState.pass => Icons.check_circle_outline,
  P5VerificationResultState.fail => Icons.cancel_outlined,
  P5VerificationResultState.error => Icons.error_outline,
  P5VerificationResultState.skipped => Icons.skip_next_outlined,
  P5VerificationResultState.blocked => Icons.block_outlined,
  P5VerificationResultState.unknown => Icons.help_outline,
  P5VerificationResultState.flaky => Icons.change_circle_outlined,
  P5VerificationResultState.notImplemented => Icons.construction_outlined,
};

String _shortcutFor(P5WorkspaceId workspace) => switch (workspace) {
  P5WorkspaceId.homeChat => '1',
  P5WorkspaceId.projects => '2',
  P5WorkspaceId.runsActivity => '3',
  P5WorkspaceId.verificationCenter => '4',
  P5WorkspaceId.ownerMode => '5',
  P5WorkspaceId.settingsDiagnostics => '6',
  P5WorkspaceId.evidence => '7',
  P5WorkspaceId.modelsProviders => '8',
  P5WorkspaceId.capabilitiesIntegrations => '9',
  _ => '—',
};
