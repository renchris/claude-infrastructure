#!/usr/bin/env bats
# research-kit-rehearse-trial — the agent-run rehearsal (method packet beb0f1a6de53, ruled "agent-run"
# 2026-10-16): `gate.sh rehearsal-activity` opens the rehearsal activity only after the stop, and
# `cc-research rehearse trial` runs ONE relay trial (REPORT.md §3.8) in a bare kitty tab: a fixed
# phrasing as claude's first and only prompt, a fixed cwd, no HANDOFF-ENGAGE envelope, the transcript
# read from the pane's pinned CLAUDE_CONFIG_DIR, the router's label from its route record, the pane
# closed from outside. `rehearse record` reads those rows and gate row 14 reads the record.
# RED-proof: before lib/rehearse_trial.py and gate_cert.cmd_rehearsal_activity, `gate.sh
# rehearsal-activity` and `cc-research rehearse trial` were unknown verbs (argparse exit 2), so no
# agent could open the rehearsal or launch a trial the relay path classifies, and every test below
# fails at its first call.
# Hermetic: PATH=<stubs>:/usr/bin:/bin; a python kitty stub plays the pane (writes the transcript and
# the route record the real claude and router would) and logs every argv.

setup() {
  unset CC_BATS_ACTIVE CC_RESEARCH_BLOCK CC_RESEARCH_ROUTER CC_TERM_KITTY_TO KITTY_LISTEN_ON
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  CR="$REPO/bin/cc-research"
  G="$REPO/scripts/research-kit/gate.sh"
  T="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"
  ROOT="$T/prog"
  B="$T/bin"
  export CC_RESEARCH_HOME="$T/rh"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$ROOT/docs/research/demo"
  REC="$CC_RESEARCH_RECORDS"
  export CLAUDE_CONFIG_DIR="$T/cfg"
  mkdir -p "$HOME" "$B" "$REC/rounds" "$CC_RESEARCH_HOME" "$CLAUDE_CONFIG_DIR"
  reg certifying
  /usr/bin/python3 -c "
import json, sys
json.dump({'profile': 'lite', 'plan': 'PLAN.md', 'reviewer_pins': {'anthropic': 'claude-opus-5-5',
  'frontier': 'claude-fable-5-1', 'openai': 'gpt-x', 'google': 'gemini-x'},
  'reask_map': [{'frame': 'deployed and live', 'axis': 'AM-24'}, {'frame': 'nothing can beat it', 'axis': 'AM-25'},
                {'frame': 'no loose ends', 'axis': 'AM-01'}, {'frame': 'cost', 'axis': None, 'excluded_quote': 'q'}]},
  open(sys.argv[1], 'w'))" "$REC/frame.json"
  printf '# plan\n' > "$REC/PLAN.md"
  printf '{"snapshot_sha":"%s"}\n' "$(printf 'a%.0s' $(seq 40))" > "$REC/freeze.json"
  # the pane's account has trusted both fixed cwds (the program root and this checkout)
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true},"%s":{"hasTrustDialogAccepted":true}}}\n' \
    "$ROOT" "$REPO" > "$CLAUDE_CONFIG_DIR/.claude.json"
  export KITTY_LOG="$T/kitty.log"
  : > "$KITTY_LOG"
  cat > "$B/kitty" <<'EOF'
#!/usr/bin/python3
# The kitty + claude + router stand-in: `@ launch` plays the trial pane (its transcript under the
# CLAUDE_CONFIG_DIR the launch pins, and the route record the router writes); `@ close-window` logs.
import json, os, sys
a = sys.argv[1:]
with open(os.environ["KITTY_LOG"], "a") as fh:
    fh.write(json.dumps(a) + "\n")
if "launch" not in a:
    sys.exit(0)
