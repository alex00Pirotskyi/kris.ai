# Support policy

## Supported release boundary

Kristin Local Agent **v1.9.0+190** is currently supported as a **`source-release` preview**. The reviewed deliverable is the source tree plus the documented source-only validation gates.

This support policy does **not** claim:

- a signed installer;
- platform notarization;
- an authenticated updater;
- unrestricted full-computer Owner Mode;
- cross-platform hostile-code isolation;
- Signed Manifest v2 or production external manifest trust.

## Current support scope

| Area | Support status |
|---|---|
| Source tree and deterministic source gates | Supported |
| Linux reference namespace worker and brokers | Supported as source-side reference behavior on a configured host |
| Windows/macOS native worker backends | Not implemented; must fail closed |
| Compiled desktop artifacts | Unsupported unless a later reviewed release sets `compiled_release_validated` to `true` |
| Owner Mode / unrestricted host authority | Roadmap target only; not part of this release |
| Signed installer / updater | Not part of this release |

## Reporting and support bundles

When reporting a defect or vulnerability:

1. Use synthetic or scrubbed data whenever possible.
2. State the exact Kristin version and branch/commit if known.
3. Identify the operating system and relevant host prerequisites.
4. Include the smallest safe reproduction and diagnostic excerpt.
5. Review support bundles locally before disclosure.

Do **not** include raw credentials, private source code you are not prepared to disclose, personal data, or active exploit payloads in a public report.

## Source-only validation commands

Typical source-preview commands include:

```bash
python tool/protocol_contract_test.py
python tool/workflow_kernel_test.py --project .
python tool/interoperability_admin_v19_test.py
python tool/policy_support_test.py
python tool/validate_release.py --skip-sdk
```

Platform formatter, analyzer, Flutter tests, and native builds remain authoritative only on a configured workstation.

## Interoperability status

The v1 envelope-supplied signed-manifest trust path is disabled. Signed Manifest v2 is not yet implemented. Until a later reviewed milestone says otherwise, plugin, skill, MCP, A2A, and source-update manifest trust remains frozen at the current local source boundary rather than a general production signing system.

## Operator responsibilities

- Protect the local account, API tokens, and any external credentials.
- Review all support exports before sharing them.
- Avoid untrusted projects and third-party integrations unless you understand the current preview limits.
- Do not market this source release as a signed desktop product or a full-host automation product.
