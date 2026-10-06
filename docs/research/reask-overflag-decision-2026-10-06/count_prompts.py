# Counts only; never prints prompt text.
import json, os, re, glob, sys, collections
ROOT = "/Users/chrisren/Development/.worktrees/tm2-plan"
ENV = re.compile(r"^\s*(\[handoff |<teammate-message|<task-notification|<local-command-stdout>|<command-name>)|HANDOFF-ENGAGE-[A-Za-z0-9._-]+")
ALIAS = re.compile(r"(?<![a-z0-9_-])(truememory-2-0|truememory 2\.0|tm2)(?![a-z0-9_-])", re.I)
def under(c, root):
    return c == root or c.startswith(root + "/")
def text_of(m):
    c = (m or {}).get("content")
    if isinstance(c, str): return c
    if isinstance(c, list):
        if any(isinstance(p, dict) and p.get("type") == "tool_result" for p in c): return None
        return "\n".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
    return None
res = {}
for label, root in (("tm2-plan (registered root)", ROOT), ("tm2-plan-replan (NOT a registered root)", ROOT + "-replan")):
    days = collections.Counter(); gen = env = sessions = 0; sids = set(); files = 0
    for d in glob.glob(os.path.expanduser("~/.claude*/projects/-Users-chrisren-Development--worktrees-tm2-plan*")):
        for f in glob.glob(d + "/*.jsonl"):
            files += 1
            try:
                for ln in open(f, errors="replace"):
                    try: r = json.loads(ln)
                    except ValueError: continue
                    if r.get("type") != "user" or r.get("isMeta") or r.get("isSidechain"): continue
                    if not under(str(r.get("cwd") or ""), root): continue
                    t = text_of(r.get("message"))
                    if t is None or not t.strip(): continue
                    if ENV.search(t): env += 1; continue
                    gen += 1; sids.add(r.get("sessionId")); days[str(r.get("timestamp", ""))[:10]] += 1
            except OSError: pass
    res[label] = dict(transcript_files_scanned=files, genuine_prompts=gen, envelope_prompts=env, sessions=len(sids),
                      active_days=len(days), per_active_day_mean=round(gen / max(1, len(days)), 1),
                      max_day=max(days.values()) if days else 0, median_day=sorted(days.values())[len(days)//2] if days else 0,
                      first=min(days) if days else None, last=max(days) if days else None)
# history.jsonl: alias-named prompts from any cwd (the router's second key), and all prompts per day for scale
h_alias = collections.Counter(); h_all = collections.Counter(); h_root = collections.Counter()
for f in glob.glob(os.path.expanduser("~/.claude*/history.jsonl")):
    for ln in open(f, errors="replace"):
        try: r = json.loads(ln)
        except ValueError: continue
        t = r.get("display") or ""; ts = r.get("timestamp"); proj = str(r.get("project") or "")
        if not isinstance(ts, (int, float)): continue
        import datetime
        day = datetime.datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
        if t.startswith("/") and " " not in t.strip(): continue
        h_all[day] += 1
        if under(proj, ROOT): h_root[day] += 1
        elif ALIAS.search(t): h_alias[day] += 1
def summ(c):
    v = sorted(c.values()); return dict(total=sum(v), days=len(v), mean=round(sum(v)/max(1,len(v)),1), median=v[len(v)//2] if v else 0, max=v[-1] if v else 0, first=min(c) if c else None, last=max(c) if c else None)
res["history: all prompts, all cwds, all accounts"] = summ(h_all)
last30 = sorted(h_all)[-30:]
res["history: all prompts, last 30 active days"] = summ({d: h_all[d] for d in last30})
res["history: prompts with project under tm2-plan root"] = summ(h_root)
res["history: prompts from OTHER cwds naming tm2 / TrueMemory 2.0 / truememory-2-0 (router key 2)"] = summ(h_alias)
print(json.dumps(res, indent=1))
