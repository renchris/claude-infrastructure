#!/usr/bin/env bats
# lr-fire-resume.sh — a refused launch with no run dir is QUEUED once and exits 75 (K3).
#
# THE INCIDENT (lr-wake 2026-10-18, RC2, c2 §2.5). The in-pane capacity gate refused with rc 9, said
# "Shed load first …, then re-run this exact command", named CC_ADMIT_MAX_LOAD_PER_CORE whatever term
# had refused, and left a plain shell. An agent did re-run it — 25 fires, 12 refusal husks. With no
# run dir nothing else would ever retry the launch, so the cure is a durable request the poller owns
# (requests/<sid>.cc-lr.json, refusals counted in place) and rc 75, which the pane runner closes on.
# With a run dir its owner retries: rc 9 and relaunch.rc, exactly as before, and no request.
#
# The WHOLE script runs, up to the gate, against the real capacity-admit.sh: the load term is fed
# through the library's own CC_ADMIT_LOADAVG_OVERRIDE seam, so the refusal is a real one. No gate is
# switched off; the ambient terms this suite has no case for are deselected, as capacity-admit.bats does.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity ratchet (handoff-fire's gate; not this one)
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.txt"\n' "$BATS_TEST_TMPDIR" > "$CC_ADMIT_NOTIFY_BIN"
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  # The refusing input: load 999 on whatever this box has, far over any per-core ceiling; a budget
  # no test reaches, so no release can turn a refusal into an admit mid-case.
  export LR_LOAD_TERM=on CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_BUDGET=99
  export CC_ADMIT_RESERVE_TERM=off CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_SEGMENT_TERM=off
  export LR_PRESEED_DONE=test CC_RESUME_TOMBSTONE_LIB="" CC_RESUME_TEAMMATE_GUARD=checked
  unset LR_RUN LR_RUN_DIR LR_ADMIT_TOKEN LR_SUBMIT_TOKEN CC_PANE_EXIT_OWED
  CFG="$BATS_TEST_TMPDIR/target"; mkdir -p "$CFG/projects"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  SID="bbbb2222-0000-4000-8000-000000000002"
  # A binary that would only run if the gate let the launch through — and then ends at once.
  export LR_CLAUDE_BIN="$BATS_TEST_TMPDIR/claude"
  printf '#!/bin/bash\necho SPAWNED >> "%s/spawned"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$LR_CLAUDE_BIN"
  chmod +x "$LR_CLAUDE_BIN"
  REQ="$LR_STATE_DIR/requests/$SID.cc-lr.json"
}

fire() {
  run timeout 120 /bin/bash "$FIRE" "$CFG" "$WT" "$SID" --model m --effort high --prompt "continue the work" </dev/null
  # What a terminal draws: the mouse-reporting resets (`ESC[?1000l` …) are consumed without a glyph,
  # and with the preflight notes now in the log they would otherwise prefix the verdict line.
  output="$(printf '%s' "$output" | sed $'s/\e\\[?[0-9;]*[hl]//g')"
}

