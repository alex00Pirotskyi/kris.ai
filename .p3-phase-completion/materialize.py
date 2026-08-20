from pathlib import Path

source_contract = Path('test/product/source_contract_test.dart')
text = source_contract.read_text()
anchor = """        'lib/product/browser/browser_runtime.dart',
        'lib/product/browser/browser_runtime_bundle.dart',
        'lib/product/browser/browser_runtime_process.dart',
        'lib/product/chat_studio.dart',"""
replacement = """        'lib/product/browser/browser_runtime.dart',
        'lib/product/browser/browser_runtime_bundle.dart',
        'lib/product/browser/browser_runtime_process.dart',
        'lib/product/browser/browser_control_plane.dart',
        'lib/product/browser/browser_profile_store.dart',
        'lib/product/browser/browser_replay.dart',
        'lib/product/browser/browser_workspace.dart',
        'lib/product/browser/web_preview.dart',
        'lib/product/browser/web_studio.dart',
        'lib/product/chat_studio.dart',"""
if replacement not in text:
    if anchor not in text:
        raise SystemExit('P3 source-contract anchor missing')
    text = text.replace(anchor, replacement, 1)
source_contract.write_text(text)

workspace = Path('lib/product/browser/browser_workspace.dart')
workspace_text = workspace.read_text()
tooltip_old = """            DropdownButton<P3BrowserViewportPreset>(
              value: controller.viewport,
              tooltip: 'Responsive viewport preset',
              items: P3BrowserViewportPreset.values"""
tooltip_new = """            Tooltip(
              message: 'Responsive viewport preset',
              child: DropdownButton<P3BrowserViewportPreset>(
                value: controller.viewport,
                items: P3BrowserViewportPreset.values"""
if tooltip_old not in workspace_text:
    raise SystemExit('P3 workspace dropdown anchor missing')
workspace_text = workspace_text.replace(tooltip_old, tooltip_new, 1)
dropdown_end_old = """              onChanged: (value) {
                if (value == null) return;
                controller.setViewport(value);
                onViewportPreset?.call(value);
              },
            ),
            IconButton("""
dropdown_end_new = """                onChanged: (value) {
                  if (value == null) return;
                  controller.setViewport(value);
                  onViewportPreset?.call(value);
                },
              ),
            ),
            IconButton("""
if dropdown_end_old not in workspace_text:
    raise SystemExit('P3 workspace dropdown close anchor missing')
workspace_text = workspace_text.replace(dropdown_end_old, dropdown_end_new, 1)
workspace_text = workspace_text.replace(
    'child: Image.memory(bytes!, fit: BoxFit.contain),',
    'child: Image.memory(bytes, fit: BoxFit.contain),',
    1,
)
workspace.write_text(workspace_text)

phase_test = Path('test/product/browser/browser_phase_completion_test.dart')
phase_text = phase_test.read_text()
image_old = "const screenshot = <int>[0xff, 0xd8, 0xff, 0xd9];"
image_new = """final screenshot = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlB+qAAAAAASUVORK5CYII=',
  );"""
if image_old not in phase_text:
    raise SystemExit('P3 workspace test image anchor missing')
phase_text = phase_text.replace(image_old, image_new, 1)
phase_text = phase_text.replace("'mediaType': 'image/jpeg',", "'mediaType': 'image/png',", 1)
assert_old = "expect(find.textContaining('desktop 1440×900'), findsOneWidget);"
assert_new = "expect(find.text('desktop 1440×900'), findsOneWidget);"
if assert_old not in phase_text:
    raise SystemExit('P3 workspace test assertion anchor missing')
phase_text = phase_text.replace(assert_old, assert_new, 1)
phase_test.write_text(phase_text)

required = [
    'lib/product/browser/browser_control_plane.dart',
    'lib/product/browser/browser_profile_store.dart',
    'lib/product/browser/browser_replay.dart',
    'lib/product/browser/browser_workspace.dart',
    'lib/product/browser/web_preview.dart',
    'lib/product/browser/web_studio.dart',
    'test/product/browser/browser_phase_completion_test.dart',
    'test/product/browser/browser_security_suite_test.dart',
    'test/fixtures/p3_browser/index.html',
    'test/fixtures/p3_browser/fixture.js',
    'docs/recipes/P3_BROWSER_TASK_RECIPES.md',
]
for relative in required:
    if not Path(relative).is_file():
        raise SystemExit(f'missing P3 phase file: {relative}')
