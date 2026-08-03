import 'package:flutter/material.dart';

import 'p2_product_runtime_bootstrap.dart';

/// Shipped application shell. Owner Mode is a first-class navigation surface,
/// not a test-only widget or a hidden route.
class P2KristinShell extends StatefulWidget {
  const P2KristinShell({
    super.key,
    required this.ownerMode,
    required this.chat,
  });

  final P2ProductRuntimeOwnerModeHandle ownerMode;
  final Widget chat;

  @override
  State<P2KristinShell> createState() => _P2KristinShellState();
}

class _P2KristinShellState extends State<P2KristinShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final qaPreview = widget.ownerMode.runtimeProvenance['qaPreview'] == true;
    final pages = <Widget>[
      widget.chat,
      widget.ownerMode.buildWorkspace(
        key: const ValueKey<String>('kristin-owner-mode-workspace'),
      ),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: 'Chat',
      ),
      NavigationDestination(
        icon: Icon(
          widget.ownerMode.available
              ? Icons.admin_panel_settings_outlined
              : Icons.gpp_bad_outlined,
        ),
        selectedIcon: Icon(
          widget.ownerMode.available
              ? Icons.admin_panel_settings
              : Icons.gpp_bad,
        ),
        label: 'Owner Mode',
      ),
    ];
    final shell = Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => _index = value),
      ),
    );
    if (!qaPreview) return shell;
    return Banner(
      message: 'OWNER-RISK QA — SECURITY EVIDENCE WAIVED',
      location: BannerLocation.topEnd,
      color: Colors.deepOrange,
      child: shell,
    );
  }
}
