import pickle, collections, re, bisect, statistics as S, sys

# skeptic analysis over /tmp/usage-audit/skeptic-lp/<acct>.pkl (own scan.py output)
# weights: WL = the other agent's list proxy; WM = repo meter price list (tm2 REPORT M1: 1.95 pp/Mtok output,
# 0.25 pp/Mtok cache_creation, cache_read excluded ~0; input folded in at the cc rate, it is <0.01% of tokens)
WL = lambda r: r[1] + 1.25 * r[2] + 0.1 * r[4] + 5 * r[5]
WM = lambda r: 1.95 * r[5] + 0.25 * (r[2] + r[1])
CTX = lambda r: r[1] + r[2] + r[4]
WATCH = re.compile(r"watcher|inbox|peer.mail|ping|wake|cc-await", re.I)
LAND = re.compile(r"\b(land|commit|ship|ci)\b", re.I)


def tcls(k, s):
    if k != "tn":
        return k
    if s.startswith("📬"):
        return "tn:mail-hook(📬)"
    if "Goal check-in" in s:
        return "tn:goal-checkin"
    if s.startswith("Background command") or s.startswith("Background shell"):
        m = re.search(r'Background command "(.*?)"', s)
        dsc = m.group(1) if m else s
        ex = re.search(r"exit code (\d+)", s)
        ex = ex.group(1) if ex else "?"
        if WATCH.search(dsc):
            return "tn:watcher(exit %s)" % ("0" if ex == "0" else "nonzero")
        if LAND.search(dsc):
            return "tn:land/commit/ci"
        return "tn:bg-other"
    if s.startswith("Agent") or "agent" in s[:30].lower():
        return "tn:agent-done"
    if "orkflow" in s[:60]:
        return "tn:workflow-done"
    if s.startswith("Monitor"):
        return "tn:monitor"
    return "tn:other"


