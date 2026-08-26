part of 'chat_control_plane_studio.dart';

extension _ChatControlPlaneView on _ChatControlPlaneStudioState {
  Widget _buildStudio() {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome),
            SizedBox(width: 9),
            Text('Kristin'),
          ],
        ),
        actions: <Widget>[
          if (selectedProject != null)
            _headerChip(Icons.folder_outlined, selectedProject!.name),
          if (selectedModel != null)
            _headerChip(Icons.memory_outlined, selectedModel!.name),
          IconButton(
            tooltip: 'Advanced workspaces',
            onPressed: busy ? null : _openAdvanced,
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: busy ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _statusStrip(),
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                      children: <Widget>[
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: _conversation(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _composer(),
              ],
            ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _statusStrip() {
    final startup = widget.startupError;
    if (startup == null && error == null && !busy && !runActive) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final failing = startup != null || error != null;
    return Material(
      color: failing ? colors.errorContainer : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: <Widget>[
            if (busy || runActive)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(failing ? Icons.error_outline : Icons.info_outline, size: 18),
            const SizedBox(width: 9),
            Expanded(child: Text(startup ?? error ?? status)),
            if (error != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => _mutate(() => error = null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conversation() {
    final children = <Widget>[];
    if (transcript.isEmpty &&
        pendingDecision == null &&
        currentRun == null &&
        prepared == null) {
      children.add(_welcome());
    }
    for (final line in transcript) {
      children.add(_messageBubble(line));
      children.add(const SizedBox(height: 14));
    }
    if (understandingHistory != null &&
        prepared == null &&
        currentRun == null) {
      children.add(_understandingCard());
      children.add(const SizedBox(height: 14));
    }
    if (prepared != null && (currentRun == null || runAwaitingApproval)) {
      children.add(awaitingPermission || runAwaitingApproval
          ? _permissionCard()
          : _planCard());
      children.add(const SizedBox(height: 14));
    }
    if (currentRun != null && !runAwaitingApproval) {
      children.add(_runCard(currentRun!));
      if (runTerminal) {
        children.add(const SizedBox(height: 14));
        children.add(_resultCard(currentRun!));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _welcome() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 30,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'What can I help you with?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 9),
          Text(
            'Ask normally, type / for actions, or use @ to reference a project, model, provider, or workspace.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            alignment: WrapAlignment.center,
            children: <Widget>[
              ActionChip(
                avatar: const Icon(Icons.build_outlined, size: 18),
                label: const Text('/build'),
                onPressed: () => _seedComposer('/build '),
              ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 18),
                label: const Text('/search'),
                onPressed: () => _seedComposer('/search '),
              ),
              ActionChip(
                avatar: const Icon(Icons.play_arrow, size: 18),
                label: const Text('/run @'),
                onPressed: () => _seedComposer('/run @'),
              ),
              ActionChip(
                avatar: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('/verify @'),
                onPressed: () => _seedComposer('/verify @'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _seedComposer(String value) {
    composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updateSuggestions();
    composerFocus.requestFocus();
  }

  Widget _messageBubble(_ChatLine line) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment:
          line.assistant ? MainAxisAlignment.start : MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (line.assistant) ...<Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: line.assistant
                  ? colors.surfaceContainerLow
                  : colors.primaryContainer,
              borderRadius: BorderRadius.circular(17),
              border: line.assistant
                  ? Border.all(color: colors.outlineVariant)
                  : null,
            ),
            child: SelectableText(line.text),
          ),
        ),
      ],
    );
  }

  Widget _understandingCard() {
    final history = understandingHistory!;
    final decision = pendingDecision!;
    final draft = history.current;
    return _assistantCard(
      icon: Icons.psychology_alt_outlined,
      title: 'I understood:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(draft.summary),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              Chip(
                avatar: const Icon(Icons.bolt_outlined, size: 16),
                label: Text(decision.capability?.displayName ?? 'Action'),
              ),
              Chip(
                avatar: const Icon(Icons.account_tree_outlined, size: 16),
                label: Text(decision.needsPlan ? 'Plan follows' : 'Direct action'),
              ),
              if (decision.riskClass != ChatRiskClass.none)
                Chip(
                  avatar: const Icon(Icons.shield_outlined, size: 16),
                  label: Text('${decision.riskClass.name} risk'),
                ),
              if (history.revisions.length > 1)
                Chip(label: Text('Understanding v${draft.revision}')),
            ],
          ),
          if (decision.ambiguous) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              decision.unresolvedMentions.isEmpty
                  ? 'I can use the currently selected context, or you can adjust this interpretation.'
                  : 'I still need a valid target for ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (understandingAdjusting) ...<Widget>[
            const SizedBox(height: 14),
            TextField(
              controller: understandingAdjustmentController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What should I change?',
              ),
              onSubmitted: (_) => _adjustUnderstanding(),
            ),
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: busy ? null : _adjustUnderstanding,
                child: const Text('Update understanding'),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const Key('chat-understanding-continue'),
                  onPressed: busy ? null : _continueUnderstanding,
                  child: const Text('Continue'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _mutate(() => understandingAdjusting = true),
                  child: const Text('Adjust'),
                ),
                TextButton(
                  onPressed: busy ? null : _tryAnotherInterpretation,
                  child: const Text('Try another interpretation'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard() {
    final command = prepared!;
    return _assistantCard(
      icon: Icons.account_tree_outlined,
      title: 'Here’s my development plan:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (command.plan.rationale.trim().isNotEmpty) ...<Widget>[
            Text(command.plan.rationale),
            const SizedBox(height: 12),
          ],
          ...command.plan.items.indexed.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 12,
                    child: Text(
                      '${entry.$1 + 1}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.$2.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (entry.$2.description.trim().isNotEmpty)
                          Text(
                            entry.$2.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (planAdjusting) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              controller: planAdjustmentController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'How should the plan change?',
              ),
              onSubmitted: (_) => _adjustPlan(),
            ),
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: busy ? null : _adjustPlan,
                child: const Text('Update plan'),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('chat-plan-start'),
                  onPressed: busy ? null : _startPlan,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _mutate(() => planAdjusting = true),
                  child: const Text('Adjust plan'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionCard() {
    final command = prepared!;
    final groups = groupPermissions(command.contract.requiredPermissions);
    return _assistantCard(
      icon: Icons.shield_outlined,
      title: 'Permission needed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Understanding and plan approval do not grant authority. This run needs the following governed access:',
          ),
          const SizedBox(height: 10),
          if (groups.isEmpty)
            const Text('The pending run is waiting for governed approval.')
          else
            ...groups.map(
              (group) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(group.icon),
                title: Text(group.title),
                subtitle: Text(group.description),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('chat-permission-allow'),
                onPressed: busy ? null : _approvePermissions,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Allow for this run'),
              ),
              TextButton(
                onPressed: busy ? null : _declinePermissions,
                child: const Text('Go back'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runCard(RunRecord run) {
    final done =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    final showModelAnswer = run.command.contract.mode == CommandMode.ask &&
        liveAssistantText.trim().isNotEmpty;
    return _assistantCard(
      icon: run.state == RunState.succeeded
          ? Icons.check_circle_outline
          : Icons.auto_awesome,
      title: friendlyRunState(run.state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LinearProgressIndicator(
            value: run.state == RunState.running && done == 0
                ? null
                : (done / total).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: 12),
          if (showModelAnswer)
            SelectableText(liveAssistantText)
          else ...<Widget>[
            if (liveProgressText.trim().isNotEmpty) ...<Widget>[
              Text(liveProgressText),
              const SizedBox(height: 9),
            ],
            ...run.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    _workStateIcon(item.state),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.item.title)),
                    Text(
                      friendlyWorkState(item.state),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            initiallyExpanded: detailsExpanded,
            onExpansionChanged: (value) => detailsExpanded = value,
            tilePadding: EdgeInsets.zero,
            title: const Text('Details'),
            subtitle: const Text('Model, tools, evidence, and technical output'),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    Chip(label: Text(run.command.model.name)),
                    Chip(label: Text('${run.toolCalls} tool calls')),
                    Chip(label: Text('${run.mutations} mutations')),
                    Chip(label: Text('${run.repairs} repairs')),
                    if (liveToolName.isNotEmpty) Chip(label: Text(liveToolName)),
                  ],
                ),
              ),
              if (liveToolOutput.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _technicalBox(liveToolOutput),
              ],
              if (evidence.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                ...evidence.take(10).map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_outlined, size: 18),
                    title: Text(item.summary),
                    subtitle: Text(item.kind.name),
                  ),
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (run.state == RunState.running)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _controlRun('pause'),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              if (run.state == RunState.paused ||
                  run.state == RunState.interrupted)
                FilledButton.icon(
                  onPressed: busy ? null : () => _controlRun('resume'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              if (runActive)
                TextButton.icon(
                  onPressed: busy ? null : () => _controlRun('cancel'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard(RunRecord run) {
    final successful = run.state == RunState.succeeded;
    final summary = _resultText(run);
    final artifacts = evidence.where((item) {
      return const <EvidenceKind>{
        EvidenceKind.mutation,
        EvidenceKind.test,
        EvidenceKind.verification,
        EvidenceKind.deployment,
      }.contains(item.kind);
    }).take(8).toList(growable: false);
    return _assistantCard(
      icon: successful ? Icons.task_alt : Icons.error_outline,
      title: successful ? 'Ready' : 'Needs attention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(summary),
          if (artifacts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'Verified results',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ...artifacts.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text(item.summary),
                subtitle: Text(item.kind.name),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (projectProcessStatus?.running == true)
                OutlinedButton.icon(
                  onPressed: busy ? null : _stopManagedProject,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop project'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : _openAdvanced,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Project'),
              ),
              FilledButton.tonalIcon(
                onPressed: _newChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New chat'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _assistantCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          backgroundColor: colors.primaryContainer,
          child: Icon(icon, size: 16, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _workStateIcon(WorkItemState state) {
    if (state == WorkItemState.running) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      switch (state) {
        WorkItemState.succeeded => Icons.check_circle_outline,
        WorkItemState.failed => Icons.error_outline,
        WorkItemState.blocked => Icons.block_outlined,
        WorkItemState.awaitingApproval => Icons.lock_clock_outlined,
        WorkItemState.cancelled => Icons.cancel_outlined,
        WorkItemState.queued => Icons.radio_button_unchecked,
        WorkItemState.running => Icons.autorenew,
      },
      size: 18,
    );
  }

  Widget _technicalBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        value,
        maxLines: 12,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _composer() {
    final colors = Theme.of(context).colorScheme;
    final hasSuggestions = suggestions.isNotEmpty;
    return Material(
      elevation: 3,
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (hasSuggestions) _autocomplete(),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Shortcuts(
                          shortcuts: <ShortcutActivator, Intent>{
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              control: true,
                            ): const _SubmitIntent(),
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              meta: true,
                            ): const _SubmitIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.arrowDown):
                                  const _NextSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.arrowUp):
                                  const _PreviousSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.enter):
                                  const _AcceptSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  const _DismissSuggestionsIntent(),
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              _SubmitIntent: CallbackAction<_SubmitIntent>(
                                onInvoke: (_) {
                                  unawaited(_submit());
                                  return null;
                                },
                              ),
                              _NextSuggestionIntent:
                                  CallbackAction<_NextSuggestionIntent>(
                                onInvoke: (_) {
                                  _mutate(() {
                                    suggestionIndex =
                                        (suggestionIndex + 1) % suggestions.length;
                                  });
                                  return null;
                                },
                              ),
                              _PreviousSuggestionIntent:
                                  CallbackAction<_PreviousSuggestionIntent>(
                                onInvoke: (_) {
                                  _mutate(() {
                                    suggestionIndex =
                                        (suggestionIndex - 1 + suggestions.length) %
                                            suggestions.length;
                                  });
                                  return null;
                                },
                              ),
                              _AcceptSuggestionIntent:
                                  CallbackAction<_AcceptSuggestionIntent>(
                                onInvoke: (_) {
                                  _selectSuggestion(suggestions[suggestionIndex]);
                                  return null;
                                },
                              ),
                              _DismissSuggestionsIntent:
                                  CallbackAction<_DismissSuggestionsIntent>(
                                onInvoke: (_) {
                                  _mutate(() {
                                    suggestions =
                                        const <ChatAutocompleteSuggestion>[];
                                  });
                                  return null;
                                },
                              ),
                            },
                            child: TextField(
                              controller: composerController,
                              focusNode: composerFocus,
                              minLines: 1,
                              maxLines: 8,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: runActive
                                    ? 'Steer the active work…'
                                    : 'Message Kristin…',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(17, 15, 17, 8),
                              ),
                              onChanged: (_) => _updateSuggestions(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
                          child: Row(
                            children: <Widget>[
                              Tooltip(
                                message: '/ chooses an action',
                                child: Text(
                                  '/ action',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Tooltip(
                                message:
                                    '@ chooses a project, model, provider, or workspace',
                                child: Text(
                                  '@ target',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              const Spacer(),
                              IconButton.filled(
                                tooltip: 'Send',
                                onPressed:
                                    busy || composerController.text.trim().isEmpty
                                        ? null
                                        : _submit,
                                icon: busy
                                    ? const SizedBox.square(
                                        dimension: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_upward),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _autocomplete() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 12,
            spreadRadius: 1,
            color: Color(0x18000000),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final selected = index == suggestionIndex;
          return Semantics(
            button: true,
            selected: selected,
            label: '${suggestion.label}. ${suggestion.description}',
            child: ListTile(
              selected: selected,
              selectedTileColor: colors.secondaryContainer,
              leading: Icon(
                suggestion.kind == ChatAutocompleteKind.command
                    ? Icons.bolt_outlined
                    : Icons.alternate_email,
              ),
              title: Text(
                suggestion.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                suggestion.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectSuggestion(suggestion),
            ),
          );
        },
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _NextSuggestionIntent extends Intent {
  const _NextSuggestionIntent();
}

class _PreviousSuggestionIntent extends Intent {
  const _PreviousSuggestionIntent();
}

class _AcceptSuggestionIntent extends Intent {
  const _AcceptSuggestionIntent();
}

class _DismissSuggestionsIntent extends Intent {
  const _DismissSuggestionsIntent();
}
