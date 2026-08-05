# Authority and supersession map

## Normative order during adoption preparation

1. Security policy and protected-branch rules.
2. `docs/roadmap/MASTER.md`.
3. `docs/roadmap/roadmap.yaml` within its declared scope.
4. Accepted ADRs, schemas, compatibility contracts, and evidence rules.
5. Draft PR #63 ANARCHY proposal documents.
6. Phase packet, task packet, valid worker claim, exact-SHA CI/review/evidence.

## One authority rule

- Human authority: `docs/roadmap/MASTER.md`.
- Machine authority: `docs/roadmap/roadmap.yaml`.
- Generated compatibility views: `STATUS.md`, `HANDOFF.md`, `GENERATED_STATE.md`, and the post-adoption ANARCHY dashboard/worker views.
- Proposal inputs: phase packets, worker proposal cards, ANARCHY constitution, migration documents, and the hash-linked v3.2 reference.
- Historical evidence: accepted manifests, review records, baselines, hashes, and superseded decision records.

No proposal, dashboard, worker file, claim, PR body, or migration ledger may assign canonical task status independently.

## Supersession rules

A supersession record must identify old object, new object, reason, compatibility period, evidence, and rollback. Historical objects remain addressable. Task IDs cannot be reused. Generated files are replaced only by their declared generator. Exact-SHA evidence remains immutable; later evidence appends a new binding.
