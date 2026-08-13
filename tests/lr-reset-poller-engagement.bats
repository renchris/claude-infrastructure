#!/usr/bin/env bats
# lr-reset-poller — THE ENGAGEMENT AUDIT (E1-E8; backlog f76e7d78aaac, 2026-08-12).
#
# THE GAP THAT IS THE SPEC. lr-reset-poller.sh claims a sid, spawns a resume, logs
# `RESUMED … pane opened`, and never asks again. "Pane opened" is the only thing it verifies. A
# resume that opened a pane and then wedged on a blocking startup modal is indistinguishable from a
# healthy one — SessionStart never fires behind a dialog, so no session row and no transcript are
# ever written and every ordinary liveness probe answers "fine". The claim then expires on a pure
# 15-minute wall-clock TTL and the sid is re-fired, with NO record anywhere that the first fire
# never engaged. hooks/lib/engagement.sh is the oracle for that class, and `cc_engaged_sid` is its
# sid-keyed entry point (the poller holds a sid and never a pane id).
#
# THE ARM IS DETECT-ONLY AND FAIL-OPEN. It must not re-fire, must not release or extend the claim,
# and must not stop the daemon recovering when the lib is unreachable. E6/E7/E8 are those three.
#
# Isolation: hermetic $HOME; the lock dir is redirected via LR_POLLER_LOCK_DIR; the transcript
# search is pinned to the fixture home via CC_ENGAGE_HOMES; no parked session is seeded, so §1/§2
# of the poller are no-ops and the audit is the only thing a tick does.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  CLAIMS="$STATE/fire-claims"
  NOTED="$STATE/engage-noted"
  LOG="$STATE/poller.log"
  PROJ="$HOME/.claude/projects/slug"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$CLAIMS" "$PROJ"

  export LR_POLLER_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export CC_ENGAGE_HOMES="$HOME/.claude"   # engagement.sh's documented test seam
  # PIN THE TERMINAL: spawn_gui has a kitty arm, and inside kitty an inherited KITTY_WINDOW_ID would
  # let a spawn reach the operator's real fleet from a test.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # Inherited from the pane that fired an agent running this suite; unset in setup, not per-test.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE

  SID="076a1186-dead-beef-0000-000000000000"
}

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────

# A claim aged past the settle window. `touch -t` with a fixed past stamp, never a sleep.
_claim_old() { : > "$CLAIMS/${1:-$SID}"; touch -t 200001010000 "$CLAIMS/${1:-$SID}"; }
# A claim written THIS INSTANT — the shape §2 leaves behind on the tick that fires.
_claim_fresh() { : > "$CLAIMS/${1:-$SID}"; }

_engaged_transcript() {
  {
    printf '{"type":"system","subtype":"init"}\n'
    printf '{"type":"user","message":{"content":"go"}}\n'
    printf '{"type":"assistant","message":{"content":"working on it"}}\n'
  } > "$PROJ/${1:-$SID}.jsonl"
}
# Rows landed, the model never ran — the state a birth-check calls healthy.
_silent_transcript() {
  {
    printf '{"type":"system","subtype":"init"}\n'
    printf '{"type":"user","message":{"content":"go"}}\n'
  } > "$PROJ/${1:-$SID}.jsonl"
}

# ALWAYS prints an integer. A bare `grep -c … || true` prints NOTHING when the log does not exist
# yet, and `[ "" -eq 0 ]` is a status-2 ERROR, not a pass — the count assertions would then be
# unable to express "the tick logged nothing", which is half of what this suite measures.
_not_engaged_lines() { local n; n="$(grep -c "NOT-ENGAGED" "$LOG" 2>/dev/null)" || n=0; printf '%s' "${n:-0}"; }

# ── E1: the class itself — a claimed sid with no assistant turn is REPORTED ─────────────────────

@test "E1: a claim past the settle window with NO assistant turn logs NOT-ENGAGED with the why token" {
  _claim_old; _silent_transcript
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run grep -c "NOT-ENGAGED $SID" "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep -q "why=transcript-without-assistant-turn" "$LOG"
  [ "$status" -eq 0 ]
}

@test "E2: no transcript at all is the modal's own signature — still NOT-ENGAGED" {
  # The wedge this exists for produces NO transcript, not an empty one: the oracle must answer, not
  # abstain. (`transcript-without-assistant-turn` covers both — a session id with no turn anywhere.)
  _claim_old                      # deliberately no transcript seeded
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run grep -q "NOT-ENGAGED $SID" "$LOG"
  [ "$status" -eq 0 ]
}

# ── E3: the healthy population must stay silent, and the case proves it can speak ───────────────

@test "E3: a claim whose session DID take an assistant turn is silent — and the same tick speaks once the turn is gone" {
  _claim_old; _engaged_transcript
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 0 ]
  # POSITIVE CONTROL, in the same test: absence is only evidence if presence was reachable. Strip
  # the assistant turn and the identical tick must report.
  _silent_transcript
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 1 ]
}

# ── E4: the settle window — a fire is not a wedge for the first few minutes ─────────────────────

