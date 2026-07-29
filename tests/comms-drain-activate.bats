#!/usr/bin/env bats
# 07-comms-drain-activate.sh — the C10 operator script that wires the 2-way-comms mailbox-drain hooks
# into the LIVE per-account settings.json. These tests run ONLY against temp settings.json fixtures
# (CC_CONFIG_DIRS / CC_LIVE_DIR seams) — never the live ~/.claude* files, which are the operator's step.

# ── runtime cap: why this file is bounded, and why the bound lives HERE ───────────────────────────
# THE STALL (backlog 11c7797f2e99): this suite blocked ~6-8 min nondeterministically and wedged every
# ship-land gate past its foreground timeout. Cause chain, all of it INDIRECT — which is why no
# grep of this file ever showed it: the script under test ends with a `verify` step that runs
# `$LIVE/bin/cc-inbox-guard --selftest` (07-comms-drain-activate.sh:171-172), step 0 having just
# symlinked that guard into place. The guard forks `it2 session list --json` against the LIVE
# iTerm2 API, and at the time (pre-8edac699/5a80a648, both landed 2026-07-25 23:0x — AFTER this
# file's last edit at 21:22) that fork was unbounded: the documented `CC_INBOX_GUARD_RECONCILE_BIN=`
# disable used `${VAR:-}`, which cannot tell unset from set-empty, so it fell through to the real
# cc-reconcile and paid the shim's full 30s bound PER SWEEP. Nine of these 14 tests reach the verify
# step and the selftest runs three sweeps each ⇒ 9 × 3 × 30s ≈ the observed 6-8 min, nondeterministic
# with the API's health and SELF-RELEASING when each 30s bound expired. Every symptom in the report.
#
# The upstream seams are fixed, so the acute cause is closed — this suite measures 7.5s green today.
# But its hermeticity was BORROWED, not owned: it survived only because the guard's own selftest
# happens to export CC_INBOX_GUARD_LIVE_UUIDS (bypassing the it2 probe). Nothing in THIS file said so.
# The moment that subject-side detail changes, the live-iTerm2 dependency silently returns and wedges
# the fleet again. So the fix is two-layered: setup() now OWNS the isolation (fixtured $HOME + a
# stubbed it2 ⇒ the live API is unreachable by construction, not by luck), and the caps below convert
# any FUTURE indefinite block into a bounded, attributable RED — a hang is a non-verdict that strands
# the gate, whereas a timeout failure names the test and lets the gate report red and move on.
#
# BATS_TEST_TIMEOUT MUST BE A FILE-LEVEL ASSIGNMENT. Setting it inside setup() is a SILENT NO-OP:
# measured 2026-07-29, a `sleep 60` test under `setup() { BATS_TEST_TIMEOUT=3; }` ran the full
# 60017ms and PASSED. bats applies the cap in the PARENT process as it launches each test, so a
# value assigned in setup() arrives too late to bind. setup_file() also works; setup() never does.
# Do not "tidy" this into setup() — that silently disarms the cap.
#
# CALIBRATION (measured, not guessed — an idle-calibrated bound is an off switch under load, and this
# box runs 30+ sessions). The gate demotes bats to background QoS via bin/cc-bats, and cost scales
# with LOAD, not just with the demotion, so it was measured at two loads:
#
#   full priority, load 11 →  7.5s total, slowest test 1.1s
#   background QoS, load 11 → 43.1s total, slowest test 2.6s     (5.8× on the total)
#   background QoS, load 18 → 49.1s total, slowest test 8.5s     (slowest test 3.3× the load-11 one)
#
# The slowest TEST inflates far faster than the total, so the per-test cap is what needs the margin.
# Extrapolating the slowest test to load ~47 (the worst this box has recorded) gives ~25s, so:
BATS_TEST_TIMEOUT="${BATS_TEST_TIMEOUT:-90}"          # per test  — ~3.6× a load-47 slowest test
CDA_FILE_BUDGET_S="${CDA_FILE_BUDGET_S:-300}"         # whole file — ~2× a load-47 whole run
# Both are deliberately loose: with the cause removed above, these only ever catch an UNKNOWN future
# hang, so a false RED on a saturated box would cost more than the extra minutes of bound. Worst case
# is now BUDGET + one cap ≈ 6.5 min of BOUNDED, test-attributable red instead of an indefinite wedge.

