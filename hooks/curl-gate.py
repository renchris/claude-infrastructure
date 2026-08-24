#!/usr/bin/env python3
"""
curl-gate.py — PreToolUse hook for safe curl invocation.

Project-scoped (fires only inside reso-management-app). Parses curl args with
shlex + urllib (not regex) to defeat query-string host-injection attacks.

Decision matrix:
  - Non-curl Bash: pass through (exit 0, no stdout)
  - Pipe-to-shell EXCEPT canonical fly.io/install.sh: deny
  - file:// scheme: deny
  - Internal-network targets (169.254.169.254 / RFC1918): deny
  - --insecure / -k: deny
  - Output to sensitive paths (.env, .ssh, .claude, .aws, /etc, /usr, /var): deny
  - @file upload of sensitive files: deny
  - HEAD/GET to allowlisted hosts: allow
  - POST to per-method allowlist (Grafana, Slack, reso.gl /api/logs): allow
  - Default: ask

Fail-closed: any unhandled exception emits deny.

Audit: appends decision to ~/.reso/curl-audit.jsonl.

Kill switch: env CURL_GATE_DISABLED=1.
"""

import json
import os
import re
import shlex
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

PROJECT_ROOT = "/Users/chrisren/Development/reso-management-app"
AUDIT_LOG = Path.home() / ".reso" / "curl-audit.jsonl"

# How far up from cwd to look for a worktree's `.git` pointer. Bounded so a
# pathological cwd can never turn this hook into an unbounded filesystem walk.
_SCOPE_WALK_MAX = 12


def in_project_scope(cwd: str) -> bool:
    """True when `cwd` is inside the reso project, including its linked worktrees.

    `cwd.startswith(PROJECT_ROOT)` alone is NOT sufficient: reso's worktrees are
    created under ~/Development/.worktrees/, which shares no prefix with
    PROJECT_ROOT. Measured 2026-08-10: 64 live reso worktrees sat outside the
    prefix, so every curl rule — pipe-to-shell, IMDS/private hosts, unsafe TLS,
    file://, sensitive uploads — exited 0 with no decision in all of them.

    A linked worktree's `.git` is a FILE holding `gitdir: <main>/.git/worktrees/<name>`;
    a primary checkout's `.git` is a DIRECTORY. Walking up until one of those is
    found tells us which repo owns `cwd` without shelling out to git.
    """
    if cwd.startswith(PROJECT_ROOT):
        return True
    try:
        here = Path(cwd)
        for cand in [here, *here.parents][:_SCOPE_WALK_MAX]:
            marker = cand / ".git"
            if marker.is_file():
                first = marker.read_text(errors="replace").split("\n", 1)[0].strip()
                if first.startswith("gitdir:"):
                    return first.split(":", 1)[1].strip().startswith(PROJECT_ROOT)
                return False
            if marker.is_dir():
                return False  # a primary checkout, and not PROJECT_ROOT
    except OSError:
        return False
    return False


# Hostnames that allow read-only methods (GET, HEAD) without prompt.
READ_HOSTS = {
    "harbour.reso.gl",
    "harbourtwo.reso.gl",
    "key.reso.gl",
    "time.reso.gl",
    "envy.reso.gl",
    "gm.reso.gl",
    "apt101.reso.gl",
    "muin.reso.gl",
    "sync-us-nw.reso.gl",
    "sync-us-sw.reso.gl",
    "sync-ap.reso.gl",
    "api.github.com",
    "raw.githubusercontent.com",
    "registry.npmjs.org",
    "ipinfo.io",
    "fly.io",
}

# Suffix matches (for *.fly.dev, *.amplifyapp.com, *.grafana.net, *.reso.gl)
READ_HOST_SUFFIXES = (
    ".fly.dev",
    ".amplifyapp.com",
    ".grafana.net",
    ".reso.gl",  # covers any tenant subdomain
)

# Hostnames that allow POST (writes). Stricter set.
POST_HOSTS = {
    "hooks.slack.com",
}
POST_HOST_SUFFIXES = (
    ".grafana.net",  # Grafana annotations / SM / Oncall API
    ".reso.gl",  # POST /api/logs ingestion; reuse tenant allowlist
)

# Methods considered safe-by-default for allowlisted read hosts.
SAFE_METHODS = {"GET", "HEAD"}

# Sensitive path fragments — block writes / uploads here.
SENSITIVE_PATHS = (
    ".env",
    ".ssh/",
    ".aws/",
    ".claude/",
    ".gnupg/",
    "/etc/",
    "/usr/",
    "/var/",
    "id_rsa",
    "id_ed25519",
)


