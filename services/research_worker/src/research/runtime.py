from __future__ import annotations

import hashlib
import html
import http.client
import ipaddress
import json
import re
import socket
import ssl
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Callable, Iterable, Mapping, Protocol, Sequence
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit
from urllib.robotparser import RobotFileParser

from ..search.models import SearchResult


class ResearchRuntimeError(ValueError):
    pass


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_text(value: str) -> str:
    return _sha256_bytes(value.encode("utf-8"))


def canonicalize_url(value: str) -> str:
    parsed = urlsplit(value.strip())
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ResearchRuntimeError("research_url_invalid")
    host = parsed.hostname.lower().rstrip(".")
    port = parsed.port
    default_port = (parsed.scheme.lower() == "https" and port == 443) or (
        parsed.scheme.lower() == "http" and port == 80
    )
    netloc = host if port is None or default_port else f"{host}:{port}"
    path = re.sub(r"/{2,}", "/", parsed.path or "/")
    if path != "/" and path.endswith("/"):
        path = path[:-1]
    query = [
        (key, item)
        for key, item in parse_qsl(parsed.query, keep_blank_values=True)
        if not key.lower().startswith("utm_")
        and key.lower() not in {"fbclid", "gclid", "mc_cid", "mc_eid"}
    ]
    query.sort()
    return urlunsplit((parsed.scheme.lower(), netloc, path, urlencode(query), ""))


@dataclass(frozen=True)
class QueryPlan:
    primary: str
    precision: tuple[str, ...]
    recall: tuple[str, ...]
    official: tuple[str, ...]
    freshness: tuple[str, ...]
    follow_up: tuple[str, ...]
    stop_after_results: int = 40

    def __post_init__(self) -> None:
        if not self.primary.strip() or len(self.primary) > 2048:
            raise ResearchRuntimeError("research_query_invalid")
        if not 5 <= self.stop_after_results <= 200:
            raise ResearchRuntimeError("research_query_stop_invalid")
        all_queries = (
            self.precision + self.recall + self.official + self.freshness + self.follow_up
        )
        if len(all_queries) > 24 or any(not item.strip() or len(item) > 2048 for item in all_queries):
            raise ResearchRuntimeError("research_query_plan_invalid")

    @property
    def queries(self) -> tuple[str, ...]:
        ordered = (self.primary,) + self.precision + self.recall + self.official + self.freshness + self.follow_up
        return tuple(dict.fromkeys(item.strip() for item in ordered if item.strip()))


class QueryPlanner:
    _current_markers = re.compile(r"\b(latest|current|today|recent|new|this week|this month|202[5-9])\b", re.I)
    _local_markers = re.compile(r"\b(near me|nearby|local|in [A-Z][A-Za-z .'-]{2,})\b")
    _technical_markers = re.compile(r"\b(api|sdk|library|framework|protocol|rfc|compiler|firmware|ble|flutter|dart|python|node)\b", re.I)

    def plan(self, question: str) -> QueryPlan:
        primary = " ".join(question.split())
        if len(primary) < 3 or len(primary) > 2048:
            raise ResearchRuntimeError("research_query_invalid")
        precision = [f'"{primary}"'] if len(primary) <= 240 else [primary]
        recall_terms = [term for term in re.findall(r"[A-Za-z0-9_.+-]{3,}", primary) if term.lower() not in {"what", "when", "where", "which", "that", "with", "from", "this", "about"}]
        recall = [" ".join(recall_terms[:6])] if recall_terms else []
        official = [f"{primary} official documentation", f"{primary} site:.gov OR site:.edu"]
        freshness = [f"{primary} latest"] if self._current_markers.search(primary) else []
        follow = []
        if self._technical_markers.search(primary):
            follow.extend([f"{primary} reference", f"{primary} changelog"])
        if self._local_markers.search(primary):
            follow.append(f"{primary} official local")
        if " vs " in primary.lower() or "compare" in primary.lower():
            follow.append(f"{primary} benchmark")
        return QueryPlan(
            primary=primary,
            precision=tuple(precision[:2]),
            recall=tuple(recall[:2]),
            official=tuple(official[:2]),
            freshness=tuple(freshness[:2]),
            follow_up=tuple(follow[:4]),
        )


@dataclass(frozen=True)
class RankedResult:
    result: SearchResult
    canonical_url: str
    score: float
    duplicate_group: str


