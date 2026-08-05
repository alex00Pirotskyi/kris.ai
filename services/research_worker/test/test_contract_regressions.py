from __future__ import annotations
import unittest
from services.research_worker.src.search import SearchContractError, SearchPage, SearchProviderException, SearchRateLimit, SearchRequest, SearchResult, stable_result_id
from services.research_worker.src.search.fixture_provider import DeterministicFixtureSearchProvider, FixtureCatalogEntry, fixture_provider_a, fixture_provider_b
NOW = '2026-08-05T00:00:00Z'
ENTRIES = (
    FixtureCatalogEntry('One', 'https://docs.example.org/one', 'one', None, 'en', 'US', {'sourceClass': 'fixture'}),
    FixtureCatalogEntry('Two', 'https://docs.example.org/two', 'two', None, 'en', 'US', {'sourceClass': 'fixture'}),
    FixtureCatalogEntry('Three', 'https://docs.example.org/three', 'three', None, 'en', 'US', {'sourceClass': 'fixture'}),
)

class P4001RegressionTest(unittest.TestCase):
    def test_query_identity_excludes_request_pagination_and_page_size(self):
        a = SearchRequest('req_a', 'fixture:all', limit=1)
        b = SearchRequest('req_b', 'fixture:all', limit=25, cursor='opaque')
        self.assertEqual(a.query_id, b.query_id)

    def test_query_identity_includes_semantic_filters(self):
        base = SearchRequest('req', 'fixture:all')
        self.assertNotEqual(base.query_id, SearchRequest('req2', 'fixture:all', language='en').query_id)
        self.assertNotEqual(base.query_id, SearchRequest('req3', 'fixture:all', safe_search='strict').query_id)

    def test_cursor_is_bound_to_provider_query_and_contract(self):
        alpha = fixture_provider_a(ENTRIES)
        beta = fixture_provider_b(ENTRIES)
        request = SearchRequest('req', 'fixture:all', limit=1)
        first = alpha.search(request)
        self.assertIsNotNone(first.next_cursor)
        second = alpha.search(SearchRequest('req2', 'fixture:all', limit=2, cursor=first.next_cursor))
        self.assertEqual(2, second.results[0].provider_rank)
        with self.assertRaises(SearchProviderException) as provider_mismatch:
            beta.search(SearchRequest('req3', 'fixture:all', limit=1, cursor=first.next_cursor))
        self.assertEqual('cursor_provider_mismatch', provider_mismatch.exception.error.diagnostic_code)
        with self.assertRaises(SearchProviderException) as query_mismatch:
            alpha.search(SearchRequest('req4', 'different query', limit=1, cursor=first.next_cursor))
        self.assertEqual('cursor_query_mismatch', query_mismatch.exception.error.diagnostic_code)
        broken = first.next_cursor.replace('p4c1.', 'p4c0.', 1)
        with self.assertRaises(SearchProviderException):
            alpha.search(SearchRequest('req5', 'fixture:all', limit=1, cursor=broken))

    def test_duplicate_result_identity_and_rank_are_rejected(self):
        query = SearchRequest('req', 'fixture:all').query_id
        result = SearchResult(stable_result_id('fixture_alpha', query, ENTRIES[0].url), 'fixture_alpha', 1, 'One', ENTRIES[0].url, ENTRIES[0].url, 'one', None, query, NOW, {})
        with self.assertRaises(SearchContractError):
            SearchPage('req', 'fixture_alpha', 'provider_req', (result, result), None, SearchRateLimit(None, None, None), None, NOW)

    def test_provider_metadata_cannot_redefine_authority_fields(self):
        provider = fixture_provider_a((FixtureCatalogEntry('Unsafe', 'https://docs.example.org/unsafe', 'unsafe', None, 'en', 'US', {'evidenceStatus': 'fetched_evidence'}),))
        with self.assertRaises(SearchContractError):
            provider.search(SearchRequest('req', 'fixture:all'))

    def test_capability_mismatches_are_typed(self):
        provider = DeterministicFixtureSearchProvider(provider_id='limited', entries=ENTRIES, supports_domain_exclude=True, supports_freshness=False, supports_safe_search=False)
        cases = (
            (SearchRequest('r1', 'fixture:all', language='fr'), 'language_not_supported'),
            (SearchRequest('r2', 'fixture:all', country='FR'), 'country_not_supported'),
            (SearchRequest('r3', 'fixture:all', freshness={'mode': 'any', 'after': None, 'before': None}), 'freshness_not_supported'),
            (SearchRequest('r4', 'fixture:all', safe_search='strict'), 'safe_search_not_supported'),
        )
        for request, diagnostic in cases:
            with self.assertRaises(SearchProviderException) as caught:
                provider.search(request)
            self.assertEqual('unsupported_filter', caught.exception.error.code)
            self.assertEqual(diagnostic, caught.exception.error.diagnostic_code)

if __name__ == '__main__':
    unittest.main()
