import 'dart:math';

import 'package:flutter/material.dart';

import 'adaptive_mission_planning.dart';
import 'domain.dart';

enum _AdaptiveInspectorView { overview, missions, economics, tests }

class AdaptivePlanningPreview extends StatelessWidget {
  const AdaptivePlanningPreview({
    super.key,
    required this.prompt,
    required this.model,
    required this.depth,
    required this.maxTasks,
  });

  final PromptStudioDraft prompt;
  final ModelIdentity model;
  final PlanningDepth depth;
  final int maxTasks;

  @override
  Widget build(BuildContext context) {
    final estimate = AdaptiveMissionPlanner.preview(
      prompt: prompt,
      model: model,
      depth: depth,
      maxTasks: maxTasks,
    );
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.calculate_outlined, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan forecast',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Text('${(estimate.confidence * 100).round()}% confidence'),
            ],
          ),
          const SizedBox(height: 10),
          _PreviewMetric(
            label: 'Likely plan size',
            value:
                '${estimate.expectedMissionCount} missions · ${estimate.expectedTaskCount} tasks',
          ),
          _PreviewMetric(
            label: 'Planning tokens',
            value: _tokenRangeLabel(estimate.planGeneration),
          ),
          _PreviewMetric(
            label: 'Output budget',
            value: _tokenRangeLabel(estimate.outputTokens),
          ),
          _PreviewMetric(
            label: 'Shared context capsule',
            value: '~${_compactNumber(estimate.sharedContextTokens)} tokens',
          ),
          const SizedBox(height: 7),
          Text(
            'Ranges are deterministic estimates from prompt size, task ceiling, planning depth, and model class—not a usage guarantee.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class AdaptiveMissionInspector extends StatefulWidget {
  const AdaptiveMissionInspector({
    super.key,
    required this.plan,
    required this.prompt,
    required this.model,
    required this.busy,
    this.onEditTask,
    this.onRunTasks,
  });

  final TaskPlanRecord plan;
  final PromptStudioDraft prompt;
  final ModelIdentity model;
  final bool busy;
  final ValueChanged<String>? onEditTask;
  final ValueChanged<Set<String>>? onRunTasks;

  @override
  State<AdaptiveMissionInspector> createState() =>
      _AdaptiveMissionInspectorState();
}

class _AdaptiveMissionInspectorState extends State<AdaptiveMissionInspector> {
  _AdaptiveInspectorView view = _AdaptiveInspectorView.overview;

  AdaptiveMissionPlan get analysis => AdaptiveMissionPlanner.analyzePlan(
        plan: widget.plan,
        prompt: widget.prompt,
      );