n = sum(1 for l in open(os.environ["KITTY_LOG"]) if '"launch"' in l)
cfg = next(x.split("=", 1)[1] for i, x in enumerate(a) if a[i - 1] == "--env" and x.startswith("CLAUDE_CONFIG_DIR="))
sid, prompt = a[-2], a[-1]
label = "work-order" if str(n) == os.environ.get("FAKE_WORKORDER_AT") else os.environ.get("FAKE_LABEL", "pushback")
d = os.path.join(cfg, "projects", "-fake-cwd")
os.makedirs(d, exist_ok=True)
recs = [{"type": "user", "message": {"role": "user", "content": prompt}, "sessionId": sid}]
if not os.environ.get("FAKE_SILENT"):
    recs += [
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "t1", "name": "Bash",
                                                       "input": {"command": os.environ.get("FAKE_TOOL", "cc-research verdict demo")}}]}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "x"}]}},
        {"type": "assistant", "message": {"content": [{"type": "text",
                                                       "text": os.environ.get("FAKE_REPLY", "demo: certified on snapshot abc")}]}},
    ]
with open(os.path.join(d, sid + ".jsonl"), "w") as fh:
    fh.write("".join(json.dumps(r) + "\n" for r in recs))
rs = os.path.join(os.environ["CC_RESEARCH_HOME"], "route-state")
os.makedirs(rs, exist_ok=True)
# the router's route record carries `trial` when the launcher marked the session before the pane
marked = os.path.exists(os.path.join(rs, "trials", sid + ".json"))
json.dump({"program": "demo", "label": label, "trial": marked}, open(os.path.join(rs, sid + ".json"), "w"))
print(40 + n)
EOF
  chmod +x "$B/kitty"
  export PATH="$B:/usr/bin:/bin"
  export CC_TERM_KITTY="$B/kitty" CC_TERM_KITTY_TO="unix:$T/kitty.sock"
  export CC_RESEARCH_TRIAL_SETTLE_S=0 CC_RESEARCH_TRIAL_POLL_S=0.05
  export CC_RESEARCH_RENDER='printf "demo: certified on snapshot abc\n"'
}

reg() { # <state>
  printf '{"programs":[{"slug":"demo","aliases":["the demo"],"cwd_roots":["%s"],"state":"%s"}]}\n' \
    "$ROOT" "$1" > "$CC_RESEARCH_REGISTRY"
}
mat() { # <dir> <kind> <seq> [extra json fields]
  mkdir -p "$REC/rounds/$1"
  printf '{"round":"%s","kind":"%s","seq":%s,"closed":true,"counted":true%s}\n' "$1" "$2" "$3" "${4:-}" > "$REC/rounds/$1/matrix.json"
}
# stopped: both frame-critique rounds, then certification rounds 1-5 closed with R_max 5 spent.
stopped() {
  mat fc1 frame-critique 1; mat fc2 frame-critique 2
  mat 1 certification 1 ',"quiet":false,"new_material":1,"forecast":{"p50":1,"p90":1}'
  local i; for i in 2 3 4; do mat "$i" certification "$i" ',"quiet":false,"new_material":1'; done
  mat 5 certification 5 ',"quiet":true,"new_material":0,"verification_only":true'
}
acts() { /usr/bin/python3 -c "import json; print(' '.join(a['id'] + ':' + a['kind'] + ':' + a['state'] for a in json.load(open('$CC_RESEARCH_HOME/activities.json'))['activities']))"; }
opened() { stopped; "$G" rehearsal-activity --program demo 2>/dev/null; }
trial() { "$CR" rehearse trial --program demo --timeout 5 "$@"; }
row() { /usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$REC/evidence/rehearsal/trials-1.jsonl')][$1 - 1]; print($2)"; }
launches() { grep -c '"launch"' "$KITTY_LOG" | tr -d ' '; }
row14() {
  /usr/bin/python3 -c "
import sys
sys.path[:0] = ['$REPO/scripts/research-kit/lib', '$REPO/scripts/lib', '$REPO/scripts/research-kit']
import gate, gate_rows_b
r = gate_rows_b.row14(gate.make_ctx('demo'))
print(r.status, '|', '; '.join(r.evidence))"
}

@test "rehearsal-activity: refused before the stop, while a settle step is owed, while a return is open, and once the relay test settled; idempotent after the stop" {
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"no certification round has run"* ]] || false
  mat fc1 frame-critique 1; mat fc2 frame-critique 2
  mat 1 certification 1 ',"quiet":false,"new_material":1'
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"certification round 2 is still due"* ]] || false
  stopped
  /usr/bin/python3 -c "import json; p='$REC/rounds/5/matrix.json'; d=json.load(open(p)); d['closed']=False; json.dump(d, open(p,'w'))"
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"round 5 is not closed"* ]] || false
  mat 5 certification 5 ',"quiet":true,"new_material":0,"verification_only":true,"kappa":{"materiality":0.1,"below":0.4}'
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"still owes rating re-pass"* ]] || false
  stopped
  printf '{"activities":[{"program":"demo","id":"ACT-demo-1","kind":"front-end-return","state":"open","area":"A1"}]}\n' \
    > "$CC_RESEARCH_HOME/activities.json"
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"a front-end return is open"* ]] || false
  printf '{"activities":[]}\n' > "$CC_RESEARCH_HOME/activities.json"
  reg certified
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"not certifying"* ]] || false
  reg certifying
  run "$G" rehearsal-activity --program demo
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = ACT-demo-1 ]
  run "$G" rehearsal-activity --program demo
  [ "${lines[${#lines[@]}-1]}" = ACT-demo-1 ]
  [ "$(acts)" = "ACT-demo-1:rehearsal:open" ]
  echo '{"event":"record","passed":true}' > "$REC/rehearsal.jsonl"
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"already passed"* ]] || false
  printf '{"event":"record","passed":false}\n{"event":"retest","passed":false}\n' > "$REC/rehearsal.jsonl"
  run "$G" rehearsal-activity --program demo
  [[ "$status" -eq 2 && "$output" == *"one repair and one re-test"* ]] || false
}