# Internal-IP regexes — checked by string-startswith on parsed host.
def is_internal_host(host: str) -> bool:
    if not host:
        return False
    host = host.lower()
    if host in ("localhost", "127.0.0.1", "0.0.0.0"):
        # Allow localhost only for known dev ports
        return False  # handled separately for dev ports
    if host == "169.254.169.254":
        return True  # cloud-metadata service
    if host.startswith("169.254."):
        return True
    if host.startswith("10."):
        return True
    if host.startswith("192.168."):
        return True
    # 172.16.0.0 - 172.31.255.255
    if host.startswith("172."):
        try:
            second = int(host.split(".")[1])
            if 16 <= second <= 31:
                return True
        except (IndexError, ValueError):
            pass
    return False


def emit(
    decision: str,
    reason: str,
    parsed_meta: dict,
    cmd: str,
    session_id: str,
    tool_use_id: str,
    cwd: str,
) -> None:
    """Write audit log + emit decision JSON."""
    log_record = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "decision": decision,
        "reason": reason,
        "cmd_redacted": redact(cmd),
        "host": parsed_meta.get("host"),
        "method": parsed_meta.get("method"),
        "session_id": session_id,
        "tool_use_id": tool_use_id,
        "cwd": cwd,
    }
    try:
        AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT_LOG.open("a", encoding="utf-8") as f:
            f.write(json.dumps(log_record) + "\n")
    except OSError:
        pass  # never fail the gate on log error

    if decision == "allow":
        # Empty stdout = implicit allow (let downstream hooks decide too)
        sys.exit(0)

    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(payload))
    sys.exit(0)


def redact(cmd: str) -> str:
    """Strip query-string secrets from logged command."""
    import re

    cmd = re.sub(
        r"([?&](?:token|api[_-]?key|secret|password|auth)=)[^&\s]+",
        r"\1[REDACTED]",
        cmd,
        flags=re.IGNORECASE,
    )
    return cmd


