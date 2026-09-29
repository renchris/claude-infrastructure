#!/usr/bin/env bats
# The pane a cc-lr relaunch leaves behind (docs/plans/LR_FIRE_RESUME_PANE_UI.md). Three panes
# relaunched by `cc-lr upgrade` on 2026-09-28 resumed, got their prompt and answered it, and were
# still visibly broken:
#   1. status lines painted over the TUI      — the expect program wrote them to the pane tty
#   2. a false "✗ NOT SUBMITTED"              — the probe's 400 KB tail never held the record
#   3. `ð¬ peer mail`                          — Tcl 8.5 cannot relay a 4-byte UTF-8 character
# Every case below that is marked RED-PROOF fails on the code as it shipped that evening.

setup() {
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  PROBE="$REPO/scripts/limit-recover/lr-submit-probe.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  CFG="$BATS_TEST_TMPDIR/target"
  SID="ddd154a9-e336-42d3-9aca-d18763b23ef2"
  mkdir -p "$CFG/projects/-Users-x-wt"
  TX="$CFG/projects/-Users-x-wt/$SID.jsonl"
  TOK="run:ddd154a9:upgrade:20260929T001507Z"
}

# ── 2. THE PROBE ──────────────────────────────────────────────────────────────────────────────────

# One JSONL record of roughly $3 bytes: type $1, timestamp $2 (or none), padded with a filler field.
rec() { # type ts size [content]
  python3 - "$@" >> "$TX" <<'PY'
import json, sys
kind, ts, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = {"type": kind}
if ts != "-":
    d["timestamp"] = ts
if len(sys.argv) > 4:
    d["message"] = {"role": "user", "content": sys.argv[4]}
d["pad"] = "x" * max(0, size - len(json.dumps(d)))
print(json.dumps(d))
PY
}

# The record sequence of run ddd154a9 (lines 78-110 of its transcript), types, order and sizes as
# measured; only the text is synthetic. The prompt's user record is followed within 0.5 s by a
# 335 KB `instructions` attachment and a 67 KB `prompt_snapshot`, and by a second snapshot at the
# end of the turn: 490 KB after the record, against a 400 KB tail.
replay_ddd154a9() {
  local i
  for i in $(seq 1 40); do rec assistant "2026-09-29T00:0$((i % 10)):00.000Z" 20000; done   # history
  for i in 1 2 3 4 5; do rec attachment 2026-09-29T00:15:32.566Z 1300; done                    # SessionStart
  rec attachment 2026-09-29T00:15:38.995Z 4550
  rec user 2026-09-29T00:16:05.219Z 991 "In-place upgrade: this session was relaunched by cc-lr upgrade. Continue exactly where you left off. $TOK"
  rec attachment 2026-09-29T00:16:05.218Z 1089     # deferred_tools_delta — 1 ms EARLIER, as measured
  rec attachment 2026-09-29T00:16:05.218Z 1152
  rec attachment 2026-09-29T00:16:05.218Z 608
  rec attachment 2026-09-29T00:16:05.737Z 335382   # instructions
  rec attachment 2026-09-29T00:16:05.739Z 536
  rec attachment 2026-09-29T00:16:05.740Z 67329    # prompt_snapshot
  for i in 1 2 3 4 5 6; do rec meta - 150; done    # last-prompt, ai-title, mode … carry no timestamp
  rec assistant 2026-09-29T00:16:09.863Z 2686
  rec assistant 2026-09-29T00:16:10.417Z 1803
  rec attachment 2026-09-29T00:16:10.453Z 67413    # prompt_snapshot
  for i in 1 2 3 4 5 6; do rec meta - 150; done
  rec attachment 2026-09-29T00:16:14.712Z 1372
  rec system 2026-09-29T00:16:14.717Z 1581
}

@test "RED-PROOF probe: the 2.1.284 record shape — the prompt buried under 490 KB of attachments — reads submitted" {
  replay_ddd154a9
  local after
  after="$(awk '/"type": "user"/{f=1} f{s+=length($0)+1} END{print s}' "$TX")"
  [ "$after" -gt 400000 ] || { echo "the replay no longer buries the record past the old 400 KB tail ($after bytes) — it proves nothing"; false; }
  run "$PROBE" "$CFG" "$SID" 2026-09-29T00:15:30 "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "submitted 2026-09-29T00:16:05.219Z" ] || { echo "$output"; false; }
}

