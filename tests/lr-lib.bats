#!/usr/bin/env bats
# scripts/limit-recover/lr-lib.sh — the shared limit-recover predicates (LIMIT_RECOVER_100P).
# Each function here replaced a per-caller re-derivation that had already produced an incident; the
# suite pins the rule each one enforces and the parity between the two copies of the engagement core.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export LR_LIB_DIR="$REPO/scripts/limit-recover"
  CFG="$BATS_TEST_TMPDIR/cfg-a"; OTHER="$BATS_TEST_TMPDIR/cfg-b"
  SLUG="-Users-x-thing"; mkdir -p "$CFG/projects/$SLUG" "$OTHER/projects/$SLUG"
  SID="aaaa1111-0000-4000-8000-000000000001"
  TX="$CFG/projects/$SLUG/$SID.jsonl"
  . "$LIB"
}
turn() { # $1=file $2=ts $3=model $4=effort [$5=text]
  printf '{"type":"assistant","timestamp":"%s","effort":"%s","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"%s"}]}}\n' "$2" "$4" "$3" "${5:-work}" >> "$1"
}
limit() { printf '{"type":"assistant","timestamp":"%s","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' "$2" >> "$1"; }

# ── tier ──────────────────────────────────────────────────────────────────────────────────────────
@test "tier: the last NON-ERROR turn BEFORE the limit error wins — not argv, not the file tail" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high
  turn "$TX" 2026-09-08T22:30:00.000Z claude-fable-5-1 xhigh
  limit "$TX" 2026-09-08T23:11:09.000Z
  turn "$TX" 2026-09-09T00:52:00.000Z claude-opus-5 max "a same-account rescuer appending by path"
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$status" -eq 0 ]; [ "$output" = "claude-fable-5-1 xhigh" ]
}
@test "tier: with no limit error the last turn overall is the tier" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high
  turn "$TX" 2026-09-08T22:30:00.000Z claude-fable-5-1 max
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$output" = "claude-fable-5-1 max" ]
}
@test "tier: a transcript already renamed .handed-off is still read" {
  turn "$TX" 2026-09-08T22:00:00.000Z claude-opus-5 high; mv "$TX" "$TX.handed-off"
  run lr_tier_from_transcript "$CFG" "$SID"
  [ "$output" = "claude-opus-5 high" ]
}
@test "tier: nothing on disk is rc 1, never a guess" {
  run lr_tier_from_transcript "$CFG" "$SID"; [ "$status" -eq 1 ]
}

# ── engagement after a baseline, and parity with handoff-fire.sh's resume_engaged ────────────────
@test "engaged: a non-error turn newer than the baseline = 0; older-only = 1; API error = 1" {
  turn "$TX" 2026-09-09T01:00:00.000Z claude-opus-5 high
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 1 ]
  limit "$TX" 2026-09-09T01:05:00.000Z
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 1 ]
  turn "$TX" 2026-09-09T01:06:00.000Z claude-opus-5 high
  run lr_engaged_after "$CFG" "$SID" 2026-09-09T01:04:00; [ "$status" -eq 0 ]
}
@test "PARITY: lr_engaged_after and handoff-fire's resume_engaged carry a byte-identical python core" {
  a="$(sed -n '/^lr_engaged_after() {/,/^}/p' "$LIB" | sed -n "/<<'PY'/,/^PY$/p")"
  b="$(sed -n '/^resume_engaged() {/,/^}/p' "$HF" | sed -n "/<<'PY'/,/^PY$/p")"
  [ -n "$a" ] && [ -n "$b" ]
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); false; }
}

# ── liveness from the registry ───────────────────────────────────────────────────────────────────
@test "registry: a row naming the sid with a LIVE pid is a live process; a dead pid is not" {
  printf '{"paneUUID":"616","session_id":"%s","pid":%d,"account":"claude-secondary","cwd":"/x"}\n' "$SID" "$$" > "$CC_REGISTRY_DIR/616.json"
  printf '{"paneUUID":"617","session_id":"%s","pid":4194102,"account":"claude-secondary","cwd":"/x"}\n' "$SID" > "$CC_REGISTRY_DIR/617.json"
  printf '{"paneUUID":"618","session_id":"other","pid":%d}\n' "$$" > "$CC_REGISTRY_DIR/618.json"
  run lr_registry_live_rows "$SID"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [[ "$output" == 616$'\t'$$$'\t'claude-secondary$'\t'/x ]] || { echo "$output"; false; }
}
@test "registry: no live row is rc 1" {
  run lr_registry_live_rows "$SID"; [ "$status" -eq 1 ]
}

