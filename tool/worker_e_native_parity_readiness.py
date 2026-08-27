#!/usr/bin/env python3
"""
Always-on Product hardening. Inspect exact current Product source/tests inside allowedPaths, identify one concrete correctness, performance, reliability, UX-facing behavior, or missing-regression defect that can be proven locally, and implement the smallest durable code/test fix. Do not create documentation-only, formatting-only, governance-only, or no-op changes.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

# Import the model module to access shared constants and functions
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from worker_e_native_parity_model import (
    EVIDENCE_ROOT, FILES, INVENTORY_FRAGMENTS, MATRIX_FRAGMENTS,
    FIXTURE_FRAGMENTS, ISOLATION_FRAGMENTS, WORKER_E_DURABLE_PATHS,
    PLATFORMS, CLASSES, BEHAVIOR, SUPPORT, STABLE_IDS, REQUIRED_OPERATIONS,
    REQUIRED_FIXTURES, DEVICE_STATES, FALLBACKS, SHA40, SHA64, ReadinessError,
    _load, _safe_relative, _load_relative, _load_inventory, _load_matrix,
    _load_fixtures, _load_isolation, _unique, _require_paths, _snapshot,
    check_source_manifest, check_dependency_status, check_inventory,
    check_platform_matrix, check_no_silent_fallback
)

# Define the main function
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Worker E Native Parity Readiness Checker")
    parser.add_argument("--check", action="store_true", help="Run the checks")
    parser.add_argument("--project", default=".", help="Project directory")
    args = parser.parse_args()

    if not args.check:
        print("Usage: python3 worker_e_native_parity_readiness.py --check [--project <path>]")
        sys.exit(1)

    project = Path(args.project)
    try:
        # Run all checks
        check_source_manifest(project)
        check_dependency_status(project)
        check_inventory(project)
        check_platform_matrix(project)
        check_no_silent_fallback(project)
        print(json.dumps({"resultState": "PASS", "schemaVersion": "1.0.0"}))
    except ReadinessError as e:
        print(json.dumps({"resultState": "FAIL", "error": str(e), "schemaVersion": "1.0.0"}))
    except Exception as e:
        print(json.dumps({"resultState": "FAIL", "error": f"Unexpected error: {e}", "schemaVersion": "1.0.0"}))
