#!/usr/bin/env python3
"""One-shot current-main P5 Product materializer.

The script is transport only. It rebuilds the canonical P5 branch from the exact
protected-main tree, ports only the runnable P5 Dart source/tests, integrates the
experience workspace into the shipped shell, repairs Owner Mode failure
presentation, validates the complete Product, removes itself with the transport
workflow, and publishes one exact two-parent candidate.
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "agent/f/P5-001-information-architecture"
EXPECTED_PRE_TRANSPORT_HEAD = "00de2bbf075d4cb91e0f82a1326f9fa6e975786d"
EXPECTED_MAIN = "67e6e0314877d4ff3233d3e11e0743dd7562de55"
P5_SOURCE_BRANCH = "agent/help/elastic-7d41b6a2/mission-005/p5-stale-preview"
P5_SOURCE_HEAD = "c55e093fec9c5858b63b77c80c7abe2d653e863f"
TEMP_WORKFLOW = ".github/workflows/temp-p5-main-delivery-20260815.yml"
TEMP_SCRIPT = "tool/temp_p5_main_delivery_20260815.py"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        output = result.stdout or ""
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n{output}"
        )
    return (result.stdout or "").strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def rebuild_from_main(transport_head: str) -> None:
    current_branch = run("git", "branch", "--show-current", capture=True)
    if current_branch != EXPECTED_BRANCH:
        raise RuntimeError(f"unexpected branch: {current_branch}")
    if run("git", "rev-parse", "HEAD", capture=True) != transport_head:
        raise RuntimeError("checkout is not bound to GITHUB_SHA")
    run(
        "git",
        "merge-base",
        "--is-ancestor",
        EXPECTED_PRE_TRANSPORT_HEAD,
        transport_head,
    )
    run(
        "git",
        "fetch",
        "--no-tags",
        "origin",
        "+refs/heads/main:refs/remotes/origin/main",
        f"+refs/heads/{P5_SOURCE_BRANCH}:refs/remotes/origin/p5-source",
    )
    if run("git", "rev-parse", "refs/remotes/origin/main", capture=True) != EXPECTED_MAIN:
        raise RuntimeError("protected main moved; recompute instead of landing stale source")
    if run("git", "rev-parse", "refs/remotes/origin/p5-source", capture=True) != P5_SOURCE_HEAD:
        raise RuntimeError("P5 source helper moved")

    run("git", "read-tree", "--reset", "-u", EXPECTED_MAIN)
    run(
        "git",
        "checkout",
        P5_SOURCE_HEAD,
        "--",
        "lib/product/p5_information_architecture",
        "test/product/p5_information_architecture",
    )
    for relative in (
        "test/product/p5_information_architecture/worker_f_p5_ia.py",
        "test/product/p5_information_architecture/worker_f_p5_ia_test.py",
    ):
        path = REPO_ROOT / relative
        if path.exists():
            path.unlink()
    if (REPO_ROOT / "lib/p5_ia_preview.dart").exists():
        raise RuntimeError("stale P5 preview unexpectedly survived current-main rebuild")
    if (REPO_ROOT / TEMP_WORKFLOW).exists() or (REPO_ROOT / TEMP_SCRIPT).exists():
        raise RuntimeError("temporary transport survived current-main rebuild")


def integrate_main_shell() -> None:
    path = REPO_ROOT / "lib/product/ui.dart"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import 'p2_app_shell.dart';\n",
        "import 'p2_product_runtime_bootstrap.dart';\n"
        "import 'p5_information_architecture/p5_controller.dart';\n"
        "import 'p5_information_architecture/p5_prototype.dart';\n",
        "ui imports",
    )
    text = replace_once(
        text,
        """      home: P2KristinShell(
        ownerMode: widget.runtime.p2OwnerMode,
        chat: ChatStudio(
          runtime: widget.runtime,
          api: api,
          startupError: startupError,
        ),
      ),
""",
        """      home: KristinMainShell(
        ownerMode: widget.runtime.p2OwnerMode,
        chat: ChatStudio(
          runtime: widget.runtime,
          api: api,
          startupError: startupError,
        ),
      ),
