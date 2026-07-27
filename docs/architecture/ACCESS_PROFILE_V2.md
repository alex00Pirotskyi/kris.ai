# Access Profile v2

P1-002 defines a portable, versioned **authority ceiling**. A profile is not a capability grant and cannot authorize a concrete effect by itself. P1-003 binds a run/task/actor/tool request to a grant that must fit inside the selected profile. P1-004 resolves organization, project and user overlays, and those overlays may only narrow the selected profile unless an explicit product-owner widening transition is performed.

## Canonical profiles

| Profile | Authority ceiling | Sandbox | Unattended | Important boundary |
|---|---|---:|---:|---|
| `chat` | Conversation only | No executor | No | No filesystem, process, network, browser or credential effects. |
| `project` | Project roots and configured destinations | No claim | No | Absolute paths, elevation and service control are forbidden. |
| `owner` | Maximum authority available to the current OS account | **No** | No | Interactive elevation and break-glass reveal may be requested; neither is automatic. |
| `owner_unattended` | Current-account authority using pre-authorized brokered leases | **No** | Yes | No raw secret reveal, interactive elevation, MFA, CAPTCHA or user-consent substitution. |
| `isolated_untrusted` | Ephemeral sandbox only | Yes | Yes | No host credentials, host paths, authenticated browser profiles, private-address access or listening sockets. |

## Invariants

1. Models, web pages, terminal output, memory and workers cannot choose or widen a profile.
2. Profile selection is durable, visible and bound to a run before a capability grant is evaluated.
3. `owner` and `owner_unattended` are deliberately not called sandboxes.
4. Raw reusable secret material is not a normal model/worker input.
5. `owner_unattended` cannot perform any operation that requires interactive reauthentication or elevation.
6. `isolated_untrusted` cannot inherit Owner authority, credentials, browser profiles or host database access.
7. The five canonical profiles have equivalent semantics on Windows, macOS and Linux; platform adapters may differ.
8. Unknown profiles, unknown fields and invalid cross-field combinations fail closed.

## Persistence and compatibility

The canonical catalog is `config/access_profiles.v2.json`; its schema is `schemas/access_profile_v2.schema.json`. Persist `profileId`, `schemaVersion` and `profileRevision` with durable run state. A newer revision must be revalidated before resume. Unsupported versions fail rather than silently mapping to a broader profile.
