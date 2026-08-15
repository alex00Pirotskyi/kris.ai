#!/usr/bin/env python3
"""Finalize and validate the P5-002 design-token Product candidate."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/product/p5-002-design-tokens-3a7c91e4"
BASE = "8bc2d61bbaa35a1bf10285cbb9993a17e50c1cb2"
WORKFLOW = ".github/workflows/temp-p5-002-design-tokens-3a7c91e4.yml"
SCRIPT = "tool/temp_p5_002_design_tokens_3a7c91e4.py"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout or ''}"
        )
    return (result.stdout or "").strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def patch_design_tokens() -> None:
    path = ROOT / "lib/product/p5_design_tokens.dart"
    text = path.read_text(encoding="utf-8")
    text = text.replace("FontWeight.w650", "FontWeight.w600")
    text = text.replace("FontWeight.w750", "FontWeight.w700")
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_ui() -> None:
    path = ROOT / "lib/product/ui.dart"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import 'p2_product_runtime_bootstrap.dart';\n"
        "import 'p5_information_architecture/p5_controller.dart';",
        "import 'p2_product_runtime_bootstrap.dart';\n"
        "import 'p5_design_tokens.dart';\n"
        "import 'p5_information_architecture/p5_controller.dart';",
        "P5 design-token import",
    )
    text = replace_once(
        text,
        "class _KristinAppState extends State<KristinApp> {",
        "class _KristinAppState extends State<KristinApp> "
        "with WidgetsBindingObserver {",
        "KristinApp accessibility observer",
    )
    text = replace_once(
        text,
        "  void initState() {\n"
        "    super.initState();\n"
        "    if (widget.runtime.settings.apiEnabled) {",
        "  void initState() {\n"
        "    super.initState();\n"
        "    WidgetsBinding.instance.addObserver(this);\n"
        "    if (widget.runtime.settings.apiEnabled) {",
        "register accessibility observer",
    )
    text = replace_once(
        text,
        "  void dispose() {\n"
        "    unawaited(api.stop());",
        "  void dispose() {\n"
        "    WidgetsBinding.instance.removeObserver(this);\n"
        "    unawaited(api.stop());",
        "remove accessibility observer",
    )
    text = replace_once(
        text,
        "  @override\n"
        "  Widget build(BuildContext context) {\n"
        "    return MaterialApp(\n"
        "      title: 'Kristin Local Agent',\n"
        "      debugShowCheckedModeBanner: false,\n"
        "      theme: _studioTheme(Brightness.light),\n"
        "      darkTheme: _studioTheme(Brightness.dark),\n"
        "      themeMode: ThemeMode.system,",
        "  @override\n"
        "  void didChangeAccessibilityFeatures() {\n"
        "    if (mounted) setState(() {});\n"
        "  }\n\n"
        "  @override\n"
        "  Widget build(BuildContext context) {\n"
        "    final reducedMotion = WidgetsBinding.instance.platformDispatcher\n"
        "        .accessibilityFeatures.disableAnimations;\n"
        "    return MaterialApp(\n"
        "      title: 'Kristin Local Agent',\n"
        "      debugShowCheckedModeBanner: false,\n"
        "      theme: _studioTheme(\n"
        "        Brightness.light,\n"
        "        reducedMotion: reducedMotion,\n"
        "      ),\n"
        "      darkTheme: _studioTheme(\n"
        "        Brightness.dark,\n"
        "        reducedMotion: reducedMotion,\n"
        "      ),\n"
        "      highContrastTheme: _studioTheme(\n"
        "        Brightness.light,\n"
        "        highContrast: true,\n"
        "        reducedMotion: reducedMotion,\n"
        "      ),\n"
        "      highContrastDarkTheme: _studioTheme(\n"
        "        Brightness.dark,\n"
        "        highContrast: true,\n"
        "        reducedMotion: reducedMotion,\n"
        "      ),\n"
        "      themeMode: ThemeMode.system,\n"
        "      themeAnimationDuration:\n"
        "          P5DesignSystem.themeTransitionDuration(reducedMotion),\n"
        "      themeAnimationCurve: Curves.easeOutCubic,",
        "MaterialApp design-token wiring",
    )
    pattern = re.compile(
        r"ThemeData _studioTheme\(Brightness brightness\) \{.*?\n\}\n\n"
        r"class SimpleStudio",
        re.DOTALL,
    )
    replacement = """ThemeData _studioTheme(
  Brightness brightness, {
  bool highContrast = false,
  bool reducedMotion = false,
}) {
  return P5DesignSystem.theme(
    brightness: brightness,
    highContrast: highContrast,
    reducedMotion: reducedMotion,
  );
}

