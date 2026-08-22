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
""",
    """                      FilledButton.icon(
                        key: const Key('review-plan-button'),
                        focusNode: _reviewPlanFocusNode,
                        onPressed: controller.canReviewPlan
""",
)

replace_once(
    'lib/product/p5_information_architecture/p5_controller.dart',
    "  bool get canLaunchComposer => !_runLifecycleLocked;\n",
    """  bool get canLaunchComposer =>
      !_runLifecycleLocked && _state.selectedRunId == null;
""",
)

prototype_path = 'lib/product/p5_information_architecture/p5_prototype.dart'
replace_once(
    prototype_path,
    """  late final TextEditingController _composerCriteriaController =
      TextEditingController(
    text: widget.controller.state.acceptanceCriteria.join('\\n'),
  );
  final TextEditingController _webProfileController =
""",
    """  late final TextEditingController _composerCriteriaController =
      TextEditingController(
    text: widget.controller.state.acceptanceCriteria.join('\\n'),
  );
  late final FocusNode _reviewPlanFocusNode;
  final TextEditingController _webProfileController =
""",
)
replace_once(
    prototype_path,
    """  void initState() {
    super.initState();
    widget.globalAutonomy?.registerBrowserEmergencyStop(
""",
    """  void initState() {
    super.initState();
    _reviewPlanFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            controller.canReviewPlan) {
          controller.apply(P5PrototypeAction.reviewPlan);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    widget.globalAutonomy?.registerBrowserEmergencyStop(
""",
)
replace_once(
    prototype_path,
    """    _composerAttachmentsController.dispose();
    _composerCriteriaController.dispose();
    _webProfileController.dispose();
""",
    """    _composerAttachmentsController.dispose();
    _composerCriteriaController.dispose();
    _reviewPlanFocusNode.dispose();
    _webProfileController.dispose();
""",
)

print('P5_006_COMPAT_FIX_APPLIED')