G = collections.defaultdict(
    collections.Counter
)  # by main-turn trigger class: main-thread only
T = collections.Counter()
turns = collections.defaultdict(list)  # class -> [(nreq, WL, WM, launched)]
subattr = collections.defaultdict(
    collections.Counter
)  # agent-style attribution of subagent weight
peer_gaps = []
age = collections.defaultdict(list)
caps = collections.Counter()
conc = collections.defaultdict(collections.Counter)
for a in sys.argv[1:]:
    D = pickle.load(open(f"/tmp/usage-audit/skeptic-lp/{a}.pkl", "rb"))
    R = D["reqs"]
    files = D["files"]
    TL = D["tl"]
    for r in R:
        T["n"] += 1
        T["WL"] += WL(r)
        T["WM"] += WM(r)
        T["WL_cr"] += 0.1 * r[4]
        T["n_" + r[6]] += 1
        T["WL_" + r[6]] += WL(r)
        T["WM_" + r[6]] += WM(r)
    bys = collections.defaultdict(list)
    for r in R:
        bys[r[7]].append(r)
    span = {s: (min(x[0] for x in L), max(x[0] for x in L)) for s, L in bys.items()}
    for s, L in bys.items():
        lng = span[s][1] - span[s][0] >= 8 * 3600
        for r in L:
            k = "long" if lng else "short"
            T["n_" + k] += 1
            T["WL_" + k] += WL(r)
            T["WM_" + k] += WM(r)
    # concurrency: distinct main sessions with a main request in the same 5-min slot
    slot = collections.defaultdict(set)
    for r in R:
        if r[6] == "main":
            slot[int(r[0] // 300)].add(r[7])
    for r in R:
        k = len(slot.get(int(r[0] // 300), ()))
        k = "0-1" if k <= 1 else "2-3" if k <= 3 else "4-7" if k <= 7 else "8+"
        conc[k]["n"] += 1
        conc[k]["WL"] += WL(r)
        conc[k]["WM"] += WM(r)
    # main-thread turns
    for s, L in bys.items():
        M = sorted((r for r in L if r[6] == "main"), key=lambda r: r[0])
        tl = sorted(TL.get(s, []))
        tts = [x[0] for x in tl]
        cur = None
        cur_rows = []

        def flush(cls, rows):
            if cls is None or not rows:
                return
            launched = any(
                t in ("Agent", "Task", "Workflow") for r in rows for t in r[10]
            )
            turns[cls].append(
                (
                    len(rows),
                    sum(WL(r) for r in rows),
                    sum(WM(r) for r in rows),
                    launched,
                    rows[0][0],
                )
            )

        lastidx = -2
        for r in M:
            i = bisect.bisect_right(tts, r[0]) - 1
            if i != lastidx:
                flush(cur, cur_rows)
                cur_rows = []
                cur = tcls(tl[i][1], tl[i][2]) if i >= 0 else "(before first trigger)"
                lastidx = i
            cur_rows.append(r)
            G[cur]["n"] += 1
            G[cur]["WL"] += WL(r)
            G[cur]["WM"] += WM(r)
            G[cur]["ctx"] += CTX(r)
            ag = (r[0] - span[s][0]) / 3600
            b = 0 if ag < 1 else 1 if ag < 8 else 2 if ag < 16 else 3 if ag < 48 else 4
            age[b].append(CTX(r))
            for c in (200, 250):
                caps[f"L{c}"] += 0.1 * max(0, CTX(r) - c * 1000)
        flush(cur, cur_rows)
        # peer / teammate inter-arrival per session
        pt = [x[0] for x in tl if x[1] in ("peer", "teammate")]
        peer_gaps += [b - a_ for a_, b in zip(pt, pt[1:])]
        # agent-style subagent attribution: trigger at subagent file's first request
        sf = collections.defaultdict(list)
        for r in L:
            if r[6] != "main":
                sf[r[8]].append(r)
        for fi, rows in sf.items():
            t0 = min(x[0] for x in rows)
            i = bisect.bisect_right(tts, t0) - 1
            cls = tcls(tl[i][1], tl[i][2]) if i >= 0 else "(parent absent/no trigger)"
            w = sum(WL(x) for x in rows)
            wm = sum(WM(x) for x in rows)
            subattr[cls]["WL"] += w
            subattr[cls]["WM"] += wm
            subattr[cls]["WL_" + files[fi][1]] += w
print(
    "== corpus (own scan, next2 sampled 15/16 sessions) requests %d: main %d, workflow-subagent %d, other subagent %d"
    % (T["n"], T["n_main"], T["n_wf"], T["n_sub"])
)
print(
    "list-proxy cache_read share of total weight: %.1f%%" % (100 * T["WL_cr"] / T["WL"])
)
print(
    "main-thread share of weight: list %.1f%% | meter %.1f%%"
    % (100 * T["WL_main"] / T["WL"], 100 * T["WM_main"] / T["WM"])
)
print(
    "8h+ sessions: %.1f%% of requests, %.1f%% list weight, %.1f%% meter weight"
    % (
        100 * T["n_long"] / T["n"],
        100 * T["WL_long"] / T["WL"],
        100 * T["WM_long"] / T["WM"],
    )
)
print(
    "main ctx by session age bucket (<1h,1-8h,8-16h,16-48h,48h+): "
    + ", ".join(
        "%.0fk(n=%d)" % (S.mean(age[b]) / 1e3, len(age[b])) for b in range(5) if age[b]
    )
)
print(
    "cap bound, list proxy: cache_read above 250k = %.1f%%, above 200k = %.1f%% of total list weight; meter weight of the same tokens = 0"
    % (100 * caps["L250"] / T["WL"], 100 * caps["L200"] / T["WL"])
)
print(
    "concurrency bucket -> req%% / list-weight%% / meter-weight%%: "
    + ", ".join(
        "%s: %.0f/%.0f/%.0f"
        % (
            k,
            100 * conc[k]["n"] / T["n"],
            100 * conc[k]["WL"] / T["WL"],
            100 * conc[k]["WM"] / T["WM"],
        )
        for k in ("0-1", "2-3", "4-7", "8+")
    )
)
print(
    "\n== main-thread requests by the turn trigger (main only; % of TOTAL weight incl. subagents)"
)
print(
    "class | main req | list w% | meter w% | mean ctx | turns | req/turn median | meter w per turn as % of mean main turn | turns launching Agent/Workflow"
)
allturns = [t for v in turns.values() for t in v]
mean_turn_wm = sum(t[2] for t in allturns) / len(allturns)
for k, v in sorted(G.items(), key=lambda x: -x[1]["WL"]):
    tv = turns.get(k, [])
    print(
        "%s | %d | %.2f | %.2f | %.0fk | %d | %s | %s | %s"
        % (
            k,
            v["n"],
            100 * v["WL"] / T["WL"],
            100 * v["WM"] / T["WM"],
            v["ctx"] / v["n"] / 1e3,
            len(tv),
            S.median([t[0] for t in tv]) if tv else "-",
            "%.0f%%" % (100 * S.mean([t[2] for t in tv]) / mean_turn_wm) if tv else "-",
            sum(1 for t in tv if t[3]),
        )
    )
print(
    "\n== agent-style attribution of subagent weight (trigger active at subagent first request) -> list w% of total, meter w%, share that is workflow-subagent (async)"
)
for k, v in sorted(subattr.items(), key=lambda x: -x[1]["WL"])[:12]:
    print(
        "%s | list %.2f%% | meter %.2f%% | wf share %.0f%%"
        % (
            k,
            100 * v["WL"] / T["WL"],
            100 * v["WM"] / T["WM"],
            100 * v["WL_wf"] / max(v["WL"], 1),
        )
    )
pg = sorted(peer_gaps)
if pg:
    print(
        "\n== peer+teammate trigger inter-arrival within a session: n=%d gaps; <60s %.0f%%, <5min %.0f%%, median %.0fs"
        % (
            len(pg),
            100 * sum(g < 60 for g in pg) / len(pg),
            100 * sum(g < 300 for g in pg) / len(pg),
            S.median(pg),
        )
    )
pickle.dump(
    {"turns": dict(turns), "G": {k: dict(v) for k, v in G.items()}, "T": dict(T)},
    open("/tmp/usage-audit/skeptic-lp/an.pkl", "wb"),
)
