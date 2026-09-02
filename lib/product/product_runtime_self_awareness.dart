import 'dart:io';

import 'chat_control_plane.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'self_awareness/capability_self_model.dart';

final class RuntimeCapabilityProvider implements KristinCapabilityProvider {
  const RuntimeCapabilityProvider({
    required this.providerId,
    required this.descriptors,
    required this.resolver,
  });

  @override
  final String providerId;
  final List<CapabilityDescriptor> descriptors;
  final Future<CapabilityAvailability> Function(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) resolver;

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => descriptors;

  @override
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) => resolver(descriptor, snapshot);
}

/// Authoritative bounded snapshot adapter for ProductRuntime.
///
/// Selection is supplied by Chat because project selection is UI/session state;
/// projects, Browser and Owner status come from their canonical runtime owners.
final class ProductRuntimeSnapshotProvider implements ApplicationSnapshotProvider {
  const ProductRuntimeSnapshotProvider({
    required this.runtime,
    this.selectedProject,
    this.selectedModel,
    this.maxProjects = 20,
    this.maxRuns = 10,
  });

  final ProductRuntime runtime;
  final ProjectRecord? selectedProject;
  final ModelIdentity? selectedModel;
  final int maxProjects;
  final int maxRuns;

  @override
  Future<ApplicationSnapshot> capture() async {
    final projects = await runtime.listProjects();
    final boundedProjects = projects.take(maxProjects).map((project) =>
        <String, Object?>{
          'id': project.id,
          'name': project.name,
          'rootPath': project.rootPath,
          'updatedAt': project.updatedAt.toIso8601String(),
        }).toList(growable: false);

    final runs = await runtime.repositories.runs.all();
    runs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final runState = <String, Object?>{
      'recent': runs.take(maxRuns).map((run) => <String, Object?>{
        'id': run.id,
        'status': run.status.name,
        'projectId': run.command.contract.projectId,
        'updatedAt': run.updatedAt.toIso8601String(),
      }).toList(growable: false),
    };

    final browser = runtime.p3BrowserRuntime;
    final owner = runtime.p2OwnerMode;
    return ApplicationSnapshot(
      capturedAt: DateTime.now().toUtc(),
      applicationIdentity: 'kris.ai',
      platform: Platform.operatingSystem,
      build: <String, Object?>{
        'runtime': Platform.version,
      },
      health: <String, Object?>{
        'runtimeOpen': true,
      },
      selectedProject: selectedProject == null
          ? null
          : <String, Object?>{
              'id': selectedProject!.id,
              'name': selectedProject!.name,
              'rootPath': selectedProject!.rootPath,
            },
      knownProjects: boundedProjects,
      selectedModel: selectedModel == null
          ? null
          : <String, Object?>{
              'providerId': selectedModel!.providerId,
              'name': selectedModel!.name,
              'digest': selectedModel!.digest,
            },
      availableModels: selectedModel == null
          ? const <Map<String, Object?>>[]
          : <Map<String, Object?>>[
              <String, Object?>{
                'providerId': selectedModel!.providerId,
                'name': selectedModel!.name,
                'digest': selectedModel!.digest,
                'selected': true,
              },
            ],
      providers: selectedModel == null
          ? const <Map<String, Object?>>[]
          : <Map<String, Object?>>[
              <String, Object?>{
                'id': selectedModel!.providerId,
                'connectedForSelectedModel': true,
              },
            ],
      runState: runState,
      authority: <String, Object?>{
        'ownerCompletionEligible': owner.completionEligible,
        'ownerSecureIsolationActive': owner.secureIsolationActive,
        // This is deliberately not a claim that Owner authority is granted
        // to any particular run. Per-run grants remain in the authority layer.
        'granted': const <String>[],
      },
      ownerMode: <String, Object?>{
        'available': owner.available,
        'completionEligible': owner.completionEligible,
        'secureIsolationActive': owner.secureIsolationActive,
        'diagnosticCode': owner.diagnosticCode,
        'provenance': owner.runtimeProvenance,
      },
      browser: <String, Object?>{
        'available': browser.available,
        'statusCode': browser.statusCode,
        'provenance': browser.provenance,
      },
      research: <String, Object?>{
        'service': runtime.research.runtimeType.toString(),
      },
    );
  }
}

