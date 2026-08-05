"""Strict validation helpers for the P4-001 search contract."""
from __future__ import annotations
import copy
import datetime as dt
import ipaddress
import json
import math
import re
import urllib.parse
from typing import Any, Mapping, Sequence
_ID_RE = re.compile('^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')
_LANGUAGE_RE = re.compile('^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$')
_COUNTRY_RE = re.compile('^[A-Z]{2}$')
_DOMAIN_RE = re.compile('^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
_URL_FORBIDDEN_RE = re.compile(r'[\x00-\x20\x7f\\]')
_SECRET_MARKERS = ('authorization', 'cookie', 'password', 'secret', 'token', 'apikey', 'clientsecret', 'privatekey')
_AUTHORITY_MARKERS = {
    'resultid', 'providerid', 'providerrank', 'title', 'url', 'displayurl',
    'snippet', 'publishedat', 'queryid', 'retrievedat', 'evidencestatus',
    'schemaversion', 'requestid', 'providerrequestid', 'nextcursor',
    'ratelimit', 'partialfailure',
    # Common aliases must not become a second authority channel.
    'identity', 'canonicalidentity', 'resultidentity', 'queryidentity',
    'paginationidentity', 'rank', 'resultrank', 'canonicalrank',
    'canonicalurl', 'evidencestate', 'retrievalstate', 'paginationstate',
    'paginationcursor', 'ratelimitstate', 'failurestate',
}

class SearchContractError(ValueError):
    """Raised when a P4-001 contract value is malformed."""

def canonical_json(value: Any) -> str:
    reject_non_finite_numbers(value)
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(',', ':'))

def json_copy(value: Any) -> Any:
    if value is None:
        return None
    return json.loads(canonical_json(copy.deepcopy(value)))

def require_exact_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    if not isinstance(value, Mapping):
        raise SearchContractError(f'{label} must be an object')
    actual = set(value)
    if actual != expected:
        raise SearchContractError(f'{label} fields are not exact; missing={sorted(expected - actual)}, extra={sorted(actual - expected)}')

def require_id(value: Any, field: str) -> str:
    if not isinstance(value, str) or _ID_RE.fullmatch(value) is None:
        raise SearchContractError(f'{field} is not a valid identifier')
    return value

def require_text(value: Any, field: str, *, maximum: int, allow_empty: bool=False) -> str:
    if not isinstance(value, str):
        raise SearchContractError(f'{field} must be text')
    if not allow_empty and (not value.strip()):
        raise SearchContractError(f'{field} must be non-empty')
    if len(value) > maximum:
        raise SearchContractError(f'{field} exceeds {maximum} characters')
    if '\x00' in value:
        raise SearchContractError(f'{field} contains NUL')
    return value

def require_language(value: Any, field: str) -> str:
    if not isinstance(value, str) or _LANGUAGE_RE.fullmatch(value) is None:
        raise SearchContractError(f'{field} is not a supported language tag')
    return value

def require_country(value: Any, field: str) -> str:
    if not isinstance(value, str) or _COUNTRY_RE.fullmatch(value) is None:
        raise SearchContractError(f'{field} is not an uppercase ISO country code')
    return value

def require_utc(value: Any, field: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith('Z'):
        raise SearchContractError(f'{field} must be an RFC3339 UTC timestamp')
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + '+00:00')
    except ValueError as exc:
        raise SearchContractError(f'{field} must be an RFC3339 UTC timestamp') from exc
    if parsed.utcoffset() != dt.timedelta(0):
        raise SearchContractError(f'{field} must be UTC')
    return parsed

def validate_freshness(value: Mapping[str, Any] | None) -> None:
    if value is None:
        return
    require_exact_keys(value, {'mode', 'after', 'before'}, 'freshness')
    mode = value['mode']
    if mode not in {'any', 'after', 'before', 'between'}:
        raise SearchContractError('freshness.mode is unsupported')
    after, before = (value['after'], value['before'])
    if after is not None:
        require_utc(after, 'freshness.after')
    if before is not None:
        require_utc(before, 'freshness.before')
    if mode == 'any' and (after is not None or before is not None):
        raise SearchContractError('freshness any cannot include bounds')
    if mode == 'after' and (after is None or before is not None):
        raise SearchContractError('freshness after requires only after')
    if mode == 'before' and (before is None or after is not None):
        raise SearchContractError('freshness before requires only before')
    if mode == 'between':
        if after is None or before is None:
            raise SearchContractError('freshness between requires both bounds')
        if require_utc(after, 'freshness.after') >= require_utc(before, 'freshness.before'):
            raise SearchContractError('freshness bounds are not increasing')

