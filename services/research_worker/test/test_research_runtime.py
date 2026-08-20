from __future__ import annotations

import io
import ssl
import unittest
from datetime import datetime, timezone

from services.research_worker.src.research.runtime import (
    CrawlCheckpoint,
    CrawlLimits,
    QueryPlanner,
    ReadableExtractor,
    ResearchCrawler,
    ResearchRuntimeError,
    SafePinnedFetcher,
    StaticEvidence,
    canonicalize_url,
    rank_results,
)
from services.research_worker.src.search.models import SearchResult


class _Response:
    def __init__(self, status=200, body=b"<html><title>Fixture</title><body><h1>Hello</h1><a href='/next'>Next</a></body></html>", headers=None):
        self.status = status
        self._stream = io.BytesIO(body)
        self._headers = {key.lower(): value for key, value in (headers or {"Content-Type": "text/html"}).items()}

    def getheader(self, name):
        return self._headers.get(name.lower())

    def read(self, amount=-1):
        return self._stream.read(amount)


class _Connection:
    def __init__(self, response):
        self.response = response
        self.requests = []
        self.closed = False

    def request(self, method, path, headers=None):
        self.requests.append((method, path, dict(headers or {})))

    def getresponse(self):
        return self.response

    def close(self):
        self.closed = True


class ResearchRuntimeTest(unittest.TestCase):
    def test_query_planner_bounds_current_technical_and_compare_queries(self):
        plan = QueryPlanner().plan("Compare current Flutter BLE APIs")
        self.assertIn("Compare current Flutter BLE APIs", plan.queries)
        self.assertTrue(any("latest" in query for query in plan.queries))
        self.assertTrue(any("reference" in query for query in plan.queries))
        self.assertLessEqual(len(plan.queries), 24)

    def test_canonical_url_strips_tracking_and_ranking_dedupes(self):
        first = SearchResult(
            "r1", "fixture", 1, "Flutter BLE reference", "https://example.com/a?utm_source=x&q=1", "example.com", "BLE reference", "2026-08-19T00:00:00Z", "q1", "2026-08-20T00:00:00Z", {}
        )
        duplicate = SearchResult(
            "r2", "fixture2", 1, "Flutter BLE reference", "https://example.com/a?q=1", "example.com", "BLE reference", "2026-08-19T00:00:00Z", "q1", "2026-08-20T00:00:00Z", {}
        )
        ranked = rank_results((duplicate, first), "Flutter BLE reference", now=datetime(2026, 8, 20, tzinfo=timezone.utc))
        self.assertEqual(len(ranked), 1)
        self.assertEqual(ranked[0].canonical_url, "https://example.com/a?q=1")

    def test_pinned_fetch_uses_resolved_public_address_and_original_host(self):
        connection = _Connection(_Response())
        calls = []
        fetcher = SafePinnedFetcher(
            resolver=lambda host, port: ("93.184.216.34",),
            connection_factory=lambda host, address, port, timeout, context: (
                calls.append((host, address, port, timeout, isinstance(context, ssl.SSLContext))) or connection
            ),
        )
        evidence = fetcher.fetch("https://example.com/a")
        self.assertEqual(calls[0][0:3], ("example.com", "93.184.216.34", 443))
        self.assertEqual(connection.requests[0][2]["Host"], "example.com")
        self.assertEqual(evidence.pinned_address, "93.184.216.34")
        self.assertEqual(evidence.body_sha256, evidence.body_sha256.lower())

    def test_pinned_fetch_rejects_dns_rebinding_to_private_address(self):
        fetcher = SafePinnedFetcher(resolver=lambda host, port: ("127.0.0.1", "10.0.0.2"))
        with self.assertRaisesRegex(ResearchRuntimeError, "research_address_forbidden"):
            fetcher.resolve_public("https://example.com/")

    def test_readable_and_structured_extraction_preserves_source_hash(self):
        raw = b"""<html><head><title>Research</title><meta name='author' content='Kristin'><script type='application/ld+json'>{\"@type\":\"Article\"}</script></head><body><h1>Heading</h1><p>Evidence text</p><table><tr><th>A</th><td>1</td></tr></table></body></html>"""
        evidence = StaticEvidence("https://example.com", "https://example.com", 200, "text/html", raw, "a" * 64, "2026-08-20T00:00:00Z", "93.184.216.34", ("https://example.com",), {})
        document = ReadableExtractor().extract(evidence)
        self.assertEqual(document.source_hash, "a" * 64)
        self.assertEqual(document.title, "Research")
        self.assertEqual(document.author, "Kristin")
        self.assertIn("Evidence text", document.text)
        self.assertEqual(document.structured["jsonLd"][0]["@type"], "Article")
        self.assertEqual(document.structured["tables"][0][0], ["A", "1"])

    def test_crawler_respects_robots_and_resume_checkpoint(self):
        pages = {
            "https://example.com/": b"<html><title>Home</title><body><a href='/next'>Next</a><a href='/blocked'>Blocked</a></body></html>",
            "https://example.com/next": b"<html><title>Next</title><body>Done</body></html>",
        }

        class _Fetcher:
            def fetch(self, url):
                body = pages[url]
                return StaticEvidence(url, url, 200, "text/html", body, str(len(body)).rjust(64, "0"), "2026-08-20T00:00:00Z", "93.184.216.34", (url,), {})

        crawler = ResearchCrawler(_Fetcher())
        result = crawler.crawl(
            "https://example.com/",
            limits=CrawlLimits(max_pages=1, max_depth=2, max_bytes=100000, max_seconds=5, per_host_delay_seconds=0),
            robots_loader=lambda origin: "User-agent: *\nDisallow: /blocked\n",
        )
        self.assertEqual(result.stopped_reason, "max_pages")
        self.assertEqual(len(result.pages), 1)
        resumed = crawler.crawl(
            "https://example.com/",
            limits=CrawlLimits(max_pages=3, max_depth=2, max_bytes=100000, max_seconds=5, per_host_delay_seconds=0),
            checkpoint=result.checkpoint,
            robots_loader=lambda origin: "User-agent: *\nDisallow: /blocked\n",
        )
        self.assertEqual([page.title for page in resumed.pages], ["Next"])
        self.assertNotIn("https://example.com/blocked", resumed.checkpoint.visited)


if __name__ == "__main__":
    unittest.main()
