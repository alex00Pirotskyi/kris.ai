# Deterministic Policy Engine v2

## Decision authority

The desktop host owns deterministic policy resolution. Models, prompts, web pages, repositories, memories, tool output, workers and environment variables may propose actions but cannot approve, widen or mint authority. The policy engine produces either `allow`, `deny`, or `approval_required`; only an `allow` decision may become a Capability Grant v2 draft.

## Resolution order

1. Load the selected Access Profile v2 ceiling.
2. Resolve the registered capability, tool and actor.
3. Apply organization, project and user overlays in fixed order and stable overlay-ID order.
4. Union denials, intersect scopes, take minimum budgets and choose the strictest approval policy.
5. Apply explicit widening only with trusted owner or organization-policy approval, and never beyond the base Access Profile ceiling.
6. Validate the concrete filesystem, process, network, browser, secret or sandbox effect.
7. Emit a deterministic decision and, only for `allow`, a bounded Capability Grant v2 draft.

## Invariants

- Unknown capabilities, unregistered tools and mismatched actors deny by default.
- A deny or force-deny overlay cannot be undone by a lower layer.
- Overlay order in input cannot change the decision.
- Budgets and scopes are monotonic narrowing unless an explicit trusted widening restores scope within the profile ceiling.
- Owner Mode keeps its intended current-account authority but high-risk operations still follow its configured approval policy.
- Owner unattended cannot gain interactive PTY or elevation through policy text.
- Isolated-untrusted execution cannot use host credentials or private-network authority.
- Raw secret reveal is never emitted in a grant draft.
- The policy decision is evidence, not proof that an effect occurred.

## Relationship to adjacent milestones

P1-002 supplies authority ceilings. P1-003 supplies authenticated worker grants. P1-004 resolves policy and creates unsigned grant drafts. P1-005 and P1-006 own durable signing. P1-012 owns authenticated local transport. Concrete terminal, browser and filesystem execution remains outside this milestone.