@test "probe: the widening stops at t0 — a PREVIOUS run's token, behind a window of newer records, stays none" {
  rec user 2026-09-29T00:01:00.000Z 900 "an earlier attempt $TOK"
  rec attachment 2026-09-29T00:16:05.737Z 335382
  rec attachment 2026-09-29T00:16:05.740Z 200000
  run "$PROBE" "$CFG" "$SID" 2026-09-29T00:15:30 "$TOK"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ] || { echo "$output"; false; }
}

# ── 1 + 3. THE EXPECT PROGRAM, RUN FOR REAL ───────────────────────────────────────────────────────
# The program is extracted from the subject and run against a stub binary, exactly as
# tests/lr-fire-resume-submit.bats does. Everything expect relays from the stub lands in $output,
# which is what the pane would have painted.

exp_setup() {
  command -v expect >/dev/null || skip "expect(1) not installed"
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed" >&2; return 1; }
  STUB="$BATS_TEST_TMPDIR/stub"
  # The session paints the peer-mail digest line exactly as hooks/mailbox-drain.sh builds it, then
  # records every line it is sent.
  cat > "$STUB" <<'SH'
#!/bin/bash
printf 'SessionStart:resume says: \xf0\x9f\x93\xac peer mail \xe2\x97\x80 1 peer message(s)\r\n'
[ -n "${LR_TEST_READY:-}" ] && printf '%s\r\n' "$LR_TEST_READY"
: > "$LR_TEST_GOT"
while IFS= read -r line; do printf 'GOT:[%s]\n' "$line" >> "$LR_TEST_GOT"; done
exit 0
SH
  chmod +x "$STUB"
  export LR_TEST_GOT="$BATS_TEST_TMPDIR/got"
  NOTIFY="$BATS_TEST_TMPDIR/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/notified" > "$NOTIFY"
  chmod +x "$NOTIFY"
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_CFG="$CFG" LR_BIN="$STUB" LR_MODEL=m LR_EFFORT=high LR_SID="$SID" LR_ASIS=1 LR_WRAP=""
  export LR_PROMPT="continue $TOK"
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" \
         LR_RE_TRUST="$never" LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" \
         LR_RE_OVERAGE="$never" LR_RE_READY="$never"
  export LR_QUIET_S=1 LR_SUBMIT_POLL_S=2 RCY_ENGAGE_TIMEOUT=3 LR_SUBMIT_PAINT_S=0
  LR_SCREEN_SH="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"
  LR_NOTE_SH="$(sed -n "/<<'LRNOTESH'/,/^LRNOTESH\$/p" "$FIRE" | sed '1d;$d')"
  [ -n "$LR_SCREEN_SH" ] && [ -n "$LR_NOTE_SH" ] || { echo "helper-program extraction failed" >&2; return 1; }
  export LR_SCREEN_SH LR_NOTE_SH
  export LR_PROBE="$PROBE" LR_SUBMIT_TOKEN="$TOK"
  export LR_RUN_DIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$LR_RUN_DIR"
  export LR_LIB_PATH="$REPO/scripts/limit-recover/lr-lib.sh"
  export LR_SAY_LOG="$LR_RUN_DIR/lr-fire-resume.log" LR_NOTIFY="$NOTIFY"
}
# A parked menu inside a real composer box, so the screen oracle reads MENU and nothing is typed.
screen_menu() {
  local b='────────────────────────────────'
  IT2="$BATS_TEST_TMPDIR/it2"
  printf '%s\n' "  Resume a session" "$b" "  ❯ 1. Resume from summary" "    2. Resume full session as-is" "$b" > "$BATS_TEST_TMPDIR/menu.txt"
  printf '#!/bin/sh\ncat "%s"\n' "$BATS_TEST_TMPDIR/menu.txt" > "$IT2"; chmod +x "$IT2"
  export LR_IT2="$IT2" LR_PANE=1
}
run_exp() { run timeout 120 expect -f "$EXP" </dev/null; }