setup_file() {
  # Exported so each test's setup() can see it — verified to propagate (bats 1.13.0).
  export CDA_T0="$(date +%s)"
}

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/docs/activation/pending-activation/07-comms-drain-activate.sh"
  A="$BATS_TEST_TMPDIR/cfg-a"
  B="$BATS_TEST_TMPDIR/cfg-b"
  LIVE="$BATS_TEST_TMPDIR/live"
  mkdir -p "$A" "$B" "$LIVE"

  # The per-test cap cannot bound the file, only each test in it. Fail LOUD (never skip — a skip
  # reads as "nothing to see") once the file's own budget is gone, so the aggregate case is capped
  # at BUDGET + one per-test cap instead of 14 × the per-test cap.
  if [ -n "${CDA_T0:-}" ]; then
    local elapsed=$(( $(date +%s) - CDA_T0 ))
    if [ "$elapsed" -gt "$CDA_FILE_BUDGET_S" ]; then
      printf 'comms-drain-activate.bats: FILE BUDGET BLOWN — %ss elapsed > %ss. Aborting the rest of\n' \
             "$elapsed" "$CDA_FILE_BUDGET_S" >&2
      printf '  the file rather than wedging the gate. Something in this suite is blocking; the usual\n' >&2
      printf '  cause is an un-stubbed external fork reaching a live service (see the header).\n' >&2
      return 1
    fi
  fi

  # ── hermeticity: this suite must not be able to reach live state, whatever its subject does ──
  # $HOME is the load-bearing seam. Both the activation script and cc-inbox-guard resolve their
  # fallbacks under it ($HOME/.claude/bin/it2 among them), so a fixtured $HOME makes the live
  # iTerm2 CLI structurally absent rather than merely unused. The ship-land gate clones $HOME, but
  # a clone still contains a WORKING it2 — cloning protects the operator's files, not the API this
  # suite must never touch. Removing this line re-adds the suite to scripts/test-hermeticity-lint.sh.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # Belt-and-suspenders over the $HOME fixture: pin the guard's it2 to a stub that answers instantly
  # with a well-formed empty pane list, and disable the cc-reconcile backfill fork. Both seams are
  # honored verbatim when SET-BUT-EMPTY (`${VAR+set}`), which is exactly the disable that used to
  # not disable. These are the two paths that reach the iTerm2 API from inside the verify step.
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2-stub"
  printf '#!/bin/bash\nprintf "[]\\n"\nexit 0\n' > "$CC_INBOX_GUARD_IT2"
  chmod +x "$CC_INBOX_GUARD_IT2"
  export CC_INBOX_GUARD_RECONCILE_BIN=""

  # A realistic-shaped settings.json: both hook keys already carry an unrelated group.
  fixture "$A"
  fixture "$B"
}

fixture() {
  cat > "$1/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/session-start.sh", "timeout": 10 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/memory-nudge.sh", "timeout": 5 } ] }
    ]
  }
}
JSON
}

# Run the activation script against the fixture dirs only.
act() { CC_CONFIG_DIRS="$A $B" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" run bash "$S" "$@"; }

drain_count() { # $1=file $2=hook key
  jq "[.hooks.$2[]?.hooks[]?.command? // empty] | map(select(contains(\"mailbox-drain\"))) | length" "$1"
}

@test "dry run (no CONFIRM) changes nothing and says so" {
  before="$(cat "$A/settings.json")"
  act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'dry run'
  [ "$before" = "$(cat "$A/settings.json")" ]
  [ ! -f "$A/settings.json.pre-comms-drain.bak" ]
}

@test "CONFIRM=1 wires every fixture dir: result parses and carries BOTH drain entries" {
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  for d in "$A" "$B"; do
    jq empty "$d/settings.json"
    [ "$(drain_count "$d/settings.json" SessionStart)" -eq 1 ]
    [ "$(drain_count "$d/settings.json" UserPromptSubmit)" -eq 1 ]
    jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("mailbox-drain.sh session-start"))' "$d/settings.json"
    jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(contains("mailbox-drain.sh prompt"))' "$d/settings.json"
  done
}