KristinCapabilityRegistry buildProductCapabilityRegistry(ProductRuntime runtime) {
  final registry = KristinCapabilityRegistry();
  registry.register(ChatCapabilityProvider(
    availabilityResolver: (capability, descriptor, snapshot) async {
      if (descriptor.projectRequired && snapshot.selectedProject == null) {
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.projectRequired,
          reasons: const <String>['No project is selected for this session.'],
          missingPrerequisites: const <String>{'selectedProject'},
          observedAt: snapshot.capturedAt,
        );
      }
      if (descriptor.modelProviderRequired && snapshot.selectedModel == null) {
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.modelProviderMissing,
          reasons: const <String>['No model/provider is selected for substantial planning.'],
          missingPrerequisites: const <String>{'selectedModel'},
          observedAt: snapshot.capturedAt,
        );
      }
      if (capability.route == ChatExecutionRoute.ownerMode) {
        final available = snapshot.ownerMode['available'] == true;
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: available
              ? CapabilityAvailabilityState.approvalRequired
              : CapabilityAvailabilityState.ownerAuthorityUnavailable,
          reasons: <String>[
            available
                ? 'Owner Mode exists, but Owner authority is not automatically granted to this work item.'
                : 'Owner Mode runtime is unavailable: ${snapshot.ownerMode['diagnosticCode']}.',
          ],
          requiredAuthority: const <String>{'owner'},
          observedAt: snapshot.capturedAt,
        );
      }
      return CapabilityAvailability(
        capabilityId: descriptor.id,
        state: CapabilityAvailabilityState.available,
        reasons: const <String>['Runtime prerequisites are currently satisfied.'],
        observedAt: snapshot.capturedAt,
      );
    },
  ));

  registry.register(RuntimeCapabilityProvider(
    providerId: 'browser.runtime',
    descriptors: const <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'browser.navigate',
        name: 'Browser navigation',
        description: 'Open and inspect a public web page using the provisioned application-owned Browser runtime.',
        semanticPurpose: 'Rendered-page observation for governed browsing/research flows.',
        category: 'connections',
        acceptedTargets: <String>{'url'},
        riskClass: CapabilityRiskClass.readOnly,
        readOnly: true,
        networkRequired: true,
        browserRequired: true,
        directlyExecutable: false,
        recoveryParticipant: true,
        limitations: <String>['Availability depends on the packaged/provisioned Browser runtime.'],
        providerId: 'browser.runtime',
      ),
    ],
    resolver: (descriptor, snapshot) async => CapabilityAvailability(
      capabilityId: descriptor.id,
      state: snapshot.browser['available'] == true
          ? CapabilityAvailabilityState.available
          : CapabilityAvailabilityState.browserUnavailable,
      reasons: <String>[
        snapshot.browser['available'] == true
            ? 'The application-owned Browser runtime is provisioned.'
            : 'Browser runtime unavailable: ${snapshot.browser['statusCode']}.',
      ],
      observedAt: snapshot.capturedAt,
    ),
  ));

  registry.register(RuntimeCapabilityProvider(
    providerId: 'owner.recovery',
    descriptors: const <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'owner.recovery.actuate',
        name: 'Owner recovery actuator',
        description: 'Perform explicitly-authorized host-level recovery effects through Owner Mode.',
        semanticPurpose: 'Controlled L1-L4 repair actuator; capability knowledge never grants its authority.',
        category: 'system',
        riskClass: CapabilityRiskClass.sensitive,
        readOnly: false,
        mutatesHostState: true,
        authorityClass: CapabilityAuthorityClass.owner,
        permissionRequirements: <String>{'owner'},
        filesystemRequired: true,
        processRequired: true,
        directlyExecutable: false,
        recoveryParticipant: true,
        limitations: <String>['Every effect remains subject to Owner Mode authority and approval policy.'],
        providerId: 'owner.recovery',
      ),
    ],
    resolver: (descriptor, snapshot) async {
      final available = snapshot.ownerMode['available'] == true;
      final eligible = snapshot.ownerMode['completionEligible'] == true;
      return CapabilityAvailability(
        capabilityId: descriptor.id,
        state: !available
            ? CapabilityAvailabilityState.ownerAuthorityUnavailable
            : eligible
                ? CapabilityAvailabilityState.approvalRequired
                : CapabilityAvailabilityState.additionalAuthorityRequired,
        reasons: <String>[
          if (!available) 'Owner Mode runtime is unavailable.'
          else if (!eligible) 'Owner Mode exists but its isolated authority service is not completion-eligible.'
          else 'Owner recovery is available but requires an explicit per-operation authority grant.',
        ],
        requiredAuthority: const <String>{'owner'},
        observedAt: snapshot.capturedAt,
      );
    },
  ));
  return registry;
}

/// Product composition entry point. Callers supply session selection so the
/// same runtime can produce truthful snapshots for different conversations.
KristinSelfModelService buildProductSelfModel(
  ProductRuntime runtime, {
  ProjectRecord? selectedProject,
  ModelIdentity? selectedModel,
}) =>
    KristinSelfModelService(
      registry: buildProductCapabilityRegistry(runtime),
      application: ProductRuntimeSnapshotProvider(
        runtime: runtime,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      ),
    );
