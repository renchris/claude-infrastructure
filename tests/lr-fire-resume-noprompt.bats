#!/usr/bin/env bats
# lr-fire-resume.sh — W2c: --no-prompt, the agent-view env on the spawn, and the re-send look schedule.
#
# WHY THE WHOLE SCRIPT RUNS HERE. --no-prompt is a promise about the keystrokes a real launch sends
# after READY, and the flag, the prompt forcing and the READY-arm latch live in three places (arg
# parse, bash exports, the expect program). Only a run of the script end to end, against a stub TUI
# that records every byte it reads, can see all three at once. The schedule cases instead extract the
# expect program and drive it directly (tests/lr-fire-resume-submit.bats exp_setup): its timing is the
# subject, and the bash half has nothing to add to it but boot latency.
#
# FIRE may point at another copy of the script (the red-proof run against the pre-change file).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="${FIRE:-$REPO/scripts/limit-recover/lr-fire-resume.sh}"
  [ -f "$FIRE" ] || skip "lr-fire-resume.sh not found"
  command -v expect >/dev/null || skip "expect(1) not installed"
  # HERMETIC: every state root the script can reach resolves under the test dir, and the capacity
  # gate (live load / memory / ps census) is off.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_ADMIT_GATE=off LR_PRESEED_DONE=bats LR_QUIET_S=2
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state" LR_RUN_DIR="$BATS_TEST_TMPDIR/run"
  export LR_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry" LR_CFG_DIRS="$BATS_TEST_TMPDIR/cfgs"
  unset LR_RUN LR_RECORD_ID LR_ATTEMPT LR_SUBMIT_TOKEN LR_ADMIT_TOKEN CC_PANE_ID ITERM_SESSION_ID \
        LR_LAUNCH_LOCK LR_LAUNCH_GUARD LR_RECR_SCHEDULE LR_SUBMIT_POLL_S
  ACCT="$BATS_TEST_TMPDIR/acct"; WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$ACCT" "$WT"
  SID="b2c0ffee-np-$$-$RANDOM"
  # THE REAL CLAUDE MUST NEVER RUN. cc-claude-bin honours CC_CLAUDE_BIN first, so a script that
  # ignores LR_CLAUDE_BIN (the pre-change file) lands on this tripwire, not on the operator's binary.
  TRIP="$BATS_TEST_TMPDIR/tripwire"
  printf '#!/bin/bash\necho TRIPPED >> "%s.hit"\nexit 97\n' "$TRIP" > "$TRIP"; chmod +x "$TRIP"
  export CC_CLAUDE_BIN="$TRIP"
  # The stub TUI: paints the READY phrase, then records every byte it reads (see its own comment).
  STUB="$BATS_TEST_TMPDIR/claude-stub"; export STUB_OUT="$BATS_TEST_TMPDIR/out"
  cat > "$STUB" <<'SH'
#!/bin/bash
env > "$STUB_OUT.env"
: > "$STUB_OUT.bytes"
# RAW before READY is painted, so no byte can be eaten by the line discipline (^U is VKILL when
# cooked) or held back waiting for a newline: every byte sent after READY reaches the file.
stty raw -echo 2>/dev/null
printf 'booting\r\n ? for shortcuts\r\n'
echo READY-PAINTED > "$STUB_OUT.painted"
# Record until the first CR/LF (the end of a typed prompt) or STUB_READ_S seconds, whichever comes
# first: alive well past any injection even under load, so an empty file is a measurement of the
# window, never a stub that had already exited.
/usr/bin/perl -e '$SIG{ALRM} = sub { exit 0 }; alarm($ENV{STUB_READ_S} || 10);
  open(my $f, ">>", "$ENV{STUB_OUT}.bytes") or exit 1; select((select($f), $| = 1)[0]);
  while (sysread(STDIN, my $b, 1)) { print $f $b; exit 0 if $b eq "\r" || $b eq "\n" }'
SH
  chmod +x "$STUB"
  export LR_CLAUDE_BIN="$STUB"
}

fire() { bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high "$@" </dev/null; }

