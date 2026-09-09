#!/usr/bin/env bats
# handoff-fire.sh — a fire must not launch into a directory another fire is ALREADY launching into
# (cc-backlog 9d1c8dadf1f8).
#
# THE INCIDENT. Panes 275 (18:18:28) and 276 (18:22:30) were fired four minutes apart, on the same
# account, with an IDENTICAL brief, into the SAME cwd on the SAME branch (fix/cloud-branch-debris).
# They clobbered each other: cherry-picks at 19:39:38 were reset away at 19:40:25 and 19:40:38.
#
# WHY THE EXISTING GATE COULD NOT SEE IT, which is the whole reason this file exists rather than a
# threshold change. hf_occupancy_gate is the right refusal and its sensor is `cc-notify --list` →
# $HOME/.claude/cc-registry. A registry row is written by the FIRED session's own SessionStart hook,
# so between "a fire is decided" and "its pane boots and registers" the store is EMPTY — and empty
# reads as free, never as "I cannot tell yet". That interval is not four minutes: a cold worktree
# installs dependencies under CC_DEPS_TIMEOUT (180s) BEFORE the launcher runs, verify_engagement
# then polls a load-scaled window capped at 480s, and mark_fired_peer — the only fire-time writer of
# a cwd — is not reached until that window SUCCEEDS. Nothing wrote on the path being sensed
# (memory: store-silence-is-evidence-only-if-it-has-a-writer).
#
# WHAT THESE CASES PIN, and why each is not the others:
#   1-2  the REFUSAL, on both worktree shapes. Case 2 is the incident's own first fire: a COLD
#        worktree, whose path does not exist yet. Both occupancy and freshness are called only for
#        `existing|pool` — correct for a SESSION, wrong for a FIRE — so this is the half no
#        existing gate can reach, and it is why the new call sits outside that `case`.
#   3-4  the MODE split, and the one discriminator the registry does not carry. `--cwd` may only
#        WARN, because it is also the warm re-fire of a peer into its own live worktree — but a
#        warm re-fire carries a DIFFERENT brief, and a duplicate is nothing else. 3 refuses on a
#        byte-identical mission; 4 proves a differing one still only warns.
#   5    the POSITIVE CONTROL — no claim says NOTHING. A gate that fired on every fire would carry
#        exactly as many bits as one that never fires (memory: alarm-polarity-and-attention-budget).
#   6-8  the sensor's own failure modes, each of which must ACQUIT: a dead owner, an lstart that
#        does not match the live pid (pid reuse — `kill -0` answers "does some process hold this
#        number", never "is it the one that wrote this"), and a claim past the age belt.
#   9    the kill switch restores the pre-change behaviour byte for byte.
#   10   the CLAIM is actually written, with the owner's own {pid,lstart} and the mission digest.
#   11   RELEASE drops only what THIS pid wrote — a release that touched a sibling's row would be
#        the very duplicate it exists to prevent.
#   12   the mission digest is taken over the ORIGINAL brief, never the launch-time copy. That copy
#        carries a per-fire HANDOFF-ENGAGE marker, so hashing it would make every fire unique and
#        case 3 could never fire.
#
# RED-PROOF (run against the pristine pre-change script recovered with
# `git show origin/main:scripts/handoff-fire.sh`, via HF_OVERRIDE): cases 1, 2, 3, 4, 10, 11 and 12
# FAIL there — that tree has no hf_inflight_gate, writes no claim, refuses nothing and prints no
# warning. Case 4 is red-proof too and it is worth naming why: it is a MODE control (--cwd must
# still only warn on a differing brief), but it asserts the warning ITSELF, which the pre-change
# tree cannot emit. Cases 5, 6, 7, 8 and 9 PASS on both trees, and those are the real controls —
# they assert the change does NOT refuse: no claim, a dead owner, a mismatched lstart, an expired
# claim, and the kill switch. The measured verdicts are recorded in the commit body.
#
# ⚠ THE RECOVERED COPY MUST LIVE INSIDE THE REPO — `scripts/.redproof-handoff-fire.sh`, not /tmp.
# handoff-fire resolves its libraries relative to $0, so a copy run from a scratch directory
# loses them and dies at `CC_ACCT_NAMES: unbound variable` during account routing, ~1200 lines
# BEFORE any gate in this file. Measured: all twelve cases went red that way, including the five
# controls, which reads as a devastating red-proof and is really an instrument that never reached
# the subject (memory: subject-reads-its-own-path-and-its-own-output).
#
# HERMETIC: $HOME is fixtured and CC_FIRE_INFLIGHT_DIR is redirected under $BATS_TEST_TMPDIR, so no
# case can read or mutate the live claim store.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$SRC/scripts/handoff-fire.sh}"
  # PHYSICAL $HOME — $BATS_TEST_TMPDIR lives under a /var → /private/var symlink and the subject
  # resolves with `pwd -P`; resolving once here leaves one normal form to assert against. Two steps
  # on purpose: the one-liner satisfies the SC2155 ratchet or the hermeticity ratchet, never both.
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  mkdir -p "$HOME/.claude/bin"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  printf 'REAL_IT2="/nonexistent/it2"\nPYTHON_BIN="/usr/bin/python3"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  # THE CLAIM STORE, redirected. Without this every case would write into the operator's own
  # ~/.claude/cc-fired/in-flight and a refusal here could block a real fire.
  IFD="$BATS_TEST_TMPDIR/in-flight"; export CC_FIRE_INFLIGHT_DIR="$IFD"
  REPO="$HOME/Development/reso-management-app"      # the subject's own DEFAULT_REPO
  WTROOT="$HOME/Development/.worktrees"
  mkdir -p "$WTROOT"
  mkfixture "$REPO"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — in-flight fixture payload." > "$PAYLOAD"
  OTHER="$BATS_TEST_TMPDIR/other.txt"
  echo "TASK — a DIFFERENT brief, which is what a warm re-fire carries." > "$OTHER"
  # ONE SPELLING OF THE KEY, and it comes from the REPO, not from $HF. Extracted rather than
  # restated so a change to the key function breaks these cases instead of letting the test and the
  # subject index two different files and both stay green (memory:
  # control-calibrated-to-implementation-decays). Deliberately NOT from $HF: under HF_OVERRIDE the
  # subject is the pre-change script, which has no key function at all — sourcing the instrument
  # from there would make the CONTROLS (cases 6-8) die on a missing helper rather than run, and a
  # control that cannot execute on the pre-change tree is not a control (memory:
  # harness-default-collapses-the-states-under-test).
  eval "$(sed -n '/^hf_inflight_key() {/,/^}/p' "$SRC/scripts/handoff-fire.sh")"
  eval "$(sed -n '/^hf_inflight_lstart() {/,/^}/p' "$SRC/scripts/handoff-fire.sh")"
}

