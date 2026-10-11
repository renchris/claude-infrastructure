#!/usr/bin/env python3
"""Peer-mail headline: one writer and one reader for the per-message metadata token.

An inbox line is `<ISO> [<from>] <body>`; forwards prepend `<ISO> [forwarded:<key>] ` chains and
the desk reroute inserts `[for:<key>] ` before the body. Since 2026-10-11 cc-notify also writes ONE
optional token right after `[<from>]`:

    <ISO> [<from>] [@v1;pane=225;sid=6ecdcaa0;title=<session title>;subj=<subject>;by=flag] <body>

Why this shape (docs/research/peer-mail-headline-2026-10-10/critic.md §5.1): it opens with `[@`,
which occurs 0 times in 31,140 historical lines, so no old reader mistakes it for a body tag; it sits
AFTER `[<from>]`, so every first-bracket sender reader and every `] <body>` grep keeps matching;
values are percent-encoded so they can never close the bracket, and the lifecycle class words the
whole-line substring classifiers key on are defanged so a session TITLE cannot reclassify a line.
The token rides inside the original line, which mailbox_migrate forwards byte for byte, so the
sender's identity survives any number of forwards.

The operator's headline:
    pane 225 · /limit-recover pane recovery gap · sent 22:59 · arrived 14 min late — <title>

Modes (stdin = inbox lines unless noted):
    meta  [--pane P] [--sid S] [--title T] [--subject X] [--by flag]   → the token, or nothing
    meta-from-row <registry-row.json> [--subject X] [--by flag]        → same; title from transcript
    drain [--own PANE]  → line 1: the ONE operator line; lines 2+: headlines (+ ack ask) for the model
    wake  [--own PANE]  → the idle-wake stderr text: headlines, then the bodies unchanged
    title               → one derived title per line (diagnostics and the bats fixture)
"""

import json
import os
import re
import sys
from datetime import datetime, timezone

# ── the token ────────────────────────────────────────────────────────────────────────────────────
# The needles of the whole-line substring classifiers (mailbox-drain noise filter and custody awk,
# cc-mail NOISE, cc-await-ping _line_class, cc-inbox-guard) plus the two routing tags. A value
# carrying one would let a session TITLE reclassify or reroute the line, so its first byte is
# percent-encoded; the renderer decodes it back for display.
CLASS_WORDS = (
    "HANDOFF-PING",
    "HANDOFF-HUSK-PANE",
    "SUPERVISOR PAGE",
    "REAPER SURFACE",
    "PERMISSION-PENDING",
    "WAKE-PATH",
    "desk-sweep",
    "forwarded:",
    "for:",
)
TITLE_CAP, SUBJ_CAP, TOKEN_CAP = 48, 80, 160


def _enc(v, cap):
    v = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", " ", str(v))).strip()[:cap]
    for a, b in (("%", "%25"), ("[", "%5B"), ("]", "%5D"), (";", "%3B"), ("=", "%3D")):
        v = v.replace(a, b)
    for w in CLASS_WORDS:
        v = re.sub(
            re.escape(w),
            lambda m: "%%%02X%s" % (ord(m.group(0)[0]), m.group(0)[1:]),
            v,
            flags=re.I,
        )
    return v


