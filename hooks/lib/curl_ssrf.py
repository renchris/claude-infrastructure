"""curl_ssrf.py — the ONE internal-address normalizer shared by curl-gate.py and smart-bash-allowlist.py.

WHY ONE COPY (2026-09-29, hook-ask decisions round 2, docs/research/hook-ask-confirmations-2026-09-28.md
§6). Both hooks answered "is this curl target internal?" by string prefix (`169.254.`, `10.`, …), so
every other spelling of the same address walked past them: decimal `2852039166`, hex `0xA9FEA9FE`,
octal `0251.0376.0251.0376`, IPv4-mapped `[::ffff:169.254.169.254]`, AWS IMDSv6 `[fd00:ec2::254]`,
and DNS names that encode an IP (`169.254.169.254.nip.io`). curl hands a numeric host to the libc
parser (inet_aton rules), which accepts all of those. smart-bash-allowlist hook-ALLOWED them outside
reso with the classifier skipped. Two copies of this logic drift; this module is the fix for both.

Also here: the routing census that decides where a connection actually goes regardless of the URL
(--resolve / --connect-to targets, proxy environment variables, curlrc relocation). Import-safe: no
I/O and no environment reads at import time.
"""

from __future__ import annotations

import ipaddress
import os
import re
import socket

_NUMERIC_HOST_RE = re.compile(
    r"^(?:0x[0-9a-f]*|[0-9]+)(?:\.(?:0x[0-9a-f]*|[0-9]+)){0,3}$", re.I
)
_RFC1918 = tuple(
    ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)
_ULA = ipaddress.ip_network("fc00::/7")  # covers AWS IMDSv6 fd00:ec2::254
_NAT64 = ipaddress.ip_network("64:ff9b::/96")

# Named metadata endpoints that resolve to link-local on the cloud that owns them.
METADATA_HOSTS = frozenset({"metadata.google.internal", "metadata.goog", "metadata"})

# Public wildcard-DNS services that answer any name with the IP spelled inside it.
_IP_IN_DNS_SUFFIXES = (".nip.io", ".sslip.io", ".xip.io", ".traefik.me")
_DOTTED4_RE = re.compile(r"(?:^|[.-])(\d{1,3}(?:[.-]\d{1,3}){3})(?=$|[.-])")
_HEX8_RE = re.compile(r"(?:^|[.-])([0-9a-f]{8})(?=$|[.-])", re.I)


def host_ip(host: str | None):
    """The address curl would connect to for a NUMERIC host, in any spelling; else None."""
    h = (host or "").lower().strip().strip("[]").rstrip(".").split("%", 1)[0]
    if not h:
        return None
    try:
        ip = ipaddress.ip_address(h)
    except ValueError:
        if not _NUMERIC_HOST_RE.match(h):
            return None
        try:
            ip = ipaddress.IPv4Address(socket.inet_aton(h))
        except OSError:
            return None
    if ip.version == 6:
        if ip.ipv4_mapped is not None:
            ip = ip.ipv4_mapped
        elif ip in _NAT64:
            ip = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
    return ip


def _ip_is_internal(ip) -> bool:
    """Link-local, RFC1918, ULA. Loopback and 0.0.0.0 are NOT internal here: they stay governed by
    the callers' own dev-port / loopback rules, which is where they always lived."""
    if ip is None or ip.is_loopback or ip.is_unspecified:
        return False
    if ip.version == 4:
        return ip.is_link_local or any(ip in n for n in _RFC1918)
    return ip.is_link_local or ip.is_site_local or ip in _ULA


def _encoded_ips(host: str) -> list:
    """IPs spelled inside a wildcard-DNS name: 10.0.0.1.nip.io, 10-0-0-1.sslip.io, a9fea9fe.nip.io,
    fd00-ec2--254.sslip.io."""
    for sfx in _IP_IN_DNS_SUFFIXES:
        if host.endswith(sfx):
            label = host[: -len(sfx)]
            break
    else:
        return []
    out = []
    for m in _DOTTED4_RE.finditer(label):
        out.append(host_ip(m.group(1).replace("-", ".")))
    for m in _HEX8_RE.finditer(label):
        out.append(ipaddress.IPv4Address(int(m.group(1), 16)))
    last = label.rsplit(".", 1)[-1]
    if "--" in last or last.count("-") >= 2:
        out.append(host_ip(last.replace("-", ":")))
    return [ip for ip in out if ip is not None]


