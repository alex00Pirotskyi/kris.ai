from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'expected one P5-006 reachability anchor in {path}, found {count}: {old!r}'
        )
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


task_path = 'lib/product/p5_information_architecture/p5_task_workspaces.dart'

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
    """                      if (state.runState !=
                              P5RunPresentationState.completed ||
                          state.selectedRunId == null)
                        FilledButton.icon(
                          key: const Key('review-plan-button'),
                          onPressed: controller.canReviewPlan
                              ? () => controller.apply(
                                    P5PrototypeAction.reviewPlan,
                                  )
                              : null,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Review concise plan'),
                        ),
""",
)

replace_once(
    task_path,
    """                  if (state.runState ==
                      P5RunPresentationState.completed) ...<Widget>[
                    FilledButton.tonalIcon(
                      key: const Key('open-evidence-button'),
""",
    """                  if (state.runState ==
                      P5RunPresentationState.completed) ...<Widget>[
                    if (state.selectedRunId != null)
                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        onPressed: controller.canReviewPlan
                            ? () => controller.apply(
                                  P5PrototypeAction.reviewPlan,
                                )
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Review new plan'),
                      ),
                    FilledButton.tonalIcon(
                      key: const Key('open-evidence-button'),
""",
)

print('P5_006_REACHABILITY_FIX_APPLIED')