@test "rehearse trial: a bare tab whose only prompt is the fixed phrase, no HANDOFF-ENGAGE, the account pinned, the pane closed, the row read from the pane's own transcript" {
  opened >/dev/null
  run trial --phrase "Are you sure?"
  [ "$status" -eq 0 ]
  [ "$(launches)" = 1 ]
  /usr/bin/python3 -c "
import json, sys
calls = [json.loads(l) for l in open('$KITTY_LOG')]
la = next(c for c in calls if 'launch' in c)
assert la[:3] == ['@', '--to', 'unix:$T/kitty.sock'] and la[3] == 'launch', la
assert '--type=tab' in la and '--keep-focus' in la and '--cwd=$ROOT' in la, la
assert la[la.index('--env') + 1] == 'CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR', la
cmd = la[la.index('--') + 1:]
assert cmd[1:3] == ['-ilc', 'claude --session-id \"\$1\" \"\$2\"'], cmd
assert cmd[-1] == 'Are you sure?', cmd           # the phrase alone is the first prompt
blob = json.dumps(la)
for bad in ('HANDOFF-ENGAGE', 'Goal set', 'HANDOFF-PING', 'cc-notify', 'self-close', '--extra'):
    assert bad not in blob, bad
cl = [c for c in calls if 'close-window' in c]
assert cl == [['@', '--to', 'unix:$T/kitty.sock', 'close-window', '--match', 'id:41']], cl
print('ok')"
  [ "$(row 1 "r['trial'], r['prompt'], r['label'], r['cwd'] == '$ROOT', r['tools'], r['reply'], r['closed'], r['timed_out']")" \
    = "1 Are you sure? pushback True ['cc-research verdict demo'] demo: certified on snapshot abc True False" ]
  [ "$(row 1 "r['transcript'].startswith('$CLAUDE_CONFIG_DIR/projects/') and r['session_id'] in r['transcript']")" = True ]
  # a reask_map frame is a fixed phrasing too
  run trial --phrase "no loose ends"
  [ "$status" -eq 0 ]
  [ "$(row 2 "r['trial'], r['prompt']")" = "2 no loose ends" ]
}

