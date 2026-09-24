#!/usr/bin/env python3
"""Audit the SessionStart additionalContext components across the 14-day window (xdup=0, main).

Per component: count, size distribution, how often the component's normalized content is identical
to the previous injection in the same project (volatility), and component-specific staleness:
  dod-persist.sh        'THE CURRENT CONTRACT' line shown, whether it was persisted (preview only),
                        how many sessions were shown the same contract, and whether the session's own
                        first human prompt shares the contract's plan/topic token (relevance proxy).
  mailbox-drain.sh      #messages, age of each message at injection (header ts; forwarded original ts).
  config-mirror-assert  FORKED count and the share of FORKED names that are settings.json backups.
  activation-watch.sh   un-run / rotting counts.
Output: measure/hooks_sessionstart_audit.json + printed summary. MEASURED unless stated.
"""

import collections
import datetime as dt
import hashlib
import json
import re
import sqlite3
import statistics

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
x = sqlite3.connect(f"file:{BASE}/data/extract.sqlite?mode=ro", uri=True)
import importlib.util

spec = importlib.util.spec_from_file_location("hc", f"{BASE}/scripts/hooks_cost.py")
hc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hc)

rows = x.execute("""SELECT i.file, i.uid, i.ts, c.project_slug FROM item i JOIN ctx c ON c.file=i.file
    WHERE i.xdup=0 AND i.visible=1 AND i.subkind='hook_additional_context:SessionStart' AND c.ctx_type='main'
    ORDER BY i.ts""").fetchall()
first_prompt = {}
for (
    f,
    d,
) in x.execute("""SELECT file, MIN(item_seq) FROM item WHERE xdup=0 AND kind='user_prompt'
                         AND subkind IN ('plain','command','pasted') GROUP BY file"""):
    first_prompt[f] = d
want = collections.defaultdict(set)
for f, uid, ts, proj in rows:
    want[f].add(uid)
TS = re.compile(r"(20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d)([+-]\d{4}|Z)?")


def parse(s, tz):
    t = dt.datetime.fromisoformat(s)
    if tz and tz != "Z":
        t = t.replace(
            tzinfo=dt.timezone(
                dt.timedelta(hours=int(tz[:3]), minutes=int(tz[0] + tz[3:]))
            )
        )
    else:
        t = t.replace(tzinfo=dt.timezone.utc)
    return t


comp = collections.defaultdict(lambda: dict(n=0, sizes=[], same_as_prev=0, prev={}))
dod = []
mail_ages = []
mail_msgs = []
forked = []
act = []
for f, uids in want.items():
    proj = None
    fp_text = None
    items = []
    fp_seq = first_prompt.get(f)
    for line in open(f):
        if '"hook_additional_context"' in line or (
            fp_text is None and '"user"' in line
        ):
            r = json.loads(line)
            if r.get("type") == "attachment" and (r.get("uuid", "") + "#0") in uids:
                items.append((r.get("timestamp"), r["attachment"].get("content") or []))
            elif r.get("type") == "user" and fp_text is None and not r.get("isMeta"):
                c = (r.get("message") or {}).get("content")
                if isinstance(c, str) and not c.startswith("<"):
                    fp_text = c[:4000]
    proj = [p for ff, u, t, p in rows if ff == f][0]
    for ts, content in items:
        inj = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        for e in content:
            if not isinstance(e, str):
                continue
            sc, pers = hc.classify(
                hc.persisted_prefix(e) if hasattr(hc, "persisted_prefix") else e[:160]
            )
            if e.startswith("<persisted-output>"):
                body = e.split("):\n", 1)[-1]
                sc, pers = hc.classify("PERSISTED|?|" + body[:160])
            g = comp[sc]
            g["n"] += 1
            g["sizes"].append(len(e))
            norm = hashlib.md5(re.sub(r"\d+", "#", e).encode()).hexdigest()
            if g["prev"].get(proj) == norm:
                g["same_as_prev"] += 1
            g["prev"][proj] = norm
            if sc == "dod-persist.sh":
                m = re.search(
                    r"THE CURRENT CONTRACT[^\n]*\n+\s*Scope \(frozen\):\s*([^\n]{0,140})",
                    e,
                )
                contract = m.group(1).strip() if m else None
                orig = re.search(r"Output too large \(([^)]*)\)", e)
                key = None
                if contract:
                    km = re.match(r"([A-Z][A-Z0-9_]{4,})", contract)
                    key = km.group(1) if km else " ".join(contract.split()[:4]).lower()
                rel = None
                if key and fp_text:
                    rel = key.lower() in fp_text.lower()
                dod.append(
                    dict(
                        file=f,
                        ts=ts,
                        persisted=e.startswith("<persisted-output>"),
                        orig=orig.group(1) if orig else None,
                        contract=contract,
                        key=key,
                        relevant=rel,
                    )
                )
            elif sc == "mailbox-drain.sh" and "peer mail" in e[:40]:
                hdrs = re.findall(
                    r"│ (20\d\d-\d\d-\d\dT[\d:]+[+-]\d{4})( \[forwarded:\d+\] (20\d\d-\d\d-\d\dT[\d:]+[+-]\d{4}))?",
                    e,
                )
                mail_msgs.append(len(hdrs))
                for h0, _, h1 in hdrs:
                    t0 = parse(h0[:19], h0[19:])
                    t1 = parse(h1[:19], h1[19:]) if h1 else t0
                    mail_ages.append(
                        (
                            (inj - t0).total_seconds() / 3600,
                            (inj - t1).total_seconds() / 3600,
                            bool(h1),
                        )
                    )
            elif sc == "config-mirror-assert.sh":
                m = re.search(r"(\d+) FORKED", e)
                lst = re.split(r"shadow ~/\.claude in [^:]*:", e, maxsplit=1)[-1]
                names = re.findall(r"\S+", lst.split("\n")[0])
                bak = sum(
                    1 for n in names if n.startswith("settings.json.") or ".bak" in n
                )
                forked.append(
                    (
                        int(m.group(1)) if m else 0,
                        bak / max(len(names), 1),
                        len(e),
                        e.startswith("<persisted-output>"),
                    )
                )
            elif sc == "activation-watch.sh":
                m = re.search(r"(\d+) un-run \((\d+) rotting", e)
                if m:
                    act.append((int(m.group(1)), int(m.group(2))))


