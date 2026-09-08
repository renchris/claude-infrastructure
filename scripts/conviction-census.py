#!/usr/bin/env python3
"""
conviction-census.py — how often a close parks a DRIVABLE follow-on as the operator's.

WHY THIS FILE EXISTS. On 2026-09-08 a session found a machine-wide root cause
(fseventsd saturated by the fleet's watcher churn), filed it as
`needs-human: the fleet's headless spawn rate is the operator's policy call`,
and closed. The operator's reply: "is it net-positive? if so, why is this not
proactively done and instead idling for the user to ask what it is and
proceed?" The INVESTIGATION was drivable; only the eventual fix MIGHT have been
a policy call. CLAUDE.md already forbade this in three places and it happened
anyway, because the rule carried no number and no mechanical check. This is the
instrument that measures how often that shape occurs, so the fix that followed
(the conviction protocol — docs/research/conviction-close-2026-09-08.md) rests
on a count that can be re-run, not on one incident.

WHAT IT MEASURES
  Over every turn-final assistant message ("close") in the four per-account
  transcript roots (reusing scripts/measure-closes.py's corpus + parser):
    DEFER  — the close hands a decision or an item to the operator
             ("your call", "policy call", "say the word", "needs-human", the
             shipped D4 offer family, the shipped D1 handoff family)
    GATE   — the same close carries a marker of a GENUINE operator-only gate
             (credential/login/sudo · money · destructive/production data ·
             a permission prompt · physical/GUI · legal/third-party · an
             explicit human-approval contract)
    UNGATED DEFERRAL = DEFER and not GATE — the shape under study.
  Both lexicons are matched on the QUOTE-STRIPPED view, exactly as
  hooks/completion-assert.sh does (a close that quotes the phrase is citing
  the defect, not committing it).

  And over the three stores a close can name an item from:
    ~/.claude/autonomy/backlog.jsonl   `needs-human` rows · agent-filed `needs` rows
    ~/.claude/autonomy/decisions/      open class-B/C packets — options count,
                                       research receipt, stated conviction

  The lexicon is an INSTRUMENT, not an oracle: `--sample K` prints K random
  ungated hits for a human read, and the research doc records the measured
  precision of that read beside every count this prints.

USAGE
  python3 scripts/conviction-census.py                 # 30-day window
  python3 scripts/conviction-census.py --days 60 --sample 40 --json /tmp/hits.json
  python3 scripts/conviction-census.py --days 30 --seed 7 --sample 40

Every figure it prints is dated by its window and decays with the corpus.
"""