g() { local r="${1:?repo required}"; shift; git -C "$r" -c user.email=f@x -c user.name=f "$@"; }

mkfixture() {
  : "${1:?mkfixture: repo path required}"
  mkdir -p "$1"
  g "$1" init -q -b main
  echo x > "$1/f"; g "$1" add f; g "$1" commit -qm init
  g "$1" update-ref refs/remotes/origin/main HEAD
}

# A worktree AT origin/main, so the freshness gate stays silent and only this file's arm can speak.
fresh_wt() { g "$REPO" worktree add -q -b "$1" "$WTROOT/$1" refs/remotes/origin/main; }

digest_of() { shasum -a 256 "$1" 2>/dev/null | cut -c1-32 | tr -d '[:space:]'; }

# claim <dir> <mission-digest> [pid] [lstart] [epoch] — seed a claim as if another fire held it.
# Defaults to a LIVE owner: this bats process, whose {pid,lstart} the subject can verify. The
# subject's own $$ differs, so its "our own claim never blocks us" arm is not what is under test.
claim() {
  local d="$1" m="$2" pid="${3:-$$}" ls="${4:-}" ep="${5:-}" key
  [ -n "$ls" ] || ls="$(hf_inflight_lstart "$pid")"
  [ -n "$ep" ] || ep="$(date +%s)"
  key="$(hf_inflight_key "$d")"
  mkdir -p "$IFD"
  jq -n --arg cwd "$d" --arg pid "$pid" --arg lstart "$ls" --arg mission "$m" \
        --arg at "seeded" --arg ep "$ep" \
        '{cwd:$cwd, pid:($pid|tonumber), lstart:$lstart, mission:$mission,
          firedAt:$at, firedAtEpoch:($ep|tonumber)}' > "$IFD/$key.json"
}

claim_file() { printf '%s/%s.json' "$IFD" "$(hf_inflight_key "$1")"; }

