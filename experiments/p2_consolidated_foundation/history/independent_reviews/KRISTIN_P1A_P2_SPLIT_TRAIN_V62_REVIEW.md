# Kristin P1A + P2 Split Integration Train V62 — Independent Technical Review

## Verdict

**The P1A/P2 split is architecturally correct, but V62 is NO-GO for `prepare-source`, evidence finalization, PR, or merge.**

**Package verification is approved.**

V62 correctly recognizes that the isolated authority service is a P1 trusted-computing-base amendment and must be merged before P2. The child launchers are substantially more resumable than V61, P2 is delegation-only at the repository level, and the package/manifest checks are strong.

However, the P1A source is not a production tri-platform authority service:

1. Windows and macOS implementations are explicit source-only stubs.
2. Linux loads an exportable PEM private key from a root-owned file despite requiring non-exportable keys.
3. Linux does not validate a real P1 policy decision or Capability Grant v2; it checks static allowlists and approval/revocation text files.
4. There is no concrete Flutter/native connector or platform installer for any operating system.
5. P1A behavioral receipts are unsigned self-asserted JSON and are trivially forgeable.
6. P2 launches the Node worker with ordinary `Process.start` under the desktop account; it does not launch the distinct worker UID/AppContainer/sandbox principal that P1A relies upon.
7. Windows/macOS P1A CI jobs only compile stubs, yet the merge and P2 dependency gates treat those build jobs as the required P1A workflow contract.

Request **V63** before preparing either train.

---

# Exact uploaded-byte verification

## Umbrella ZIP

```text
KRISTIN_P1A_P2_SPLIT_TRAIN_V62_BUNDLE(1).zip
SHA-256:
6a15def024978e0ee3851f4b5bd710e36ab1f14985d6e6279a414fc43115c8c9
```

The value matches the published checksum.

## Uploaded P1A validator

```text
validate_kristin_p1a_v62_package(1).py
SHA-256:
0747ea9aaa92a094588f5a5a9d7f494590640a4035252aeac8e2bd0af52749dd
```

## Uploaded P2 launcher

```text
integrate_kristin_p2_full_train_v62(1).sh
SHA-256:
d182364b9e8f5a41f6b1707101891bd2a4ddcabf097cad8a0553724579af73de
```

All match the published V62 values.

## Umbrella contents

Independent inspection found:

```text
Umbrella ZIP entries: 32
Umbrella payload records: 31
P1A child ZIP SHA-256:
415a58e88b8f0886efca76246a16e772ccc8b288deccf633e2f04eb9c7750d4a

P2 child ZIP SHA-256:
25bcfa8e75becc2c81fa3cbd49eba8ddf4621dd601bc5fc90d0eb98b4eb4fa59
```

The child ZIPs, launchers, validators and sidecars match `BUNDLE_MANIFEST.json`.

## Child package validators

Both genuine child packages pass their exact validators and one-byte mutation rejection:

```text
P1A:
ZIP entries: 56
Manifest payloads: 55
Launcher syntax: PASS
Launcher verify-package: PASS
Mutation rejected: PASS
Completion claim: false

P2:
ZIP entries: 210
Manifest payloads: 209
Launcher syntax: PASS
Launcher verify-package: PASS
Mutation rejected: PASS
Completion claim: false
```

---

# Genuine improvements

## 1. Correct governance split

P1A is now a separate amendment and P2 refuses to prepare without merged P1A evidence and exact base gates.

This is the correct direction and resolves the V61 governance problem of redefining P1 authority inside P2.

## 2. Better stage recovery

The child launchers now expose:

```text
verify-package
status
prepare-source
resume-source-ci
collect-review
resume-evidence
merge
discard-failed-branch
```

State is external to the operator checkout, committed stages are exact-SHA resumable, and destructive branch removal requires an exact expected SHA.

## 3. Strong package boundaries

- Child packages are immutable-digest bound.
- Unsafe ZIP paths, collisions, symlinks, encrypted members and caches are rejected.
- P2 package validator rejects P1 authority/broker material.
- No completed P1A or P2 packet is packaged.
- Source packages remain fail closed.