def _token_set(value: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]{2,}", value.lower()))


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def rank_results(results: Sequence[SearchResult], query: str, *, now: datetime | None = None) -> tuple[RankedResult, ...]:
    now = now or datetime.now(timezone.utc)
    query_tokens = _token_set(query)
    seen: list[tuple[str, set[str], str]] = []
    ranked: list[RankedResult] = []
    provider_counts: dict[str, int] = {}
    for result in results:
        canonical = canonicalize_url(result.url)
        text_tokens = _token_set(f"{result.title} {result.snippet}")
        duplicate_group = _sha256_text(canonical)[:16]
        duplicate = False
        for existing_url, existing_tokens, existing_group in seen:
            if canonical == existing_url or _jaccard(text_tokens, existing_tokens) >= 0.92:
                duplicate = True
                duplicate_group = existing_group
                break
        if duplicate:
            continue
        seen.append((canonical, text_tokens, duplicate_group))
        relevance = _jaccard(query_tokens, text_tokens)
        provider_counts[result.provider_id] = provider_counts.get(result.provider_id, 0) + 1
        diversity = 1.0 / provider_counts[result.provider_id]
        freshness = 0.0
        if result.published_at:
            try:
                published = datetime.fromisoformat(result.published_at.replace("Z", "+00:00"))
                age_days = max(0.0, (now - published).total_seconds() / 86400.0)
                freshness = 1.0 / (1.0 + age_days / 30.0)
            except ValueError:
                freshness = 0.0
        provider_rank_score = 1.0 / max(1, result.provider_rank)
        score = 0.55 * relevance + 0.20 * freshness + 0.15 * diversity + 0.10 * provider_rank_score
        ranked.append(RankedResult(result, canonical, score, duplicate_group))
    ranked.sort(key=lambda item: (-item.score, item.result.provider_rank, item.canonical_url))
    return tuple(ranked)


def _forbidden_ip(value: str) -> bool:
    address = ipaddress.ip_address(value)
    return (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
    )


@dataclass(frozen=True)
class PinnedAddress:
    host: str
    address: str
    port: int

    def __post_init__(self) -> None:
        if not self.host or _forbidden_ip(self.address):
            raise ResearchRuntimeError("research_address_forbidden")
        if not 1 <= self.port <= 65535:
            raise ResearchRuntimeError("research_port_invalid")


class _PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host: str, pinned_ip: str, port: int, *, timeout: float, context: ssl.SSLContext) -> None:
        super().__init__(host=host, port=port, timeout=timeout, context=context)
        self._pinned_ip = pinned_ip

    def connect(self) -> None:
        raw = socket.create_connection((self._pinned_ip, self.port), self.timeout)
        if self._tunnel_host:
            self.sock = raw
            self._tunnel()
            raw = self.sock
        self.sock = self._context.wrap_socket(raw, server_hostname=self.host)


@dataclass(frozen=True)
class StaticEvidence:
    requested_url: str
    final_url: str
    status: int
    content_type: str
    body: bytes
    body_sha256: str
    fetched_at: str
    pinned_address: str
    redirect_chain: tuple[str, ...]
    headers: Mapping[str, str]