# ── Curl options that CONSUME THE NEXT ARGV TOKEN ────────────────────────────────────────────────
# WHY THIS TABLE EXISTS (measured 2026-08-23). parse_curl() used to know only the ~8 value-taking
# flags it had explicit handlers for. Every OTHER flag fell through `elif t.startswith("-")`, which
# advances by ONE — so the flag's VALUE landed in the positional branch and was judged as a URL.
# `-A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ..."` contains both a "."
# and a "/", so it was promoted to `https://Mozilla/5.0 (Macintosh; ...` and urlparse read the host
# as "mozilla". The gate then asked "GET to unknown host mozilla" — and because decide() returns on
# the FIRST unrecognised host, it never even reached the real URL sitting later in the same argv.
#
# That single defect was 894 of the 1,970 asks in ~/.reso/curl-audit.jsonl (45%), and over the seven
# days to 2026-08-23 it was ~80% of every Bash permission prompt the fleet showed
# (~/.claude/autonomy/permission-archive: 947 of 1,189). `-e/--referer` produced the same class in a
# different disguise — "Non-HTTP scheme: referer" — because a bare referer value has no "://".
#
# THE FIX IS TWO INDEPENDENT LAYERS, deliberately. This table is the PRECISE one: it makes a
# correctly-spelled curl parse correctly. `looks_like_bare_host()` below is the BACKSTOP: it refuses
# to promote a token that is not a syntactically valid host, so the next flag curl adds — or any
# flag missing from this table — degrades to "not a URL" instead of to "a URL on a host named after
# whatever word came first". A table alone would have to be exhaustive forever to stay correct; the
# backstop alone would let a genuine bare-host value (`--proxy corp.internal:3128`) be read as a
# target. Neither layer subsumes the other, so both ship.
#
# NOT included, deliberately: -O/--remote-name, -J, -L, -s, -S, -k, -i, -I, -v, -f, --compressed,
# --http1.1/--http2, -N, -g, -6/-4 and the rest of the boolean family — consuming an argument for
# those would EAT THE URL and turn a checkable request into "No URL parsed; review manually".
_VALUE_FLAGS_LONG = frozenset(
    {
        "--user-agent",
        "--header",
        "--cookie",
        "--cookie-jar",
        "--referer",
        "--user",
        "--proxy-user",
        "--proxy",
        "--proxy-header",
        "--noproxy",
        "--preproxy",
        "--max-time",
        "--connect-timeout",
        "--expect100-timeout",
        "--happy-eyeballs-timeout-ms",
        "--retry",
        "--retry-delay",
        "--retry-max-time",
        "--max-redirs",
        "--max-filesize",
        "--limit-rate",
        "--range",
        "--continue-at",
        "--time-cond",
        "--speed-limit",
        "--speed-time",
        "--write-out",
        "--dump-header",
        "--trace",
        "--trace-ascii",
        "--stderr",
        "--output-dir",
        "--cacert",
        "--capath",
        "--cert",
        "--cert-type",
        "--key",
        "--key-type",
        "--pass",
        "--pubkey",
        "--ciphers",
        "--tls13-ciphers",
        "--tlsuser",
        "--tlspassword",
        "--tlsauthtype",
        "--crlfile",
        "--pinnedpubkey",
        "--random-file",
        "--egd-file",
        "--engine",
        "--resolve",
        "--connect-to",
        "--interface",
        "--local-port",
        "--dns-servers",
        "--dns-interface",
        "--dns-ipv4-addr",
        "--dns-ipv6-addr",
        "--doh-url",
        "--form-string",
        "--data-ascii",
        "--json",
        "--oauth2-bearer",
        "--aws-sigv4",
        "--negotiate-delegation",
        "--service-name",
        "--sasl-authzid",
        "--login-options",
        "--mail-from",
        "--mail-rcpt",
        "--mail-auth",
        "--ftp-account",
        "--ftp-alternative-to-user",
        "--ftp-method",
        "--ftp-port",
        "--krb",
        "--quote",
        "--telnet-option",
        "--socks4",
        "--socks4a",
        "--socks5",
        "--socks5-hostname",
        "--socks5-gssapi-service",
        "--hostpubmd5",
        "--hostpubsha256",
        "--proto",
        "--proto-default",
        "--proto-redir",
        "--request-target",
        "--alt-svc",
        "--hsts",
        "--etag-save",
        "--etag-compare",
        "--unix-socket",
        "--abstract-unix-socket",
        "--libcurl",
        "--keepalive-time",
        "--happy-eyeballs-timeout",
        "--parallel-max",
        "--rate",
        "--create-file-mode",
        "--output",
        "--upload-file",
        "--request",
        "--data",
        "--data-raw",
        "--data-binary",
        "--data-urlencode",
        "--form",
        "--config",
        "--url",
        "--variable",
    }
)

# Short forms that take a value. The cluster rule below reads the LAST character of a short cluster,
# because `curl -sSLo out.html URL` is legal and only the trailing `o` consumes an argument.
_VALUE_FLAGS_SHORT = frozenset("AbcCdDeEFHKmoPQrtTuUwxXyYz")


def looks_like_bare_host(tok: str) -> bool:
    """True only for `host[:port][/path]` shapes that a human would call a URL.

    The BACKSTOP layer described above. The incumbent test was `"." in tok and "/" in tok`, which is
    satisfied by an enormous amount of non-URL text — a User-Agent string, a `-w` format containing a
    path, a sed script, a date format. This asks the narrower question the promotion actually needs:
    is everything before the first "/" a syntactically legal host with a dotted TLD-ish tail?
    """
    if not tok or tok.startswith("-") or any(ch.isspace() for ch in tok):
        return False
    authority = tok.split("/", 1)[0].split("?", 1)[0]
    if "@" in authority:  # user:pass@host — keep it out of the bare-host fast path
        return False
    if ":" in authority:
        authority, _, port = authority.partition(":")
        if not port.isdigit():
            return False
    if "." not in authority or authority.endswith("."):
        return False
    labels = authority.split(".")
    if len(labels[-1]) < 2 or not labels[-1].replace("-", "").isalnum():
        return False
    return all(
        lbl
        and not lbl.startswith("-")
        and not lbl.endswith("-")
        and all(c.isalnum() or c == "-" for c in lbl)
        for lbl in labels
    )