  @override
  Widget build(BuildContext context) {
    final data = analysis;
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.route_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Adaptive mission plan',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'A compact skeleton, ready-frontier packets, risk-based tests, and token ranges calculated before execution.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _MiniBadge(
                  icon: Icons.memory_outlined,
                  label: widget.model.name,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _AdaptiveInspectorView.values
                  .map(
                    (candidate) => ChoiceChip(
                      selected: view == candidate,
                      avatar: Icon(_viewIcon(candidate), size: 17),
                      label: Text(_viewLabel(candidate)),
                      onSelected: (_) => setState(() => view = candidate),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: switch (view) {
              _AdaptiveInspectorView.overview => _overview(data),
              _AdaptiveInspectorView.missions => _missions(data),
              _AdaptiveInspectorView.economics => _economics(data),
              _AdaptiveInspectorView.tests => _tests(data),
            },
          ),
        ],
      ),
    );
  }

  Widget _overview(AdaptiveMissionPlan data) {
    final criticalTokens = data.criticalPath.fold<int>(
      0,
      (total, id) =>
          total + (data.taskEconomics[id]?.totalTokens.likely ?? 0),
    );
    final concentration = data.economics.likely == 0
        ? 0.0
        : criticalTokens / data.economics.likely;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 880
                ? 4
                : constraints.maxWidth >= 520
                    ? 2
                    : 1;
            final width =
                (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MissionMetric(
                  width: width,
                  icon: Icons.flag_outlined,
                  value: '${data.missions.length}',
                  label: 'missions',
                  detail: '${data.readyFrontier.length} tasks ready now',
                ),
                _MissionMetric(
                  width: width,
                  icon: Icons.data_usage_outlined,
                  value: _compactNumber(data.economics.likely),
                  label: 'likely tokens',
                  detail: _tokenRangeLabel(data.economics),
                ),
                _MissionMetric(
                  width: width,
                  icon: Icons.fact_check_outlined,
                  value: '${(data.verificationCoverage * 100).round()}%',
                  label: 'verification coverage',
                  detail: '${data.tests.length} test recommendations',
                ),
                _MissionMetric(
                  width: width,
                  icon: Icons.compress_outlined,
                  value: _compactNumber(data.contextTokensSaved),
                  label: 'context tokens avoided',
                  detail: '${data.lazyPacketCount} packets materialize later',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Execution economics',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        _BudgetBand(
          range: data.economics,
          criticalFraction: concentration.clamp(0.0, 1.0).toDouble(),
        ),
        const SizedBox(height: 14),
        Text(
          'Critical path',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        if (data.criticalPath.isEmpty)
          const Text('No enabled path is available.')
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: data.criticalPath.map((id) {
              final task = widget.plan.tasks
                  .where((item) => item.id == id)
                  .firstOrNull;
              return Chip(
                avatar: const Icon(Icons.bolt, size: 17),
                label: Text(task?.title ?? id),
              );
            }).toList(growable: false),
          ),
        const SizedBox(height: 16),
        Text(
          'Planner findings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        ...data.findings.map(_findingCard),
      ],
    );
  }

  Widget _missions(AdaptiveMissionPlan data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Mission graph',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            _MiniBadge(
              icon: Icons.playlist_play,
              label: '${data.readyFrontier.length} ready',
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...data.missions.map((mission) => _missionCard(data, mission)),
      ],
    );
  }

  Widget _missionCard(AdaptiveMissionPlan data, AdaptiveMission mission) {
    final colors = Theme.of(context).colorScheme;
    final tasks = mission.taskIds
        .map(
          (id) => widget.plan.tasks.where((item) => item.id == id).firstOrNull,
        )
        .whereType<PlanTaskRecord>()
        .toList(growable: false);
    final runnableIds = mission.taskIds
        .where(data.readyFrontier.contains)
        .toSet();
    final blocked = mission.dependencies.isNotEmpty && runnableIds.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: mission.ready
          ? colors.primaryContainer.withValues(alpha: 0.30)
          : colors.surfaceContainerLow,
      child: ExpansionTile(
        initiallyExpanded: mission.ready || mission.criticalTaskIds.isNotEmpty,
        leading: CircleAvatar(
          child: Text('${data.missions.indexOf(mission) + 1}'),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                mission.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (mission.criticalTaskIds.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Mission intersects the critical path',
                  child: Icon(Icons.bolt, size: 19),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${mission.taskIds.length} packets · ${_tokenRangeLabel(mission.economics)} · ${blocked ? 'blocked' : mission.ready ? 'ready' : 'staged'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: <Widget>[
          Align(alignment: Alignment.centerLeft, child: Text(mission.objective)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              mission.contextCapsule,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (mission.dependencies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Depends on ${mission.dependencies.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...tasks.map((task) => _missionTaskRow(data, task)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${mission.tests.length} risk-based test recommendations',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.onRunTasks != null && runnableIds.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: widget.busy
                      ? null
                      : () => widget.onRunTasks!(runnableIds),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    runnableIds.length == 1
                        ? 'Run ready packet'
                        : 'Run ${runnableIds.length} ready packets',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _missionTaskRow(AdaptiveMissionPlan data, PlanTaskRecord task) {
    final estimate = data.taskEconomics[task.id];
    final ready = data.readyFrontier.contains(task.id);
    final critical = data.criticalPath.contains(task.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              ready
                  ? Icons.play_circle_outline
                  : task.manual
                      ? Icons.person_outline
                      : Icons.schedule_outlined,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (critical) const Icon(Icons.bolt, size: 17),
                    ],
                  ),
                  Text(
                    '${task.risk.name} risk · ${estimate == null ? 'unestimated' : '${_compactNumber(estimate.totalTokens.likely)} likely tokens'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (widget.onEditTask != null)
              IconButton(
                tooltip: 'Edit runner packet',
                onPressed:
                    widget.busy ? null : () => widget.onEditTask!(task.id),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (widget.onRunTasks != null && ready && !task.manual)
              IconButton(
                tooltip: 'Run this ready packet',
                onPressed: widget.busy
                    ? null
                    : () => widget.onRunTasks!(<String>{task.id}),
                icon: const Icon(Icons.play_arrow),
              ),
          ],
        ),
      ),
    );
  }

  Widget _economics(AdaptiveMissionPlan data) {
    final estimates = data.taskEconomics.values.toList()
      ..sort((a, b) => b.totalTokens.likely.compareTo(a.totalTokens.likely));
    final maxLikely = estimates.isEmpty
        ? 1
        : estimates.map((item) => item.totalTokens.likely).reduce(max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Token economics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            _MiniBadge(
              icon: Icons.compress_outlined,
              label: '${_compactNumber(data.contextTokensSaved)} saved',
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'The estimator models prompt/context input, generated output, tool-result volume, uncertainty, retry reserve, and model size. It reports ranges instead of false precision.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        ...estimates.map((estimate) {
          final task = widget.plan.tasks
              .where((item) => item.id == estimate.taskId)
              .firstOrNull;
          final fraction = estimate.totalTokens.likely / maxLikely;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        task?.title ?? estimate.taskId,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(_tokenRangeLabel(estimate.totalTokens)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: <Widget>[
                    Text(
                      'input ${_compactNumber(estimate.inputTokens.likely)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'output ${_compactNumber(estimate.outputTokens.likely)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'tools ${_compactNumber(estimate.toolResultTokens.likely)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'retry ${(estimate.retryProbability * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${(estimate.confidence * 100).round()}% confidence',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _tests(AdaptiveMissionPlan data) {
    final byKind = <AdaptiveTestKind, List<MissionTestRecommendation>>{};
    for (final test in data.tests) {
      byKind.putIfAbsent(test.kind, () => <MissionTestRecommendation>[]).add(test);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Risk-based test matrix',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            _MiniBadge(
              icon: Icons.verified_outlined,
              label: '${(data.verificationCoverage * 100).round()}% covered',
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Tests are selected from the task’s change surface and risk rather than generated as one generic final checklist.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ...byKind.entries.map((entry) {
          return Card(
            margin: const EdgeInsets.only(bottom: 9),
            child: ExpansionTile(
              initiallyExpanded: entry.key.index <= AdaptiveTestKind.integration.index,
              leading: Icon(_testIcon(entry.key)),
              title: Text(
                _testKindLabel(entry.key),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${entry.value.length} recommendation${entry.value.length == 1 ? '' : 's'}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              children: entry.value.map((test) {
                final taskTitles = test.taskIds
                    .map(
                      (id) => widget.plan.tasks
                          .where((item) => item.id == id)
                          .firstOrNull
                          ?.title,
                    )
                    .whereType<String>()
                    .take(4)
                    .join(' · ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    test.automated
                        ? Icons.smart_toy_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(test.title),
                  subtitle: Text(
                    '${test.reason}${taskTitles.isEmpty ? '' : '\n$taskTitles'}',
                  ),
                  isThreeLine: taskTitles.isNotEmpty,
                );
              }).toList(growable: false),
            ),
          );
        }),
      ],
    );
  }

  Widget _findingCard(AdaptivePlanningFinding finding) {
    final colors = Theme.of(context).colorScheme;
    final (icon, background) = switch (finding.severity) {
      AdaptiveFindingSeverity.info =>
        (Icons.info_outline, colors.surfaceContainerLow),
      AdaptiveFindingSeverity.recommendation =>
        (Icons.lightbulb_outline, colors.secondaryContainer),
      AdaptiveFindingSeverity.warning =>
        (Icons.warning_amber_outlined, colors.tertiaryContainer),
      AdaptiveFindingSeverity.critical =>
        (Icons.error_outline, colors.errorContainer),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  finding.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(finding.detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionMetric extends StatelessWidget {
  const _MissionMetric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BudgetBand extends StatelessWidget {
  const _BudgetBand({
    required this.range,
    required this.criticalFraction,
  });

  final TokenRange range;
  final double criticalFraction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Low ${_compactNumber(range.low)}')),
              Text(
                'Likely ${_compactNumber(range.likely)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Expanded(
                child: Text(
                  'High ${_compactNumber(range.high)}',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: criticalFraction,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${(criticalFraction * 100).round()}% of likely tokens sit on the serial critical path.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _viewIcon(_AdaptiveInspectorView view) => switch (view) {
      _AdaptiveInspectorView.overview => Icons.dashboard_outlined,
      _AdaptiveInspectorView.missions => Icons.flag_outlined,
      _AdaptiveInspectorView.economics => Icons.data_usage_outlined,
      _AdaptiveInspectorView.tests => Icons.fact_check_outlined,
    };

String _viewLabel(_AdaptiveInspectorView view) => switch (view) {
      _AdaptiveInspectorView.overview => 'Overview',
      _AdaptiveInspectorView.missions => 'Missions',
      _AdaptiveInspectorView.economics => 'Economics',
      _AdaptiveInspectorView.tests => 'Tests',
    };

IconData _testIcon(AdaptiveTestKind kind) => switch (kind) {
      AdaptiveTestKind.staticAnalysis => Icons.rule_outlined,
      AdaptiveTestKind.unit => Icons.science_outlined,
      AdaptiveTestKind.component => Icons.widgets_outlined,
      AdaptiveTestKind.integration => Icons.hub_outlined,
      AdaptiveTestKind.regression => Icons.history_outlined,
      AdaptiveTestKind.acceptance => Icons.verified_outlined,
      AdaptiveTestKind.manual => Icons.person_search_outlined,
    };

String _testKindLabel(AdaptiveTestKind kind) => switch (kind) {
      AdaptiveTestKind.staticAnalysis => 'Static and source contracts',
      AdaptiveTestKind.unit => 'Unit and failure-path tests',
      AdaptiveTestKind.component => 'Component and interaction tests',
      AdaptiveTestKind.integration => 'Integration and boundary tests',
      AdaptiveTestKind.regression => 'Regression protection',
      AdaptiveTestKind.acceptance => 'Acceptance and artifact evidence',
      AdaptiveTestKind.manual => 'Focused manual review',
    };

String _tokenRangeLabel(TokenRange range) =>
    '${_compactNumber(range.low)}–${_compactNumber(range.high)} tokens';

String _compactNumber(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
  }
  return '$value';
}
