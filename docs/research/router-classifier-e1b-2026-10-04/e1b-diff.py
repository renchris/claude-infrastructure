import json, os, sys, collections, concurrent.futures as cf, subprocess, tempfile, shutil
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
import router
H = os.path.expanduser("~/.claude/autonomy/research/router-heldout/")
rows = [json.loads(l) for l in open(H + "tuning.jsonl")]
A = {json.loads(l)["id"]: json.loads(l)["label"] for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning-labels-anthropic.jsonl"))}
O = {json.loads(l)["id"]: json.loads(l)["label"] for l in open(os.path.expanduser("~/.claude/autonomy/research/router-heldout/tuning-labels-openai.jsonl"))}
pre_argv = ["/opt/homebrew/bin/claude", "-p", "--model", router.haiku_model(), "--setting-sources", "local",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
pre_brief = ("You route one operator prompt in a research program that has a certificate.\n"
             "Answer with exactly ONE of these labels and nothing else:\n" + router.ROUTE_DEFINITIONS
             + "\n\nCERTIFICATE STATE LINES:\n{cert}\n\nPROMPT:\n{prompt}\n\nLABEL:")
built = router.classifier_argv(); built[0] = "/opt/homebrew/bin/claude"
i = built.index("--settings"); built_think = built[:i] + built[i+2:]
ARMS = {"pre": (pre_argv, pre_brief), "built": (built, router.CLASSIFIER_BRIEF), "built+think": (built_think, router.CLASSIFIER_BRIEF)}
if len(sys.argv) > 3:  # optional alternative brief module
    exec(open(sys.argv[3]).read())
arm = sys.argv[1]; reps = int(sys.argv[2]); argv, brief = ARMS[arm]
def one(j):
    k, r = j
    d = tempfile.mkdtemp()
    try:
        p = subprocess.run(argv, input=brief.format(cert="(none rendered)", prompt=rows[k]["prompt"]), capture_output=True,
                           text=True, timeout=40, cwd=d, env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"))
        lab = p.stdout.split()[0] if len(p.stdout.split()) == 1 and p.stdout.split()[0] in router.ROUTES else "FALLBACK"
    except subprocess.TimeoutExpired:
        lab = "TIMEOUT"
    shutil.rmtree(d, ignore_errors=True)
    return k, lab
with cf.ThreadPoolExecutor(4) as ex:
    res = list(ex.map(one, [(k, r) for k in range(len(rows)) for r in range(reps)]))
out = collections.defaultdict(list)
for k, lab in res: out[k].append(lab)
json.dump({"arm": arm, "labels": out}, open(f"diff-{arm}.json", "w"))
print(arm, "done")
