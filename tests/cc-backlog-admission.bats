#!/usr/bin/env bats
# cc-backlog admission gate (BACKLOG_MASTER W0 ledger-admission): what may ENTER the ledger.
#   · fixture-root refusal — add/needs/block from a checkout (or non-git cwd) under a tmp root
#   · class gate on block/needs — warn-only, then enforce on 7 clean days of evidence

setup() {
  export CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_KICK=off CC_BACKLOG_COVERAGE_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export CC_BACKLOG_NEEDS_BRAKE=off CC_BACKLOG_PREMISE=off
  unset CC_BACKLOG_FILE CC_BACKLOG_ALLOW_TMP CC_BACKLOG_CLASS_GATE CC_BACKLOG_GATE_LOG CC_BACKLOG_CALLER
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  LEDGER="$HOME/.claude/autonomy/backlog.jsonl"
  GLOG="$HOME/.claude/autonomy/backlog-gate.jsonl"
  : > "$LEDGER"
  FX=""
}

teardown() {
  case "$FX" in /private/tmp/ccbl-adm-*) rm -rf "$FX" ;; esac
}

mkrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; }

# ── fixture-root refusal ──────────────────────────────────────────────────────────────────────

@test "admission: --project fx from a git repo under /private/tmp is REFUSED, ledger byte-identical" {
  FX="$(mktemp -d /private/tmp/ccbl-adm-XXXXXX)"
  mkrepo "$FX/x/fx"
  before="$(shasum "$LEDGER")"
  cd "$FX/x/fx"
  run bash "$CB" add --title "fixture work" --project fx
  [ "$status" -eq 2 ]
  [[ "$output" == *"fixture root"* ]]
  run bash "$CB" needs "fixture step" --project fx --class needs-human
  [ "$status" -eq 2 ]
  [ "$(shasum "$LEDGER")" = "$before" ]
}

@test "admission: a non-git cwd under /tmp is REFUSED" {
  FX="$(mktemp -d /private/tmp/ccbl-adm-XXXXXX)"
  cd "$FX"
  run bash "$CB" add --title "loose fixture" --project fx
  [ "$status" -eq 2 ]
  [[ "$output" == *"fixture root"* ]]
  [ ! -s "$LEDGER" ]
}

@test "admission: a worktree under a tmp root of a repo OUTSIDE it is admitted" {
  mkrepo "$HOME/src/main"
  export CC_BACKLOG_TMP_ROOTS="$BATS_TEST_TMPDIR/tmproot"
  mkdir -p "$BATS_TEST_TMPDIR/tmproot"
  git -C "$HOME/src/main" worktree add -q "$BATS_TEST_TMPDIR/tmproot/wt-foo" -b wt-foo
  cd "$BATS_TEST_TMPDIR/tmproot/wt-foo"
  run bash "$CB" add --title "real work from a tmp worktree"
  [ "$status" -eq 0 ]
  grep -q '"project":"main"' "$LEDGER"
}

@test "admission: a /private/tmp fixture with its OWN CC_BACKLOG_FILE files into that file" {
  FX="$(mktemp -d /private/tmp/ccbl-adm-XXXXXX)"
  mkrepo "$FX/x/fx"
  cd "$FX/x/fx"
  CC_BACKLOG_FILE="$FX/own.jsonl" run bash "$CB" add --title "graded filing" --project fx
  [ "$status" -eq 0 ]
  grep -q 'graded filing' "$FX/own.jsonl"
  [ ! -s "$LEDGER" ]
}

@test "admission: CC_BACKLOG_ALLOW_TMP=1 overrides the refusal and logs it" {
  FX="$(mktemp -d /private/tmp/ccbl-adm-XXXXXX)"
  cd "$FX"
  CC_BACKLOG_ALLOW_TMP=1 run bash "$CB" add --title "deliberate tmp filing" --project fx
  [ "$status" -eq 0 ]
  jq -e 'select(.event=="tmp-override")' "$GLOG" >/dev/null
}

# ── class gate ────────────────────────────────────────────────────────────────────────────────

