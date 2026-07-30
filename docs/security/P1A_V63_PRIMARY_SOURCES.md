# P1A V63 platform authority primary sources

Reviewed on 2026-07-29. These sources constrain the production adapters and do not constitute behavioral proof.

## Windows

- Microsoft Learn, `ImpersonateNamedPipeClient`: named-pipe servers can impersonate the client security context and must fail closed if impersonation fails.
  https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-impersonatenamedpipeclient
- Microsoft Learn, `GetNamedPipeClientProcessId`: retrieves the process ID of the connected named-pipe client.
  https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid
- Microsoft Learn, pipe functions overview.
  https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-functions
- Microsoft CNG persisted keys and Platform Crypto Provider documentation must govern final provisioning, export policy, machine-key ACLs and signing receipts.
  https://learn.microsoft.com/en-us/windows/win32/secauthn/cng-portal

## macOS

- Apple Service Management `SMAppService`: macOS 13+ registration and control for bundled LaunchAgents and LaunchDaemons.
  https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple XPC: launchd-managed IPC and privilege-isolation mechanism.
  https://developer.apple.com/documentation/xpc
- Apple `xpc_listener_set_peer_requirement`: all listener messages are checked against the configured peer code-signing requirement.
  https://developer.apple.com/documentation/xpc/xpc_listener_set_peer_requirement
- Apple `SecKeyCopyExternalRepresentation`: export fails for non-exportable keys, including Secure Enclave-bound keys or keys marked nonextractable.
  https://developer.apple.com/documentation/security/seckeycopyexternalrepresentation(_:_:)
- Apple `SecKeyCreateSignature`: service-side signing using the non-exportable private key.
  https://developer.apple.com/documentation/security/seckeycreatesignature(_:_:_:_:)

## Linux and OpenSSL providers

- Linux `unix(7)`: `SO_PEERCRED` returns the peer credentials captured for a connected AF_UNIX socket.
  https://man7.org/linux/man-pages/man7/unix.7.html
- OpenSSL `OSSL_STORE_open`: provider/loader-backed objects are retrieved from a URI and then used without exporting the private object.
  https://docs.openssl.org/3.5/man3/OSSL_STORE_open/
- OpenSSL store/provider documentation includes provider-specific URI loaders such as PKCS#11 URIs when the provider implements the loader.
  https://docs.openssl.org/3.0/man7/ossl_store/

## Evidence rule

Source use of these APIs is completion-ineligible. The P1A gate still requires exact signed Windows, macOS and Linux installation, caller-authentication, key-provider, restricted-worker denial, replay-after-restart, build-provenance and cleanup evidence from controlled runners.
