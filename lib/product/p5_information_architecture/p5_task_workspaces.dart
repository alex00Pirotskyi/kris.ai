part of 'p5_prototype.dart';

extension _P5TaskWorkspaces on _P5InformationArchitecturePrototypeState {
  Widget _homeWorkspace(BuildContext context) {
    final state = controller.state;
    final project = P5PrototypeFixtures.projects
        .where((item) => item.id == state.selectedProjectId)
        .firstOrNull;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        _WorkspaceHeader(
          title: 'What would you like Kristin to do?',
          subtitle:
              'Start simply. Plans, evidence, and technical detail remain available when needed.',
          icon: Icons.chat_bubble_outline,
        ),
        if (project == null)
          _RecoveryCard(
            key: const Key('no-project-state'),
            state: 'EMPTY',
            title: 'Choose a project first',
            message:
                'The prototype keeps every task inside an explicit local project context.',
            actionLabel: 'Choose sample project',
            onAction: () => controller.apply(
              P5PrototypeAction.createSampleProject,
            ),
          )
        else ...<Widget>[
          Card(
            key: const Key('p5-task-composer'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    key: const Key('task-input'),
                    controller: _taskController,
                    enabled: controller.canEditTaskDraft,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: controller.updateTaskDraft,
                    decoration: const InputDecoration(
                      labelText: 'Task',
                      hintText: 'Describe a result in plain language',
                      helperText:
                          'Ctrl+Enter or Cmd+Enter launches this composer.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    toggled: state.planOnly,
                    label:
                        'Plan-only mode. Presentation fixture; authority is unchanged.',
                    child: CheckboxListTile(
                      key: const Key('plan-only-toggle'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: state.planOnly,
                      title: const Text('Plan only'),
                      subtitle: const Text(
                        'Review the plan without presenting an execution state.',
                      ),
                      onChanged: controller.canChangePlanOnly
                          ? (_) => controller.apply(
                                P5PrototypeAction.choosePlanOnly,
                              )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (state.runState != P5RunPresentationState.completed ||
                          state.selectedRunId == null)
                        FilledButton.icon(
                          key: const Key('review-plan-button'),
                          onPressed: controller.canReviewPlan
                              ? () => controller.apply(
                                    P5PrototypeAction.reviewPlan,
                                  )
                              : null,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Review concise plan'),
                        ),
                      OutlinedButton.icon(
                        key: const Key('start-run-button'),
                        onPressed: controller.canLaunchComposer
                            ? controller.launchComposer
                            : null,
                        icon: Icon(
                          state.composerLaunchTiming ==
                                  P5ComposerLaunchTiming.runNow
                              ? Icons.play_arrow
                              : Icons.schedule_outlined,
                        ),
                        label: Text(
                          state.composerLaunchTiming ==
                                  P5ComposerLaunchTiming.runNow
                              ? (state.planOnly
                                  ? 'Review plan only'
                                  : 'Run now')
                              : 'Request schedule',
                        ),
                      ),
                    ],
                  ),
                  if (state.planReviewed) ...<Widget>[
                    const SizedBox(height: 14),
                    _planCard(context),
                  ],
                ],
              ),
            ),
          ),
          _runControlCard(context),
          Card(
            key: const Key('p5-task-composer-details'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Task context and constraints',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'These selections describe task intent. They do not grant runtime authority.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: <Widget>[
                      _composerSelect<String>(
                        key: const Key('composer-project'),
                        label: 'Project',
                        value: state.selectedProjectId!,
                        values: P5PrototypeFixtures.projects
                            .map((item) => item.id)
                            .toList(growable: false),
                        itemLabel: (id) => P5PrototypeFixtures.projects
                            .firstWhere((item) => item.id == id)
                            .name,
                        onChanged: controller.canChangeProjectContext
                            ? (value) {
                                if (value != null) {
                                  controller.selectProject(value);
                                }
                              }
                            : null,
                      ),
                      _composerSelect<P5ComposerProfile>(
                        key: const Key('composer-profile'),
                        label: 'Profile',
                        value: state.composerProfile,
                        values: P5ComposerProfile.values,
                        itemLabel: (value) => value.label,
                        onChanged: controller.canEditComposerContext
                            ? (value) {
                                if (value != null) {
                                  controller.updateComposerProfile(value);
                                }
                              }
                            : null,
                      ),
                      _composerSelect<P5ComposerModel>(
                        key: const Key('composer-model'),
                        label: 'Model',
                        value: state.composerModel,
                        values: P5ComposerModel.values,
                        itemLabel: (value) => value.label,
                        onChanged: controller.canEditComposerContext
                            ? (value) {
                                if (value != null) {
                                  controller.updateComposerModel(value);
                                }
                              }
                            : null,
                      ),
                      _composerSelect<P5ComposerAccess>(
                        key: const Key('composer-access'),
                        label: 'Access request',
                        value: state.composerAccess,
                        values: P5ComposerAccess.values,
                        itemLabel: (value) => value.label,
                        onChanged: controller.canEditComposerContext
                            ? (value) {
                                if (value != null) {
                                  controller.updateComposerAccess(value);
                                }
                              }
                            : null,
                      ),
                      _composerSelect<P5ComposerBudget>(
                        key: const Key('composer-budget'),
                        label: 'Budget',
                        value: state.composerBudget,
                        values: P5ComposerBudget.values,
                        itemLabel: (value) => value.label,
                        onChanged: controller.canEditComposerContext
                            ? (value) {
                                if (value != null) {
                                  controller.updateComposerBudget(value);
                                }
                              }
                            : null,
                      ),
                      _composerSelect<P5ComposerLaunchTiming>(
                        key: const Key('composer-timing'),
                        label: 'Timing',
                        value: state.composerLaunchTiming,
                        values: P5ComposerLaunchTiming.values,
                        itemLabel: (value) => value.label,
                        onChanged: controller.canEditComposerContext
                            ? (value) {
                                if (value != null) {
                                  controller.updateComposerLaunchTiming(value);
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: <Widget>[
                      SizedBox(
                        width: 360,
                        child: TextField(
                          key: const Key('composer-attachments'),
                          controller: _composerAttachmentsController,
                          enabled: controller.canEditComposerContext,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (value) =>
                              controller.updateComposerAttachments(
                            const LineSplitter().convert(value),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Attachment references',
                            helperText:
                                '${state.attachments.length}/8 references • one per line',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 420,
                        child: TextField(
                          key: const Key('composer-criteria'),
                          controller: _composerCriteriaController,
                          enabled: controller.canEditComposerContext,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (value) =>
                              controller.updateAcceptanceCriteria(
                            const LineSplitter().convert(value),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Acceptance criteria',
                            helperText:
                                '${state.acceptanceCriteria.length}/8 criteria • one per line',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _BoundaryNotice(
                    message:
                        'Profile, model, access, budget, attachments, criteria, and schedule are task intent only in this P5 slice. They do not grant runtime authority. Scheduling remains unbound and fails closed.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _composerSelect<T>({
    required Key key,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) itemLabel,
    required ValueChanged<T?>? onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: key,
            value: value,
            isExpanded: true,
            items: values
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(itemLabel(item)),
                  ),
                )
                .toList(growable: false),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context) {
    final state = controller.state;
    final sideEffects = controller.sideEffects;
    final profile = state.composerProfile;
    final attachments = state.attachments.isEmpty
        ? 'None declared.'
        : state.attachments.join(', ');
    final verification = state.acceptanceCriteria.isEmpty
        ? 'No acceptance criteria declared.'
        : state.acceptanceCriteria.join(' • ');
    return Card(
      key: const Key('concise-plan-card'),
      child: SizedBox(
        height: 210,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Concise plan',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              const Text(
                'Review intent, authority boundaries, and verification before launch.',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const Key('p5-plan-review-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _planReviewSection(
                          key: const Key('p5-plan-goal'),
                          title: 'Goal',
                          value: state.taskDraft,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-files'),
                          title: 'Files / attachments',
                          value: attachments,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-commands'),
                          title: 'Commands',
                          value:
                              'None compiled in P5 presentation mode. No command authority is implied.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-sites'),
                          title: 'Sites',
                          value:
                              'None declared in this composer. Browser/network authority is not inferred.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-side-effects'),
                          title: 'Side effects',
                          value:
                              '${sideEffects.filesystemMutations} filesystem, ${sideEffects.networkRequests} network, ${sideEffects.runtimeCommands} runtime, ${sideEffects.ownerModeActions} Owner Mode, ${sideEffects.deviceRequests} device effects executed.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-verification'),
                          title: 'Verification',
                          value: verification,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-risk'),
                          title: 'Risk',
                          value:
                              'NOT_EVALUATED — no deterministic effect plan has been compiled. Do not interpret presentation mode as low risk.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-profile'),
                          title: 'Profile and access intent',
                          value:
                              '${profile.label} • access request: ${state.composerAccess.label} • model intent: ${state.composerModel.label} • budget: ${state.composerBudget.label} • timing: ${state.composerLaunchTiming.label}.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-approval-policy'),
                          title:
                              'Approval policy: ${profile.approvalPolicyLabel}',
                          value: profile.approvalPolicyExplanation,
                        ),
                        const _BoundaryNotice(
                          message:
                              'Access profiles are maximum authority ceilings, not capability grants. This plan review does not authorize files, commands, sites, credentials, or runtime effects.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planReviewSection({
    required Key key,
    required String title,
    required String value,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }

  Widget _runControlCard(BuildContext context) {
    final state = controller.state;
    return Semantics(
      liveRegion: true,
      label: 'Simulated run status: ${state.runState.label}',
      child: Card(
        key: const Key('run-control-card'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Run presentation: ${state.runState.label}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(value: 0.62),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (state.runState == P5RunPresentationState.running)
                    OutlinedButton.icon(
                      key: const Key('pause-run-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.pauseRun),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  if (state.runState == P5RunPresentationState.paused ||
                      state.runState == P5RunPresentationState.interrupted)
                    OutlinedButton.icon(
                      key: const Key('resume-run-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.resumeRun),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                    ),
                  if (state.runState == P5RunPresentationState.running ||
                      state.runState == P5RunPresentationState.paused)
                    OutlinedButton.icon(
                      key: const Key('stop-run-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.stopRun),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                  if (state.runState == P5RunPresentationState.running ||
                      state.runState == P5RunPresentationState.stopping)
                    FilledButton.tonalIcon(
                      key: const Key('complete-run-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.completeRun),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Complete fixture'),
                    ),
                  if (state.runState ==
                      P5RunPresentationState.completed) ...<Widget>[
                    if (state.selectedRunId != null)
                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        onPressed: controller.canReviewPlan
                            ? () => controller.apply(
                                  P5PrototypeAction.reviewPlan,
                                )
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review new plan'),
                      ),
                    FilledButton.tonalIcon(
                      key: const Key('open-evidence-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.openEvidence),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Open evidence (Advanced)'),
                    ),
                    FilledButton.icon(
                      key: const Key('run-verification-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.runVerification),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Run verification fixture'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectsWorkspace(BuildContext context) {
    final state = controller.state;
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Projects',
          subtitle:
              'A selected project is global context and remains stable across workspaces.',
          icon: Icons.folder_outlined,
        ),
        Card(
          child: Column(
            children: <Widget>[
              for (final project in P5PrototypeFixtures.projects)
                Semantics(
                  selected: project.id == state.selectedProjectId,
                  label:
                      '${project.name} project${project.id == state.selectedProjectId ? ', selected' : ''}',
                  child: ListTile(
                    key: Key('project-${project.id}'),
                    selected: project.id == state.selectedProjectId,
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: Text(project.name),
                    subtitle: Text(project.pathLabel),
                    trailing: project.id == state.selectedProjectId
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: controller.canChangeProjectContext
                        ? () => controller.selectProject(project.id)
                        : null,
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                key: const Key('clear-project-button'),
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Preview no-project state'),
                subtitle: const Text('Presentation fixture only'),
                onTap: controller.canChangeProjectContext
                    ? () => controller.apply(P5PrototypeAction.clearProject)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _runsWorkspace(BuildContext context) {
    final state = controller.state;
    final selectedSavedRun = P5PrototypeFixtures.runs
        .where((run) => run.id == state.selectedRunId)
        .firstOrNull;
    final isCurrentSimulatedRun =
        state.selectedRunId == 'run.p5-simulated-current';
    return _scrollWorkspace(
      context,
      children: <Widget>[
        const _WorkspaceHeader(
          title: 'Runs / Activity',
          subtitle:
              'Open a saved run, inspect related views, and return without losing context.',
          icon: Icons.timeline_outlined,
        ),
        Card(
          child: Column(
            children: <Widget>[
              for (final run in P5PrototypeFixtures.runs)
                Semantics(
                  selected: run.id == state.selectedRunId,
                  label:
                      '${run.title}, ${run.state.label}${run.id == state.selectedRunId ? ', selected' : ''}',
                  child: ListTile(
                    key: Key('run-${run.id}'),
                    selected: run.id == state.selectedRunId,
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text(run.title),
                    subtitle: Text(
                      '${run.updatedAtLabel} • ${run.state.label}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: controller.canSelectSavedRun
                        ? () => controller.selectRun(run.id)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        if (selectedSavedRun != null)
          Card(
            key: const Key('selected-run-detail'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    selectedSavedRun.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${selectedSavedRun.updatedAtLabel} • Current presentation: ${state.runState.label}',
                  ),
                  const SizedBox(height: 8),
                  const _BoundaryNotice(
                    message:
                        'Saved-run detail is rendered from deterministic fixture fields. No synthetic event timeline is invented.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      if (state.runState == P5RunPresentationState.interrupted)
                        OutlinedButton.icon(
                          key: const Key('resume-existing-run-button'),
                          onPressed: () => controller.apply(
                            P5PrototypeAction.retryInterruptedRun,
                          ),
                          icon: const Icon(Icons.replay),
                          label: const Text('Resume fixture'),
                        ),
                      OutlinedButton.icon(
                        key: const Key('existing-run-evidence-button'),
                        onPressed: () =>
                            controller.selectWorkspace(P5WorkspaceId.evidence),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Evidence (Advanced)'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('existing-run-verification-button'),
                        onPressed: () => controller.selectWorkspace(
                          P5WorkspaceId.verificationCenter,
                        ),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Verification'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (isCurrentSimulatedRun)
          Card(
            key: const Key('current-run-detail'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Current simulated run',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Status: ${state.runState.label}'),
                  const SizedBox(height: 8),
                  const _BoundaryNotice(
                    message:
                        'This is the in-memory current run, not a saved-run fixture. No saved timeline is fabricated for it.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      OutlinedButton.icon(
                        key: const Key('current-run-home-button'),
                        onPressed: () =>
                            controller.selectWorkspace(P5WorkspaceId.homeChat),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Back to task'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('current-run-verification-button'),
                        onPressed: () => controller.selectWorkspace(
                          P5WorkspaceId.verificationCenter,
                        ),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Verification'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else if (state.selectedRunId != null)
          _RecoveryCard(
            key: const Key('invalid-run-state'),
            state: 'BLOCKED',
            title: 'Run unavailable',
            message:
                'The selected run does not match a saved or current fixture.',
            actionLabel: 'Clear invalid run',
            onAction: () => controller.selectRun(null),
          ),
      ],
    );
  }
}
