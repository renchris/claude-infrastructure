#!/usr/bin/env bats
# lr-fire-resume.sh — gap 1 (docs/research/lr-sustained-load-2026-10-20/gap-1-post-relaunch-prompt-delivery.md):
# the owed prompt rides the spawn argv, nothing is typed, and a slow boot no longer ends READY-NOT-SEEN.
#
# WHY THE WHOLE SCRIPT RUNS HERE (as in lr-fire-resume-noprompt.bats). The decision (bash), the spawn
# line and the no-typing branches (the expect program) live in different halves of the file; only an
# end-to-end run against a stub TUI that records its argv AND every byte it reads sees all of them.
# The stub plays the CLI's own submit: once it has painted READY it appends a user record carrying the
# prompt to the transcript, from argv (STUB_SUBMIT=argv) or from what was typed (STUB_SUBMIT=typed),
# so the run's verdict is the real lr-submit-probe.sh reading a real transcript.
#
# FIRE may point at another copy of the script (the red-proof run against the pre-change file).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="${FIRE:-$REPO/scripts/limit-recover/lr-fire-resume.sh}"
  [ -f "$FIRE" ] || skip "lr-fire-resume.sh not found"
  command -v expect >/dev/null || skip "expect(1) not installed"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_ADMIT_GATE=off LR_PRESEED_DONE=bats LR_QUIET_S=2 LR_SUBMIT_PAINT_S=0
  export LR_SUBMIT_POLL_S=5 RCY_ENGAGE_TIMEOUT=8
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state" LR_RUN_DIR="$BATS_TEST_TMPDIR/run"
  export LR_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry" LR_CFG_DIRS="$BATS_TEST_TMPDIR/cfgs"
  unset LR_RUN LR_RECORD_ID LR_ATTEMPT LR_SUBMIT_TOKEN LR_ADMIT_TOKEN CC_PANE_ID ITERM_SESSION_ID \
        LR_LAUNCH_LOCK LR_LAUNCH_GUARD LR_RECR_SCHEDULE LR_PROMPT_ARGV LR_READY_WAIT_S
  ACCT="$BATS_TEST_TMPDIR/acct"; WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$ACCT/projects/p" "$WT"
  SID="a7c0ffee-argv-$$-$RANDOM"
  export STUB_TX="$ACCT/projects/p/$SID.jsonl"; : > "$STUB_TX"
  # THE REAL CLAUDE MUST NEVER RUN (cc-claude-bin honours CC_CLAUDE_BIN first).
  TRIP="$BATS_TEST_TMPDIR/tripwire"
  printf '#!/bin/bash\necho TRIPPED >> "%s.hit"\nexit 97\n' "$TRIP" > "$TRIP"; chmod +x "$TRIP"
  export CC_CLAUDE_BIN="$TRIP"
  STUB="$BATS_TEST_TMPDIR/claude-stub"; export STUB_OUT="$BATS_TEST_TMPDIR/out"
  cat > "$STUB" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_OUT.argv"
: > "$STUB_OUT.bytes"
stty raw -echo 2>/dev/null
printf 'booting\r\n'
# A SLOW BOOT: nothing READY-shaped is painted for STUB_BOOT_S seconds, as a resume under load.
sleep "${STUB_BOOT_S:-0}"
printf ' ? for shortcuts\r\n'
echo READY-PAINTED > "$STUB_OUT.painted"
submit() { /usr/bin/python3 -c 'import json,sys,datetime
t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
print(json.dumps({"type": "user", "timestamp": t, "message": {"role": "user", "content": sys.argv[1]}}))' "$1" >> "$STUB_TX"; }
if [ "${STUB_SUBMIT:-}" = argv ]; then submit "${!#}"; fi
# Record until the first CR/LF or STUB_READ_S seconds: alive past any injection, so an empty file is
# a measurement of the window, never a stub that had already exited.
/usr/bin/perl -e '$SIG{ALRM} = sub { exit 0 }; alarm($ENV{STUB_READ_S} || 10);
  open(my $f, ">>", "$ENV{STUB_OUT}.bytes") or exit 1; select((select($f), $| = 1)[0]);
  while (sysread(STDIN, my $b, 1)) { print $f $b; exit 0 if $b eq "\r" || $b eq "\n" }'
if [ "${STUB_SUBMIT:-}" = typed ] && [ -s "$STUB_OUT.bytes" ]; then submit "$(cat "$STUB_OUT.bytes")"; fi
sleep 2
SH
  chmod +x "$STUB"
  export LR_CLAUDE_BIN="$STUB"
}