## 4. P2 repository boundary is delegation-only

The P2 overlay does not contain the prior P1 policy engine, grant issuer, use ledger, revocation authority, audit signer or protected-key broker.

Its Dart adapter consumes `P1AuthorityServiceHandleV1`.

That repository boundary is improved, although runtime worker identity remains unresolved.

---

# Release-blocking findings

## 1. Windows P1A is an explicit stub

The Windows source performs a few named-pipe client-token checks, but its authentication function ends with:

```cpp
return false; // fail closed until provisioned identities are supplied.
```

Its executable otherwise prints:

```text
BLOCKED: Windows P1A service is not provisioned by this source-only amendment package.
```

It does not implement:

- named-pipe server lifecycle;
- Windows service installation;
- service SID ACL;
- CNG non-exportable signing key;
- typed authority protocol;
- internal policy/grant/use/revocation/audit logic;
- worker AppContainer/restricted-token denial;
- restart/replay state.

### Impact

No real Windows behavioral receipt can honestly be produced by the exact V62 Windows source.

A receipt claiming `installerObserved`, `nonExportableKeys`, internal policy/grant checks and worker denial would describe code not present in the reviewed source tree.

---

## 2. macOS P1A is an explicit stub

The macOS file contains an audit-token/SecRequirement helper but no XPC service implementation.

Its main function prints:

```text
BLOCKED: macOS P1A XPC service is not provisioned by this source-only amendment package.
```

It does not implement:

- Mach/XPC listener;
- SMAppService installer;
- LaunchDaemon/helper lifecycle;
- Keychain ACL/non-exportable key;
- typed authority request dispatch;
- internal policy/grant/use/revocation/audit validation;
- sandboxed-worker denial;
- restart/replay state.

### Impact

The exact V62 source cannot generate completion-eligible macOS authority-service evidence.

---

## 3. Linux uses an exportable PEM private key

The common native library loads the authority key using:

```cpp
PEM_read_PrivateKey(...)
```

from a filesystem path supplied through `--key`.

The Linux service requires the file to be root-owned and mode-restricted, but the key remains an exportable private-key file.

The P1A completion contract requires:

```text
nonExportableKeys: true
```

and the configuration describes a service-owned non-exportable authority key.

### Impact

The implemented Linux reference cannot truthfully satisfy the non-exportable-key completion requirement.

### Required V63 correction

Use a platform keystore/HSM-backed key whose private material cannot be exported:

- Linux: TPM2/PKCS#11/kernel keyring or a separately justified non-exportable provider.
- Windows: CNG KSP service-owned non-exportable key.
- macOS: Keychain/Secure Enclave where appropriate with service-only ACL.

Receipts must bind the provider, key identity, ACL/policy and signing operation provenance.

---

## 4. Linux does not validate a real P1 grant or policy decision

The Linux authorize request includes IDs and digests, but the service implementation checks only:

- static `allowed_tools`;
- static `allowed_operations`;
- owner approval ID appearing in a text file;
- capability ID absent from a revocation text file;
- request deadline;
- nonce replay.

It does not load or validate:

- a deterministic P1 policy-decision record;
- Capability Grant v2 body and signature;
- grant scope;
- grant subject/actor/run/task binding;
- grant use limit;
- expected grant digest;
- revocation epoch;
- signed audit-chain predecessor/checkpoint.

Despite this, the response reports:

```text
policyValidatedInsideService: true
grantIssuedInsideService: true
useConsumedInsideService: true
```

The platform evidence contract instead requires:

```text
grantValidatedInsideService: true
```

This creates an implementation/contract mismatch.

### Impact

The service can mint an effect permit from caller-supplied identifiers without proving that a valid P1 grant exists.

### Required V63 correction

The isolated service must own or securely query the actual P1 authority state and validate the exact policy decision and grant before issuing a permit.

The native, Dart and evidence field names must agree exactly.

---

## 5. No concrete platform connector exists

The Dart runtime defines:

```dart
abstract interface class P1AuthorityServiceConnectorV1
```

and a registry where a native embedder may install a connector.

No concrete connector is included for:

- Windows named pipes;
- macOS XPC;
- Linux AF_UNIX.

