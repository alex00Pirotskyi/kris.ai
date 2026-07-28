# Kristin threat model v2

The threat model treats model output, web content, repositories, terminal output, MCP/A2A peers and worker results as untrusted data. None can become policy, approve widening, select a trust root or reveal a secret.

Critical scenarios include prompt injection, confused deputy, grant replay, wrong-run execution, signer substitution, key revocation failure, malicious extension updates, local IPC impersonation, secret leakage, audit truncation, updater rollback/freeze/mix-and-match, browser-profile leakage, Owner Mode scope escape and delegation widening.

`config/threat_model_v2.json` assigns an owner and executable planned test to every high-risk boundary. Residual risk must remain explicit; absence of a backend is reported as unavailable rather than silently downgraded.
