#!/usr/bin/env python3
"""Closed-scope Mission Execution 1.5 delivery-control compatibility entry point."""
from __future__ import annotations

import mission_delivery_control as control

EXACT_V15_CONTROL_PATTERNS = (
    "config/mission_delivery.v1.json",
    "docs/roadmap/missions/landing-validations/requests/*.json",
    "tool/branch_hygiene.py",
)


def install_exact_v15_control_scope() -> None:
    control.V15_CONTROL_PATTERNS = tuple(
        dict.fromkeys(
            (
                *control.V15_CONTROL_PATTERNS,
                *EXACT_V15_CONTROL_PATTERNS,
            )
        )
    )


install_exact_v15_control_scope()


if __name__ == "__main__":
    raise SystemExit(control.main())
