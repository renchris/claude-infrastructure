#!/usr/bin/env bats
# cwd-changed — the CwdChanged re-arm (HOOK_SURFACE_100P § 3e part 3, § 3 row 30, W3-E).
#
# Harness laws, inherited from tests/file-changed.bats and NOT relaxed:
#   L1 every fixture payload is the literal shape the harness emits — the field list measured in
#      § 3e ({cwd, hook_event_name, new_cwd, old_cwd, session_id, transcript_path}), not invented.
#   L2 assertions key on failure-DISTINCT strings, so a handler that emitted the wrong field or
#      swallowed the list goes RED rather than passing on a coincidence.
#   L3 every assertion is `[ ]` / `grep -q` — never `[[ ]]`, `(( ))` or `! cmd`. bash exempts an
#      inverted return status from errexit entirely, so `! foo` is a VACUOUS assertion wearing a
#      green tick; a negative is asserted as `run foo` + `[ "$status" -ne 0 ]`.
#   L4 both the firing and the NOT-firing case are fixtured.
#   L5 `run` never appears on the right of a pipe — bats runs a pipeline's last element in a
#      SUBSHELL, so $status and $output come back empty and every assertion on them passes
#      vacuously. Payloads reach the hooks by REDIRECTION.
#
# 🚨 THE ARM THIS SUITE EXISTS FOR IS "the watch SURVIVES a cd". A happy-path suite over this
# handler — feed it a CwdChanged payload, see JSON come out — is vacuous against the failure the
# hook was written to prevent, because that failure is not in the emit's SHAPE, it is in the
# LIFECYCLE: `onCwdChanged` overwrites the dynamic watch list wholesale with whatever the
# CwdChanged hooks return, so with no re-emit the list is EMPTY after the first `cd` and every
# dynamically-armed path is lost silently. The acceptance arm below models exactly the two
# mechanisms § 3e measured — and only those two — and asserts the originally-armed path is still
# watched on the far side of the transition, while the same-named file under the NEW cwd is not.
# That second half is the measured § 3e trap: after a `cd`, the relative matcher fired for a
# DIFFERENT file of that name while the originally-armed path produced zero rows.
#
# ⚠️ WHAT THAT ARM IS AND IS NOT. It does not drive the binary's watcher — the measurement that
# established these mechanics is done and § 3e is its record; re-probing it here would be a second,
# weaker instrument. It is a model of the documented lifecycle, and it is falsifiable in the one
# way that matters: break the handler's emit and the arm goes red, because the modelled list is
# rebuilt from the handler's real stdout on a real payload.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/cwd-changed.sh"
  FCHOOK="$REPO/hooks/file-changed.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_CWDCHANGED_LOG_DIR="$HOME/.claude/logs"
  LOG="$CC_CWDCHANGED_LOG_DIR/cwd-changed.log"
  export CC_FILECHANGED_WATCHLIST="$BATS_TEST_TMPDIR/file-watch-paths"
  PAYLOAD="$BATS_TEST_TMPDIR/payload.json"
}

# The literal CwdChanged payload. `cwd` and `old_cwd` are BOTH present and both name the origin —
# that is the shape the brief records, and the handler must not confuse either with the
# destination.
cwd_payload() { # <old_cwd> <new_cwd> <session_id>
  jq -nc --arg o "$1" --arg n "$2" --arg s "$3" \
    '{session_id:$s,transcript_path:"/tmp/t.jsonl",cwd:$o,
      hook_event_name:"CwdChanged",old_cwd:$o,new_cwd:$n}'
}

# The sibling event's payload, for the mis-registration arms and for the arming half of the model.
fc_payload() { # <file_path> <event> <session_id>
  jq -nc --arg f "$1" --arg e "$2" --arg s "$3" \
    '{session_id:$s,transcript_path:"/tmp/t.jsonl",cwd:"/private/tmp/hs/fc",
      hook_event_name:"FileChanged",file_path:$f,event:$e}'
}

feed_cwd() { cwd_payload "$1" "$2" "$3" > "$PAYLOAD"; }

