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
# must go red — that is the red-proof.
#
# 🚨 AND THE GUARD MUST FAIL IN BOTH DIRECTIONS, WHICH IT ORIGINALLY DID NOT. The first version
# rejected every absolute matcher outright. § 3e — landed by a sibling wave while this one was in
# flight — shows ARMING and DISPATCH are separate mechanisms and that the correct wiring REQUIRES an
# absolute matcher as its arming half. So the too-strict direction was live: the guard would have
# refused the plan's own prescription. Both directions are now pinned below (arm accepts absolute /
# rejects relative; dispatch rejects absolute / accepts `*` / notices a bare basename).

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

@test "an absolute-path matcher never DISPATCHES — the measured silent no-op" {
  run "$HOOK" --check-matcher /private/tmp/hs/fc/abs.txt
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "absolute path"
  echo "$output" | grep -q "never DISPATCH"
}

@test "...but that rejection names the ARMING role, so it cannot block the § 3e pair" {
  # THE ARM THAT KEEPS THIS GUARD HONEST. § 3e (landed by a sibling wave, corroborated here at
  # 220:430421 where the dispatch query is built from basename(n.file_path)) shows arming and
  # dispatch are DIFFERENT mechanisms: an absolute matcher ARMS durably and survives a cd, and
  # only the dispatch half needs a `*`. A guard that rejected absolutes unconditionally would
  # refuse the very registration the plan prescribes — a proxy failing in the other direction.
  run "$HOOK" --check-matcher /private/tmp/hs/fc/abs.txt
  echo "$output" | grep -q "ARMING"
  echo "$output" | grep -q "CwdChanged"
}

@test "an absolute matcher is ACCEPTED in the arming role" {
  run "$HOOK" --check-matcher /private/tmp/hs/fc/dyn.txt --role arm
  [ "$status" -eq 0 ]
}

@test "a RELATIVE matcher is REJECTED in the arming role — a cd re-bases it" {
  # Measured in § 3e: after a cd, the probe3.txt matcher fired for a DIFFERENT file of that name
  # while the originally-armed path produced zero rows. A relative arm is worse than no arm,
  # because it keeps firing and looks healthy.
  run "$HOOK" --check-matcher probe.txt --role arm
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "re-bases"
}

@test "a bare basename DISPATCHES but carries the cd re-target notice" {
  # It must not be silently blessed: this is the shape that keeps firing for the wrong file.
  run "$HOOK" --check-matcher probe.txt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NOTICE"
  echo "$output" | grep -q "RE-BASES"
}

@test "an absolute path is rejected even when hidden inside an alternation" {
  # `.env|/etc/hosts` — one live element and one dead one. A checker that only looked at the first
  # character of the whole matcher string would pass this, and the dead half would stay silent.
  run "$HOOK" --check-matcher '.env|/etc/hosts'
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "/etc/hosts"
}

@test "a relative path with a separator is dead in BOTH roles" {
  # It can neither arm durably (not absolute) nor match a basename (has a separator).
  run "$HOOK" --check-matcher 'sub/probe.txt'
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "dead in both roles"
}

@test "an empty matcher is rejected — it names nothing, so it decides nothing" {
  run "$HOOK" --check-matcher ""
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "decides nothing"
}

@test "a rejection names the remedy, not just the refusal" {
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

# ── § 3e PART 3: the CwdChanged re-arm, which had NO working implementation until 2026-09-07 ────
#
# 🚨 THESE ARE THE ARMS THAT FAIL AGAINST THE PRE-FIX HANDLER. § 3e mandates a THREE-part wiring
# and part 3 is a CwdChanged hook re-emitting `watchPaths`, because `onCwdChanged` OVERWRITES the
# dynamic watch list wholesale with whatever the CwdChanged hooks return — so with no re-emit the
# list is EMPTY after the first `cd` and every dynamically-armed path is lost silently.
#
# The handler could not do it. Its `[ -n "${FILE_PATH:-}" ] || exit 0` guard sat ABOVE the
# watchPaths emit, and a CwdChanged payload carries no file_path, so the early exit fired first:
#   CwdChanged  → stdout EMPTY        FileChanged → {"hookSpecificOutput":{…}}
# measured on both arms with CC_FILECHANGED_WATCHLIST set. A registration on CwdChanged would have
# read GREEN over a hook that could not perform the one job it was registered for — which is why
# 0017 waits for this fix rather than shipping alongside 0016.
#
# One mutant per SITE, so a green run credits each: arm 1 pins the guard's PLACEMENT (restore the
# early exit and it goes red), arm 2 pins the hookEventName's SOURCE (hard-code the constant back
# and it goes red), arm 3 pins the direction the fix must NOT overshoot in — narrowing the guard to
# the logging path must not start writing unattributable rows.

cwd_payload() { # <old_cwd> <new_cwd> <session_id>
  jq -nc --arg o "$1" --arg n "$2" --arg s "$3" \
    '{session_id:$s,transcript_path:"/tmp/t.jsonl",cwd:$o,
      hook_event_name:"CwdChanged",new_cwd:$n}'
}