addrow() { (cd "$HOME" && bash "$CB" add --title "$1" --project gatesuite); }
nevents() { jq -c --arg e "$1" 'select(.event==$e)' "$GLOG" 2>/dev/null | grep -c . || true; }

@test "class gate (warn): an unclassed block SUCCEEDS and logs exactly one unclassed-transition naming its caller" {
  id="$(addrow "unclassed one")"
  CC_BACKLOG_CALLER=scripts/fake-producer.sh run bash "$CB" block "$id" --needs "somebody should look"
  [ "$status" -eq 0 ]
  [[ "$output" != *WARN* ]]
  [ "$(nevents unclassed-transition)" -eq 1 ]
  jq -e 'select(.event=="unclassed-transition") | select(.caller=="scripts/fake-producer.sh" and .reasons=="unclassed")' "$GLOG" >/dev/null
  [ "$(bash "$CB" list --blocked --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = blocked ]
}

@test "class gate: --class and the dated anchor classify; blockClass survives the fold; no event logged" {
  a="$(addrow "classed a")"; b="$(addrow "classed b")"
  run bash "$CB" block "$a" --needs "the vendor has not shipped 2.2" --class not-yet-true
  [ "$status" -eq 0 ]
  run bash "$CB" block "$b" --needs "On or after 2026-10-14, read the 7-day saving"
  [ "$status" -eq 0 ]
  [ "$(nevents unclassed-transition)" -eq 0 ]
  [ "$(bash "$CB" list --blocked --json | jq -r --arg i "$a" '.[]|select(.id==$i)|.blockClass')" = not-yet-true ]
  [ "$(bash "$CB" list --blocked --json | jq -r --arg i "$b" '.[]|select(.id==$i)|.blockClass')" = not-yet-true ]
}

@test "class gate: needs-human on block without conviction+receipt warns; with them it is clean" {
  a="$(addrow "value call a")"; b="$(addrow "value call b")"
  run bash "$CB" block "$a" --needs "pick the retention window" --class needs-human
  [ "$status" -eq 0 ]
  jq -e 'select(.event=="unclassed-transition" and .reasons=="needs-human-without-conviction")' "$GLOG" >/dev/null
  run bash "$CB" block "$b" --needs "pick the retention window" --class needs-human --conviction 70 --receipt "wc -l x => 3"
  [ "$status" -eq 0 ]
  [ "$(nevents unclassed-transition)" -eq 1 ]
}

@test "class gate (enforce): unclassed block exits non-zero, receipt-less re-block exits non-zero, --force logs" {
  export CC_BACKLOG_CLASS_GATE=enforce
  id="$(addrow "enforced")"
  run bash "$CB" block "$id" --needs "somebody should look"
  [ "$status" -ne 0 ]
  [[ "$output" == *REFUSED* ]]
  run bash "$CB" block "$id" --needs "no-capacity: measured wall" 
  [ "$status" -eq 0 ]
  run bash "$CB" block "$id" --needs "not-yet-true: a rewritten premise"
  [ "$status" -ne 0 ]
  [[ "$output" == *reblock-without-receipt* ]]
  run bash "$CB" block "$id" --needs "not-yet-true: a rewritten premise" --receipt "date => 2026-09-30"
  [ "$status" -eq 0 ]
  id2="$(addrow "forced")"
  run bash "$CB" block "$id2" --needs "prose only" --force
  [ "$status" -eq 0 ]
  [ "$(nevents forced-transition)" -eq 1 ]
  [ "$(nevents unclassed-transition)" -eq 0 ]
}

@test "class gate (enforce): an unclassed needs is refused BEFORE the add — no orphan open row" {
  export CC_BACKLOG_CLASS_GATE=enforce
  n0="$(grep -c . "$LEDGER" || true)"
  run bash -c "cd '$HOME' && bash '$CB' needs 'paste the key'"
  [ "$status" -ne 0 ]
  [ "$(grep -c . "$LEDGER" || true)" = "$n0" ]
  run bash -c "cd '$HOME' && bash '$CB' needs 'paste the key' --class needs-credential"
  [ "$status" -eq 0 ]
}

@test "class gate (auto): enforces only after the armed window passes with zero unclassed events" {
  old="$(date -u -v-8d +%Y-%m-%dT%H:%M:%SZ)"; recent="$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"gate-armed","caller":"x","days":"7"}\n' "$old" > "$GLOG"
  run bash "$CB" class-gate --enforcing
  [ "$status" -eq 0 ]
  printf '{"ts":"%s","event":"unclassed-transition","caller":"scripts/late.sh","id":"x","verb":"block","reasons":"unclassed"}\n' "$recent" >> "$GLOG"
  run bash "$CB" class-gate --enforcing
  [ "$status" -ne 0 ]
  run bash "$CB" class-gate
  [[ "$output" == *"mode=warn"* ]]
  [[ "$output" == *"scripts/late.sh"* ]]
  : > "$GLOG"; printf '{"ts":"%s","event":"gate-armed","caller":"x","days":"7"}\n' "$recent" > "$GLOG"
  run bash "$CB" class-gate --enforcing
  [ "$status" -ne 0 ]
}

# ── activation + roster hygiene ───────────────────────────────────────────────────────────────

@test "activation: a second open row activating the same launchd label is REFUSED" {
  a="$(addrow "Activate com.claude.desk-invariant: flip it to run in launchd/fleet.manifest and load it")"
  run bash -c "cd '$HOME' && bash '$CB' add --title 'Flip com.claude.desk-invariant from staged to run' --project gatesuite"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$a"* ]]
  run bash -c "cd '$HOME' && bash '$CB' add --title 'com.claude.desk-invariant crashed twice today' --project gatesuite"
  [ "$status" -eq 0 ]
  bash "$CB" done "$a" --evidence "loaded"
  run bash -c "cd '$HOME' && bash '$CB' add --title 'Flip com.claude.desk-invariant from staged to run' --project gatesuite"
  [ "$status" -eq 0 ]
}

@test "activation: a run naming a pending-activation script with a .done or .superseded marker is REFUSED" {
  export CC_BACKLOG_PENDING_DIR="$BATS_TEST_TMPDIR/pa"; mkdir -p "$CC_BACKLOG_PENDING_DIR"
  : > "$CC_BACKLOG_PENDING_DIR/36-router-activate.sh.done"
  : > "$CC_BACKLOG_PENDING_DIR/40-other-activate.sh.superseded"
  run bash -c "cd '$HOME' && bash '$CB' add --title 'router' --project gatesuite --run 'CONFIRM=1 bash ~/.claude/docs/activation/pending-activation/36-router-activate.sh'"
  [ "$status" -eq 2 ]
  id="$(addrow "other")"
  run bash "$CB" block "$id" --needs "needs-human: run it" --run "bash x/pending-activation/40-other-activate.sh"
  [ "$status" -eq 2 ]
  run bash -c "cd '$HOME' && bash '$CB' add --title 'fresh' --project gatesuite --run 'bash x/pending-activation/41-new-activate.sh'"
  [ "$status" -eq 0 ]
}

@test "roster: a roster row cannot be claimed and closes when its last member closes" {
  m1="$(addrow "member one")"; m2="$(addrow "member two")"; r="$(addrow "W9 WAVE: header")"
  bash "$CB" link "$m1" --condition rostersuite >/dev/null
  bash "$CB" link "$m2" --condition rostersuite >/dev/null
  run bash "$CB" roster "$r" --of rostersuite
  [ "$status" -eq 0 ]
  run bash "$CB" claim "$r" --by someone
  [ "$status" -eq 4 ]
  bash "$CB" done "$m1" --evidence one
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$r" '.[]|select(.id==$i)|.status')" = open ]
  bash "$CB" done "$m2" --evidence two
  run bash -c "bash '$CB' list --all --json | jq -r --arg i '$r' '.[]|select(.id==\$i)|[.status,.closeKind,.closePointer]|join(\" \")'"
  [ "$output" = "done superseded $m2" ]
}

