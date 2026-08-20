# P3 Browser Task Recipes

These recipes describe the supported product path for browser work. They are examples of the governed runtime contracts, not permission bypasses. Every effect remains subject to the active P1/P2 authority and the browser runtime's bounded validation.

## Inspect a page before acting

1. Start an application-owned browser session.
2. Open the target page.
3. Capture a canonical observation.
4. Review URL, visible text, accessibility tree, forms, console, network and screenshot in Browser Workspace.
5. Bind actions to the observation hash and stable locators.

Do not use visual targeting before stable locator resolution has been attempted.

## Fill and submit a form

1. Prefer role, label, placeholder or test-id locators.
2. Capture the pre-action observation.
3. Fill fields with a structured action.
4. Submit with a structured click or press action.
5. Verify the returned before/after observation hashes and the expected visible state or URL.
6. If the target is ambiguous, stop rather than guessing.

## Use visual fallback

Visual fallback is allowed only after the structured locator path fails with the governed locator failure. The visual source must match the exact screenshot and observation hashes, targets must be inside the viewport, confidence must meet the runtime minimum, and a post-action observation or URL condition must verify the effect. A low-confidence or ambiguous result transitions to user takeover.

## User takeover and resume

1. When the runtime returns `user_takeover_required`, automation is paused.
2. Give the user explicit control of the browser surface.
3. Do not run automation while user control is active.
4. After the user finishes, capture a fresh canonical observation.
5. Resume only when the fresh observation hash differs from the pre-takeover hash and is accepted by the takeover controller.

## Persistent authenticated profile

Persistent profile state is local and application-owned. Serialize cookies/local storage into a bounded JSON object, then persist it through `P3BrowserProfileStore` with a platform-backed authenticated cipher. Plaintext browser state must never be written by the profile store. Delete the profile through the store when the user requests profile removal.

## Download a file

1. Enable downloads explicitly for the session.
2. Initiate the download through a stable locator.
3. Accept only the bounded application-owned quarantine receipt.
4. Verify byte count, SHA-256, session/profile binding and locator binding before moving or opening the payload.

## Upload a file

1. Enable uploads explicitly for the session.
2. Stage an absolute local file through the application-owned upload staging API.
3. Verify the stage manifest and SHA-256.
4. Select the file input with a stable locator and consume the stage once.
5. Verify the durable upload receipt. Never pass arbitrary local filesystem paths directly to page script.

## Web Studio preview

Use static preview for local HTML/CSS/JavaScript projects. The preview server binds only to loopback and injects the bounded live-reload endpoint. For framework dev servers, launch through `P3P2ManagedPreviewProcessHost`; readiness must be loopback-only and bounded, and shutdown must use the managed P2 process identity. A failed stop remains visible and retryable.

## Failure replay

On failed browser tasks, export the bounded replay bundle. It includes action/observation hashes and sanitized console/network telemetry but excludes screenshot payloads, DOM bodies, visible-text bodies and sensitive typed values. Use it for diagnosis without turning replay artifacts into another secret store.

## Deterministic validation

Use `test/fixtures/p3_browser/` for browser regression tests. The fixture is local-only and provides forms, dialog, drag/drop, download, upload, console output and accessibility content without external network dependencies.