No Flutter plugin, FFI binding, method channel, platform runner integration or native embedder patch installs the connector.

### Impact

Even the Linux reference service cannot be used by the shipped Kristin runtime from this source package.

`ProductRuntime.p1AuthorityService` remains null unless external unreviewed code installs the connector.

---

## 6. No production platform installers are included

The P1A evidence contract requires:

```text
installerObserved: true
installerSha256
```

But the source package contains no:

- Windows service installer;
- macOS SMAppService/LaunchDaemon installer;
- Linux systemd/package installer;
- uninstall/rollback implementation;
- service upgrade/migration mechanism.

### Impact

Completion receipts can reference installer hashes that do not correspond to any reviewed source file in the train.

---

## 7. P1A platform receipts are forgeable

`validate_platform_receipt()` verifies:

- JSON identity;
- expected booleans;
- hexadecimal digest formatting;
- an artifact-directory digest;
- a worker-denial artifact digest.

It does not verify:

- a platform/runner signature;
- exact GitHub repository/workflow/ref;
- exact workflow run attempt;
- exact job identity from GitHub;
- runner provisioning trust;
- service installer provenance;
- binary-to-source reproducible build;
- service-generated signed receipt.

An independently constructed fake Windows receipt containing self-asserted booleans, made-up workflow IDs and arbitrary 64-hex values was accepted by the production validator after its artifact digest was made internally consistent.

### Impact

The P1A finalizer can create:

```text
tasks/completed/P1A-001.md
release/evidence/P1A/manifest.json status=passed
p2DependencySatisfied=true
```

from unsigned self-asserted receipt files plus manual review/owner JSON.

### Required V63 correction

P1A needs the same or stronger signed exact-run provenance model used by P2:

- signed runner provisioning;
- repository/workflow/ref/run/attempt/job binding;
- exact runner/service identity;
- source commit/tree;
- installer/binary/source/build digests;
- service-generated typed behavior receipts;
- post-test uninstall/cleanup receipt;
- trust-root validation;
- GitHub API verification.

---

## 8. P1A CI does not execute Windows or macOS behavior

The P1A workflow jobs are:

```text
p1a-linux-reference
p1a-windows-build
p1a-macos-build
```

Windows and macOS only compile their stubs.

The P1A source, final-branch, PR test-merge and merged-main gates require only these job names.

P2's merged-P1A dependency gate also requires only the same build/reference jobs.

### Impact

Protected main can be considered P1A-green without any production Windows/macOS authority service, installer, worker denial or typed authorization behavior being reproduced by CI.

### Required V63 correction

Replace build-only jobs with controlled behavioral jobs:

```text
p1a-behavioral-windows
p1a-behavioral-macos
p1a-behavioral-linux
```

Each must install the exact service, run the real desktop connector, launch the real restricted worker principal, prove denial, exercise typed authorization, restart the service and reject replay, then uninstall and prove cleanup.

---

## 9. P2 does not launch a separate worker OS principal

`P2ProcessAutomationHostClient.start()` starts Node using ordinary Dart:

```dart
Process.start(...)
```

There is no:

- Linux setuid/setgid helper;
- Windows restricted token/AppContainer launcher;
- macOS sandbox profile/distinct identity launcher;
- `CreateProcessAsUser`;
- native worker broker.

The Node worker therefore runs as the same desktop user by default.

P1A's Linux service admits `desktop_uid` and denies a distinct configured `worker_uid`.

### Impact

The actual P2 worker is not the denied worker principal. It can present the same UID as the desktop and potentially connect to the authority service if it discovers the endpoint.

The key V61 same-account issue therefore remains unresolved in the composed P1A+P2 system.

### Required V63 correction

P2 must launch the automation worker through a platform-native restricted-principal launcher:

- Linux: dedicated unprivileged `kristin-worker` UID, sanitized namespaces/environment and controlled filesystem.
- Windows: AppContainer or restricted token with a distinct SID and named-pipe ACL denial.
- macOS: signed sandboxed helper with distinct code requirement/entitlements.

The worker-denial test must use the exact production worker launcher and binary.

---