@test "link --clear --force takes a row out of its group; without --force it is refused" {
  id="$(addrow "grouped")"
  bash "$CB" link "$id" --condition master-operator-gated >/dev/null
  run bash "$CB" link "$id" --clear
  [ "$status" -eq 2 ]
  run bash "$CB" link "$id" --clear --force
  [ "$status" -eq 0 ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.condition // ""')" = "" ]
}

@test "operator gate: only needs-human / needs-credential blocks join master-operator-gated" {
  a="$(addrow "cred")"; b="$(addrow "dated")"; c="$(addrow "value")"
  bash "$CB" block "$a" --needs "paste the key" --class needs-credential >/dev/null
  bash "$CB" block "$b" --needs "On or after 2026-10-14, read it" >/dev/null
  bash "$CB" block "$c" --needs "pick one" --class needs-human --conviction 60 --receipt "ls => x" >/dev/null
  cond() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.condition // ""'; }
  [ "$(cond "$a")" = master-operator-gated ]
  [ "$(cond "$b")" = "" ]
  [ "$(cond "$c")" = master-operator-gated ]
}

# ── the dl route ──────────────────────────────────────────────────────────────────────────────
# A fixture dl store: the real bin/dl module, pointed at an empty DL_DIR; the decay lane is FILLED to
# its cap (15) with live items so the cap arm is exercised by dl's own admit().
dl_fixture() {
  export DL_DIR="$BATS_TEST_TMPDIR/dl"; mkdir -p "$DL_DIR/items"
  local n
  for n in $(seq 1 15); do
    printf '{"id":"admin.decay-%s","kind":"decay","state":"open","title":"call x"}' "$n" > "$DL_DIR/items/admin.decay-$n.json"
  done
}
needs_in() { (cd "$HOME" && bash "$CB" needs "$@"); }

@test "dl route: an admissible real-world act prints the dl add line and is refused here" {
  dl_fixture
  run needs_in "Call Rogers about the renewal" --project personal --dl-lost 2026-10-20 --dl-class money --dl-usd 90 --dl-text "Rogers bills 90 on renewal"
  [ "$status" -eq 3 ]
  [[ "$output" == *"dl add --kind hard --lost 2026-10-20"* ]]
  [ ! -s "$LEDGER" ]
}

@test "dl route: --force keeps an admissible act in the backlog" {
  dl_fixture
  run needs_in "Call Rogers about the renewal" --project personal --dl-lost 2026-10-20 --dl-class money --dl-usd 90 --dl-text "Rogers bills 90" --force
  [ "$status" -eq 0 ]
  [ "$(bash "$CB" list --blocked --json | jq length)" -eq 1 ]
}

@test "dl route: a no-clock act stays a classed needs-human row recording dl's refusal" {
  dl_fixture
  run needs_in "Call the landlord" --project personal
  [ "$status" -eq 0 ]
  row="$(bash "$CB" list --blocked --json | jq -c '.[0]')"
  [ "$(printf '%s' "$row" | jq -r .blockClass)" = needs-human ]
  [[ "$(printf '%s' "$row" | jq -r .needs)" == *"dl refused: kind hard requires --lost"* ]]
}

@test "dl route: a full kind is kept as needs-human with the cap named; a valid --replaces is admitted" {
  dl_fixture
  run needs_in "Call Rogers back" --project personal --dl-kind decay --dl-since 2026-09-20 --dl-class relationship --dl-text "Rogers waits"
  [ "$status" -eq 0 ]
  [[ "$(bash "$CB" list --blocked --json | jq -r '.[0].needs')" == *"decay is at its cap (15/15)"* ]]
  [ "$(bash "$CB" list --blocked --json | jq -r '.[0].blockClass')" = needs-human ]
  run needs_in "Call Bell back" --project personal --dl-kind decay --dl-since 2026-09-20 --dl-class relationship --dl-text "Bell waits" --replaces admin.decay-3
  [ "$status" -eq 3 ]
  [[ "$output" == *"--replaces admin.decay-3"* ]]
}

@test "dl route: work that is not a real-world act is untouched" {
  dl_fixture
  run needs_in "authenticate motion-plus in /mcp" --project gatesuite --class needs-credential
  [ "$status" -eq 0 ]
  [[ "$output" != *"dl add"* ]]
}
