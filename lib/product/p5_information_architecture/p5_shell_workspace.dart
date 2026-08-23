part of 'p5_prototype.dart';

extension _P5ShellWorkspace on _P5InformationArchitecturePrototypeState {
  Future<void> _initializeP5ShellLayout() async {
    final store = widget.layoutPersistence;
    if (store == null) {
      return;
    }
    _shellLayoutStore = store;
    try {
      final restored = await store.load();
      if (!mounted || restored == null) {
        return;
      }
      controller.updateShellLayout(restored);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      controller.showRecoveryMessage(
        'Saved workspace layout could not be restored: $error',
      );
    }
  }

  void _scheduleP5ShellLayoutSave() {
    final store = _shellLayoutStore;
    if (store == null) {
      return;
    }
    _shellLayoutSaveDebounce?.cancel();
    _shellLayoutSaveDebounce = Timer(const Duration(milliseconds: 140), () {
      unawaited(
        store.save(controller.shellLayout).catchError((Object error) {
          if (mounted) {
            controller.showRecoveryMessage(
              'Workspace layout could not be saved: $error',
            );
          }
        }),
      );
    });
  }

  void _updateP5ShellLayout(P5ShellLayoutState next) {
    controller.updateShellLayout(next);
    _scheduleP5ShellLayoutSave();
  }

