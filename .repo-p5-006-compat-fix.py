from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one P5-006 compatibility anchor in {path}, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


task_path = 'lib/product/p5_information_architecture/p5_task_workspaces.dart'
replace_once(
    task_path,
    """                      FilledButton.tonalIcon(
                        key: const Key('review-plan-button'),
""",
    """                      FilledButton.icon(
                        key: const Key('review-plan-button'),
""",
)
replace_once(
    task_path,
    """                      FilledButton.icon(
                        key: const Key('start-run-button'),
""",
    """                      OutlinedButton.icon(
                        key: const Key('start-run-button'),
""",
)
replace_once(
    task_path,
    """                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        onPressed: controller.canReviewPlan
                            ? () =>
                                controller.apply(P5PrototypeAction.reviewPlan)
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review concise plan'),
                      ),
""",
    """                      Shortcuts(
                        shortcuts: const <ShortcutActivator, Intent>{
                          SingleActivator(LogicalKeyboardKey.enter):
                              _P5ReviewPlanIntent(),
                        },
                        child: Actions(
                          actions: <Type, Action<Intent>>{
                            _P5ReviewPlanIntent:
                                CallbackAction<_P5ReviewPlanIntent>(
                              onInvoke: (_) {
                                controller.apply(P5PrototypeAction.reviewPlan);
                                return null;
                              },
                            ),
                          },
                          child: FilledButton.icon(
                            key: const Key('review-plan-button'),
                            onPressed: controller.canReviewPlan
                                ? () => controller
                                    .apply(P5PrototypeAction.reviewPlan)
                                : null,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Review concise plan'),
                          ),
                        ),
                      ),
""",
)

replace_once(
    'lib/product/p5_information_architecture/p5_controller.dart',
    "  bool get canLaunchComposer => !_runLifecycleLocked;\n",
    """  bool get canLaunchComposer =>
      !_runLifecycleLocked && _state.selectedRunId == null;
""",
)

replace_once(
    'lib/product/p5_information_architecture/p5_components.dart',
    """class _P5LaunchComposerIntent extends Intent {
  const _P5LaunchComposerIntent();
}
""",
    """class _P5ReviewPlanIntent extends Intent {
  const _P5ReviewPlanIntent();
}

class _P5LaunchComposerIntent extends Intent {
  const _P5LaunchComposerIntent();
}
""",
)

print('P5_006_COMPAT_FIX_APPLIED')
