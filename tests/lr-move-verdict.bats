#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# scripts/limit-recover/lr-move-lib.sh lr_move_verdict — the outcome of one account move, re-derived
# from disk and ps (design-swap-v3 §4.6, 2026-10-04).
#
# THE DEFECT IT REPLACES: the old lane read SWITCHED / NOTMOVED out of the subject's reply and a
# transcript mtime. On 2026-10-04 it reported SWITCHED for 762a6daa, whose target store still held a
# tombstone naming the store it had just left, so the prompt guard blocked every prompt there; the
# proposed "process alive + env + READY" proof passes on that session too.
#
# EVERY CONJUNCT IS MUTATED ALONE: each case starts from the fully MOVED fixture (case 1), breaks
# exactly one fact, and asserts the verdict names exactly that conjunct. So removing any one check
# from lr_move_verdict turns exactly its case red, and case 1 is the control that the fixture is
# otherwise whole. Before lr-move-lib.sh existed none of these cases could run.
#
# Hermetic: see tests/helpers/lr-move-fixture.sh. No pane is read, nothing is written by the subject.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  SID="aaaa1111-0000-4000-8000-000000000001"; PANE=31
  mvf_session "$PANE" "$SID"
  mvf_plan b1 move "$PANE:$SID"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
}
teardown() {
  # the location cases make projects/ unlistable; bats cannot clean a tree it cannot list
  [ -z "${UNLISTABLE:-}" ] || chmod 755 "$SRC/projects" "$DST/projects" 2>/dev/null || true
  mvf_teardown
}
slug_of() { printf %s "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }
location() { # $1=sid [$2=cwd]
  run bash -c '. "$1/lr-lib.sh"; . "$1/lr-move-lib.sh"; lr_session_location "$2" "$3"' _ "$LRD" "$1" "${2:-}"
}

verdict() { # [from cfg] [to cfg] [batch dir or ""]
  run bash -c '. "$1/lr-lib.sh"; . "$1/lr-move-lib.sh"; lr_move_verdict "$2" "$3" "$4" "$5" "$6"' _ \
    "$LRD" "$SID" "$PANE" "${1:-$SRC}" "${2:-$DST}" "${3-$BDIR}"
  V="$(printf '%s' "$output" | cut -f1)"; WHY="$(printf '%s' "$output" | cut -f2)"; FLAGS="$(printf '%s' "$output" | cut -f4)"
}

@test "1 MOVED: the row, the process environment, the one transcript, no tombstone, one holder, admission, debt" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  verdict
  [ "$status" -eq 0 ]
  [ "$V" = MOVED ]
  [ "$FLAGS" = 1111111 ]
}

@test "2 NOTMOVED: before any move the session is live in its pane on the source, one copy" {
  verdict
  [ "$V" = NOTMOVED ]
}

@test "3 P2 alone: the row says target but the process runs under the SOURCE config dir ⇒ FAILED P2" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  # shellcheck disable=SC2153  # MVF_PID is set by mvf_session in the sourced fixture
  printf '%s' "$SRC" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "4 P3 alone: a second live transcript left under the source ⇒ FAILED P3 (two copies)" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  cp "$DST/projects/-x/$SID.jsonl" "$SRC/projects/-x/$SID.jsonl"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P3 transcript:"* ]]
}

@test "5 P4 alone: a tombstone in the target naming another account (the 8e18da3f / 762a6daa shape) ⇒ FAILED P4" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$SRC" > "$DST/projects/-x/$SID.HANDOFF.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P4 tombstone:"* ]] || false
  [[ "$WHY" == *"cc-lr repair-markers --sid $SID"* ]]
}

@test "5b a tombstone in the target naming the target's OWN account is not foreign: still MOVED" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"handed_off_to":"%s","ts":"2026-10-03T02:28:00Z"}\n' "$DST" > "$DST/projects/-x/$SID.HANDOFF.json"
  verdict
  [ "$V" = MOVED ]
}

@test "6 P5 alone: a second live process holding the session ⇒ FAILED P5" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  first="$MVF_PID"
  sleep 900 3>&- &
  other=$!; MVF_PIDS="$MVF_PIDS $other"
  printf '{"paneUUID":"77","pid":%d,"session_id":"%s","account":"claude-tertiary","cwd":"/x"}\n' "$other" "$SID" > "$CC_REGISTRY_DIR/77.json"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$other"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P5 holders:"* ]] || false
  [ "$first" != "$other" ]
}

@test "7 P6 alone: the batch recorded no ranked target ⇒ FAILED P6; without a batch dir P6 is not asked" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"admitted":true,"target":"next3","target_auth":"unverified"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P6 admission:"* ]] || false
  printf '{"admitted":true,"target":"next3","target_auth":"unverified-accepted"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = MOVED ]
  printf '{"admitted":false,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  verdict
  [ "$V" = FAILED ]
  verdict "$SRC" "$DST" ""
  [ "$V" = MOVED ]
}

