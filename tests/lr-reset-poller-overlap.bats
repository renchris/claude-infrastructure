#!/usr/bin/env bats
# lr-reset-poller — SELF-OVERLAP LOCK + FIRE CLAIM (LO1-LO4, LC1-LC4; 2026-07-26).
#
# THE INCIDENT THAT IS THE SPEC (2026-07-26):
#   FOUR concurrent `claude --resume 076a1186-…` processes, each under its own lr-fire-resume.sh
#   expect wrapper, three of them spawned within ~90 seconds — ~1.9 GB of duplicate sessions, and
#   four processes appending to ONE transcript file. Two independent holes produced it:
#     (1) NO self-overlap lock. launchd fires the poller every ~10 min, but a tick does a
#         per-session lr-audit subprocess plus claude-accounts calls; on a loaded box a tick
#         outruns its own interval and two ticks run concurrently. (Same class as the cc-reaper
#         self-overlap already fixed in this repo.)
#     (2) The "already running" guard is `pgrep -f "resume <sid>"` — it looks for the claude
#         CHILD, but the spawn chain is launcher → lr-fire-resume.sh → expect → claude. For the
#         seconds that chain takes, NOTHING carries `--resume <sid>`, so the next tick sees "not
#         running" and fires a second one.
#   Fix (1) = a skip-not-queue lock whose holder identity is pid+lstart (`kill -0` alone wedges
#   forever on a recycled pid). Fix (2) = a TTL-bounded claim written BEFORE the spawn.
#
# Isolation: hermetic $HOME; the lock dir is redirected via LR_POLLER_LOCK_DIR; the claim helpers
# are sed-extracted and sourced (mirrors tests/handoff-selfclose.bats' unit technique).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed"
  export LR_POLLER_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  LOG="$STATE/poller.log"
  # A pid that CANNOT exist (macOS pid_max is 99999) — a deterministic "dead holder" with no
  # spawn/kill fixture. The spawn-then-kill idiom is what flaked land-lock.bats (debc016): under
  # bats errexit the sleep may already have exited, `kill` returns 1, and the test dies.
  DEAD_PID=999999
}

teardown() { [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null; true; }

_lstart_of() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' '; }

# A parked session is what makes a tick OBSERVABLE: an unlocked tick logs CONSOLIDATED + LISTED
# for it. Without this seed every "did no work" assertion is vacuous — an empty HOME produces an
# empty log whether the tick ran or skipped (the trap tests/bats negative assertions fall into).
_seed_parked() {
  printf '{"sid":"%s","acct":"next","cfg":"%s/.claude-next","cwd":"%s","reset_at_utc":"2020-01-01T00:00:00Z"}\n' \
    "076a1186-dead-beef-0000-000000000000" "$HOME" "$BATS_TEST_TMPDIR" \
    > "$STATE/parked/076a1186-dead-beef-0000-000000000000.json"
}

# ── LO1: a live holder makes the tick SKIP (not queue, not run) ───────────────────────────
@test "LO1: a tick whose lock is held by a LIVE holder exits 0 and does NO work" {
  _seed_parked
  sleep 60 & HOLDER_PID=$!
  mkdir -p "$LR_POLLER_LOCK_DIR"
  echo "$HOLDER_PID" > "$LR_POLLER_LOCK_DIR/pid"
  _lstart_of "$HOLDER_PID" > "$LR_POLLER_LOCK_DIR/lstart"
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  # the discriminator: an UNLOCKED tick logs CONSOLIDATED/LISTED for the seeded session
  [ ! -s "$LOG" ]
  [ -f "$LR_POLLER_LOCK_DIR/pid" ]                  # holder's lock left intact
  [ "$(cat "$LR_POLLER_LOCK_DIR/pid")" = "$HOLDER_PID" ]
}

# ── LO1b: the same tick, WITHOUT a holder, provably does the work LO1 asserts is skipped ──
# Pins LO1's discriminator: if this ever stops logging, LO1 silently becomes vacuous again.
@test "LO1b: control — an unheld tick DOES process the seeded session" {
  _seed_parked
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  [ -s "$LOG" ]
  grep -q "076a1186" "$LOG"
}