@test "the wired entries are copied VERBATIM from settings.example.json" {
  CONFIRM=1 act
  T="$REPO/settings-templates/settings.example.json"
  want="$(jq -cS 'first(.hooks.SessionStart[]?.hooks[]? | select(.command? // "" | contains("mailbox-drain.sh session-start")))' "$T")"
  got="$(jq -cS 'first(.hooks.SessionStart[]?.hooks[]? | select(.command? // "" | contains("mailbox-drain.sh session-start")))' "$A/settings.json")"
  [ "$want" = "$got" ]
}

@test "append never overwrites the pre-existing sibling groups" {
  CONFIRM=1 act
  jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("session-start.sh"))' "$A/settings.json"
  jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(contains("memory-nudge.sh"))' "$A/settings.json"
}

@test "a backup is written before the edit and restores the pre-wired state" {
  CONFIRM=1 act
  [ -f "$A/settings.json.pre-comms-drain.bak" ]
  [ "$(drain_count "$A/settings.json.pre-comms-drain.bak" SessionStart)" -eq 0 ]
}

@test "IDEMPOTENT: a second run skips every dir and adds nothing twice" {
  CONFIRM=1 act
  after_first="$(cat "$A/settings.json")"
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already wired'
  printf '%s' "$output" | grep -q 'wired:   0'
  [ "$after_first" = "$(cat "$A/settings.json")" ]
  [ "$(drain_count "$A/settings.json" SessionStart)" -eq 1 ]
  [ "$(drain_count "$A/settings.json" UserPromptSubmit)" -eq 1 ]
}

@test "malformed settings.json → RESTORE + nonzero, the file is byte-identical" {
  printf '{ "hooks": { "SessionStart": [ ' > "$B/settings.json"   # truncated JSON
  before="$(cat "$B/settings.json")"
  CONFIRM=1 act
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'RESTORED'
  [ "$before" = "$(cat "$B/settings.json")" ]
  ! grep -q 'mailbox-drain' "$B/settings.json"
}

@test "a settings.json with no .hooks at all is wired cleanly (not corrupted)" {
  echo '{"model":"opus"}' > "$B/settings.json"
  CC_CONFIG_DIRS="$B" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" CONFIRM=1 run bash "$S"
  [ "$status" -eq 0 ]
  jq -e '.model == "opus"' "$B/settings.json"
  [ "$(drain_count "$B/settings.json" SessionStart)" -eq 1 ]
  [ "$(drain_count "$B/settings.json" UserPromptSubmit)" -eq 1 ]
}

@test "--rollback restores every backup and drops the drain lines" {
  CONFIRM=1 act
  act --rollback
  [ "$status" -eq 0 ]
  for d in "$A" "$B"; do
    ! grep -q 'mailbox-drain' "$d/settings.json" || false
    [ ! -f "$d/settings.json.pre-comms-drain.bak" ]
    jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("session-start.sh"))' "$d/settings.json"
  done
}

@test "step 0 creates the per-file symlinks the wired path depends on" {
  CONFIRM=1 act
  for rel in hooks/mailbox-drain.sh hooks/lib/mailbox-pending.sh bin/cc-inbox-guard; do
    [ -L "$LIVE/$rel" ]
    [ "$(readlink "$LIVE/$rel")" = "$REPO/$rel" ]
    [ -e "$LIVE/$rel" ]
  done
}

