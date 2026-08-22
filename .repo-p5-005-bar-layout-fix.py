from pathlib import Path

path = Path('lib/product/p5_global_autonomy.dart')
text = path.read_text(encoding='utf-8')
old = '''              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: <Widget>[
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-profile'),
                      icon: Icons.shield_outlined,
                      label: 'Profile: ${snapshot.profileLabel}',
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-model'),
                      icon: Icons.memory_outlined,
                      label: 'Model: ${snapshot.modelLabel}',
                    ),
                    Tooltip(
                      message: snapshot.sessionBreakdown,
                      child: _P5AutonomyStatusChip(
                        key: const Key('p5-global-sessions'),
                        icon: Icons.hub_outlined,
                        label: 'Sessions: ${snapshot.activeSessionCount}',
                      ),
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-takeover'),
                      icon: Icons.pan_tool_outlined,
                      label: 'Takeover: ${snapshot.takeoverLabel}',
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-network'),
                      icon: Icons.public_outlined,
                      label: 'Network: ${snapshot.networkLabel}',
                    ),
                    const SizedBox(width: 8),
                    Center(
                      child: FilledButton.tonalIcon(
                        key: const Key('p5-global-pause'),
                        onPressed: _busy || !snapshot.canPause
                            ? null
                            : () => _perform(widget.binding.pauseActiveRuns),
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Center(
                      child: OutlinedButton.icon(
                        key: const Key('p5-global-stop'),
                        onPressed: _busy || !snapshot.canStop
                            ? null
                            : () => _perform(widget.binding.stopActiveRuns),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Center(
                      child: FilledButton.icon(
                        key: const Key('p5-global-kill'),
                        onPressed: _busy || !snapshot.canEmergencyKill
                            ? null
                            : () => _perform(widget.binding.emergencyKill),
                        icon: const Icon(Icons.emergency_outlined),
                        label: const Text('Emergency kill'),
                      ),
                    ),
                    if (_busy) ...<Widget>[
                      const SizedBox(width: 10),
                      const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                    if (_errorCode != null) ...<Widget>[
                      const SizedBox(width: 10),
                      Center(
                        child: Text(
                          _errorCode!,
                          key: const Key('p5-global-action-error'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
'''
new = '''              child: SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('p5-global-status-scroll'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: <Widget>[
                            _P5AutonomyStatusChip(
                              key: const Key('p5-global-profile'),
                              icon: Icons.shield_outlined,
                              label: 'Profile: ${snapshot.profileLabel}',
                            ),
                            _P5AutonomyStatusChip(
                              key: const Key('p5-global-model'),
                              icon: Icons.memory_outlined,
                              label: 'Model: ${snapshot.modelLabel}',
                            ),
                            Tooltip(
                              message: snapshot.sessionBreakdown,
                              child: _P5AutonomyStatusChip(
                                key: const Key('p5-global-sessions'),
                                icon: Icons.hub_outlined,
                                label: 'Sessions: ${snapshot.activeSessionCount}',
                              ),
                            ),
                            _P5AutonomyStatusChip(
                              key: const Key('p5-global-takeover'),
                              icon: Icons.pan_tool_outlined,
                              label: 'Takeover: ${snapshot.takeoverLabel}',
                            ),
                            _P5AutonomyStatusChip(
                              key: const Key('p5-global-network'),
                              icon: Icons.public_outlined,
                              label: 'Network: ${snapshot.networkLabel}',
                            ),
                            if (_errorCode != null) ...<Widget>[
                              const SizedBox(width: 10),
                              Text(
                                _errorCode!,
                                key: const Key('p5-global-action-error'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_busy) ...<Widget>[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: const Key('p5-global-pause'),
                      onPressed: _busy || !snapshot.canPause
                          ? null
                          : () => _perform(widget.binding.pauseActiveRuns),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      key: const Key('p5-global-stop'),
                      onPressed: _busy || !snapshot.canStop
                          ? null
                          : () => _perform(widget.binding.stopActiveRuns),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: FilledButton.icon(
                        key: const Key('p5-global-kill'),
                        onPressed: _busy || !snapshot.canEmergencyKill
                            ? null
                            : () => _perform(widget.binding.emergencyKill),
                        icon: const Icon(Icons.emergency_outlined),
                        label: const Text('Emergency kill'),
                      ),
                    ),
                  ],
                ),
              ),
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one global bar layout anchor, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P5_005_BAR_LAYOUT_FIX_APPLIED')
