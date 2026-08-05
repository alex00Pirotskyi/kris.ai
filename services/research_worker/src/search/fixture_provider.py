"""Deterministic, network-free providers for the P4-001 contract gate."""

from __future__ import annotations

import urllib.parse
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .models import (
    SearchPage,
    SearchPartialFailure,
    SearchProviderCapabilities,
    SearchProviderError,
    SearchRateLimit,
    SearchRequest,
    SearchResult,
    stable_result_id,
)
from .provider import SearchProvider, SearchProviderException

_FIXED_RETRIEVED_AT = "2026-08-05T00:00:00Z"
_FIXED_RESET_AT = "2026-08-05T00:05:00Z"


@dataclass(frozen=True)
class FixtureCatalogEntry:
    title: str
    url: str
    snippet: str
    published_at: str | None
    language: str
    country: str
    provider_metadata: Mapping[str, Any]


class DeterministicFixtureSearchProvider(SearchProvider):
    def __init__(
        self,
        *,
        provider_id: str,
        entries: Sequence[FixtureCatalogEntry],
        supports_domain_exclude: bool,
    ) -> None:
        self._capabilities = SearchProviderCapabilities(
            provider_id=provider_id,
            supported_languages=("en", "vi", "uk"),
            supported_countries=("US", "VN", "UA"),
            supports_domain_exclude=supports_domain_exclude,
            max_page_size=25,
        )
        self._entries = tuple(entries)

    @property
    def capabilities(self) -> SearchProviderCapabilities:
        return self._capabilities

    def search(self, request: SearchRequest) -> SearchPage:
        self._validate_supported_request(request)
        if request.query == "fixture:throttle":
            raise SearchProviderException(
                SearchProviderError(
                    request_id=request.request_id,
                    provider_id=self.capabilities.provider_id,
                    code="throttled",
                    retryable=True,
                    safe_message="Fixture provider is rate limited.",
                    retry_after_ms=1000,
                    diagnostic_code="fixture_throttle",
                )
            )
        filtered = [entry for entry in self._entries if self._matches(entry, request)]
        offset = self._decode_cursor(request)
        page_size = min(request.limit, self.capabilities.max_page_size)
        selected = filtered[offset : offset + page_size]
        next_offset = offset + len(selected)
        next_cursor = f"offset:{next_offset}" if next_offset < len(filtered) else None
        results = tuple(
            self._normalize(entry, request, rank=offset + index + 1)
            for index, entry in enumerate(selected)
        )
        partial = None
        if request.query == "fixture:partial":
            partial = SearchPartialFailure(
                code="provider_partial_failure",
                safe_message="Fixture provider returned a partial page.",
                retryable=True,
            )
        return SearchPage(
            request_id=request.request_id,
            provider_id=self.capabilities.provider_id,
            provider_request_id=(
                f"{self.capabilities.provider_id}:{request.query_id}:{offset}"
            ),
            results=results,
            next_cursor=next_cursor,
            rate_limit=SearchRateLimit(1000, 999, _FIXED_RESET_AT),
            partial_failure=partial,
            retrieved_at=_FIXED_RETRIEVED_AT,
        )

    def _validate_supported_request(self, request: SearchRequest) -> None:
        caps = self.capabilities
        if request.limit > caps.max_page_size:
            raise SearchProviderException(
                self._unsupported(request, "limit_exceeds_provider_maximum")
            )
        if request.language and request.language not in caps.supported_languages:
            raise SearchProviderException(
                self._unsupported(request, "language_not_supported")
            )
        if request.country and request.country not in caps.supported_countries:
            raise SearchProviderException(
                self._unsupported(request, "country_not_supported")
            )
        domains = request.domains or {"include": (), "exclude": ()}
        if domains.get("exclude") and not caps.supports_domain_exclude:
            raise SearchProviderException(
                self._unsupported(request, "domain_exclude_not_supported")
            )

    def _unsupported(
        self, request: SearchRequest, diagnostic_code: str
    ) -> SearchProviderError:
        return SearchProviderError(
            request_id=request.request_id,
            provider_id=self.capabilities.provider_id,
            code="unsupported_filter",
            retryable=False,
            safe_message="The fixture provider does not support this filter.",
            diagnostic_code=diagnostic_code,
        )

    def _matches(self, entry: FixtureCatalogEntry, request: SearchRequest) -> bool:
        if request.language and entry.language != request.language:
            return False
        if request.country and entry.country != request.country:
            return False
        domains = request.domains or {"include": (), "exclude": ()}
        hostname = (urllib.parse.urlsplit(entry.url).hostname or "").lower()
        includes = tuple(domains.get("include", ()))
        excludes = tuple(domains.get("exclude", ()))
        if includes and not any(
            hostname == domain or hostname.endswith(f".{domain}")
            for domain in includes
        ):
            return False
        if any(
            hostname == domain or hostname.endswith(f".{domain}")
            for domain in excludes
        ):
            return False
        query = request.query.casefold()
        if query.startswith("fixture:"):
            return True
        haystack = f"{entry.title}\n{entry.snippet}".casefold()
        return all(token in haystack for token in query.split())

    def _normalize(
        self, entry: FixtureCatalogEntry, request: SearchRequest, *, rank: int
    ) -> SearchResult:
        return SearchResult(
            result_id=stable_result_id(
                self.capabilities.provider_id, request.query_id, entry.url
            ),
            provider_id=self.capabilities.provider_id,
            provider_rank=rank,
            title=entry.title,
            url=entry.url,
            display_url=entry.url,
            snippet=entry.snippet,
            published_at=entry.published_at,
            query_id=request.query_id,
            retrieved_at=_FIXED_RETRIEVED_AT,
            provider_metadata=entry.provider_metadata,
        )

    def _decode_cursor(self, request: SearchRequest) -> int:
        cursor = request.cursor
        if cursor is None:
            return 0
        if not cursor.startswith("offset:"):
            raise SearchProviderException(self._invalid_cursor(request, "cursor_format_invalid"))
        raw = cursor[len("offset:") :]
        if not raw.isdigit() or len(raw) > 6:
            raise SearchProviderException(self._invalid_cursor(request, "cursor_offset_invalid"))
        return int(raw)

    def _invalid_cursor(
        self, request: SearchRequest, diagnostic_code: str
    ) -> SearchProviderError:
        return SearchProviderError(
            request_id=request.request_id,
            provider_id=self.capabilities.provider_id,
            code="invalid_request",
            retryable=False,
            safe_message="The cursor is invalid.",
            diagnostic_code=diagnostic_code,
        )


def fixture_provider_a(entries: Sequence[FixtureCatalogEntry]) -> SearchProvider:
    return DeterministicFixtureSearchProvider(
        provider_id="fixture_alpha",
        entries=entries,
        supports_domain_exclude=True,
    )


def fixture_provider_b(entries: Sequence[FixtureCatalogEntry]) -> SearchProvider:
    return DeterministicFixtureSearchProvider(
        provider_id="fixture_beta",
        entries=entries,
        supports_domain_exclude=False,
    )
