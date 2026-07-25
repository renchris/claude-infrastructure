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
import shlex
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

PROJECT_ROOT = "/Users/chrisren/Development/reso-management-app"
AUDIT_LOG = Path.home() / ".reso" / "curl-audit.jsonl"

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


def parse_curl(cmd: str) -> dict:
    """Tokenize a curl command and extract URLs + method + flags."""
    try:
        tokens = shlex.split(cmd, posix=True)
    except ValueError:
        return {"error": "shlex parse failed"}

    if not tokens or tokens[0] != "curl":
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
        elif t.startswith("-"):
            # Other flags — skip
            i += 1
            continue
        else:
            # Positional — treat as URL if it looks like one or has a scheme
            if "://" in t or t.startswith(("http", "ftp", "file", "//")):
                urls.append(t)
            elif "." in t and "/" in t:
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

        port = u.port
        if is_localhost_dev(host, port):
            decisions.append(("allow", f"Local dev server :{port}"))
            continue

        method = parsed["method"]

        if method in SAFE_METHODS:
            if host_matches(host, READ_HOSTS, READ_HOST_SUFFIXES):
                decisions.append(("allow", f"{method} to allowlisted host {host}"))
                continue
            return "ask", f"{method} to unknown host {host}"

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

    # Project-aware: only gate inside reso-management-app
    if not cwd.startswith(PROJECT_ROOT):
        sys.exit(0)

    cmd_trim = cmd.strip()
    # Quick filter: only inspect commands containing curl (top-level or piped)
    if "curl" not in cmd_trim:
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
        parsed = parse_curl(cmd_trim)
        decision, reason = decide(parsed)
        host = parsed["urls"][0] if parsed.get("urls") else None
        if host:
            try:
                host = urlparse(host).hostname
            except Exception:
                host = None
        meta = {"host": host, "method": parsed.get("method")}
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
