import json, collections, sys
from datetime import datetime
P = "/Users/chrisren/.claude/logs/account-utilization.jsonl"
c = collections.Counter(); rng = {}; wired = collections.Counter(); dec = collections.Counter()
keys = collections.Counter(); gaps = collections.defaultdict(list); last = {}
for line in open(P):
    try: r = json.loads(line)
    except Exception: c["bad"] += 1; continue
    a = r.get("acct"); c[(a, r.get("auth"), bool(r.get("stale")))] += 1
    for k in r: keys[k] += 1
    if r.get("auth") != "ok" or r.get("stale"): continue
    t = datetime.fromisoformat(r["ts"]).timestamp()
    lo, hi = rng.get(a, (9e18, 0)); rng[a] = (min(lo, t), max(hi, t))
    w = r.get("wire_7d_util")
    if isinstance(w, float):
        wired[a] += 1
        s = repr(w)
        dec[len(s.split(".")[1]) if "." in s else 0] += 1
    if a in last: gaps[a].append(t - last[a])
    last[a] = t
for k, v in sorted(c.items(), key=str): print(k, v)
for a, (lo, hi) in sorted(rng.items()):
    g = sorted(gaps[a]); n = len(g)
    print(a, datetime.utcfromtimestamp(lo).isoformat(), datetime.utcfromtimestamp(hi).isoformat(), "gap p50=%.0f p90=%.0f p99=%.0f" % (g[n//2], g[int(.9*n)], g[int(.99*n)]), "wired", wired[a])
print("wire decimals", dec)
print(keys.most_common())
