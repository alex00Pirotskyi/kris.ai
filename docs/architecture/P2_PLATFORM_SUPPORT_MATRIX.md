# P2 V63 platform support and proof matrix

Every row is a gate, not a marketing claim. Source presence, interface definitions, and unit tests do not replace target-platform behavior. `blocked`, `unsupported`, `source_only`, and `not_tested` cannot be promoted to `passed` by the finalizer.

| Operation | Windows implementation | macOS implementation | Linux implementation | Required proof |
|---|---|---|---|---|
| Absolute filesystem | drive/UNC/extended paths; final-target identity checks | root/mounted volumes; final-target identity checks | root/mounted volumes; final-target identity checks | task-specific path, Unicode, hidden, long-path, link/race, transaction and recovery receipt |
| Finite process | direct process + Job Object registration | direct process + dedicated group | direct process + dedicated group | cwd/env/output/timeout/cancel/descendant receipt |
| PTY | node-pty ConPTY | node-pty Unix PTY | node-pty Unix PTY | input/resize/ANSI/Unicode/attach/reconnect receipt |
| Descendant kill | persistent Job Object supervisor | PID/PGID/UID/start-token watchdog | PID/PGID/UID/start-token watchdog | parent death, PID reuse, timeout and forced-kill receipt |
| Packages/SDKs | npm controlled fixture; approved native manager adapter | npm controlled fixture; approved brew adapter | npm controlled fixture; detected approved manager adapter | dry-run, fixture apply/remove, SDK provenance and target-image receipt |
| Services/apps | SCM plus stable process identity | launchd plus stable process identity | detected init plus stable process identity | status/start/stop/open/close or honest typed unsupported result |
| Clipboard/screen | interactive native desktop | interactive native desktop with TCC | interactive X11/Wayland backend | clipboard round-trip, nonempty capture, redaction/no-log-leak receipt |
| Restore points | approved native support only | typed unsupported unless proven | typed unsupported unless proven | reversibility and injected-failure recovery receipt |

Generic headless runners are expected to report P2-009 as `blocked`. P2 completion requires suitable target desktop runners; the launcher will not reinterpret a headless failure as proof.
