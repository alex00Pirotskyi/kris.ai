"""P4-001 provider-neutral search contract."""

from .models import (
    CONTRACT_VERSION,
    SCHEMA_VERSION,
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
from .validation import SearchContractError, canonical_json

__all__ = [
    "CONTRACT_VERSION",
    "SCHEMA_VERSION",
    "SearchContractError",
    "SearchPage",
    "SearchPartialFailure",
    "SearchProvider",
    "SearchProviderCapabilities",
    "SearchProviderError",
    "SearchProviderException",
    "SearchRateLimit",
    "SearchRequest",
    "SearchResult",
    "canonical_json",
    "stable_result_id",
]
