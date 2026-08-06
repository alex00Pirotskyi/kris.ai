# Worker mission commands

```text
Take the repo. You are Worker A. Take MISSION-001 and continue autonomously.
Take the repo. You are Worker B. Take MISSION-002 and continue autonomously.
Take the repo. You are Worker C. Take MISSION-004 and continue autonomously.
Take the repo. You are Worker D. Take MISSION-003 and continue autonomously.
Take the repo. You are Worker E. Take MISSION-010 and continue autonomously.
Take the repo. You are Worker F. Take MISSION-005 and continue autonomously.
Take the repo. You are Worker J. Take MISSION-015 and continue autonomously.
```

For transfer: the current executor records a final checkpoint, changes state to `YIELDED`, removes or supersedes the active claim, and names the exact next action. The replacement creates a new claim after collision and live-state validation.
