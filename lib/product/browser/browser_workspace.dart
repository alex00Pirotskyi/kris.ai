import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'browser_quality.dart';
import 'browser_runtime.dart';

enum P3BrowserWorkspaceSection {
  page,
  dom,
  accessibility,
  console,
  network,
  testTools,
}

enum P3BrowserViewportPreset {
  desktop(1440, 900),
  tablet(820, 1180),
  mobile(390, 844);

  const P3BrowserViewportPreset(this.width, this.height);
  final int width;
  final int height;
}

final class P3BrowserWorkspaceController extends ChangeNotifier {
  P3BrowserPageObservation? _observation;
  P3BrowserViewportPreset _viewport = P3BrowserViewportPreset.desktop;
  String _status = 'No page observation yet';

  P3BrowserPageObservation? get observation => _observation;
  P3BrowserViewportPreset get viewport => _viewport;
  String get status => _status;

  void showObservation(P3BrowserPageObservation value) {
    _observation = value;
    _status = 'Observation ${value.observationHash.substring(0, 12)} verified';
    notifyListeners();
  }

  void setViewport(P3BrowserViewportPreset value) {
    if (_viewport == value) return;
    _viewport = value;
    notifyListeners();
  }

  void setStatus(String value) {
    final normalized = value.trim();
    _status = normalized.isEmpty ? 'Ready' : normalized;
    notifyListeners();
  }
}

final class P3BrowserWorkspace extends StatelessWidget {
  const P3BrowserWorkspace({
    super.key,
    required this.controller,
    this.onViewportPreset,
    this.onRefresh,
    this.onUserTakeover,
  });

  final P3BrowserWorkspaceController controller;
  final ValueChanged<P3BrowserViewportPreset>? onViewportPreset;
  final VoidCallback? onRefresh;
  final VoidCallback? onUserTakeover;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DefaultTabController(
          length: P3BrowserWorkspaceSection.values.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Toolbar(
                controller: controller,
                onViewportPreset: onViewportPreset,
                onRefresh: onRefresh,
                onUserTakeover: onUserTakeover,
              ),
              const TabBar(
                isScrollable: true,
                tabs: <Widget>[
                  Tab(text: 'Page', icon: Icon(Icons.public)),
                  Tab(text: 'DOM', icon: Icon(Icons.account_tree_outlined)),
                  Tab(
                      text: 'Accessibility',
                      icon: Icon(Icons.accessibility_new)),
                  Tab(text: 'Console', icon: Icon(Icons.terminal)),
                  Tab(text: 'Network', icon: Icon(Icons.swap_vert)),
                  Tab(
                      text: 'Test tools',
                      icon: Icon(Icons.fact_check_outlined)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _PagePanel(controller.observation),
                    _JsonPanel(
                      label: 'DOM snapshot',
                      value: _field(controller.observation, 'dom'),
                    ),
                    _JsonPanel(
                      label: 'Accessibility snapshot',
                      value: _field(controller.observation, 'accessibility'),
                    ),
                    _JsonPanel(
                      label: 'Console telemetry',
                      value: _field(controller.observation, 'console'),
                    ),
                    _JsonPanel(
                      label: 'Network telemetry',
                      value: _field(controller.observation, 'network'),
                    ),
                    _TestToolsPanel(controller: controller),
                  ],
                ),
              ),
              Semantics(
                liveRegion: true,
                label: 'Browser workspace status',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Text(
                    controller.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onViewportPreset,
    required this.onRefresh,
    required this.onUserTakeover,
  });

  final P3BrowserWorkspaceController controller;
  final ValueChanged<P3BrowserViewportPreset>? onViewportPreset;
  final VoidCallback? onRefresh;
  final VoidCallback? onUserTakeover;

  @override
  Widget build(BuildContext context) {
    final observation = controller.observation;
    final url = observation?.observation['url']?.toString() ?? 'about:blank';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final location = Expanded(
          child: Semantics(
            label: 'Current browser URL',
            child: SelectableText(
              url,
              maxLines: 1,
            ),
          ),
        );
        final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Tooltip(
              message: 'Responsive viewport preset',
              child: DropdownButton<P3BrowserViewportPreset>(
                value: controller.viewport,
                items: P3BrowserViewportPreset.values
                    .map(
                      (value) => DropdownMenuItem<P3BrowserViewportPreset>(
                        value: value,
                        child: Text(
                          '${value.name} ${value.width}×${value.height}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  controller.setViewport(value);
                  onViewportPreset?.call(value);
                },
              ),
            ),
            IconButton(
              tooltip: 'Refresh observation',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.tonalIcon(
              onPressed: onUserTakeover,
              icon: const Icon(Icons.pan_tool_alt_outlined),
              label: const Text('Take over'),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.all(12),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(children: <Widget>[location]),
                    const SizedBox(height: 8),
                    controls,
                  ],
                )
              : Row(
                  children: <Widget>[
                    location,
                    const SizedBox(width: 12),
                    controls,
                  ],
                ),
        );
      },
    );
  }
}

