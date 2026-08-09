# P2-004 — Automation host technology selection

## Contract

Select the P2 automation-host architecture using real measured startup, memory,
packaging footprint, reliability and PTY viability on Windows, macOS and Linux.

## Corrected done condition

P2-004 is DONE when an exact reviewed tri-platform measurement selects an
automation-host technology. It does not certify the complete interactive PTY or
process-tree feature set for every rejected architecture.

Production proof remains downstream:

- P2-005 — interactive PTY, attach/detach/reconnect/transcript/ANSI/resize.
- P2-006 — stable process identity, descendants, stop/kill and no surviving
  descendants.

## Governed selection artifacts

- `docs/adr/ADR-0012-p2-automation-host.md`
- `tool/p2_004_technology_selection.py`
- `tool/p2_004_technology_selection_test.py`
- `.github/workflows/p2-004-technology-selection.yml`
- `release/evidence/P2-004/manifest.json`

The existing automation host under `automation_host/` is measured without
modification by this corrective slice.

## Current assurance status

The clean corrective candidate begins as selection-pending. Source presence or
hosted setup alone is not acceptance evidence. P2-004 becomes eligible for
acceptance only after the exact candidate produces successful Windows 2025,
macOS 15 and Ubuntu 24.04 measurements, the aggregate selects a candidate, exact
Product validation is green, and the exact measured decision receives required
review.

P1-012 is already completed and owner-approved on protected main; it is not a
live P3 blocker. P3 remains gated on P2-004 acceptance until this selection
closes.
