import 'dart:io';

import 'process_identity_linux.dart';
import 'process_identity_windows.dart';

/// Result of comparing a durable [ProjectRuntimeSession]'s recorded process
/// identity against what the OS reports right now for the same pid.
///
/// [unverifiablePlatform] is returned whenever this platform (macOS in Wave
/// A) or this process cannot be inspected at all — it is never treated the
/// same as [alive]. A recovered session that cannot be verified is
/// reconciled as interrupted rather than trusted, per the project's
/// fail-closed process-identity policy: a bare PID is never enough on its
/// own to resume "this is still my process."
enum ProcessIdentityVerification {
  alive,
  mismatchOrGone,
  unverifiablePlatform,
}

/// Captures and verifies PID-reuse-safe process identity across platforms.
/// Linux and Windows are backed by real OS-level checks
/// (`process_identity_linux.dart`, `process_identity_windows.dart`); macOS
/// has no reader in Wave A and always reports
/// [ProcessIdentityVerification.unverifiablePlatform].
class ProcessIdentityProbe {
  const ProcessIdentityProbe();

  /// Captures an identity token for [pid] on the current platform, to be
  /// stored alongside a durable [ProjectRuntimeSession] at start time. Null
  /// when this platform has no reader or the process could not be
  /// inspected.
  Future<String?> capture(int pid) async {
    if (Platform.isLinux) {
      return (await readLinuxProcessIdentity(pid))?.token;
    }
    if (Platform.isWindows) {
      return readWindowsProcessIdentity(pid)?.token;
    }
    return null;
  }

  /// Re-derives the current identity for [pid] and compares it against
  /// [expectedToken] recorded when the session started. Used on restart
  /// recovery: only [ProcessIdentityVerification.alive] justifies
  /// reattaching to the process as still running.
  Future<ProcessIdentityVerification> verify(
    int pid,
    String? expectedToken,
  ) async {
    if (expectedToken == null || expectedToken.isEmpty) {
      return ProcessIdentityVerification.unverifiablePlatform;
    }
    if (Platform.isLinux) {
      final identity = await readLinuxProcessIdentity(pid);
      if (identity == null || identity.isZombie) {
        return ProcessIdentityVerification.mismatchOrGone;
      }
      return identity.token == expectedToken
          ? ProcessIdentityVerification.alive
          : ProcessIdentityVerification.mismatchOrGone;
    }
    if (Platform.isWindows) {
      final identity = readWindowsProcessIdentity(pid);
      if (identity == null) {
        return ProcessIdentityVerification.mismatchOrGone;
      }
      return identity.token == expectedToken
          ? ProcessIdentityVerification.alive
          : ProcessIdentityVerification.mismatchOrGone;
    }
    return ProcessIdentityVerification.unverifiablePlatform;
  }
}