@test "a dir-symlinked hooks/ is detected and left alone" {
  ln -s "$REPO/hooks" "$LIVE/hooks"
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'dir-symlink'
  [ -L "$LIVE/hooks" ]
}

@test "a dir with no settings.json is not created or wired" {
  empty="$BATS_TEST_TMPDIR/no-settings"
  mkdir -p "$empty"
  CC_CONFIG_DIRS="$A $empty" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" CONFIRM=1 run bash "$S"
  [ "$status" -eq 0 ]
  [ ! -e "$empty/settings.json" ]
}

@test "a template PREDATING the 2-way-comms commit → nonzero + names the ff-sync fix" {
  fake="$BATS_TEST_TMPDIR/oldrepo"
  mkdir -p "$fake/settings-templates"
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh"}]}]}}' \
    > "$fake/settings-templates/settings.example.json"
  CC_CONFIG_DIRS="$A" CC_LIVE_DIR="$LIVE" CC_REPO="$fake" CONFIRM=1 run bash "$S"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'no mailbox-drain entry'
  printf '%s' "$output" | grep -q 'merge --ff-only origin/main'
  ! grep -q 'mailbox-drain' "$A/settings.json"
}

# ── guards on the guards ────────────────────────────────────────────────────────────────
# The two protections above are what stops this file from wedging the landing gate again (backlog
# 11c7797f2e99). Both are silent when removed — a deleted `export HOME=` still leaves 14 passing
# tests, and a cap moved into setup() still reads like a cap while binding nothing. So assert them:
# a disarmed protection must fail LOUD here rather than resurface as a 6-8 min gate stall.

@test "GUARD: the runtime caps are armed (a hang fails bounded, never wedges the gate)" {
  [ -n "${BATS_TEST_TIMEOUT:-}" ]                 # file-level assignment reached this test
  [[ "$BATS_TEST_TIMEOUT" =~ ^[0-9]+$ ]] || false
  [ "$BATS_TEST_TIMEOUT" -gt 0 ]
  [ -n "${CDA_FILE_BUDGET_S:-}" ]
  [[ "$CDA_FILE_BUDGET_S" =~ ^[0-9]+$ ]] || false
  [ "$CDA_FILE_BUDGET_S" -gt 0 ]
  [ -n "${CDA_T0:-}" ]                            # setup_file ran and its export propagated
}

@test "GUARD: this suite cannot reach the live iTerm2 CLI or the operator's real \$HOME" {
  # $HOME must be the fixture — being under BATS_TEST_TMPDIR is what proves it is not the real one.
  case "$HOME" in "$BATS_TEST_TMPDIR"/*) ;; *) false ;; esac
  [ -d "$HOME" ]
  # The fallback the stall came through — cc-inbox-guard's IT2="${CC_INBOX_GUARD_IT2:-$HOME/.claude/bin/it2}"
  # — must resolve to nothing under the fixtured $HOME.
  [ ! -e "$HOME/.claude/bin/it2" ]
  # …and the explicit pin must be a live, in-fixture stub that answers instantly.
  case "$CC_INBOX_GUARD_IT2" in "$BATS_TEST_TMPDIR"/*) ;; *) false ;; esac
  [ -x "$CC_INBOX_GUARD_IT2" ]
  run "$CC_INBOX_GUARD_IT2" session list --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  # set-but-EMPTY is the documented disable for the cc-reconcile backfill fork; prove it is SET.
  [ -n "${CC_INBOX_GUARD_RECONCILE_BIN+set}" ]
  [ -z "$CC_INBOX_GUARD_RECONCILE_BIN" ]
}

@test "the live ~/.claude* settings are NEVER touched by this suite" {
  # Guard the guard: the script must refuse to run with no template rather than fall back to defaults.
  CC_CONFIG_DIRS="$A" CC_LIVE_DIR="$LIVE" CC_REPO="$BATS_TEST_TMPDIR/nope" CONFIRM=1 run bash "$S"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'template not found'
  ! grep -q 'mailbox-drain' "$A/settings.json"
}