@test "rehearse trial refuses an off-list phrase, a name on a root trial, an unregistered name, no open activity, a program not certifying, an untrusted cwd, and a 21st trial" {
  run trial --phrase "Are you sure?"
  [[ "$status" -eq 2 && "$output" == *"no open rehearsal activity"* ]] || false
  opened >/dev/null
  run trial --phrase "Are you sure you checked everything?"
  [[ "$status" -eq 2 && "$output" == *"not a fixed phrasing"* ]] || false
  run trial --phrase "cost"
  [[ "$status" -eq 2 && "$output" == *"not a fixed phrasing"* ]] || false
  run trial --phrase "Are you sure?" --name "the demo"
  [[ "$status" -eq 2 && "$output" == *"only an outside trial names the program"* ]] || false
  run trial --phrase "Are you sure?" --where outside --name "another program"
  [[ "$status" -eq 2 && "$output" == *"not demo's slug or a registered alias"* ]] || false
  printf '{"projects":{}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
  run trial --phrase "Are you sure?"
  [[ "$status" -eq 2 && "$output" == *"has not trusted"* ]] || false
  reg certified
  run trial --phrase "Are you sure?"
  [[ "$status" -eq 2 && "$output" == *"not certifying"* || "$output" == *"'certified'"* ]] || false
  [ "$(launches)" = 0 ]
  reg certifying
  printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$T" > "$CLAUDE_CONFIG_DIR/.claude.json"  # a parent
  mkdir -p "$REC/evidence/rehearsal"
  for i in $(seq 20); do echo '{"trial":0}' >> "$REC/evidence/rehearsal/trials-1.jsonl"; done
  run trial --phrase "Are you sure?"
  [[ "$status" -eq 2 && "$output" == *"already holds 20 trials"* ]] || false
  [ "$(launches)" = 0 ]
}

@test "rehearse trial --where outside: the fixed outside cwd is this checkout, and only that trial names the program" {
  opened >/dev/null
  run trial --phrase "no take-backs?" --where outside
  [ "$status" -eq 0 ]
  [ "$(row 1 "r['cwd'] == '$REPO', r['prompt'], r['where']")" = "True no take-backs? (about the research program the demo) outside" ]
  run trial --phrase "no take-backs?" --where outside --name demo
  [ "$(row 2 "r['prompt']")" = "no take-backs? (about the research program demo)" ]
}

@test "a trial that never ends is recorded timed out, its pane still closed, and the record fails it" {
  opened >/dev/null
  FAKE_SILENT=1 run "$CR" rehearse trial --program demo --phrase "Are you sure?" --timeout 0.3
  [ "$status" -eq 1 ]
  [ "$(row 1 "r['timed_out'], r['closed'], r['reply']")" = "True True " ]
}

@test "the lease: rehearse trial runs while another owner holds it; rehearse record does not" {
  opened >/dev/null
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"owner":"someone-else","pid":1,"host":"h","acquired":"%s","heartbeat":"%s"}\n' "$now" "$now" \
    > "$CC_RESEARCH_HOME/demo/lease.json"
  run trial --phrase "Are you sure?"
  [ "$status" -eq 0 ]
  run "$CR" rehearse record --program demo --frames-typed "no loose ends"
  [[ "$status" -eq 2 && "$output" == *"leased to someone-else"* ]] || false
}

# The acceptance row of the brief: 3 lens frames typed + 20 trials (one outside) passes row 14; 19
# trials, or none outside, fails it. RED on the base commit: `rehearse trial` did not exist.
@test "end to end: 20 trials with one outside, then record (no --trials: the trial file) passes row 14 and closes the activity" {
  opened >/dev/null
  [ "$(row14 | cut -d' ' -f1)" = FAIL ]
  run trial --phrase "Are you sure?" --where outside
  [ "$status" -eq 0 ]
  for i in $(seq 2 20); do
    trial --phrase "Is this all before we close?" >/dev/null
  done
  [ "$(launches)" = 20 ]
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relay test passed: 20 trials"* ]] || false
  [[ "$output" == *"rehearsal activity closed: ACT-demo-1"* ]] || false
  [ "$(acts)" = "ACT-demo-1:rehearsal:closed" ]
  [ "$(row14)" = "PASS | " ]
  run trial --phrase "Are you sure?"
  [[ "$status" -eq 2 && "$output" == *"no open rehearsal activity"* ]] || false
}

