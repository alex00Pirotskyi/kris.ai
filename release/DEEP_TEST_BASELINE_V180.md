# Deep baseline: Kristin v1.8.0+180

This report captures the pre-v1.9 baseline from the current cumulative source line before interoperability and release-operations hardening.

## Baseline verdict

- governed validation: **Kristin governed source validation passed.**
- architecture validation: **Kristin governed source validation passed.**
- offline system contracts: **36/36**
- durable workflow kernel: **14/14**
- Prompt Studio 2: **30/30**
- Linux sandbox worker: **8 / 8**
- network broker: **6 / 6**
- execution intelligence: **40/40**
- Project Manager 2: **16/16**
- knowledge and memory: **12/12**
- file adapters: **14/14**

## Workflow kernel baseline

- schema version: **5**
- migration digest: `bb954f8b5eff84f971abfcaf30a5a907ea36601b86ef12e9b9d622360b80e0be`
- append-only events: **20**
- idempotency records: **2**
- compensation records: **1**
- integrity: **ok**

## Why this baseline matters

The v1.9 work was added only after the cumulative v1.8 line already passed its retained reliability, workflow, sandbox, convergence, memory, and file-adapter gates. This prevents v1.9 interoperability work from masking older regressions.