# ── LO2: a DEAD holder's lock is stolen, not obeyed forever ───────────────────────────────
@test "LO2: a stale lock (dead holder pid) is stolen and the tick proceeds" {
  _seed_parked
  mkdir -p "$LR_POLLER_LOCK_DIR"
  echo "$DEAD_PID" > "$LR_POLLER_LOCK_DIR/pid"
  echo "Mon Jan  1 00:00:00 2020" > "$LR_POLLER_LOCK_DIR/lstart"
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  [ -s "$LOG" ]                                     # it PROCEEDED (positive proof, not "no dir")
  grep -q "076a1186" "$LOG"
}

# ── LO3: PID REUSE — a live pid with a DIFFERENT lstart is stale, not a holder ────────────
# This is the whole reason identity is pid+lstart: `kill -0` alone would see "alive" and wedge
# the poller out of every future tick once a pid got recycled.
@test "LO3: a recycled pid (alive, wrong lstart) does NOT hold the lock" {
  sleep 60 & HOLDER_PID=$!
  mkdir -p "$LR_POLLER_LOCK_DIR"
  echo "$HOLDER_PID" > "$LR_POLLER_LOCK_DIR/pid"
  echo "Mon Jan  1 00:00:00 2020" > "$LR_POLLER_LOCK_DIR/lstart"   # same pid, different start
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  [ "$(cat "$LR_POLLER_LOCK_DIR/lstart" 2>/dev/null)" != "Mon Jan  1 00:00:00 2020" ]
}

# ── LO4: the lock is released on exit (a tick never wedges the next one) ──────────────────
# Seeded with a DEAD holder so the assertion is real: the pre-existing dir must be GONE at exit.
# (Asserting "no dir" on a bare run is vacuous — an unlocked poller never creates one.)
@test "LO4: a tick steals a dead holder's lock and RELEASES it on exit" {
  mkdir -p "$LR_POLLER_LOCK_DIR"
  echo "$DEAD_PID" > "$LR_POLLER_LOCK_DIR/pid"
  echo "Mon Jan  1 00:00:00 2020" > "$LR_POLLER_LOCK_DIR/lstart"
  run bash "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$LR_POLLER_LOCK_DIR" ]                    # trap fired — next tick is never wedged
}

# ── the FIRE CLAIM units ──────────────────────────────────────────────────────────────────
_load_claim_helpers() {
  CLAIMS="$BATS_TEST_TMPDIR/claims"; mkdir -p "$CLAIMS"
  CLAIM_TTL_MIN=15
  H="$BATS_TEST_TMPDIR/claim-helpers.sh"
  sed -n '/^sid_claimed() {/,/^}/p;/^claim_sid() {/,/^}/p' "$POLLER" > "$H"
  # shellcheck disable=SC1090
  . "$H"
}

@test "LC1: no claim ⇒ sid_claimed is false" {
  _load_claim_helpers
  # The helpers must EXIST — otherwise "command not found" (127) satisfies a bare `-ne 0`
  # and this negative assertion silently passes against a poller that has no claim at all.
  declare -F sid_claimed >/dev/null
  declare -F claim_sid   >/dev/null
  run sid_claimed "076a1186"
  [ "$status" -ne 0 ]
}

@test "LC2: claim_sid reserves the sid — a following tick sees it as claimed" {
  _load_claim_helpers
  claim_sid "076a1186"
  run sid_claimed "076a1186"
  [ "$status" -eq 0 ]
}

@test "LC3: an EXPIRED claim is reclaimable and is cleaned up (a failed spawn never wedges recovery)" {
  _load_claim_helpers
  claim_sid "076a1186"
  touch -t "$(date -v-40M +%Y%m%d%H%M 2>/dev/null || date -d '40 minutes ago' +%Y%m%d%H%M)" "$CLAIMS/076a1186"
  run sid_claimed "076a1186"
  [ "$status" -ne 0 ]
  [ ! -f "$CLAIMS/076a1186" ]
}

@test "LC4: a claim for one sid never masks a different sid" {
  _load_claim_helpers
  declare -F sid_claimed >/dev/null
  claim_sid "076a1186"
  run sid_claimed "a3f68174"
  [ "$status" -ne 0 ]
  [ -f "$CLAIMS/076a1186" ]        # …and the unrelated claim is untouched
}
