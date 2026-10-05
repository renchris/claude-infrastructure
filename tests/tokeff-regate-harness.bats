#!/usr/bin/env bats
# tokeff-regate-harness — the F1 harness builds today's arms, keeps the machine's memory out of a run,
# and the held-out tasks T22-T31 stay frozen (docs/research/token-efficiency-2026-09-23/eval/GATE.md
# § Held-out re-gate, prepared 2026-10-04).
#
# WHY. Since the 2026-10-03 layout (~/.claude/CLAUDE.md = the selected slim variant, the full text in
# CLAUDE.full.md, the slim close rules in ~/.claude/rules/10-session-close.md) build-arms.sh refused
# (STALE), copied slim as the "full" arm and a deleted lessons file, and run.sh's hard-coded exclude
# list let the 31 KB close-rules file load into BOTH arms. No model is called here: claude is a stub.
#
# Hermetic: HOME is a scratch dir; the arms come from a fixture checkout ($GATE_SRC); the mission board
# is rendered by the repo's own bin/cc-mission from one blocked-operator row.

setup() {
  unset CC_BATS_ACTIVE GATE_REQUIRE_SYNC GATE_BOARD_SPLIT GATE_GUARD
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HARNESS="$REPO/docs/research/token-efficiency-2026-09-23/eval/harness"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_MISSION="$REPO/bin/cc-mission"
  local rows="$HOME/.claude/autonomy/customer/rows" now
  mkdir -p "$rows" "$HOME/.claude/rules"
  now="$(date +%s)"
  printf '{"id":"t1","lead":"Test lead","venue":"Room","artifact":"floor-plan","state":"blocked-operator","blocked_since":%s,"budget_days":1,"next":"do the thing"}\n' \
    "$((now - 5 * 86400))" > "$rows/t1.json"
  # the live layout: slim in CLAUDE.md, the slim close rules + board under rules/
  printf 'slim text\n' > "$HOME/.claude/CLAUDE.md"
  printf 'close rules\n' > "$HOME/.claude/rules/10-session-close.md"
  printf 'board\n' > "$HOME/.claude/rules/00-mission-board.md"
  # a fixture checkout holding the three source files, slim derived from the current full text
  export GATE_SRC="$BATS_TEST_TMPDIR/src"; mkdir -p "$GATE_SRC"
  printf '# full text\nFULL-ONLY RULE\n' > "$GATE_SRC/CLAUDE.global.md"
  local h; h="$(shasum -a 256 "$GATE_SRC/CLAUDE.global.md" | cut -c1-16)"
  printf '<!-- instructions-variant: slim · derived-from CLAUDE.global.md sha256:%s -->\n# slim\n' "$h" \
    > "$GATE_SRC/CLAUDE.global.slim.md"
  printf '## Session Close Protocol (slim)\n' > "$GATE_SRC/CLAUDE.rules.slim.10-session-close.md"
  export GATE_ROOT="$BATS_TEST_TMPDIR/gate"
}

@test "build-arms --dry-run: full = the full text alone, slim = slim + its close rules; nothing under GATE_ROOT" {
  run bash "$HARNESS/build-arms.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"slim sync: in sync"* ]] || false
  [[ "$output" == *"build-arms --dry-run: OK"* ]] || false
  # each arm's printed file list: the full arm has the board but no close rules; the slim arm has both
  local full slim
  full="$(printf '%s\n' "$output" | awk '/^full arm:/{f=1;next} /^slim arm:/{f=0} f')"
  slim="$(printf '%s\n' "$output" | awk '/^slim arm:/{f=1;next} /^memory excludes/{f=0} f')"
  [[ "$full" == *" CLAUDE.md"* && "$full" == *"rules/00-mission-board.md"* ]] || false
  [[ "$full" != *"10-session-close"* ]] || false
  [[ "$slim" == *" CLAUDE.md"* && "$slim" == *"rules/10-session-close.md"* && "$slim" == *"rules/00-mission-board.md"* ]] || false
  [ ! -e "$GATE_ROOT" ]
}

