# Kristin P0-009 Initial Benchmark Baseline

- Suite: `kristin.p0-009.initial` version `1.0.0`
- Mode: `portable`
- Cases: **12**
- Measured coverage: **50.0%**
- Scored readiness: **50.0%**
- Result fingerprint: `b13796f9c5ece24377b75c20ab5f082b60e8326b4bd617e3240ab60b211ff5f8`

> This is a reproducible starting measurement, not a production-readiness claim. Unsupported, unavailable, failed, and model-not-run cases remain visible and do not count as passing.

## Category summary

| Category | Cases | Measured | Coverage | Score | Readiness |
|---|---:|---:|---:|---:|---:|
| Coding | 2 | 1 | 50.0% | 100.0% | 50.0% |
| Analysis | 2 | 1 | 50.0% | 100.0% | 50.0% |
| Path safety | 2 | 1 | 50.0% | 100.0% | 50.0% |
| Crash recovery | 2 | 2 | 100.0% | 100.0% | 100.0% |
| Browser capability honesty | 2 | 0 | 0.0% | 0.0% | 0.0% |
| Research and citations | 2 | 1 | 50.0% | 100.0% | 50.0% |

## Cases

| Case | Category | Assurance | Status | Score | Reason |
|---|---|---|---|---:|---|
| `coding.python_bugfix_task` | coding | benchmark_task | **not_run** | — | model_candidate_not_supplied |
| `coding.protocol_contract_gate` | coding | behavioral | **passed** | 100.0% | command_expectations_satisfied |
| `analysis.architecture_review_task` | analysis | benchmark_task | **not_run** | — | model_candidate_not_supplied |
| `analysis.offline_system_contract` | analysis | source_contract | **passed** | 100.0% | command_expectations_satisfied |
| `path_safety.generated_state_policy` | path_safety | behavioral | **passed** | 100.0% | all_path_expectations_satisfied |
| `path_safety.flutter_workspace_behavior` | path_safety | behavioral | **unavailable** | — | portable_baseline_excludes_sdk |
| `crash_recovery.sqlite_workflow_kernel` | crash_recovery | behavioral | **passed** | 100.0% | command_expectations_satisfied |
| `crash_recovery.diagnostic_replay` | crash_recovery | behavioral | **passed** | 100.0% | command_expectations_satisfied |
| `browser_absent.capability_inventory` | browser_absent | capability_inventory | **unsupported** | 0.0% | browser_automation_not_implemented |
| `browser_absent.form_completion_task` | browser_absent | benchmark_task | **unsupported** | 0.0% | required_capability_unsupported:browser_absent.capability_inventory |
| `research.knowledge_memory_gate` | research | behavioral | **passed** | 100.0% | command_expectations_satisfied |
| `research.local_citation_task` | research | benchmark_task | **not_run** | — | model_candidate_not_supplied |

## Claim boundaries

- Source inspection is not behavioral proof.
- Unsupported, unavailable, and not-run cases are not passes.
- Completing P0-009 proves corpus/version/reproduction integrity only.