@test "end to end: 19 trials fail row 14" {
  opened >/dev/null
  trial --phrase "Are you sure?" --where outside >/dev/null
  for i in $(seq 2 19); do trial --phrase "no take-backs?" >/dev/null; done
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 1 ]
  [[ "$output" == *"19 trials; the relay test is 20"* ]] || false
  [ "$(acts)" = "ACT-demo-1:rehearsal:open" ]   # one repair and one re-test remain
  [ "$(row14 | cut -d' ' -f1)" = FAIL ]
}

@test "end to end: 20 trials with none outside the root fail row 14" {
  opened >/dev/null
  for i in $(seq 20); do trial --phrase "Are you sure?" >/dev/null; done
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no trial was asked from outside"* ]] || false
  [ "$(row14 | cut -d' ' -f1)" = FAIL ]
}

@test "a trial the router labeled a work order (an allow-all turn, not the relay) fails the record, and a failed re-test closes the activity" {
  opened >/dev/null
  trial --phrase "Are you sure?" --where outside >/dev/null
  for i in $(seq 2 20); do FAKE_WORKORDER_AT=3 trial --phrase "if more research moves your conviction, do it now" >/dev/null; done
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trial 3: the router labeled it work-order, not a relay label"* ]] || false
  # the re-test's own file: trials-2.jsonl
  trial --phrase "Are you sure?" >/dev/null
  [ -s "$REC/evidence/rehearsal/trials-2.jsonl" ]
  run "$CR" rehearse record --program demo --frames-typed x --retest
  [ "$status" -eq 1 ]
  [ "$(acts)" = "ACT-demo-1:rehearsal:closed" ]
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$REC/rehearsal.json'))['relay']['unstable'])")" = True ]
}

# §3.8's four phrasings, five times each: the fourth routes research-order (router.relays).
four() { # [FAKE_TOOL for the research-order trials]
  local i
  trial --phrase "Are you sure?" --where outside >/dev/null
  for i in 1 2 3 4 5; do
    [ "$i" = 1 ] || trial --phrase "Are you sure?" >/dev/null
    trial --phrase "Is this all before we close?" >/dev/null
    trial --phrase "no take-backs?" >/dev/null
    FAKE_LABEL=research-order FAKE_TOOL="${1:-cc-research verdict demo}" \
      trial --phrase "if more research moves your conviction, do it now" >/dev/null
  done
}

@test "rehearse trial marks its session for the router before the pane starts, and records that the route saw it" {
  opened >/dev/null
  run trial --phrase "if more research moves your conviction, do it now"
  [ "$status" -eq 0 ]
  sid="$(row 1 "r['session_id']")"
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_HOME/route-state/trials/$sid.json'))['program'])")" = demo ]
  [ "$(row 1 "r['trial_routed']")" = True ]
}

@test "end to end: 20 trials of the four phrasings, five of them research-order relays, pass record and row 14" {
  opened >/dev/null
  four
  [ "$(launches)" = 20 ]
  [ "$(/usr/bin/python3 -c "import json; print(sum(json.loads(l)['label'] == 'research-order' for l in open('$REC/evidence/rehearsal/trials-1.jsonl')))")" = 5 ]
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relay test passed: 20 trials"* ]] || false
  [ "$(row14)" = "PASS | " ]
}

@test "a research-order trial that calls a tool other than the certificate read fails the record" {
  opened >/dev/null
  four "git log --oneline"
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trial 4: it called git log --oneline (only the certificate read is allowed)"* ]] || false
  [[ "$output" != *"not a relay label"* ]] || false
  [ "$(row14 | cut -d' ' -f1)" = FAIL ]
}

# truememory-2-0 run 1, trial 2: the session read the certificate as `bash scripts/research-kit/gate.sh
# --render --program truememory-2-0`, the block denied it, and the record counted the denied call.
@test "a trial that reads the certificate through the bash interpreter passes the record" {
  opened >/dev/null
  read_cmd="bash $REPO/scripts/research-kit/gate.sh --render --program demo"
  FAKE_TOOL="$read_cmd" four "$read_cmd"
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relay test passed: 20 trials"* ]] || false
}

# ── --practice: a real trial that the relay test never reads (preflight before the re-test) ─────
practice_rows() { /usr/bin/python3 -c "import json; print(len([l for l in open('$REC/evidence/rehearsal/practice.jsonl') if l.strip()]))"; }