@test "build-arms: the frozen arms hold exactly their own files, and the board is identical in both" {
  run bash "$HARNESS/build-arms.sh"
  [ "$status" -eq 0 ]
  cmp "$GATE_SRC/CLAUDE.global.md" "$GATE_ROOT/arms/full/CLAUDE.md"
  cmp "$GATE_SRC/CLAUDE.global.slim.md" "$GATE_ROOT/arms/slim/CLAUDE.md"
  cmp "$GATE_SRC/CLAUDE.rules.slim.10-session-close.md" "$GATE_ROOT/arms/slim/rules/10-session-close.md"
  [ ! -e "$GATE_ROOT/arms/full/rules/10-session-close.md" ]
  [ ! -e "$GATE_ROOT/arms/full/rules/agent-operating-lessons.md" ]
  cmp "$GATE_ROOT/arms/full/rules/00-mission-board.md" "$GATE_ROOT/arms/slim/rules/00-mission-board.md"
  grep 'do the thing' "$GATE_ROOT/arms/full/rules/00-mission-board.md" >/dev/null
  (cd "$GATE_ROOT/arms" && shasum -a 256 -c MANIFEST.sha256 >/dev/null)
}

@test "build-arms: a STALE slim warns and builds; GATE_REQUIRE_SYNC=1 refuses" {
  printf 'a rule added after the slim was derived\n' >> "$GATE_SRC/CLAUDE.global.md"
  run bash "$HARNESS/build-arms.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"slim sync: STALE"* ]] || false
  GATE_REQUIRE_SYNC=1 run bash "$HARNESS/build-arms.sh"
  [ "$status" -eq 3 ]
  [ ! -e "$GATE_ROOT/arms" ]
}

@test "run.sh: the close-rules file and any later rules file are excluded from the run's memory" {
  printf 'added later\n' > "$HOME/.claude/rules/99-new.md"
  mkdir -p "$HOME/.claude/rules/sub"; printf 'nested\n' > "$HOME/.claude/rules/sub/deep.md"
  mkdir -p "$GATE_ROOT/arms/slim/rules" "$BATS_TEST_TMPDIR/tasks/T99"
  : > "$GATE_ROOT/arms/slim/CLAUDE.md"; : > "$GATE_ROOT/arms/slim/rules/x.md"
  export GATE_TASKS="$BATS_TEST_TMPDIR/tasks"
  printf 'do the thing\n' > "$GATE_TASKS/T99/prompt.txt"
  # shellcheck disable=SC2016  # the stub's text is literal; it expands when the stub runs
  printf '#!/bin/bash\nmkdir -p "$1" && git -C "$1" init -q\n' > "$GATE_TASKS/T99/fixture.sh"
  chmod +x "$GATE_TASKS/T99/fixture.sh"
  local ccd="$BATS_TEST_TMPDIR/ccd"; mkdir -p "$ccd"
  # the stub claude records the --settings value it was given
  export CLAUDE_BIN="$BATS_TEST_TMPDIR/claude-stub" SEEN="$BATS_TEST_TMPDIR/settings.json"
  # shellcheck disable=SC2016  # the stub's text is literal; it expands when the stub runs
  printf '#!/bin/bash\nwhile [ $# -gt 0 ]; do [ "$1" = --settings ] && printf "%%s" "$2" > "$SEEN"; shift; done\necho "{}"\n' > "$CLAUDE_BIN"
  chmod +x "$CLAUDE_BIN"
  run bash "$HARNESS/run.sh" slim T99 1 "$ccd"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; ex=json.load(open(sys.argv[1]))["claudeMdExcludes"]; print("\n".join(ex))' "$SEEN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.claude/rules/10-session-close.md"* ]] || false
  [[ "$output" == *"$HOME/.claude/rules/99-new.md"* ]] || false
  [[ "$output" == *"$HOME/.claude/CLAUDE.md"* ]] || false
  [[ "$output" == *"$ccd/CLAUDE.md"* ]] || false
  [[ "$output" == *"$HOME/.claude/rules/sub/deep.md"* ]] || false
  # the list run.sh actually passed covers every file an independent walk finds
  run python3 -B "$HARNESS/gate-excludes.py" --check "$ccd" "$SEEN"
  [ "$status" -eq 0 ]
}

@test "gate-excludes --check walks the disk itself: a list missing a live rules file fails" {
  local ccd="$BATS_TEST_TMPDIR/ccd"; mkdir -p "$ccd/rules"
  printf 'account rule\n' > "$ccd/rules/05-acct.md"
  python3 -B "$HARNESS/gate-excludes.py" "$ccd" > "$BATS_TEST_TMPDIR/all.json"
  run python3 -B "$HARNESS/gate-excludes.py" --check "$ccd" "$BATS_TEST_TMPDIR/all.json"
  [ "$status" -eq 0 ]
  # the same list minus the close-rules file, as the 2026-09 hard-coded list was
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); s["claudeMdExcludes"]=[p for p in s["claudeMdExcludes"] if not p.endswith("10-session-close.md")]; json.dump(s,open(sys.argv[2],"w"))' \
    "$BATS_TEST_TMPDIR/all.json" "$BATS_TEST_TMPDIR/short.json"
  run python3 -B "$HARNESS/gate-excludes.py" --check "$ccd" "$BATS_TEST_TMPDIR/short.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LEAKS    $HOME/.claude/rules/10-session-close.md"* ]] || false
}