# fire <cwd> [args…] — the real subject, ambient gates pinned off.
fire() {
  local at="$1"; shift
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      CC_FIRE_INFLIGHT_DIR="$IFD" \
      bash -c "cd '$at' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' \"\$@\"" _ "$@"
}

# ── 1-2: the REFUSAL, on both worktree shapes ───────────────────────────────────────────────────

@test "1 a --worktree fire into a tree another fire is ALREADY launching into is REFUSED" {
  fresh_wt wt-x
  claim "$WTROOT/wt-x" "$(digest_of "$PAYLOAD")"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "in-flight: another fire is ALREADY launching into" || false
  echo "$output" | grep -q "Refusing to fire a SECOND session into a directory a live fire is already claiming" || false
}

@test "2 the COLD shape — a path that does not exist YET is refused too (the incident's own fire)" {
  # No fresh_wt: wt-cold has never been created. Both existing gates are called only for
  # `existing|pool`, so this is the case neither of them can reach, and it is the one the incident
  # started with — fire 1 was cold, fire 2 four minutes later found the tree it had made.
  [ ! -d "$WTROOT/wt-cold" ]
  claim "$WTROOT/wt-cold" "$(digest_of "$PAYLOAD")"
  fire "$REPO" --dry-run --worktree wt-cold
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "in-flight: another fire is ALREADY launching into" || false
}

# ── 3-4: the MODE split, and the discriminator the registry does not carry ──────────────────────

@test "3 --cwd REFUSES when the in-flight brief is BYTE-IDENTICAL — that is a duplicate, not a re-fire" {
  fresh_wt wt-c
  claim "$WTROOT/wt-c" "$(digest_of "$PAYLOAD")"
  fire "$REPO" --dry-run --cwd "$WTROOT/wt-c"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "the in-flight fire carries the BYTE-IDENTICAL brief" || false
}

@test "4 --cwd only WARNS when the brief DIFFERS — the warm re-fire of a peer must still work" {
  fresh_wt wt-c
  claim "$WTROOT/wt-c" "$(digest_of "$OTHER")"
  fire "$REPO" --dry-run --cwd "$WTROOT/wt-c"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "in-flight: another fire is ALREADY launching into" || false
  echo "$output" | grep -q "this brief differs from the in-flight one" || false
}

# ── 5: the POSITIVE CONTROL ────────────────────────────────────────────────────────────────────

@test "5 POSITIVE CONTROL — with no claim the fire is silent, and says nothing about in-flight" {
  fresh_wt wt-x
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "in-flight"; then false; fi
}

# ── 6-8: the sensor's own failure modes — each must ACQUIT ─────────────────────────────────────

@test "6 a claim whose owner process is DEAD is ignored" {
  fresh_wt wt-x
  # A pid that is reliably not running: claim one, then let the shell that held it exit.
  dead="$(bash -c 'echo $$')"
  claim "$WTROOT/wt-x" "$(digest_of "$PAYLOAD")" "$dead" "Wed Sep 9 00:00:00 2026"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "in-flight"; then false; fi
}

@test "7 PID REUSE — a live pid whose lstart does not match the claim is ignored" {
  fresh_wt wt-x
  claim "$WTROOT/wt-x" "$(digest_of "$PAYLOAD")" "$$" "Wed Sep 9 00:00:00 2026"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "in-flight"; then false; fi
}

@test "8 a claim past the age belt is ignored even with a live, matching owner" {
  fresh_wt wt-x
  claim "$WTROOT/wt-x" "$(digest_of "$PAYLOAD")" "$$" "" "$(( $(date +%s) - 99999 ))"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "in-flight"; then false; fi
}

# ── 9: the kill switch ─────────────────────────────────────────────────────────────────────────

@test "9 CC_FIRE_INFLIGHT=off restores the pre-change behaviour with a live claim in place" {
  fresh_wt wt-x
  claim "$WTROOT/wt-x" "$(digest_of "$PAYLOAD")"
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      CC_FIRE_INFLIGHT_DIR="$IFD" CC_FIRE_INFLIGHT=off \
      bash -c "cd '$REPO' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' --dry-run --worktree wt-x"
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "in-flight"; then false; fi
}

