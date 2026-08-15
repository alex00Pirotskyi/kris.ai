#!/usr/bin/env python3
"""Machine-observed, network-free source gate for P4-001."""
from __future__ import annotations

import argparse
import ast
import contextlib
import datetime as dt
import hashlib
import io
import json
import pathlib
import sys
import time
import unittest
from typing import Iterable

MODULE_ID = "tm.p4-001.search-provider-interface"
TASK_ID = "P4-001"
CANONICAL_STATUS = "CANONICAL_TEST_CENTER_V1"

REQUIRED = (
    "config/test_center_registry.v1.json",
    "schemas/test_center.v1.json",
    "schemas/web_search_request.v1.json",
    "schemas/web_search_page.v1.json",
    "schemas/web_search_error.v1.json",
    "services/research_worker/src/search/validation.py",
    "services/research_worker/src/search/models.py",
    "services/research_worker/src/search/provider.py",
    "services/research_worker/src/search/fixture_provider.py",
    "services/research_worker/test/schema_validator.py",
    "services/research_worker/test/support.py",
    "services/research_worker/test/test_contract_models.py",
    "services/research_worker/test/test_fixture_provider.py",
    "services/research_worker/test/test_contract_regressions.py",
    "services/research_worker/test/test_normalized_result_adapter.py",
    "services/research_worker/test/fixtures/p4_001_search_provider/contract_cases.json",
    "release/evidence/P4-001/history/test-center-handoff.provisional.0.1.1.json",
    "release/evidence/P4-001/test-center-handoff.json",
    "tool/p4_001_test_center_v1.py",
)
PRODUCTION_SOURCES = (
    "services/research_worker/src/search/validation.py",
    "services/research_worker/src/search/models.py",
    "services/research_worker/src/search/provider.py",
    "services/research_worker/src/search/fixture_provider.py",
)
FORBIDDEN_PRODUCTION_IMPORTS = {
    "aiohttp",
    "ftplib",
    "http.client",
    "httpx",
    "playwright",
    "psutil",
    "requests",
    "selenium",
    "socket",
    "sqlite3",
    "ssl",
    "subprocess",
    "urllib.request",
}

STABLE_TESTS: dict[str, tuple[str, ...]] = {
    "tc.p4-001.request-schema": (
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_schema_documents_are_valid_draft_2020_12",
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_negative_request_vectors_fail",
    ),
    "tc.p4-001.result-schema": (
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_schema_negative_instances_are_rejected",
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_every_fixture_case_is_unique_and_executed",
    ),
    "tc.p4-001.page-schema": (
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_every_fixture_case_is_unique_and_executed",
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_invalid_cursor_is_typed_and_bound",
    ),
    "tc.p4-001.provider-error-schema": (
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_every_fixture_case_is_unique_and_executed",
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_invalid_cursor_is_typed_and_bound",
    ),
    "tc.p4-001.url-fail-closed": (
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_result_url_validation_fails_closed",
    ),
    "tc.p4-001.credential-rejection": (
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_result_url_credentials_are_rejected",
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_request_has_no_authority_or_credential_channel",
    ),
    "tc.p4-001.secret-normalization": (
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_provider_metadata_rejects_secret_bearing_keys",
        "services.research_worker.test.test_contract_models.SearchContractModelsTest.test_secret_key_normalization_fails_closed",
    ),
    "tc.p4-001.provider-metadata-isolation": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_provider_metadata_cannot_redefine_authority_fields",
    ),
    "tc.p4-001.stable-query-identity": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_query_identity_excludes_request_pagination_and_page_size",
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_query_identity_includes_semantic_filters",
    ),
    "tc.p4-001.stable-result-identity": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_result_identity_is_stable_and_provider_query_url_bound",
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_duplicate_result_identity_and_rank_are_rejected",
    ),
    "tc.p4-001.cursor-provider-binding": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_cursor_is_bound_to_provider_query_and_contract",
    ),
    "tc.p4-001.capability-negotiation": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_capability_mismatches_are_typed",
    ),
    "tc.p4-001.rate-limit-representation": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_rate_limit_representation_is_typed_and_bounded",
    ),
    "tc.p4-001.partial-failure-representation": (
        "services.research_worker.test.test_contract_regressions.P4001RegressionTest.test_partial_failure_representation_is_typed",
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_every_fixture_case_is_unique_and_executed",
    ),
    "tc.p4-001.fixture-provider-parity": (
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_two_fixture_providers_share_contract_shape",
    ),
    "tc.p4-001.network-free-determinism": (
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_fixture_execution_is_network_free",
    ),
    "tc.p4-001.unfetched-snippet-classification": (
        "services.research_worker.test.test_fixture_provider.FixtureProviderContractTest.test_every_fixture_case_is_unique_and_executed",
    ),
    "tc.p4-001.normalized-result-state-preservation": (
        "services.research_worker.test.test_normalized_result_adapter.NormalizedResultAdapterTest.test_preserves_every_canonical_state_without_upgrade",
    ),
}