def q(v, ps=(0.5, 0.9)):
    v = sorted(v)
    return [round(v[int(len(v) * p)], 1) for p in ps] if v else None


out = dict(components={}, dod={}, mail={}, mirror={}, activation={})
for sc, g in sorted(comp.items(), key=lambda kv: -sum(kv[1]["sizes"])):
    out["components"][sc] = dict(
        n=g["n"],
        chars=sum(g["sizes"]),
        median=q(g["sizes"])[0],
        p90=q(g["sizes"])[1],
        identical_to_prev_in_project=round(g["same_as_prev"] / g["n"], 3),
    )
cc = collections.Counter(d["contract"][:80] if d["contract"] else None for d in dod)
out["dod"] = dict(
    n=len(dod),
    persisted=sum(d["persisted"] for d in dod),
    orig_sizes=collections.Counter(d["orig"] for d in dod if d["orig"]).most_common(8),
    distinct_contracts=len(cc),
    top_contracts=cc.most_common(8),
    relevance_checked=sum(1 for d in dod if d["relevant"] is not None),
    relevant=sum(1 for d in dod if d["relevant"]),
    not_relevant=sum(1 for d in dod if d["relevant"] is False),
)
out["mail"] = dict(
    injections=len(mail_msgs),
    msgs_median_p90=q(mail_msgs),
    messages=len(mail_ages),
    forwarded=sum(1 for a in mail_ages if a[2]),
    age_hours_since_delivery_median_p90=q([a[0] for a in mail_ages]),
    age_hours_since_origin_median_p90=q([a[1] for a in mail_ages]),
    origin_older_than_24h=sum(1 for a in mail_ages if a[1] > 24),
    origin_older_than_7d=sum(1 for a in mail_ages if a[1] > 168),
)
out["mirror"] = dict(
    n=len(forked),
    forked_median_p90=q([f[0] for f in forked]),
    bak_share_median=q([f[1] for f in forked])[0] if forked else None,
    chars_median_p90=q([f[2] for f in forked]),
    persisted=sum(f[3] for f in forked),
)
out["activation"] = dict(
    n=len(act),
    unrun_median=q([a[0] for a in act]),
    rotting_median=q([a[1] for a in act]),
)
json.dump(
    out,
    open(f"{BASE}/measure/hooks_sessionstart_audit.json", "w"),
    indent=1,
    default=str,
)
print(json.dumps(out, indent=1, default=str)[:6000])
