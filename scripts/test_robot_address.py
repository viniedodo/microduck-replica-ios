#!/usr/bin/env python3
"""Reference checks for RobotAddress.parse rules. Keep in sync with Tools/RobotAddressTests.swift."""
from __future__ import annotations

import ipaddress
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse, urlunparse

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "scripts" / "address_fixtures.json"
DEFAULT_PORT = 8000
DEFAULT_SCHEME = "https"
HOSTNAME_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", re.IGNORECASE)


class ParseError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def is_ipv4(host: str) -> bool:
    parts = host.split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdigit() or len(p) > 3 or (len(p) > 1 and p.startswith("0")):
            return False
        n = int(p, 10)
        if n < 0 or n > 255:
            return False
    return True


def is_ipv6(host: str) -> bool:
    h = host[1:-1] if host.startswith("[") and host.endswith("]") else host
    try:
        ipaddress.IPv6Address(h)
        return True
    except ipaddress.AddressValueError:
        return False


def is_hostname(host: str) -> bool:
    if host.startswith(".") or host.endswith(".") or ".." in host:
        return False
    if len(host) > 253:
        return False
    labels = host.split(".")
    if not labels:
        return False
    for label in labels:
        if not label or len(label) > 63 or not HOSTNAME_RE.match(label):
            return False
    return True


def looks_like_ipv4(host: str) -> bool:
    parts = host.split(".")
    return len(parts) == 4 and all(p.isdigit() for p in parts)


def is_valid_host(host: str) -> bool:
    if looks_like_ipv4(host):
        return is_ipv4(host)
    return is_ipv6(host) or is_hostname(host)


def scheme_prefix(text: str) -> str | None:
    lowered = text.lower()
    i = lowered.find("://")
    return lowered[:i] if i != -1 else None


def reject_disallowed_scheme(trimmed: str) -> None:
    if ":" not in trimmed:
        return
    head, rest = trimmed.split(":", 1)
    if not head or not head[0].isalpha():
        return
    if any(not (ch.isalnum() or ch in "+.-") for ch in head):
        return
    lowered = head.lower()
    if lowered in ("http", "https"):
        if not rest.startswith("//"):
            raise ParseError("invalidScheme")
        return
    if rest.startswith("//"):
        raise ParseError("invalidScheme")
    port_part = rest.split("/", 1)[0]
    if port_part.isdigit() and 1 <= int(port_part, 10) <= 65535:
        return
    raise ParseError("invalidScheme")


def parse(raw: str, page: str) -> dict:
    trimmed = raw.strip()
    if not trimmed:
        raise ParseError("empty")
    if "@" in trimmed:
        raise ParseError("credentialsForbidden")
    reject_disallowed_scheme(trimmed)
    prefix = scheme_prefix(trimmed)
    text = trimmed
    if prefix is None:
        text = f"{DEFAULT_SCHEME}://{text}"
    parsed = urlparse(text)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https"):
        raise ParseError("invalidScheme")
    if parsed.username is not None or parsed.password is not None:
        raise ParseError("credentialsForbidden")
    host = parsed.hostname or ""
    if host.startswith("[") and host.endswith("]") and len(host) >= 2:
        host = host[1:-1]
    if not host:
        raise ParseError("missingHost")
    if looks_like_ipv4(host):
        if not is_ipv4(host):
            raise ParseError("invalidHost")
    elif is_ipv6(host):
        pass
    elif is_hostname(host):
        host = host.lower()
    else:
        raise ParseError("invalidHost")
    if parsed.port is None:
        # urlparse may raise or return None if no port
        port = DEFAULT_PORT
    else:
        port = parsed.port
        if not (1 <= port <= 65535):
            raise ParseError("invalidPort")
    path = "/m" if page == "mobile" else "/"
    host_part = f"[{host}]" if ":" in host and not host.startswith("[") else host
    url = f"{scheme}://{host_part}:{port}{path}"
    return {"scheme": scheme, "host": host, "port": port, "url": url}


def _port_or_error(raw: str) -> None:
    # urlparse raises ValueError on out-of-range ports; map to invalidPort
    pass


def safe_parse(raw: str, page: str) -> dict:
    try:
        return parse(raw, page)
    except ParseError:
        raise
    except ValueError as exc:
        msg = str(exc).lower()
        if "port" in msg:
            raise ParseError("invalidPort") from exc
        raise ParseError("invalidURL") from exc


def main() -> int:
    data = json.loads(FIXTURES.read_text(encoding="utf-8"))
    failed = 0

    for case in data["accept"]:
        try:
            got = safe_parse(case["raw"], case["page"])
        except ParseError as exc:
            failed += 1
            print(f"FAIL accept {case['raw']!r}: raised {exc.code}")
            continue
        for key in ("scheme", "host", "port", "url"):
            if got[key] != case[key]:
                failed += 1
                print(f"FAIL accept {case['raw']!r} {key}: got {got[key]!r} want {case[key]!r}")
                break
        else:
            print(f"OK   accept {case['raw']!r} -> {got['url']}")

    for case in data["reject"]:
        try:
            got = safe_parse(case["raw"], case["page"])
        except ParseError as exc:
            if exc.code != case["error"]:
                failed += 1
                print(f"FAIL reject {case['raw']!r}: got {exc.code} want {case['error']}")
            else:
                print(f"OK   reject {case['raw']!r} ({exc.code})")
            continue
        failed += 1
        print(f"FAIL reject {case['raw']!r}: unexpectedly accepted as {got['url']}")

    if failed:
        print(f"\n{failed} failure(s)")
        return 1
    print("\nAll address fixture tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
