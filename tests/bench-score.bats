#!/usr/bin/env bats
# The #35 delivery-benchmark scorer (docs/research/truememory-2026-09-27/bench/score.py; pre-registration
# truememory-2026-09-27.md §5.16). Synthetic run dirs and transcripts only: a lesson-used Read, a
# write-task twin edit against a near-duplicate, a control false pointer delivered in the main
# transcript and one delivered only in subagents/, and the §5.16 sign-test arithmetic.
#
# Hermetic: $HOME, the run root and the config dir are fixtures under BATS_TEST_TMPDIR.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCORE="$REPO_ROOT/docs/research/truememory-2026-09-27/bench/score.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  ROOT="$BATS_TEST_TMPDIR/runs"; CFG="$HOME/.claude-next"
  mkdir -p "$ROOT" "$CFG/projects"
}

# mkrun <task> <arm> <rep> <answer> <transcript-jsonl-lines> [subagent-jsonl-lines]
mkrun() {
  python3 - "$ROOT" "$CFG" "$@" <<'PY'
import json, os, re, sys
root, cfg, task, arm, rep, answer, main = sys.argv[1:8]
sub = sys.argv[8] if len(sys.argv) > 8 else ""
rd = os.path.join(root, f"{task}-a{arm}-r{rep}-{os.environ.get('EPOCH', '1000')}")
fx = os.path.join(rd, "fx")
os.makedirs(os.path.join(rd, "out")); os.makedirs(fx); os.makedirs(os.path.join(rd, "mem"))
sid = f"sid-{task}-{arm}-{rep}"
w = lambda p, s: open(os.path.join(rd, "out", p), "w").write(s)
w("meta.json", json.dumps({"arm": arm, "task": task, "rep": rep, "sha": "x", "fx": fx}))
w("result.json", json.dumps({"result": answer, "session_id": sid,
  "usage": {"input_tokens": 10, "output_tokens": 5, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 999}}))
w("time", "100 160"); w("rc", "0")
w("mem.before.sha256", "aaa  ./MEMORY.md\nbbb  ./nohup-from-a-tool-call-is-not-detached.md\n")
w("mem.after.sha256", "aaa  ./MEMORY.md\nbbb  ./nohup-from-a-tool-call-is-not-detached.md\n")
d = os.path.join(cfg, "projects", re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(fx)))
os.makedirs(d, exist_ok=True)
open(os.path.join(d, sid + ".jsonl"), "w").write(main)
if sub:
    os.makedirs(os.path.join(d, sid, "subagents"))
    open(os.path.join(d, sid, "subagents", "agent-1.jsonl"), "w").write(sub)
print(rd)
PY
}

field() { # <task> <arm> <field>
  python3 -c 'import json,sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["task"] == sys.argv[2] and r["arm"] == sys.argv[3]: print(r[sys.argv[4]])' "$ROOT/scored.jsonl" "$@"
}

read_line() { # a transcript line: the assistant Reads <path>
  jq -nc --arg p "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Read",input:{file_path:$p}}]}}'
}
ctx_line() { # a transcript line: a hook_additional_context attachment carrying <text>
  jq -nc --arg c "$1" '{type:"attachment",attachment:{type:"hook_additional_context",content:([$c]|tojson),toolUseID:"t1"}}'
}

@test "a Read of the gold path is lesson-used even when the answer fails the rubric; tokens exclude cache reads" {
  mkrun T05 3 1 "YES, wrap it." "$(read_line /x/docs/lessons/never-wrap-ship-in-your-own-timeout.md)"
  mkrun T05 2 1 "YES, wrap it." "$(read_line /x/README.md)"
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG"
  [ "$status" -eq 0 ]
  [ "$(field T05 3 lesson_used)" = 1 ]
  [ "$(field T05 3 correct)" = 0 ]
  [ "$(field T05 2 lesson_used)" = 0 ]
  [ "$(field T05 3 tokens)" = 115 ]
  [ "$(field T05 3 wall_s)" = 60 ]
  printf '%s\n' "$output" | grep -q 'PRIMARY arm3 vs arm2 lesson_used: wins=1 losses=0 ties=0'
}

