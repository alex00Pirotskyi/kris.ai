from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


replace_once(
    'lib/product/ui.dart',
    """    switch (command.actionKind) {
      case P5CommandActionKind.shellDestination:
        _selectDestination(command.shellIndex!);
      case P5CommandActionKind.experienceWorkspace:
        _selectDestination(1);
        _experienceController.selectWorkspace(command.workspace!);
      case P5CommandActionKind.launchExperienceTask:
        _selectDestination(1);
        _experienceController.selectWorkspace(P5WorkspaceId.homeChat);
        _experienceController.launchComposer();
    }
""",
    """    switch (command.actionKind) {
      case P5CommandActionKind.shellDestination:
        _selectDestination(command.shellIndex!);
        return;
      case P5CommandActionKind.experienceWorkspace:
        _selectDestination(1);
        _experienceController.selectWorkspace(command.workspace!);
        return;
      case P5CommandActionKind.launchExperienceTask:
        _selectDestination(1);
        _experienceController.selectWorkspace(P5WorkspaceId.homeChat);
        _experienceController.launchComposer();
        return;
    }
""",
)
replace_once(
    'test/product/p5_command_palette_test.dart',
    "find.byKey(const Key('p5-global-emergency'))",
    "find.byKey(const Key('p5-global-kill'))",
)