@test "build-arms: a leak refusal leaves no arms/ for run.sh, not even the previous build" {
  run bash "$HARNESS/build-arms.sh"
  [ "$status" -eq 0 ]
  [ -f "$GATE_ROOT/arms/slim/CLAUDE.md" ]
  mv "$GATE_SRC/CLAUDE.rules.slim.10-session-close.md" "$BATS_TEST_TMPDIR/"
  run bash "$HARNESS/build-arms.sh"
  [ "$status" -eq 4 ]
  [[ "$output" == *"the slim arm would lack its close rules"* ]] || false
  [ ! -e "$GATE_ROOT/arms" ]
  [ -z "$(find "$GATE_ROOT" -maxdepth 1 -name 'arms.build.*')" ]
}

@test "sched.py plan: the default task set skips the held-out tasks; --tasks still names them" {
  unset GATE_TASKS; mkdir -p "$GATE_ROOT"
  run python3 -B "$HARNESS/sched.py" plan --accounts a,b,c
  [ "$status" -eq 0 ]
  [[ "$output" == *"planned 200 cells over 20 tasks"* ]] || false
  run python3 -c 'import json,sys; print(" ".join(sorted({c["task"][:3] for c in json.load(open(sys.argv[1]))})))' "$GATE_ROOT/schedule.json"
  [ "$output" = "T01 T02 T03 T04 T05 T06 T07 T08 T09 T10 T11 T12 T13 T14 T15 T16 T17 T18 T19 T20" ]
  export GATE_ROOT="$BATS_TEST_TMPDIR/gate2"; mkdir -p "$GATE_ROOT"
  run python3 -B "$HARNESS/sched.py" plan --accounts a --reps 4 --tasks T22-question-endpoint,T30-push-refused
  [ "$status" -eq 0 ]
  [[ "$output" == *"planned 8 cells over 2 tasks"* ]] || false
}

@test "held-out tasks: T22-T31 match their frozen manifest, and every task has a rubric" {
  cd "$HARNESS"
  run shasum -a 256 -c tasks/HELDOUT-MANIFEST.sha256
  [ "$status" -eq 0 ]
  local n; n="$(grep -c '/prompt.txt$' tasks/HELDOUT-MANIFEST.sha256)"
  [ "$n" -eq 10 ]
  # the fixtures source the shared lib, so the freeze must pin it too
  grep '  lib-fixture.sh$' tasks/HELDOUT-MANIFEST.sha256 >/dev/null
  run python3 -c '
import json, os, sys
rub = {k for k in json.load(open("rubrics-heldout.json")) if not k.startswith("_")}
dirs = {d for d in os.listdir("tasks") if d[:3] in {f"T{i}" for i in range(22, 32)}}
sys.exit(0 if rub == dirs and len(dirs) == 10 else f"rubrics {sorted(rub)} != dirs {sorted(dirs)}")'
  [ "$status" -eq 0 ]
}

@test "held-out tasks: every fixture builds, and the traps the rubrics grade are present" {
  local w="$BATS_TEST_TMPDIR/fx" t
  for t in "$HARNESS"/tasks/T2[2-9]-* "$HARNESS"/tasks/T3[01]-*; do
    run /bin/bash "$t/fixture.sh" "$w/${t##*/}/fx" "$w/${t##*/}/origin.git"
    [ "$status" -eq 0 ]
  done
  # T28: the pushed code sources a file that is only untracked
  [ "$(git -C "$w/T28-close-untracked/fx" status --short)" = "?? lib/" ]
  # T30: one commit ahead, and origin refuses main
  [ "$(git -C "$w/T30-push-refused/fx" rev-list --count origin/main..main)" -eq 1 ]
  run git -C "$w/T30-push-refused/fx" push origin main
  [ "$status" -ne 0 ]
  [[ "$output" == *"main is protected"* ]] || false
  # T25: W3b (--json) is in no commit
  run grep -- '--json' "$w/T25-plan-partial-landed/fx/src/export.sh"
  [ "$status" -ne 0 ]
}