def utc_now() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_suite(suite: unittest.TestSuite) -> tuple[unittest.TestResult, str, int]:
    output = io.StringIO()
    started_ns = time.monotonic_ns()
    with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
        result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    duration_ms = max(0, (time.monotonic_ns() - started_ns) // 1_000_000)
    return result, output.getvalue(), duration_ms


def imported_modules(tree: ast.AST) -> set[str]:
    modules: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.add(node.module)
    return modules


def validate_canonical_registration(project: pathlib.Path) -> tuple[bool, str]:
    registry_path = project / "config/test_center_registry.v1.json"
    handoff_path = project / "release/evidence/P4-001/test-center-handoff.json"
    history_path = (
        project
        / "release/evidence/P4-001/history/test-center-handoff.provisional.0.1.1.json"
    )
    try:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
        handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
        historical = json.loads(history_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return False, f"canonical registration unreadable: {exc}"

    if registry.get("schemaVersion") != "1.0.0":
        return False, "canonical registry schemaVersion mismatch"
    modules = {
        item.get("moduleId"): item
        for item in registry.get("testModules", [])
        if isinstance(item, dict)
    }
    module = modules.get(MODULE_ID)
    if module is None:
        return False, "canonical P4-001 module is not registered"
    case_ids = [
        item.get("testId")
        for item in registry.get("testCases", [])
        if isinstance(item, dict) and item.get("moduleId") == MODULE_ID
    ]
    profile_ids = [
        item.get("stableCheckId")
        for item in registry.get("projectTestProfiles", [])
        if isinstance(item, dict)
        and str(item.get("stableCheckId", "")).startswith("tc.p4-001.")
    ]
    expected = list(STABLE_TESTS)
    if case_ids != expected or profile_ids != expected:
        return (
            False,
            f"canonical IDs mismatch: cases={case_ids!r}, profiles={profile_ids!r}",
        )
    if handoff.get("canonicalContractStatus") != CANONICAL_STATUS:
        return False, "canonical handoff status mismatch"
    if handoff.get("moduleId") != MODULE_ID:
        return False, "canonical handoff module mismatch"
    if handoff.get("canonicalTestIds") != expected:
        return False, "canonical handoff stable IDs mismatch"
    aliases = handoff.get("provisionalIdAliases")
    if not isinstance(aliases, dict) or sorted(aliases.values()) != sorted(expected):
        return False, "provisional-to-canonical alias map is incomplete"
    superseded = handoff.get("supersedes")
    if (
        not isinstance(superseded, dict)
        or superseded.get("status") != "SUPERSEDED"
        or superseded.get("historicalPath")
        != "release/evidence/P4-001/history/test-center-handoff.provisional.0.1.1.json"
        or superseded.get("sha256") != sha256(history_path)
    ):
        return False, "historical provisional handoff binding mismatch"
    if historical.get("canonicalContractStatus") != "BLOCKED_BY_SHARED_CONTRACT":
        return False, "historical provisional handoff bytes are not preserved"
    return (
        True,
        f"module={MODULE_ID}, stableIds={len(expected)}, historicalSha256={sha256(history_path)}",
    )


def selected_test_ids(values: Iterable[str]) -> list[str]:
    values = list(values)
    if not values:
        return list(STABLE_TESTS)
    unknown = sorted(set(values) - set(STABLE_TESTS))
    if unknown:
        raise ValueError(f"unknown canonical test IDs: {unknown}")
    return [test_id for test_id in STABLE_TESTS if test_id in set(values)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    parser.add_argument("--test-id", action="append", default=[])
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    requested_ids = selected_test_ids(args.test_id)
    started_at = utc_now()
    started_ns = time.monotonic_ns()
    assertions: list[dict[str, object]] = []

    missing = [path for path in REQUIRED if not (project / path).is_file()]
    assertions.append(
        {
            "id": "p4-001.files-present",
            "passed": not missing,
            "detail": f"missing={missing}",
        }
    )

    syntax_errors: list[str] = []
    forbidden: list[str] = []
    for relative in REQUIRED:
        path = project / relative
        if path.suffix != ".py" or not path.is_file():
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=relative)
        except SyntaxError as exc:
            syntax_errors.append(f"{relative}:{exc.lineno}:{exc.msg}")
            continue
        if relative in PRODUCTION_SOURCES:
            for module in imported_modules(tree):
                if module in FORBIDDEN_PRODUCTION_IMPORTS:
                    forbidden.append(f"{relative}:{module}")
    assertions.extend(
        (
            {
                "id": "p4-001.python-syntax",
                "passed": not syntax_errors,
                "detail": f"errors={syntax_errors}",
            },
            {
                "id": "p4-001.production-dependency-boundary",
                "passed": not forbidden,
                "detail": f"forbiddenImports={forbidden}",
            },
        )
    )

    registration_passed, registration_detail = (
        validate_canonical_registration(project)
        if not missing
        else (False, "required files missing")
    )
    assertions.append(
        {
            "id": "p4-001.canonical-test-center-registration",
            "passed": registration_passed,
            "detail": registration_detail,
        }
    )

    sys.path.insert(0, str(project))
    full_result: unittest.TestResult | None = None
    full_output = ""
    full_duration_ms = 0
    if not args.test_id:
        full_suite = unittest.defaultTestLoader.discover(
            str(project / "services/research_worker/test"), pattern="test_*.py"
        )
        full_result, full_output, full_duration_ms = run_suite(full_suite)
        assertions.append(
            {
                "id": "p4-001.full-source-suite",
                "passed": full_result.wasSuccessful(),
                "detail": (
                    f"testsRun={full_result.testsRun}, "
                    f"failures={len(full_result.failures)}, "
                    f"errors={len(full_result.errors)}, "
                    f"skipped={len(full_result.skipped)}"
                ),
            }
        )

    semantic_results: list[dict[str, object]] = []
    for test_id in requested_ids:
        selectors = STABLE_TESTS[test_id]
        suite = unittest.defaultTestLoader.loadTestsFromNames(selectors)
        result, output, duration_ms = run_suite(suite)
        expected = len(selectors)
        passed = result.wasSuccessful() and result.testsRun == expected
        state = "PASS" if passed else "FAIL"
        semantic_results.append(
            {
                "testId": test_id,
                "resultState": state,
                "exitCode": 0 if passed else 1,
                "selectors": list(selectors),
                "testsRun": result.testsRun,
                "expectedTests": expected,
                "failures": len(result.failures),
                "errors": len(result.errors),
                "skipped": len(result.skipped),
                "durationMillis": duration_ms,
                "output": output,
            }
        )
        assertions.append(
            {
                "id": test_id,
                "passed": passed,
                "detail": (
                    f"testsRun={result.testsRun}/{expected}, "
                    f"failures={len(result.failures)}, "
                    f"errors={len(result.errors)}, "
                    f"skipped={len(result.skipped)}"
                ),
            }
        )

    passed = all(bool(item["passed"]) for item in assertions)
    ended_at = utc_now()
    duration_ms = max(0, (time.monotonic_ns() - started_ns) // 1_000_000)
    report = {
        "schemaVersion": "2.0.0",
        "taskId": TASK_ID,
        "moduleId": MODULE_ID,
        "canonicalContractStatus": CANONICAL_STATUS,
        "classification": "P4-001_SOURCE_IMPLEMENTATION_COMPLETE",
        "assuranceClass": "source_contract",
        "resultState": "PASS" if passed else "FAIL",
        "exitCode": 0 if passed else 1,
        "startedAt": started_at,
        "endedAt": ended_at,
        "durationMillis": duration_ms,
        "selectedTestIds": requested_ids,
        "testsRun": full_result.testsRun if full_result is not None else sum(
            int(item["testsRun"]) for item in semantic_results
        ),
        "fullSuiteDurationMillis": full_duration_ms,
        "failures": len(full_result.failures) if full_result is not None else sum(
            int(item["failures"]) for item in semantic_results
        ),
        "errors": len(full_result.errors) if full_result is not None else sum(
            int(item["errors"]) for item in semantic_results
        ),
        "skipped": len(full_result.skipped) if full_result is not None else sum(
            int(item["skipped"]) for item in semantic_results
        ),
        "networkUsage": "none_observed_and_runtime_denied",
        "assertions": assertions,
        "semanticResults": semantic_results,
        "sourceHashes": {
            path: sha256(project / path)
            for path in REQUIRED
            if (project / path).is_file()
        },
        "unittestOutput": full_output,
        "completionEligible": False,
        "completionReason": (
            "Source foundation only. Exact-head tri-platform evidence, Worker B review, "
            "Worker I security review, and Worker J no-conflict remain separate gates."
        ),
        "supportClaimBoundary": {
            "capabilitySupport": "SOURCE_FOUNDATION",
            "behaviorSupportEstablished": False,
            "liveProviderBehaviorCertified": False,
            "networkRetrievalImplemented": False,
            "fetchImplemented": False,
            "citationsImplemented": False,
            "browserImplemented": False,
            "datasetsImplemented": False,
            "releaseSupported": False,
        },
    }
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        target = pathlib.Path(args.json_output)
        if not target.is_absolute():
            target = project / target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
