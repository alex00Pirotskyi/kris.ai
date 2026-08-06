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
            onAction: () =>
                controller.apply(P5PrototypeAction.createSampleProject),
          )
        else ...<Widget>[
          Card(
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    toggled: state.planOnly,
                    label:
                        'Plan-only mode. Presentation fixture; authority is unchanged.',
                    child: CheckboxListTile(
                      key: const Key('plan-only-toggle'),
                      contentPadding: EdgeInsets.zero,
                      value: state.planOnly,
                      title: const Text('Plan only'),
                      subtitle: const Text(
                        'Review the plan without presenting an execution state.',
                      ),
                      onChanged: controller.canChangePlanOnly
                          ? (_) => controller
                              .apply(P5PrototypeAction.choosePlanOnly)
                          : null,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        onPressed: controller.canReviewPlan
                            ? () => controller.apply(P5PrototypeAction.reviewPlan)
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review concise plan'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('start-run-button'),
                        onPressed: controller.canStartRun
                            ? () => controller.apply(P5PrototypeAction.startRun)
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start simulated run'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (state.planReviewed) _planCard(context),
          _runControlCard(context),
        ],
      ],
    );
  }

  Widget _planCard(BuildContext context) {
    return Card(
      key: const Key('concise-plan-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Concise plan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('1. Inspect the selected project context.'),
            const Text('2. Propose bounded changes and expected evidence.'),
            const Text('3. Verify selected checks and preserve receipts.'),
            const SizedBox(height: 10),
            const _BoundaryNotice(
              message:
                  'This is deterministic fixture data. No files, commands, credentials, or network services are accessed.',
            ),
          ],
        ),
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
                    FilledButton.tonalIcon(
                      key: const Key('open-evidence-button'),
                      onPressed: () =>
                          controller.apply(P5PrototypeAction.openEvidence),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Open evidence'),
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
                    subtitle:
                        Text('${run.updatedAtLabel} • ${run.state.label}'),
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
                          onPressed: () => controller
                              .apply(P5PrototypeAction.retryInterruptedRun),
                          icon: const Icon(Icons.replay),
                          label: const Text('Resume fixture'),
                        ),
                      OutlinedButton.icon(
                        key: const Key('existing-run-evidence-button'),
                        onPressed: () =>
                            controller.selectWorkspace(P5WorkspaceId.evidence),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Evidence'),
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
