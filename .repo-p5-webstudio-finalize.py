from __future__ import annotations

from pathlib import Path
import re
import subprocess

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


accessibility = ROOT / 'test/product/p5_information_architecture/p5_accessibility_test.dart'
expected_accessibility = 'ef8599d34758c0ac3cff49fcf514df160e5d5bd5'
actual_accessibility = subprocess.check_output(
    ['git', 'hash-object', str(accessibility)], text=True
).strip()
if actual_accessibility != expected_accessibility:
    raise SystemExit(
        f'P5 accessibility collision: expected={expected_accessibility} actual={actual_accessibility}'
    )

navigation = ROOT / 'test/product/p5_information_architecture/p5_navigation_test.dart'
nav_text = navigation.read_text(encoding='utf-8')
nav_pattern = re.compile(
    r"^  testWidgets\('Web Studio unavailable state has an exit', \(tester\) async \{.*?^  \}\);\n",
    re.MULTILINE | re.DOTALL,
)
nav_replacement = (
    "  testWidgets('Web Studio opens from capabilities and has a navigation exit',\n"
    "      (tester) async {\n"
    "    final controller = P5InformationArchitectureController()\n"
    "      ..changeExperienceLevel(P5ExperienceLevel.advanced)\n"
    "      ..selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);\n"
    "    addTearDown(controller.dispose);\n"
    "    await pumpPrototype(tester, controller);\n\n"
    "    await tapKey(tester, const Key('capability-webStudio'));\n"
    "    expect(controller.state.workspace, P5WorkspaceId.webStudio);\n"
    "    expect(find.byKey(const Key('web-studio-runtime-card')), findsOneWidget);\n\n"
    "    await tapKey(tester, const Key('history-back'));\n"
    "    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);\n"
    "    expect(controller.sideEffects.isZero, isTrue);\n"
    "  });\n"
)
nav_text, nav_count = nav_pattern.subn(nav_replacement, nav_text, count=1)
if nav_count != 1:
    raise SystemExit('stale Web Studio navigation contract not found exactly once')
navigation.write_text(nav_text, encoding='utf-8', newline='\n')

text = accessibility.read_text(encoding='utf-8')
old_owner = 'Owner Mode status: Blocked by environment. Presentation only.'
new_owner = 'Owner Mode status: Blocked by environment.'
if text.count(old_owner) != 1:
    raise SystemExit('stale Owner Mode accessibility label not found exactly once')
text = text.replace(old_owner, new_owner, 1)

access_pattern = re.compile(
    r"^    controller\.selectWorkspace\(P5WorkspaceId\.capabilitiesIntegrations\);\n"
    r"    await tester\.pumpAndSettle\(\);\n"
    r"    final webCapability = find\.byKey\(const Key\('capability-webStudio'\)\);\n"
    r"    await tester\.ensureVisible\(webCapability\);\n"
    r"    await tester\.tap\(webCapability\);\n"
    r"    await tester\.pumpAndSettle\(\);\n\n"
    r"    expect\(\n"
    r"      find\.bySemanticsLabel\(\n"
    r"        'Web Studio is BLOCKED_BY_DEPENDENCY\. P3-001 browser runtime is not implemented\.',\n"
    r"      \),\n"
    r"      findsOneWidget,\n"
    r"    \);\n",
    re.MULTILINE,
)
access_replacement = (
    "    controller.selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);\n"
    "    await tester.pumpAndSettle();\n"
    "    expect(\n"
    "      find.bySemanticsLabel(\n"
    "        'Web Studio: EXPERIMENTAL. P3-002 through P3-006B browser sessions, observations, actions, downloads, and uploads are landed and consumable from Experience.',\n"
    "      ),\n"
    "      findsOneWidget,\n"
    "    );\n\n"
    "    final webCapability = find.byKey(const Key('capability-webStudio'));\n"
    "    await tester.ensureVisible(webCapability);\n"
    "    await tester.tap(webCapability);\n"
    "    await tester.pumpAndSettle();\n"
    "    expect(find.byKey(const Key('web-studio-runtime-card')), findsOneWidget);\n"
)
text, access_count = access_pattern.subn(access_replacement, text, count=1)
if access_count != 1:
    raise SystemExit('stale Web Studio accessibility contract not found exactly once')
accessibility.write_text(text, encoding='utf-8', newline='\n')

prototype = ROOT / 'lib/product/p5_information_architecture/p5_prototype.dart'
prototype_text = prototype.read_text(encoding='utf-8')
prototype_anchor = '  P5InformationArchitectureController get controller => widget.controller;\n\n'
prototype_helper = (
    '  P5InformationArchitectureController get controller => widget.controller;\n\n'
    '  void mutatePresentation(VoidCallback update) {\n'
    '    if (!mounted) {\n'
    '      return;\n'
    '    }\n'
    '    setState(update);\n'
    '  }\n\n'
)
if prototype_text.count(prototype_anchor) != 1:
    raise SystemExit('P5 prototype mutation-helper anchor drifted')
prototype.write_text(
    prototype_text.replace(prototype_anchor, prototype_helper, 1),
    encoding='utf-8',
    newline='\n',
)

support = ROOT / 'lib/product/p5_information_architecture/p5_support_workspaces.dart'
support_text = support.read_text(encoding='utf-8')
set_state_count = support_text.count('setState(')
if set_state_count != 20:
    raise SystemExit(f'P5 support setState call count drifted: {set_state_count}')
support_text = support_text.replace('setState(', 'mutatePresentation(')
if 'setState(' in support_text:
    raise SystemExit('P5 support protected setState call remains')
support.write_text(support_text, encoding='utf-8', newline='\n')

print('P5_WEB_STUDIO_FINALIZER_APPLIED')