@test "8 P7 alone: an open resume debt ⇒ FAILED P7; a proven one passes" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  printf '{"state":"open"}\n' > "$CC_RESUME_DEBT_DIR/meta/$SID.json"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P7 resume debt:"* ]] || false
  printf '{"state":"proven"}\n' > "$CC_RESUME_DEBT_DIR/meta/$SID.json"
  verdict
  [ "$V" = MOVED ]
}

@test "9 STRANDED: no live process holds the session" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  kill "$MVF_PID"; wait "$MVF_PID" 2>/dev/null || true
  verdict
  [ "$V" = STRANDED ]
}

@test "10 MOVED-NEW-PANE: the live row is on the target but in another pane" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  jq -c '.paneUUID = "88"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/88.json"; rm -f "$CC_REGISTRY_DIR/$PANE.json"
  verdict
  [ "$V" = MOVED-NEW-PANE ]
}

@test "11 MOVED-UNREGISTERED: the registry row was lost, and one --resume process holds the session under the target" {
  # session-register.sh has a 5 s timeout and loses rows at load 30-50; a lost row is not a failed move.
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  /usr/bin/perl -e 'sleep 900' -- --resume "$SID" 3>&- &
  rp=$!; MVF_PIDS="$MVF_PIDS $rp"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$rp"
  sleep 0.3
  verdict
  [ "$V" = MOVED-UNREGISTERED ]
  # the same process under the SOURCE config dir is not a move
  printf '%s' "$SRC" > "$LR_MOVE_ENV_DIR/$rp"
  verdict
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "11b no registry row and no --resume process: nothing names a holder ⇒ STRANDED" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  verdict
  [ "$V" = STRANDED ]
}

@test "12 the next account: a move ONTO next is MOVED when the row says claude and the store is the mirror" {
  # ~/.claude and ~/.claude-next are one account: the relaunch runs under ~/.claude-next, the
  # registry writes `claude-next` or `claude`, and ~/.claude-next/projects is a symlink to
  # ~/.claude/projects. A raw compare of names or directories fails every such move.
  mkdir -p "$HOME/.claude/projects/-x" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  mv "$SRC/projects/-x/$SID.jsonl" "$HOME/.claude/projects/-x/$SID.jsonl"
  jq -c '.account = "claude"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/$PANE.json.t"; mv "$CC_REGISTRY_DIR/$PANE.json.t" "$CC_REGISTRY_DIR/$PANE.json"
  printf '%s' "$HOME/.claude-next" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict "$SRC" "$HOME/.claude-next"
  [ "$V" = MOVED ]
  # P2 stays byte-exact: the same process under ~/.claude (another Keychain item) is not the target
  printf '%s' "$HOME/.claude" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict "$SRC" "$HOME/.claude-next"
  [ "$V" = FAILED ]
  [[ "$WHY" == "P2 environment:"* ]]
}

@test "13 the next account: a session still on next reads NOTMOVED for a move OFF next" {
  mkdir -p "$HOME/.claude/projects/-x" "$HOME/.claude-next"
  ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  mv "$SRC/projects/-x/$SID.jsonl" "$HOME/.claude/projects/-x/$SID.jsonl"
  jq -c '.account = "claude-next"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/$PANE.json.t"; mv "$CC_REGISTRY_DIR/$PANE.json.t" "$CC_REGISTRY_DIR/$PANE.json"
  verdict "$HOME/.claude-next" "$DST"
  [ "$V" = NOTMOVED ]
}

@test "14 the verdict writes nothing: the fixture tree is byte-identical after a read" {
  mvf_flip "$PANE" "$SID" "$SRC" "$DST"
  before="$(cd "$BATS_TEST_TMPDIR" && find home reg penv debt -type f -exec shasum {} + | sort | shasum)"
  verdict
  after="$(cd "$BATS_TEST_TMPDIR" && find home reg penv debt -type f -exec shasum {} + | sort | shasum)"
  [ "$before" = "$after" ]
}

# THE KNOWN PATH BEFORE THE GLOB (LR_INPLACE_IMMEDIACY W2 (b)). A `projects/*/<sid>.jsonl` glob
# walks ~18,200 dirs in each of 4 stores, 1.0 CPU-s a verdict, and the prove step ran 604-685 s
# after rc 6 (raw/F § 4). Claude Code writes the transcript at projects/<slug(cwd)>/, so a caller
# that knows the cwd stats that path. An UNLISTABLE projects/ (mode 111) is the proof: a stat
# through it works and a glob through it finds nothing, so a hit there came from the known path.