def is_internal_host(host: str | None) -> bool:
    """True when `host` names cloud metadata, a private network, or link-local, in ANY spelling."""
    h = (host or "").lower().strip().strip("[]").rstrip(".")
    if not h:
        return False
    if h in ("localhost", "127.0.0.1", "0.0.0.0"):
        return False  # loopback: the callers' dev-port rules own it
    # Incumbent string rules, kept verbatim so no host that was internal before stops being so.
    if h.startswith(("169.254.", "10.", "192.168.")):
        return True
    if h.startswith("172."):
        try:
            if 16 <= int(h.split(".")[1]) <= 31:
                return True
        except (IndexError, ValueError):
            pass
    if h in METADATA_HOSTS:
        return True
    if _ip_is_internal(host_ip(h)):
        return True
    return any(_ip_is_internal(ip) for ip in _encoded_ips(h))


# ── Routing: where the connection goes regardless of the URL's host ─────────────────────────────

ROUTE_FLAGS = frozenset({"--resolve", "--connect-to"})
PROXY_FLAGS = frozenset(
    {
        "-x",
        "--proxy",
        "--proxy1.0",
        "--preproxy",
        "--socks4",
        "--socks4a",
        "--socks5",
        "--socks5-hostname",
    }
)
SOCKET_FLAGS = frozenset({"--unix-socket", "--abstract-unix-socket"})
DNS_FLAGS = frozenset({"--doh-url", "--dns-servers"})
# curl 8.3+ builds a URL from a variable at run time, so the URL as written names no real host.
EXPAND_FLAGS_PREFIX = "--expand-"

# A proxy environment variable assigned anywhere in the command. curl honours [scheme]_proxy and
# ALL_PROXY; no_proxy only narrows, so it is not listed.
ENV_PROXY_RE = re.compile(
    r"(?i)(?:^|[\s;&|(])(?:export\s+)?(?:all|https?|ftp|ftps|socks\w*)_proxy="
)
# Assignments that move where curl looks for its default config file (curlrc can carry proxy,
# resolve and connect-to lines the command text never shows).
ENV_CURLRC_RE = re.compile(
    r"(?:^|[\s;&|(])(?:export\s+)?(?:CURL_HOME|XDG_CONFIG_HOME|HOME)="
)


def _split_host(s: str) -> tuple[str | None, str]:
    """(host, remainder-after-colon) with bracketed IPv6 support; host None if malformed."""
    if s.startswith("["):
        end = s.find("]")
        if end < 0:
            return None, ""
        host, rest = s[1:end], s[end + 1 :]
        return host, rest[1:] if rest.startswith(":") else rest
    host, _, rest = s.partition(":")
    return host, rest


def route_target_hosts(flag: str, val: str) -> list:
    """Addresses a --resolve / --connect-to value sends the connection to.

    Returns a list of host strings; a None entry means UNDECIDABLE (a shell expansion, a malformed
    value). An empty list means the value routes nowhere new (a `-host:port` removal, or a
    --connect-to whose HOST2 is empty, which keeps the original host).
    """
    if "$" in val or "`" in val:
        return [None]
    v = val.strip()
    if flag == "--resolve":
        if v.startswith("-"):
            return []  # `-host:port` removes a cache entry; it adds no target
        v = v.lstrip("+")
        _h1, rest = _split_host(v)
        port, _, addrs = rest.partition(":")
        if _h1 is None or not port or not addrs:
            return [None]
        out = []
        for a in addrs.split(","):
            a = a.strip()
            if a:
                out.append(a.strip("[]"))
        return out or [None]
    # --connect-to HOST1:PORT1:HOST2:PORT2 (HOST1/PORT1/HOST2/PORT2 may be empty)
    h1, rest = _split_host(v)
    if h1 is None:
        return [None]
    _p1, sep, rest = rest.partition(":")
    if not sep:
        return [None]
    h2, _p2 = _split_host(rest)
    if h2 is None:
        return [None]
    return [h2] if h2 else []


def default_curlrc_present(env: dict | None = None) -> str | None:
    """Path of a default curlrc curl would read at run time, if one exists; else None."""
    env = os.environ if env is None else env
    home = env.get("HOME") or os.path.expanduser("~")
    xdg = env.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    cands = []
    if env.get("CURL_HOME"):
        cands.append(os.path.join(env["CURL_HOME"], ".curlrc"))
    cands += [
        os.path.join(xdg, "curlrc"),
        os.path.join(xdg, ".curlrc"),
        os.path.join(home, ".curlrc"),
    ]
    for c in cands:
        if os.path.isfile(c):
            return c
    return None
