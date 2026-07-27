import 'package:flutter/material.dart';

import 'domain.dart';

enum StudioSection { newTask, activity, projects, templates }

enum SimpleTaskMode { auto, askOnly, planOnly, choose }

enum WorkspaceView { preview, files, changes, tests, flow }

enum InspectorSection { summary, steps, changes, tests, sources, logs }

enum LogDetail { simple, technical, raw }

class StudioDestination {
  const StudioDestination({
    required this.section,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final StudioSection section;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<StudioDestination> studioDestinations = <StudioDestination>[
  StudioDestination(
    section: StudioSection.newTask,
    label: 'New task',
    icon: Icons.add_circle_outline,
    selectedIcon: Icons.add_circle,
  ),
  StudioDestination(
    section: StudioSection.activity,
    label: 'Activity',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
  ),
  StudioDestination(
    section: StudioSection.projects,
    label: 'Projects',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
  StudioDestination(
    section: StudioSection.templates,
    label: 'Templates',
    icon: Icons.auto_awesome_mosaic_outlined,
    selectedIcon: Icons.auto_awesome_mosaic,
  ),
];

class StudioTemplate {
  const StudioTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.prompt,
    required this.icon,
    required this.suggestedMode,
    required this.tags,
  });

  final String id;
  final String title;
  final String description;
  final String prompt;
  final IconData icon;
  final CommandMode suggestedMode;
  final List<String> tags;
}

const List<StudioTemplate> studioTemplates = <StudioTemplate>[
  StudioTemplate(
    id: 'website',
    title: 'Build a website',
    description: 'Create a polished website, test it, and prepare it to share.',
    prompt:
        'Build a polished responsive website. Create the project structure, implement the pages and interactions, run the available checks, and prepare a clear local run guide.',
    icon: Icons.language_outlined,
    suggestedMode: CommandMode.build,
    tags: <String>['Website', 'Design', 'Tests'],
  ),
  StudioTemplate(
    id: 'telegram_bot',
    title: 'Create a Telegram bot',
    description:
        'Build a safe bot with commands, storage, tests, and Docker support.',
    prompt:
        'Create a production-ready Telegram bot with clear commands, configuration through named secrets, conversation storage, automated tests, and a Docker deployment package. Use current official documentation when network research is approved.',
    icon: Icons.smart_toy_outlined,
    suggestedMode: CommandMode.build,
    tags: <String>['Telegram', 'Bot', 'Docker'],
  ),
  StudioTemplate(
    id: 'application',
    title: 'Create an application',
    description:
        'Turn an idea into a tested desktop, mobile, or local application.',
    prompt:
        'Create a complete application from this project. Choose the most suitable existing stack, implement the core user journey, add tests and error handling, and provide simple run and build instructions.',
    icon: Icons.apps_outlined,
    suggestedMode: CommandMode.build,
    tags: <String>['App', 'Product', 'Quality'],
  ),
  StudioTemplate(
    id: 'fix_project',
    title: 'Fix my project',
    description: 'Find the cause, repair it safely, and verify the result.',
    prompt:
        'Inspect this project, identify the root cause of the reported problems, make the smallest safe repair, run the relevant checks, and explain what changed.',
    icon: Icons.build_circle_outlined,
    suggestedMode: CommandMode.fix,
    tags: <String>['Debug', 'Repair', 'Verify'],
  ),
  StudioTemplate(
    id: 'improve_project',
    title: 'Improve my project',
    description:
        'Review usability, reliability, structure, and release readiness.',
    prompt:
        'Review this project for user experience, reliability, maintainability, security, and release readiness. Implement the highest-value improvements that can be verified safely.',
    icon: Icons.trending_up_outlined,
    suggestedMode: CommandMode.review,
    tags: <String>['Review', 'UX', 'Quality'],
  ),
  StudioTemplate(
    id: 'ask_code',
    title: 'Ask about my code',
    description: 'Get a clear answer grounded in the selected project.',
    prompt:
        'Explain the selected part of this project in clear language. Point to the important files and describe risks or next steps without changing anything.',
    icon: Icons.chat_bubble_outline,
    suggestedMode: CommandMode.ask,
    tags: <String>['Explain', 'No changes', 'Project'],
  ),
];

CommandMode inferCommandMode(String request) {
  final lower = request.trim().toLowerCase();
  if (lower.isEmpty) {
    return CommandMode.build;
  }
  if (isConversationalRequest(request)) {
    return CommandMode.ask;
  }

  bool hasAny(Iterable<String> values) => values.any(lower.contains);

  if (hasAny(
      <String>['fix ', 'repair ', 'debug ', 'broken', 'error', 'failing'])) {
    return CommandMode.fix;
  }
  if (hasAny(
      <String>['review ', 'audit ', 'assess ', 'inspect ', 'critique '])) {
    return CommandMode.review;
  }
  if (hasAny(<String>['run ', 'launch ', 'start the ', 'execute ']) &&
      !hasAny(<String>['build ', 'create ', 'implement ', 'make '])) {
    return CommandMode.run;
  }
  if (hasAny(<String>[
    'analyze ',
    'analyse ',
    'investigate ',
    'compare ',
    'examine '
  ])) {
    return CommandMode.analyze;
  }
  if (hasAny(<String>['plan ', 'roadmap', 'architecture', 'design a plan']) &&
      !hasAny(<String>['build ', 'create ', 'implement ', 'make '])) {
    return CommandMode.plan;
  }
  if ((lower.endsWith('?') ||
          hasAny(<String>[
            'what ',
            'why ',
            'how ',
            'explain ',
            'tell me ',
            'where ',
            'when '
          ])) &&
      !hasAny(<String>[
        'build ',
        'create ',
        'implement ',
        'make ',
        'change ',
        'add '
      ])) {
    return CommandMode.ask;
  }
  return CommandMode.build;
}

CommandMode resolveTaskMode({
  required String request,
  required SimpleTaskMode choice,
  required CommandMode chosenMode,
}) {
  return switch (choice) {
    SimpleTaskMode.auto => inferCommandMode(request),
    SimpleTaskMode.askOnly => CommandMode.ask,
    SimpleTaskMode.planOnly => CommandMode.plan,
    SimpleTaskMode.choose => chosenMode,
  };
}

String simpleModeLabel(SimpleTaskMode value) => switch (value) {
      SimpleTaskMode.auto => 'Auto — recommended',
      SimpleTaskMode.askOnly => 'Ask only',
      SimpleTaskMode.planOnly => 'Plan only',
      SimpleTaskMode.choose => 'Choose a mode',
    };

String friendlyRunState(RunState state) => switch (state) {
      RunState.prepared => 'Plan ready',
      RunState.awaitingApproval => 'Waiting for your approval',
      RunState.queued => 'Ready to start',
      RunState.running => 'Kristin is working',
      RunState.paused => 'Paused',
      RunState.cancelling => 'Stopping safely',
      RunState.cancelled => 'Stopped',
      RunState.succeeded => 'Ready',
      RunState.failed => 'Needs attention',
      RunState.interrupted => 'Ready to continue',
    };

String friendlyWorkState(WorkItemState state) => switch (state) {
      WorkItemState.queued => 'Waiting',
      WorkItemState.running => 'Working',
      WorkItemState.blocked => 'Blocked',
      WorkItemState.awaitingApproval => 'Needs you',
      WorkItemState.succeeded => 'Done',
      WorkItemState.failed => 'Needs attention',
      WorkItemState.cancelled => 'Stopped',
    };

String jobSizeLabel(int complexity) {
  if (complexity <= 3) {
    return 'Small job';
  }
  if (complexity <= 6) {
    return 'Medium job';
  }
  if (complexity <= 8) {
    return 'Large job';
  }
  return 'Ambitious job';
}

String modeLabel(CommandMode mode) => switch (mode) {
      CommandMode.ask => 'Ask',
      CommandMode.analyze => 'Analyze',
      CommandMode.plan => 'Plan',
      CommandMode.build => 'Build',
      CommandMode.fix => 'Fix',
      CommandMode.review => 'Review',
      CommandMode.run => 'Run',
    };

class AccessGroup {
  const AccessGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.scopes,
    this.highRisk = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Set<PermissionScope> scopes;
  final bool highRisk;
}

List<AccessGroup> groupPermissions(Set<PermissionScope> scopes) {
  final groups = <AccessGroup>[];
  final fileScopes = scopes.intersection(<PermissionScope>{
    PermissionScope.projectRead,
    PermissionScope.projectWrite,
    PermissionScope.projectDelete,
  });
  if (fileScopes.isNotEmpty) {
    groups.add(AccessGroup(
      title: fileScopes.contains(PermissionScope.projectWrite)
          ? 'Work in this project folder'
          : 'Read this project folder',
      description: fileScopes.contains(PermissionScope.projectDelete)
          ? 'Read, change, and remove individual checkpointed files inside the selected project.'
          : fileScopes.contains(PermissionScope.projectWrite)
              ? 'Read and safely change checkpointed files inside the selected project.'
              : 'Read files only inside the selected project.',
      icon: Icons.folder_copy_outlined,
      scopes: fileScopes,
      highRisk: fileScopes.contains(PermissionScope.projectDelete),
    ));
  }

  if (scopes.contains(PermissionScope.networkResearch)) {
    groups.add(const AccessGroup(
      title: 'Read approved documentation',
      description:
          'Fetch public HTTPS documentation through size, redirect, and private-network protections.',
      icon: Icons.public_outlined,
      scopes: <PermissionScope>{PermissionScope.networkResearch},
    ));
  }
  if (scopes.contains(PermissionScope.networkPackages)) {
    groups.add(const AccessGroup(
      title: 'Install project packages',
      description:
          'Download approved dependencies for this project when package networking is enabled.',
      icon: Icons.inventory_2_outlined,
      scopes: <PermissionScope>{PermissionScope.networkPackages},
    ));
  }

  final processScopes = scopes.intersection(<PermissionScope>{
    PermissionScope.executeFinite,
    PermissionScope.executeManaged,
  });
  if (processScopes.isNotEmpty) {
    groups.add(AccessGroup(
      title: processScopes.contains(PermissionScope.executeManaged)
          ? 'Run and keep the project active'
          : 'Run checks and local commands',
      description: processScopes.contains(PermissionScope.executeManaged)
          ? 'Run bounded checks and start a tracked local project process.'
          : 'Run bounded tests, builds, and project commands without a shell.',
      icon: Icons.play_circle_outline,
      scopes: processScopes,
      highRisk: processScopes.contains(PermissionScope.executeManaged),
    ));
  }

  if (scopes.contains(PermissionScope.secretUse)) {
    groups.add(const AccessGroup(
      title: 'Use a named secret',
      description:
          'Resolve only an approved named secret reference. The value is never shown or saved in source.',
      icon: Icons.key_outlined,
      scopes: <PermissionScope>{PermissionScope.secretUse},
      highRisk: true,
    ));
  }
  if (scopes.contains(PermissionScope.deploymentPackage)) {
    groups.add(const AccessGroup(
      title: 'Prepare an export package',
      description:
          'Create a scanned deployment archive with a manifest and dependency inventory.',
      icon: Icons.archive_outlined,
      scopes: <PermissionScope>{PermissionScope.deploymentPackage},
    ));
  }
  if (scopes.contains(PermissionScope.mcpConnect)) {
    groups.add(const AccessGroup(
      title: 'Use a trusted integration',
      description:
          'Connect only to a separately approved project-bound MCP server and its exact tool list.',
      icon: Icons.hub_outlined,
      scopes: <PermissionScope>{PermissionScope.mcpConnect},
      highRisk: true,
    ));
  }
  return groups;
}

String humanEventText(EventEnvelope event, {RunRecord? run}) {
  String workTitle() {
    final id = event.data['workItemId']?.toString();
    if (id == null || run == null) {
      return 'the next step';
    }
    return run.items
            .where((progress) => progress.item.id == id)
            .map((progress) => progress.item.title)
            .firstOrNull ??
        'the next step';
  }

  return switch (event.type) {
    'command.prepared' => 'I made a safe plan for your task.',
    'run.created' => 'Your task is ready to start.',
    'run.approved' => 'Access approved. I can begin safely.',
    'run.started' => 'I started working on your project.',
    'run.paused' => 'I paused the task and kept its state safe.',
    'run.resumed' => 'I continued from the saved point.',
    'run.cancelling' => 'I am stopping safely.',
    'run.cancelled' => 'The task stopped. Your checkpoint is safe.',
    'run.succeeded' => 'Everything finished and the checks passed.',
    'run.failed' => 'I found a problem and stopped safely.',
    'work_item.started' => 'Working on ${workTitle()}.',
    'work_item.succeeded' => 'Finished ${workTitle()}.',
    'work_item.attempt_failed' =>
      'A check failed, so I am reviewing ${workTitle()}.',
    'evidence.recorded' => 'Saved a verification record for this step.',
    'project.added' => 'Project added and ready to use.',
    'settings.updated' => 'Settings saved.',
    _ => event.type.replaceAll('.', ' '),
  };
}

int runPhaseIndex({PreparedCommand? prepared, RunRecord? run}) {
  if (run == null) {
    return prepared == null ? 0 : 1;
  }
  if (run.state == RunState.succeeded) {
    return 4;
  }
  if (run.state == RunState.failed || run.state == RunState.cancelled) {
    return 3;
  }
  if (run.state == RunState.awaitingApproval || run.state == RunState.queued) {
    return 1;
  }
  if (run.state == RunState.running ||
      run.state == RunState.paused ||
      run.state == RunState.cancelling ||
      run.state == RunState.interrupted) {
    if (run.items.isEmpty) {
      return 2;
    }
    final succeeded =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final verificationStarted = run.items.any((item) {
      final lower = item.item.title.toLowerCase();
      return (lower.contains('verify') || lower.contains('test')) &&
          item.state != WorkItemState.queued;
    });
    return verificationStarted || succeeded / run.items.length >= 0.7 ? 3 : 2;
  }
  return 1;
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: emphasized ? 1 : 0,
      color: emphasized ? colors.surfaceContainerLow : colors.surface,
      child: Padding(padding: padding, child: child),
    );
  }
}

