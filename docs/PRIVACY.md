# Privacy

Kristin is local-first. Project files, prompts, knowledge, research snapshots, run memory, run state, audit data, and local model traffic remain on the workstation unless the operator explicitly configures a non-local model endpoint, grants network research, invokes an MCP server, packages/exports data, or sends an artifact elsewhere.

## v0.9 evidence retention

The local research archive can retain:

- requested and final URLs;
- redirect history, status, selected headers, provider, and timestamps;
- raw fetched content and extracted text;
- search queries and result snippets;
- hashes, byte counts, MIME types, and project association.

Run memory can retain the user's request, outcome, summaries, failure descriptions, changed-file references, verification summaries, evidence identifiers/hashes, and execution counters.

These records are intentionally useful for future retrieval, which also makes them sensitive. Access to the Kristin data root is effectively access to project history and gathered research.

## Model context

A bounded subset of project knowledge and memory can be inserted into a model request. With a local provider it remains local to that provider process. With a configured remote provider, retrieved passages are transmitted to that provider when used. The UI should therefore make the chosen model/provider and consulted citations inspectable.

## Exports

Knowledge exports are local ZIP files and may include archived raw web content, extracted text, project notes, and run memory. Treat them as project-confidential. Creating an export does not upload it, but subsequent sharing is the operator's responsibility.

## Logs and support data

The product has no built-in advertising or behavioral analytics. Local operational logs can include task/run identifiers, model identity, durations, tool names, commands, errors, evidence summaries, and redacted attributes.

The v1.0.3 diagnostic exporter replaces source-like payload fields with hashes, bounds large strings, and applies recognized-secret redaction. This remains defensive pattern-based redaction, not proof that ordinary request text, project names, URLs, relative paths, errors, model previews, personal data, or all secrets are absent. Diagnostic ZIPs and raw logs must be reviewed before disclosure.

## Deletion and retention

Deleting a project registration does not delete the user's project folder and should not be assumed to erase all archive, memory, log, export, or checkpoint data. Until a dedicated retention UI is implemented, operators should manage the data root through documented backups and careful offline cleanup.

External model providers, search services, package registries, MCP servers, deployment platforms, and websites have their own data practices. Enabling any of them is an explicit trust decision.