# ── transplant read ──────────────────────────────────────────────────────────────────────────────
@test "transplanted_to: a lock naming ANOTHER store whose copy exists prints that store" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$OTHER/projects/$SLUG/$SID.jsonl"
  run lr_transplanted_to "$SID" "$CFG"
  [ "$status" -eq 0 ]; [ "$output" = "$OTHER" ]
}
@test "transplanted_to: the successor is GONE ⇒ rc 1 (this store's copy is the one to act on)" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  run lr_transplanted_to "$SID" "$CFG"; [ "$status" -eq 1 ]
}
@test "transplanted_to: asked FROM the target itself ⇒ rc 1 (the target is the successor)" {
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$CFG" "$OTHER" > "$LR_STATE_DIR/locks/$SID.lock"
  : > "$OTHER/projects/$SLUG/$SID.jsonl"
  run lr_transplanted_to "$SID" "$OTHER"; [ "$status" -eq 1 ]
}

# ── the pane argv shape ──────────────────────────────────────────────────────────────────────────
@test "launch tail: with bin/cc-pane-runner present the window is RUNNER-rooted and the launcher rides in CC_PANE_CMD, non-exec" {
  lr_launch_tail /tmp/lr-launch-x.sh
  [ "$LR_SPAWN_SHAPE" = runner ]
  local joined; joined="$(printf '%s\n' "${LR_LAUNCH_TAIL[@]}")"
  printf '%s\n' "$joined" | grep -qx 'CC_PANE_CMD=bash /tmp/lr-launch-x.sh'
  printf '%s\n' "$joined" | grep -qx 'CC_PANE_CMD_INTERACTIVE=1'
  printf '%s\n' "$joined" | grep -qx 'exec "$CC_PANE_RUNNER"'
  ! printf '%s\n' "$joined" | grep -q 'exec bash'
}
@test "launch tail CONTROL: with no runner anywhere the argv fallback is `-- /bin/bash <launcher>`" {
  export LR_LIB_DIR="$BATS_TEST_TMPDIR/nowhere" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nowhere" CC_PANE_RUNNER_BIN="$BATS_TEST_TMPDIR/absent"
  lr_launch_tail /tmp/lr-launch-x.sh
  [ "$LR_SPAWN_SHAPE" = argv ]
  [ "${LR_LAUNCH_TAIL[1]}" = /bin/bash ] && [ "${LR_LAUNCH_TAIL[2]}" = /tmp/lr-launch-x.sh ]
}

# ── the kitty spawn: anchored beside the SOURCE, socket-addressed, provenance in --var ──────────
@test "kitty spawn with an anchor: vsplit beside it, --source-window pinned, no focus steal, no --title, provenance in --var" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.log"; echo 777\n' "$BATS_TEST_TMPDIR" > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3 616
  [ "$status" -eq 0 ]; [ "$output" = 777 ]
  log="$(cat "$BATS_TEST_TMPDIR/kitty.log")"
  [[ "$log" == *"@ --to unix:/tmp/fake-kitty launch --type=window --location=vsplit --match window_id:616 --next-to id:616 --source-window id:616 --cwd=current --dont-take-focus"* ]] || { echo "$log"; false; }
  [[ "$log" == *"--var lr_continuation_of=$SID --var lr_source_pane=616 --var lr_target_account=next3"* ]] || { echo "$log"; false; }
  [[ "$log" != *"--title"* ]]
}
@test "kitty spawn with no anchor: an os-window at the explicit cwd (never --cwd=current: that reads the ACTIVE window)" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.log"; echo 778\n' "$BATS_TEST_TMPDIR" > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3
  [ "$status" -eq 0 ]; [ "$output" = 778 ]
  grep -q -- '--type=os-window --cwd=/tmp/wt' "$BATS_TEST_TMPDIR/kitty.log"
}
@test "kitty spawn: a non-integer id from kitty is not a pane — rc 1, nothing claimed" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/bash\necho "Error: no such tab"\n' > "$STUB/kitty"; chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:/tmp/fake-kitty"
  run lr_kitty_spawn /tmp/lr-launch-x.sh /tmp/wt "$SID" next3
  [ "$status" -eq 1 ]
}