@test "a CwdChanged payload EMITS watchPaths — § 3e part 3, the re-arm" {
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch-cwd"
  printf '/Users/x/mailbox.md\n/Users/x/other.md\n' > "$CC_FILECHANGED_WATCHLIST"
  cwd_payload /private/tmp/hs/fc /private/tmp/hs/cwdtarget sid-cwd > "$BATS_TEST_TMPDIR/cwd.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/cwd.json"
  [ "$status" -eq 0 ]
  # the pre-fix handler exits before this line ever runs, so $output is empty and this fails
  echo "$output" | grep -q "watchPaths"
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 2' > /dev/null
  echo "$output" | grep -q "/Users/x/mailbox.md"
}

@test "the emitted hookEventName names the event being HANDLED, not a constant" {
  # Hard-coded "FileChanged" would label a CwdChanged re-arm with an event that did not fire it.
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch-name"
  printf '/Users/x/mailbox.md\n' > "$CC_FILECHANGED_WATCHLIST"
  cwd_payload /tmp/a /tmp/b sid-name > "$BATS_TEST_TMPDIR/cwd2.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/cwd2.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "CwdChanged"' > /dev/null
  # and the FileChanged arm still says FileChanged — a name read from the payload, not swapped
  feed /private/tmp/hs/fc/probe.txt change sid-name2
  run "$HOOK" < "$PAYLOAD"
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "FileChanged"' > /dev/null
}

@test "a CwdChanged payload still writes NO log row — the guard was narrowed, not deleted" {
  # The over-wide fix. A CwdChanged payload has no file_path, so a row for it would name no file
  # and no later query could attribute it; narrowing the guard to the logging path must preserve
  # exactly the behaviour the no-file_path arm above pins.
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/watch-nolog"
  printf '/Users/x/mailbox.md\n' > "$CC_FILECHANGED_WATCHLIST"
  cwd_payload /tmp/a /tmp/b sid-nolog > "$BATS_TEST_TMPDIR/cwd3.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/cwd3.json"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
  # it did emit, so the absent log is the guard working rather than the handler exiting early
  echo "$output" | grep -q "watchPaths"
}

@test "a CwdChanged payload with NO watchlist prints nothing — the default stays silent" {
  cwd_payload /tmp/a /tmp/b sid-quiet > "$BATS_TEST_TMPDIR/cwd4.json"
  run "$HOOK" < "$BATS_TEST_TMPDIR/cwd4.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the '*' matcher is judged as ITSELF, not pathname-expanded to the cwd" {
  # 🚨 THE VACUOUS PASS. `--check-matcher` splits on `|` with an UNQUOTED expansion, which is also
  # subject to pathname expansion — so `*` globbed to whatever files sat in the caller's cwd and
  # the checker judged THOSE. It exited 0 (bare basenames are accepted), so the star arm above
  # passed for entirely the wrong reason and could never have rejected a bad `*`. Measured
  # 2026-09-07: migrations/0017 asserting its own dispatch matcher printed 36 NOTICE lines naming
  # this repo's own files. The star is the dispatch half of the § 3e pair, so a checker blind to it
  # is blind to the half that decides whether the hook ever runs.
  cd "$BATS_TEST_TMPDIR"
  touch alpha.txt beta.txt
  run "$HOOK" --check-matcher '*'
  [ "$status" -eq 0 ]
  # pre-fix this printed a NOTICE per file in cwd; a correctly-judged `*` says nothing at all
  [ -z "$output" ]
}
