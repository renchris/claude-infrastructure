#!/bin/bash
# walk_v12.sh <scratch dir> — one dry walk of a method v1.2 research program, from intake to the
# Stage 9 built certificate and the implementation signature, through the kit's own verbs
# (RESEARCH_PROGRAM_BUILD waves E3c and E3d).
# Everything lives under <scratch dir>: a fixture HOME, registry and records; never the live
# pilot, never a vendor (the courier is a stub), never a real operator signature: the one
# signature the walk makes is the fixture signer's, on the fixture store, and says so in its chain.
#
#   Part A  a fresh program `walk`: intake init → rulings → escape cost → contract page (the v1.2
#           ceiling), then stage 3's yield stop (REPORT.md §12.1): a failing probe keeps the stage
#           open and `budget end` refuses; quiet probes stop it and `budget end` records why.
#   Part B  stages 2-8 cannot be walked by verbs without vendors and the operator's signature, so
#           the known-good fixture `demo` (build_good.py, stamped 1.2 by build_built.py, its
#           hand-written Stage 9 records deleted) stands in at a signed research certificate. Then
#           Stage 9 by verbs only (§11): built-freeze, a finding with a failing test, the fix and a
#           refreeze, a no-repro finding, mutation, as-built contact, 25 hourly soak samples by
#           `cc-research job soak`, two built rounds, the built gate, the certificate, the render.
#           Then the implementation signature (wave E3d): `built signoff` renders what is signed;
#           the gate refuses `built-signed`, `close` and a post-signoff wave while it is unsigned;
#           cc-signoff under a process named claude is refused (exit 3, nothing written); and the
#           fixture signer (fixture_signer.py: bin/cc-signoff itself with an operator's ancestry,
#           fixture store only) signs, which moves the registry to implementation-signed.
#
# Every command is echoed with `$ ` before its output. Exit 0 only if the walk ends closed, by way
# of build-certified and implementation-signed.
# Dates are relative to the clock at start (CC_NOW is stepped for the soak), never absolute.
set -eu

