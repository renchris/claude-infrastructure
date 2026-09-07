#!/usr/bin/env bats
# file-changed — the FileChanged observer (HOOK_SURFACE_100P § 3 row 29, W3-B).
#
# Harness laws, inherited from tests/bash-audit-attrib.bats and NOT relaxed:
#   L1 every fixture payload is the LITERAL shape 2.1.220 emits. These are not invented — they are
#      the captured rows from the W1 probe (/tmp/hs/log/fs2-NAME.tsv, fs2-STAR.tsv), transcribed
#      here so the suite does not depend on a /tmp directory that a reboot wipes.
#   L2 assertions key on failure-DISTINCT strings, so a handler that logged the wrong field or
#      swallowed the row goes RED rather than passing on a coincidence.
#   L3 every assertion is `[ ]` / `grep -q` — never `[[ ]]` or `(( ))`, which bash 3.2 exempts from
#      errexit in any non-last position and which the block-position analyzer therefore calls DEAD
#      (tests/bats-assert-liveness.bats).
#   L4 both the firing and the NOT-firing case are fixtured.
#
# 🚨 THE ARM THAT EARNS THIS SUITE IS THE NEGATIVE ONE. A happy-path suite over this handler is
# vacuous against the bug that actually makes the event worthless: the matcher is documented by the
# binary as "filenames to watch in the current directory", so an ABSOLUTE path in the matcher never
# matches, never errors and never logs — measured as 0 rows against `*`'s 3 in the same run. That
# defect lives in the REGISTRATION, so it is unreachable from any runtime behaviour of the script;
# `--check-matcher` is where it becomes catchable, and "the absolute-path matcher is rejected" is
# the assertion this file exists for. Delete that arm from hooks/file-changed.sh and this suite
# must go red — that is the red-proof, and it is exercised by `control:` below.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/file-changed.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  LOG="$HOME/.claude/logs/file-changed.log"
}

# The literal 2.1.220 FileChanged payload. `file_path` arrives ABSOLUTE and already resolved even
# though the matcher that armed it was the bare basename `probe.txt` — that asymmetry is the whole
# trap, and fixturing it is what keeps a reader from "fixing" the matcher to match the payload.
fc_payload() { # <file_path> <event> <session_id>
  jq -nc --arg f "$1" --arg e "$2" --arg s "$3" \
    '{session_id:$s,transcript_path:"/tmp/t.jsonl",cwd:"/private/tmp/hs/fc",
      prompt_id:"6d1eb1af-8b85-4176-85f4-9ff5c31bc880",
      hook_event_name:"FileChanged",file_path:$f,event:$e}'
}

# `run` must NEVER appear on the right of a pipe: bats runs the pipeline's last element in a
# SUBSHELL, so $status and $output never reach the test body and every assertion on them reads an
# empty string. That is a vacuous pass wearing a green tick, and it is precisely the shape
# tests/anti-vacuity-contract.bats exists to prevent — caught here on the first run of this suite.
# Payloads therefore go to a file and reach the hook by REDIRECTION, which keeps `run` in the
# test's own shell.
feed() { # <file_path> <event> <session_id>  → writes $PAYLOAD
  PAYLOAD="$BATS_TEST_TMPDIR/payload.json"
  fc_payload "$1" "$2" "$3" > "$PAYLOAD"
}

# ── the negative arm: the matcher shape measured never to fire ────────────────────────────────

@test "an absolute-path matcher is REJECTED — it is the measured silent no-op" {
  run "$HOOK" --check-matcher /private/tmp/hs/fc/abs.txt
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "absolute path"
  echo "$output" | grep -q "0 changes"
}

@test "an absolute path is rejected even when hidden inside an alternation" {
  # `.env|/etc/hosts` — one live element and one dead one. A checker that only looked at the first
  # character of the whole matcher string would pass this, and the dead half would stay silent.
  run "$HOOK" --check-matcher '.env|/etc/hosts'
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "/etc/hosts"
}

@test "a relative path with a separator is rejected, and labelled as DERIVED not measured" {
  run "$HOOK" --check-matcher 'sub/probe.txt'
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "path separator"
  # Provenance must survive in the message: only the absolute case was measured. A future reader
  # who inherits this rejection as a measurement would be over-claiming.
  echo "$output" | grep -q "not measured"
}

@test "an empty matcher is rejected — it watches nothing and can never fire" {
  run "$HOOK" --check-matcher ""
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "never fire"
}

@test "a rejection names the SUPPORTED route to a path outside cwd" {
  # Without this, the check is a refusal with no remedy, and the next person just deletes it.
  run "$HOOK" --check-matcher /private/tmp/hs/fc/abs.txt
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "watchPaths"
}

