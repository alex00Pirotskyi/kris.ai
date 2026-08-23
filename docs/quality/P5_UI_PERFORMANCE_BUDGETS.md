# P5 UI Performance Budgets

**Task:** P5-013  
**Boundary:** Kristin desktop UI process. Local model-host memory and model inference latency are measured by their own runtime/model gates and are not hidden inside these UI budgets.

## Initial targets

| Metric | Initial target | Why it exists |
|---|---:|---|
| Startup to first rendered frame | <= 3000 ms | A fresh desktop launch must produce visible UI promptly even before capability probes finish. |
| Frame total time p95 | <= 25 ms | Interactive navigation/streaming should remain comfortably responsive on the supported desktop baseline. |
| Frames over 34 ms | <= 5% | Sustained visible jank must be surfaced rather than averaged away. |
| Live run stream UI flush p95 | <= 100 ms | Model/tool updates must feel live while still being coalesced to protect the UI thread. |
| Kristin process RSS | <= 768 MiB | The UI/runtime process needs a bounded initial desktop envelope; model-host memory is separate. |
| Mounted items for collections >=1000 rows | <= 250 | Large timelines/data views must remain virtualized rather than constructing the entire collection. |

## Instrumentation contract

`P5UiPerformanceMonitor` is the product-owned collector. It records startup, Flutter frame timings, coalesced live-run UI flushes, process RSS and large-list mounted-item peaks. `P5UiPerformanceDashboard` exposes the current values in Verification Center. Missing samples are `CALIBRATING`, never an implicit pass.

The deterministic test suite validates budget evaluation with passing, missing and deliberately over-budget samples. Environment-sensitive measurements may be retained as evidence, but a noisy CI machine must not be used to forge a production performance claim.

## Closure rule

P5-013 source closure requires the live monitor and dashboard to be wired to real app lifecycle and live-run batching, the deterministic budget suite to pass, large-list virtualization to be instrumented, and the exact candidate to pass the P5 quality workflow. Later P8 soak/performance work may tighten these targets; it must not silently weaken them.
