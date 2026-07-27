# Kristin Production Risk Register

**Roadmap authority:** `DERIVED`

| ID | Risk | Severity | Current state | Owner task | Required evidence to close |
|---|---|---:|---|---|---|
| `RISK-001` | Three-platform CI does not yet prove analyzer, tests, validators, and native builds | Critical | Open | `P0-003` | One exact commit passes Ubuntu, Windows, and macOS through native build |
| `RISK-002` | Toolchains and GitHub Actions are mutable | High | Open | `P0-004` | Exact versions and Action SHAs; two matching reruns |
| `RISK-003` | Security/support claims can drift from product behavior | High | Open/Review | `P0-005` | README, SECURITY, UI, and release metadata agree; independent review |
| `RISK-004` | Source markers can be mistaken for behavioral proof | High | Review | `P0-007`, `P8-001` | Categorized assurance report; later full test hierarchy |
| `RISK-005` | Roadmap status can drift across chat, Markdown, task files, and GitHub | High | Mitigated by P0-008, pending review | `P0-008`, `P24` | Strict manifest validation and fresh-session selection |
| `RISK-006` | Legacy v1 signed manifests could regain authorization authority | Critical | Contained | `P0-002`, `P1-005`–`P1-007` | Disablement regression remains passing; v2 replaces it |
| `RISK-007` | Early no-SQL migration could weaken the tested SQLite durability baseline | Critical | Controlled | `P24` | Dual-write/replay/chaos evidence equals or exceeds SQLite baseline |
| `RISK-008` | Full-computer Owner Mode can cause broad destructive effects | Critical | Architectural | `P1`, `P2`, `P8` | Explicit profile, kill, audit, snapshots, reconciliation, adversarial suite |
| `RISK-009` | Browser, web, MCP, A2A, and project content can inject instructions | Critical | Architectural | `P6-005`, `P6-006`, `P7`, `P8` | Provenance labels and zero unauthorized effects in adversarial corpus |
| `RISK-010` | Repository provenance and release supply chain remain insufficient for stable distribution | High | Open | `P0-006`, `P9` | Protected history, signed artifacts, SBOM, provenance, TUF, install/update tests |

## Update rule

Every task that changes authority, execution, secrets, network, browser, updater, release, or storage must update this register or explicitly state that no risk entry changed.