@test "E4: a claim INSIDE the settle window is not judged — and IS judged once it ages past it" {
  # A claim is written BEFORE the launcher→expect→claude chain starts, so a fresh one has no
  # transcript by construction. Judging it immediately would report every healthy fire as wedged.
  _claim_fresh
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 0 ]
  touch -t 200001010000 "$CLAIMS/$SID"      # same claim, now aged past the window
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 1 ]
}

# ── E5: notify-once damping — the daemon ticks every ~10 min forever ────────────────────────────

@test "E5: three consecutive ticks over one wedged claim log the report exactly ONCE" {
  _claim_old; _silent_transcript
  run bash "$POLLER"; [ "$status" -eq 0 ]
  run bash "$POLLER"; [ "$status" -eq 0 ]
  run bash "$POLLER"; [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 1 ]
  [ -f "$NOTED/$SID" ]
}

@test "E5b: the damping marker is RE-ARMED once the session engages — a later wedge still reports" {
  # A marker that is never cleared silences the second incident on any session that succeeded once.
  _claim_old; _silent_transcript
  run bash "$POLLER"; [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 1 ]
  _engaged_transcript                        # it came up
  run bash "$POLLER"; [ "$status" -eq 0 ]
  [ ! -f "$NOTED/$SID" ]
  _silent_transcript                         # a LATER fire of the same sid wedges
  run bash "$POLLER"; [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 2 ]
}

@test "E5c: --dry-run REPORTS but does not spend the one report" {
  # A preview that silences the real tick 10 minutes later is worse than no preview.
  _claim_old; _silent_transcript
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 1 ]
  [ ! -f "$NOTED/$SID" ]
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run _not_engaged_lines
  [ "$output" -eq 2 ]
}

# ── E6: DETECT-ONLY — the arm may observe the claim and nothing else ────────────────────────────

@test "E6: the claim is untouched — not released, not re-stamped, and nothing is spawned" {
  _claim_old; _silent_transcript
  local before after
  before="$(stat -f %m "$CLAIMS/$SID")"
  run bash "$POLLER"
  [ "$status" -eq 0 ]
  run grep -q "NOT-ENGAGED $SID" "$LOG"      # positive anchor: the arm DID run
  [ "$status" -eq 0 ]
  [ -f "$CLAIMS/$SID" ]                      # claim not released
  after="$(stat -f %m "$CLAIMS/$SID")"
  [ "$before" = "$after" ]                   # claim not re-stamped (would extend the TTL)
  run grep -c "RESUMED" "$LOG"
  [ "$output" -eq 0 ]                        # no fire decision was taken
}

# ── E7 / E8: FAIL-OPEN — the lib is a side-car, not a precondition for recovery ─────────────────

# A copy of the poller in a tree where NO rung of the ladder resolves: repo-relative is gone
# (fake tree), $HOME is fixtured and holds no .claude/hooks. This exercises the REAL ladder rather
# than a seam that only tests could break.
_orphan_poller() {
  ORPH="$BATS_TEST_TMPDIR/orphan/scripts/limit-recover"
  mkdir -p "$ORPH"
  cp "$POLLER" "$ORPH/lr-reset-poller.sh"
  # lr-select lives beside the script; the poller fails CLOSED on a missing one and exits before
  # §1b. Point it back at the real one so this test measures the ENGAGEMENT ladder, not that.
  export LR_SELECT_BIN="$REPO/scripts/limit-recover/lr-select.py"
  printf '%s' "$ORPH/lr-reset-poller.sh"
}

@test "E7: with the engagement lib unreachable the tick still exits 0 and says so ONCE" {
  local p; p="$(_orphan_poller)"
  _claim_old; _silent_transcript
  run bash "$p"
  [ "$status" -eq 0 ]
  run grep -c "ENGAGE-SKIP" "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run _not_engaged_lines
  [ "$output" -eq 0 ]                        # fail OPEN: no verdict, not a false verdict
  [ -f "$CLAIMS/$SID" ]                      # recovery state untouched
  run bash "$p"                              # second tick: damped, still exit 0
  [ "$status" -eq 0 ]
  run grep -c "ENGAGE-SKIP" "$LOG"
  [ "$output" -eq 1 ]
}

@test "E8: the skip marker clears when the lib comes back — a LATER outage is a fresh line" {
  local p; p="$(_orphan_poller)"
  _claim_old; _silent_transcript
  run bash "$p"; [ "$status" -eq 0 ]
  [ -f "$STATE/engage-lib-missing.notified" ]
  run bash "$POLLER"                         # the real one — ladder resolves
  [ "$status" -eq 0 ]
  [ ! -f "$STATE/engage-lib-missing.notified" ]
  run grep -q "NOT-ENGAGED $SID" "$LOG"
  [ "$status" -eq 0 ]
  run bash "$p"                              # outage returns
  [ "$status" -eq 0 ]
  run grep -c "ENGAGE-SKIP" "$LOG"
  [ "$output" -eq 2 ]
}