@test "RED-PROOF no run dir: rc 75, one request carrying the K3 fields, one line naming the term's knob" {
  fire
  [ "$status" -eq 75 ] || { echo "rc $status"; echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/spawned" ] || { echo "the refused launch spawned claude anyway"; false; }
  [ -f "$REQ" ] || { echo "no request at $REQ"; ls -R "$LR_STATE_DIR"; false; }
  run jq -r '[.sid, .mode, .cause, .account, .cwd, .model, .effort, .prompt, (.refusals|tostring), (.first_refused_at|type)] | join("|")' "$REQ"
  [ "$output" = "$SID|recover|capacity|$CFG|$WT|m|high|continue the work|1|number" ] || { echo "request: $output"; false; }
  # the poller owns these, so the writer never sets them
  run jq -r 'has("next_at") or has("cap_k") or has("spawned_at")' "$REQ"
  [ "$output" = false ] || { echo "the writer set a poller-owned field"; cat "$REQ"; false; }
  fire
  local refusal; refusal="$(printf '%s\n' "$output" | grep -E '⏸|✗')"
  [ "$(printf '%s\n' "$refusal" | wc -l | tr -d ' ')" = 1 ] || { echo "not ONE refusal line: $output"; false; }
  [[ "$refusal" == "⏸ ${SID:0:8} queued"* ]] || { echo "the line does not lead with the verdict: $refusal"; false; }
  # The pane carries the term's numbers; the knob that moves THAT term is detail (Wave H2), logged.
  [[ "$refusal" == *"(load "*"/core > "*")"* ]] || { echo "no load fact on the line: $refusal"; false; }
  [[ "$refusal" != *"knob"* ]] || { echo "an override on the pane line: $refusal"; false; }
  grep -q 'knob CC_ADMIT_MAX_LOAD_PER_CORE' "$HOME/.claude/logs/pane-say.jsonl" || { echo "no knob for the load term in the detail"; cat "$HOME/.claude/logs/pane-say.jsonl"; false; }
}

@test "RED-PROOF three re-runs leave exactly ONE request, first_refused_at unchanged, no re-run advice" {
  fire; [ "$status" -eq 75 ] || { echo "rc $status: $output"; false; }
  local first; first="$(jq -r '.first_refused_at' "$REQ")"
  sleep 1
  fire; fire; fire
  [ "$status" -eq 75 ] || { echo "rc $status: $output"; false; }
  [ "$(find "$LR_STATE_DIR/requests" -type f | wc -l | tr -d ' ')" = 1 ] || { ls -la "$LR_STATE_DIR/requests"; false; }
  [ "$(jq -r '.first_refused_at' "$REQ")" = "$first" ] || { echo "first_refused_at was rewritten"; cat "$REQ"; false; }
  [ "$(jq -r '.refusals' "$REQ")" = 4 ] || { echo "refusals not counted in place"; cat "$REQ"; false; }
  [[ "$output" != *"re-run this exact command"* ]] || { echo "the refusal still invites a re-run: $output"; false; }
  [[ "$output" != *"CC_ADMIT_GATE=off"* ]] || { echo "the refusal still offers the gate-off override: $output"; false; }
}

@test "RED-PROOF with a run dir: rc 9, relaunch.rc 9, the owed marker, and NO request" {
  export LR_RUN_DIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$LR_RUN_DIR"
  export CC_PANE_EXIT_OWED="$BATS_TEST_TMPDIR/pane.owed"
  fire
  [ "$status" -eq 9 ] || { echo "rc $status"; echo "$output"; false; }
  [ "$(cat "$LR_RUN_DIR/relaunch.rc")" = 9 ] || { echo "relaunch.rc: $(cat "$LR_RUN_DIR/relaunch.rc" 2>&1)"; false; }
  [ -e "$CC_PANE_EXIT_OWED" ] || { echo "the runner was not told a durable record owns the retry"; false; }
  [ ! -e "$LR_STATE_DIR/requests" ] || [ -z "$(ls -A "$LR_STATE_DIR/requests")" ] || { echo "a run-dir launch queued a request"; ls "$LR_STATE_DIR/requests"; false; }
}

@test "something else already owning the retry is a dedupe hit: rc 75 and no second owner" {
  mkdir -p "$LR_STATE_DIR/parked"; printf '{"sid":"%s"}\n' "$SID" > "$LR_STATE_DIR/parked/$SID.json"
  fire
  [ "$status" -eq 75 ] || { echo "rc $status: $output"; false; }
  [ ! -e "$REQ" ] || { echo "a parked session got a second owner"; false; }
  # The pane says "already queued"; WHO owns the retry is detail (Wave H2), in the cc-say log.
  [[ "$output" == *"⏸ ${SID:0:8} already queued · load "* ]] || { echo "$output"; false; }
  grep -q 'a parked record owns the retry' "$HOME/.claude/logs/pane-say.jsonl" || { cat "$HOME/.claude/logs/pane-say.jsonl"; false; }
}

@test "the worktree argument must be absolute and free of control characters (403's cwd)" {
  run timeout 60 /bin/bash "$FIRE" "$CFG" $'whose\n/tmp' "$SID" --model m </dev/null
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  run timeout 60 /bin/bash "$FIRE" "$CFG" "/tmp/a"$'\n'"b" "$SID" --model m </dev/null
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"control character"* ]] || { echo "no control-character refusal: $output"; false; }
  [ ! -e "$REQ" ]
}
