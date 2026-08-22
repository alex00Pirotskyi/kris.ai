from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'expected one P5-006 compatibility anchor in {path}, found {count}: {old!r}'
        )
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


def replace_span(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{path}: P5-006 compatibility start marker missing')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{path}: P5-006 compatibility end marker missing')
    if text.find(start_marker, start + 1) >= 0:
        raise SystemExit(f'{path}: P5-006 compatibility start marker is ambiguous')
    target.write_text(text[:start] + replacement + text[end:], encoding='utf-8', newline='\n')


task_path = 'lib/product/p5_information_architecture/p5_task_workspaces.dart'
compact_home = """        else ...<Widget>[
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
                      helperText: 'Ctrl+Enter or Cmd+Enter launches this composer.',
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
                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        onPressed: controller.canReviewPlan
                            ? () =>
                                controller.apply(P5PrototypeAction.reviewPlan)
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
                              ? (state.planOnly ? 'Review plan only' : 'Run now')
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

"""
replace_span(
    task_path,
    "        else ...<Widget>[\n          Card(\n            key: const Key('p5-task-composer'),\n",
    "  Widget _composerSelect<T>({\n",
    compact_home,
)

replace_once(
    'lib/product/p5_information_architecture/p5_controller.dart',
    "  bool get canLaunchComposer => !_runLifecycleLocked;\n",
    """  bool get canLaunchComposer =>
      !_runLifecycleLocked && _state.selectedRunId == null;
""",
)

print('P5_006_COMPAT_FIX_APPLIED')