@test "--no-prompt: READY is seen, noted once, and NOTHING is typed after it" {
  # Every keystroke the program can send is sent before interact, and the recorder outlives the
  # program (it stops at a CR or 10 s), so an empty file covers everything the program could type.
  run fire --no-prompt
  [ "$status" -eq 0 ] || { echo "rc=$status"; echo "$output"; false; }
  [ ! -e "$TRIP.hit" ] || { echo "the real-binary tripwire ran: LR_CLAUDE_BIN was ignored"; false; }
  [ -s "$STUB_OUT.painted" ] || { echo "the stub never painted READY — the case proves nothing"; false; }
  [ -f "$STUB_OUT.bytes" ] || { echo "the byte recorder wrote no file"; false; }
  [ ! -s "$STUB_OUT.bytes" ] || { echo "bytes typed after READY:"; od -c "$STUB_OUT.bytes"; false; }
  run grep -c '"READY"' "$LR_RUN_DIR/events.jsonl"
  [ "$output" = 1 ] || { echo "READY notes: $output"; cat "$LR_RUN_DIR/events.jsonl"; false; }
}

@test "control: the byte recorder does see a typed prompt (so zero bytes above is a measurement)" {
  # PAINT_S=0: the CR follows the text at once, so the recorder's CR stop ends the case promptly.
  LR_SUBMIT_PAINT_S=0 run fire --prompt "hello-from-bats"
  [ -s "$STUB_OUT.bytes" ] || { echo "the recorder saw nothing even with a prompt: $output"; false; }
  grep -q 'hello-from-bats' "$STUB_OUT.bytes" || { od -c "$STUB_OUT.bytes" | head; false; }
}

@test "--no-prompt together with --prompt is refused, rc 2" {
  run fire --no-prompt --prompt "x"
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"mutually exclusive"* ]] || { echo "$output"; false; }
  [ ! -e "$STUB_OUT.env" ] || { echo "the stub was spawned despite the refusal"; false; }
}

@test "both spawn lines carry CLAUDE_CODE_DISABLE_AGENT_VIEW=1, and the spawned process sees it" {
  run grep -c 'spawn -noecho env .*DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_AGENT_VIEW=1 ' "$FIRE"
  [ "$output" = 2 ] || { echo "spawn lines carrying it: $output"; false; }
  run fire --no-prompt
  grep -qx 'CLAUDE_CODE_DISABLE_AGENT_VIEW=1' "$STUB_OUT.env" \
    || { echo "not in the stub env (rc=$status)"; echo "$output"; false; }
}

@test "LR_PRESEED_DONE skips the preseed with one stderr line" {
  run fire --no-prompt
  [[ "$output" == *"-- lr-fire-resume: preseed skipped (LR_PRESEED_DONE=bats)"* ]] || { echo "$output"; false; }
}

@test "LR_CLAUDE_BIN that is not an executable file is the cannot-resolve error, rc 1" {
  LR_CLAUDE_BIN="$BATS_TEST_TMPDIR" run fire --no-prompt
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"cannot resolve the claude binary"* ]] || { echo "$output"; false; }
}

@test "an invalid LR_RECR_SCHEDULE falls back to the default, loudly" {
  for bad in "5,3" "0,5" "a,b" "5,,9" "05,9"; do
    LR_RECR_SCHEDULE="$bad" run fire --no-prompt
    [[ "$output" == *"LR_RECR_SCHEDULE='$bad' is not a list"*"using 5,15,30,45"* ]] \
      || { echo "[$bad] no fallback warning: $output"; false; }
    grep -qx 'LR_RECR_SCHEDULE=5,15,30,45' "$STUB_OUT.env" || { echo "[$bad] not exported as the default"; false; }
  done
  LR_RECR_SCHEDULE="2,4" run fire --no-prompt
  [[ "$output" != *"is not a list"* ]] || { echo "a valid schedule was rejected: $output"; false; }
  grep -qx 'LR_RECR_SCHEDULE=2,4' "$STUB_OUT.env"
}