def parse_curl(cmd: str) -> dict:
    """Tokenize a curl command and extract URLs + method + flags."""
    # PUNCTUATION-AWARE tokenisation, so the walk below sees ONLY curl's own argv.
    # `shlex.split()` does not treat `;` or `|` as separators, so `curl … -o /tmp/x.bin; file /tmp/x.bin`
    # tokenised as one flat list and the walk ran straight on into the NEXT command's arguments. Two
    # real misreadings came from exactly that: the bare word `file` was promoted to a URL (18 asks
    # reading "Non-HTTP scheme: "), and a downstream `grep -oE` offered its flags to the credential
    # census. The `;` and `|` handling below was written expecting separate tokens and simply never
    # fired. This mode emits them, while leaving a QUOTED separator inside its token — which matters
    # here, because `-A "Mozilla/5.0 (Macintosh; Intel Mac OS X …)"` contains a semicolon.
    # Falls back to the incumbent tokeniser rather than inventing a new deny on a shape only the
    # stricter lexer rejects.
    try:
        lexer = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        try:
            tokens = shlex.split(cmd, posix=True)
        except ValueError:
            return {"error": "shlex parse failed"}

    return parse_argv(tokens, cmd)


def parse_argv(tokens: list[str], cmd: str) -> dict:
    """The argv walk itself, split out so decide_command() can run it per curl invocation.

    `cmd` is still taken because the pipe-to-shell backstop below is a raw-text scan by design —
    it must see a `| bash` anywhere in the command, including in a segment this argv excludes.
    """
    if not tokens or not (tokens[0] == "curl" or tokens[0].endswith("/curl")):
        return {"error": "not a curl command"}

    urls: list[str] = []
    method: str | None = None
    has_data = False
    has_file_upload = False
    has_insecure = False
    has_pipe_to_shell = False
    output_path: str | None = None
    data_file_arg: str | None = None
    config_file: bool = False  # -K
    cred_flags: list[str] = []
    headers: list[str] = []

    i = 1
    while i < len(tokens):
        t = tokens[i]
        # Recognize stop-of-curl when shell metachar inadvertently survived
        # (shlex should have split on |, but defensively):
        if t in ("|", "||", "&&", ";"):
            # Check what follows
            if i + 1 < len(tokens) and tokens[i + 1] in ("bash", "sh", "zsh", "sudo"):
                has_pipe_to_shell = True
            break

        # Credential census — a non-exclusive pre-pass, so it observes every token without taking
        # over consumption from the elif chain below (which is what knows the arity of each flag).
        # It sits INSIDE the walk, and therefore behind the `break` above: a flag belonging to a
        # program on the far side of a pipe is structurally unreachable from here.
        if t in _CRED_FLAG_TOKENS:
            cred_flags.append(t)
        elif t in ("-H", "--header", "--proxy-header"):
            if i + 1 < len(tokens):
                headers.append(tokens[i + 1])
        elif t.startswith("-") and not t.startswith("--") and len(t) > 2:
            if t[1] == "H":
                headers.append(t[2:])  # attached form: -H"Authorization: …"
            elif set(short_cluster_flags(t[1:])) & _CRED_SHORT_CHARS:
                cred_flags.append(t)

        if t in ("-X", "--request"):
            if i + 1 < len(tokens):
                method = tokens[i + 1].upper()
                i += 2
                continue
        elif t.startswith("-X") and len(t) > 2:
            method = t[2:].upper()
            i += 1
            continue
        elif t in (
            "-d",
            "--data",
            "--data-binary",
            "--data-raw",
            "--data-urlencode",
            "-F",
            "--form",
        ):
            has_data = True
            if i + 1 < len(tokens):
                v = tokens[i + 1]
                if v.startswith("@"):
                    data_file_arg = v[1:]
                i += 2
                continue
        elif t in ("-T", "--upload-file"):
            has_file_upload = True
            if i + 1 < len(tokens):
                data_file_arg = tokens[i + 1]
                i += 2
                continue
        elif t in ("-k", "--insecure"):
            has_insecure = True
        elif t in ("-o", "--output", "--output-dir"):
            if i + 1 < len(tokens):
                output_path = tokens[i + 1]
                i += 2
                continue
        elif t == "-K" or t == "--config":
            config_file = True
            i += 1
            continue
        elif t in ("--url",):
            if i + 1 < len(tokens):
                urls.append(tokens[i + 1])
                i += 2
                continue
        elif (
            t.startswith("--") and "=" in t and t.split("=", 1)[0] in _VALUE_FLAGS_LONG
        ):
            # `--max-time=30` — the value is attached, so nothing to consume.
            i += 1
            continue
        elif t in _VALUE_FLAGS_LONG:
            # Known long option that takes a value: consume BOTH tokens, so the value can never
            # reach the positional branch and be judged as a URL.
            i += 2
            continue
        elif t.startswith("-") and not t.startswith("--") and len(t) > 1:
            # Short option or a cluster of them. Only the LAST character of a cluster may take a
            # value (`-sSLo out.html`), and an attached value (`-mo30`, `-A"UA"`) consumes nothing.
            body = t[1:]
            if body[0] in _VALUE_FLAGS_SHORT and len(body) > 1:
                i += 1  # attached value, e.g. -m30 / -XPOST
                continue
            i += 2 if body[-1] in _VALUE_FLAGS_SHORT else 1
            continue
        elif t.startswith("-"):
            # Any other flag (long boolean, or one this table does not know) — skip it alone.
            # If it DID take a value, looks_like_bare_host() below is what stops that value from
            # being promoted into a URL.
            i += 1
            continue
        else:
            # Positional — treat as URL if it carries a scheme, or is a bare `host/path`.
            # The scheme test requires an actual scheme punctuation. The incumbent
            # `t.startswith(("http","ftp","file","//"))` matched the bare command name `file`,
            # producing a URL with no scheme at all and the reason "Non-HTTP scheme: ". Note this
            # does NOT weaken the file:// deny below: both `file:///etc/passwd` and the single-slash
            # `file:/etc/passwd` still match here and still reach that arm.
            if "://" in t or t.startswith("//") or _SCHEME_RE.match(t):
                urls.append(t)
            elif looks_like_bare_host(t):
                # Bare host/path like "harbour.reso.gl/api/health"
                urls.append("https://" + t)
            i += 1
            continue
        i += 1

    # Check trailing pipe via shell metachar in original cmd (shlex strips them)
    # If `| bash` / `| sh` / `| sudo` appears in the raw cmd, flag it.
    import re

    if re.search(r"\|\s*(bash|sh|zsh|sudo)(\s|$)", cmd):
        has_pipe_to_shell = True

    # Default method = GET (curl default)
    if method is None:
        method = "POST" if has_data or has_file_upload else "GET"

    return {
        "cred_flags": cred_flags,
        "headers": headers,
        "urls": urls,
        "method": method,
        "has_data": has_data,
        "has_file_upload": has_file_upload,
        "has_insecure": has_insecure,
        "has_pipe_to_shell": has_pipe_to_shell,
        "output_path": output_path,
        "data_file_arg": data_file_arg,
        "config_file": config_file,
    }


