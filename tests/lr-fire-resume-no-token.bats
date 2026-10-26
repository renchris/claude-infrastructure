#!/usr/bin/env bats
# lr-fire-resume.sh — a run the driver handed NO submit token still proves (or disproves) delivery.
#
# THE INCIDENT (lr-wake 2026-10-18, pane 430, e §2). A by-hand rescue run had no LR_SUBMIT_TOKEN, so
# the submit poll returned `skip` on its first turn and broke out before its first look at the
# composer: no second Enter, no state note (no run dir), and one log line — "submission not
# verified". The prompt never reached the transcript and the pane sat with it for 8 h.
#
# The cure under test: the run mints its own token (run:<sid8>:<UTC>:<hex>, the form composer-intent
# calls rail-token), so the transcript probe has something to find; the look/re-CR loop runs; the run
# ends on a non-green verdict told to the session inbox; and the notes land in a fallback run dir.
#
# The WHOLE script runs, stdin at EOF, so `interact` returns and the pane-survival shell is skipped.
# The TUI is a stub on a real pty, the pane reader a stub it2 at the path the script resolves, and
# the probe is the real lr-submit-probe.sh over an empty transcript, so it answers `none`.

load helpers/pty-reap
teardown() { pty_reap; } # no stub spawned on a pty outlives its test (tests/helpers/pty-reap.bash)