  Widget _buildP5ThreePaneBody(
    BuildContext context, {
    required bool compact,
    required P5PresentationState state,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = controller.shellLayout.normalized();
        final center = Column(
          key: const Key('p5-center-workspace'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _contextBar(context),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'workspace-content-${state.workspace.name}',
                ),
                child: _workspace(context, state.workspace),
              ),
            ),
          ],
        );
        final centerAndInspector = compact
            ? center
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    key: const Key('p5-left-rail'),
                    width: layout.leftRailWidth,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: SafeArea(top: false, child: _navigation(context)),
                    ),
                  ),
                  _P5ResizeHandle.vertical(
                    key: const Key('p5-left-resize-handle'),
                    semanticsLabel: 'Resize navigation rail',
                    onDrag: (delta) => _updateP5ShellLayout(
                      layout.copyWith(
                        leftRailWidth: layout.leftRailWidth + delta,
                      ),
                    ),
                  ),
                  Expanded(child: center),
                  if (layout.inspectorOpen) ...<Widget>[
                    _P5ResizeHandle.vertical(
                      key: const Key('p5-inspector-resize-handle'),
                      semanticsLabel: 'Resize inspector',
                      onDrag: (delta) => _updateP5ShellLayout(
                        layout.copyWith(
                          inspectorWidth: layout.inspectorWidth - delta,
                        ),
                      ),
                    ),
                    SizedBox(
                      key: const Key('p5-right-inspector'),
                      width: layout.inspectorWidth,
                      child: _buildP5Inspector(context, state),
                    ),
                  ],
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: centerAndInspector),
            if (layout.activityDrawerOpen) ...<Widget>[
              _P5ResizeHandle.horizontal(
                key: const Key('p5-activity-resize-handle'),
                semanticsLabel: 'Resize activity drawer',
                onDrag: (delta) {
                  final maximum = (constraints.maxHeight * 0.55)
                      .clamp(
                        P5ShellLayoutState.minimumActivityHeight,
                        P5ShellLayoutState.maximumActivityHeight,
                      )
                      .toDouble();
                  _updateP5ShellLayout(
                    layout.copyWith(
                      activityDrawerHeight:
                          (layout.activityDrawerHeight - delta)
                              .clamp(
                                P5ShellLayoutState.minimumActivityHeight,
                                maximum,
                              )
                              .toDouble(),
                    ),
                  );
                },
              ),
              SizedBox(
                key: const Key('p5-activity-drawer'),
                height: layout.activityDrawerHeight
                    .clamp(
                      P5ShellLayoutState.minimumActivityHeight,
                      (constraints.maxHeight * 0.55)
                          .clamp(
                            P5ShellLayoutState.minimumActivityHeight,
                            P5ShellLayoutState.maximumActivityHeight,
                          )
                          .toDouble(),
                    )
                    .toDouble(),
                child: _buildP5ActivityDrawer(context, state),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildP5Inspector(BuildContext context, P5PresentationState state) {
    final project = P5PrototypeFixtures.projects
        .where((item) => item.id == state.selectedProjectId)
        .firstOrNull;
    final run = P5PrototypeFixtures.runs
        .where((item) => item.id == state.selectedRunId)
        .firstOrNull;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: ListView(
          key: const Key('p5-inspector-scroll'),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.tune_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inspector',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DomainCard(
              title: 'Workspace',
              value: state.workspace.label,
              detail: state.workspaceStates[state.workspace]?.label ?? 'READY',
              icon: _workspaceIcon(state.workspace),
            ),
            _DomainCard(
              title: 'Project',
              value: project?.name ?? 'No project',
              detail: project?.pathLabel ?? 'Choose a project to bind context.',
              icon: Icons.folder_outlined,
            ),
            _DomainCard(
              title: 'Run',
              value: run?.title ?? state.selectedRunId ?? 'No saved run',
              detail: state.runState.label,
              icon: Icons.play_circle_outline,
            ),
            _DomainCard(
              title: 'Owner Mode',
              value: _liveOwnerLabel,
              detail: 'Authority is unchanged by the Experience shell.',
              icon: Icons.admin_panel_settings_outlined,
            ),
            _DomainCard(
              title: 'Browser runtime',
              value: widget.browserRuntimeAvailable
                  ? 'Available'
                  : 'Unavailable',
              detail: widget.browserRuntimeStatusCode,
              icon: Icons.web_outlined,
            ),
            if (state.recoveryMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              _BoundaryNotice(message: state.recoveryMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildP5ActivityDrawer(
    BuildContext context,
    P5PresentationState state,
  ) {
    final runtimeActivity = _webActivity.reversed
        .take(8)
        .toList(growable: false);
    final rows = <String>[
      'Workspace: ${state.workspace.label}',
      'Run state: ${state.runState.label}',
      if (state.recoveryMessage != null) 'Notice: ${state.recoveryMessage}',
      ...runtimeActivity.map((entry) => 'Browser: $entry'),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _P5ActivityHeader(
            title: 'Activity',
            subtitle: runtimeActivity.isEmpty
                ? 'Live presentation state — no fabricated saved timeline'
                : '${runtimeActivity.length} recent browser runtime events',
            onToggle: () => _updateP5ShellLayout(
              controller.shellLayout.copyWith(activityDrawerOpen: false),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              key: const Key('p5-activity-list'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: rows.length,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: Text(rows[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _P5ResizeHandle extends StatelessWidget {
  const _P5ResizeHandle.vertical({
    super.key,
    required this.semanticsLabel,
    required this.onDrag,
  }) : axis = Axis.vertical;

  const _P5ResizeHandle.horizontal({
    super.key,
    required this.semanticsLabel,
    required this.onDrag,
  }) : axis = Axis.horizontal;

  final Axis axis;
  final String semanticsLabel;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Semantics(
      label: semanticsLabel,
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: vertical
              ? (details) => onDrag(details.delta.dx)
              : null,
          onVerticalDragUpdate: vertical
              ? null
              : (details) => onDrag(details.delta.dy),
          child: SizedBox(
            width: vertical ? 8 : double.infinity,
            height: vertical ? double.infinity : 8,
            child: Center(
              child: Container(
                width: vertical ? 1 : 36,
                height: vertical ? 36 : 1,
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _P5ActivityHeader extends StatelessWidget {
  const _P5ActivityHeader({
    required this.title,
    required this.subtitle,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.timeline_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            key: const Key('p5-activity-collapse-button'),
            tooltip: 'Collapse activity drawer',
            onPressed: onToggle,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }
}
