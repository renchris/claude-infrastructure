#!/bin/bash
# f2/setup.sh [sha] — build the FROZEN population every F2 brief reads, then compute ground truth.
#   $G/f2/tree    git archive of claude-infrastructure at <sha> (default: the gate's pinned sha), read-only
#   $G/f2/corpus  40 synthetic session transcripts (deterministic; no real transcript is copied)
#   $G/f2/review  a shell script with 3 planted bugs
#   $G/f2/truth.json  the verifier's answers, computed here by code, never by a model
# Nothing a slot reads can move while the gate runs (L3 lesson: the pilot's count grew mid-run).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/tmp/tokeff-gate}
SHA=${1:-d636fa0c769c6dca9ef0b54160a0731e320f2733}
REPO=$(git -C "$H" rev-parse --show-toplevel)
F="$G/f2"
[ -d "$F/tree" ] && chmod -R u+w "$F/tree"
rm -rf "${F:?}/tree" "$F/corpus" "$F/review"; mkdir -p "$F/tree" "$F/corpus" "$F/review" "$F/out"
git -C "$REPO" archive "$SHA" | tar -x -C "$F/tree"
echo "$SHA" > "$F/tree.sha"

python3 - "$F/corpus" <<'PY'
import json, random, sys
out = sys.argv[1]; rnd = random.Random(20260924)
for i in range(40):
    recs, fb = [], rnd.choice([0, 0, 0, 1, 2, 3])
    recs.append({"type": "user", "message": {"role": "user", "content": f"task {i}"}})
    for t in range(rnd.randint(2, 6)):
        recs.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": f"step {t}"}]}})
    for k in range(fb):
        recs.append({"type": "user", "isMeta": True, "message": {"role": "user", "content": f"Stop hook feedback:\n[hook {k}] finish the work"}})
    if i % 7 == 3:  # decoys: the phrase inside ordinary user text, not a meta record
        recs.append({"type": "user", "message": {"role": "user", "content": "why did the Stop hook feedback fire earlier?"}})
    open(f"{out}/session-{i:02d}.jsonl", "w").write("\n".join(json.dumps(r) for r in recs) + "\n")
PY

cat > "$F/review/rotate-logs.sh" <<'EOF'
#!/bin/bash
# rotate-logs.sh <dir> [keep] — gzip every *.log in <dir> older than 1 day, keep the newest <keep> archives.
dir=$1
keep=${2:-5}
cd $dir
for f in $(ls *.log); do
  if [ $(find "$f" -mtime +1) ]; then
    gzip "$f"
  fi
done
ls -t *.gz | tail -n +$keep | xargs rm -f
echo "rotated logs in $dir"
EOF

python3 - "$F" <<'PY'
import json, os, re, subprocess, sys
F = sys.argv[1]; T = f"{F}/tree"; truth = {}
# B02 CLAUDE_CONFIG_DIR fallback census: expansions ${CLAUDE_CONFIG_DIR:-...} on non-comment lines, bin/ hooks/ scripts/
tot = empty = 0; files = set()
for top in ("bin", "hooks", "scripts"):
    for dp, _, fs in os.walk(f"{T}/{top}"):
        for fn in fs:
            p = f"{dp}/{fn}"
            try: lines = open(p, errors="strict").read().splitlines()
            except Exception: continue
            for ln in lines:
                if ln.lstrip().startswith("#"): continue
                for m in re.finditer(r"\$\{CLAUDE_CONFIG_DIR:-([^}]*)\}", ln):
                    tot += 1; files.add(os.path.relpath(p, T))
                    if m.group(1) == "": empty += 1
truth["B02"] = {"expansions": tot, "empty_fallbacks": empty, "files": len(files)}
# B03 synthetic corpus
sess = with_fb = recs = 0
for fn in sorted(os.listdir(f"{F}/corpus")):
    sess += 1; n = 0
    for line in open(f"{F}/corpus/{fn}"):
        r = json.loads(line)
        c = r.get("message", {}).get("content")
        if r.get("isMeta") and isinstance(c, str) and c.startswith("Stop hook feedback"): n += 1
    recs += n; with_fb += n > 0
truth["B03"] = {"sessions": sess, "sessions_with_feedback": with_fb, "feedback_records": recs}
# B04 bats census
bats = [f for f in subprocess.run(["find", f"{T}/tests", "-name", "*.bats", "-type", "f"], capture_output=True, text=True).stdout.split()]
ntest = sum(len(re.findall(r"^\s*@test\b", open(b, errors="replace").read(), re.M)) for b in bats)
truth["B04"] = {"bats_files": len(bats), "test_cases": ntest}
# B05 project settings allow list
allow = json.load(open(f"{T}/.claude/settings.json"))["permissions"]["allow"]
truth["B05"] = {"allow_entries": len(allow), "cc_entries": sum(1 for a in allow if a.startswith("Bash(cc-"))}
# B06 planted bugs (by construction)
truth["B06"] = {"planted": ["unquoted $dir in cd (and cd without || exit: a failed cd rotates the CWD)",
                            "ls *.log word-splitting / parsing ls (filenames with spaces)",
                            "tail -n +$keep deletes one archive too many (keeps keep-1; needs +$((keep+1)))"]}
# B07 hooks line census
sizes = {}
for fn in os.listdir(f"{T}/hooks"):
    p = f"{T}/hooks/{fn}"
    if fn.endswith(".sh") and os.path.isfile(p):
        sizes[fn] = sum(1 for _ in open(p, errors="replace"))
top3 = sorted(sizes.items(), key=lambda kv: -kv[1])[:3]
truth["B07"] = {"sh_files": len(sizes), "total_lines": sum(sizes.values()), "top3": top3}
# B08 BASELINE ctx_type table
rows = []
txt = open(f"{T}/docs/research/token-efficiency-2026-09-23/BASELINE.md").read().splitlines()
for i, ln in enumerate(txt):
    if ln.startswith("| ctx_type"):
        for r in txt[i + 2:]:
            if not r.startswith("|"): break
            rows.append([c.strip() for c in r.strip("|").split("|")])
        break
truth["B08"] = {"rows": [[r[0], r[1], r[2]] for r in rows]}
# B09 migrations
mig = sorted(f for f in os.listdir(f"{T}/migrations") if re.match(r"^\d{4}-.*\.sh$", f))
truth["B09"] = {"count": len(mig), "highest": mig[-1][:4] if mig else None}
# B10 wrap-ledger kill switches: env vars compared against off/0 (verifier lists candidates; judge scores)
wl = open(f"{T}/scripts/wrap-ledger.sh", errors="replace").read()
ks = sorted(set(re.findall(r"\$\{?([A-Z][A-Z0-9_]+)(?::-[^}]*)?\}?\"?\s*(?:=|==|!=)\s*\"?(?:off|0)\b", wl)))
truth["B10"] = {"kill_switch_candidates": ks}
# B01 session-continue block sites (verifier context only; judged)
sc = open(f"{T}/hooks/session-continue.sh", errors="replace").read().splitlines()
truth["B01"] = {"block_emit_lines": [i + 1 for i, l in enumerate(sc) if re.search(r'"decision"\s*:\s*"block"|decision:\s*"?block|emit_block|block_json', l)]}
json.dump(truth, open(f"{F}/truth.json", "w"), indent=1)
print(json.dumps({k: (v if k not in ("B01", "B08", "B10") else "...") for k, v in truth.items()}, indent=0))
PY
chmod -R a-w "$F/tree" "$F/corpus" "$F/review"
