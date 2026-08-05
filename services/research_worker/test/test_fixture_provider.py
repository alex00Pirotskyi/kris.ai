from __future__ import annotations

import unittest

from services.research_worker.src.search import SearchProviderException, SearchRequest
from services.research_worker.test.support import load_contract_state


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


if __name__ == "__main__":
    unittest.main()
