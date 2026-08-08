from __future__ import annotations

import copy
import unittest

from services.research_worker.src.search import (
    SearchContractError,
    SearchRequest,
    SearchResult,
    canonical_json,
    stable_result_id,
)
from services.research_worker.src.search.fixture_provider import FixtureCatalogEntry, fixture_provider_a
from services.research_worker.test.schema_validator import validate_schema_document
from services.research_worker.test.support import load_contract_state


class SearchContractModelsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fixture, cls.schemas, cls.validators, cls.providers = load_contract_state()

    def test_schema_documents_are_valid_draft_2020_12(self) -> None:
        for schema in self.schemas.values():
            validate_schema_document(schema)

    def test_serialization_is_stable_and_strict(self) -> None:
        request = SearchRequest.from_dict(self.fixture["cases"][0]["request"])
        self.assertEqual(canonical_json(request.to_dict()), canonical_json(request.to_dict()))
        for value in (float("nan"), float("inf"), float("-inf")):
            with self.assertRaises(SearchContractError):
                canonical_json({"authority": value})

    def test_request_domain_normalization_does_not_mutate_query(self) -> None:
        request = SearchRequest(
            request_id="req_normalize",
            query="A+B order:sensitive",
            domains={"include": ["Docs.Example.Org."], "exclude": []},
        )
        payload = request.to_dict()
        self.assertEqual("A+B order:sensitive", payload["query"])
        self.assertEqual(["docs.example.org"], payload["domains"]["include"])

    def test_negative_request_vectors_fail(self) -> None:
        base = copy.deepcopy(self.fixture["cases"][0]["request"])
        observed = set()
        for case in self.fixture["negativeRequests"]:
            payload = copy.deepcopy(base)
            payload.update(case.get("mutation", {}))
            payload.update(case.get("replace", {}))
            with self.assertRaises(SearchContractError):
                SearchRequest.from_dict(payload)
            observed.add(case["id"])
        self.assertEqual(
            {case["id"] for case in self.fixture["negativeRequests"]}, observed
        )

    def test_schema_negative_instances_are_rejected(self) -> None:
        request = copy.deepcopy(self.fixture["cases"][0]["request"])
        request["rawToken"] = "forbidden"
        self.assertTrue(list(self.validators["request"].iter_errors(request)))

        page = self.providers["fixture_alpha"].search(
            SearchRequest.from_dict(self.fixture["cases"][0]["request"])
        ).to_dict()
        page["results"][0]["evidenceStatus"] = "fetched_evidence"
        self.assertTrue(list(self.validators["page"].iter_errors(page)))

        for unsafe_url in (
            "https://user:pass@docs.example.org/private",
            "https://127.0.0.1/private",
            "https://localhost/private",
            "https://docs.example.org/result#fragment",
        ):
            unsafe_page = self.providers["fixture_alpha"].search(
                SearchRequest.from_dict(self.fixture["cases"][0]["request"])
            ).to_dict()
            unsafe_page["results"][0]["url"] = unsafe_url
            with self.subTest(unsafe_url=unsafe_url):
                self.assertTrue(list(self.validators["page"].iter_errors(unsafe_page)))

        error = {
            "schemaVersion": "1.0.0",
            "requestId": "req_error",
            "providerId": "fixture_alpha",
            "code": "throttled",
            "retryable": True,
            "safeMessage": "Retry later.",
            "retryAfterMs": -1,
            "diagnosticCode": "fixture",
        }
        self.assertTrue(list(self.validators["error"].iter_errors(error)))

    def test_provider_metadata_rejects_secret_bearing_keys(self) -> None:
        provider = fixture_provider_a((
            FixtureCatalogEntry(
                title="Unsafe",
                url="https://docs.example.org/unsafe",
                snippet="Unsafe metadata fixture.",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={"apiToken": "must-not-pass"},
            ),
        ))
        with self.assertRaises(SearchContractError):
            provider.search(SearchRequest(request_id="req_secret", query="fixture:all"))

    def test_secret_key_normalization_fails_closed(self) -> None:
        for key in ("API-TOKEN", "client secret", "private.key", "auth_orization"):
            provider = fixture_provider_a((
                FixtureCatalogEntry(
                    title="Unsafe",
                    url="https://docs.example.org/unsafe",
                    snippet="Unsafe metadata fixture.",
                    published_at=None,
                    language="en",
                    country="US",
                    provider_metadata={key: "must-not-pass"},
                ),
            ))
            with self.subTest(key=key), self.assertRaises(SearchContractError):
                provider.search(SearchRequest(request_id="req_secret", query="fixture:all"))

    def test_result_url_credentials_are_rejected(self) -> None:
        provider = fixture_provider_a((
            FixtureCatalogEntry(
                title="Credential URL",
                url="https://user:pass@docs.example.org/private",
                snippet="Must be rejected.",
                published_at=None,
                language="en",
                country="US",
                provider_metadata={},
            ),
        ))
        with self.assertRaises(SearchContractError):
            provider.search(SearchRequest(request_id="req_url", query="fixture:all"))

    def test_result_url_validation_fails_closed(self) -> None:
        request = SearchRequest(request_id="req_url_matrix", query="fixture:all")
        for url in (
            "ftp://docs.example.org/result",
            "https://docs.example.org/result#fragment",
            "https:///missing-host",
            "https://127.0.0.1/private",
            "https://10.0.0.1/private",
            "https://localhost/private",
            "https://service.localhost/private",
            "https://docs.example.org:0/private",
            "https://docs.example.org:70000/private",
            "https://docs.example.org/private path",
            "https://docs.example.org\\private",
        ):
            with self.subTest(url=url), self.assertRaises(SearchContractError):
                SearchResult(
                    stable_result_id("fixture_alpha", request.query_id, "https://docs.example.org/safe"),
                    "fixture_alpha",
                    1,
                    "Unsafe URL",
                    url,
                    url,
                    "Must be rejected.",
                    None,
                    request.query_id,
                    "2026-08-05T00:00:00Z",
                    {},
                )

    def test_request_has_no_authority_or_credential_channel(self) -> None:
        serialized = canonical_json(
            SearchRequest(request_id="req_boundary", query="contract boundary").to_dict()
        ).casefold()
        for forbidden in (
            "grant", "owner", "authorization", "cookie", "apikey",
            "secret", "password",
        ):
            self.assertNotIn(forbidden, serialized)


if __name__ == "__main__":
    unittest.main()
