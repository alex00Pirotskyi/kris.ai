from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


def replace_span(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{path}: start marker missing')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{path}: end marker missing')
    target.write_text(text[:start] + replacement + text[end:], encoding='utf-8', newline='\n')


models_path = 'lib/product/p5_information_architecture/p5_models.dart'
replace_once(
    models_path,
    "import 'package:flutter/foundation.dart';\n",
    "import 'package:flutter/foundation.dart';\n\nimport '../access_profile_v2.dart';\n",
)
replace_once(
    models_path,
    """extension P5ComposerProfileLabel on P5ComposerProfile {
  String get label => switch (this) {
        P5ComposerProfile.project => 'Project',
        P5ComposerProfile.owner => 'Owner',
        P5ComposerProfile.ownerUnattended => 'Owner unattended',
        P5ComposerProfile.isolatedUntrusted => 'Isolated untrusted',
      };
}
""",
    """extension P5ComposerProfileLabel on P5ComposerProfile {
  String get label => switch (this) {
        P5ComposerProfile.project => 'Project',
        P5ComposerProfile.owner => 'Owner',
        P5ComposerProfile.ownerUnattended => 'Owner unattended',
        P5ComposerProfile.isolatedUntrusted => 'Isolated untrusted',
      };

  AccessProfileId get accessProfileId => switch (this) {
        P5ComposerProfile.project => AccessProfileId.project,
        P5ComposerProfile.owner => AccessProfileId.owner,
        P5ComposerProfile.ownerUnattended => AccessProfileId.ownerUnattended,
        P5ComposerProfile.isolatedUntrusted => AccessProfileId.isolatedUntrusted,
      };

  ApprovalPolicy get approvalPolicy => switch (this) {
        P5ComposerProfile.project => ApprovalPolicy.highRiskOnly,
        P5ComposerProfile.owner => ApprovalPolicy.highRiskOnly,
        P5ComposerProfile.ownerUnattended => ApprovalPolicy.never,
        P5ComposerProfile.isolatedUntrusted => ApprovalPolicy.always,
      };

  String get approvalPolicyLabel => switch (approvalPolicy) {
        ApprovalPolicy.always => 'ALWAYS',
        ApprovalPolicy.highRiskOnly => 'HIGH_RISK_ONLY',
        ApprovalPolicy.never => 'NEVER',
      };

  String get approvalPolicyExplanation => switch (approvalPolicy) {
        ApprovalPolicy.always =>
          'Approval prompts are required by this profile before governed effects proceed.',
        ApprovalPolicy.highRiskOnly =>
          'High-risk effects require approval. Lower-risk effects still require deterministic policy authorization.',
        ApprovalPolicy.never =>
          'No approval prompts are required by this profile. This does not grant capabilities, widen the profile ceiling, or bypass deterministic policy and overlay denials.',
      };
}
""",
)


task_path = 'lib/product/p5_information_architecture/p5_task_workspaces.dart'
plan_function = """  Widget _planCard(BuildContext context) {
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Concise plan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Review intent, authority boundaries, and expected verification before launch.',
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 4),
            const _BoundaryNotice(
              message:
                  'Access profiles are maximum authority ceilings, not capability grants. This plan review does not authorize files, commands, sites, credentials, or runtime effects.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _planReviewSection({
    required Key key,
    required String title,
    required String value,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }

"""
replace_span(
    task_path,
    '  Widget _planCard(BuildContext context) {\n',
    '  Widget _runControlCard(BuildContext context) {\n',
    plan_function,
)


test_path = Path('test/product/p5_information_architecture/p5_plan_review_test.dart')
test_path.write_text(
    """import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/access_profile_v2.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';

Future<void> _pump(
  WidgetTester tester,
  P5InformationArchitectureController controller,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: P5InformationArchitecturePrototype(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('P5-007 profile approval mapping matches governed P1 catalog', () {
    final catalog = jsonDecode(
      File('config/access_profiles.v2.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(catalog['authoritySemantics'], 'maximum_ceiling_not_capability_grant');
    final profiles = <String, String>{};
    for (final raw in catalog['profiles'] as List<dynamic>) {
      final item = raw as Map<String, dynamic>;
      profiles[item['profileId'] as String] = item['approvalPolicy'] as String;
    }

    const expectedIds = <P5ComposerProfile, String>{
      P5ComposerProfile.project: 'project',
      P5ComposerProfile.owner: 'owner',
      P5ComposerProfile.ownerUnattended: 'owner_unattended',
      P5ComposerProfile.isolatedUntrusted: 'isolated_untrusted',
    };
    const expectedPolicies = <ApprovalPolicy, String>{
      ApprovalPolicy.always: 'always',
      ApprovalPolicy.highRiskOnly: 'high_risk_only',
      ApprovalPolicy.never: 'never',
    };

    for (final profile in P5ComposerProfile.values) {
      expect(
        profiles[expectedIds[profile]],
        expectedPolicies[profile.approvalPolicy],
      );
    }
    expect(P5ComposerProfile.ownerUnattended.approvalPolicy, ApprovalPolicy.never);
  });

  testWidgets('P5-007 plan review exposes every governed review field',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..updateComposerAttachments(const <String>['lib/example.dart'])
      ..updateAcceptanceCriteria(const <String>[
        'Requested behavior is verified by tests.',
        'No unexpected side effect is reported.',
      ])
      ..apply(P5PrototypeAction.reviewPlan);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    for (final key in const <String>[
      'p5-plan-goal',
      'p5-plan-files',
      'p5-plan-commands',
      'p5-plan-sites',
      'p5-plan-side-effects',
      'p5-plan-verification',
      'p5-plan-risk',
      'p5-plan-profile',
      'p5-plan-approval-policy',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.textContaining('NOT_EVALUATED'), findsOneWidget);
    expect(find.textContaining('0 filesystem'), findsOneWidget);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('P5-007 Owner unattended never policy is represented accurately',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..updateComposerProfile(P5ComposerProfile.ownerUnattended)
      ..apply(P5PrototypeAction.reviewPlan);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('Approval policy: NEVER'), findsOneWidget);
    expect(
      find.textContaining('No approval prompts are required by this profile'),
      findsOneWidget,
    );
    expect(find.textContaining('does not grant capabilities'), findsOneWidget);
    expect(find.textContaining('maximum authority ceilings'), findsOneWidget);
    expect(controller.sideEffects.isZero, isTrue);
  });

  testWidgets('P5-007 plan review never fabricates commands sites or low risk',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..apply(P5PrototypeAction.reviewPlan);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.textContaining('None compiled in P5 presentation mode'), findsOneWidget);
    expect(find.textContaining('None declared in this composer'), findsOneWidget);
    expect(find.textContaining('Do not interpret presentation mode as low risk'), findsOneWidget);
    expect(find.textContaining('No command authority is implied'), findsOneWidget);
  });
}
""",
    encoding='utf-8',
    newline='\n',
)

print('P5_007_PLAN_REVIEW_PATCH_APPLIED')
