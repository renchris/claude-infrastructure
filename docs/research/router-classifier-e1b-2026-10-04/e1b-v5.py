import json, os, sys, collections, concurrent.futures as cf, subprocess, tempfile, shutil
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
import router
H = os.path.expanduser("~/.claude/autonomy/research/router-heldout/")
rows = [json.loads(l) for l in open(H + "tuning.jsonl")]
A = {int(json.loads(l)["id"][1:]): json.loads(l)["label"] for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning-labels-anthropic.jsonl"))}
O = {int(json.loads(l)["id"][1:]): json.loads(l)["label"] for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning-labels-openai.jsonl"))}
R = ("completeness", "pushback")
argv = router.classifier_argv(); argv[0] = "/opt/homebrew/bin/claude"
NOTE = {
 "N1": "\n- When you are unsure whether a prompt asks about completeness (or doubts the answer), answer completeness\n  (or pushback): missing one of those questions costs far more than labeling a borderline prompt as one.",
 "N2": "\n- A prompt asking for a summary or recap of what was achieved, what is left, or what is needed from the\n  operator to finish is completeness. When you are unsure between completeness or pushback and a later label,\n  answer the earlier one: missing a completeness question costs far more than a borderline false one.",
}[sys.argv[1]]
brief = router.CLASSIFIER_BRIEF.replace(router.CLASSIFIER_NOTES, router.CLASSIFIER_NOTES + NOTE)
assert brief != router.CLASSIFIER_BRIEF
reps = int(sys.argv[2])
def one(j):
    k, r = j; d = tempfile.mkdtemp()
    try:
        p = subprocess.run(argv, input=brief.format(cert="(none rendered)", prompt=rows[k]["prompt"]), capture_output=True,
                           text=True, timeout=40, cwd=d, env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"))
        w = p.stdout.split(); lab = w[0] if len(w) == 1 and w[0] in router.ROUTES else "FALLBACK"
    except subprocess.TimeoutExpired:
        lab = "TIMEOUT"
    shutil.rmtree(d, ignore_errors=True); return k, lab
with cf.ThreadPoolExecutor(4) as ex:
    res = list(ex.map(one, [(k, r) for k in range(96) for r in range(reps)]))
oth = [0, 0]; rec = [0, 0]; bord = [0, 0]; fb = 0; miss = collections.Counter()
for k, lab in res:
    fb += lab in ("FALLBACK", "TIMEOUT"); s = rows[k]["stratum"]
    if A[k] == O[k]:
        if s == "other":
            oth[1] += 1; oth[0] += lab == A[k]
            if lab != A[k]: miss[(k, s, A[k], lab)] += 1
        elif A[k] in R:
            rec[1] += 1; rec[0] += lab in R
            if lab not in R: miss[(k, s, A[k], lab)] += 1
    elif A[k] in R or O[k] in R:
        bord[1] += 1; bord[0] += lab in R
print(f"{sys.argv[1]} other {oth[0]}/{oth[1]}={oth[0]/oth[1]:.2f} recall {rec[0]}/{rec[1]}={rec[0]/rec[1]:.2f} borderline-relay {bord[0]}/{bord[1]} fallback {fb}")
for m, n in sorted(miss.items()): print("   miss", n, m, repr(rows[m[0]]["prompt"][:120]))