## 10. P2 evidence trusts separation metadata rather than proving launch identity

The P2 runtime reads P1A endpoint fields such as:

```text
workerPrincipalSeparated
workerDeniedByOs
```

and behavioral receipts require those booleans.

But the production worker launch code does not bind:

- worker UID/SID/audit token;
- launcher binary digest;
- worker process identity;
- P1A service denial attempt by that exact process.

### Impact

P2 evidence can assert separation based on external attestation while the shipped process runs under the desktop principal.

---

## 11. The umbrella ZIP is not self-contained

The uploaded umbrella ZIP includes:

- child ZIPs;
- child launchers;
- child validators;
- a bundle-contents validator.

It does not include the advertised:

```text
integrate_kristin_p1a_p2_split_train_v62.sh
validate_kristin_p1a_p2_v62_bundle.py
```

Those are documented as separate primary downloads, but they were not attached to this review.

### Impact

The advertised umbrella commands:

```bash
python validate_kristin_p1a_p2_v62_bundle.py ...
bash integrate_kristin_p1a_p2_split_train_v62.sh verify-all ...
```

cannot be independently executed from the uploaded artifact set.

This is a delivery-completeness issue, not the principal security blocker.

---

## 12. P1A native workflow toolchains are not fully governed

The P1A workflow uses hosted runner ambient Python and CMake/compiler state and does not set up the exact governed Python/native toolchain or record compiler/binary provenance as workflow artifacts.

`product-gates` provides separate repository validation, but it does not replace exact authority-service native build provenance.

---

# Approved actions

## Safe now

Verify and inspect the immutable packages only.

The exact child validators already pass against the uploaded child archives.

## Not approved

Do not run:

```text
P1A prepare-source
P1A resume-evidence
P1A merge
P2 prepare-source
P2 resume-evidence
P2 merge
```

Do not push:

```text
integration/p1-authority-service-v62
integration/p2-full-train-v62
```

Continue using the quarantined P2 safe-foundation branch for non-authority contracts and native probes while V63 is produced.

---

# Required V63 architecture

## P1A

1. Real production Windows named-pipe service.
2. Real production macOS XPC/SMAppService service.
3. Real production Linux service.
4. Concrete installers/uninstallers/updaters on all platforms.
5. Non-exportable platform keys.
6. Actual P1 policy decision and Capability Grant v2 validation inside service.
7. Exact revocation epoch, use ledger and signed audit-chain integration.
8. Concrete Flutter/native connectors for all platforms.
9. Signed exact-run behavioral receipts.
10. Real worker-principal denial using the production P2 worker launcher.
11. Behavioral CI on Windows/macOS/Linux, not build-only stubs.

## P2

1. Platform-native restricted worker launcher.
2. Exact worker UID/SID/audit-token evidence.
3. Worker process identity bound to every session/effect receipt.
4. Real denial attempt against P1A by the exact worker process.
5. P2 base gate requiring real P1A behavioral jobs and signed P1A manifest graph.

## Umbrella

1. Include or separately attach the exact coordinator and external bundle validator.
2. Complete the combined status/discard simulation.
3. Verify both child stage machines against a disposable remote.

---

# Classification

| Area | Result |
|---|---|
| Architectural P1A/P2 split | PASS |
| Umbrella and child package integrity | PASS |
| Child package mutation rejection | PASS |
| Resumable child launcher design | IMPROVED |
| P2 repository-level delegation-only boundary | PASS |
| Windows authority implementation | FAIL — stub |
| macOS authority implementation | FAIL — stub |
| Linux non-exportable key requirement | FAIL |
| Linux policy/grant validation | FAIL |
| Platform connector implementation | MISSING |
| Platform installer implementation | MISSING |
| P1A evidence authenticity | FAIL |
| P1A tri-platform behavioral CI | FAIL |
| P2 restricted worker principal | FAIL |
| P2/P1A composed worker denial | FAIL |
| Exact controlled platform evidence | NOT SUPPLIED |
| Safe to verify packages | YES |
| Safe to prepare P1A | NO |
| Safe to prepare P2 | NO |
| Safe to merge either train | NO |
| Required revision | **V63** |