class SafePinnedFetcher:
    def __init__(
        self,
        *,
        max_bytes: int = 8 * 1024 * 1024,
        max_redirects: int = 5,
        timeout_seconds: float = 15.0,
        resolver: Callable[[str, int], Sequence[str]] | None = None,
        connection_factory: Callable[[str, str, int, float, ssl.SSLContext], http.client.HTTPSConnection] | None = None,
    ) -> None:
        if not 1024 <= max_bytes <= 64 * 1024 * 1024:
            raise ResearchRuntimeError("research_fetch_budget_invalid")
        if not 0 <= max_redirects <= 10 or not 0.1 <= timeout_seconds <= 120:
            raise ResearchRuntimeError("research_fetch_policy_invalid")
        self.max_bytes = max_bytes
        self.max_redirects = max_redirects
        self.timeout_seconds = timeout_seconds
        self._resolver = resolver or self._resolve
        self._connection_factory = connection_factory or self._connect

    @staticmethod
    def _resolve(host: str, port: int) -> Sequence[str]:
        addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        return tuple(dict.fromkeys(item[4][0] for item in addresses))

    @staticmethod
    def _connect(host: str, address: str, port: int, timeout: float, context: ssl.SSLContext) -> http.client.HTTPSConnection:
        return _PinnedHTTPSConnection(host, address, port, timeout=timeout, context=context)

    def resolve_public(self, url: str) -> PinnedAddress:
        parsed = urlsplit(canonicalize_url(url))
        if parsed.scheme != "https":
            raise ResearchRuntimeError("research_https_required")
        port = parsed.port or 443
        addresses = self._resolver(parsed.hostname or "", port)
        public = [item for item in addresses if not _forbidden_ip(item)]
        if not public:
            raise ResearchRuntimeError("research_address_forbidden")
        return PinnedAddress(parsed.hostname or "", sorted(public)[0], port)

    def fetch(self, url: str) -> StaticEvidence:
        requested = canonicalize_url(url)
        current = requested
        chain = [current]
        context = ssl.create_default_context()
        for redirect in range(self.max_redirects + 1):
            parsed = urlsplit(current)
            pinned = self.resolve_public(current)
            connection = self._connection_factory(
                pinned.host, pinned.address, pinned.port, self.timeout_seconds, context
            )
            path = parsed.path or "/"
            if parsed.query:
                path += f"?{parsed.query}"
            try:
                connection.request(
                    "GET",
                    path,
                    headers={
                        "Host": pinned.host,
                        "Accept": "text/html,text/plain,text/markdown,application/json,application/xml,text/xml;q=0.9,*/*;q=0.1",
                        "User-Agent": "KristinResearch/1",
                        "Connection": "close",
                    },
                )
                response = connection.getresponse()
                if response.status in {301, 302, 303, 307, 308}:
                    location = response.getheader("Location")
                    response.read()
                    if redirect >= self.max_redirects or not location:
                        raise ResearchRuntimeError("research_redirect_limit")
                    current = canonicalize_url(urljoin(current, location))
                    if urlsplit(current).scheme != "https":
                        raise ResearchRuntimeError("research_redirect_scheme_rejected")
                    chain.append(current)
                    continue
                if not 200 <= response.status < 300:
                    response.read(min(self.max_bytes, 65536))
                    raise ResearchRuntimeError(f"research_http_{response.status}")
                declared = response.getheader("Content-Length")
                if declared and int(declared) > self.max_bytes:
                    raise ResearchRuntimeError("research_body_too_large")
                chunks: list[bytes] = []
                total = 0
                while True:
                    chunk = response.read(min(64 * 1024, self.max_bytes + 1 - total))
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > self.max_bytes:
                        raise ResearchRuntimeError("research_body_too_large")
                    chunks.append(chunk)
                body = b"".join(chunks)
                content_type = (response.getheader("Content-Type") or "application/octet-stream").split(";", 1)[0].strip().lower()
                if content_type not in {
                    "text/html", "text/plain", "text/markdown", "application/json", "application/xml", "text/xml"
                }:
                    raise ResearchRuntimeError("research_mime_rejected")
                selected = {
                    key.lower(): value
                    for key in ("ETag", "Last-Modified", "Cache-Control", "Content-Type")
                    if (value := response.getheader(key))
                }
                return StaticEvidence(
                    requested_url=requested,
                    final_url=current,
                    status=response.status,
                    content_type=content_type,
                    body=body,
                    body_sha256=_sha256_bytes(body),
                    fetched_at=_utc_now(),
                    pinned_address=pinned.address,
                    redirect_chain=tuple(chain),
                    headers=selected,
                )
            finally:
                connection.close()
        raise ResearchRuntimeError("research_redirect_limit")


@dataclass(frozen=True)
class RenderedEvidence:
    final_url: str
    title: str
    dom: str
    visible_text: str
    screenshot_sha256: str | None
    observation_hash: str
    rendered_at: str


class RenderedFetcher(Protocol):
    def fetch_rendered(self, url: str) -> RenderedEvidence: ...


class _ReadableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title = ""
        self.author: str | None = None
        self.published_at: str | None = None
        self.headings: list[str] = []
        self.lists: list[str] = []
        self.links: list[tuple[str, str]] = []
        self.code: list[str] = []
        self.text: list[str] = []
        self._stack: list[str] = []
        self._href: str | None = None
        self._skip_depth = 0
        self._metadata: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        lower = tag.lower()
        self._stack.append(lower)
        attrs_map = {key.lower(): value or "" for key, value in attrs}
        if lower in {"script", "style", "noscript"}:
            self._skip_depth += 1
        if lower == "a":
            self._href = attrs_map.get("href")
        if lower == "meta":
            key = (attrs_map.get("name") or attrs_map.get("property") or "").lower()
            content = attrs_map.get("content", "")
            if key and content:
                self._metadata[key] = content

    def handle_endtag(self, tag: str) -> None:
        lower = tag.lower()
        if lower in {"script", "style", "noscript"} and self._skip_depth:
            self._skip_depth -= 1
        if lower == "a":
            self._href = None
        if self._stack:
            self._stack.pop()

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        value = " ".join(data.split())
        if not value:
            return
        tag = self._stack[-1] if self._stack else ""
        if tag == "title":
            self.title = f"{self.title} {value}".strip()
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self.headings.append(value)
        if tag == "li":
            self.lists.append(value)
        if tag in {"code", "pre"}:
            self.code.append(value)
        if tag == "a" and self._href:
            self.links.append((value, self._href))
        self.text.append(value)

    def finalize(self) -> None:
        self.author = self._metadata.get("author") or self._metadata.get("article:author")
        self.published_at = self._metadata.get("article:published_time") or self._metadata.get("date")