fire() { bash "$FIRE" "$ACCT" "$WT" "$SID" --model m --effort high "$@" </dev/null; }
events() { cat "$LR_RUN_DIR/events.jsonl" 2>/dev/null; }
noted() { grep -q "\"state\":\"$1\"" "$LR_RUN_DIR/events.jsonl" 2>/dev/null; }

@test "the prompt is the last spawn argument, and NOTHING is typed" {
  STUB_SUBMIT=argv run fire --prompt "[limit-recover] continue the task"
  [ ! -e "$TRIP.hit" ] || { echo "the real-binary tripwire ran"; false; }
  [ -s "$STUB_OUT.painted" ] || { echo "the stub never painted READY — the case proves nothing: $output"; false; }
  last="$(tail -n 1 "$STUB_OUT.argv")"
  [[ "$last" == "[limit-recover] continue the task (submit token: run:"* ]] \
    || { echo "last argv element: [$last]"; cat "$STUB_OUT.argv"; false; }
  grep -qx -- "--resume" "$STUB_OUT.argv" || { cat "$STUB_OUT.argv"; false; }
  [ -f "$STUB_OUT.bytes" ] || { echo "the byte recorder wrote no file"; false; }
  [ ! -s "$STUB_OUT.bytes" ] || { echo "bytes typed:"; od -c "$STUB_OUT.bytes" | head; false; }
  noted prompt-argv || { events; false; }
  noted submitted || { echo "no submitted verdict"; events; false; }
  ! noted READY-NOT-SEEN || { events; false; }
}

@test "prompt-argv is noted AFTER relaunch-typed (the reconciler reads only what follows a start)" {
  STUB_SUBMIT=argv run fire --prompt "[limit-recover] go"
  run grep -o '"state":"\(relaunch-typed\|prompt-argv\)"' "$LR_RUN_DIR/events.jsonl"
  [ "${lines[0]}" = '"state":"relaunch-typed"' ] && [ "${lines[1]}" = '"state":"prompt-argv"' ] \
    || { echo "$output"; false; }
}

@test "a slash-head prompt is typed, not passed on argv" {
  STUB_SUBMIT=typed run fire --prompt "/goal finish it"
  [ "$(tail -n 1 "$STUB_OUT.argv")" = "$SID" ] || { echo "argv:"; cat "$STUB_OUT.argv"; false; }
  grep -q 'goal finish it' "$STUB_OUT.bytes" || { od -c "$STUB_OUT.bytes" | head; false; }
  ! noted prompt-argv || { events; false; }
}

@test "--no-prompt passes no positional argument" {
  run fire --no-prompt
  [ "$(tail -n 1 "$STUB_OUT.argv")" = "$SID" ] || { cat "$STUB_OUT.argv"; false; }
}

@test "slow boot, argv: the TUI paints after 30 s and the prompt still lands, with no READY-NOT-SEEN" {
  STUB_BOOT_S=30 STUB_READ_S=45 STUB_SUBMIT=argv run fire --prompt "[limit-recover] slow argv"
  [ -s "$STUB_OUT.painted" ] || { echo "the stub never painted: $output"; false; }
  ! noted READY-NOT-SEEN || { events; false; }
  noted READY-ARGV || { events; false; }
  noted submitted || { events; false; }
  [ ! -s "$STUB_OUT.bytes" ] || { echo "bytes typed:"; od -c "$STUB_OUT.bytes" | head; false; }
}

@test "slow boot, typed (LR_PROMPT_ARGV=off): the look arm re-arms until the TUI paints at 30 s, then types" {
  LR_PROMPT_ARGV=off STUB_BOOT_S=30 STUB_READ_S=45 STUB_SUBMIT=typed run fire --prompt "[limit-recover] slow typed"
  [ -s "$STUB_OUT.painted" ] || { echo "the stub never painted: $output"; false; }
  ! noted READY-NOT-SEEN || { events; false; }
  grep -q 'slow typed' "$STUB_OUT.bytes" || { od -c "$STUB_OUT.bytes" | head; events; false; }
  noted submitted || { events; false; }
  [ "$(tail -n 1 "$STUB_OUT.argv")" = "$SID" ] || { cat "$STUB_OUT.argv"; false; }
}

@test "typed: the wait is bounded — past LR_READY_WAIT_S it ends READY-NOT-SEEN with a capture, typing nothing" {
  LR_PROMPT_ARGV=off LR_READY_WAIT_S=5 STUB_BOOT_S=20 STUB_READ_S=25 run fire --prompt "[limit-recover] bounded"
  noted READY-NOT-SEEN || { events; false; }
  grep -q '"state":"READY-NOT-SEEN".*after spawn (bound 5s)' "$LR_RUN_DIR/events.jsonl" || { events; false; }
  [ ! -s "$STUB_OUT.bytes" ] || { od -c "$STUB_OUT.bytes" | head; false; }
}