# ── the positive arm: the matcher shapes measured to fire, 1 row and 3 rows ────────────────────

@test "the bare basename matcher measured at 1 row is ACCEPTED" {
  run "$HOOK" --check-matcher probe.txt
  [ "$status" -eq 0 ]
}

@test "the star matcher measured at 3 rows is ACCEPTED" {
  run "$HOOK" --check-matcher '*'
  [ "$status" -eq 0 ]
}

@test "the binary's own documented example .envrc|.env is ACCEPTED" {
  # If the checker rejected the example the binary itself gives, the checker is wrong, not the doc.
  run "$HOOK" --check-matcher '.envrc|.env'
  [ "$status" -eq 0 ]
}

# ── the handler: it records what the payload carries ───────────────────────────────────────────

@test "a real FileChanged payload is recorded with its file, event and session" {
  feed /private/tmp/hs/fc/probe.txt change 5f0ad321-3889-4965-a814-9977ad10b776
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  grep -q "/private/tmp/hs/fc/probe.txt" "$LOG"
  grep -q "5f0ad321-3889-4965-a814-9977ad10b776" "$LOG"
  grep -q "change" "$LOG"
}

@test "add and unlink are recorded distinctly — the handler must not assume 'change'" {
  # Only `change` was observed in the W1 probe; the binary documents all three. A handler that
  # hardcoded the observed value would silently mislabel the two it never saw.
  feed /tmp/a.txt add sid-a
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  feed /tmp/b.txt unlink sid-b
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -q "add" "$LOG"
  grep -q "unlink" "$LOG"
  # and they are on their own rows, not conflated
  [ "$(grep -c "unlink" "$LOG")" -eq 1 ]
}

@test "each invocation appends exactly one row" {
  feed /tmp/one.txt change sid-1
  run "$HOOK" < "$PAYLOAD"
  feed /tmp/two.txt change sid-2
  run "$HOOK" < "$PAYLOAD"
  [ "$(wc -l < "$LOG")" -eq 2 ]
}

# ── fail-open: an observer may never break its host ────────────────────────────────────────────

@test "malformed JSON on stdin exits 0 and writes no row" {
  echo 'not json {{{' > "$BATS_TEST_TMPDIR/bad.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/bad.json"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "empty stdin exits 0" {
  printf '' > "$BATS_TEST_TMPDIR/empty.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/empty.json"
  [ "$status" -eq 0 ]
}

@test "no stdin at all exits 0" {
  run "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
}

@test "an unrecognised argument falls through to the observer and still exits 0" {
  # The harness passes no arguments, but a fail-open script must not become fail-closed because
  # someone added a flag. Only the exact literal --check-matcher may take the checking path.
  feed /tmp/c.txt change sid-c
  run "$HOOK" --some-future-flag < "$PAYLOAD"
  [ "$status" -eq 0 ]
}

@test "a payload with no file_path writes no row — an unattributable row is worse than none" {
  echo '{"hook_event_name":"FileChanged","event":"change","session_id":"s"}' > "$BATS_TEST_TMPDIR/nofp.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/nofp.json"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "an unwritable log directory does not fail the hook" {
  mkdir -p "$HOME/.claude"
  : > "$HOME/.claude/logs"        # a FILE where the log dir must go — mkdir -p will fail
  feed /tmp/d.txt change sid-d
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
}

# ── the dynamic watch list: the only supported route to a path outside cwd ─────────────────────

@test "no watchlist file means no stdout — the default posture is silent observation" {
  feed /tmp/e.txt change sid-e
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a watchlist emits hookSpecificOutput.watchPaths with the absolute paths" {
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch"
  printf '# a comment\n/Users/x/mailbox.md\n/Users/x/other.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed /tmp/f.txt change sid-f
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "watchPaths"
  echo "$output" | grep -q "/Users/x/mailbox.md"
  # the comment line is not smuggled into the array
  echo "$output" | grep -qv "a comment"
  # and the output is a single well-formed JSON object the harness can parse
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 2' > /dev/null
}

@test "a RELATIVE entry in the watchlist is dropped — it would re-create the cwd dependency" {
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch2"
  printf 'relative.md\n/Users/x/absolute.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed /tmp/g.txt change sid-g
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 1' > /dev/null
  echo "$output" | grep -q "/Users/x/absolute.md"
}

@test "a watchlist with no usable entry prints nothing rather than an empty array" {
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch3"
  printf '# only comments\nrelative.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed /tmp/h.txt change sid-h
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