class SimpleStudio"""
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"theme delegation: expected one match, found {count}")
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_source_contract() -> None:
    path = ROOT / "test/product/source_contract_test.dart"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "        'lib/product/p2_terminal_model.dart',\n"
        "        'lib/product/p5_information_architecture/p5_components.dart',",
        "        'lib/product/p2_terminal_model.dart',\n"
        "        'lib/product/p5_design_tokens.dart',\n"
        "        'lib/product/p5_information_architecture/p5_components.dart',",
        "governed source inventory",
    )
    marker = "    test('stale-source migration consumes governed inventories', () {"
    addition = """    test('application wires semantic accessibility themes', () {
      final ui = source('lib/product/ui.dart');
      expect(ui, contains("import 'p5_design_tokens.dart';"));
      expect(ui, contains('highContrastTheme: _studioTheme('));
      expect(ui, contains('highContrastDarkTheme: _studioTheme('));
      expect(ui, contains('accessibilityFeatures.disableAnimations'));
      expect(ui, contains('P5DesignSystem.themeTransitionDuration'));
      expect(ui, contains('WidgetsBinding.instance.addObserver(this)'));
      expect(ui, contains('WidgetsBinding.instance.removeObserver(this)'));
    });

""" + marker
    text = replace_once(text, marker, addition, "design-system source contract")
    path.write_text(text, encoding="utf-8", newline="\n")


def validate() -> None:
    run("flutter", "pub", "get")
    run("python3", "tool/dart_format_scope.py")
    run("python3", "tool/dart_format_scope.py", "--check")
    run(
        "flutter",
        "analyze",
        "--no-pub",
        "--fatal-warnings",
        "--fatal-infos",
    )
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter=expanded",
        "test/product/p5_design_tokens_test.dart",
        "test/product/source_contract_test.dart",
    )
    run(
        "flutter",
        "test",
        "--no-pub",
        "--concurrency=1",
        "--reporter=expanded",
    )
    run("npm", "ci", "--prefix", "automation_host")
    run("npm", "test", "--prefix", "automation_host")


def finalize_manifest() -> None:
    (ROOT / WORKFLOW).unlink()
    (ROOT / SCRIPT).unlink()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def prove_scope() -> list[str]:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        BASE,
        "--",
        capture=True,
    ).splitlines()
    expected = {
        "SOURCE_MANIFEST.sha256",
        "lib/product/p5_design_tokens.dart",
        "lib/product/ui.dart",
        "test/product/p5_design_tokens_test.dart",
        "test/product/source_contract_test.dart",
    }
    if set(paths) != expected:
        raise RuntimeError(
            f"exact P5-002 scope mismatch: expected {sorted(expected)}, got {paths}"
        )
    if "config/p2_source_inventory.v1.json" in paths:
        raise RuntimeError("P5 source must not pollute the P2-only inventory")
    return paths


def publish(paths: list[str]) -> None:
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    run(
        "git",
        "commit",
        "-m",
        "feat(p5): add accessible semantic design tokens",
        "-m",
        "Introduce readable light, dark, high-contrast, and reduced-motion "
        "themes for the normal application shell with deterministic tests and "
        "a canonical source manifest.",
    )
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"P5_002_FINAL_COMMIT={head}")
    print(f"P5_002_FINAL_TREE={tree}")
    print("P5_002_FINAL_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise RuntimeError("checkout does not match the exact trigger head")
    run("git", "merge-base", "--is-ancestor", BASE, trigger)
    patch_design_tokens()
    patch_ui()
    patch_source_contract()
    validate()
    finalize_manifest()
    paths = prove_scope()
    publish(paths)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
