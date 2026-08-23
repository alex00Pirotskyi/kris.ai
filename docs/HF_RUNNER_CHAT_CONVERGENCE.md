# Runner + Chat Convergence Hotfix

This hotfix makes Chat the primary orchestration surface and turns the existing run graph into a live execution map.

## Product contract

- Kristin never starts expensive execution before a plan-scoped readiness check proves required capabilities.
- Model progress and bounded streamed model output are visible while a run is active.
- Prompt Studio clarification is available inline from Chat for underspecified build requests.
- New build requests may provision a project workspace automatically.
- Active runs accept conversational steering at the next safe model boundary.
- Saved runs reload durable run-scoped events instead of depending only on the 600-event UI buffer.
- The execution graph remains the primary visual explanation of a run and uses a separate inspector for detail.
- Raw provider chain-of-thought is not exposed. The UI shows model stage, streamed protocol/output, tools, evidence, and high-level activity.

## Readiness verdicts

`ready` starts automatically. `readyWithWarnings` starts with optional capability warnings. `blocked` fails before the run enters normal execution and records a durable preflight receipt.

## Live versus durable telemetry

High-frequency model text and tool activity use `LiveRunSignalBus`. Durable state transitions, readiness receipts, work items, tools, evidence, verification, retries, and steering application remain in the event journal.

## Manual acceptance

1. Send `hello` and verify model identity/stage appears immediately and the final surface contains the actual assistant answer.
2. Ask `build me an app` and verify inline clarification appears without navigating to Prompt Studio.
3. Start a Flutter build on a machine where Flutter is absent and verify preflight blocks before a `flutter create` tool call.
4. Start a healthy build and verify the tree shows model/tool activity, the live timeline updates, and the inspector follows selected nodes.
5. During an active run send `keep everything local`; verify it queues and applies at the next model turn.
6. Reopen a completed run after restart and verify its durable timeline is available.
7. Verify no execution node overflows at 1366x768 and 200% text scale.