class StudioPageHeader extends StatelessWidget {
  const StudioPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.centered = false,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
        ),
      ],
    );
    if (trailing == null) {
      return content;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: content),
        const SizedBox(width: 16),
        trailing!,
      ],
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return StudioPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: colors.primaryContainer,
              child: Icon(icon, color: colors.onPrimaryContainer, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.emphasis = false,
  });

  final String label;
  final IconData icon;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color:
            emphasis ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 16,
            color:
                emphasis ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: emphasis
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class QuickTemplateCard extends StatelessWidget {
  const QuickTemplateCard({
    super.key,
    required this.template,
    required this.onTap,
    this.compact = false,
  });

  final StudioTemplate template;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${template.title}. ${template.description}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: compact ? 230 : 300,
          padding: EdgeInsets.all(compact ? 16 : 20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(template.icon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(height: 16),
              Text(
                template.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                template.description,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FivePhaseProgress extends StatelessWidget {
  const FivePhaseProgress({
    super.key,
    required this.prepared,
    required this.run,
  });

  final PreparedCommand? prepared;
  final RunRecord? run;

  static const List<String> _labels = <String>[
    'Understand',
    'Plan',
    'Build',
    'Test',
    'Ready',
  ];

  @override
  Widget build(BuildContext context) {
    final active = runPhaseIndex(prepared: prepared, run: run);
    final failed =
        run?.state == RunState.failed || run?.state == RunState.cancelled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(_labels.length, (index) {
              return _phaseChip(context, index, active, failed);
            }),
          );
        }
        return Row(
          children: List<Widget>.generate(_labels.length * 2 - 1, (slot) {
            if (slot.isOdd) {
              final lineIndex = slot ~/ 2;
              return Expanded(
                child: Container(
                  height: 2,
                  color: lineIndex < active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              );
            }
            final index = slot ~/ 2;
            return _phaseChip(context, index, active, failed);
          }),
        );
      },
    );
  }

  Widget _phaseChip(BuildContext context, int index, int active, bool failed) {
    final colors = Theme.of(context).colorScheme;
    final done =
        index < active || index == 4 && run?.state == RunState.succeeded;
    final current = index == active && !done;
    final error = failed && current;
    final background = error
        ? colors.errorContainer
        : done
            ? colors.primaryContainer
            : current
                ? colors.secondaryContainer
                : colors.surfaceContainerHighest;
    final foreground = error
        ? colors.onErrorContainer
        : done
            ? colors.onPrimaryContainer
            : current
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            error
                ? Icons.error_outline
                : done
                    ? Icons.check
                    : current
                        ? Icons.more_horiz
                        : Icons.circle_outlined,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Text(
            _labels[index],
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                ),
          ),
        ],
      ),
    );
  }
}

class FlowNode extends StatelessWidget {
  const FlowNode({
    super.key,
    required this.title,
    required this.state,
    this.onTap,
  });

  final String title;
  final WorkItemState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (state) {
      WorkItemState.succeeded => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      WorkItemState.running => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
          Icons.autorenew,
        ),
      WorkItemState.failed => (
          colors.errorContainer,
          colors.onErrorContainer,
          Icons.error_outline,
        ),
      WorkItemState.awaitingApproval => (
          colors.tertiaryContainer,
          colors.onTertiaryContainer,
          Icons.front_hand_outlined,
        ),
      WorkItemState.blocked => (
          colors.errorContainer,
          colors.onErrorContainer,
          Icons.block_outlined,
        ),
      WorkItemState.cancelled => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          Icons.stop_circle_outlined,
        ),
      WorkItemState.queued => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          Icons.schedule_outlined,
        ),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: foreground, size: 20),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              friendlyWorkState(state),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