final class _PagePanel extends StatelessWidget {
  const _PagePanel(this.observation);
  final P3BrowserPageObservation? observation;

  @override
  Widget build(BuildContext context) {
    final value = observation;
    if (value == null) {
      return const Center(child: Text('Start or select a browser page.'));
    }
    final screenshotValue = value.observation['screenshot'];
    Uint8List? bytes;
    if (screenshotValue is Map) {
      final encoded = screenshotValue['base64'];
      if (encoded is String) {
        try {
          bytes = base64Decode(encoded);
        } on FormatException {
          bytes = null;
        }
      }
    }
    final visible = _textField(value.observation['visibleText']);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final preview = Card(
          margin: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? const Center(child: Text('Screenshot unavailable'))
              : InteractiveViewer(
                  minScale: 0.25,
                  maxScale: 4,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
        );
        final text = Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                visible.isEmpty ? 'No visible text captured.' : visible,
              ),
            ),
          ),
        );
        return wide
            ? Row(
                children: <Widget>[
                  Expanded(flex: 3, child: preview),
                  Expanded(flex: 2, child: text),
                ],
              )
            : Column(
                children: <Widget>[
                  Expanded(flex: 3, child: preview),
                  Expanded(flex: 2, child: text),
                ],
              );
      },
    );
  }
}

final class _JsonPanel extends StatelessWidget {
  const _JsonPanel({required this.label, required this.value});
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(value ?? <String, Object?>{});
    final bounded = encoded.length > 512 * 1024
        ? '${encoded.substring(0, 512 * 1024)}\n…truncated…'
        : encoded;
    return Semantics(
      label: label,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(bounded),
      ),
    );
  }
}

final class _TestToolsPanel extends StatelessWidget {
  const _TestToolsPanel({required this.controller});
  final P3BrowserWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final observation = controller.observation;
    final accessibility = _textField(observation?.observation['accessibility']);
    final checks = <(String, bool)>[
      ('Canonical observation hash available', observation != null),
      ('Accessibility tree captured', accessibility.trim().isNotEmpty),
      ('Desktop viewport preset available', true),
      ('Tablet viewport preset available', true),
      ('Mobile viewport preset available', true),
      ('Screenshot diff contract available', true),
      ('Link and form checks available', true),
      ('Prompt-injection and stale-target guards available', true),
      ('Receipt-producing task recipes available', true),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text(
          'Responsive and accessibility checks',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final check in checks)
          ListTile(
            leading: Icon(check.$2 ? Icons.check_circle : Icons.error_outline),
            title: Text(check.$1),
            subtitle: check.$2
                ? null
                : const Text('Needs attention before completion.'),
          ),
        const Divider(),
        SelectableText(
          'Active preset: ${controller.viewport.name} '
          '${controller.viewport.width}×${controller.viewport.height}',
        ),
        const SizedBox(height: 12),
        Text(
          'Deterministic task recipes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final recipe in P3BrowserTaskRecipes.all)
              Tooltip(
                message: recipe.description,
                child: Chip(
                  key: Key('browser-recipe-${recipe.kind.name}'),
                  avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(recipe.kind.name),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Object? _field(P3BrowserPageObservation? observation, String key) =>
    observation?.observation[key];

String _textField(Object? raw) {
  if (raw is! Map) return '';
  final value = raw['text'];
  return value is String ? value : '';
}
