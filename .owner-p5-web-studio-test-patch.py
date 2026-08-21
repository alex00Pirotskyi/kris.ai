from pathlib import Path

navigation_path = Path(
    'test/product/p5_information_architecture/p5_navigation_test.dart'
)
navigation = navigation_path.read_text(encoding='utf-8')
old_navigation = """  testWidgets('Web Studio unavailable state has an exit', (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);
    await tapKey(tester, const Key('capability-webStudio'));
    expect(find.text('BLOCKED_BY_DEPENDENCY'), findsOneWidget);
    await tester.tap(find.text('Back to Capabilities'));
    await tester.pumpAndSettle();
    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);
    expect(controller.sideEffects.isZero, isTrue);
  });
"""
new_navigation = """  testWidgets('Web Studio experimental runtime has a governed exit',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.capabilitiesIntegrations);
    addTearDown(controller.dispose);
    await pumpPrototype(tester, controller);

    expect(find.text('EXPERIMENTAL'), findsOneWidget);
    await tapKey(tester, const Key('capability-webStudio'));
    expect(find.byKey(const Key('web-studio-runtime-card')), findsOneWidget);

    await tapKey(tester, const Key('history-back'));
    expect(controller.state.workspace, P5WorkspaceId.capabilitiesIntegrations);
    expect(controller.sideEffects.isZero, isTrue);
  });
"""
if navigation.count(old_navigation) != 1:
    raise SystemExit('P5 navigation truth-update anchor mismatch')
navigation_path.write_text(
    navigation.replace(old_navigation, new_navigation),
    encoding='utf-8',
)

accessibility_path = Path(
    'test/product/p5_information_architecture/p5_accessibility_test.dart'
)
accessibility = accessibility_path.read_text(encoding='utf-8')
old_owner = """      find.bySemanticsLabel(
        'Owner Mode status: Blocked by environment. Presentation only.',
      ),
"""
new_owner = """      find.bySemanticsLabel(
        'Owner Mode status: Blocked by environment.',
      ),
"""
if accessibility.count(old_owner) != 1:
    raise SystemExit('P5 owner semantics anchor mismatch')
accessibility = accessibility.replace(old_owner, new_owner)

old_web = """    expect(
      find.bySemanticsLabel(
        'Web Studio is BLOCKED_BY_DEPENDENCY. P3-001 browser runtime is not implemented.',
      ),
      findsOneWidget,
    );
"""
new_web = """    expect(
      find.bySemanticsLabel(
        'Web Studio: EXPERIMENTAL. P3-002 through P3-006B browser sessions, observations, actions, downloads, and uploads are landed and consumable from Experience.',
      ),
      findsOneWidget,
    );
"""
if accessibility.count(old_web) != 1:
    raise SystemExit('P5 Web Studio semantics anchor mismatch')
accessibility_path.write_text(
    accessibility.replace(old_web, new_web),
    encoding='utf-8',
)
