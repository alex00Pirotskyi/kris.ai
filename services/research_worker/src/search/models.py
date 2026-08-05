"""Immutable data models for the P4-001 provider-neutral search contract."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .validation import (
    SearchContractError,
    canonical_json,
    json_copy,
    normalized_domains,
    reject_secret_material,
    require_country,
    require_exact_keys,
    require_id,
    require_language,
    require_public_result_url,
    require_text,
    require_utc,
    validate_domains,
    validate_freshness,
)

SCHEMA_VERSION = "1.0.0"
CONTRACT_VERSION = "p4.search-provider.v1"


@dataclass(frozen=True)
class SearchProviderCapabilities:
    provider_id: str
    supported_languages: tuple[str, ...] = ()
    supported_countries: tuple[str, ...] = ()
    supports_domain_include: bool = True
    supports_domain_exclude: bool = True
    supports_freshness: bool = True
    supports_safe_search: bool = True
    max_page_size: int = 100

    def __post_init__(self) -> None:
        require_id(self.provider_id, "provider_id")
        if not 1 <= self.max_page_size <= 100:
            raise SearchContractError("max_page_size must be in 1..100")
        for value in self.supported_languages:
            require_language(value, "supported_languages")
        for value in self.supported_countries:
            require_country(value, "supported_countries")

    def to_dict(self) -> dict[str, Any]:
        return {
            "contractVersion": CONTRACT_VERSION,
            "providerId": self.provider_id,
            "supportedLanguages": list(self.supported_languages),
            "supportedCountries": list(self.supported_countries),
            "supportsDomainInclude": self.supports_domain_include,
            "supportsDomainExclude": self.supports_domain_exclude,
            "supportsFreshness": self.supports_freshness,
            "supportsSafeSearch": self.supports_safe_search,
            "maxPageSize": self.max_page_size,
        }


@dataclass(frozen=True)
class SearchRequest:
    request_id: str
    query: str
    limit: int = 10
    cursor: str | None = None
    language: str | None = None
    country: str | None = None
    safe_search: str = "moderate"
    freshness: Mapping[str, Any] | None = None
    domains: Mapping[str, Sequence[str]] | None = None

    def __post_init__(self) -> None:
        require_id(self.request_id, "request_id")
        require_text(self.query, "query", maximum=2048)
        if not isinstance(self.limit, int) or isinstance(self.limit, bool):
            raise SearchContractError("limit must be an integer")
        if not 1 <= self.limit <= 100:
            raise SearchContractError("limit must be in 1..100")
        if self.cursor is not None:
            require_text(self.cursor, "cursor", maximum=512)
        if self.language is not None:
            require_language(self.language, "language")
        if self.country is not None:
            require_country(self.country, "country")
        if self.safe_search not in {"off", "moderate", "strict"}:
            raise SearchContractError("safe_search is unsupported")
        validate_freshness(self.freshness)
        validate_domains(self.domains)

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "SearchRequest":
        expected = {
            "schemaVersion", "requestId", "query", "limit", "cursor",
            "language", "country", "safeSearch", "freshness", "domains",
        }
        require_exact_keys(value, expected, "search request")
        if value["schemaVersion"] != SCHEMA_VERSION:
            raise SearchContractError("unsupported search request schemaVersion")
        reject_secret_material(value)
        return cls(
            request_id=value["requestId"], query=value["query"],
            limit=value["limit"], cursor=value["cursor"],
            language=value["language"], country=value["country"],
            safe_search=value["safeSearch"], freshness=json_copy(value["freshness"]),
            domains=json_copy(value["domains"]),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "requestId": self.request_id,
            "query": self.query,
            "limit": self.limit,
            "cursor": self.cursor,
            "language": self.language,
            "country": self.country,
            "safeSearch": self.safe_search,
            "freshness": json_copy(self.freshness),
            "domains": normalized_domains(self.domains),
        }

    @property
    def query_id(self) -> str:
        digest = hashlib.sha256(canonical_json(self.to_dict()).encode("utf-8"))
        return f"qry_{digest.hexdigest()[:32]}"


@dataclass(frozen=True)
class SearchResult:
    result_id: str
    provider_id: str
    provider_rank: int
    title: str
    url: str
    display_url: str
    snippet: str
    published_at: str | None
    query_id: str
    retrieved_at: str
    provider_metadata: Mapping[str, Any]

    def __post_init__(self) -> None:
        require_id(self.result_id, "result_id")
        require_id(self.provider_id, "provider_id")
        require_id(self.query_id, "query_id")
        if not isinstance(self.provider_rank, int) or isinstance(self.provider_rank, bool):
            raise SearchContractError("provider_rank must be an integer")
        if not 1 <= self.provider_rank <= 10000:
            raise SearchContractError("provider_rank must be in 1..10000")
        require_text(self.title, "title", maximum=512)
        require_public_result_url(self.url, "url")
        require_text(self.display_url, "display_url", maximum=2048)
        require_text(self.snippet, "snippet", maximum=4096, allow_empty=True)
        if self.published_at is not None:
            require_utc(self.published_at, "published_at")
        require_utc(self.retrieved_at, "retrieved_at")
        reject_secret_material(self.provider_metadata)
        if len(canonical_json(self.provider_metadata).encode("utf-8")) > 16384:
            raise SearchContractError("provider_metadata exceeds 16384 bytes")

    def to_dict(self) -> dict[str, Any]:
        return {
            "resultId": self.result_id, "providerId": self.provider_id,
            "providerRank": self.provider_rank, "title": self.title,
            "url": self.url, "displayUrl": self.display_url,
            "snippet": self.snippet, "publishedAt": self.published_at,
            "queryId": self.query_id, "retrievedAt": self.retrieved_at,
            "evidenceStatus": "unfetched_snippet_only",
            "providerMetadata": json_copy(self.provider_metadata),
        }


@dataclass(frozen=True)
class SearchRateLimit:
    limit: int | None
    remaining: int | None
    reset_at: str | None

    def __post_init__(self) -> None:
        for field, value in (("limit", self.limit), ("remaining", self.remaining)):
            if value is not None and (
                not isinstance(value, int) or isinstance(value, bool) or value < 0
            ):
                raise SearchContractError(f"rate_limit.{field} is invalid")
        if self.limit is not None and self.remaining is not None:
            if self.remaining > self.limit:
                raise SearchContractError("rate_limit.remaining exceeds limit")
        if self.reset_at is not None:
            require_utc(self.reset_at, "rate_limit.reset_at")

    def to_dict(self) -> dict[str, Any]:
        return {"limit": self.limit, "remaining": self.remaining, "resetAt": self.reset_at}


@dataclass(frozen=True)
class SearchPartialFailure:
    code: str
    safe_message: str
    retryable: bool

    def __post_init__(self) -> None:
        allowed = {
            "provider_partial_failure", "provider_result_truncated",
            "provider_metadata_omitted",
        }
        if self.code not in allowed:
            raise SearchContractError("partial failure code is unsupported")
        require_text(self.safe_message, "safe_message", maximum=512)
        if not isinstance(self.retryable, bool):
            raise SearchContractError("retryable must be a boolean")

    def to_dict(self) -> dict[str, Any]:
        return {"code": self.code, "safeMessage": self.safe_message, "retryable": self.retryable}


@dataclass(frozen=True)
class SearchPage:
    request_id: str
    provider_id: str
    provider_request_id: str
    results: tuple[SearchResult, ...]
    next_cursor: str | None
    rate_limit: SearchRateLimit
    partial_failure: SearchPartialFailure | None
    retrieved_at: str

    def __post_init__(self) -> None:
        require_id(self.request_id, "request_id")
        require_id(self.provider_id, "provider_id")
        require_id(self.provider_request_id, "provider_request_id")
        if len(self.results) > 100:
            raise SearchContractError("results exceed 100")
        for result in self.results:
            if result.provider_id != self.provider_id:
                raise SearchContractError("result provider does not match page")
            if result.retrieved_at != self.retrieved_at:
                raise SearchContractError("result retrieval time does not match page")
        if self.next_cursor is not None:
            require_text(self.next_cursor, "next_cursor", maximum=512)
        require_utc(self.retrieved_at, "retrieved_at")

    def to_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION, "requestId": self.request_id,
            "providerId": self.provider_id,
            "providerRequestId": self.provider_request_id,
            "results": [item.to_dict() for item in self.results],
            "nextCursor": self.next_cursor,
            "rateLimit": self.rate_limit.to_dict(),
            "partialFailure": self.partial_failure.to_dict() if self.partial_failure else None,
            "retrievedAt": self.retrieved_at,
        }


@dataclass(frozen=True)
class SearchProviderError:
    request_id: str
    provider_id: str
    code: str
    retryable: bool
    safe_message: str
    retry_after_ms: int | None = None
    diagnostic_code: str | None = None

    def __post_init__(self) -> None:
        require_id(self.request_id, "request_id")
        require_id(self.provider_id, "provider_id")
        if self.code not in {
            "invalid_request", "unsupported_filter", "throttled",
            "provider_unavailable", "provider_error",
        }:
            raise SearchContractError("provider error code is unsupported")
        if not isinstance(self.retryable, bool):
            raise SearchContractError("retryable must be a boolean")
        require_text(self.safe_message, "safe_message", maximum=512)
        if self.retry_after_ms is not None and (
            not isinstance(self.retry_after_ms, int) or isinstance(self.retry_after_ms, bool)
            or not 0 <= self.retry_after_ms <= 86_400_000
        ):
            raise SearchContractError("retry_after_ms is invalid")
        if self.diagnostic_code is not None:
            require_id(self.diagnostic_code, "diagnostic_code")

    def to_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION, "requestId": self.request_id,
            "providerId": self.provider_id, "code": self.code,
            "retryable": self.retryable, "safeMessage": self.safe_message,
            "retryAfterMs": self.retry_after_ms,
            "diagnosticCode": self.diagnostic_code,
        }


def stable_result_id(provider_id: str, query_id: str, url: str) -> str:
    require_id(provider_id, "provider_id")
    require_id(query_id, "query_id")
    require_public_result_url(url, "url")
    digest = hashlib.sha256(f"{provider_id}\n{query_id}\n{url}".encode("utf-8"))
    return f"res_{digest.hexdigest()[:32]}"
