#!/usr/bin/env python3
"""Score classifier variants on the agreed TUNING set (never the sealed set), the way heldout.evaluate
scores: completeness strata -> relay recall on relay-gold items; other stratum -> exact label."""
import json, os, sys, collections, concurrent.futures as cf
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
import router
H = os.path.expanduser("~/.claude/autonomy/research/router-heldout/")
rows = [json.loads(l) for l in open(H + "tuning.jsonl")]
gold = json.load(open(H + "tuning-gold.json"))
os.environ["CC_RESEARCH_CLASSIFIER_TIMEOUT"] = "30"
RELAYED = ("completeness", "pushback")
def run(arm_argv, brief, reps, workers=4, show=False):
    if arm_argv is not None:
        router.classifier_argv = lambda: arm_argv
    if brief is not None:
        router.CLASSIFIER_BRIEF = brief
    jobs = [(g, r) for g in gold for r in range(reps)]
    with cf.ThreadPoolExecutor(workers) as ex:
        res = list(ex.map(lambda j: (j[0], router.classify(rows[j[0]["idx"]]["prompt"], "")[0]), jobs))
    oth = [0, 0]; rec = [0, 0]; exact = [0, 0]; fb = 0; miss = collections.Counter()
    for g, got in res:
        fb += got is None
        exact[0] += got == g["gold"]; exact[1] += 1
        if g["stratum"] == "other":
            oth[1] += 1; oth[0] += got == g["gold"]
            if got != g["gold"]: miss[(g["idx"], g["gold"], got)] += 1
        elif g["gold"] in RELAYED:
            rec[1] += 1; rec[0] += got in RELAYED
            if got not in RELAYED: miss[(g["idx"], g["gold"], got)] += 1
    print(f"  other {oth[0]}/{oth[1]}={oth[0]/oth[1]:.2f}  relay-recall {rec[0]}/{rec[1]}={rec[0]/rec[1]:.2f}  exact {exact[0]}/{exact[1]}={exact[0]/exact[1]:.2f}  fallback {fb}")
    for (i, gl, got), n in sorted(miss.items()):
        print(f"    miss x{n} idx={i} {rows[i]['stratum']} gold={gl} got={got}" + (f" :: {rows[i]['prompt'][:160]!r}" if show else ""))
if __name__ == "__main__":
    import importlib
    base = ["/opt/homebrew/bin/claude", "-p", "--model", router.haiku_model(), "--setting-sources", "local",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
    nt = base + ["--disable-slash-commands", "--settings", '{"alwaysThinkingEnabled":false}']
    which = sys.argv[1]; reps = int(sys.argv[2])
    arm = {"A": base, "C": nt}[which]
    print(which); run(arm, None, reps, show="-v" in sys.argv)