@test "rehearse trial --practice runs the counted trial's pane, mark and transcript read, writes only practice.jsonl, and prints its own relay verdict" {
  opened >/dev/null
  run trial --phrase "Are you sure?" --practice
  [ "$status" -eq 0 ]
  [ "$(launches)" = 1 ]
  /usr/bin/python3 -c "
import json
la = next(json.loads(l) for l in open('$KITTY_LOG') if '\"launch\"' in l)
assert '--type=tab' in la and '--keep-focus' in la and '--cwd=$ROOT' in la, la
assert la[la.index('--env') + 1] == 'CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR', la
cmd = la[la.index('--') + 1:]
assert cmd[1:3] == ['-ilc', 'claude --session-id \"\$1\" \"\$2\"'] and cmd[-1] == 'Are you sure?', cmd"
  printf '%s' "$output" | jq -e '.practice == true and .fails == [] and .trial == 1' >/dev/null
  [ ! -e "$REC/evidence/rehearsal/trials-1.jsonl" ]
  [ "$(practice_rows)" = 1 ]
  r="$(/usr/bin/python3 -c "import json; r=json.loads(open('$REC/evidence/rehearsal/practice.jsonl').readline()); print(r['practice'], r['trial_routed'], r['label'], r['tools'], r['phrase'])")"
  [ "$r" = "True True pushback ['cc-research verdict demo'] Are you sure?" ]
  sid="$(/usr/bin/python3 -c "import json; print(json.loads(open('$REC/evidence/rehearsal/practice.jsonl').readline())['session_id'])")"
  [ "$(/usr/bin/python3 -c "import json; m=json.load(open('$CC_RESEARCH_HOME/route-state/trials/$sid.json')); print(m['program'], m['practice'])")" = "demo True" ]
  # a failing practice trial says why, the way the record would
  FAKE_TOOL="git log --oneline" run trial --phrase "no take-backs?" --practice
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.trial == 2 and (.fails | length) == 1 and (.fails[0] | test("trial 2: it called git log --oneline"))' >/dev/null
}

@test "practice trials are never read by rehearse record or row 14, neither count toward nor block the 20, and stop once the relay test is settled" {
  opened >/dev/null
  trial --phrase "Are you sure?" --practice >/dev/null
  trial --phrase "no take-backs?" --where outside --practice >/dev/null
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [[ "$status" -eq 2 && "$output" == *"no "*"trials-1.jsonl from rehearse trial"* ]] || false
  run "$CR" rehearse record --program demo --frames-typed x --trials "$REC/evidence/rehearsal/practice.jsonl"
  [[ "$status" -eq 2 && "$output" == *"practice"* ]] || false
  run "$CR" rehearse record --program demo --frames-typed x --practice
  [[ "$status" -eq 2 && "$output" == *"practice"* ]] || false
  [ ! -e "$REC/rehearsal.jsonl" ]
  [ "$(row14)" = "FAIL | no rehearsal record" ]
  four
  run trial --phrase "Is this all before we close?" --practice
  [ "$status" -eq 0 ]
  [ "$(practice_rows)" = 3 ]
  run "$CR" rehearse record --program demo --frames-typed "deployed and live" "nothing can beat it" "no loose ends"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relay test passed: 20 trials"* ]] || false
  run trial --phrase "Are you sure?" --practice
  [ "$status" -eq 2 ]
  # settled with the activity still open (hand-written): refused on the settled record itself
  "$G" rehearsal-activity --program demo >/dev/null 2>&1 || true
  printf '{"activities":[{"program":"demo","id":"ACT-demo-9","kind":"rehearsal","state":"open"}]}\n' \
    > "$CC_RESEARCH_HOME/activities.json"
  run trial --phrase "Are you sure?" --practice
  [[ "$status" -eq 2 && "$output" == *"already passed"* ]] || false
  printf '{"event":"record","passed":false}\n{"event":"retest","passed":false}\n' > "$REC/rehearsal.jsonl"
  run trial --phrase "Are you sure?" --practice
  [[ "$status" -eq 2 && "$output" == *"one repair and one re-test"* ]] || false
  [ "$(practice_rows)" = 3 ]
}