def host_matches(host: str, hosts_set: set[str], suffixes: tuple) -> bool:
    if not host:
        return False
    host = host.lower()
    if host in hosts_set:
        return True
    for sfx in suffixes:
        if host.endswith(sfx):
            return True
    return False


def is_localhost_dev(host: str, port: int | None) -> bool:
    """Allow localhost dev-server ports."""
    if host not in ("localhost", "127.0.0.1"):
        return False
    if port is None:
        return False
    return port in (3000, 3001, 3002, 3003, 4040, 6006, 9229, 11434)


# ── What a request SENDS, which is the thing a read can actually leak ────────────────────────────
# Header names and option spellings whose presence means this request carries a credential outward.
_CRED_HEADER_RE = re.compile(
    r"""(?ix) (?:^|['"\s]) (?: authorization | cookie | proxy-authorization
        | x-api-key | x-auth-token | x-access-token | x-amz-security-token
        | x-goog-api-key | private-token | api-key ) \s*:""",
)
# Credential-bearing options, matched against PARSED ARGV — never against the raw command text.
#
# WHY NOT A RAW-TEXT SCAN (measured on the audit corpus, 2026-08-23). The first draft regex'd the
# whole command string. `curl -sL "https://web.dev/x" | grep -oE '(rubber|bounce)'` then convicted
# the curl of carrying credentials, because `-oE` matches a short cluster ending in E — and `-E` is
# curl's client-certificate flag. That is a flag belonging to a DIFFERENT PROGRAM on the far side of
# a pipe. 123 of 155 remaining asks were this one false positive, i.e. the guard was spending most
# of its prompts on grep. parse_curl()'s token walk stops at `|`, so reading the flags off the argv
# it already built is both precise and free.
#
# CASE-SENSITIVE on purpose, and this is the other subtlety. curl's short flags distinguish case and
# the pairs are opposites: -u is credentials but -e is a referer; -E is a client cert but -e is not.
# The first draft compiled with re.IGNORECASE, so `-e https://ref` read as `-E` and a harmless
# referer was convicted — caught by the -e positive control in tests/curl-gate-decide.bats.
_CRED_FLAG_TOKENS = frozenset(
    {
        "-u",
        "--user",
        "-U",
        "--proxy-user",
        "-b",
        "--cookie",
        "-E",
        "--cert",
        "--key",
        "--oauth2-bearer",
        "--aws-sigv4",
        "--netrc",
        "--netrc-file",
        "--netrc-optional",
        "--tlsuser",
        "--tlspassword",
        "--proxy-cert",
        "--proxy-key",
    }
)
_CRED_SHORT_CHARS = frozenset("uUbE")