# ── 10-12: the CLAIM, its RELEASE, and what the mission digest is taken over ───────────────────
#
# UNIT, not end-to-end, and the reason is mechanical: the subject RELEASES its claim on its own EXIT
# trap, so a post-mortem read after a fire always finds nothing and could not tell "claimed then
# released" from "never claimed". Observing mid-fire would need a background job, and a `&` in a
# bats fixture prints a spurious `not ok` beside a passing body (memory:
# bats-background-job-fabricates-not-ok). So the functions are sed-extracted and executed directly —
# the pattern tests/handoff-fire-pane-parked.bats:53 already uses on this same file.

# Every assignment below feeds a function this file EXTRACTED, so shellcheck — which cannot see
# through an `eval` of a sed extraction — reads all four as unused. The finding is about the
# extraction, not the variables. Scoped to the function and to that one code: a per-line directive
# does NOT work here, because it binds to the next COMMAND and `a=1; b=2; c=3` is three of them
# (measured: one directive silenced only the first, leaving two findings live).
# shellcheck disable=SC2034
unit() {
  eval "$(sed -n '/^hf_is_shared_checkout() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_inflight_key() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_inflight_lstart() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_inflight_live() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_mission_digest() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_inflight_gate() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_inflight_release() {/,/^}/p' "$HF")"
  HF_INFLIGHT_DIR="$IFD"; HF_INFLIGHT_CLAIMED=""; DRY=0
  # A shared-checkout probe must not resolve to the operator's real one from inside a fixture.
  CC_FIRE_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/absent-shared"
}

@test "10 the CLAIM is written with this process's own {pid,lstart} and the mission digest" {
  unit
  fresh_wt wt-x
  PROMPT_FILE="$PAYLOAD"; PROMPT_FILE_ORIG=""
  run_gate() { hf_inflight_gate "$WTROOT/wt-x" worktree; }
  run_gate
  f="$(claim_file "$WTROOT/wt-x")"
  [ -s "$f" ]
  [ "$(jq -r '.mission' "$f")" = "$(digest_of "$PAYLOAD")" ]
  [ "$(jq -r '.cwd' "$f")" = "$WTROOT/wt-x" ]
  [ "$(jq -r '.pid' "$f")" = "$$" ]
  [ "$(jq -r '.lstart' "$f")" = "$(hf_inflight_lstart $$)" ]
}

@test "11 RELEASE drops the claim this pid wrote, and leaves a sibling's row alone" {
  unit
  fresh_wt wt-x
  fresh_wt wt-y
  sib="$(claim_file "$WTROOT/wt-y")"
  claim "$WTROOT/wt-y" "$(digest_of "$OTHER")" 1 "seeded-lstart"
  PROMPT_FILE="$PAYLOAD"; PROMPT_FILE_ORIG=""
  hf_inflight_gate "$WTROOT/wt-x" worktree
  [ -s "$(claim_file "$WTROOT/wt-x")" ]
  hf_inflight_release
  [ ! -e "$(claim_file "$WTROOT/wt-x")" ]
  # A release that dropped someone else's row would BE the duplicate it exists to prevent.
  [ -s "$sib" ]
  [ "$(jq -r '.mission' "$sib")" = "$(digest_of "$OTHER")" ]
}

@test "12 the mission digest is over the ORIGINAL brief, not the launch-time copy" {
  # The copy handoff-fire launches from carries a per-fire HANDOFF-ENGAGE marker and a self-retire
  # trailer, so its hash differs on every fire. Taking the digest there would make two fires of ONE
  # brief never match, and case 3 could never fire. PROMPT_FILE_ORIG is the file's own established
  # idiom for exactly this distinction (it is what payload_lint_gate's preview reads).
  unit
  COPY="$BATS_TEST_TMPDIR/copy.txt"
  cat "$PAYLOAD" > "$COPY"
  printf '\n<!-- handoff-fire engagement marker: HANDOFF-ENGAGE-1-2-3 (ignore) -->\n' >> "$COPY"
  [ "$(digest_of "$COPY")" != "$(digest_of "$PAYLOAD")" ]
  # Both are read by the extracted hf_mission_digest, invisibly to shellcheck; one directive per
  # assignment, because a directive covers one command and these were two.
  # shellcheck disable=SC2034
  PROMPT_FILE="$COPY"
  # shellcheck disable=SC2034
  PROMPT_FILE_ORIG="$PAYLOAD"
  [ "$(hf_mission_digest)" = "$(digest_of "$PAYLOAD")" ]
}