""",
        "shipped home",
    )
    marker = "ThemeData _studioTheme(Brightness brightness) {"
    shell = r'''
class KristinMainShell extends StatefulWidget {
  const KristinMainShell({
    super.key,
    required this.ownerMode,
    required this.chat,
  });

  final P2ProductRuntimeOwnerModeHandle ownerMode;
  final Widget chat;

  @override
  State<KristinMainShell> createState() => _KristinMainShellState();
}

class _KristinMainShellState extends State<KristinMainShell> {
  var _index = 0;
  late final P5InformationArchitectureController _experienceController;

  @override
  void initState() {
    super.initState();
    _experienceController = P5InformationArchitectureController();
  }

  @override
  void dispose() {
    _experienceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qaPreview = widget.ownerMode.runtimeProvenance['qaPreview'] == true;
    final ownerAvailable = widget.ownerMode.available;
    final pages = <Widget>[
      widget.chat,
      P5InformationArchitecturePrototype(
        controller: _experienceController,
      ),
      widget.ownerMode.buildWorkspace(
        key: const ValueKey<String>('kristin-owner-mode-workspace'),
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final shell = Scaffold(
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: _selectDestination,
                  destinations: <NavigationRailDestination>[
                    const NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: Text('Chat'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.dashboard_customize_outlined),
                      selectedIcon: Icon(Icons.dashboard_customize),
                      label: Text('Experience'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(
                        ownerAvailable
                            ? Icons.admin_panel_settings_outlined
                            : Icons.gpp_bad_outlined,
                      ),
                      selectedIcon: Icon(
                        ownerAvailable
                            ? Icons.admin_panel_settings
                            : Icons.gpp_bad,
                      ),
                      label: const Text('Owner Mode'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ],
            )
          : IndexedStack(index: _index, children: pages),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
              destinations: <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Chat',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.dashboard_customize_outlined),
                  selectedIcon: Icon(Icons.dashboard_customize),
                  label: 'Experience',
                ),
                NavigationDestination(
                  icon: Icon(
                    ownerAvailable
                        ? Icons.admin_panel_settings_outlined
                        : Icons.gpp_bad_outlined,
                  ),
                  selectedIcon: Icon(
                    ownerAvailable
                        ? Icons.admin_panel_settings
                        : Icons.gpp_bad,
                  ),
                  label: 'Owner Mode',
                ),
              ],
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

  void _selectDestination(int value) {
    if (value == _index) return;
    setState(() => _index = value);
  }
}

'''
    text = replace_once(text, marker, shell + marker, "main shell insertion")
    path.write_text(text, encoding="utf-8", newline="\n")


def repair_owner_mode() -> None:
    path = REPO_ROOT / "lib/product/p2_product_runtime_bootstrap.dart"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        """  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';

""",
        """  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';

  String get diagnosticCode =>
      _normalizedFailureCode(failureCode ?? 'owner_runtime_start_failed');

  String get recoveryMessage {
    if (diagnosticCode == 'merged_p1a_service_unavailable') {
      return 'The Kristin Authority Service is not installed or running. Install or start it, then restart Kristin. Owner Mode stayed locked and no host authority was granted.';
    }
    if (diagnosticCode == 'product_runtime_p2_not_initialized') {
      return 'Owner Mode has not finished starting. Restart Kristin and open Owner Mode again. No host authority was granted.';
    }
    return 'Kristin could not start Owner Mode safely. Review the diagnostic code, repair the local runtime, and restart Kristin. No host authority was granted.';
  }

""",
        "Owner Mode recovery getters",
    )
    text = replace_once(
        text,
        """                const Text(
                  'Kristin failed closed because the isolated P1 authority service or the application-owned P2 runtime bundle was unavailable. No host authority was granted.',
                  textAlign: TextAlign.center,
                ),
""",
        """                Text(
                  recoveryMessage,
                  textAlign: TextAlign.center,
                ),
