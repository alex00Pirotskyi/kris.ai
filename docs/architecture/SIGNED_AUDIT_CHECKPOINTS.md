# Append-only signed audit checkpoints

Audit events remain an append-only hash chain. Periodic checkpoints bind the event count, current audit head, previous checkpoint hash, signer key id and sequence. Each checkpoint is Ed25519-signed with a protected audit-signing key.

Verification detects mutation, truncation, reordering, chain replacement and signer substitution. An exported receipt contains public verification data only.
