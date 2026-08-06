#!/usr/bin/env python3
"""Run the Worker F recovery patch with standard-library-only bootstrapping."""
from __future__ import annotations

import re
import runpy
import shutil
import sys
import textwrap
import types
from pathlib import Path


def safe_load(text: str):
    lines = text.splitlines()
    name = "Materialize reviewed source and deterministic contracts"
    start = next(
        index
        for index, line in enumerate(lines)
        if line.strip() == f"- name: {name}"
    )
    run_index = next(
        index
        for index in range(start + 1, len(lines))
        if lines[index].strip() == "run: |"
    )
    body: list[str] = []
    for line in lines[run_index + 1 :]:
        if line.startswith("      - name:"):
            break
        body.append(line)
    script = textwrap.dedent("\n".join(body)).rstrip() + "\n"
    return {
        "jobs": {
            "prepare": {
                "steps": [
                    {
                        "name": name,
                        "run": script,
                    }
                ]
            }
        }
    }


root = Path(".")
checker_template = root / "tool/worker_f_p5_ia_template.py"
workflow_template = root / "tool/worker_f_p5_ia_workflow_template.yml"
shutil.copyfile(checker_template, root / "tool/worker_f_p5_ia.py")
(root / ".github/workflows").mkdir(parents=True, exist_ok=True)
shutil.copyfile(
    workflow_template,
    root / ".github/workflows/worker-f-p5-001-information-architecture.yml",
)
checker_template.unlink()
workflow_template.unlink()

patch_path = root / "tool/worker_f_recovery_patch.py"
patch_text = patch_path.read_text(encoding="utf-8").replace(
    '"326462d4db7c9ec895c7f9dbf09de84fa83b8895": "3c8d9d7ad78bd47970c4742f55a355e0768ea718",',
    '"326462d4db7c9ec895c7f9dbf09de84fa83b8895": "3c8d9d7ad78bd47970c4742f55a355e0768ea718",\n'
    '    "d581f21fb7b36ca9938cb55f24052df36df8475f": "ef5d5ae584b1d823502bf6f2191ecf4285d36845",',
)
patch_text = patch_text.replace(
    "    patch_validator()\n",
    "    # The current checker is supplied as a deterministic reviewed template.\n",
)
patch_text = patch_text.replace(
    "    patch_workflow()\n",
    "    # The read-only tri-platform workflow is supplied as a pinned template.\n",
)
patch_path.write_text(patch_text, encoding="utf-8")

yaml_module = types.ModuleType("yaml")
yaml_module.safe_load = safe_load
sys.modules["yaml"] = yaml_module
try:
    runpy.run_path("tool/worker_f_recovery_patch.py", run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        raise

components_path = root / "lib/product/p5_information_architecture/p5_components.dart"
components = components_path.read_text(encoding="utf-8")
components, removed = re.subn(
    r"\nextension _P5IterableFirstOrNull<T> on Iterable<T> \{\n"
    r"  T\? get firstOrNull \{\n"
    r"    final iterator = this\.iterator;\n"
    r"    return iterator\.moveNext\(\) \? iterator\.current : null;\n"
    r"  \}\n"
    r"\}\n?$",
    "\n",
    components,
    count=1,
)
if removed != 1:
    raise RuntimeError("duplicate firstOrNull extension was not found")
components_path.write_text(components, encoding="utf-8")

accessibility_path = root / "test/product/p5_information_architecture/p5_accessibility_test.dart"
accessibility_path.write_text(
    r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    P5InformationArchitectureApp(controller: controller),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressChord(
  WidgetTester tester, {
  required LogicalKeyboardKey modifier,
  LogicalKeyboardKey? secondModifier,
  required LogicalKeyboardKey key,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (secondModifier != null) {
    await tester.sendKeyDownEvent(secondModifier);
  }
  await tester.sendKeyEvent(key);
  if (secondModifier != null) {
    await tester.sendKeyUpEvent(secondModifier);
  }
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _focusWithTab(
  WidgetTester tester,
  Finder target, {
  int maximumTabs = 30,
}) async {
  for (var index = 0; index < maximumTabs; index++) {
    if (target.evaluate().isNotEmpty &&
        Focus.of(tester.element(target)).hasPrimaryFocus) {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Target did not receive focus after $maximumTabs Tab presses.');
}

void main() {
  testWidgets('keyboard-only primary and verification flows', (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    final reviewButton = find.byKey(const Key('review-plan-button'));
    await _focusWithTab(tester, reviewButton);
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('concise-plan-card')), findsOneWidget);

    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.controlLeft,
      secondModifier: LogicalKeyboardKey.shiftLeft,
      key: LogicalKeyboardKey.keyV,
    );
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(find.text('Verification Center'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.homeChat);

    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.altLeft,
      key: LogicalKeyboardKey.digit3,
    );
    expect(controller.state.workspace, P5WorkspaceId.runsActivity);
    await _pressChord(
      tester,
      modifier: LogicalKeyboardKey.altLeft,
      key: LogicalKeyboardKey.digit4,
    );
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('primary navigation and state semantics are announced',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await _pump(tester, controller);

    expect(
      find.bySemanticsLabel('Home / Chat workspace, shortcut Alt+1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Owner Mode status: Blocked by environment. Presentation only.',
      ),
      findsOneWidget,
    );

    controller.selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    await tester.pumpAndSettle();
    final webCapability = find.byKey(const Key('capability-webStudio'));
    await tester.ensureVisible(webCapability);
    await tester.tap(webCapability);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'Web Studio is BLOCKED_BY_DEPENDENCY. P3-001 browser runtime is not implemented.',
      ),
      findsOneWidget,
    );
    expect(controller.sideEffects, P5SideEffectLedger.zero);
  });
}
''',
    encoding="utf-8",
)
