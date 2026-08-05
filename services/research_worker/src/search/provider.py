"""Provider interface for P4-001.

No method in this module grants authority, selects credentials, fetches pages, or
mutates authoritative storage. Concrete providers return normalized candidates.
"""

from __future__ import annotations

import abc

from .models import SearchPage, SearchProviderCapabilities, SearchProviderError, SearchRequest


class SearchProviderException(RuntimeError):
    def __init__(self, error: SearchProviderError):
        super().__init__(error.safe_message)
        self.error = error


class SearchProvider(abc.ABC):
    @property
    @abc.abstractmethod
    def capabilities(self) -> SearchProviderCapabilities:
        raise NotImplementedError

    @abc.abstractmethod
    def search(self, request: SearchRequest) -> SearchPage:
        """Return a normalized page or raise SearchProviderException."""
        raise NotImplementedError
