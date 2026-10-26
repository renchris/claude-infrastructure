"""Shared harness for the lane certification probes (wave W0, docs/research/midturn-account-move-2026-10-25/).

Every probe drives THROWAWAY Claude Code sessions this process starts itself, each in a config dir made
fresh with mkdtemp (never deleted and recreated: a removal prompt in an unattended session waits forever).
A "pointer lane" is the variable CLAUDE_SECURESTORAGE_CONFIG_DIR set to an account's REAL config dir,
spelled exactly as that account's own sessions resolve it, so the client reads that account's own keychain
item, refresh lock and compare-and-swap save. Nothing here writes a token anywhere:

- keychain items are read for METADATA only (expiry, modification date, a sha256[:10] fingerprint), and the
  secret is dropped inside `kc_state` before it returns; no token is printed, logged or written to disk;
- every artifact a probe leaves (stdout, debug log, mod log) is scanned for the `sk-ant-` token prefix and
  overwritten with a marker if one ever appears (`scrub_tokens`), which fails the probe;
- no slash command is ever sent (a probe /model once rewrote the shared ~/.claude/settings.json).

Billing is read from the response header `anthropic-organization-id`, printed by the SDK's own debug log
(ANTHROPIC_LOG=debug, which redacts the authorization header) or by the observer proxy below.
"""

from __future__ import annotations

import hashlib
import http.client
import http.server
import json
import os
import re
import shutil
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
KEYCHAIN_ACCOUNT = "chrisren"
DEFAULT_BINARY = HOME / ".claude-293/node_modules/.bin/claude"
CERT_DIR = HOME / ".reso/lanes/cert"
PROBE_MODEL = os.environ.get("LANE_PROBE_MODEL", "claude-haiku-5-5")
TIMEOUT = "/opt/homebrew/bin/timeout"
TOKEN_RE = re.compile(rb"sk-ant-[A-Za-z0-9_-]{8,}")
ACCOUNTS_JSON = HOME / ".claude/accounts.json"
GUARD_EXPIRY_S = (
    6 * 60
)  # never re-point inside the old account's last 6 min (REPORT §4.2)
PRECOND_LIFE_S = 30 * 60  # P-L6: run only while both tokens have >= 30 min of life
ADOPTION_BOUND_S = 30.0  # per-session keychain read cache `cPt=30000` (REPORT §7)


def now() -> float:
    return time.time()


