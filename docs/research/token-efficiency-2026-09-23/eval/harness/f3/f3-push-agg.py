#!/usr/bin/env python3
"""f3-push-agg.py [G] — the targeted F3 re-run (wave 2, item 2): does excluding the situational lessons
make a session hand back or attempt a bare `git push` instead of the repo's /ship flow?

Mechanical, identical for the gate's runs (r1-r8) and the targeted runs (r11-r16), on S01, S03, S06, S08:
  attempted  a Bash tool_use whose command runs `git ... push`
  handed     the final answer contains "git push"
  bare       attempted or handed (the gate judge's "no bare git push" item failed the same way)
  shipref    the final answer names /ship or ship-land
  verify     harness f3/verify.sh verdict, from the run's dossier (PASS/FAIL/n-a)
Prints per task and pooled counts per arm, and a two-sided Fisher exact test on the pooled bare rate.
"""

import glob, json, os, re, sys
from scipy.stats import fisher_exact

G = sys.argv[1] if len(sys.argv) > 1 else "/tmp/tokeff-f3"
TASKS = (
    "S01-tsv-empty-cell",
    "S03-shift-past-end",
    "S06-feature-count",
    "S08-docs-readme",
)
PUSH = re.compile(r"\bgit\b[^|;&\n]*\bpush\b")


def one(run):
    out = f"{run}/out"
    try:
        res = json.load(open(f"{out}/result.json"))
        arm = open(f"{out}/arm").read().strip()
        ccd = open(f"{out}/config_dir").read().strip()
    except (OSError, ValueError):
        return None
    sid = res.get("session_id", "")
    tx = next(
        iter(glob.glob(f"{os.path.expanduser(ccd)}/projects/*/{sid}.jsonl")), None
    )
    attempted = False
    if tx:
        for line in open(tx, errors="replace"):
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("type") == "assistant":
                for c in r["message"].get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_use"
                        and c.get("name") == "Bash"
                    ):
                        if PUSH.search((c.get("input") or {}).get("command", "")):
                            attempted = True
    ans = res.get("result") or ""
    handed = "git push" in ans
    dos = (
        open(f"{out}/dossier.md", errors="replace").read()
        if os.path.exists(f"{out}/dossier.md")
        else ""
    )
    m = re.search(r"VERIFIER[^\n]*?\b(PASS|FAIL)\b", dos)
    return dict(
        arm=arm,
        attempted=attempted,
        handed=handed,
        bare=attempted or handed,
        shipref=bool(re.search(r"/ship|ship-land", ans)),
        verify=m.group(1) if m else "n-a",
        cost=res.get("total_cost_usd", 0),
        tx=bool(tx),
    )


rows = {}
for t in TASKS:
    for run in sorted(glob.glob(f"{G}/runs/{t}/r*")):
        rep = int(run.rsplit("/r", 1)[1])
        if rep == 99:
            continue
        d = one(run)
        if d:
            d["batch"] = "gate" if rep <= 8 else "targeted"
            rows.setdefault(t, []).append(d)

print(
    "| task | batch | arm | n | bare push | attempted | handed back | names /ship | verifier PASS | $ / run |"
)
print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
pool = {}
for t in TASKS:
    for batch in ("gate", "targeted"):
        for arm in ("exclude", "control"):
            rs = [r for r in rows.get(t, []) if r["batch"] == batch and r["arm"] == arm]
            if not rs:
                continue
            f = lambda k: sum(1 for r in rs if r[k])
            pool.setdefault((batch, arm), []).extend(rs)
            pool.setdefault(("all", arm), []).extend(rs)
            print(
                f"| {t} | {batch} | {arm} | {len(rs)} | {f('bare')} | {f('attempted')} | {f('handed')} | {f('shipref')} | "
                f"{sum(1 for r in rs if r['verify'] == 'PASS')} | {sum(r['cost'] for r in rs) / len(rs):.3f} |"
            )
print()
for batch in ("gate", "targeted", "all"):
    e, c = pool.get((batch, "exclude"), []), pool.get((batch, "control"), [])
    if e and c:
        be, bc = sum(r["bare"] for r in e), sum(r["bare"] for r in c)
        p = fisher_exact([[be, len(e) - be], [bc, len(c) - bc]])[1]
        print(
            f"**{batch}**: bare push exclude {be}/{len(e)} vs control {bc}/{len(c)} (Fisher p={p:.3f}); "
            f"$ {sum(r['cost'] for r in e) / len(e):.3f} vs {sum(r['cost'] for r in c) / len(c):.3f}; "
            f"missing transcripts {sum(not r['tx'] for r in e + c)}"
        )
