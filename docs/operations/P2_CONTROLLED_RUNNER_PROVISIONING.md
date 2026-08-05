# P2 controlled runner provisioning — V63

P2 behavioral evidence is accepted only from three externally governed, interactive-desktop self-hosted runners. Repository code cannot create or self-sign runner authority or the separately merged P1A authority service.

## External authority artifacts

Each runner receives a separately signed V3 provisioning packet and external Ed25519 trust policy. The packet binds the exact runner IDs, names, group IDs, immutable labels, host-image digest, configuration receipt, per-job attestation provider, post-run cleanup provider, controlled package/service fixtures, and three technology-candidate receipts. It is validated into an external V5 runtime policy.

The runner receives only public, signed P1A evidence: the merged P1A manifest, authority-service attestation, installation/provisioning receipt, and worker-denial receipt. It receives no key handle, broker executable, private key, HMAC key, signing provider, owner approval signer, live policy state, or revocation secret.

## Exact current-job attestation

For each workflow run attempt and job, the externally controlled attestation provider signs the exact repository, workflow path/ref/file digest, run, attempt, job, commit, GitHub-observed runner identity/group/labels, unique ephemeral runner session, interactive session, permissions, exclusivity, P1A service evidence, and controlled resources. The resulting `p2-controlled-runner-attestation-receipt-v5` remains completion-ineligible.

It must prove `workerCannotAccessAuthorityService: true` and `p2ReceivesAuthoritySecrets: false`. Changing any run/job/runner/session/resource field invalidates the signature or exact binding.

## Post-run cleanup

Every platform job has an `if: always()` cleanup step. The external cleanup provider terminates managed and orphaned process trees, verifies zero descendants, removes controlled user services and packages, clears clipboard/screen test data, clears copied P1A evidence artifacts without touching the external service, removes workspaces and test secrets, and confirms runner exclusivity.

Only `p2_finalize_platform_after_cleanup.py` may convert a V5 provisional receipt into `p2-task-platform-behavioral-v5`, and only after a signed V2 cleanup receipt is verified. A failed, absent, stale, malformed, or mismatched cleanup keeps every task blocked.
