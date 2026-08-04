import 'dart:convert';

import 'generated/v190_contracts.g.dart';
import 'release_operations_v19.dart';

const String interoperabilityV19Version = '1.9.0+190';
const String interoperabilityV19SchemaVersion = '1.0.0';
const String interoperabilityV19ContractDigest = v190ContractsSha256;

class SignedManifestEnvelope {
  const SignedManifestEnvelope({
    required this.manifestType,
    required this.manifest,
    required this.manifestSha256,
    required this.signature,
    required this.signerKeyId,
    required this.signerPublicKey,
    required this.signedAt,
  });

  final String manifestType;
  final Map<String, dynamic> manifest;
  final String manifestSha256;
  final String signature;
  final String signerKeyId;
  final String signerPublicKey;
  final DateTime signedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': interoperabilityV19SchemaVersion,
        'manifestType': manifestType,
        'manifest': manifest,
        'manifestSha256': manifestSha256,
        'signature': signature,
        'signedAt': signedAt.toUtc().toIso8601String(),
        'signer': <String, String>{
          'keyId': signerKeyId,
          'algorithm': 'Ed25519',
          'publicKey': signerPublicKey,
        },
      };
}

class CapabilityManifest {
  const CapabilityManifest({
    required this.kind,
    required this.id,
    required this.title,
    required this.capabilities,
    required this.dataBoundary,
    required this.approvalPolicy,
  });

  final String kind;
  final String id;
  final String title;
  final List<String> capabilities;
  final String dataBoundary;
  final String approvalPolicy;
}

class McpServerDescriptor {
  const McpServerDescriptor({
    required this.id,
    required this.label,
    required this.allowedTools,
    required this.allowedResources,
    required this.allowedPrompts,
    required this.roots,
  });

  final String id;
  final String label;
  final List<String> allowedTools;
  final List<String> allowedResources;
  final List<String> allowedPrompts;
  final List<String> roots;
}

class McpLifecycleController {
  const McpLifecycleController();

  Map<String, dynamic> negotiate(McpServerDescriptor descriptor) =>
      <String, dynamic>{
        'serverId': descriptor.id,
        'roots': descriptor.roots,
        'tools': descriptor.allowedTools,
        'resources': descriptor.allowedResources,
        'prompts': descriptor.allowedPrompts,
        'contractDigest': interoperabilityV19ContractDigest,
      };
}

class A2ATaskContractV19 {
  const A2ATaskContractV19({
    required this.taskId,
    required this.allowedCapabilities,
    required this.expectedArtifacts,
    required this.maxSteps,
  });

  final String taskId;
  final List<String> allowedCapabilities;
  final List<String> expectedArtifacts;
  final int maxSteps;
}

class A2ADelegationController {
  const A2ADelegationController();

  Map<String, dynamic> prepare(A2ATaskContractV19 contract) =>
      <String, dynamic>{
        'taskId': contract.taskId,
        'allowedCapabilities': contract.allowedCapabilities,
        'expectedArtifacts': contract.expectedArtifacts,
        'maxSteps': contract.maxSteps,
      };
}

class AuditChain {
  const AuditChain({required this.headSha256, required this.recordCount});

  final String headSha256;
  final int recordCount;

  AuditVerificationResultV19 verify() => AuditVerificationResultV19(
        verified: headSha256.isNotEmpty && recordCount >= 0,
        recordCount: recordCount,
      );
}

class UpdatePolicyVerifier {
  const UpdatePolicyVerifier({required this.policy});

  final SupportLifecyclePolicyV19 policy;

  bool allowsChannel(String channel) =>
      policy.currentVersion.isNotEmpty &&
      policy.minimumSupportedUpgradeFrom.isNotEmpty &&
      channel.isNotEmpty;
}

bool hasInteroperabilityContract(String name) =>
    v190ContractSchemas.containsKey(name);

String encodeSignedManifest(SignedManifestEnvelope envelope) =>
    const JsonEncoder.withIndent('  ').convert(envelope.toJson());