# ── the harness model, used ONLY by the acceptance arm ──────────────────────────────────────────
# ARM      — the dynamic list as it stands before the cd, built from the FileChanged handler's own
#            emit, which is how it is actually armed.
# CD       — `onCwdChanged` OVERWRITES the list with what the CwdChanged hooks return (r = A.watchPaths).
# WATCHED  — a `*` matcher dispatches for any path IN the list; a path absent from the list is not
#            watched at all, so no matcher can reach it.
harness_arm() { # <abs path that the watchlist holds>
  fc_payload "$1" change sid-arm > "$BATS_TEST_TMPDIR/arm.json"
  HARNESS_LIST="$("$FCHOOK" < "$BATS_TEST_TMPDIR/arm.json" | jq -r '.hookSpecificOutput.watchPaths[]?' 2>/dev/null || true)"
}
harness_cd() { # <old_cwd> <new_cwd>
  cwd_payload "$1" "$2" sid-cd > "$BATS_TEST_TMPDIR/cd.json"
  HARNESS_LIST="$("$HOOK" < "$BATS_TEST_TMPDIR/cd.json" | jq -r '.hookSpecificOutput.watchPaths[]?' 2>/dev/null || true)"
}
harness_watched() { grep -qxF -- "$1" <<< "$HARNESS_LIST"; }

# ════════════════════════════════════════════════════════════════════════════════════════════════
# THE ACCEPTANCE ARM
# ════════════════════════════════════════════════════════════════════════════════════════════════

@test "THE WATCH SURVIVES A cd — the originally-armed path is still watched afterwards" {
  OLD="$BATS_TEST_TMPDIR/old"; NEW="$BATS_TEST_TMPDIR/old/sub"
  mkdir -p "$OLD" "$NEW"
  printf '%s\n' "$OLD/dyn.txt" > "$CC_FILECHANGED_WATCHLIST"

  # arm it, and prove the arm took — a control, so a later "still watched" cannot pass on an
  # assertion that was never true in the first place
  harness_arm "$OLD/dyn.txt"
  run harness_watched "$OLD/dyn.txt"
  [ "$status" -eq 0 ]

  # the cd. This is the moment the list is wiped and rebuilt; with no CwdChanged handler it is
  # EMPTY from here on and everything below fails.
  harness_cd "$OLD" "$NEW"

  # write the ORIGINALLY-ARMED file, and assert it would still dispatch
  printf 'changed\n' > "$OLD/dyn.txt"
  run harness_watched "$OLD/dyn.txt"
  [ "$status" -eq 0 ]

  # ...and the measured § 3e trap: a same-named file under the NEW cwd is NOT what is watched.
  # A handler that re-based the list onto new_cwd would pass the line above and fail here.
  printf 'decoy\n' > "$NEW/dyn.txt"
  run harness_watched "$NEW/dyn.txt"
  [ "$status" -ne 0 ]
}

@test "...and with NO re-arm the list is empty after the cd — the failure the arm above detects" {
  # The control that makes the acceptance arm mean something: the same model, with the CwdChanged
  # hook replaced by the do-nothing handler that is the state of the world before this file exists.
  OLD="$BATS_TEST_TMPDIR/old2"; NEW="$BATS_TEST_TMPDIR/old2/sub"
  mkdir -p "$OLD" "$NEW"
  printf '%s\n' "$OLD/dyn.txt" > "$CC_FILECHANGED_WATCHLIST"
  harness_arm "$OLD/dyn.txt"
  run harness_watched "$OLD/dyn.txt"
  [ "$status" -eq 0 ]
  HARNESS_LIST=""          # onCwdChanged with no registered CwdChanged hook: r = nothing
  run harness_watched "$OLD/dyn.txt"
  [ "$status" -ne 0 ]
}

# ── the emit ────────────────────────────────────────────────────────────────────────────────────

@test "a CwdChanged payload re-emits the armed watchPaths" {
  printf '/Users/x/mailbox.md\n/Users/x/other.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-1
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "watchPaths"
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 2' > /dev/null
  echo "$output" | grep -q "/Users/x/mailbox.md"
}

@test "the emitted hookEventName names the event being HANDLED, not a constant" {
  printf '/Users/x/mailbox.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-2
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "CwdChanged"' > /dev/null
}

@test "stdout is EXACTLY one JSON object and nothing else" {
  # The harness parses this; a stray byte hands it a malformed watchPaths and can corrupt the very
  # list this hook exists to preserve.
  printf '/Users/x/a.md\n/Users/x/b.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-3
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | jq -e 'type == "object"' > /dev/null
}

