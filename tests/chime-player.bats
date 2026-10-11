#!/usr/bin/env bats
# chime-player.js — the ONE resident coreaudiod client hooks/notify.sh enqueues chimes to (2026-10-10).
#
# WHY THIS SUITE EXISTS: a fresh afplay per chime is a new coreaudiod client and costs 3 TCC permission
# checks inside coreaudiod; one long-lived player paid 0 per play after its first (measured from
# coreaudiod's log). The player's whole value is in what it REFUSES to do, so every case below pins a
# refusal or a bound on its real outputs: what it would have played, what is left in the spool, and
# the heartbeat notify.sh keys on.
#
# HERMETIC AND SILENT: the REAL script runs under the real /usr/bin/osascript, with CC_CHIME_DRYRUN set,
# so a "play" appends "<epoch> <path>" to a file and no NSSound is ever created — no audio client is
# opened by this suite. The spool is a per-test temp dir (CC_CHIME_DIR), never the live one.
# Every player is started in the background, waited on with a bounded poll, and killed in teardown.
#
# RED-proof: each case was run against a scratch copy of the .js with exactly its behavior removed
# (no stale check, no allow-list, no delete, no heartbeat, no backlog cap) and went red. Also red,
# 2026-10-10 review: STALE_S 10 -> 50 (the stale case's request is 13 s old, not 60) and ALLOWED cut
# to Sounds/ only (the allow-list case plays a ScreenReader sound).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="${CHIME_PLAYER_JS:-$REPO/scripts/chime-player.js}"
  B="$BATS_TEST_TMPDIR/cc-chime"; mkdir -p "$B/spool"
  PLAYED="$BATS_TEST_TMPDIR/played"
  ERR="$BATS_TEST_TMPDIR/player.err"
  PLAYER_PID=""
  S=/System/Library/Sounds
}

teardown() {
  if [ -n "$PLAYER_PID" ]; then kill "$PLAYER_PID" 2>/dev/null || true; fi
}

start_player() {
  CC_CHIME_DIR="$B" CC_CHIME_DRYRUN="$PLAYED" CC_CHIME_POLL_S=0.1 \
    /usr/bin/osascript -l JavaScript "$P" >/dev/null 2>"$ERR" 3>&- &
  PLAYER_PID=$!
}

# <shell condition> — poll it every 0.1 s for up to 30 s (osascript start-up is slow on a loaded box).
wait_for() {
  local i=0
  while [ $i -lt 300 ]; do
    if eval "$1"; then return 0; fi
    sleep 0.1; i=$((i + 1))
  done
  echo "timed out waiting for: $1"; cat "$ERR" 2>/dev/null; return 1
}

req() {          # <name> <sound path> [<seconds old>]
  printf '%s\n' "$2" > "$B/spool/$1.req"
  if [ -n "${3:-}" ]; then touch -t "$(date -r $(( $(date +%s) - $3 )) +%Y%m%d%H%M.%S)" "$B/spool/$1.req"; fi
}
plays() { cut -d' ' -f2- "$PLAYED" 2>/dev/null || true; }
left() { local n=0 f; for f in "$B"/spool/*.req; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

@test "a fresh request plays exactly once and its request file is deleted" {
  req 1000.1 "$S/Pop.aiff"
  start_player
  wait_for '[ -s "$PLAYED" ]'
  # A second request proves later passes RAN, so "once" is a count over passes, not over one pass.
  req 1000.2 "$S/Glass.aiff"
  wait_for 'grep -q Glass "$PLAYED"'
  [ "$(plays | grep -c Pop.aiff)" = 1 ]
  [ "$(head -1 "$PLAYED" | cut -d' ' -f2)" = "$S/Pop.aiff" ]
  [ "$(left)" = 0 ]
}

@test "a request older than 10 s is deleted UNPLAYED (no burst of old chimes after a stall)" {
  # 13 s, not a minute: just over the 10 s line, so a looser cutoff (say 30 s) replays it and goes red.
  # The fresh one still plays — osascript starts in ~0.1 s, nowhere near the 3 s of headroom.
  req 1000.1 "$S/Basso.aiff" 13
  req 1000.2 "$S/Glass.aiff"
  start_player
  wait_for 'grep -q Glass "$PLAYED"'
  [ "$(plays)" = "$S/Glass.aiff" ]
  [ "$(left)" = 0 ]
  grep -q 'dropped 1000.1.req (stale' "$ERR"
}

@test "a path outside the allowed sound dirs is dropped, including a ../ escape; the ScreenReader dir plays" {
  # notify.sh plays from two dirs: Sounds/ for most events, ScreenReader's for elicitation. Narrowing
  # the allow-list to one would silently drop every MCP-input chime while notify.sh logs `via player`.
  SR=/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/Sounds
  [ -r "$SR/BubbleAppear.aiff" ]                   # the fixture is real on this macOS, not assumed
  # Three requests, not four: past KEEP=3 the oldest is dropped as backlog, never reaching this check.
  # Every other case plays from Sounds/, so this one carries the ScreenReader dir.
  req 1000.1 /etc/hosts
  req 1000.2 "$S/../../../etc/hosts"
  req 1000.3 "$SR/BubbleAppear.aiff"
  start_player
  wait_for 'grep -q BubbleAppear "$PLAYED"'
  [ "$(plays)" = "$SR/BubbleAppear.aiff" ]
  [ "$(left)" = 0 ]
  [ "$(grep -c 'not an allowed sound' "$ERR")" = 2 ]
}

@test "the heartbeat is created and kept fresh" {
  start_player
  wait_for '[ -f "$B/heartbeat" ]'
  touch -t 202001010000 "$B/heartbeat"
  wait_for '[ $(( $(date +%s) - $(stat -f %m "$B/heartbeat") )) -le 5 ]'
}

@test "a backlog of 6 plays only the newest 3, in order, and empties the spool" {
  n=1; for s in Basso Blow Bottle Frog Funk Glass; do req "1000.$n" "$S/$s.aiff"; n=$((n + 1)); done
  start_player
  wait_for '[ "$(left)" = 0 ] && grep -q Glass "$PLAYED"'
  [ "$(plays | tr '\n' ' ')" = "$S/Frog.aiff $S/Funk.aiff $S/Glass.aiff " ]
  [ "$(grep -c '(backlog)' "$ERR")" = 3 ]
}
