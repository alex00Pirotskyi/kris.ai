# Restricted worker launch policy V2

The production launcher accepts only a service-owned policy and a desktop-generated worker session ID. The policy binds the exact launcher, Node executable, automation-host script, working directory, installed P1A endpoint, platform principal, source commit/tree, package digest, and permitted environment surface.

The launchers fail closed unless `schemaVersion` is `2.0.0`. Platform identity fields live under the corresponding `linux`, `windows`, or `macos` object. The staged policy contains no authority private key, grant key, approval key, key handle, secret token, or signing broker.

Before P2 sends any public-verifier bootstrap:

- Linux changes to the dedicated `kristin-worker` UID/GID, enables `NO_NEW_PRIVS`, isolates mount/IPC/UTS namespaces, and makes the exact authority denial attempt.
- Windows creates the exact Node worker suspended in its AppContainer, binds it to a kill-on-close Job Object, emits the launcher identity, then resumes it. The worker itself performs the exact named-pipe denial probe.
- macOS applies the signed App Sandbox profile, performs the exact Mach/XPC denial probe, then starts the digest-bound Node worker with the inherited sandbox.

The desktop binds the launcher identity and the exact worker-denial record before sending the one-use public-verifier bootstrap. P1A completion additionally requires the authority service’s own signed behavior ledger to record denial of the same launcher/session/process identity.
