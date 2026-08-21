# Test Center — P25 Prompt Studio

**Canonical suite:** `docs/roadmap/p25/prompt_studio_test_station.v1.json`

## Profiles

### `contract`

Portable validation of the P25 roadmap extension, task DAG, performance budget, benchmark corpus, Test Center registration, and non-mutation.

```bash
python3 tool/p25_prompt_studio_test_station.py --project . --profile contract --check
```

### `latency-unit`

Deterministic Prompt Studio operation and latency-trace behavior. This profile is `BLOCKED_NOT_IMPLEMENTED` until P25-001 product source lands.

### `local-phi-cpu`

Real owner-machine benchmark. It requires exact model and hardware identity and remains `BLOCKED_ENVIRONMENT` in ordinary CI.

### `packaged-windows`

Installed Windows Prompt Studio journey. It remains `BLOCKED_NOT_IMPLEMENTED` until the migration and packaged application exist.

## Result states

- `PASS`
- `FAIL`
- `BLOCKED_ENVIRONMENT`
- `BLOCKED_NOT_IMPLEMENTED`

Blocked cases never count as pass. Source tests do not prove installed-product behavior, platform support, release support, production readiness, release, or GA.
