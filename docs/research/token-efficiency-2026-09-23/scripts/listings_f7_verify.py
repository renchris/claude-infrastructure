#!/usr/bin/env python3
"""Usage: python3 listings_f7_verify.py <worktree> <measure/listings_raw dir> <config-dir .claude.json>

Before/after check of the skill listing for F7, using the renderer logic in
docs/research/token-efficiency-2026-09-23/scripts/listings_simulate.py (Claude Code 2.1.280, fn JBt).
Repo-owned skills/commands are read from the worktree; skills that exist only in the live ~/.claude/skills
are read from there; bundled/anthropic entries keep their measured lengths from the latest real listing."""
import glob, json, os, re, sys, time
import yaml
W, RAW, CJ = sys.argv[1:4]
BUDGET, MAXD = 30000, 1536
HOME = os.path.expanduser("~")

def parse(p):
    t = open(p, encoding="utf-8").read()
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", t, re.S)
    body = t[m.end():] if m else t
    meta, strict = {}, True
    if m:
        try:
            meta = yaml.safe_load(m.group(1)) or {}
        except Exception:
            strict = False
            for line in m.group(1).splitlines():
                mm = re.match(r"^([A-Za-z_][\w-]*):\s?(.*)$", line)
                if mm:
                    v = mm.group(2).strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'": v = v[1:-1]
                    meta[mm.group(1)] = v
    first = next((l.strip() for l in body.splitlines() if l.strip()), "")
    d = meta.get("description"); d = "" if d is None else str(d)
    w = str(meta.get("when_to_use") or "")
    return dict(desc=d, wtu=w, derived=first[:100], strict=strict, has_desc=bool(d))

src = {}  # name -> (kind, path, own)
for p in sorted(glob.glob(HOME + "/.claude/skills/*/SKILL.md")):
    n = os.path.basename(os.path.dirname(p))
    wp = f"{W}/skills/{n}/SKILL.md"
    src[n] = ("skill", wp, True) if os.path.exists(wp) else ("skill", p, False)
for p in sorted(glob.glob(W + "/skills/*/SKILL.md")):
    n = os.path.basename(os.path.dirname(p)); src.setdefault(n, ("skill", p, True))
for p in sorted(glob.glob(W + "/commands/*.md")):
    n = os.path.basename(p)[:-3]
    if re.search(r"^disable-model-invocation:\s*true\s*$", open(p).read(), re.M): continue  # not listed
    src.setdefault(n, ("command", p, True))  # skill beats same-named command

lat = json.load(open(os.path.join(RAW, "latest_listing_entries.json")))
ents = [e["name"] for e in lat["entries"]]
for n in src:
    if n not in ents: ents.append(n)   # a new own skill/command joins the listing
BUNDLED = {"dataviz","update-config","keybindings-help","code-review","simplify","fewer-permission-prompts",
           "loop","schedule","claude-api","workflow-authoring","claude-in-chrome","run"}
fixed_nameonly = {e for e in ents if e.startswith("anthropic-skills:") or e in ("init","security-review")}
info, full = {}, {}
for e in ents:
    if e in src and e not in BUNDLED:
        kind, p, own = src[e]; x = parse(p); info[e] = dict(x, kind=kind, own=own, path=p)
        d = x["desc"] + (" - " + x["wtu"] if x["wtu"] else "")
        if not d: d = x["derived"]
        full[e] = len(e) + 4 + min(len(d), MAXD) if d else len(e) + 2
    else:
        full[e] = next(x["chars"] for x in lat["entries"] if x["name"] == e)

su = json.load(open(CJ)).get("skillUsage") or {}
now = time.time() * 1000
score = {k: v["usageCount"] * max(0.5 ** (((now - v["lastUsedAt"]) / 86400000) / 7), 0.1) for k, v in su.items()}
n = len(ents); nol = {e: len(e) + 2 for e in ents}
total_full = sum(full.values()) + n - 1
if total_full <= BUDGET:
    got, total, mode = {e for e in ents if e not in fixed_nameonly}, total_full, "fits"
else:
    keep = {e for e in ents if e in BUNDLED or e in fixed_nameonly}
    room = BUDGET - (sum(full[e] if e in BUNDLED else nol[e] for e in ents) + n - 1)
    got = set(BUNDLED & set(ents))
    for e in sorted([e for e in ents if e not in keep], key=lambda x: -score.get(x, 0)):
        inc = full[e] - nol[e]
        if inc <= room: got.add(e); room -= inc
    total = sum(full[e] if e in got else nol[e] for e in ents) + n - 1; mode = "priority"
own = [e for e in ents if e in info]
repo = [e for e in own if info[e]["own"]]
out = dict(entries=n, full_total=total_full, rendered_total=total, mode=mode, headroom=BUDGET - total_full,
    own_entries=len(own), own_described=sum(e in got for e in own), repo_entries=len(repo),
    repo_described=sum(e in got for e in repo),
    own_nameonly=sorted(e for e in own if e not in got),
    no_frontmatter_desc=sorted(e for e in own if not info[e]["has_desc"]),
    over250=sorted((e, len(info[e]["desc"])) for e in repo if len(info[e]["desc"]) > 250),
    strict_yaml_fail=sorted(e for e in own if not info[e]["strict"]),
    live_only=sorted((e, full[e]) for e in own if not info[e]["own"]),
    own_chars=sum(full[e] for e in own), repo_chars=sum(full[e] for e in repo))
print(json.dumps(out, indent=1))