def _dec(v):
    return re.sub(r"%([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), v)


def make_token(pane="", sid="", title="", subj="", by=""):
    f = {
        "pane": re.sub(r"[^A-Za-z0-9._-]", "", str(pane or ""))[:32],
        "sid": re.sub(r"[^0-9A-Za-z]", "", str(sid or ""))[:8],
        "title": _enc(title, TITLE_CAP) if title else "",
        "subj": _enc(subj, SUBJ_CAP) if subj else "",
        "by": "flag" if by == "flag" else "",
    }
    if not (
        f["pane"] or f["subj"]
    ):  # nothing a reader could use: write no token at all
        return ""

    def render():
        return "[@v1;" + ";".join("%s=%s" % (k, v) for k, v in f.items() if v) + "]"

    for drop in ("title", "subj"):  # encoding can triple a value: shed the session
        if (
            len(render().encode()) <= TOKEN_CAP
        ):  # title first, the explicit subject last
            break
        f[drop] = ""
    return render()


def session_title(row):
    """custom-title > agent-name > ai-title, from the tail of the sender's own transcript."""
    sid, cwd, acct = (
        row.get("session_id") or "",
        row.get("cwd") or "",
        row.get("account") or "",
    )
    if not (sid and cwd):
        return ""
    home = os.path.expanduser("~")
    dirs = [os.path.join(home, "." + acct.lstrip("."))] if acct else []
    dirs.append(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude"))
    for d in dirs:
        try:
            with open(
                os.path.join(d, "projects", re.sub(r"[/.]", "-", cwd), sid + ".jsonl"),
                "rb",
            ) as fh:
                fh.seek(0, 2)
                fh.seek(max(0, fh.tell() - 262144))
                tail = fh.read().decode("utf-8", "replace")
        except OSError:
            continue
        best = {}
        for ln in tail.splitlines():
            if '-title"' not in ln and '"agent-name"' not in ln:
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            for k, fld in (
                ("custom-title", "customTitle"),
                ("agent-name", "agentName"),
                ("ai-title", "aiTitle"),
            ):
                if r.get("type") == k and r.get(fld):
                    best[k] = r[fld]
        return next(
            (
                best[k]
                for k in ("custom-title", "agent-name", "ai-title")
                if best.get(k)
            ),
            "",
        )
    return ""


def token_from_row(path, subj="", by=""):
    try:
        with open(path, encoding="utf-8") as fh:
            row = json.load(fh)
    except (OSError, ValueError):
        row = {}
    sid = row.get("session_id") or ""
    # Stale-row guard: a reused kitty window id, or a background fork that outlived its session, must
    # not sign as the pane's NEW tenant. When the harness tells us whose session this is, it must match.
    live = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not sid or (live and live != sid):
        return make_token(subj=subj, by=by)
    return make_token(row.get("paneUUID"), sid, session_title(row), subj, by)


# ── the line ─────────────────────────────────────────────────────────────────────────────────────
LINE = re.compile(r"^((?:\S+ \[forwarded:[^\]]*\] )*)(\S+) \[([^\]]*)\] ?(.*)$", re.S)
META = re.compile(r"^\[@v\d+;([^\]]*)\] ?")
FOR = re.compile(r"^\[for:[^\]]*\] ?")
NOISE = re.compile(r"HANDOFF-HUSK-PANE|REAPER SURFACE|\[desk-sweep\]")


def parse_ts(s):
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None


def parse(raw):
    """Origin sender, origin stamp, decoded token and bare body — the chain is stripped first."""
    rec = {"raw": raw, "ok": False, "from": "", "ts": None, "meta": {}, "body": raw}
    m = LINE.match(raw)
    if not m:
        return rec
    _chain, ts, frm, rest = m.groups()
    rec.update(ok=True, ts=parse_ts(ts), **{"from": frm})
    mm = META.match(rest)
    if mm:
        for kv in mm.group(1).split(";"):
            k, _, v = kv.partition("=")
            rec["meta"][k] = _dec(v)
        rest = rest[mm.end() :]
    rec["body"] = FOR.sub("", rest, count=1)
    return rec


# ── the title: T0 (critic.md §3/§5.3 — ties the tuned A4.1 out of sample at a fraction of the rules)
UUID = re.compile(r"\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
STRIP = (
    re.compile(r"^\[(?:for:[^\]]*|restart|lead|restore)\]\s*"),
    re.compile(r"^(?:⚠️|⚠|⛔|✗|✓|✔|❌|📬|🔴|🟢|\\)\s*"),
    re.compile(r"^HANDOFF-PING [A-Za-z0-9][A-Za-z0-9._/-]*:\s*"),
)


def cap(s, n=72):
    if len(s) <= n:
        return s
    cut = s[: n - 1]
    sp = cut.rfind(" ")
    if (
        s[n - 1] != " " and sp >= n // 2
    ):  # back up to a word boundary unless the cut is already on one
        cut = cut[:sp]
    return cut.rstrip(" ,;:—-(") + "…"


def title(body, subj=""):
    if subj:
        return cap(re.sub(r"\s+", " ", subj).strip())
    s = UUID.sub(r"\1", re.sub(r"\s+", " ", body)).strip()
    for _ in range(4):
        prev = s
        for rx in STRIP:
            s = rx.sub("", s)
        if s == prev:
            break
    return cap(s or re.sub(r"\s+", " ", body).strip())


# ── the headline ─────────────────────────────────────────────────────────────────────────────────
def _env_num(name, default):
    try:
        return max(0, float(os.environ.get(name, default)))
    except ValueError:
        return float(default)


def _when(dt, now):
    loc, nloc = dt.astimezone(), now.astimezone()
    hm = loc.strftime("%H:%M")
    return (
        hm
        if loc.date() == nloc.date()
        else "%s %d %s" % (loc.strftime("%b"), loc.day, hm)
    )


def lag_phrase(dt, now):
    mins = (now - dt).total_seconds() / 60.0
    if mins < _env_num("CC_MAIL_LATE_MIN", 10):
        return ""
    if mins < 90:
        return "arrived %d min late" % round(mins)
    if mins < 36 * 60:
        return "arrived %d h late" % round(mins / 60)
    return "arrived %d days late" % round(mins / 1440)


def who(rec, short=False):
    """`pane 225 · <session title>` when the line carries the token, else the origin [from]."""
    m = rec["meta"]
    if not m.get("pane"):
        return rec["from"] or "?"
    lab = "pane " + m["pane"]
    return lab if short or not m.get("title") else lab + " · " + cap(m["title"], 40)


def headline(rec, now):
    bits = [who(rec)] if rec["ok"] else []  # an unstamped line has no sender to name
    if rec["ts"]:
        bits.append("sent " + _when(rec["ts"], now))
        lag = lag_phrase(rec["ts"], now)
        if lag:
            bits.append(lag)
    t = title(rec["body"], rec["meta"].get("subj", ""))
    return (" · ".join(bits) + " — " + t) if bits else t


def ack_eligible(rec, own, now):
    """Session-written mail worth one chat line: another pane's token (not a --from daemon voice),
    or a HANDOFF-PING; never lifecycle noise, never a forward older than the stale-forward horizon."""
    if not rec["ok"] or NOISE.search(rec["raw"]):
        return False
    if (
        rec["ts"]
        and (now - rec["ts"]).total_seconds()
        > _env_num("CC_DRAIN_STALE_FORWARD_H", 24) * 3600
    ):
        return False
    m = rec["meta"]
    if m.get("pane"):
        return m["pane"] != own and m.get("by") != "flag"
    return "HANDOFF-PING" in rec["body"]


ACK = (
    "📣 ACKNOWLEDGE IN CHAT — session mail above. At the start of your next text, write ONE line "
    "covering every 📬 delivery since your last 📬 line: `📬 <sender label as shown>: <acting on it now "
    "| after <current step> | needs you: <what> | noted>` (several senders: join with '; ', at most 3, "
    "then '+N more'). At most one such line per text block; never acknowledge by cc-notify; "
    "lifecycle or status mail needs no line."
)


def drain(lines, own, now):
    recs = [parse(ln) for ln in lines]
    sig = [r for r in recs if not NOISE.search(r["raw"])]
    noise = len(recs) - len(sig)
    if not sig:
        return [
            "📬 peer mail ◀ %d lifecycle/fixture message(s), no peer traffic — cc-mail --all"
            % len(recs)
        ]
    names = []
    for r in sig:
        w = who(r, short=True) if r["ok"] else ""
        if w and w not in names:
            names.append(w)
    msg = "📬 peer mail ◀ %d peer message(s)" % len(sig)
    if len(sig) == 1:
        msg += " · " + headline(sig[0], now)
    else:
        # The first message's full headline, then the OTHER senders once each: naming the first sender
        # in a list and again in its headline would print it twice. Three senders at most in total.
        msg += " · first: " + headline(sig[0], now)
        first = who(sig[0], short=True) if sig[0]["ok"] else ""
        others = [w for w in names if w != first]
        if others:
            msg += " · also from " + ", ".join(others[:2]) + (", …" if len(others) > 2 else "")
    if noise:
        msg += " · %d fixture/lifecycle suppressed" % noise
    out = [msg + " — full text: cc-mail"]
    heads = [r for r in sig if r["ok"]]
    if heads:
        out.append("  headlines:")
        out += ["  📬 " + headline(r, now) for r in heads[:10]]
        if len(heads) > 10:
            out.append("  … +%d more" % (len(heads) - 10))
    if any(ack_eligible(r, own, now) for r in sig):
        out.append("  " + ACK)
    return out


def main(argv):
    mode, opts, pos, i = (argv[1] if len(argv) > 1 else ""), {}, [], 2
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            opts[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            pos.append(argv[i])
            i += 1
    now = parse_ts(os.environ.get("CC_MAIL_NOW", "")) or datetime.now(timezone.utc)
    own = opts.get("own", "")
    lines = []
    if mode in ("drain", "wake", "title"):
        lines = [ln for ln in sys.stdin.read().split("\n") if ln.strip()]
    if mode == "meta":
        tok = make_token(
            opts.get("pane"),
            opts.get("sid"),
            opts.get("title"),
            opts.get("subject"),
            opts.get("by"),
        )
        if tok:
            print(tok)
    elif mode == "meta-from-row" and pos:
        tok = token_from_row(pos[0], opts.get("subject", ""), opts.get("by", ""))
        if tok:
            print(tok)
    elif mode == "drain":
        print("\n".join(drain(lines, own, now)))
    elif mode == "wake":
        # Headlines lead, bodies follow unchanged. No acknowledgement ask here: the woken turn's own
        # drain re-delivers these lines 1-35 s later (13 of 14 measured) and asks once, from there.
        for r in [
            r for r in map(parse, lines) if r["ok"] and not NOISE.search(r["raw"])
        ][:10]:
            print("📬 " + headline(r, now))
        print("\n".join(lines))
    elif mode == "title":
        for r in map(parse, lines):
            print(title(r["body"], r["meta"].get("subj", "")))
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