@test "15 location: the transcript at the cwd's slug is found by its path, with every projects/ unlistable" {
  slug="$(slug_of "$BATS_TEST_TMPDIR")"
  mkdir -p "$DST/projects/$slug"; mv "$SRC/projects/-x/$SID.jsonl" "$DST/projects/$slug/$SID.jsonl"
  UNLISTABLE=1; chmod 111 "$SRC/projects" "$DST/projects"
  location "$SID" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$DST"$'\t'"$DST/projects/$slug/$SID.jsonl" ]
  # the verdict passes its plan row's cwd: MOVED, where a glob-only read sees no transcript (P3)
  # the row and the process environment move to the target; the transcript is already there
  jq -c '.account = "claude-tertiary"' "$CC_REGISTRY_DIR/$PANE.json" > "$CC_REGISTRY_DIR/$PANE.json.t"
  mv "$CC_REGISTRY_DIR/$PANE.json.t" "$CC_REGISTRY_DIR/$PANE.json"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$MVF_PID"
  verdict
  [ "$V" = MOVED ]
}

@test "16 location: a slug hit in one store globs no store; no slug hit anywhere, or the switch off, globs them all" {
  slug="$(slug_of "$BATS_TEST_TMPDIR")"
  # a copy at the slug in the target, and a decoy at another dir in the source that only a glob sees
  mkdir -p "$DST/projects/$slug"; cp "$SRC/projects/-x/$SID.jsonl" "$DST/projects/$slug/$SID.jsonl"
  location "$SID" "$BATS_TEST_TMPDIR"
  [ "$output" = "$DST"$'\t'"$DST/projects/$slug/$SID.jsonl" ]
  # a cwd whose slug holds nothing: the glob runs and finds both copies (P3's two-copies read)
  location "$SID" "/no/such/cwd"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  location "$SID"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  export LR_MOVE_LOCATION_FAST=off
  location "$SID" "$BATS_TEST_TMPDIR"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# THE PLAN ROW'S PID IS A HOLDER (LR_INPLACE_IMMEDIACY W2 (d)). On 2026-10-18 e3dedc17 was alive in
# pane 201 with no registry row and no `--resume` argv, so nothing named a holder and the verdict
# said STRANDED "no live process holds the session" (raw/C row 20261018T020022Z·2123). The census
# that wrote the plan saw its pid; that pid, still alive, a claude, and started no later than the
# plan was written (so not a reused pid), is the holder.
# claude_stub → a live process whose argv[0] is .../claude (how a real claude shows in ps); its pid is CP
claude_stub() {
  mkdir -p "$STUBS/.bin"
  /bin/bash -c 'exec -a "$1" sleep 900' _ "$STUBS/.bin/claude" 3>&- &
  CP=$!; MVF_PIDS="$MVF_PIDS $CP"
  printf '%s' "${1:-$SRC}" > "$LR_MOVE_ENV_DIR/$CP"
}
plan_pid() { # $1=pid → the plan row's pid, as cc-lr's census writes it (a string)
  jq -c --arg p "$1" '.rows[0].pid = $p' "$BDIR/plan.json" > "$BDIR/plan.json.t" && mv "$BDIR/plan.json.t" "$BDIR/plan.json"
}

@test "17 [RED] no registry row, no --resume argv, the plan's pid alive as claude on the source: NOTMOVED, not STRANDED" {
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  claude_stub "$SRC"
  i=0; until [ -n "$(ps -o command= -p "$CP" 2>/dev/null)" ] || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
  plan_pid "$CP"
  verdict
  [ "$V" = NOTMOVED ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | cut -f3)" = "$CP" ]
  # the same process under the target, its transcript moved: the move happened, its row was lost
  mv "$SRC/projects/-x/$SID.jsonl" "$DST/projects/-x/$SID.jsonl"
  printf '%s' "$DST" > "$LR_MOVE_ENV_DIR/$CP"
  verdict
  [ "$V" = MOVED-UNREGISTERED ] || { echo "$output"; false; }
}

@test "17b the plan's pid dead, reused (started after the plan), or not a claude: still STRANDED" {
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  # not a claude: a live process with another argv[0]
  sleep 900 3>&- &
  other=$!; MVF_PIDS="$MVF_PIDS $other"
  plan_pid "$other"
  verdict
  [ "$V" = STRANDED ]
  # reused: a claude that started after the plan was written
  claude_stub "$SRC"
  plan_pid "$CP"
  touch -t 202001010000 "$BDIR/plan.json"
  verdict
  [ "$V" = STRANDED ]
  # dead
  touch "$BDIR/plan.json"
  kill "$CP"; wait "$CP" 2>/dev/null || true
  verdict
  [ "$V" = STRANDED ]
}