# A URI scheme per RFC 3986 §3.1 — a letter then letters/digits/+/-/. then a colon.
_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*:")


def short_cluster_flags(body: str) -> str:
    """The flag characters in a short-option cluster, stopping at the first value-taking one.

    `-o/tmp/Errors.txt` is `-o` plus an ATTACHED value; naively scanning the whole token for a
    credential character would find the `E` in "Errors" and convict it. curl requires a value-taking
    short flag to be last in its cluster (everything after it is its value), so the flag section is
    exactly the leading run up to and including the first value-taking character.
    """
    out: list[str] = []
    for ch in body:
        if not ch.isalpha():
            break
        out.append(ch)
        if ch in _VALUE_FLAGS_SHORT:
            break
    return "".join(out)


# Query/userinfo parameter names that carry a secret. Matched on the URL only.
_CRED_QUERY_RE = re.compile(
    r"""(?ix) [?&#] \s* (?: token | api[_-]?key | apikey | access[_-]?token | id[_-]?token
        | refresh[_-]?token | secret | client[_-]?secret | password | passwd | pwd
        | auth | authorization | session | sig | signature | credential | x-amz-signature ) \s* =""",
)


def outbound_credentials(parsed: dict) -> str | None:
    """Name the credential this request would SEND, or None if it sends nothing secret.

    THE POLICY PIVOT (2026-08-23). Until now the gate's read rule was "is this host on a list I
    recognise" — and that question is orthogonal to the harm a read can do. It asked about
    `www.w3.org` (382 distinct public hosts asked about, 1,810 asks, an unbounded research tail no
    allowlist can chase) while ALLOWING `api.github.com` carrying `Authorization: token ghp_…`,
    because the host was on the list. The list gated the wrong axis in both directions.

    A GET can hurt in exactly five ways, and four are already covered independently of the host,
    each by its own arm of decide() that runs BEFORE this one:
        SSRF / cloud metadata  → is_internal_host()      (deny, unconditional)
        remote code execution  → has_pipe_to_shell       (deny)
        TLS downgrade          → has_insecure            (deny)
        clobbering a secret    → SENSITIVE_PATHS on -o   (deny)
    The fifth is EXFILTRATION — carrying a secret outward to a host of the model's choosing — and
    that is what this function detects. So the read rule becomes: any public host is fine to read
    FROM, and the prompt is spent on the one case where the operator has a real decision to make,
    namely a request that would hand a credential to a host nobody has vetted.

    Deliberately over-broad on the SHAPE of a secret — every extra prompt is the incumbent behaviour
    and therefore safe, while a false negative hands out a credential. But strictly precise on WHOSE
    flags it reads: the census runs inside parse_curl()'s token walk, which stops at the first shell
    metacharacter, so `curl … | grep -oE …` can never be convicted of carrying a client certificate.
    Attached and detached spellings (-H"Authorization: x" vs -H "Authorization: x") are both captured
    there, so no raw-text scan is needed to see them.
    """
    for h in parsed.get("headers") or []:
        if _CRED_HEADER_RE.search(h):
            return "an Authorization/Cookie-class header"
    flags = parsed.get("cred_flags") or []
    if flags:
        return f"a credential-bearing curl option ({flags[0]})"
    for u in parsed.get("urls") or []:
        if _CRED_QUERY_RE.search(u):
            return "a secret-shaped query parameter"
        try:
            if "@" in (urlparse(u).netloc or ""):
                return "inline userinfo credentials in the URL"
        except ValueError:
            return "an unparseable URL authority"
    return None


