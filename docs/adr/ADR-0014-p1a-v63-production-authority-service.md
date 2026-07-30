# ADR-0014 — Production tri-platform P1 authority service V63

Status: proposed source candidate; acceptance requires exact controlled-runner evidence.

V63 retains the P1A/P2 governance split. P1A owns the isolated authority service, platform connector, restricted-worker launcher contract, platform installer, non-exportable permit key, durable grant/replay state, and signed audit integration. P2 may consume only the merged `P1AuthorityServiceHandleV1` and installed restricted-worker launcher.

Windows uses a service SID, named pipe, AppContainer worker, LSA credentials and CNG Platform KSP. macOS uses XPC, SMAppService/LaunchDaemon installation, App Sandbox worker, Keychain and Secure Enclave. Linux uses systemd, AF_UNIX peer credentials, dedicated UIDs, encrypted credentials and PKCS#11/TPM2 providers.

No platform may substitute a source marker or build-only job for behavior. Unsupported provisioning remains blocked rather than weakening the authority boundary.
