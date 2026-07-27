# Kristin Security Review Prompt

Attack the selected task assuming the model, project, web page, terminal output, MCP/A2A metadata, connector description, plugin, and memory can be malicious.

Test unintended authority, command injection, path races, symlink/reparse escape, secret exposure, signer substitution, replay, duplicate effects, browser profile leakage, SSRF/rebinding, stale UI targets, process survival after kill, evidence tampering, update substitution, and false completion.

Owner Mode may be intentionally broad; verify that breadth is explicit and attributable rather than silently narrowed. Never treat approval policy `never` as permission to disable kill, redaction, audit, reconciliation, or verification.
