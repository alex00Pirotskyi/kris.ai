"""P4 research planning, fetch, extraction, and crawl runtime."""

from .runtime import (
    CrawlCheckpoint,
    CrawlLimits,
    CrawlPage,
    CrawlResult,
    ExtractedDocument,
    PinnedAddress,
    QueryPlan,
    QueryPlanner,
    RankedResult,
    ReadableExtractor,
    RenderedEvidence,
    RenderedFetcher,
    ResearchCrawler,
    SafePinnedFetcher,
    StaticEvidence,
    StructuredDataExtractor,
    canonicalize_url,
    rank_results,
)

__all__ = [
    "CrawlCheckpoint",
    "CrawlLimits",
    "CrawlPage",
    "CrawlResult",
    "ExtractedDocument",
    "PinnedAddress",
    "QueryPlan",
    "QueryPlanner",
    "RankedResult",
    "ReadableExtractor",
    "RenderedEvidence",
    "RenderedFetcher",
    "ResearchCrawler",
    "SafePinnedFetcher",
    "StaticEvidence",
    "StructuredDataExtractor",
    "canonicalize_url",
    "rank_results",
]

# Temporary P4 materialization trigger; final reconciler restores source bytes.