[ $# -eq 1 ] || { echo "usage: walk_v12.sh <scratch dir>" >&2; exit 2; }
W="$(mkdir -p "$1" && cd "$1" && pwd)"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
FX="$REPO/tests/fixtures/research-kit"
KIT="$REPO/scripts/research-kit"
CR="$REPO/bin/cc-research"
export HOME="$W/home-fixture"
export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
export CC_RESEARCH_VAULT_KEY="walk-key" CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
unset CC_RESEARCH_RECORDS CC_BATS_ACTIVE
mkdir -p "$HOME" "$CC_RESEARCH_HOME"
T0="$(date -u +%s)"
at() { /usr/bin/python3 -c "import sys,time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
export CC_NOW; CC_NOW="$(at "$T0")"

say() { printf '\n## %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; "$@"; }
# runs a command that must refuse; its exit code is printed, never fatal
refuse() { printf '$ %s\n' "$*"; set +e; "$@"; rc=$?; set -e; echo "(exit $rc)"; [ "$rc" -ne 0 ]; }
preflight() { # <slug>: preflight.json as courier.sh preflight writes it, an hour before CC_NOW
  /usr/bin/python3 - "$CC_RESEARCH_HOME/$1/preflight.json" "$CC_NOW" <<'PY'
import calendar, json, os, sys, time
path, now = sys.argv[1], sys.argv[2]
t = calendar.timegm(time.strptime(now, "%Y-%m-%dT%H:%M:%SZ")) - 3600
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump({v: {"ok": True, "model_id": v + "-model", "error": None,
               "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))}
           for v in ("anthropic", "frontier", "openai", "google")}, open(path, "w"))
PY
}

# ── Part A: intake and the yield stop on a fresh v1.2 program ──────────────────────────────────
say "Part A — stage 1 by intake.py on a fresh program (REPORT.md §3.2)"
ROOT="$W/walk-repo"; mkdir -p "$ROOT"
run "$KIT/intake.py" init --program walk --root "$ROOT" --profile lite \
  --deliverable "a daemon that loses 0 writes in 1000 trials" --intent "make it solid"
run "$KIT/intake.py" ruling --program walk --which definition-of-complete --adopt --quote "adopt it"
run "$KIT/intake.py" ruling --program walk --which exemption --adopt --quote "adopt it too"
run "$KIT/intake.py" set --program walk --escape-cost-days 3
preflight walk
run "$KIT/intake.py" contract-page --program walk
WREC="$ROOT/docs/research/walk"
echo "frame.json method_version: $(/usr/bin/python3 -c "import json; print(json.load(open('$WREC/frame.json'))['method_version'])")"
printf '$ sed -n "/^## Profile/,/^## Your escape/p" CONTRACT.md\n'
sed -n '/^## Profile/,/^## Your escape/p' "$WREC/CONTRACT.md"
run "$CR" ceiling --program walk

say "Part A — stage 3 ends on yield, not on the clock (REPORT.md §12.1)"
run "$CR" budget start --program walk --stage 3
run "$CR" probe --program walk --id P-1 --kind skeleton --negative-control false -- /bin/bash -c 'exit 1'
refuse "$CR" yield show --program walk --stage 3
refuse "$CR" budget end --program walk --stage 3
for i in 2 3 4 5 6 7; do
  CC_NOW="$(at $((T0 + i * 1800)))"
  run "$CR" probe --program walk --id "P-$i" --kind skeleton --negative-control false -- /bin/bash -c true
done
run "$CR" yield show --program walk --stage 3
run "$CR" budget end --program walk --stage 3
CC_NOW="$(at "$T0")"

# ── Part B: Stage 9 on the known-good program ──────────────────────────────────────────────────
say "Part B — fixture: the known-good program demo at a signed research certificate (stages 2-8)"
"$FX/build_good.py" "$W" > "$W/records-path"
"$FX/build_built.py" "$W"
REC="$(cat "$W/records-path")"
A="$W/artifact"
/usr/bin/python3 - "$REC" "$CC_RESEARCH_HOME/demo/built" "$CC_NOW" "$REPO" <<'PY'
import glob, json, os, shutil, sys
rec, sealed, now, repo = sys.argv[1:5]
sys.path.insert(0, repo + "/scripts/research-kit/lib")
import kit
# the hand-written Stage 9 records go: every one of them is re-made below by a verb
shutil.rmtree(f"{rec}/built")
for d in glob.glob(f"{rec}/rounds/b*"):
    shutil.rmtree(d)
kit.registry_set("demo", "certified", cwd_roots=[os.path.dirname(os.path.dirname(os.path.dirname(rec)))])
acc = json.load(open(f"{rec}/acceptance.json"))
acc["rows"][0]["check_cmd"] = 'grep -q "echo ok" "$ARTIFACT/daemon.sh"'
json.dump(acc, open(f"{rec}/acceptance.json", "w"))
os.makedirs(sealed, exist_ok=True)
json.dump([{"id": f"M-{i}", "file": "daemon.sh", "search": "echo ok", "replace": f"echo bad-{i}"}
           for i in range(1, 11)], open(f"{sealed}/mutants.json", "w"))
open(f"{rec}/probes.jsonl", "a").write(json.dumps({"id": "P-3", "cmd": ["/bin/bash", "daemon.sh"]}) + "\n")
cert = json.load(open(f"{rec}/cert/CERT-v1.json"))
cert.update(issued=now, changes_at_issue=[], forecast={
    "desk_mean": 6.0, "desk_n95": 9, "invisible_mean": 0.5, "invisible_bound95": 2,
    "before_impl_mean": 3.8, "after_impl_mean": 2.7, "after_impl_bound95": 11,
    "build_findable_share": 0.585},
    stop="dry", quiet_streak=2, rounds=2, profile="lite",
    fingerprint={"model": "m", "rules": "r", "memory": "x"},
    state={"decisions": 1, "populations": 1, "checks": 1, "premises_at_level": 1, "premises": 1,
           "sources": 1, "ruled_90": 1, "operator_ruled": 0, "by_default": [], "carried": [],
           "parked": 0, "frame_defects": 0, "unasked_intent": 0})
json.dump(cert, open(f"{rec}/cert/CERT-v1.json", "w"))
PY
"$FX/build_built.py" "$W" resign
echo "registry: demo $(/usr/bin/python3 -c "import json; print([p['state'] for p in json.load(open('$CC_RESEARCH_REGISTRY'))['programs'] if p['slug'] == 'demo'][0])"), frame method_version 1.2, research certificate CERT-v1 signed"

say "Stage 9.1 — freeze the built snapshot (gate.sh built-freeze)"
run "$KIT/gate.sh" built-freeze --program demo --artifact "$A" --wave B1 --wave B2

say "Stage 9.2 — a finding is material only with a failing test the tool ran"
run "$CR" built finding add --program demo --source contact --severity material \
  --claim "daemon.sh runs without set -u, so a typo'd variable expands to nothing" \
  --test-cmd "grep -qx 'set -u' daemon.sh"
refuse "$CR" built finding fix --program demo --id BF-1
run "$CR" built finding add --program demo --source round --severity material --claim "the retry might be slow"
echo "-- the fix lands as a new commit; the snapshot is re-frozen on it"
printf '#!/bin/bash\nset -u\necho ok\n' > "$A/daemon.sh"
git -C "$A" -c user.name=t -c user.email=t@example.com commit -qam "set -u"
run "$KIT/gate.sh" built-freeze --program demo --artifact "$A" --wave B1 --wave B2 --refreeze
run "$CR" built finding fix --program demo --id BF-1

say "Stage 9.3 — mutation testing of the acceptance harness, mutants as seeds"
run "$CR" built mutate --program demo

say "Stage 9.4 — as-built contact: empty HOME, PATH=/usr/bin:/bin, /bin/bash 3.2"
run "$CR" built contact --program demo --target P-3 --negative-control 'test -f missing.sh'
run "$CR" built contact --program demo --target AM-1 --negative-control 'grep -q "echo ok" /dev/null'

say "Stage 9.5 — the soak: cc-research job soak, hourly for 25 hours (what com.claude.research-soak runs)"
for h in $(seq 1 25); do
  CC_NOW="$(at $((T0 + h * 3600)))"
  out="$("$CR" job soak)"
  case "$h" in 1|2|24|25) echo "[$CC_NOW] \$ cc-research job soak → $out" ;; 3) echo "  … hours 3-23 …" ;; esac
done

say "Stage 9.6 — built rounds over the snapshot (stub courier; briefs/built-reviewer.md)"
export CC_RESEARCH_COURIER="$W/courier-stub"
cat > "$CC_RESEARCH_COURIER" <<'STUB'
#!/bin/bash
verb="$1"; shift
rid=""; pid=""
while [ $# -gt 0 ]; do
  case "$1" in --round) rid="$2" ;; --pid) pid="$2" ;; esac
  shift
done
[ "$verb" = run ] || exit 0
d="$WALK_REC/rounds/$rid/panels"; mkdir -p "$d"
printf '{"pid":"%s","status":"complete","lenses":[],"findings":[]}\n' "$pid" > "$d/$pid.json"
STUB
chmod +x "$CC_RESEARCH_COURIER"
export WALK_REC="$REC"
preflight demo
for n in 1 2; do
  run "$KIT/round.sh" run --program demo --kind built --round "$n" --plan "$REC/PLAN.md" \
    --brief "$REPO/skills/research-program/briefs/built-reviewer.md" | tail -3
  run "$KIT/round.sh" close --program demo --round "b$n"
done

say "Stage 9.7 — the built gate: rows 20-25, the certificate"
run "$CR" built show --program demo
run "$KIT/gate.sh" built-run --program demo
printf '$ cat built/BUILT-CERT-v1.md\n'
cat "$REC/built/BUILT-CERT-v1.md"
run "$KIT/gate.sh" render --program demo

regstate() { /usr/bin/python3 -c "import json; print([p['state'] for p in json.load(open('$CC_RESEARCH_REGISTRY'))['programs'] if p['slug'] == 'demo'][0])"; }
echo "registry: demo $(regstate)"
[ "$(regstate)" = build-certified ]

say "Stage 9.8 — the implementation signature: the agent renders it, only the operator signs (§11)"
SIGLOG="$CC_RESEARCH_HOME/demo/signoff.jsonl"
implsigs() { grep -c '"action": "implementation"' "$SIGLOG" || true; }
run "$CR" built signoff --program demo
echo "-- unsigned, a build-certified program is not done"
refuse "$KIT/gate.sh" built-signed --program demo
refuse "$KIT/gate.sh" close --program demo
refuse "$KIT/gate.sh" requires --program demo --after-signoff
echo "-- an agent signs: cc-signoff under a process whose name is claude"
AGENT="$W/claude-agent-shell"
ln -s /bin/bash "$AGENT"
printf '$ claude-agent-shell -c "bin/cc-signoff research:demo/implementation --evidence built/BUILT-CERT-v1.md"\n'
set +e
# `; exit $?` keeps the agent shell alive as the CLI's parent (a lone -c command is exec'd in place)
"$AGENT" -c "'$REPO/bin/cc-signoff' research:demo/implementation --evidence built/BUILT-CERT-v1.md; exit \$?"
rc=$?
set -e
echo "(exit $rc)"
[ "$rc" -eq 3 ]
echo "implementation signatures on file: $(implsigs) · registry: demo $(regstate)"
# one test per line: under set -e a failing left side of `A && B` does not stop the script
[ "$(implsigs)" = 0 ]
[ "$(regstate)" = build-certified ]
echo "-- the operator signs: bin/cc-signoff by the fixture signer (an operator's ancestry, fixture store only)"
run "$FX/fixture_signer.py" research:demo/implementation --evidence built/BUILT-CERT-v1.md
echo "implementation signatures on file: $(implsigs) · registry: demo $(regstate)"
[ "$(implsigs)" = 1 ]
[ "$(regstate)" = implementation-signed ]
run "$KIT/gate.sh" render --program demo
run "$KIT/gate.sh" requires --program demo --after-signoff
run "$KIT/gate.sh" close --program demo

say "Walk end: demo is $(regstate), by way of implementation-signed"
[ "$(regstate)" = closed ]
