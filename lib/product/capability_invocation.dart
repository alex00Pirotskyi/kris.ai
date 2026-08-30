import 'chat_control_plane.dart';
import 'domain.dart';
import 'storage_security.dart';

/// Canonical description of one capability request before authority is
/// resolved. Model-produced capabilities are proposals only; requested scopes
/// are validated against deterministic capability policy below.
class CapabilityInvocation {
  const CapabilityInvocation({
    required this.capabilityId,
    this.targetIds = const <String>{},
    this.requestedScopes = const <PermissionScope>{},
    this.modelProposed = false,
    this.reason = '',
  });

  final String capabilityId;
  final Set<String> targetIds;
  final Set<PermissionScope> requestedScopes;
  final bool modelProposed;
  final String reason;
}

class CapabilityAuthorityDecision {
  const CapabilityAuthorityDecision({
    required this.invocation,
    required this.capability,
    required this.requiredScopes,
  });

  final CapabilityInvocation invocation;
  final KristinCapability capability;
  final Set<PermissionScope> requiredScopes;
}

/// One deterministic authority resolver shared by explicit slash commands,
/// natural-language routing and model-authored task capability requirements.
/// It computes the permission envelope; it never grants it.
class CapabilityAuthorityResolver {
  const CapabilityAuthorityResolver({
    this.registry = const ChatCapabilityRegistry(),
  });

  final ChatCapabilityRegistry registry;

  CapabilityAuthorityDecision resolve(CapabilityInvocation invocation) {
    final capability = registry.byId(invocation.capabilityId);
    if (capability == null) {
      throw ProductException(
        'capability_unknown',
        'Unknown Kristin capability: ${invocation.capabilityId}',
      );
    }
    if (capability.isCoordinatorCapability && invocation.modelProposed) {
      throw ProductException(
        'capability_coordinator_not_executable',
        '${capability.id} is a coordinator capability and cannot be granted to an execution model.',
      );
    }
    if (capability.route == ChatExecutionRoute.ownerMode && invocation.modelProposed) {
      throw ProductException(
        'owner_full_host_not_implemented',
        'This release does not implement unrestricted full-host Owner authority. Owner Mode may be inspected, but an execution model cannot be granted full-host control.',
      );
    }

    final required = _requiredScopes(capability);
    if (!required.containsAll(invocation.requestedScopes)) {
      final extra = invocation.requestedScopes.difference(required).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      throw ProductException(
        'capability_scope_escalation',
        'The capability request includes authority not implied by ${capability.id}.',
        details: <String, dynamic>{
          'extraScopes': extra.map((scope) => scope.name).toList(),
          'requiredScopes': required.map((scope) => scope.name).toList()..sort(),
        },
      );
    }
    return CapabilityAuthorityDecision(
      invocation: invocation,
      capability: capability,
      requiredScopes: Set<PermissionScope>.unmodifiable(required),
    );
  }

  Set<PermissionScope> _requiredScopes(KristinCapability capability) {
    final scopes = <PermissionScope>{};
    if (capability.riskClass == ChatRiskClass.readOnly) {
      scopes.add(PermissionScope.projectRead);
    } else if (capability.riskClass == ChatRiskClass.execution) {
      scopes.addAll(const <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.executeFinite,
      });
    } else if (capability.riskClass == ChatRiskClass.mutation) {
      scopes.addAll(const <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
      });
    } else if (capability.riskClass == ChatRiskClass.sensitive) {
      scopes.add(PermissionScope.secretUse);
    } else if (capability.riskClass == ChatRiskClass.destructive) {
      scopes.addAll(const <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
        PermissionScope.projectDelete,
      });
    }

    if (capability.route == ChatExecutionRoute.researchSearch) {
      scopes
        ..remove(PermissionScope.projectRead)
        ..add(PermissionScope.networkResearch);
    } else if (const <ChatExecutionRoute>{
      ChatExecutionRoute.projectRun,
      ChatExecutionRoute.projectStop,
      ChatExecutionRoute.projectRestart,
    }.contains(capability.route)) {
      scopes
        ..remove(PermissionScope.executeFinite)
        ..add(PermissionScope.executeManaged);
    } else if (capability.route == ChatExecutionRoute.connectProvider) {
      scopes.add(PermissionScope.secretUse);
    }
    return scopes;
  }
}