def decide(parsed: dict) -> tuple[str, str]:
    """Return (decision, reason). decision in {allow, deny, ask}."""
    if "error" in parsed:
        return "deny", f"curl-gate: {parsed['error']}"

    # Pipe-to-shell first — but allow the canonical flyctl bootstrap
    if parsed["has_pipe_to_shell"]:
        for url in parsed["urls"]:
            if url.startswith("https://fly.io/install.sh"):
                return "allow", "Canonical flyctl bootstrap"
        return "deny", "Pipe to shell (RCE risk)"

    if parsed["has_insecure"]:
        return "deny", "--insecure disables TLS verification"

    if parsed["config_file"]:
        return "deny", "-K/--config indirect URL source not parseable"

    # Sensitive output / upload paths
    op = parsed.get("output_path") or ""
    df = parsed.get("data_file_arg") or ""
    for path_frag in SENSITIVE_PATHS:
        if path_frag in op or path_frag in df:
            return "deny", f"Sensitive path involved: {path_frag}"

    urls = parsed["urls"]
    if not urls:
        return "ask", "No URL parsed; review manually"

    # Multi-URL: must all pass
    decisions: list[tuple[str, str]] = []
    for raw_url in urls:
        u = urlparse(raw_url)
        if u.scheme == "file":
            return "deny", "file:// scheme blocked"
        if u.scheme not in ("http", "https"):
            return "ask", f"Non-HTTP scheme: {u.scheme}"
        host = (u.hostname or "").lower()

        if is_internal_host(host):
            return "deny", f"Internal/IMDS target: {host}"

        # `.port` is a PROPERTY that RAISES on a non-numeric authority — and ours frequently is one,
        # because the model writes `http://localhost:3000$CHUNK` and the shell expands the variable
        # later. Unguarded, that ValueError escaped decide() to main()'s catch-all and became a
        # fail-closed DENY reading "curl-gate: internal error", which is how 20 ordinary localhost
        # reads were blocked. The hostname parses fine in every one of these; only the port does not.
        try:
            port = u.port
        except ValueError:
            port = None
        if is_localhost_dev(host, port):
            decisions.append(("allow", f"Local dev server :{port}"))
            continue

        method = parsed["method"]

        if method in SAFE_METHODS:
            if host_matches(host, READ_HOSTS, READ_HOST_SUFFIXES):
                decisions.append(("allow", f"{method} to allowlisted host {host}"))
                continue
            # Open-read rule — see outbound_credentials() for why the host is no longer the axis.
            # The host has already survived is_internal_host() above, so it is public or loopback.
            if not parsed.get("has_data") and not parsed.get("has_file_upload"):
                leak = outbound_credentials(parsed)
                if leak is None:
                    decisions.append(
                        ("allow", f"{method} {host} — read-only, sends no credential")
                    )
                    continue
                return (
                    "ask",
                    f"{method} to unvetted host {host} — request carries {leak}",
                )
            return "ask", f"{method} to unknown host {host} — and it sends a body"

        # Writes (POST/PUT/PATCH/DELETE)
        if method == "POST":
            if host_matches(host, POST_HOSTS, POST_HOST_SUFFIXES):
                decisions.append(("allow", f"POST to allowlisted host {host}"))
                continue
            return "ask", f"POST to unknown host {host} — confirm intent"

        # PUT/PATCH/DELETE — never auto-allow
        return "ask", f"{method} {host} — confirm intent"

    # All URLs passed individually
    if all(d[0] == "allow" for d in decisions):
        return "allow", "; ".join(d[1] for d in decisions)

    return "ask", "Mixed decision; review manually"


# Tokens at which one command's argv ends: shell statement separators plus redirections.
# Redirections are included because nothing after `> file` is reliably part of curl's argv, and the
# failure direction of stopping early is an extra prompt, never a missed rule.
_STATEMENT_SEPS = frozenset(
    {";", "|", "||", "&&", "&", ">", ">>", "<", "<<", ">&", "&>", "<&"}
)


def curl_invocations(cmd: str) -> list[list[str]] | None:
    """Every curl invocation in a compound command, as separate argv lists.

    WHY EVERY ONE, NOT JUST THE FIRST (2026-08-23). decide() was only ever handed the first curl in
    a command, so `curl A | wc -l ⏎ curl B` was judged entirely on A. That gap was invisible while a
    second defect masked it: the incumbent shlex.split() raised on the quoting in such multi-line
    blocks, main() caught it and fail-closed to deny, and the deny looked like a rule rather than
    what it was — an unparsed command. Teaching the lexer to parse those blocks (see parse_curl)
    removed the accidental net, which is only safe if the thing the net was standing in for actually
    works. This is that thing.

    Segments are cut at separator TOKENS from the quote-aware lexer, never by regex over the raw
    text: main()'s incumbent `re.split(r"[;&|]+", cmd)` splits inside a quoted string, and
    `-A "Mozilla/5.0 (Macintosh; Intel Mac OS X …)"` contains a semicolon — so a regex split would
    cut the user-agent in half and strand the URL in a fragment that no longer starts with curl.
    A bare `curl` token also ends the previous segment, because shell newlines are whitespace to the
    lexer and would otherwise glue a second invocation onto the tail of the first.

    Returns None when the command cannot be tokenised at all, which the caller fails closed on.
    """
    try:
        lexer = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return None

    segments: list[list[str]] = []
    current: list[str] = []
    for t in tokens:
        is_curl = t == "curl" or t.endswith("/curl")
        if t in _STATEMENT_SEPS or (is_curl and current):
            segments.append(current)
            current = [t] if is_curl else []
            continue
        current.append(t)
    segments.append(current)
    return [s for s in segments if s and (s[0] == "curl" or s[0].endswith("/curl"))]


