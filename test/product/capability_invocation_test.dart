import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_invocation.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  test('research compiles to network authority without a project read grant', () {
    final decision = const CapabilityAuthorityResolver().resolve(
      const CapabilityInvocation(capabilityId: 'research.search'),
    );
    expect(decision.requiredScopes, contains(PermissionScope.networkResearch));
    expect(
      decision.requiredScopes,
      isNot(contains(PermissionScope.projectRead)),
    );
  });

  test('model cannot turn create-project coordinator capability into executor authority', () {
    expect(
      () => const CapabilityAuthorityResolver().resolve(
        const CapabilityInvocation(
          capabilityId: 'agent.create_project',
          modelProposed: true,
        ),
      ),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'capability_coordinator_not_executable',
        ),
      ),
    );
  });

  test('model cannot receive full-host Owner authority in this release', () {
    expect(
      () => const CapabilityAuthorityResolver().resolve(
        const CapabilityInvocation(
          capabilityId: 'owner.mode',
          modelProposed: true,
        ),
      ),
      throwsA(
        isA<ProductException>().having(
          (error) => error.code,
          'code',
          'owner_full_host_not_implemented',
        ),
      ),
    );
  });
}
