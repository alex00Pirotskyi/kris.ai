# Stage B CI closure V41

- **Scope:** cumulative P0-001 through P0-010
- **Base Stage B SHA:** `a8a299b665fa2536e35cb757c966105a452a77c3`
- **Failed run:** `30216928276`
- **Ubuntu/macOS boundary:** `P0-003 integration repair`
- **Windows boundary:** `Validate locked toolchain`

## Repair

1. Windows batch launchers are executed through `COMSPEC` only when the resolved executable is `.bat` or `.cmd`.
2. The P0-003 workflow validator now checks semantic indentation containment and still requires all reviewed commands, ordering, strict analyzer/test flags, and stable tri-OS jobs.
3. `STATUS.md` is normalized to exactly one terminal LF.

The machine-readable record is `STAGE_B_CI_REPAIR_V41.json`. This closes the P0 integration line and does not claim future P1 implementation.