def decide_command(cmd: str) -> tuple[str, str, dict]:
    """Judge EVERY curl in the command; the strictest verdict wins (deny > ask > allow)."""
    invocations = curl_invocations(cmd)
    if invocations is None:
        return "deny", "curl-gate: shlex parse failed", {"host": None, "method": None}
    if not invocations:
        return "allow", "no curl invocation", {"host": None, "method": None}

    meta: dict = {"host": None, "method": None}
    verdicts: list[tuple[str, str]] = []
    for argv in invocations:
        parsed = parse_argv(argv, cmd)
        decision, reason = decide(parsed)
        if meta["host"] is None:
            first = (parsed.get("urls") or [None])[0]
            try:
                meta = {
                    "host": urlparse(first).hostname if first else None,
                    "method": parsed.get("method"),
                }
            except ValueError:
                meta = {"host": None, "method": parsed.get("method")}
        verdicts.append((decision, reason))

    for want in ("deny", "ask"):
        for decision, reason in verdicts:
            if decision == want:
                return decision, reason, meta
    return "allow", "; ".join(r for _, r in verdicts), meta


def main() -> None:
    if os.environ.get("CURL_GATE_DISABLED") == "1":
        sys.exit(0)

    try:
        raw = sys.stdin.read()
        if not raw.strip():
            sys.exit(0)
        payload = json.loads(raw)
    except (json.JSONDecodeError, OSError):
        sys.exit(0)  # malformed input — defer to downstream

    tool_name = payload.get("tool_name", "")
    cmd = (payload.get("tool_input", {}) or {}).get("command", "") or ""
    cwd = payload.get("cwd", "") or os.getcwd()
    session_id = payload.get("session_id", "unknown")
    tool_use_id = payload.get("tool_use_id", "unknown")

    if tool_name != "Bash":
        sys.exit(0)

    cmd_trim = cmd.strip()
    # Quick filter: only inspect commands containing curl (top-level or piped).
    # This runs BEFORE the scope test on purpose: the scope test may touch the
    # filesystem (linked-worktree resolution below), and this hook fires on every
    # single Bash call. Ordering it first keeps that cost on curl commands only.
    if "curl" not in cmd_trim:
        sys.exit(0)

    # Project-aware: only gate inside reso-management-app — INCLUDING its linked
    # worktrees, which live OUTSIDE PROJECT_ROOT (~/Development/.worktrees/), so a
    # prefix test alone left the gate inert exactly where the work happens.
    if not in_project_scope(cwd):
        sys.exit(0)

    # Only gate if curl appears as a command (not just a string literal)
    # Cheap heuristic: tokenize and see if "curl" is the first token of any
    # statement separated by ; & && || |
    import re

    statements = re.split(r"[;&|]+", cmd_trim)
    is_curl_invocation = any(
        s.strip().startswith("curl") or s.strip().startswith("xargs curl")
        for s in statements
    )
    if not is_curl_invocation:
        sys.exit(0)

    if cmd_trim.startswith("xargs curl"):
        emit(
            "deny",
            "xargs curl indirect URL source",
            {"host": None, "method": None},
            cmd,
            session_id,
            tool_use_id,
            cwd,
        )

    try:
        decision, reason, meta = decide_command(cmd_trim)
        emit(decision, reason, meta, cmd, session_id, tool_use_id, cwd)
    except Exception:
        # Fail-closed on any error
        emit(
            "deny",
            "curl-gate: internal error (fail-closed)",
            {"host": None, "method": None},
            cmd,
            session_id,
            tool_use_id,
            cwd,
        )


if __name__ == "__main__":
    main()