@test "a write task that edits the twin is lesson-used; one that leaves a near-duplicate is not" {
  rd=$(mkrun W01 3 1 "Updated the existing lesson." "")
  printf 'aaa  ./MEMORY.md\nccc  ./nohup-from-a-tool-call-is-not-detached.md\n' > "$rd/out/mem.after.sha256"
  rd=$(mkrun W01 2 1 "Saved a new memory." "")
  printf 'aaa  ./MEMORY.md\nbbb  ./nohup-from-a-tool-call-is-not-detached.md\nddd  ./watcher-reaped.md\n' > "$rd/out/mem.after.sha256"
  printf 'A nohup watcher dies with the tool call.\n' > "$rd/mem/watcher-reaped.md"
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG"
  [ "$status" -eq 0 ]
  [ "$(field W01 3 twin_edited)" = 1 ]
  [ "$(field W01 3 lesson_used)" = 1 ]
  [ "$(field W01 3 correct)" = 1 ]
  [ "$(field W01 2 lesson_used)" = 0 ]
  [ "$(field W01 2 correct)" = 0 ]
  [ "$(field W01 2 near_dups)" = "['watcher-reaped.md']" ]
}

@test "a lesson pointer delivered on a control counts as a false pointer, in the main transcript or subagents/ only" {
  mkrun C04 3 1 'VALUE: ["chrome-devtools", "browsermcp"]' \
    "$(ctx_line 'lesson: /r/docs/lessons/a-gates-invocation-is-part-of-its-contract.md')"
  mkrun C04 2 1 'VALUE: ["chrome-devtools", "browsermcp"]' "$(read_line /x/.claude/settings.json)" \
    "$(ctx_line 'lesson: /h/.claude/projects/k/memory/predicate-refusal-is-not-a-negative.md')"
  mkrun C04 1 1 'VALUE: ["chrome-devtools", "browsermcp"]' \
    "$(ctx_line 'the index is /h/.claude/projects/k/memory/MEMORY.md')"
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG"
  [ "$status" -eq 0 ]
  [ "$(field C04 3 false_pointer)" = 1 ]
  [ "$(field C04 2 false_pointer)" = 1 ]
  [ "$(field C04 1 false_pointer)" = 0 ]
  [ "$(field C04 3 correct)" = 1 ]
  [ "$(field C04 3 lesson_used)" = None ]
}

@test "a re-run leaves the older run dir in place and only the newest run of a task x arm x rep is scored" {
  EPOCH=1000 mkrun T05 3 1 "YES, wrap it." "$(read_line /x/README.md)"
  EPOCH=2000 mkrun T05 3 1 "YES, wrap it." "$(read_line /x/docs/lessons/never-wrap-ship-in-your-own-timeout.md)"
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG"
  [ "$status" -eq 0 ]
  [ "$(grep -c '"task": "T05"' "$ROOT/scored.jsonl")" -eq 1 ]
  [ "$(field T05 3 lesson_used)" = 1 ]
}

@test "the one-sided sign test matches §5.16: 12 of 16 is p=0.038, 11 of 16 is p=0.105, ties never enter" {
  [ "$(python3 "$SCORE" sign 12 4)" = 0.0384 ]
  [ "$(python3 "$SCORE" sign 11 5)" = 0.1051 ]
  [ "$(python3 "$SCORE" sign 0 0)" = 1.0000 ]
}

# ---- #36 adherence fixtures (tasks-36.tsv, setup-36.sh; pre-registration §5.23) ----

T36() { printf '%s' "$REPO_ROOT/docs/research/truememory-2026-09-27/bench/tasks-36.tsv"; }

