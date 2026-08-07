from __future__ import annotations

import socket
import unittest
from unittest import mock

from services.research_worker.src.search import (
    SearchContractError,
    SearchPage,
    SearchProvider,
    SearchProviderCapabilities,
    SearchProviderException,
    SearchRateLimit,
    SearchRequest,
    SearchResult,
)
from services.research_worker.src.search.fixture_provider import (
    DeterministicFixtureSearchProvider,
    FixtureCatalogEntry,
)
from services.research_worker.test.support import load_contract_state

_FIXED_RETRIEVED_AT = "2026-08-05T00:00:00Z"


class AdversarialSearchProvider(SearchProvider):
    """Schema-valid pages used to prove the public provider gate fails closed."""

    def __init__(self, mode: str):
        self.mode = mode
        self._capabilities = SearchProviderCapabilities(
            provider_id="fixture_adversarial",
            max_page_size=25,
        )

    @property
    def capabilities(self) -> SearchProviderCapabilities:
        return self._capabilities

    def _result(
        self,
        request: SearchRequest,
        *,
        index: int,
        query_id: str,
        provider_id: str,
    ) -> SearchResult:
        return SearchResult(
            result_id=f"res_adversarial_{index}",
            provider_id=provider_id,
            provider_rank=index,
            title=f"Adversarial result {index}",
            url=f"https://example.com/result-{index}",
            display_url=f"https://example.com/result-{index}",
            snippet="deterministic correlation fixture",
            published_at=None,
            query_id=query_id,
            retrieved_at=_FIXED_RETRIEVED_AT,
            provider_metadata={},
        )

    def _search(self, request: SearchRequest) -> SearchPage:
        page_request_id = (
            "req_foreign" if self.mode == "wrong_request" else request.request_id
        )
        page_provider_id = (
            "fixture_foreign"
            if self.mode == "wrong_provider"
            else self.capabilities.provider_id
        )
        count = 2 if self.mode in {"over_limit", "mixed_query"} else 1
        results = []
        for index in range(1, count + 1):
            query_id = request.query_id
            if self.mode == "wrong_query":
                query_id = "qry_foreign"
            elif self.mode == "mixed_query" and index == count:
                query_id = "qry_foreign"
            results.append(
                self._result(
                    request,
                    index=index,
                    query_id=query_id,
                    provider_id=page_provider_id,
                )
            )
        return SearchPage(
            request_id=page_request_id,
            provider_id=page_provider_id,
            provider_request_id="provider_req_adversarial",
            results=tuple(results),
            next_cursor=None,
            rate_limit=SearchRateLimit(None, None, None),
            partial_failure=None,
            retrieved_at=_FIXED_RETRIEVED_AT,
        )


class FixtureProviderContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture, _, cls.validators, cls.providers = load_contract_state()

    def validate(self, schema_name: str, instance) -> None:
        errors = sorted(
            self.validators[schema_name].iter_errors(instance),
            key=lambda error: list(error.absolute_path),
        )
        self.assertEqual([], [error.message for error in errors])

    def _freshness_providers(self):
        entries = (
            FixtureCatalogEntry(
                title="Day one",
                url="https://example.com/day-1",
                snippet="freshness fixture",
                published_at="2026-01-01T00:00:00Z",
                language="en",
                country="US",
                provider_metadata={},
            ),
            FixtureCatalogEntry(
                title="Day two",
                url="https://example.com/day-2",
                snippet="freshness fixture",
                published_at="2026-01-02T00:00:00Z",
                language="en",
                country="US",
                provider_metadata={},
            ),
            FixtureCatalogEntry(
                title="Day three",
                url="https://example.com/day-3",
                snippet="freshness fixture",
                published_at="2026-01-03T00:00:00Z",
                language="en",
                country="US",
                provider_metadata={},
            ),
            FixtureCatalogEntry(
                title="Undated",
                url="https://example.com/undated",
                snippet="freshness fixture",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
            ),
        )
        return (
            DeterministicFixtureSearchProvider(
                provider_id="freshness_alpha",
                entries=entries,
                supports_domain_exclude=True,
            ),
            DeterministicFixtureSearchProvider(
                provider_id="freshness_beta",
                entries=entries,
                supports_domain_exclude=False,
            ),
        )

    def _freshness_results(self, provider, *, mode, after=None, before=None):
        request = SearchRequest(
            request_id=f"req_freshness_{provider.capabilities.provider_id}_{mode}",
            query="fixture:all",
            limit=10,
            freshness={"mode": mode, "after": after, "before": before},
        )
        return [result.published_at for result in provider.search(request).results]

    def _safe_search_providers(self):
        entries = (
            FixtureCatalogEntry(
                title="Off only",
                url="https://example.com/off-only",
                snippet="safe-search fixture",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
                safety_tier="off",
            ),
            FixtureCatalogEntry(
                title="Moderate safe",
                url="https://example.com/moderate-safe",
                snippet="safe-search fixture",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
                safety_tier="moderate",
            ),
            FixtureCatalogEntry(
                title="Strict safe",
                url="https://example.com/strict-safe",
                snippet="safe-search fixture",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
                safety_tier="strict",
            ),
        )
        return (
            DeterministicFixtureSearchProvider(
                provider_id="safe_alpha",
                entries=entries,
                supports_domain_exclude=True,
            ),
            DeterministicFixtureSearchProvider(
                provider_id="safe_beta",
                entries=entries,
                supports_domain_exclude=False,
            ),
        )

    def _safe_search_titles(self, provider, *, mode, limit=10):
        request = SearchRequest(
            request_id=f"req_safe_{provider.capabilities.provider_id}_{mode}_{limit}",
            query="fixture:all",
            limit=limit,
            safe_search=mode,
        )
        page = provider.search(request)
        return page, [result.title for result in page.results]

    def test_every_fixture_case_is_unique_and_executed(self) -> None:
        cases = self.fixture["cases"]
        ids = [case["id"] for case in cases]
        self.assertEqual(len(ids), len(set(ids)))
        executed = set()
        for case in cases:
            executed.add(case["id"])
            request = SearchRequest.from_dict(case["request"])
            self.validate("request", request.to_dict())
            provider_ids = case.get("providers") or [case["provider"]]
            for provider_id in provider_ids:
                provider = self.providers[provider_id]
                if case["kind"] in {"error", "provider_specific_error"}:
                    with self.assertRaises(SearchProviderException) as caught:
                        provider.search(request)
                    self.assertEqual(case["expectedCode"], caught.exception.error.code)
                    self.validate("error", caught.exception.error.to_dict())
                    continue
                page = provider.search(request)
                self.validate("page", page.to_dict())
                self.assertEqual(provider_id, page.provider_id)
                self.assertTrue(all(
                    result.to_dict()["evidenceStatus"] == "unfetched_snippet_only"
                    for result in page.results
                ))
                if case["kind"] == "partial":
                    self.assertIsNotNone(page.partial_failure)
                if case["kind"] == "pagination":
                    self._assert_second_page(provider, request, page)
        self.assertEqual(set(ids), executed)

    def _assert_second_page(self, provider, request, page) -> None:
        self.assertIsNotNone(page.next_cursor)
        second_request = SearchRequest(
            request_id="req_page_second",
            query=request.query,
            limit=request.limit,
            cursor=page.next_cursor,
            language=request.language,
            country=request.country,
            safe_search=request.safe_search,
            freshness=request.freshness,
            domains=request.domains,
        )
        second_page = provider.search(second_request)
        self.validate("page", second_page.to_dict())
        self.assertTrue(
            {item.result_id for item in page.results}.isdisjoint(
                {item.result_id for item in second_page.results}
            )
        )

    def test_two_fixture_providers_share_contract_shape(self) -> None:
        request = SearchRequest.from_dict(self.fixture["cases"][0]["request"])
        alpha = self.providers["fixture_alpha"].search(request).to_dict()
        beta = self.providers["fixture_beta"].search(request).to_dict()
        self.assertEqual(set(alpha), set(beta))
        self.assertEqual(
            [set(result) for result in alpha["results"]],
            [set(result) for result in beta["results"]],
        )
        self.validate("page", alpha)
        self.validate("page", beta)

    def test_fixture_execution_is_network_free(self) -> None:
        request = SearchRequest.from_dict(self.fixture["cases"][0]["request"])
        denied = AssertionError("P4-001 fixture provider attempted network access")
        with mock.patch.object(socket, "socket", side_effect=denied), mock.patch.object(
            socket, "create_connection", side_effect=denied
        ):
            pages = [provider.search(request) for provider in self.providers.values()]
        self.assertEqual({"fixture_alpha", "fixture_beta"}, {page.provider_id for page in pages})

    def test_invalid_cursor_is_typed_and_bound(self) -> None:
        request = SearchRequest(
            request_id="req_bad_cursor",
            query="fixture:all",
            cursor="opaque-not-offset",
        )
        with self.assertRaises(SearchProviderException) as caught:
            self.providers["fixture_alpha"].search(request)
        error = caught.exception.error
        self.assertEqual(request.request_id, error.request_id)
        self.assertEqual("fixture_alpha", error.provider_id)
        self.assertEqual("invalid_request", error.code)
        self.validate("error", error.to_dict())

    def test_provider_boundary_rejects_wrong_page_request_id(self) -> None:
        request = SearchRequest(request_id="req_expected", query="fixture:all")
        with self.assertRaisesRegex(
            SearchContractError,
            "page request identity does not match originating request",
        ):
            AdversarialSearchProvider("wrong_request").search(request)

    def test_provider_boundary_rejects_consistent_foreign_query_id(self) -> None:
        request = SearchRequest(request_id="req_expected", query="fixture:all")
        with self.assertRaisesRegex(
            SearchContractError,
            "result query identity does not match originating request",
        ):
            AdversarialSearchProvider("wrong_query").search(request)

    def test_provider_boundary_rejects_page_above_request_limit(self) -> None:
        request = SearchRequest(
            request_id="req_expected",
            query="fixture:all",
            limit=1,
        )
        with self.assertRaisesRegex(
            SearchContractError,
            "page result count exceeds originating request limit",
        ):
            AdversarialSearchProvider("over_limit").search(request)

    def test_provider_boundary_rejects_provider_identity_drift(self) -> None:
        request = SearchRequest(request_id="req_expected", query="fixture:all")
        with self.assertRaisesRegex(
            SearchContractError,
            "page provider identity does not match provider capabilities",
        ):
            AdversarialSearchProvider("wrong_provider").search(request)

    def test_page_model_rejects_mixed_query_injection(self) -> None:
        request = SearchRequest(
            request_id="req_expected",
            query="fixture:all",
            limit=2,
        )
        with self.assertRaisesRegex(SearchContractError, "multiple query identities"):
            AdversarialSearchProvider("mixed_query").search(request)

    def test_provider_subclass_cannot_override_public_search_gate(self) -> None:
        with self.assertRaisesRegex(TypeError, "must implement _search"):
            class UnsafeProvider(SearchProvider):
                @property
                def capabilities(self):
                    return SearchProviderCapabilities(provider_id="unsafe")

                def search(self, request):
                    raise AssertionError("unsafe override")

                def _search(self, request):
                    raise AssertionError("unused")

    def test_safe_search_modes_are_monotonic_and_precede_pagination(self) -> None:
        expected = {
            "off": ["Off only", "Moderate safe", "Strict safe"],
            "moderate": ["Moderate safe", "Strict safe"],
            "strict": ["Strict safe"],
        }
        for provider in self._safe_search_providers():
            for mode, titles in expected.items():
                with self.subTest(provider=provider.capabilities.provider_id, mode=mode):
                    page, actual = self._safe_search_titles(provider, mode=mode)
                    self.assertEqual(titles, actual)
                    self.assertEqual(
                        list(range(1, len(actual) + 1)),
                        [result.provider_rank for result in page.results],
                    )
            with self.subTest(
                provider=provider.capabilities.provider_id,
                mode="strict-before-pagination",
            ):
                page, titles = self._safe_search_titles(
                    provider,
                    mode="strict",
                    limit=1,
                )
                self.assertEqual(["Strict safe"], titles)
                self.assertEqual([1], [result.provider_rank for result in page.results])
                self.assertIsNone(page.next_cursor)

    def test_fixture_entry_rejects_unknown_safety_tier(self) -> None:
        with self.assertRaisesRegex(SearchContractError, "safety_tier"):
            FixtureCatalogEntry(
                title="Unknown safety",
                url="https://example.com/unknown-safety",
                snippet="safe-search fixture",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
                safety_tier="unknown",
            )

    def test_freshness_modes_and_equality_boundaries_on_two_providers(self) -> None:
        for provider in self._freshness_providers():
            with self.subTest(provider=provider.capabilities.provider_id, mode="any"):
                self.assertEqual(
                    [
                        "2026-01-01T00:00:00Z",
                        "2026-01-02T00:00:00Z",
                        "2026-01-03T00:00:00Z",
                        None,
                    ],
                    self._freshness_results(provider, mode="any"),
                )
            with self.subTest(provider=provider.capabilities.provider_id, mode="after"):
                self.assertEqual(
                    ["2026-01-03T00:00:00Z"],
                    self._freshness_results(
                        provider,
                        mode="after",
                        after="2026-01-02T00:00:00Z",
                    ),
                )
            with self.subTest(provider=provider.capabilities.provider_id, mode="before"):
                self.assertEqual(
                    ["2026-01-01T00:00:00Z"],
                    self._freshness_results(
                        provider,
                        mode="before",
                        before="2026-01-02T00:00:00Z",
                    ),
                )
            with self.subTest(provider=provider.capabilities.provider_id, mode="between"):
                self.assertEqual(
                    ["2026-01-02T00:00:00Z"],
                    self._freshness_results(
                        provider,
                        mode="between",
                        after="2026-01-01T00:00:00Z",
                        before="2026-01-03T00:00:00Z",
                    ),
                )


if __name__ == "__main__":
    unittest.main()
