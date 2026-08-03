import 'p2_automation_host.dart';
import 'p2_effect_boundary.dart';
import 'p2_filesystem_service.dart';
import 'p2_host_operations.dart';

/// Desktop-side authorization adapter for effects executed in the trusted
/// desktop process rather than in the automation worker.
///
/// The adapter does not invent authority. It asks the P1-backed envelope
/// authority to consume a grant use before the effect and then validates the
/// exact signed/authenticated authorization envelope. The envelope is not sent
/// to a worker because the filesystem operation is performed locally.
final class P2DesktopFilesystemAuthorizer implements P2FilesystemAuthorizer {
  const P2DesktopFilesystemAuthorizer(this.authority);

  final P2AutomationEnvelopeAuthority authority;

  @override
  Future<Map<String, Object?>> authorize(
    P2EffectBinding binding,
    String operation,
    String target,
  ) async {
    final exactOperation = operation.startsWith('filesystem.')
        ? operation
        : 'filesystem.$operation';
    if (binding.operation != exactOperation) {
      throw StateError('filesystem_authorization_operation_mismatch');
    }
    final envelope = await authority.issue(
      binding: binding,
      operation: exactOperation,
      payload: <String, Object?>{
        'operation': exactOperation,
        'target': target,
        'contentLogged': false,
      },
    );
    envelope.validate();
    return <String, Object?>{
      'status': 'allow',
      'requestId': envelope.requestId,
      'grantId': envelope.grantProof.grantId,
      'grantDigest': envelope.grantProof.grantDigest,
      'useNumber': envelope.grantProof.useNumber,
      'target': target,
    };
  }
}

/// Desktop-side authorization adapter for snapshot/undo and other local host
/// operations. Grant use is durably consumed by the P1 desktop authority before
/// the local effect begins.
final class P2DesktopHostOperationAuthorizer
    implements P2HostOperationAuthorizer {
  const P2DesktopHostOperationAuthorizer(this.authority);

  final P2AutomationEnvelopeAuthority authority;

  @override
  Future<void> authorize(
    P2EffectBinding binding,
    String operation,
    Map<String, Object?> scope,
  ) async {
    if (binding.operation != operation) {
      throw StateError('host_authorization_operation_mismatch');
    }
    final envelope = await authority.issue(
      binding: binding,
      operation: operation,
      payload: <String, Object?>{
        'operation': operation,
        'scope': scope,
      },
    );
    envelope.validate();
  }
}