@test "the re-arm is INDEPENDENT of new_cwd — no path is re-based onto the destination" {
  # Re-basing is the defect the event exists to escape (§ 3e: after a cd the relative matcher fired
  # for a DIFFERENT file of that name). The emitted paths must be the watchlist's own, verbatim.
  printf '/private/tmp/hs/old/dyn.txt\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /private/tmp/hs/old /private/tmp/hs/new sid-4
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "/private/tmp/hs/old/dyn.txt"
  run grep -q "/private/tmp/hs/new/dyn.txt" <<< "$output"
  [ "$status" -ne 0 ]
}

@test "the REVERT path changes nothing — a misnamed new_cwd cannot reach the emit" {
  # § 3e's hazard "new_cwd can misname the session directory" is conditional on an out-of-scope cd.
  # The emit must be byte-identical whatever new_cwd says, because it never reads it.
  printf '/Users/x/mailbox.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /private/tmp/hs/old /private/tmp/hs/old sid-5
  run "$HOOK" < "$PAYLOAD"
  A="$output"
  feed_cwd /private/tmp/hs/old /a/completely/wrong/place sid-5
  run "$HOOK" < "$PAYLOAD"
  [ "$A" = "$output" ]
}

# ── the watchlist reader ────────────────────────────────────────────────────────────────────────

@test "a RELATIVE watchlist entry is DROPPED, not resolved" {
  # Resolving it would re-create the cwd dependency this whole wiring exists to escape.
  printf 'relative.md\n/Users/x/absolute.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-6
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 1' > /dev/null
  echo "$output" | grep -q "/Users/x/absolute.md"
}

@test "comments and blank lines in the watchlist are ignored" {
  printf '# a comment\n\n   # an indented comment\n/Users/x/real.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-7
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.watchPaths | length == 1' > /dev/null
  echo "$output" | grep -q "/Users/x/real.md"
}

@test "no watchlist at all prints nothing — the default posture is a silent observer" {
  feed_cwd /tmp/a /tmp/b sid-8
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a watchlist with no usable entry prints nothing rather than an empty array" {
  printf '# only comments\nrelative.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-9
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── the receipt: what makes a re-arm distinguishable from a registered no-op ─────────────────────

@test "a transition writes ONE receipt row carrying the count it re-armed" {
  printf '/Users/x/a.md\n/Users/x/b.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /private/tmp/old /private/tmp/new sid-rec
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 1 ]
  grep -q "sid-rec" "$LOG"
  grep -q "/private/tmp/old" "$LOG"
  grep -q "/private/tmp/new" "$LOG"
  grep -qE '	2$' "$LOG"
}

@test "the count-0 case STILL writes a row — it is the § 3e failure made observable" {
  # 🚨 THE ARM THAT EARNS THE RECEIPT. § 3e-FINDING's failure class is a registered no-op that reads
  # GREEN: the command string is present, the file is executable, it exits 0. Without a row on the
  # empty path, "the registration fired and rebuilt an EMPTY list" and "the registration never
  # fired" are the same observation — and the first is the bug the wiring exists to prevent.
  printf '# nothing usable\nrelative.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /private/tmp/old /private/tmp/new sid-zero
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$LOG" ]
  grep -q "sid-zero" "$LOG"
  grep -qE '	0$' "$LOG"
}

@test "old_cwd is recorded as the ORIGIN, with cwd as the fallback when it is absent" {
  # A row that recorded the destination as the origin would invert the transition it is the only
  # record of.
  jq -nc '{session_id:"sid-fb",transcript_path:"/tmp/t.jsonl",cwd:"/private/tmp/origin",
           hook_event_name:"CwdChanged",new_cwd:"/private/tmp/dest"}' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -qE '	/private/tmp/origin	/private/tmp/dest	' "$LOG"
}

@test "old_cwd WINS over cwd when they disagree — the row records the ORIGIN" {
  # The arm that makes the `.old_cwd // .cwd` preference falsifiable. Every other fixture has the
  # two fields agreeing, so a handler that read `.cwd` alone passed them all; only a payload where
  # they DIVERGE can tell the preference from the fallback. `old_cwd` is this event's own field and
  # is authoritative for the transition — a row that took the generic `cwd` instead would record
  # whichever directory the harness happened to hold and silently misname the origin.
  jq -nc '{session_id:"sid-pref",transcript_path:"/tmp/t.jsonl",cwd:"/private/tmp/stale",
           hook_event_name:"CwdChanged",old_cwd:"/private/tmp/origin",new_cwd:"/private/tmp/dest"}' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -qE '\t/private/tmp/origin\t/private/tmp/dest\t' "$LOG"
  run grep -q "/private/tmp/stale" "$LOG"
  [ "$status" -ne 0 ]
}