""",
        "Owner Mode recovery copy",
    )
    text = replace_once(
        text,
        "                SelectableText('Status: ${failureCode ?? 'unknown'}'),\n",
        "                SelectableText('Diagnostic: $diagnosticCode'),\n",
        "Owner Mode diagnostic label",
    )
    text = replace_once(
        text,
        """  static P2ProductRuntimeOwnerModeHandle blocked(String code) =>
      P2ProductRuntimeOwnerModeHandle._(runtime: null, failureCode: code);
}
""",
        """  static P2ProductRuntimeOwnerModeHandle blocked(String code) =>
      P2ProductRuntimeOwnerModeHandle._(
        runtime: null,
        failureCode: _normalizedFailureCode(code),
      );

  static String _normalizedFailureCode(String code) {
    final normalized = code
        .trim()
        .replaceFirst(
          RegExp(r'^Bad[ _]state[:_ ]+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'owner_runtime_start_failed' : normalized;
  }
}
""",
        "Owner Mode blocked factory",
    )
    text = replace_once(
        text,
        """  static String _safeFailureCode(Object error) {
    final value = '$error';
""",
        """  static String _safeFailureCode(Object error) {
    if (error is StateError &&
        error.message == 'merged_p1a_service_unavailable') {
      return 'merged_p1a_service_unavailable';
    }
    final value = '$error';
""",
        "stable P1A diagnostic",
    )
    path.write_text(text, encoding="utf-8", newline="\n")


def update_source_contract() -> None:
    path = REPO_ROOT / "test/product/source_contract_test.dart"
    text = path.read_text(encoding="utf-8")
    p5_paths = """        'lib/product/p5_information_architecture/p5_components.dart',
        'lib/product/p5_information_architecture/p5_controller.dart',
        'lib/product/p5_information_architecture/p5_fixtures.dart',
        'lib/product/p5_information_architecture/p5_models.dart',
        'lib/product/p5_information_architecture/p5_prototype.dart',
        'lib/product/p5_information_architecture/p5_support_workspaces.dart',
        'lib/product/p5_information_architecture/p5_task_workspaces.dart',
        'lib/product/p5_information_architecture/p5_verification_workspaces.dart',
"""
    text = replace_once(
        text,
        "        'lib/product/mcp_protocol.dart',\n",
        p5_paths + "        'lib/product/mcp_protocol.dart',\n",
        "source inventory",
    )
    pattern = re.compile(
        r"    test\('application opens chat-first through the governed P2 shell'.*?^    \}\);\n",
        re.MULTILINE | re.DOTALL,
    )
    replacement = """    test('application opens chat-first through the integrated experience shell', () {
      final ui = source('lib/product/ui.dart');
      expect(ui, contains('home: KristinMainShell('));
      expect(ui, contains('var _index = 0;'));
      final chatOffset = ui.indexOf('widget.chat,');
      final experienceOffset = ui.indexOf('P5InformationArchitecturePrototype(');
      final ownerOffset = ui.indexOf('widget.ownerMode.buildWorkspace(');
      expect(chatOffset, greaterThanOrEqualTo(0));
      expect(experienceOffset, greaterThan(chatOffset));
      expect(ownerOffset, greaterThan(experienceOffset));
    });
"""
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"source shell contract: expected one block, found {count}")
    text = replace_once(
        text,
        "expect(ui, contains('home: P2KristinShell('));",
        "expect(ui, contains('home: KristinMainShell('));",
        "secondary shell expectation",
    )
    text = replace_once(
        text,
        "final p2Shell = source('lib/product/p2_app_shell.dart');",
        "final shell = source('lib/product/ui.dart');",
        "secondary shell source",
    )
    text = replace_once(
        text,
        "expect(p2Shell, contains('var _index = 0;'));",
        "expect(shell, contains('var _index = 0;'));",
        "secondary initial workspace",
    )
    text = replace_once(
        text,
        "expect(p2Shell, contains('widget.chat,'));",
        "expect(shell, contains('widget.chat,'));",
        "secondary chat ordering",
    )
    if "home: P2KristinShell(" in text:
        raise RuntimeError("stale P2-only shell contract remains")
    path.write_text(text, encoding="utf-8", newline="\n")


def write_regressions() -> None:
    (REPO_ROOT / "test/product/p5_main_shell_integration_test.dart").write_text(
        """import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/ui.dart';

void main() {
  testWidgets('main shell exposes chat, experience, and Owner Mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ownerMode = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad state: merged_p1a_service_unavailable',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: KristinMainShell(
          ownerMode: ownerMode,
          chat: const Center(child: Text('Chat surface')),
        ),
      ),
    );

    expect(find.text('Chat surface'), findsOneWidget);
    await tester.tap(find.text('Experience'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-title')), findsOneWidget);

    await tester.tap(find.text('Owner Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Owner Mode is unavailable'), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
  });
}
""",
        encoding="utf-8",
        newline="\n",
    )
    (REPO_ROOT / "test/product/p2_owner_mode_failure_presentation_test.dart").write_text(
        """import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';

void main() {
  test('missing merged P1A service returns a stable diagnostic', () async {
    final root = await Directory.systemTemp.createTemp('kristin-p1a-missing-');
    addTearDown(() => root.delete(recursive: true));

    final handle = await P2ProductRuntimeBootstrap.start(
      dataRoot: root,
      p1AuthorityService: null,
    );

    expect(handle.available, isFalse);
    expect(handle.failureCode, 'merged_p1a_service_unavailable');
    expect(
      handle.runtimeProvenance['failureCode'],
      'merged_p1a_service_unavailable',
    );
  });

  testWidgets('blocked Owner Mode explains recovery without raw Dart text',
      (tester) async {
    final handle = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad_state:_merged_p1a_service_unavailable',
    );
    await tester.pumpWidget(MaterialApp(home: handle.buildWorkspace()));

    expect(find.textContaining('install or start it'), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('Bad_state'), findsNothing);
  });
}
""",
        encoding="utf-8",
        newline="\n",
    )


def validate_product() -> None:
    format_paths = [
        "lib/product/ui.dart",
        "lib/product/p2_product_runtime_bootstrap.dart",
        "lib/product/p5_information_architecture",
        "test/product/p5_information_architecture",
        "test/product/p5_main_shell_integration_test.dart",
        "test/product/p2_owner_mode_failure_presentation_test.dart",
        "test/product/source_contract_test.dart",
    ]
    run("dart", "format", *format_paths)
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (REPO_ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (REPO_ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py", "--check")
    run("flutter", "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos")
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter",
        "expanded",
    )
    run("npm", "test", "--prefix", "automation_host")


def prove_scope() -> None:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        EXPECTED_MAIN,
        "--",
        capture=True,
    ).splitlines()
    exact = {
        "SOURCE_MANIFEST.sha256",
        "lib/product/ui.dart",
        "lib/product/p2_product_runtime_bootstrap.dart",
        "test/product/source_contract_test.dart",
        "test/product/p5_main_shell_integration_test.dart",
        "test/product/p2_owner_mode_failure_presentation_test.dart",
    }
    prefixes = (
        "lib/product/p5_information_architecture/",
        "test/product/p5_information_architecture/",
    )
    unauthorized = [
        path for path in paths if path not in exact and not path.startswith(prefixes)
    ]
    if unauthorized:
        raise RuntimeError(f"unauthorized Product paths: {unauthorized}")
    if len(paths) < 20:
        raise RuntimeError(f"unexpectedly small Product candidate: {paths}")
    for forbidden in (TEMP_WORKFLOW, TEMP_SCRIPT, "lib/p5_ia_preview.dart"):
        if forbidden in paths:
            raise RuntimeError(f"temporary or stale path leaked into candidate: {forbidden}")
    print("Exact current-main Product diff:")
    print("\n".join(paths))


def publish(transport_head: str) -> tuple[str, str]:
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    tree = run("git", "write-tree", capture=True)
    message = (
        "feat(p5): ship integrated experience workspace\n\n"
        "Rebuild P5 on protected main, expose the tested experience workspace "
        "from the normal app shell, and replace raw Owner Mode startup errors "
        "with stable actionable recovery diagnostics.\n"
    )
    commit = subprocess.run(
        [
            "git",
            "commit-tree",
            tree,
            "-p",
            transport_head,
            "-p",
            EXPECTED_MAIN,
        ],
        cwd=REPO_ROOT,
        input=message,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout.strip()
    run("git", "reset", "--hard", commit)
    if run("git", "rev-parse", "HEAD^{tree}", capture=True) != tree:
        raise RuntimeError("published candidate tree changed")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("candidate worktree is not clean")
    run("git", "push", "origin", f"{commit}:refs/heads/{EXPECTED_BRANCH}")
    return commit, tree


def main() -> int:
    transport_head = os.environ.get("GITHUB_SHA", "").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", transport_head):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    rebuild_from_main(transport_head)
    integrate_main_shell()
    repair_owner_mode()
    update_source_contract()
    write_regressions()
    validate_product()
    prove_scope()
    commit, tree = publish(transport_head)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as handle:
            handle.write(
                "### Published runnable Product candidate\n"
                f"- commit: `{commit}`\n"
                f"- tree: `{tree}`\n"
                f"- protected-main base: `{EXPECTED_MAIN}`\n"
            )
    print(f"P5_MAIN_DELIVERY_SUCCESS commit={commit} tree={tree}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
