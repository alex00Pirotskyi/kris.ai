from pathlib import Path

path = Path('lib/product/p5_information_architecture/p5_task_workspaces.dart')
text = path.read_text(encoding='utf-8')
start_marker = '  Widget _planCard(BuildContext context) {\n'
end_marker = '  Widget _planReviewSection({\n'
start = text.find(start_marker)
if start < 0:
    raise SystemExit('P5-007 plan card start marker missing')
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit('P5-007 plan review section marker missing')
replacement = """  Widget _planCard(BuildContext context) {
    final state = controller.state;
    final sideEffects = controller.sideEffects;
    final profile = state.composerProfile;
    final attachments = state.attachments.isEmpty
        ? 'None declared.'
        : state.attachments.join(', ');
    final verification = state.acceptanceCriteria.isEmpty
        ? 'No acceptance criteria declared.'
        : state.acceptanceCriteria.join(' • ');
    return Card(
      key: const Key('concise-plan-card'),
      child: SizedBox(
        height: 210,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Concise plan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              const Text(
                'Review intent, authority boundaries, and verification before launch.',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    key: const Key('p5-plan-review-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _planReviewSection(
                          key: const Key('p5-plan-goal'),
                          title: 'Goal',
                          value: state.taskDraft,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-files'),
                          title: 'Files / attachments',
                          value: attachments,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-commands'),
                          title: 'Commands',
                          value:
                              'None compiled in P5 presentation mode. No command authority is implied.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-sites'),
                          title: 'Sites',
                          value:
                              'None declared in this composer. Browser/network authority is not inferred.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-side-effects'),
                          title: 'Side effects',
                          value:
                              '${sideEffects.filesystemMutations} filesystem, ${sideEffects.networkRequests} network, ${sideEffects.runtimeCommands} runtime, ${sideEffects.ownerModeActions} Owner Mode, ${sideEffects.deviceRequests} device effects executed.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-verification'),
                          title: 'Verification',
                          value: verification,
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-risk'),
                          title: 'Risk',
                          value:
                              'NOT_EVALUATED — no deterministic effect plan has been compiled. Do not interpret presentation mode as low risk.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-profile'),
                          title: 'Profile and access intent',
                          value:
                              '${profile.label} • access request: ${state.composerAccess.label} • model intent: ${state.composerModel.label} • budget: ${state.composerBudget.label} • timing: ${state.composerLaunchTiming.label}.',
                        ),
                        _planReviewSection(
                          key: const Key('p5-plan-approval-policy'),
                          title: 'Approval policy: ${profile.approvalPolicyLabel}',
                          value: profile.approvalPolicyExplanation,
                        ),
                        const _BoundaryNotice(
                          message:
                              'Access profiles are maximum authority ceilings, not capability grants. This plan review does not authorize files, commands, sites, credentials, or runtime effects.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

"""
path.write_text(text[:start] + replacement + text[end:], encoding='utf-8', newline='\n')
print('P5_007_LAYOUT_FIX_APPLIED')
