#!/usr/bin/env python3
import json, os, shutil, statistics, subprocess, sys, tempfile, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
import router
N = int(sys.argv[1]); out = sys.argv[2]
rows = [json.loads(l) for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning.jsonl"))]
prompts = [r["prompt"] for r in rows if r["stratum"] == "other"][:N]
base = ["/opt/homebrew/bin/claude", "-p", "--model", router.haiku_model(), "--setting-sources", "local",
        "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
SP = "You route one operator prompt to one label. Reply with the label only."
arms = {
  "A-current": base,
  "B-noslash": base + ["--disable-slash-commands"],
  "C-nothink": base + ["--disable-slash-commands", "--settings", '{"alwaysThinkingEnabled":false}'],
  "D-sysprompt": base + ["--disable-slash-commands", "--settings", '{"alwaysThinkingEnabled":false}', "--system-prompt", SP],
}
rec = []
for i, p in enumerate(prompts):
    for name, argv in arms.items():
        text = router.CLASSIFIER_BRIEF.format(cert="(none rendered)", prompt=p)
        d = tempfile.mkdtemp(prefix="cc-e1b-bench-")
        l0 = os.getloadavg()[0]; t0 = time.time()
        try:
            r = subprocess.run(argv, input=text, capture_output=True, text=True, timeout=60, cwd=d,
                               env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"))
            lab, rc = r.stdout.strip()[:40], r.returncode
        except subprocess.TimeoutExpired:
            lab, rc = "TIMEOUT", 124
        w = time.time() - t0
        shutil.rmtree(d, ignore_errors=True)
        rec.append({"arm": name, "i": i, "wall": round(w, 2), "load": round(l0, 1), "rc": rc, "label": lab})
        print(json.dumps(rec[-1]), flush=True)
json.dump(rec, open(out, "w"))
for name in arms:
    ws = sorted(x["wall"] for x in rec if x["arm"] == name); ls = [x["load"] for x in rec if x["arm"] == name]
    print(f"{name:12} n={len(ws)} median={statistics.median(ws):.2f} p90={ws[int(0.9*(len(ws)-1))]:.2f} max={ws[-1]:.2f} >9s={sum(w>9 for w in ws)} load {min(ls)}-{max(ls)} (median {statistics.median(ls)})")