@test "the log rotates at the byte cap instead of growing without bound" {
  mkdir -p "$CC_CWDCHANGED_LOG_DIR"
  head -c 400 /dev/zero | tr '\0' 'x' > "$LOG"
  export CC_CWDCHANGED_MAX_BYTES=100
  feed_cwd /tmp/a /tmp/b sid-rot
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -f "$LOG.1" ]
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 1 ]
}

# ── the event gate: a mis-registration must be INERT ─────────────────────────────────────────────

@test "a FileChanged payload is inert — no emit, no row" {
  # The realistic mis-registration: this handler is wired BESIDE FileChanged, so pointing it at the
  # wrong one of the pair is one keystroke. It must not re-emit the list on a per-file-save cadence
  # and must not mint a transition row for a payload carrying no transition.
  printf '/Users/x/a.md\n' > "$CC_FILECHANGED_WATCHLIST"
  fc_payload /private/tmp/hs/fc/probe.txt change sid-fc > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

@test "a payload with no hook_event_name at all is inert" {
  printf '/Users/x/a.md\n' > "$CC_FILECHANGED_WATCHLIST"
  jq -nc '{session_id:"sid-none",cwd:"/tmp/a",new_cwd:"/tmp/b"}' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

# ── fail-open ───────────────────────────────────────────────────────────────────────────────────

@test "malformed JSON exits 0, emits nothing and writes nothing" {
  printf '/Users/x/a.md\n' > "$CC_FILECHANGED_WATCHLIST"
  printf '{not json' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

@test "empty stdin exits 0 and emits nothing" {
  : > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unwritable log directory does not cost the re-arm" {
  # The emit is the load-bearing half. A read-only HOME or a full disk must degrade the receipt,
  # never the thing the hook is registered for.
  printf '/Users/x/a.md\n' > "$CC_FILECHANGED_WATCHLIST"
  export CC_CWDCHANGED_LOG_DIR="/dev/null/nope"
  feed_cwd /tmp/a /tmp/b sid-ro
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "watchPaths"
}

@test "the kill switch makes it a total no-op" {
  printf '/Users/x/a.md\n' > "$CC_FILECHANGED_WATCHLIST"
  export CC_CWD_CHANGED_DISABLED=1
  feed_cwd /tmp/a /tmp/b sid-ks
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$LOG" ]
}

# ── the two contracts that are not about this handler's own behaviour ────────────────────────────

@test "AGREEMENT: this handler and file-changed.sh emit IDENTICAL watchPaths over one watchlist" {
  # 🚨 THE ANTI-DRIFT ARM. § 3e's wiring is a PAIR plus a re-arm reading ONE watchlist; two hooks
  # reading two different lists would be a second SSOT. They share the file and the env seam, but
  # they are separate readers, so the guarantee is made mechanical here: change either reader
  # without the other and this goes red (memory: sibling-auditors-must-share-the-state-model).
  printf '# c\n/Users/x/a.md\nrelative.md\n\n/Users/x/b.md\n' > "$CC_FILECHANGED_WATCHLIST"
  feed_cwd /tmp/a /tmp/b sid-agree
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  MINE="$(echo "$output" | jq -c '.hookSpecificOutput.watchPaths')"
  run "$FCHOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  THEIRS="$(echo "$output" | jq -c '.hookSpecificOutput.watchPaths')"
  [ -n "$MINE" ]
  [ "$MINE" = "$THEIRS" ]
}

@test "this handler is registered in NO settings file in this repo" {
  # § 4's adoption precondition, made mechanical rather than remembered: W3-E ships the handler and
  # the desk composes the registration as a separate c10 migration. A future session cannot wire it
  # from inside this wave's own deliverable without going red.
  run grep -rl "cwd-changed.sh" "$REPO/settings-templates" "$REPO/.claude"
  [ "$status" -ne 0 ]
}