# ── the look schedule, on the extracted expect program ──────────────────────────────────────────────
# The screen stub reads EMPTY on its first call (the quiet arm types the prompt) and DRAFT-MINE from
# then on; the probe stub says `none` until the stub TUI has received two re-sent CRs, then
# `submitted`, which ends the poll without waiting out its deadline. Every line the TUI receives is
# stamped, so the re-sends are measured relative to the first CR (the one ending the typed prompt).
sched_setup() {
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body failed" >&2; return 1; }
  export LR_GOT="$BATS_TEST_TMPDIR/got"
  cat > "$STUB" <<'SH'
#!/bin/bash
echo BOOTED
while IFS= read -r line; do
  printf '%s %s\n' "$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.2f", time')" "${line:-CR}" >> "$LR_GOT"
done
SH
  local b='────────────────────────────────'
  export LR_IT2="$BATS_TEST_TMPDIR/it2" LR_PANE=1 LR_STUB_N="$BATS_TEST_TMPDIR/screen-n"
  cat > "$LR_IT2" <<SH
#!/bin/bash
n=0; [ -f "\$LR_STUB_N" ] && n="\$(cat "\$LR_STUB_N")"; echo \$((n + 1)) > "\$LR_STUB_N"
if [ "\$n" -eq 0 ]; then printf '%s\n' chrome "$b" " ❯ " "$b"; else printf '%s\n' chrome "$b" " ❯ \${LR_SCREEN_LATER:-\$LR_PROMPT}" "$b"; fi
SH
  export LR_PROBE="$BATS_TEST_TMPDIR/probe"
  cat > "$LR_PROBE" <<'SH'
#!/bin/bash
if [ "$(grep -c ' CR$' "$LR_GOT" 2>/dev/null)" -ge 2 ]; then echo "submitted 2026-09-29T00:00:00.000Z"; else echo none; fi
SH
  chmod +x "$STUB" "$LR_IT2" "$LR_PROBE"
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_CFG="$ACCT" LR_BIN="$STUB" LR_MODEL=m LR_EFFORT=high LR_SID="$SID" LR_ASIS=1 LR_WRAP=""
  export LR_PROMPT="resume-schedule-probe-prompt" LR_SUBMIT_TOKEN="run:x:y:0123abcd" LR_NO_PROMPT=0
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" LR_RE_TRUST="$never" \
         LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" LR_RE_OVERAGE="$never" LR_RE_READY="$never"
  export LR_QUIET_S=1 LR_SUBMIT_POLL_S=60 RCY_ENGAGE_TIMEOUT=60 LR_SUBMIT_PAINT_S=4
  LR_SCREEN_WANT="$(printf '%s' "$LR_PROMPT" | cut -c1-40)"; export LR_SCREEN_WANT
  LR_SCREEN_SH="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"; export LR_SCREEN_SH
  [ -n "$LR_SCREEN_SH" ] || { echo "screen-program extraction failed" >&2; return 1; }
  export LR_SAY_LOG="$BATS_TEST_TMPDIR/say.log"
}
# prints the re-send offsets (seconds after the first CR, 2 decimals), one per line
resend_offsets() {
  awk '$2 != "CR" && !t0 { t0 = $1; next } t0 && $2 == "CR" { printf "%.2f\n", $1 - t0 }' "$LR_GOT"
}
in_band() { awk -v x="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(x >= lo && x <= hi) }'; }

@test "schedule: the default re-sends at ~5 s and ~15 s after the first CR" {
  sched_setup
  unset LR_RECR_SCHEDULE
  run timeout 90 expect -f "$EXP" </dev/null
  offs="$(resend_offsets)"; echo "# re-send offsets: ${offs//$'\n'/ }" >&3
  [ "$(printf '%s\n' "$offs" | grep -c .)" -eq 2 ] || { echo "re-sends: [$offs]"; cat "$LR_GOT"; false; }
  # Lower bounds prove the schedule (never early); upper bounds allow for load, because a look
  # fires only at a loop turn and a turn (probe + screen read + 1 s pump) stretches on a busy box.
  in_band "$(sed -n 1p <<<"$offs")" 4 10   || { echo "first re-send not at ~5 s: $offs"; false; }
  in_band "$(sed -n 2p <<<"$offs")" 14 24 || { echo "second re-send not at ~15 s: $offs"; false; }
}

@test "schedule: LR_RECR_SCHEDULE=2,4 re-sends at ~2 s and ~4 s" {
  sched_setup
  export LR_RECR_SCHEDULE=2,4
  run timeout 60 expect -f "$EXP" </dev/null
  offs="$(resend_offsets)"; echo "# re-send offsets: ${offs//$'\n'/ }" >&3
  [ "$(printf '%s\n' "$offs" | grep -c .)" -eq 2 ] || { echo "re-sends: [$offs]"; cat "$LR_GOT"; false; }
  in_band "$(sed -n 1p <<<"$offs")" 1.5 7 || { echo "first re-send not at ~2 s: $offs"; false; }
  in_band "$(sed -n 2p <<<"$offs")" 3.5 12  || { echo "second re-send not at ~4 s: $offs"; false; }
  in_band "$(awk 'NR==1{a=$1} NR==2{print $1-a}' <<<"$offs")" 1 99 || { echo "re-sends back to back: $offs"; false; }
}

@test "schedule: a composer holding a draft that is NOT ours stops the looks but not the poll — a late record is SUBMITTED" {
  # The first look now comes at ~1-5 s instead of 29 s, and an accepted Enter can take 1.6-11 s to
  # reach the transcript (W0). If that look reads someone else's draft and ENDS the poll, the verdict
  # is a false FAILED:submit. It must stop looking and sending, and keep polling to the deadline.
  sched_setup
  export LR_RECR_SCHEDULE=1 LR_SUBMIT_PAINT_S=0 LR_SCREEN_LATER="git status # typed by someone else"
  export LR_PROBE_T0="$BATS_TEST_TMPDIR/probe-t0"
  cat > "$LR_PROBE" <<'SH'
#!/bin/bash
[ -f "$LR_PROBE_T0" ] || date +%s > "$LR_PROBE_T0"
if [ $(( $(date +%s) - $(cat "$LR_PROBE_T0") )) -ge 3 ]; then echo "submitted 2026-09-29T00:00:00.000Z"; else echo none; fi
SH
  run timeout 60 expect -f "$EXP" </dev/null
  [[ "$(cat "$LR_SAY_LOG")" == *"SUBMITTED"* ]] || { cat "$LR_SAY_LOG"; false; }
  [[ "$(cat "$LR_SAY_LOG")" != *"NOT SUBMITTED"* ]] || { cat "$LR_SAY_LOG"; false; }
  [ "$(grep -c ' CR$' "$LR_GOT")" = 0 ] || { echo "an Enter was sent over a draft that is not ours"; cat "$LR_GOT"; false; }
}

# ── A NO-PROMPT ACCOUNT SWAP RUNS NO IN-PANE GATE (design-swap-v3 I8 / F13, 2026-10-04) ───────────
# The in-pane gate runs after the pane's old claude has exited, so a refusal there strands the pane
# at a bare shell. The refusal is made deterministic by demanding an impossible headroom: the real
# gate, on, refuses rc 9 on its first evaluation in a fresh state dir.
refusing_gate() { export CC_ADMIT_GATE=on CC_ADMIT_MIN_HEADROOM_GB=999999 CC_ADMIT_BUDGET=9; }

@test "control: with the gate refusing and no swap mode, the resume exits 9 and never spawns" {
  refusing_gate
  run fire --no-prompt
  [ "$status" -eq 9 ]
  [ ! -s "$STUB_OUT.painted" ]
}

@test "[RED] LR_ADMIT_MODE=swap with --no-prompt skips the refusing gate, says so, and spawns" {
  refusing_gate
  LR_ADMIT_MODE=swap run fire --no-prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"-- gate-exempt: swap"* ]] || false
  [ -s "$STUB_OUT.painted" ]
  grep -q '"gate-exempt"' "$LR_RUN_DIR/events.jsonl"
}

@test "kill switch: LR_ADMIT_SWAP=off ignores the mode, and the refusing gate refuses rc 9" {
  refusing_gate
  LR_ADMIT_MODE=swap LR_ADMIT_SWAP=off run fire --no-prompt
  [ "$status" -eq 9 ]
  [ ! -s "$STUB_OUT.painted" ]
}

@test "swap mode is for a no-prompt resume only: a prompted resume is still gated" {
  refusing_gate
  LR_ADMIT_MODE=swap run fire --prompt "go"
  [ "$status" -eq 9 ]
}

@test "[RED] the swap mode never reaches the resumed session: both spawn lines unset it" {
  run grep -c 'spawn -noecho env .*-u LR_ADMIT_MODE ' "$FIRE"
  [ "$output" = 2 ]
  LR_ADMIT_MODE=swap run fire --no-prompt
  [ "$status" -eq 0 ]
  ! grep -q '^LR_ADMIT_MODE=' "$STUB_OUT.env"
}