@dataclass(frozen=True)
class ExtractedDocument:
    source_url: str
    source_hash: str
    title: str
    author: str | None
    published_at: str | None
    text: str
    headings: tuple[str, ...]
    lists: tuple[str, ...]
    links: tuple[tuple[str, str], ...]
    code_blocks: tuple[str, ...]
    structured: Mapping[str, object]
    extraction_hash: str
    diagnostics: tuple[str, ...]


class StructuredDataExtractor:
    _json_ld = re.compile(
        r"<script\b[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>",
        re.I | re.S,
    )
    _table = re.compile(r"<table\b[^>]*>(.*?)</table>", re.I | re.S)
    _row = re.compile(r"<tr\b[^>]*>(.*?)</tr>", re.I | re.S)
    _cell = re.compile(r"<t[hd]\b[^>]*>(.*?)</t[hd]>", re.I | re.S)

    def extract(self, raw_html: str) -> Mapping[str, object]:
        json_ld: list[object] = []
        for match in self._json_ld.finditer(raw_html):
            try:
                json_ld.append(json.loads(html.unescape(match.group(1)).strip()))
            except json.JSONDecodeError:
                continue
        tables: list[list[list[str]]] = []
        for table in self._table.finditer(raw_html):
            rows: list[list[str]] = []
            for row in self._row.finditer(table.group(1)):
                cells = [
                    " ".join(re.sub(r"<[^>]+>", " ", html.unescape(cell)).split())
                    for cell in self._cell.findall(row.group(1))
                ]
                if cells:
                    rows.append(cells)
            if rows:
                tables.append(rows)
        og = {
            key.lower(): value
            for key, value in re.findall(
                r"<meta\b[^>]*(?:property|name)=[\"'](og:[^\"']+)[\"'][^>]*content=[\"']([^\"']*)[\"'][^>]*>",
                raw_html,
                re.I,
            )
        }
        forms = len(re.findall(r"<form\b", raw_html, re.I))
        assets = tuple(
            sorted(
                set(
                    re.findall(
                        r"(?:href|src)=[\"']([^\"']+\.(?:csv|json|xml|pdf|zip))[\"']",
                        raw_html,
                        re.I,
                    )
                )
            )
        )
        return {"jsonLd": json_ld, "tables": tables, "openGraph": og, "formCount": forms, "assets": assets}


class ReadableExtractor:
    def __init__(self, structured: StructuredDataExtractor | None = None, max_text_chars: int = 1_000_000) -> None:
        self.structured = structured or StructuredDataExtractor()
        self.max_text_chars = max_text_chars

    def extract(self, evidence: StaticEvidence | RenderedEvidence) -> ExtractedDocument:
        if isinstance(evidence, StaticEvidence):
            raw = evidence.body.decode("utf-8", errors="replace")
            source_url = evidence.final_url
            source_hash = evidence.body_sha256
        else:
            raw = evidence.dom
            source_url = evidence.final_url
            source_hash = evidence.observation_hash
        parser = _ReadableParser()
        parser.feed(raw)
        parser.finalize()
        text = "\n".join(parser.text)
        diagnostics: list[str] = []
        if len(text) > self.max_text_chars:
            text = text[: self.max_text_chars]
            diagnostics.append("text_truncated")
        structured = self.structured.extract(raw)
        canonical = json.dumps(
            {
                "sourceUrl": source_url,
                "sourceHash": source_hash,
                "title": parser.title,
                "author": parser.author,
                "publishedAt": parser.published_at,
                "text": text,
                "headings": parser.headings,
                "lists": parser.lists,
                "links": parser.links,
                "code": parser.code,
                "structured": structured,
            },
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        )
        return ExtractedDocument(
            source_url=source_url,
            source_hash=source_hash,
            title=parser.title or urlsplit(source_url).hostname or source_url,
            author=parser.author,
            published_at=parser.published_at,
            text=text,
            headings=tuple(parser.headings),
            lists=tuple(parser.lists),
            links=tuple((label, urljoin(source_url, href)) for label, href in parser.links),
            code_blocks=tuple(parser.code),
            structured=structured,
            extraction_hash=_sha256_text(canonical),
            diagnostics=tuple(diagnostics),
        )


