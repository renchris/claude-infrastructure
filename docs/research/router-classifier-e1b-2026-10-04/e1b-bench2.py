import json, os, shutil, statistics, subprocess, sys, tempfile, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
import router
N = int(sys.argv[1]); out = sys.argv[2]
rows = [json.loads(l) for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning.jsonl"))]
prompts = [r["prompt"] for r in rows if r["stratum"] == "other"][:N]
pre_argv = ["/opt/homebrew/bin/claude", "-p", "--model", router.haiku_model(), "--setting-sources", "local",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
pre_brief = ("You route one operator prompt in a research program that has a certificate.\n"
             "Answer with exactly ONE of these labels and nothing else:\n" + router.ROUTE_DEFINITIONS
             + "\n\nCERTIFICATE STATE LINES:\n{cert}\n\nPROMPT:\n{prompt}\n\nLABEL:")
post_argv = router.classifier_argv(); post_argv[0] = "/opt/homebrew/bin/claude"
arms = {"pre-E1b": (pre_argv, pre_brief), "as-built": (post_argv, router.CLASSIFIER_BRIEF)}
rec = []
for i, p in enumerate(prompts):
    for name, (argv, brief) in arms.items():
        d = tempfile.mkdtemp(prefix="cc-e1b-bench-")
        l0 = os.getloadavg()[0]; t0 = time.time()
        try:
            r = subprocess.run(argv, input=brief.format(cert="(none rendered)", prompt=p), capture_output=True,
                               text=True, timeout=60, cwd=d, env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"))
            lab = r.stdout.strip()[:40]
        except subprocess.TimeoutExpired:
            lab = "TIMEOUT"
        rec.append({"arm": name, "i": i, "wall": round(time.time() - t0, 2), "load": round(l0, 1), "label": lab})
        shutil.rmtree(d, ignore_errors=True)
json.dump(rec, open(out, "w"))
for name in arms:
    ws = sorted(x["wall"] for x in rec if x["arm"] == name); ls = [x["load"] for x in rec if x["arm"] == name]
    print(f"{name:9} n={len(ws)} median={statistics.median(ws):.2f} p90={ws[int(0.9*(len(ws)-1))]:.2f} max={ws[-1]:.2f} >9s={sum(w>9 for w in ws)} load {min(ls)}-{max(ls)} (median {statistics.median(ls)})")