setup() {
  command -v expect >/dev/null || skip "expect(1) not installed"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity ratchet (handoff-fire's gate; not this one)
  # The capacity gate ADMITS on its own measured terms: quiet load and headroom through the library's
  # override seams, the ambient census terms deselected (capacity-admit.bats does the same).
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/page"; printf '#!/bin/bash\nexit 0\n' > "$CC_ADMIT_NOTIFY_BIN"; chmod +x "$CC_ADMIT_NOTIFY_BIN"
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_ADMIT_RESERVE_TERM=off CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_SEGMENT_TERM=off
  export LR_PRESEED_DONE=test CC_RESUME_TOMBSTONE_LIB="" CC_RESUME_TEAMMATE_GUARD=checked
  unset LR_RUN LR_RUN_DIR LR_ADMIT_TOKEN LR_SUBMIT_TOKEN
  # seconds, not minutes: every bound the expect program reads is a seam for this reason
  export LR_QUIET_S=1 LR_SUBMIT_POLL_S=2 RCY_ENGAGE_TIMEOUT=3 LR_RECR_SCHEDULE=1,2 LR_SUBMIT_RECR_MAX=1
  # the TYPED path is the subject (re-Enter at the first look), so the argv delivery is switched off
  export LR_PROMPT_ARGV=off
  SID="aaaa1111-0000-4000-8000-000000000001"
  CFG="$BATS_TEST_TMPDIR/target"; mkdir -p "$CFG/projects/-x"; : > "$CFG/projects/-x/$SID.jsonl"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  export LR_TEST_GOT="$BATS_TEST_TMPDIR/got"
  export LR_CLAUDE_BIN="$BATS_TEST_TMPDIR/claude"
  cat > "$LR_CLAUDE_BIN" <<'SH'
#!/bin/bash
: > "$LR_TEST_GOT"
while IFS= read -r line; do printf 'GOT:[%s]\n' "$line" >> "$LR_TEST_GOT"; done
SH
  chmod +x "$LR_CLAUDE_BIN"
  # The pane reader: an EMPTY box on the first read (so the quiet arm types), then our prompt sitting
  # in the box on every read after it — the stranded shape. The head needle is the prompt first 40
  # ink characters, which with the token appended is deterministic up to the sid8.
  export CC_PANE_ID=77 LR_STUB_N="$BATS_TEST_TMPDIR/screen-n"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/bin/bash
n=0; [ -f "$LR_STUB_N" ] && n="$(cat "$LR_STUB_N")"; n=$((n + 1)); printf '%s' "$n" > "$LR_STUB_N"
b='────────────────────────────────'
if [ "$n" -le 1 ]; then printf '%s\n' "  chrome" "$b" " ❯ " "$b" " ? for shortcuts"
else printf '%s\n' "  chrome" "$b" " ❯ continue the work (submit token: run:aaaa1111:" "$b" " ? for shortcuts"; fi
SH
  chmod +x "$HOME/.claude/bin/it2"
  export LR_NOTIFY_BIN="$BATS_TEST_TMPDIR/inbox"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/inbox.txt"\n' "$BATS_TEST_TMPDIR" > "$LR_NOTIFY_BIN"; chmod +x "$LR_NOTIFY_BIN"
}

# lr_tell mails the inbox from a BACKGROUND exec, so the recorder may land a moment after expect exits.
inbox_has() { # $1 = phrase → 0 once the inbox recorder holds it (bounded at 30 s)
  local n=0
  while [ "$n" -lt 60 ]; do grep -q "$1" "$BATS_TEST_TMPDIR/inbox.txt" 2>/dev/null && return 0; sleep 0.5; n=$((n + 1)); done
  return 1
}

@test "RED-PROOF a run with no token mints one, re-Enters at the first look, and ends non-green" {
  # A hang bound only: the program bounds itself, and at load 60/core a clean run outlasted 600 s.
  run timeout 1800 /bin/bash "$FIRE" "$CFG" "$WT" "$SID" --model m --effort high --prompt "continue the work" </dev/null
  echo "# rc $status" >&3
  # 1 — a token was minted into the typed text, in the rail-token form
  grep -aqE 'GOT:\[.*continue the work \(submit token: run:aaaa1111:[0-9]{8}T[0-9]{6}Z:[0-9a-f]{8}\)' "$LR_TEST_GOT" \
    || { echo "no minted token in what was typed:"; cat -v "$LR_TEST_GOT"; echo "$output" | tail -20; false; }
  # 2 — the look/re-CR loop ran: one more Enter, an empty line after the prompt
  [ "$(grep -c '^GOT:\[\]$' "$LR_TEST_GOT")" -ge 1 ] || { echo "no re-Enter was sent:"; cat -v "$LR_TEST_GOT"; false; }
  # 3 — the verdict is non-green and reached the session inbox, not just a log
  inbox_has 'NOT SUBMITTED' \
    || { echo "no non-green verdict in the inbox:"; cat "$BATS_TEST_TMPDIR/inbox.txt" 2>&1; false; }
  # 4 — with no run dir the notes still landed, in the fallback dir
  local ev; ev="$(find "$LR_STATE_DIR/fire-resume/$SID" -name events.jsonl 2>/dev/null | head -1)"
  [ -n "$ev" ] || { echo "no fallback run dir holds the notes"; find "$LR_STATE_DIR" | head -20; false; }
  jq -r '.state' "$ev" | grep -qx 'SUBMIT-RECR' || { echo "states: $(jq -r .state "$ev" | tr '\n' ' ')"; false; }
  jq -r '.state' "$ev" | grep -qx 'FAILED:submit' || { echo "states: $(jq -r .state "$ev" | tr '\n' ' ')"; false; }
}

@test "with no probe reachable the composer is still looked at, and the run ends UNSUBMITTED" {
  # skip used to break before the look; now it looks, re-Enters on our draft, and says so to the inbox
  local exp="$BATS_TEST_TMPDIR/resume.exp"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$exp"
  [ -s "$exp" ] || { echo "expect body extraction failed"; false; }
  LR_SCREEN_SH="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"; export LR_SCREEN_SH
  LR_NOTE_SH="$(sed -n "/<<'LRNOTESH'/,/^LRNOTESH\$/p" "$FIRE" | sed '1d;$d')"; export LR_NOTE_SH
  LR_CAPTURE_SH="$(sed -n "/<<'LRCAPTURESH'/,/^LRCAPTURESH\$/p" "$FIRE" | sed '1d;$d')"; export LR_CAPTURE_SH
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" LR_RE_TRUST="$never" \
         LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" LR_RE_OVERAGE="$never" LR_RE_READY="$never"
  export LR_CFG="$CFG" LR_BIN="$LR_CLAUDE_BIN" LR_MODEL=m LR_EFFORT=high LR_SID="$SID" LR_ASIS=1 LR_WRAP=""
  export LR_PROMPT="continue the work (submit token: run:aaaa1111:20261018T100712Z:2bd71e0a)"
  export LR_SUBMIT_TOKEN="run:aaaa1111:20261018T100712Z:2bd71e0a" LR_PROBE=""
  export LR_IT2="$HOME/.claude/bin/it2" LR_PANE=77 LR_SCREEN_WANT="continuethework(submittoken:run:aaaa1111"
  export LR_NOTE_DIR="$BATS_TEST_TMPDIR/note" LR_LIB_PATH="$REPO/scripts/limit-recover/lr-lib.sh"
  export LR_SAY_LOG="$BATS_TEST_TMPDIR/say.log" LR_NOTIFY="$LR_NOTIFY_BIN"
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  mkdir -p "$LR_NOTE_DIR"
  run pty_timeout 1800 expect -f "$exp" </dev/null
  [ "$(grep -c '^GOT:\[\]$' "$LR_TEST_GOT")" -ge 1 ] || { echo "no re-Enter without a probe:"; cat -v "$LR_TEST_GOT"; cat "$LR_SAY_LOG"; false; }
  inbox_has 'UNSUBMITTED' \
    || { echo "no UNSUBMITTED verdict in the inbox:"; cat "$BATS_TEST_TMPDIR/inbox.txt" 2>&1; cat "$LR_SAY_LOG"; false; }
  jq -r '.state' "$LR_NOTE_DIR/events.jsonl" | grep -qx UNSUBMITTED || { echo "states: $(jq -r .state "$LR_NOTE_DIR/events.jsonl" 2>&1 | tr '\n' ' ')"; false; }
  # our own text left in the box is filed as this pane residue, so the next rail clears it
  [ -f "$CC_COMPOSER_RESIDUE_DIR/77" ] || { echo "no residue filed for pane 77"; false; }
}