@dataclass(frozen=True)
class CrawlLimits:
    max_pages: int = 100
    max_depth: int = 3
    max_bytes: int = 32 * 1024 * 1024
    max_seconds: float = 120.0
    per_host_delay_seconds: float = 0.25

    def __post_init__(self) -> None:
        if not 1 <= self.max_pages <= 5000 or not 0 <= self.max_depth <= 12:
            raise ResearchRuntimeError("crawl_limits_invalid")
        if not 1024 <= self.max_bytes <= 2 * 1024 * 1024 * 1024:
            raise ResearchRuntimeError("crawl_limits_invalid")
        if not 1 <= self.max_seconds <= 3600 or not 0 <= self.per_host_delay_seconds <= 60:
            raise ResearchRuntimeError("crawl_limits_invalid")


@dataclass(frozen=True)
class CrawlCheckpoint:
    frontier: tuple[tuple[str, int], ...]
    visited: tuple[str, ...]
    bytes_fetched: int


@dataclass(frozen=True)
class CrawlPage:
    url: str
    depth: int
    body_sha256: str
    extraction_hash: str
    title: str


@dataclass(frozen=True)
class CrawlResult:
    pages: tuple[CrawlPage, ...]
    checkpoint: CrawlCheckpoint
    stopped_reason: str


class ResearchCrawler:
    def __init__(self, fetcher: SafePinnedFetcher, extractor: ReadableExtractor | None = None) -> None:
        self.fetcher = fetcher
        self.extractor = extractor or ReadableExtractor()

    def crawl(
        self,
        seed_url: str,
        *,
        limits: CrawlLimits = CrawlLimits(),
        checkpoint: CrawlCheckpoint | None = None,
        robots_loader: Callable[[str], str] | None = None,
    ) -> CrawlResult:
        seed = canonicalize_url(seed_url)
        seed_host = urlsplit(seed).hostname
        if checkpoint:
            frontier = list(checkpoint.frontier)
            visited = set(checkpoint.visited)
            bytes_fetched = checkpoint.bytes_fetched
        else:
            frontier = [(seed, 0)]
            visited: set[str] = set()
            bytes_fetched = 0
        pages: list[CrawlPage] = []
        handled = set(visited)
        started = time.monotonic()
        robots_by_origin: dict[str, RobotFileParser] = {}
        last_host_at: dict[str, float] = {}
        reason = "frontier_exhausted"
        while frontier:
            if len(visited) >= limits.max_pages:
                reason = "max_pages"
                break
            if bytes_fetched >= limits.max_bytes:
                reason = "max_bytes"
                break
            if time.monotonic() - started >= limits.max_seconds:
                reason = "max_time"
                break
            current, depth = frontier.pop(0)
            canonical = canonicalize_url(current)
            if canonical in handled or depth > limits.max_depth:
                continue
            parsed = urlsplit(canonical)
            if parsed.hostname != seed_host:
                continue
            origin = f"{parsed.scheme}://{parsed.netloc}"
            robots = robots_by_origin.get(origin)
            if robots is None:
                robots = RobotFileParser()
                robots.set_url(f"{origin}/robots.txt")
                text = robots_loader(origin) if robots_loader else "User-agent: *\nAllow: /\n"
                robots.parse(text.splitlines())
                robots_by_origin[origin] = robots
            if not robots.can_fetch("KristinResearch/1", canonical):
                handled.add(canonical)
                continue
            previous = last_host_at.get(parsed.hostname or "", 0.0)
            delay = limits.per_host_delay_seconds - (time.monotonic() - previous)
            if delay > 0:
                time.sleep(delay)
            evidence = self.fetcher.fetch(canonical)
            last_host_at[parsed.hostname or ""] = time.monotonic()
            bytes_fetched += len(evidence.body)
            if bytes_fetched > limits.max_bytes:
                reason = "max_bytes"
                break
            extracted = self.extractor.extract(evidence)
            visited.add(canonical)
            handled.add(canonical)
            pages.append(CrawlPage(canonical, depth, evidence.body_sha256, extracted.extraction_hash, extracted.title))
            if depth < limits.max_depth:
                for _, href in extracted.links:
                    try:
                        next_url = canonicalize_url(href)
                    except ResearchRuntimeError:
                        continue
                    if urlsplit(next_url).hostname == seed_host and next_url not in handled:
                        frontier.append((next_url, depth + 1))
                frontier = list(dict.fromkeys(frontier))
        saved = CrawlCheckpoint(tuple(frontier), tuple(sorted(visited)), bytes_fetched)
        return CrawlResult(tuple(pages), saved, reason)