def validate_domains(value: Mapping[str, Sequence[str]] | None) -> None:
    if value is None:
        return
    require_exact_keys(value, {'include', 'exclude'}, 'domains')
    all_domains = []
    for key in ('include', 'exclude'):
        domains = value[key]
        if not isinstance(domains, Sequence) or isinstance(domains, (str, bytes, bytearray)):
            raise SearchContractError(f'domains.{key} must be an array')
        if len(domains) > 50:
            raise SearchContractError(f'domains.{key} exceeds 50 entries')
        for domain in domains:
            if not isinstance(domain, str):
                raise SearchContractError(f'domains.{key} values must be strings')
            normalized = domain.rstrip('.').lower()
            if _DOMAIN_RE.fullmatch(normalized) is None:
                raise SearchContractError(f'domains.{key} contains invalid domain')
            try:
                ipaddress.ip_address(normalized)
            except ValueError:
                pass
            else:
                raise SearchContractError('domain filters cannot contain IP literals')
            all_domains.append(normalized)
    if len(set(all_domains)) != len(all_domains):
        raise SearchContractError('domain filters contain duplicates or overlap')

def normalized_domains(value):
    if value is None:
        return None
    validate_domains(value)
    return {'include': sorted((i.rstrip('.').lower() for i in value['include'])), 'exclude': sorted((i.rstrip('.').lower() for i in value['exclude']))}

def require_public_result_url(value: Any, field: str) -> str:
    require_text(value, field, maximum=4096)
    if _URL_FORBIDDEN_RE.search(value):
        raise SearchContractError(f'{field} contains whitespace, control characters, or backslashes')
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in {'http', 'https'}:
        raise SearchContractError(f'{field} must use http or https')
    if parsed.username is not None or parsed.password is not None:
        raise SearchContractError(f'{field} must not contain credentials')
    if not parsed.hostname:
        raise SearchContractError(f'{field} must contain a host')
    if parsed.fragment:
        raise SearchContractError(f'{field} must not contain a fragment')
    try:
        port = parsed.port
    except ValueError as exc:
        raise SearchContractError(f'{field} contains an invalid port') from exc
    if port == 0 or parsed.netloc.endswith(':'):
        raise SearchContractError(f'{field} contains an invalid port')

    hostname = parsed.hostname.casefold()
    if '%' in hostname or hostname.endswith('.'):
        raise SearchContractError(f'{field} contains a non-canonical host')
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        if hostname == 'localhost' or hostname.endswith('.localhost'):
            raise SearchContractError(f'{field} must use a public host')
        if '.' not in hostname or _DOMAIN_RE.fullmatch(hostname) is None:
            raise SearchContractError(f'{field} contains an invalid public host')
    else:
        if not address.is_global:
            raise SearchContractError(f'{field} must not use a non-public IP address')
    return value

def _compact_key(key: str) -> str:
    return re.sub('[^a-z0-9]', '', key.casefold())

def reject_secret_material(value: Any, path: str='$') -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if not isinstance(key, str):
                raise SearchContractError(f'{path} contains a non-string key')
            compact = _compact_key(key)
            if any((marker in compact for marker in _SECRET_MARKERS)):
                raise SearchContractError(f'{path}.{key} may contain secret material')
            reject_secret_material(child, f'{path}.{key}')
    elif isinstance(value, Sequence) and (not isinstance(value, (str, bytes, bytearray))):
        for index, child in enumerate(value):
            reject_secret_material(child, f'{path}[{index}]')

def reject_provider_authority_fields(value: Any, path: str='provider_metadata') -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if not isinstance(key, str):
                raise SearchContractError(f'{path} contains a non-string key')
            if _compact_key(key) in _AUTHORITY_MARKERS:
                raise SearchContractError(f'{path}.{key} attempts to redefine a canonical authority field')
            reject_provider_authority_fields(child, f'{path}.{key}')
    elif isinstance(value, Sequence) and (not isinstance(value, (str, bytes, bytearray))):
        for index, child in enumerate(value):
            reject_provider_authority_fields(child, f'{path}[{index}]')

def reject_non_finite_numbers(value: Any, path: str='$') -> None:
    if isinstance(value, float) and (not math.isfinite(value)):
        raise SearchContractError(f'{path} contains a non-finite number')
    if isinstance(value, Mapping):
        for key, child in value.items():
            reject_non_finite_numbers(child, f'{path}.{key}')
    elif isinstance(value, Sequence) and (not isinstance(value, (str, bytes, bytearray))):
        for index, child in enumerate(value):
            reject_non_finite_numbers(child, f'{path}[{index}]')
