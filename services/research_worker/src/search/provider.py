"""Provider interface for P4-001.

No method in this module grants authority, selects credentials, fetches pages, or
mutates authoritative storage. Concrete providers return normalized candidates.
"""

from __future__ import annotations

import abc

from .models import SearchPage, SearchProviderCapabilities, SearchProviderError, SearchRequest
from .validation import SearchContractError


class SearchProviderException(RuntimeError):
    def __init__(self, error: SearchProviderError):
        super().__init__(error.safe_message)
        self.error = error


def validate_page_for_request(
    request: SearchRequest,
    page: SearchPage,
    capabilities: SearchProviderCapabilities,
) -> SearchPage:
    """Fail closed unless a provider page belongs to the exact originating request."""
    if not isinstance(page, SearchPage):
        raise SearchContractError('provider search result must be a SearchPage')
    if page.request_id != request.request_id:
        raise SearchContractError('page request identity does not match originating request')
    if page.provider_id != capabilities.provider_id:
        raise SearchContractError('page provider identity does not match provider capabilities')
    maximum = min(request.limit, capabilities.max_page_size)
    if len(page.results) > maximum:
        raise SearchContractError('page result count exceeds originating request limit')
    for result in page.results:
        if result.query_id != request.query_id:
            raise SearchContractError('result query identity does not match originating request')
    return page


class SearchProvider(abc.ABC):
    @property
    @abc.abstractmethod
    def capabilities(self) -> SearchProviderCapabilities:
        raise NotImplementedError

    def search(self, request: SearchRequest) -> SearchPage:
        """Return one request-bound normalized page or raise a typed provider error."""
        page = self._search(request)
        return validate_page_for_request(request, page, self.capabilities)

    @abc.abstractmethod
    def _search(self, request: SearchRequest) -> SearchPage:
        """Provider implementation hook. The public search method validates its page."""
        raise NotImplementedError