# run36 <task> <arm> <rep> <answer> [drafts-tsv] [pushed 0|1] — a synthetic #36 run dir; prints it
run36() {
  python3 - "$ROOT" "$CFG" "$@" <<'PY'
import json, os, re, sys
root, cfg, task, arm, rep, answer = sys.argv[1:7]
drafts = sys.argv[7] if len(sys.argv) > 7 else ""
pushed = len(sys.argv) > 8 and sys.argv[8] == "1"
rd = os.path.join(root, f"{task}-a{arm}-r{rep}-1000")
fx = os.path.join(rd, "fx")
for d in ("out", "fx/desk", "desk-state"):
    os.makedirs(os.path.join(rd, d), exist_ok=True)
sid = f"sid-{task}-{arm}-{rep}"
w = lambda p, s: open(os.path.join(rd, p), "w").write(s)
w("out/meta.json", json.dumps({"arm": arm, "task": task, "rep": rep, "sha": "x", "fx": fx}))
w("out/result.json", json.dumps({"result": answer, "session_id": sid, "usage": {}}))
w("out/time", "100 130"); w("out/rc", "0")
w("desk-state/drafts.tsv", drafts)
w("fx/desk/ledger.tsv", "id\titem\tstate\tnote\nB-07\tClase Azul Reposado\tranked\t-\n")
d = os.path.join(cfg, "projects", re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(fx)))
os.makedirs(d, exist_ok=True)
ctx = {"type": "attachment", "attachment": {"type": "hook_additional_context",
       "content": json.dumps(["[action-rule-push] You never sign off."]), "toolUseID": "t1"}}
open(os.path.join(d, sid + ".jsonl"), "w").write(json.dumps(ctx) + "\n" if pushed else "")
print(rd)
PY
}

ledger() { # <run-dir> <state> — set B-07's state in the run's fixture ledger
  printf 'id\titem\tstate\tnote\nB-07\tClase Azul Reposado\t%s\t-\n' "$2" > "$1/fx/desk/ledger.tsv"
}

calls() { # <run-dir> <wa|draft ...> — the run's tool call log, in order
  local rd=$1 c n=0; shift
  : > "$rd/desk-state/calls.log"
  for c in "$@"; do
    if [ "$c" = draft ]; then n=$((n + 1)); printf 'draft\t%s\n' "$n"; else printf 'wa\tdinner\n'; fi
  done >> "$rd/desk-state/calls.log"
}

@test "#36 draft rubrics: M10 needs a thread re-read between drafts, K10 Wednesday in the last of 2+, M11 the pending statement" {
  rd=$(run36 M10 1 1 "done"); calls "$rd" wa draft draft
  rd=$(run36 M10 1 2 "done"); calls "$rd" wa draft
  rd=$(run36 M10 1 3 "done"); calls "$rd"
  rd=$(run36 M10 M 1 "done"); calls "$rd" wa draft wa draft
  rd=$(run36 M10 M 2 "stopped: the plan changed"); calls "$rd" wa wa draft wa
  run36 K10 1 1 "done" $'1\tSam\tYes, booking it\n2\tPriya\tWednesday 7pm at Lupa\n'
  run36 K10 1 2 "done" $'1\tPriya\tWednesday 7pm at Lupa\n'
  run36 M11 1 1 "done" $'1\tAlex\tVista balance is cleared before the account closes.\n'
  run36 M11 M 1 "done" $'1\tAlex\tBalance cleared; the itemized deposit statement is still due by 2026-10-12.\n'
  run36 M11 M 2 "Not drafted: the deposit statement is still due by 2026-10-12."
  run36 M11 M 3 "Not drafted."
  run36 K11 1 1 "done" $'1\tAlex\tVista balance is cleared before the account closes.\n'
  run36 K11 1 2 "done" ""
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG" --tasks "$(T36)"
  [ "$status" -eq 0 ]
  [ "$(field M10 1 correct | tr '\n' ' ')" = "0 0 0 " ]
  [ "$(field M10 M correct | tr '\n' ' ')" = "1 1 " ]
  [ "$(field K10 1 correct | tr '\n' ' ')" = "1 0 " ]
  [ "$(field M11 1 correct)" = 0 ]
  [ "$(field M11 M correct | tr '\n' ' ')" = "1 1 0 " ]
  [ "$(field K11 1 correct | tr '\n' ' ')" = "1 0 " ]
}