@test "RED-PROOF tty: a verdict is written to the run log and the inbox, never painted on the pane" {
  exp_setup
  screen_menu
  run_exp
  # the stub's own paint still reaches the pane — the relay is intact
  [[ "$output" == *"peer mail"* ]] || { echo "the session output was not relayed: $output"; false; }
  # …and nothing of ours is on it
  [[ "$output" != *"lr-fire-resume"* && "$output" != *"READY NEVER SEEN"* ]] \
    || { echo "a status line was painted onto the pane:"; printf '%s\n' "$output"; false; }
  grep -q "READY NEVER SEEN.*screen reads MENU" "$LR_SAY_LOG" || { echo "log: $(cat "$LR_SAY_LOG" 2>&1)"; false; }
  # the inbox write runs in the background — give it a moment to land
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/notified" ] && break; sleep 0.3; done
  grep -q -- "--from lr-fire-resume $SID lr-fire-resume: ✗ READY NEVER SEEN" "$BATS_TEST_TMPDIR/notified" \
    || { echo "notified: $(cat "$BATS_TEST_TMPDIR/notified" 2>&1)"; false; }
}

@test "RED-PROOF tty: the success path is silent on the pane too — SUBMITTED goes to the log" {
  exp_setup
  export LR_IT2="" LR_TEST_READY="READY-HERE" LR_RE_READY="READY-HERE"
  printf '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","message":{"role":"user","content":"continue %s"}}\n' "$TOK" > "$TX"
  run_exp
  grep -qF "GOT:[continue $TOK]" "$LR_TEST_GOT" || { echo "the prompt was not typed: $(cat "$LR_TEST_GOT" 2>&1)"; false; }
  [[ "$output" != *"SUBMITTED"* && "$output" != *"lr-fire-resume"* ]] \
    || { echo "a status line was painted onto the pane:"; printf '%s\n' "$output"; false; }
  grep -q "SUBMITTED — the prompt is in the transcript at 2099-01-01" "$LR_SAY_LOG" || { echo "log: $(cat "$LR_SAY_LOG" 2>&1)"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/notified" ] || { echo "a success paged the inbox: $(cat "$BATS_TEST_TMPDIR/notified")"; false; }
}

@test "tty: the expect program holds no send_user and no puts that could reach the pane" {
  local body
  body="$(sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | grep -v '^[[:space:]]*#')"
  [ -n "$body" ] || { echo "extraction failed"; false; }
  ! grep -n 'send_user' <<<"$body" || { echo "send_user writes the pane tty"; false; }
  # the only puts allowed is into the status log handle
  ! grep -nE '(^|[[:space:];{])puts ' <<<"$body" | grep -v 'puts \$fh ' || { echo "a puts that is not the log handle"; false; }
}

@test "RED-PROOF mojibake: a 4-byte emoji the session paints reaches the pane byte-for-byte" {
  exp_setup
  screen_menu
  run_exp
  local want=$'\xf0\x9f\x93\xac peer mail \xe2\x97\x80'
  [[ "$output" == *"$want"* ]] || { echo "relayed bytes:"; printf '%s' "$output" | grep -a 'peer mail' | od -An -tx1 | head -4; false; }
  [[ "$output" != *$'\xc3\xb0\xc2\x9f'* ]] || { echo "the emoji was decoded as Latin-1 (ð…)"; false; }
}

@test "mojibake: under the byte relay, a non-ASCII READY pattern still matches and a non-ASCII prompt is typed exactly" {
  # The fix moves the stream to bytes, so every pattern and every typed string must move with it.
  # LR_IT2 is empty, so the screen oracle reads UNKNOWN and the quiet arm types NOTHING: the prompt
  # can only arrive through the READY arm, i.e. only if the ❯ pattern matched the byte stream.
  exp_setup
  export LR_IT2="" LR_TEST_READY="❯ résumé ready" LR_RE_READY="❯ résumé ready"
  export LR_PROMPT="continue ◀ résumé $TOK"
  : > "$TX"
  run_exp
  grep -qF "GOT:[continue ◀ résumé $TOK]" "$LR_TEST_GOT" \
    || { echo "typed:"; od -c "$LR_TEST_GOT" | head; false; }
}
