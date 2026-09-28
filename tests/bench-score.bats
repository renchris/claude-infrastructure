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
rd = os.path.join(root, task, f"a{arm}-r{rep}")
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

@test "the one-sided sign test matches §5.16: 12 of 16 is p=0.038, 11 of 16 is p=0.105, ties never enter" {
  [ "$(python3 "$SCORE" sign 12 4)" = 0.0384 ]
  [ "$(python3 "$SCORE" sign 11 5)" = 0.1051 ]
  [ "$(python3 "$SCORE" sign 0 0)" = 1.0000 ]
}
