"""Deterministic, network-free providers for the P4-001 contract gate."""
from __future__ import annotations
import base64
import binascii
import json
import re
import urllib.parse
from dataclasses import dataclass
from typing import Any, Mapping, Sequence
from .models import CONTRACT_VERSION, SearchPage, SearchPartialFailure, SearchProviderCapabilities, SearchProviderError, SearchRateLimit, SearchRequest, SearchResult, stable_result_id
from .provider import SearchProvider, SearchProviderException
from .validation import SearchContractError, canonical_json, require_exact_keys, require_utc
_FIXED_RETRIEVED_AT = '2026-08-05T00:00:00Z'
_FIXED_RESET_AT = '2026-08-05T00:05:00Z'
_CURSOR_PREFIX = 'p4c1.'
_CURSOR_TOKEN_RE = re.compile(r'^[A-Za-z0-9_-]+$')

@dataclass(frozen=True)
class FixtureCatalogEntry:
    title: str
    url: str
    snippet: str
    published_at: str | None
    language: str
    country: str
    provider_metadata: Mapping[str, Any]
    safety_tier: str = 'strict'

    def __post_init__(self):
        if self.safety_tier not in {'strict', 'moderate', 'off'}:
            raise SearchContractError('fixture safety_tier is unsupported')

class DeterministicFixtureSearchProvider(SearchProvider):
    def __init__(self, *, provider_id: str, entries: Sequence[FixtureCatalogEntry], supports_domain_exclude: bool, supports_freshness: bool=True, supports_safe_search: bool=True):
        self._capabilities = SearchProviderCapabilities(provider_id=provider_id, supported_languages=('en', 'vi', 'uk'), supported_countries=('US', 'VN', 'UA'), supports_domain_exclude=supports_domain_exclude, supports_freshness=supports_freshness, supports_safe_search=supports_safe_search, max_page_size=25)
        self._entries = tuple(entries)

    @property
    def capabilities(self):
        return self._capabilities

    def _search(self, request: SearchRequest) -> SearchPage:
        self._validate_supported_request(request)
        if request.query == 'fixture:throttle':
            raise SearchProviderException(SearchProviderError(request.request_id, self.capabilities.provider_id, 'throttled', True, 'Fixture provider is rate limited.', 1000, 'fixture_throttle'))
        filtered = [e for e in self._entries if self._matches(e, request)]
        offset = self._decode_cursor(request)
        page_size = min(request.limit, self.capabilities.max_page_size)
        selected = filtered[offset:offset + page_size]
        next_offset = offset + len(selected)
        next_cursor = self._encode_cursor(request, next_offset) if next_offset < len(filtered) else None
        results = tuple(self._normalize(e, request, rank=offset + i + 1) for i, e in enumerate(selected))
        partial = SearchPartialFailure('provider_partial_failure', 'Fixture provider returned a partial page.', True) if request.query == 'fixture:partial' else None
        return SearchPage(request.request_id, self.capabilities.provider_id, f'{self.capabilities.provider_id}:{request.query_id}:{offset}', results, next_cursor, SearchRateLimit(1000, 999, _FIXED_RESET_AT), partial, _FIXED_RETRIEVED_AT)

    def _validate_supported_request(self, request):
        caps = self.capabilities
        if request.limit > caps.max_page_size:
            raise SearchProviderException(self._unsupported(request, 'limit_exceeds_provider_maximum'))
        if request.language and request.language not in caps.supported_languages:
            raise SearchProviderException(self._unsupported(request, 'language_not_supported'))
        if request.country and request.country not in caps.supported_countries:
            raise SearchProviderException(self._unsupported(request, 'country_not_supported'))
        if request.freshness is not None and not caps.supports_freshness:
            raise SearchProviderException(self._unsupported(request, 'freshness_not_supported'))
        if request.safe_search != 'moderate' and not caps.supports_safe_search:
            raise SearchProviderException(self._unsupported(request, 'safe_search_not_supported'))
        domains = request.domains or {'include': (), 'exclude': ()}
        if domains.get('include') and not caps.supports_domain_include:
            raise SearchProviderException(self._unsupported(request, 'domain_include_not_supported'))
        if domains.get('exclude') and not caps.supports_domain_exclude:
            raise SearchProviderException(self._unsupported(request, 'domain_exclude_not_supported'))

    def _unsupported(self, request, diagnostic_code):
        return SearchProviderError(request.request_id, self.capabilities.provider_id, 'unsupported_filter', False, 'The fixture provider does not support this filter.', None, diagnostic_code)

    def _matches_freshness(self, entry: FixtureCatalogEntry, request: SearchRequest) -> bool:
        freshness = request.freshness
        if freshness is None or freshness['mode'] == 'any':
            return True
        if entry.published_at is None:
            return False
        published = require_utc(entry.published_at, 'published_at')
        mode = freshness['mode']
        if mode == 'after':
            return published > require_utc(freshness['after'], 'freshness.after')
        if mode == 'before':
            return published < require_utc(freshness['before'], 'freshness.before')
        if mode == 'between':
            after = require_utc(freshness['after'], 'freshness.after')
            before = require_utc(freshness['before'], 'freshness.before')
            return after < published < before
        raise SearchContractError('freshness.mode is unsupported')

    def _matches_safe_search(self, entry: FixtureCatalogEntry, request: SearchRequest) -> bool:
        mode = request.safe_search
        if mode == 'off':
            return True
        if mode == 'moderate':
            return entry.safety_tier in {'strict', 'moderate'}
        if mode == 'strict':
            return entry.safety_tier == 'strict'
        raise SearchContractError('safe_search is unsupported')

    def _matches(self, entry, request):
        if request.language and entry.language != request.language:
            return False
        if request.country and entry.country != request.country:
            return False
        if not self._matches_safe_search(entry, request):
            return False
        if not self._matches_freshness(entry, request):
            return False
        domains = request.domains or {'include': (), 'exclude': ()}
        hostname = (urllib.parse.urlsplit(entry.url).hostname or '').lower()
        includes = tuple(domains.get('include', ()))
        excludes = tuple(domains.get('exclude', ()))
        if includes and not any(hostname == d or hostname.endswith(f'.{d}') for d in includes):
            return False
        if any(hostname == d or hostname.endswith(f'.{d}') for d in excludes):
            return False
        query = request.query.casefold()
        if query.startswith('fixture:'):
            return True
        haystack = f'{entry.title}\n{entry.snippet}'.casefold()
        return all(token in haystack for token in query.split())

    def _normalize(self, entry, request, *, rank):
        return SearchResult(stable_result_id(self.capabilities.provider_id, request.query_id, entry.url), self.capabilities.provider_id, rank, entry.title, entry.url, entry.url, entry.snippet, entry.published_at, request.query_id, _FIXED_RETRIEVED_AT, entry.provider_metadata)

    def _encode_cursor(self, request, offset):
        payload = {'contractVersion': CONTRACT_VERSION, 'providerId': self.capabilities.provider_id, 'queryId': request.query_id, 'offset': offset}
        raw = canonical_json(payload).encode()
        return _CURSOR_PREFIX + base64.urlsafe_b64encode(raw).decode().rstrip('=')

    def _decode_cursor(self, request):
        cursor = request.cursor
        if cursor is None:
            return 0
        if not cursor.startswith(_CURSOR_PREFIX):
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_format_invalid'))
        token = cursor[len(_CURSOR_PREFIX):]
        if (
            not token
            or len(token) > 480
            or _CURSOR_TOKEN_RE.fullmatch(token) is None
        ):
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_payload_invalid'))
        try:
            raw = base64.b64decode(
                token + '=' * ((4 - len(token) % 4) % 4),
                altchars=b'-_',
                validate=True,
            )
            payload = json.loads(raw.decode('utf-8'))
            require_exact_keys(payload, {'contractVersion', 'providerId', 'queryId', 'offset'}, 'cursor')
            canonical_token = base64.urlsafe_b64encode(raw).decode().rstrip('=')
            if canonical_token != token or canonical_json(payload).encode() != raw:
                raise SearchContractError('cursor payload is not canonical')
        except (
            ValueError,
            UnicodeDecodeError,
            json.JSONDecodeError,
            SearchContractError,
            binascii.Error,
        ):
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_payload_invalid'))
        if payload['contractVersion'] != CONTRACT_VERSION:
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_version_invalid'))
        if payload['providerId'] != self.capabilities.provider_id:
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_provider_mismatch'))
        if payload['queryId'] != request.query_id:
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_query_mismatch'))
        offset = payload['offset']
        if not isinstance(offset, int) or isinstance(offset, bool) or not 0 <= offset <= 1000000:
            raise SearchProviderException(self._invalid_cursor(request, 'cursor_offset_invalid'))
        return offset

    def _invalid_cursor(self, request, diagnostic_code):
        return SearchProviderError(request.request_id, self.capabilities.provider_id, 'invalid_request', False, 'The cursor is invalid.', None, diagnostic_code)

def fixture_provider_a(entries):
    return DeterministicFixtureSearchProvider(provider_id='fixture_alpha', entries=entries, supports_domain_exclude=True)

def fixture_provider_b(entries):
    return DeterministicFixtureSearchProvider(provider_id='fixture_beta', entries=entries, supports_domain_exclude=False)