import argparse
import glob
import importlib.util
import json
import os
import random
import re
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_measure_closes():
    p = os.path.join(HERE, "measure-closes.py")
    spec = importlib.util.spec_from_file_location("measure_closes", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mc = _load_measure_closes()

# ─────────────────────────────────────────────────────────────────────────────
# LEXICONS
# ─────────────────────────────────────────────────────────────────────────────

# DEFER — the close hands a DECISION to the operator. The first group is this
# census's own (the incident's vocabulary and its synonyms); the other two are
# the shipped families from hooks/completion-assert.sh (D4 offers, D1 handoffs),
# so the count is comparable to what the Stop hook can already see.
DEFER_DECISION = (
    r"your call|policy call|value call|operator'?s call|your decision|"
    r"(is|are|it'?s) (for )?you(rs)? to (decide|settle|rule|choose|weigh)|"
    r"decision is yours|up to you|needs[- ]human|human[- ]only|"
    r"your (choice|preference)|which (would|do) you (prefer|want)|"
    r"would you (like|prefer|rather)|do you want (me|us) to|"
    r"if you (want|prefer|would like|decide)|let me know (which|whether|if you)|"
    r"(await|awaiting|wait(ing)? (for|on)) your (call|decision|ruling|verdict|go-ahead|word)|"
    r"parked (for|as|until) (you|your)|leav(e|ing) (this|that|it) (to|with) you"
)
RE_DEFER_DECISION = re.compile(DEFER_DECISION, re.I)
RE_DEFER_OFFER = re.compile(
    r"say the word|if you want (me|a|another)|want me to|shall i|"
    r"let me know if you.?d? ?(like|want)|happy to (pick|take|go|proceed|do|continue)|"
    r"i can pick (it|these|either) up|clean stopping point|otherwise (this|that) is a|"
    r"for a next (thread|session)|if you.?d? ?like me to|ready when you are",
    re.I,
)
RE_DEFER_HANDOFF = mc.RE_HANDOFF
RE_DEFER_NEG = mc.RE_NEG

# GATE — a marker that the item genuinely needs the operator. Deliberately
# NARROW spellings: "token" alone matches context-window prose and "screen"
# matches screenshots, and a broad gate lexicon would launder every deferral
# as legitimate. A gated hit may still hide an ungated one beside it; the
# sample read measures that direction too.
GATE = {
    "credential": (
        r"sudo|password|passcode|passphrase|credential|keychain|api[ -]?key|"
        r"access token|auth token|bearer|oauth|/login\b|logged[- ]out|log ?in to|"
        r"sign ?in|re-?auth|2fa|mfa|one-time code|verification code"
    ),
    "money": (
        r"\$[0-9]|[0-9]+ ?(usd|dollars)|\bmoney\b|billing|invoice|"
        r"spend(s|ing)? (real|money|\$)|budget approval|paid plan|charge(s|d)? (the|your) card"
    ),
    "destructive": (
        r"destructive|irreversible|cannot be undone|production (data|database|db|tenant)|"
        r"drop (the )?(table|column|database)|\bwipe\b|data loss|delete .{0,40}(production|tenant|customer)|"
        r"destructive migration|force[- ]push"
    ),
    "permission": (
        r"permission prompt|classifier|denied by|auto mode|allowlist|approve (the|this) (prompt|command)|"
        r"typed yes"
    ),
    "physical": (
        r"physical(ly)?|gui-only|\bgui\b|click (the|on|through)|plug|unplug|reboot|"
        r"restart (the|your) (mac|machine|laptop)|system settings|touch id|face id|"
        r"accessibility permission|screen recording permission"
    ),
    "legal": (
        r"legal|lawyer|perjury|declaration|contract|vendor|landlord|third[- ]party|"
        r"send (the|this|an) (email|text|message) to|reply to (the|their)"
    ),
    "human-contract": (
        r"propose-only|human-approved|never auto-apply|apply only on approval|"
        r"explicitly (asked|told) (me|us) (not|never) to"
    ),
}
RE_GATE = {k: re.compile(v, re.I) for k, v in GATE.items()}

RE_QUOTE_STRIP = re.compile(r"`[^`]*`|\"[^\"]*\"|“[^“”]*”")
RE_FENCE = re.compile(r"```.*?```", re.S)
RUNGS = "⛔📤🔧📦🚀👤✅"

# Stop-hook feedback that BLOCKED a close rides the user channel with one of
# these signatures. A close whose next record carries one was CAUGHT — the
# hook made the session continue — and never reached the operator.
RE_HOOK_CAUGHT = re.compile(
    r"completion-assert|dispatch-assert|Stop hook|stop hook|session-continue|"
    r"Your close names remaining work|a row is not a disposition|BLOCKED ON YOU",
    re.I,
)


def stripped_view(text):
    t = RE_FENCE.sub(" ", text)
    t2 = RE_QUOTE_STRIP.sub(" ", t)
    return t2 if t2.strip() else t


def rung_of(text):
    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        for ch in s[:4]:
            if ch in RUNGS:
                return ch
        return ""
    return ""


def defer_hits(view):
    hits = []
    for m in RE_DEFER_DECISION.finditer(view):
        hits.append(("decision", m.group(0)))
    for m in RE_DEFER_OFFER.finditer(view):
        hits.append(("offer", m.group(0)))
    neg = RE_DEFER_NEG.sub(" ", view)
    for m in RE_DEFER_HANDOFF.finditer(neg):
        hits.append(("handoff", m.group(0)))
    return hits


def gate_hits(view):
    out = []
    for k, rx in RE_GATE.items():
        m = rx.search(view)
        if m:
            out.append((k, m.group(0)))
    return out


def excerpt_lines(text, phrases, width=2):
    """The lines carrying a matched phrase, one excerpt per hit family."""
    lines = text.splitlines()
    out = []
    seen = set()
    low = [ln.lower() for ln in lines]
    for _, ph in phrases:
        p = ph.lower()
        for i, ln in enumerate(low):
            if p in ln and i not in seen:
                seen.add(i)
                out.append(lines[i].strip()[:400])
                break
        if len(out) >= width:
            break
    return out


# ─────────────────────────────────────────────────────────────────────────────
# CLOSE ITERATOR — measure-closes' parser, plus the record AFTER the close so a
# hook-caught close can be told from one that reached the operator.
# ─────────────────────────────────────────────────────────────────────────────


def iter_closes(path, root):
    recs = []
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") in ("assistant", "user") and r.get("isSidechain") is not True:
            recs.append(r)
    seq = []
    i = 0
    while i < len(recs):
        r = recs[i]
        if r.get("type") != "assistant":
            kind, payload = mc.classify_user(r)
            rawtxt, _ = mc.user_text(r)
            seq.append(("user", payload, kind, rawtxt or ""))
            i += 1
            continue
        mid = (r.get("message") or {}).get("id")
        j = i + 1
        if mid is not None:
            while (
                j < len(recs)
                and recs[j].get("type") == "assistant"
                and (recs[j].get("message") or {}).get("id") == mid
            ):
                j += 1
        texts, tool = [], False
        for k2 in range(i, j):
            t, hs = mc.assistant_text(recs[k2])
            if t:
                texts.append(t)
            tool = tool or hs
        seq.append(("assistant", "\n".join(texts), tool, recs[j - 1].get("timestamp")))
        i = j
    for k, (kind, text, aux, ts) in enumerate(seq):
        if kind != "assistant" or aux or not text.strip():
            continue
        nxt = seq[k + 1] if k + 1 < len(seq) else None
        if nxt is None:
            reply_kind, after = "eof", ""
        elif nxt[0] == "assistant" or nxt[2] == "tool":
            continue
        else:
            reply_kind, after = "machine", ""
            m = k + 1
            while m < len(seq):
                if seq[m][0] == "assistant" or seq[m][2] == "tool":
                    reply_kind = "continued"
                    break
                if seq[m][2] == "human":
                    reply_kind, after = "human", seq[m][1]
                    break
                m += 1
            else:
                reply_kind = "eof"
            # the raw text of the record right after the close, hook feedback included
            after_raw = seq[k + 1][3] if seq[k + 1][0] == "user" else ""
            after = after or after_raw
        yield {
            "file": path,
            "root": root,
            "ts": ts,
            "text": text,
            "reply_kind": reply_kind,
            "after": after,
        }


# ─────────────────────────────────────────────────────────────────────────────
# STORES
# ─────────────────────────────────────────────────────────────────────────────


def _fold_backlog(path):
    items = {}
    if not os.path.isfile(path):
        return items
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        it = items.setdefault(r.get("id"), {"events": []})
        it["events"].append(r)
        for k, v in r.items():
            if k != "event" and v not in ("", None):
                it[k] = v
        ev = r.get("event")
        if ev == "add":
            it["status"] = it.get("status") or "open"
        elif ev in ("block",):
            it["status"] = "blocked"
        elif ev in ("done",):
            it["status"] = "done"
        elif ev in ("reopen", "unblock"):
            it["status"] = "open"
        elif ev == "claim":
            it["status"] = "claimed"
    return items


def store_census(days, cutoff_iso):
    home = os.path.expanduser("~")
    bl = os.path.join(home, ".claude", "autonomy", "backlog.jsonl")
    dd = os.path.join(home, ".claude", "autonomy", "decisions")
    out = {"needs_human": [], "needs_agent_filed": [], "packets": []}
    items = _fold_backlog(bl)
    for iid, it in items.items():
        wnn = it.get("whyNotNow") or ""
        if wnn.lower().startswith("needs-human"):
            view = stripped_view(it.get("title", "") + " " + wnn)
            out["needs_human"].append(
                {
                    "id": iid,
                    "ts": it.get("ts"),
                    "status": it.get("status"),
                    "conviction": it.get("conviction"),
                    "receipt": it.get("receipt"),
                    "gate": [g for g, _ in gate_hits(view)],
                    "why": wnn[:200],
                }
            )
        # agent-filed operator steps: a `block --needs` carrying a session, in window
        for ev in it["events"]:
            if (
                ev.get("event") == "block"
                and ev.get("needs")
                and ev.get("session")
                and (ev.get("ts") or "") >= cutoff_iso
            ):
                view = stripped_view(it.get("title", "") + " " + ev.get("needs", ""))
                out["needs_agent_filed"].append(
                    {
                        "id": iid,
                        "ts": ev.get("ts"),
                        "session": ev.get("session"),
                        "conviction": ev.get("conviction") or it.get("conviction"),
                        "receipt": ev.get("receipt") or it.get("receipt"),
                        "gate": [g for g, _ in gate_hits(view)],
                        "needs": ev.get("needs", "")[:160],
                    }
                )
                break
    if os.path.isdir(dd):
        for f in glob.glob(os.path.join(dd, "*.json")):
            try:
                p = json.load(open(f))
            except Exception:
                continue
            st = p.get("status") or "open"
            if st != "open" or p.get("class") not in ("B", "C"):
                continue
            if (p.get("created") or "") < cutoff_iso:
                continue
            blob = " ".join(
                str(p.get(k) or "")
                for k in (
                    "what_plain",
                    "route_around_taken",
                    "recommendation",
                    "staged_artifact_path",
                )
            )
            out["packets"].append(
                {
                    "id": p.get("id"),
                    "class": p.get("class"),
                    "created": p.get("created"),
                    "options": len(p.get("options") or []),
                    "conviction": p.get("conviction"),
                    "receipt": p.get("receipt"),
                    "research_path": bool(re.search(r"docs/(research|plans)/", blob)),
                    "gate": [g for g, _ in gate_hits(stripped_view(blob))],
                    "what": (p.get("what_plain") or "")[:140],
                }
            )
    return out


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────


def pct(a, b):
    return "%5.1f%%" % (100.0 * a / b) if b else "   n/a"


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument(
        "--sample",
        type=int,
        default=0,
        help="print K random UNGATED hits for a human read",
    )
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--json", help="dump every DEFER hit to this path")
    ap.add_argument("--quiet-corpus", action="store_true")
    a = ap.parse_args()

    t0 = time.time()
    print("=" * 78)
    print(
        "CONVICTION-CENSUS — window %d days — run at %s"
        % (a.days, time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    )
    print("=" * 78)
    files, _ = mc.iter_transcripts(a.days, verbose=not a.quiet_corpus)
    cutoff_iso = time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - a.days * 86400)
    )

    closes = 0
    rung_closes = 0
    hits = []
    for path, root in files:
        for c in iter_closes(path, root):
            closes += 1
            rung = rung_of(c["text"])
            if rung:
                rung_closes += 1
            view = stripped_view(c["text"])
            d = defer_hits(view)
            if not d:
                continue
            g = gate_hits(view)
            caught = bool(
                c["reply_kind"] == "continued"
                and RE_HOOK_CAUGHT.search(c["after"] or "")
            )
            hits.append(
                {
                    "sid": os.path.basename(path)[:-6],
                    "project": os.path.basename(os.path.dirname(path)),
                    "root": root,
                    "ts": c["ts"],
                    "rung": rung,
                    "reply_kind": c["reply_kind"],
                    "hook_caught": caught,
                    "defer": d,
                    "gate": g,
                    "families": sorted({f for f, _ in d}),
                    "excerpt": excerpt_lines(c["text"], d),
                    "words": len(c["text"].split()),
                }
            )

    ungated = [h for h in hits if not h["gate"]]
    gated = [h for h in hits if h["gate"]]
    print()
    print("CLOSES")
    print("  turn-final assistant messages       %6d" % closes)
    print("  … carrying a ledger rung            %6d" % rung_closes)
    print()
    print("DEFERRALS — the close hands a decision or item to the operator")
    print(
        "  DEFER hits                          %6d   %s of all closes · %s of rung closes"
        % (
            len(hits),
            pct(len(hits), closes),
            pct(len([h for h in hits if h["rung"]]), rung_closes),
        )
    )
    print("  … GATED   (a genuine-gate marker)   %6d" % len(gated))
    print(
        "  … UNGATED (no gate marker at all)   %6d   %s of all closes · %s of rung closes  ← the shape under study"
        % (
            len(ungated),
            pct(len(ungated), closes),
            pct(len([h for h in ungated if h["rung"]]), rung_closes),
        )
    )
    fam = Counter()
    for h in ungated:
        for f in h["families"]:
            fam[f] += 1
    print("  ungated by family (a hit may carry several):", dict(fam))
    dec = [h for h in ungated if "decision" in h["families"]]
    print(
        '  ungated DECISION-family only        %6d   ("your call" / "policy call" / needs-human / up to you …)'
        % len(dec)
    )
    print()
    print("WHERE THE UNGATED DEFERRAL WENT")
    rk = Counter(h["reply_kind"] for h in ungated)
    for k in ("human", "eof", "continued", "machine"):
        print("  %-10s %6d   %s" % (k, rk.get(k, 0), pct(rk.get(k, 0), len(ungated))))
    caught = sum(1 for h in ungated if h["hook_caught"])
    print(
        "  caught by a Stop hook (continued + hook signature)  %6d   %s"
        % (caught, pct(caught, len(ungated)))
    )
    reached = sum(1 for h in ungated if h["reply_kind"] in ("human", "eof"))
    print(
        "  reached the operator (human reply or EOF)          %6d   %s"
        % (reached, pct(reached, len(ungated)))
    )
    print()
    print("UNGATED BY RUNG")
    rr = Counter(h["rung"] or "(none)" for h in ungated)
    for k, v in sorted(rr.items(), key=lambda kv: -kv[1]):
        print("  %-8s %6d" % (k, v))
    print()
    print("UNGATED BY WEEK (ISO, by close timestamp)")
    wk = Counter()
    for h in ungated:
        ts = h["ts"] or ""
        try:
            tm = time.strptime(ts[:10], "%Y-%m-%d")
            wk[time.strftime("%G-W%V", tm)] += 1
        except Exception:
            wk["?"] += 1
    for k in sorted(wk):
        print("  %-10s %6d" % (k, wk[k]))
    print()
    print("UNGATED BY PROJECT (top 12)")
    pj = Counter(h["project"] for h in ungated)
    for k, v in pj.most_common(12):
        print("  %-64s %6d" % (k[:64], v))

    # ── stores ──
    st = store_census(a.days, cutoff_iso)
    print()
    print("STORES — what the ask was filed AS")
    nh = st["needs_human"]
    print(
        "  backlog `needs-human` rows (all time)         %4d   with conviction %d · with receipt %d · gate-marked %d"
        % (
            len(nh),
            sum(1 for r in nh if r["conviction"] not in (None, "")),
            sum(1 for r in nh if r["receipt"]),
            sum(1 for r in nh if r["gate"]),
        )
    )
    for r in sorted(nh, key=lambda r: r["ts"] or ""):
        print(
            "     %s %s conv=%-4s rcpt=%-5s gate=%-24s %s"
            % (
                r["id"],
                (r["ts"] or "")[:10],
                r["conviction"] if r["conviction"] not in (None, "") else "-",
                "yes" if r["receipt"] else "-",
                ",".join(r["gate"]) or "-",
                r["why"][:110],
            )
        )
    na = st["needs_agent_filed"]
    print(
        "  agent-filed `needs` rows (block --needs with a session), window   %4d   gate-marked %d (%s) · with conviction %d"
        % (
            len(na),
            sum(1 for r in na if r["gate"]),
            pct(sum(1 for r in na if r["gate"]), len(na)),
            sum(1 for r in na if r["conviction"] not in (None, "")),
        )
    )
    pk = st["packets"]
    print(
        "  open class-B/C decision packets created in window   %4d   options==0: %d · research path in prose: %d · stated conviction: %d · receipt: %d · gate-marked: %d"
        % (
            len(pk),
            sum(1 for p in pk if p["options"] == 0),
            sum(1 for p in pk if p["research_path"]),
            sum(1 for p in pk if p["conviction"] not in (None, "")),
            sum(1 for p in pk if p["receipt"]),
            sum(1 for p in pk if p["gate"]),
        )
    )

    if a.sample:
        random.seed(a.seed)
        pool = ungated[:]
        random.shuffle(pool)
        print()
        print(
            "SAMPLE — %d random UNGATED hits for a human read (seed %d)"
            % (min(a.sample, len(pool)), a.seed)
        )
        for n, h in enumerate(pool[: a.sample], 1):
            print(
                "  [%2d] sid=%s  project=%s  ts=%s  rung=%s  reply=%s%s"
                % (
                    n,
                    h["sid"],
                    h["project"][:40],
                    (h["ts"] or "")[:19],
                    h["rung"] or "-",
                    h["reply_kind"],
                    " CAUGHT" if h["hook_caught"] else "",
                )
            )
            print(
                "       defer=%s"
                % ", ".join("%s:%r" % (f, p) for f, p in h["defer"][:3])
            )
            for e in h["excerpt"]:
                print("       > %s" % e[:300])

    if a.json:
        with open(a.json, "w") as fh:
            json.dump(
                {
                    "window_days": a.days,
                    "closes": closes,
                    "rung_closes": rung_closes,
                    "hits": hits,
                    "stores": st,
                },
                fh,
                indent=1,
                default=str,
            )
        print("\nhits written to %s" % a.json)
    print("\n(%0.1fs)" % (time.time() - t0))


if __name__ == "__main__":
    main()
