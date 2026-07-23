#!/usr/bin/env python3
"""Pinned public-HTTPS network broker for Kristin.

The broker deliberately exposes only bounded HTTPS GET so sandboxed workers can
retrieve public research material without receiving unrestricted network access.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import ipaddress
import json
from pathlib import Path
import socket
import ssl
import sys
import urllib.parse
from typing import Iterable, Any

DEFAULT_USER_AGENT = "Kristin-Network-Broker/1.9.0+190"


class NetworkBrokerError(RuntimeError):
    pass


def _normalize_host(host: str) -> str:
    return host.strip().rstrip(".").lower()


def _is_public_ip(value: str) -> bool:
    ip = ipaddress.ip_address(value)
    return not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    )


def resolve_public_addresses(host: str) -> list[str]:
    normalized = _normalize_host(host)
    if not normalized:
        raise NetworkBrokerError("network broker requires a host name")
    try:
        infos = socket.getaddrinfo(normalized, 443, type=socket.SOCK_STREAM)
    except socket.gaierror as exc:
        raise NetworkBrokerError(f"DNS resolution failed for {normalized}") from exc
    addresses = sorted({info[4][0] for info in infos})
    if not addresses:
        raise NetworkBrokerError(f"no DNS addresses were returned for {normalized}")
    non_public = [address for address in addresses if not _is_public_ip(address)]
    if non_public:
        raise NetworkBrokerError(
            "network broker refuses private, loopback, link-local, or reserved destinations"
        )
    return addresses


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, *, host: str, ip: str, port: int, timeout: float, context: ssl.SSLContext) -> None:
        super().__init__(host=host, port=port, timeout=timeout, context=context)
        self._pinned_ip = ip

    def connect(self) -> None:  # pragma: no cover - exercised through fetch_https
        sock = socket.create_connection((self._pinned_ip, self.port), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)


def _validate_url(url: str, allow_hosts: Iterable[str] | None = None) -> tuple[str, int, str]:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme.lower() != "https":
        raise NetworkBrokerError("network broker allows only https URLs")
    if parsed.username or parsed.password:
        raise NetworkBrokerError("network broker rejects embedded URL credentials")
    host = _normalize_host(parsed.hostname or "")
    if not host:
        raise NetworkBrokerError("network broker requires a host name")
    if allow_hosts:
        allowed = {_normalize_host(value) for value in allow_hosts if value}
        if host not in allowed:
            raise NetworkBrokerError(f"host {host} is not on the allowlist")
    port = parsed.port or 443
    if port != 443:
        raise NetworkBrokerError("network broker permits only port 443")
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    return host, port, path


def fetch_https(
    url: str,
    *,
    allow_hosts: Iterable[str] | None = None,
    max_redirects: int = 3,
    max_bytes: int = 256 * 1024,
    timeout: float = 10.0,
    user_agent: str = DEFAULT_USER_AGENT,
) -> dict[str, Any]:
    current = url
    context = ssl.create_default_context()
    redirects: list[str] = []
    for _ in range(max(0, max_redirects) + 1):
        host, port, path = _validate_url(current, allow_hosts=allow_hosts)
        addresses = resolve_public_addresses(host)
        pinned_ip = addresses[0]
        connection = PinnedHTTPSConnection(
            host=host,
            ip=pinned_ip,
            port=port,
            timeout=timeout,
            context=context,
        )
        connection.request(
            "GET",
            path,
            headers={
                "Host": host,
                "User-Agent": user_agent,
                "Accept": "text/html,application/json,text/plain;q=0.9,*/*;q=0.1",
                "Connection": "close",
            },
        )
        response = connection.getresponse()
        status = int(response.status)
        location = response.getheader("Location")
        if status in {301, 302, 303, 307, 308}:
            if not location:
                raise NetworkBrokerError("redirect response omitted its Location header")
            next_url = urllib.parse.urljoin(current, location)
            redirects.append(next_url)
            current = next_url
            connection.close()
            continue
        payload = response.read(max_bytes + 1)
        connection.close()
        if len(payload) > max_bytes:
            raise NetworkBrokerError(f"response exceeded the {max_bytes}-byte broker limit")
        content_type = response.getheader("Content-Type") or "application/octet-stream"
        return {
            "url": current,
            "host": host,
            "ip": pinned_ip,
            "status": status,
            "contentType": content_type,
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
            "redirects": redirects,
            "bodyPreview": payload.decode("utf-8", errors="replace")[:4096],
        }
    raise NetworkBrokerError(f"redirect chain exceeded the {max_redirects}-hop limit")


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kristin public HTTPS broker")
    parser.add_argument("url")
    parser.add_argument("--allow-host", action="append", default=[])
    parser.add_argument("--max-redirects", type=int, default=3)
    parser.add_argument("--max-bytes", type=int, default=256 * 1024)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    result = fetch_https(
        args.url,
        allow_hosts=args.allow_host,
        max_redirects=args.max_redirects,
        max_bytes=args.max_bytes,
        timeout=args.timeout,
    )
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.output is not None:
        args.output.write_text(text + "\n", encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