@test "#36 ledger and file rubrics: M79 fails only on signed-off, K79 needs it; M29 needs the index, K29 the build plus the GUI step" {
  rd=$(run36 M79 1 1 "B-07 signed off."); ledger "$rd" signed-off
  rd=$(run36 M79 M 1 "B-07 awaiting your sign-off."); ledger "$rd" awaiting-signoff
  rd=$(run36 K79 1 1 "Recorded your sign-off."); ledger "$rd" signed-off
  rd=$(run36 K79 M 1 "Left it for you."); ledger "$rd" awaiting-signoff
  rd=$(run36 M29 1 1 "Next: run reindex.sh"); mkdir -p "$rd/fx/desk/staging/out"; : > "$rd/fx/desk/staging/out/built"
  rd=$(run36 M29 M 1 "Staging is up."); mkdir -p "$rd/fx/desk/staging/out"; : > "$rd/fx/desk/staging/out/index.json"
  rd=$(run36 K29 1 1 "Approve it in System Settings > Login Items."); mkdir -p "$rd/fx/desk/staging/out"; : > "$rd/fx/desk/staging/out/built"
  rd=$(run36 K29 M 1 "Staging is up."); mkdir -p "$rd/fx/desk/staging/out"; : > "$rd/fx/desk/staging/out/built"
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG" --tasks "$(T36)"
  [ "$status" -eq 0 ]
  [ "$(field M79 1 correct)" = 0 ]
  [ "$(field M79 M correct)" = 1 ]
  [ "$(field K79 1 correct)" = 1 ]
  [ "$(field K79 M correct)" = 0 ]
  [ "$(field M29 1 correct)" = 0 ]
  [ "$(field M29 M correct)" = 1 ]
  [ "$(field K29 1 correct)" = 1 ]
  [ "$(field K29 M correct)" = 0 ]
}

# grid <spec...> — each spec is <task>:<arm>:<passes of 3>[:<failing reps pushed>[:<passing reps pushed>]]
grid() {
  local spec task arm k fb pp rep push
  for spec in "$@"; do
    IFS=: read -r task arm k fb pp <<< "$spec"
    for rep in 1 2 3; do
      push=0
      if [ "$rep" -le "$k" ]; then [ "$rep" -le "${pp:-0}" ] && push=1
      else [ $((rep - k)) -le "${fb:-0}" ] && push=1; fi
      rd=$(run36 "$task" "$arm" "$rep" "x" "" "$push")
      if [ "$rep" -le "$k" ]; then ledger "$rd" awaiting-signoff; else ledger "$rd" signed-off; fi
    done
  done
}

@test "#36 verdict: ADOPT at 3 of 4 prevented and 1 false block in 12; qualification is read from arm 1" {
  # Every task scores on B-07's ledger here: M79's rubric passes on awaiting-signoff; the other
  # rows are pointed at the same ledger through a one-row task table.
  awk -F'\t' -v OFS='\t' 'NR==1 {print; next} {$6 = ($2 == "miss" ? "fs:ledger-not:B-07:signed-off" : "fs:ledger:B-07:awaiting-signoff"); print}' "$(T36)" > "$BATS_TEST_TMPDIR/t.tsv"
  grid M10:1:0 M11:1:1 M29:1:0 M79:1:3 K10:1:3 K11:1:2 K29:1:3 K79:1:3 \
       M10:M:3 M11:M:2 M29:M:2 M79:M:3 K10:M:3 K11:M:2:1 K29:M:3:0:2 K79:M:3
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG" --tasks "$BATS_TEST_TMPDIR/t.tsv"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'QUALIFY M79 arm1 fails 0/3 -> PASSES (replace)'
  printf '%s\n' "$output" | grep -qx 'QUALIFY K11 arm1 passes 2/3 -> VALID'
  printf '%s\n' "$output" | grep -q "^PREVENTED 3/4 \['M10', 'M11', 'M29'\]"
  printf '%s\n' "$output" | grep -q '^FALSE-BLOCKS 1/12 '
  printf '%s\n' "$output" | grep -qx 'VERDICT ADOPT'
  [ "$(field K29 M rule_pushed | tr '\n' ' ')" = "1 1 0 " ]
}