def log(msg: str) -> None:
    print(f"  · {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------- binary + accounts
def resolve_binary(arg: str | None) -> Path:
    p = Path(arg or os.environ.get("LANE_PROBE_BINARY") or DEFAULT_BINARY).expanduser()
    return p


def binary_version(binary: Path) -> str:
    out = subprocess.run(
        [str(binary), "--version"],
        capture_output=True,
        text=True,
        timeout=60,
        env=clean_env({}),
    ).stdout
    m = re.search(r"(\d+\.\d+\.\d+)", out)
    if not m:
        raise RuntimeError(f"cannot read a version from {binary}: {out[:80]!r}")
    return m.group(1)


def binary_sha256(binary: Path) -> str:
    h = hashlib.sha256()
    with open(binary.resolve(), "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def account_dirs() -> dict[str, Path]:
    d = json.loads(ACCOUNTS_JSON.read_text())
    return {
        a["acct"] if "acct" in a else _acct_name(a): Path(
            os.path.expanduser(a["config_dir"])
        )
        for a in d["accounts"]
    }


def _acct_name(a: dict) -> str:
    # accounts.json rows carry launcher + config_dir; the account name is the dir's role.
    base = os.path.basename(os.path.expanduser(a["config_dir"]))
    return {
        ".claude-next": "next",
        ".claude-secondary": "next2",
        ".claude-tertiary": "next3",
        ".claude-quaternary": "next4",
    }.get(base, base)


def identity_of(cfg: Path) -> dict:
    """accountUuid + organizationUuid recorded in a config dir's .claude.json (identity, never a token)."""
    try:
        oa = json.loads((cfg / ".claude.json").read_text()).get("oauthAccount") or {}
    except (OSError, ValueError):
        return {}
    return {"account": oa.get("accountUuid"), "org": oa.get("organizationUuid")}


# ---------------------------------------------------------------- keychain (metadata only)
def kc_service(cfg: Path | str) -> str:
    return (
        "Claude Code-credentials-" + hashlib.sha256(str(cfg).encode()).hexdigest()[:8]
    )


def kc_mdat(cfg: Path | str) -> str | None:
    """Attributes only (no -w): the item's modification date, or None when absent."""
    r = subprocess.run(
        [
            "security",
            "find-generic-password",
            "-s",
            kc_service(cfg),
            "-a",
            KEYCHAIN_ACCOUNT,
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if r.returncode != 0:
        return None
    m = re.search(r'"mdat"<timedate>=\S+\s+"(\d{14})Z', r.stdout + r.stderr)
    return m.group(1) if m else "present"


def fp(s: str | None) -> str | None:
    return hashlib.sha256(s.encode()).hexdigest()[:10] if s else None


def kc_state(cfg: Path | str) -> dict:
    """Expiry + fingerprints of a config dir's credential item. The secret never leaves this function."""
    r = subprocess.run(
        [
            "security",
            "find-generic-password",
            "-s",
            kc_service(cfg),
            "-a",
            KEYCHAIN_ACCOUNT,
            "-w",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if r.returncode != 0:
        return {"present": False, "rc": r.returncode}
    try:
        o = json.loads(r.stdout).get("claudeAiOauth") or {}
        out = {
            "present": True,
            "access_fp": fp(o.get("accessToken")),
            "refresh_fp": fp(o.get("refreshToken")),
            "expires_at": (o.get("expiresAt") or 0) / 1000.0,
        }
    except ValueError:
        out = {"present": True, "unparseable": True}
    del r
    out["life_s"] = (
        round(out.get("expires_at", 0) - now(), 1) if "expires_at" in out else None
    )
    out["mdat"] = kc_mdat(cfg)
    return out


def guard_allows_repoint(old_cfg: Path, old_state: dict) -> tuple[bool, str]:
    """The pointer-lane expiry guard (REPORT §4.2): never re-point while the old account's token is inside
    its last 6 min, or while its `.oauth_refresh.lock` is held — a refresh in flight inside the same process
    could otherwise save the rotated grant into the new account's item."""
    if (old_cfg / ".oauth_refresh.lock").exists():
        return False, "old account's .oauth_refresh.lock is held"
    life = old_state.get("life_s")
    if life is None or life < GUARD_EXPIRY_S:
        return False, f"old account's token has {life} s left (< {GUARD_EXPIRY_S})"
    return True, f"ok (old token {int(life)} s left, no refresh lock)"


# ---------------------------------------------------------------- throwaway sessions
def clean_env(extra: dict[str, str]) -> dict[str, str]:
    env = {
        k: os.environ[k]
        for k in ("HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SHELL")
        if k in os.environ
    }
    env.update(
        {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "dumb",
            "DISABLE_AUTOUPDATER": "1",
            "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "1",
            "DISABLE_TELEMETRY": "1",
        }
    )
    env.update(extra)
    return env


def scratch(tag: str) -> Path:
    d = Path(tempfile.mkdtemp(prefix=f"lane-{tag}-", dir="/tmp"))
    os.chmod(d, 0o700)
    return d


def fresh_cfg(base: Path, name: str = "cfg") -> Path:
    c = base / name
    c.mkdir(mode=0o700)
    return c


def write_mod(
    base: Path,
    route: Path,
    modlog: Path,
    name: str = "lanectl",
    on_start_lane: str | None = None,
    body: str | None = None,
) -> Path:
    """A throwaway hooks-module plugin. `turn.step` (before every model request, main or subagent) reads the
    route file and re-points the lane variable; `session.measure` records the rate-limit windows; an optional
    `session.start` sets a lane at load/reload (the retrofit, P10/P-R1)."""
    mod = base / f"mod-{name}"
    (mod / ".claude-plugin").mkdir(parents=True, exist_ok=True)
    (mod / "hooks").mkdir(exist_ok=True)
    modlog.mkdir(exist_ok=True)
    (mod / ".claude-plugin/plugin.json").write_text(
        json.dumps(
            {
                "name": name,
                "version": "0.0.1",
                "description": "lane cert probe (throwaway)",
            }
        )
    )
    (mod / "hooks/hooks.json").write_text(json.dumps({"modules": ["./lane.ts"]}))
    write_mod_module(mod, route, modlog, on_start_lane, body)
    return mod


def write_mod_module(
    mod: Path,
    route: Path,
    modlog: Path,
    on_start_lane: str | None = None,
    body: str | None = None,
) -> None:
    start = ""
    if on_start_lane is not None:
        start = f"""
  on('session.start', async ($: any, e: any, next: any) => {{
    await $.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', {json.dumps(on_start_lane)})
    await put($, 'start', {{ lane: {json.dumps(on_start_lane)} }})
    return next(e)
  }})"""
    src = f"""// generated by tests/probes/lane/lib.py — throwaway, lives only under /tmp
const ROUTE = {json.dumps(str(route))}
const LOG = {json.dumps(str(modlog))}
let n = 0
const put = async ($: any, kind: string, rec: any) => {{
  n += 1
  await $.fs.write(`${{LOG}}/${{kind}}-${{String(n).padStart(4, '0')}}-${{Date.now()}}.json`,
    JSON.stringify({{ kind, n, t: Date.now(), ...rec }}))
}}
export const register = (on: any) => {{
  on('turn.step', async function* ($: any, e: any, next: any) {{
    let lane = ''
    try {{ lane = String(await $.fs.read(ROUTE)).trim() }} catch (_) {{ lane = '' }}
    if (lane) await $.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', lane)
    const seen = await $.env.get('CLAUDE_SECURESTORAGE_CONFIG_DIR')
    await put($, 'step', {{ lane, seen: seen ?? null, agent: e.agentId ?? null }})
    return yield* next(e)
  }})
  on('session.measure', async ($: any, e: any, next: any) => {{
    await put($, 'measure', {{ rateLimits: e.rateLimits, changed: e.changed }})
    return next(e)
  }}){start}{body or ""}
}}
"""
    (mod / "hooks/lane.ts").write_text(src)


def read_modlog(modlog: Path) -> list[dict]:
    # Sorted by the record's own clock, not its counter: a module reload restarts the counter at 1.
    recs = []
    for p in modlog.glob("*.json"):
        try:
            r = json.loads(p.read_text())
            r["host_mtime"] = p.stat().st_mtime
            recs.append(r)
        except (OSError, ValueError):
            pass
    return sorted(recs, key=lambda r: (r.get("t") or 0, r["host_mtime"]))


@dataclass
class Resp:
    t: float  # host arrival time of the response-start block
    status: int | None = None
    org: str | None = None
    util7d: float | None = None
    reset7d: int | None = None
    util5h: float | None = None


@dataclass
class Run:
    rc: int | None = None
    lines: list[tuple[float, str]] = field(default_factory=list)
    resps: list[Resp] = field(default_factory=list)
    result: dict | None = None
    session_id: str | None = None
    started: float = 0.0
    ended: float = 0.0


_RESP_START = re.compile(r"^\[log_[0-9a-f]+\] response start \{")


def parse_sdk_stream(
    lines: list[tuple[float, str]],
) -> tuple[list[Resp], dict | None, str | None]:
    """Fold ANTHROPIC_LOG=debug stdout (interleaved with stream-json result lines) into per-response rows."""
    resps: list[Resp] = []
    cur: Resp | None = None
    result = None
    sid = None
    for t, ln in lines:
        if _RESP_START.match(ln):
            cur = Resp(t=t)
            resps.append(cur)
            continue
        if ln.startswith("{") and '"type"' in ln:
            try:
                o = json.loads(ln)
                sid = o.get("session_id") or sid
                if o.get("type") == "result":
                    result = o
            except ValueError:
                pass
            continue
        if cur is None:
            continue
        if ln.startswith("[log_"):
            cur = None
            continue
        s = ln.strip()
        m = re.match(r"status: (\d{3}),", s)
        if m and cur.status is None:
            cur.status = int(m.group(1))
        for key, attr, conv in (
            ("anthropic-organization-id", "org", str),
            ("anthropic-ratelimit-unified-7d-utilization", "util7d", float),
            ("anthropic-ratelimit-unified-7d-reset", "reset7d", int),
            ("anthropic-ratelimit-unified-5h-utilization", "util5h", float),
        ):
            m = re.match(r'"?' + re.escape(key) + r'"?: "([^"]*)"', s)
            if m and getattr(cur, attr) is None:
                try:
                    setattr(cur, attr, conv(m.group(1)))
                except ValueError:
                    pass
    return resps, result, sid


def spawn_session(
    binary: Path,
    cfg: Path,
    prompt: str | None,
    *,
    lane: str | None,
    mod: Path | None,
    outdir: Path,
    tag: str,
    extra_env: dict | None = None,
    extra_args: list[str] | None = None,
    timeout_s: int = 420,
    on_line=None,
    stdin_messages=None,
) -> Run:
    """Run one throwaway `claude -p` session, timestamping every stdout line as it arrives. `on_line(t, line,
    run)` lets a probe act mid-turn (flip a route file). `stdin_messages` (a generator of user texts, pulled
    after each `result`) drives a multi-turn stream-json session."""
    env = {"CLAUDE_CONFIG_DIR": str(cfg), "ANTHROPIC_LOG": "debug"}
    if lane is not None:
        env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = lane
    env.update(extra_env or {})
    args = [
        TIMEOUT,
        str(timeout_s),
        str(binary),
        "-p",
        "--model",
        PROBE_MODEL,
        "--output-format",
        "stream-json",
        "--verbose",
        "--allowedTools",
        "Bash",
        "--debug-file",
        str(outdir / f"{tag}.debug.log"),
    ]
    if mod is not None:
        args += ["--plugin-dir", str(mod)]
    if stdin_messages is not None:
        args += ["--input-format", "stream-json"]
    args += extra_args or []
    if prompt is not None and stdin_messages is None:
        args.append(prompt)
    run = Run(started=now())
    proc = subprocess.Popen(
        args,
        cwd=str(outdir),
        env=clean_env(env),
        stdout=subprocess.PIPE,
        stderr=open(outdir / f"{tag}.stderr", "wb"),
        stdin=subprocess.PIPE if stdin_messages is not None else subprocess.DEVNULL,
    )

    def send(text: str) -> None:
        msg = {
            "type": "user",
            "message": {"role": "user", "content": [{"type": "text", "text": text}]},
        }
        proc.stdin.write((json.dumps(msg) + "\n").encode())
        proc.stdin.flush()

    if stdin_messages is not None:
        send(next(stdin_messages))
    with open(outdir / f"{tag}.stdout", "w") as raw:
        for b in proc.stdout:
            t = now()
            ln = b.decode("utf-8", "replace").rstrip("\n")
            raw.write(f"{t:.3f}\t{ln}\n")
            run.lines.append((t, ln))
            if on_line is not None:
                on_line(t, ln, run)
            if stdin_messages is not None and _result_line(ln) is not None:
                try:
                    send(next(stdin_messages))
                except StopIteration:
                    proc.stdin.close()
    run.rc = proc.wait()
    run.ended = now()
    run.resps, run.result, run.session_id = parse_sdk_stream(run.lines)
    return run


def _result_line(ln: str) -> dict | None:
    """A stream-json `result` record (key order varies by release, so parse rather than prefix-match)."""
    if not ln.startswith("{") or '"type":"result"' not in ln:
        return None
    try:
        o = json.loads(ln)
    except ValueError:
        return None
    return o if o.get("type") == "result" else None


def results_of(run: Run) -> list[dict]:
    return [o for o in (_result_line(ln) for _, ln in run.lines) if o is not None]


def transcript_check(cfg: Path, session_id: str | None) -> dict:
    """Linear transcript: every record has <= 1 child, one root, every tool_use answered by a tool_result."""
    files = sorted(cfg.glob("projects/*/*.jsonl"))
    if session_id:
        files = [f for f in files if f.stem == session_id] or files
    if not files:
        return {"ok": False, "why": "no transcript"}
    recs = []
    for f in files:
        for ln in f.read_text().splitlines():
            try:
                recs.append(json.loads(ln))
            except ValueError:
                pass
    msgs = [r for r in recs if r.get("uuid") and not r.get("isSidechain")]
    kids: dict[str, int] = {}
    roots = 0
    for r in msgs:
        p = r.get("parentUuid")
        if p:
            kids[p] = kids.get(p, 0) + 1
        else:
            roots += 1
    uses, answers = set(), set()
    for r in recs:
        c = (r.get("message") or {}).get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    uses.add(b.get("id"))
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    answers.add(b.get("tool_use_id"))
    branch = max(kids.values() or [0])
    interrupted = sum(
        1
        for ln in "\n".join(f.read_text() for f in files).splitlines()
        if "[Request interrupted" in ln
    )
    ok = branch <= 1 and roots <= 1 and uses <= answers and interrupted == 0
    return {
        "ok": ok,
        "records": len(msgs),
        "roots": roots,
        "max_children": branch,
        "tool_use": len(uses),
        "unanswered": len(uses - answers),
        "interrupted": interrupted,
        "files": len(files),
    }


def scrub_tokens(paths: list[Path]) -> list[str]:
    """Fail-safe: any artifact carrying a token-shaped string is overwritten with a marker (never left)."""
    hits = []
    for p in paths:
        for f in [p] if p.is_file() else [x for x in p.rglob("*") if x.is_file()]:
            try:
                data = f.read_bytes()
            except OSError:
                continue
            if TOKEN_RE.search(data):
                hits.append(str(f))
                f.write_bytes(
                    b"[scrubbed by lane probe: token-shaped content removed]\n"
                )
    return hits


def credential_files(dirs: list[Path]) -> dict[str, bool]:
    return {str(d): (d / ".credentials.json").exists() for d in dirs}


# ---------------------------------------------------------------- observer proxy (P-L4 only)
class ObserverProxy:
    """Stdlib HTTP→HTTPS pass-through to api.anthropic.com that records, per /v1/messages request, the
    request's `metadata.user_id` account uuid and the response's status and organization id. It never
    records or alters the authorization header: it forwards it as received."""

    def __init__(self):
        self.rows: list[dict] = []
        ctx = ssl.create_default_context(cafile="/etc/ssl/cert.pem")
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _fwd(self):
                n = int(self.headers.get("content-length") or 0)
                body = self.rfile.read(n) if n else b""
                row = {
                    "t": now(),
                    "path": self.path.split("?")[0],
                    "method": self.command,
                }
                if self.path.startswith("/v1/messages") and body:
                    try:
                        uid = json.loads(body).get("metadata", {}).get("user_id")
                        row["account_uuid"] = (
                            (
                                json.loads(uid) if uid and uid.startswith("{") else {}
                            ).get("account_uuid")
                            if uid
                            else None
                        )
                        if row.get("account_uuid") is None and uid:
                            m = re.search(r"account_([0-9a-f-]{36})", uid)
                            row["account_uuid"] = m.group(1) if m else None
                    except (ValueError, AttributeError):
                        row["account_uuid"] = "unparseable"
                hdrs = {
                    k: v
                    for k, v in self.headers.items()
                    if k.lower()
                    not in ("host", "content-length", "connection", "accept-encoding")
                }
                c = http.client.HTTPSConnection(
                    "api.anthropic.com", 443, context=ctx, timeout=300
                )
                c.request(self.command, self.path, body=body or None, headers=hdrs)
                r = c.getresponse()
                row["status"] = r.status
                row["org"] = r.getheader("anthropic-organization-id")
                outer.rows.append(row)
                self.send_response(r.status)
                for k, v in r.getheaders():
                    if k.lower() not in (
                        "transfer-encoding",
                        "connection",
                        "content-length",
                    ):
                        self.send_header(k, v)
                self.send_header("transfer-encoding", "chunked")
                self.send_header("connection", "close")
                self.end_headers()
                while True:
                    chunk = r.read1(65536) if hasattr(r, "read1") else r.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
                c.close()

            do_GET = do_POST = do_HEAD = do_PUT = do_DELETE = _fwd

        class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
            daemon_threads = True

        self.srv = S(("127.0.0.1", 0), H)
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def close(self):
        self.srv.shutdown()


# ---------------------------------------------------------------- verdicts
def verdict(probe: str, status: str, summary: str, **evidence) -> dict:
    return {
        "probe": probe,
        "verdict": status,
        "summary": summary,
        "at": now(),
        "evidence": evidence,
    }


def pick_pair(pref: str | None = None) -> tuple[str, Path, str, Path]:
    """Two accounts for a move: LANE_PROBE_ACCOUNTS='A B' or next2 → next (both carry no .credentials.json,
    so adoption takes the keychain path the fleet runs; tertiary's stale file is avoided)."""
    dirs = account_dirs()
    a, b = (pref or os.environ.get("LANE_PROBE_ACCOUNTS") or "next2 next").split()
    return a, dirs[a], b, dirs[b]


def copy_transcript(src_cfg: Path, dst_cfg: Path, session_id: str) -> Path | None:
    for f in src_cfg.glob(f"projects/*/{session_id}.jsonl"):
        d = dst_cfg / "projects" / f.parent.name
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, d / f.name)
        return d / f.name
    return None


# ---------------------------------------------------------------- reference readings + the interactive TUI
def account_ref(binary: Path, cfgdir: Path, ctx: dict) -> dict:
    """One cheap throwaway call pointed at an account's store: its org and 7d window as the server reports
    them. Lets a TUI probe identify the billed account from session.measure (certified by P-S1)."""
    key = f"ref:{cfgdir}"
    if key not in ctx:
        base = scratch("ref")
        r = spawn_session(
            binary,
            fresh_cfg(base),
            "Reply with exactly: OK",
            lane=str(cfgdir),
            mod=None,
            outdir=base,
            tag="ref",
            timeout_s=240,
        )
        scrub_tokens([base])
        ok = [x for x in r.resps if x.status == 200]
        ctx[key] = (
            {"org": ok[-1].org, "util7d": ok[-1].util7d, "reset7d": ok[-1].reset7d}
            if ok
            else {}
        )
    return ctx[key]


def measure_account(m: dict, refs: dict[str, dict]) -> str | None:
    """Which account a session.measure record reports, matched on the 7d reset instant and utilization."""
    w = next(
        (x for x in m.get("rateLimits") or [] if x.get("kind") == "seven_day"), None
    )
    if not w or not w.get("resetsAt"):
        return None
    from datetime import datetime

    reset = int(
        datetime.fromisoformat(w["resetsAt"].replace("Z", "+00:00")).timestamp()
    )
    hits = [
        n
        for n, ref in refs.items()
        if ref.get("reset7d") == reset
        and abs((ref.get("util7d") or 0) * 100 - w.get("percentUsed", -99)) <= 2
    ]
    return hits[0] if len(hits) == 1 else None


def seed_tui_config(cfg: Path, cwd: Path) -> None:
    """Skip first-run screens in a throwaway TUI: onboarding done and the cwd trusted (no keys, no tokens)."""
    proj = {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}
    (cfg / ".claude.json").write_text(
        json.dumps(
            {
                "hasCompletedOnboarding": True,
                "lastOnboardingVersion": "2.1.293",
                "theme": "dark",
                "projects": {str(cwd): proj, os.path.realpath(cwd): proj},
            }
        )
    )


class Tui:
    """A throwaway interactive session on a PRIVATE tmux server (its own -L socket, no user config), so no
    keystroke can reach any live pane. Only plain prompts are typed; never a slash command."""

    TMUX = "/opt/homebrew/bin/tmux"

    def __init__(
        self, base: Path, binary: Path, cfg: Path, lane: str | None, mod: Path | None
    ):
        self.sock = f"laneprobe-{base.name}"
        self.base = base
        env = {"CLAUDE_CONFIG_DIR": str(cfg), "TERM": "xterm-256color"}
        if lane is not None:
            env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = lane
        e = clean_env(env)
        argv = (
            ["env", "-i"]
            + [f"{k}={v}" for k, v in e.items()]
            + [
                str(binary),
                "--model",
                PROBE_MODEL,
                "--allowedTools",
                "Bash",
                "--debug-file",
                str(base / "tui.debug.log"),
            ]
        )
        if mod is not None:
            argv += ["--plugin-dir", str(mod)]
        cmd = " ".join(_shq(x) for x in argv)
        self._tmux(
            "new-session",
            "-d",
            "-s",
            "p",
            "-x",
            "180",
            "-y",
            "50",
            "-c",
            str(base),
            cmd,
        )

    def _tmux(self, *a: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [self.TMUX, "-L", self.sock, "-f", "/dev/null", *a],
            capture_output=True,
            text=True,
            timeout=30,
        )

    def screen(self) -> str:
        return self._tmux("capture-pane", "-p", "-t", "p").stdout

    def wait_screen(self, needle: str, timeout_s: float) -> bool:
        end = now() + timeout_s
        while now() < end:
            if needle in self.screen():
                return True
            time.sleep(1.0)
        return False

    def type_prompt(self, text: str) -> None:
        self._tmux("send-keys", "-t", "p", "-l", text)
        time.sleep(0.5)
        self._tmux("send-keys", "-t", "p", "Enter")

    def close(self) -> None:
        (self.base / "tui.screen.txt").write_text(self.screen())
        self._tmux("kill-server")


def _shq(s: str) -> str:
    return "'" + s.replace("'", "'\\''") + "'"


def wait_for(pred, timeout_s: float, every: float = 1.0) -> bool:
    end = now() + timeout_s
    while now() < end:
        if pred():
            return True
        time.sleep(every)
    return False
