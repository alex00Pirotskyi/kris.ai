# Controlled P2 adversarial fixtures

Fixtures are bounded and must run only in disposable CI/worktrees. They cover path replacement, output flood, parent/descendant timeout, process-group escape attempts, crash/restart reconciliation, and watchdog kill. No fixture targets operator files, services, or packages.