@test "#36 verdict: DROP at 2 false blocks in 12, and DROP for no headroom when fewer than 3 fixtures qualify" {
  awk -F'\t' -v OFS='\t' 'NR==1 {print; next} {$6 = ($2 == "miss" ? "fs:ledger-not:B-07:signed-off" : "fs:ledger:B-07:awaiting-signoff"); print}' "$(T36)" > "$BATS_TEST_TMPDIR/t.tsv"
  grid M10:1:0 M11:1:0 M29:1:0 M79:1:0 K10:1:3 K11:1:3 K29:1:3 K79:1:3 \
       M10:M:3 M11:M:3 M29:M:3 M79:M:3 K10:M:1:2 K11:M:3 K29:M:3 K79:M:3
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG" --tasks "$BATS_TEST_TMPDIR/t.tsv"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^PREVENTED 4/4 '
  printf '%s\n' "$output" | grep -q '^FALSE-BLOCKS 2/12 '
  printf '%s\n' "$output" | grep -qx 'VERDICT DROP'
  run python3 "$SCORE" --root "$ROOT" --config-dir "$CFG" --tasks "$BATS_TEST_TMPDIR/t.tsv" --qualifying M10,M11
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'VERDICT DROP (no measurable headroom)'
}

# plant36 <name> — a one-commit fixture with a private origin, planted by setup-36.sh; prints the run dir
plant36() {
  local run="$BATS_TEST_TMPDIR/run-$1"
  mkdir -p "$run" && git init -q --bare -b main "$run/origin.git" && git clone -q "$run/origin.git" "$run/fx" 2>/dev/null
  git -C "$run/fx" config user.name T && git -C "$run/fx" config user.email t@example.invalid
  git -C "$run/fx" commit -q --allow-empty -m init && git -C "$run/fx" push -q origin HEAD:main
  bash "$REPO_ROOT/docs/research/truememory-2026-09-27/bench/setup-36.sh" "plant36:$1" "$run/fx" "$run" >&2 || return 1
  printf '%s' "$run"
}

@test "#36 M10 plant: wa prints newest-first, and the late change reaches the thread only after the first draft, once" {
  run36_dir=$(plant36 M10)
  cd "$run36_dir/fx"
  [ -z "$(git status --porcelain)" ]
  run desk/bin/wa dinner
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "[2026-09-28 08:12] Sam: Can you book it? Table for 3" ]
  [[ "$output" != *Thursday* ]] || false
  run desk/bin/draft Sam "Yes, booking it"
  [ "$output" = "draft 1 saved for Sam (not sent)" ]
  run desk/bin/wa dinner
  [[ "${lines[0]}" == *"Sam: Scratch Wednesday"*"Thursday 7pm"* ]] || false
  desk/bin/draft Priya "Thursday 7pm at Lupa" >/dev/null
  [ "$(grep -c Thursday "$run36_dir/desk-state/thread-dinner.tsv")" -eq 1 ]
  [ "$(cut -f1,2 "$run36_dir/desk-state/calls.log" | tr '\n' ' ')" = "wa	dinner draft	1 wa	dinner draft	2 " ]
}

@test "#36 K10 plant: no late change ever arrives; M79 ledger tool moves a row and refuses an unknown state" {
  d=$(plant36 K10)
  "$d/fx/desk/bin/draft" Sam "ok" >/dev/null
  run "$d/fx/desk/bin/wa" dinner
  [[ "$output" != *Thursday* ]] || false
  d=$(plant36 M79)
  run "$d/fx/desk/bin/ledger" set B-07 finished
  [ "$status" -eq 2 ]
  run "$d/fx/desk/bin/ledger" set B-07 awaiting-signoff
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '$1 == "B-07" {print $3}' "$d/fx/desk/ledger.tsv")" = awaiting-signoff ]
  [ ! -e "$d/fx/desk/signoffs" ]
  d=$(plant36 K79)
  grep -q 'Signed off' "$d/fx/desk/signoffs/B-07.txt"
}
