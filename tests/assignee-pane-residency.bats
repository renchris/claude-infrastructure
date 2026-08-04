#!/usr/bin/env bats
# shellcheck shell=bash
#   bats files are bash with @test sugar and shellcheck has no bats mode, so the shell is declared
#   explicitly (SC1008). Without it shellcheck ABORTS on the file and reports zero findings — a lint
#   that cannot parse its subject is SILENT, not clean (memory: lint-blindness-composes).
#
# assignee-pane-residency.bats — does the close path move the WORLD?
#
# What this suite is FOR. Four fixes to the assignee self-close chain each went green on the
# mechanism they named and moved the outcome by zero, because every one was measured against a
# defer-reason or an internal predicate. The subject measures panes instead, joined from three
# sources that do not depend on each other. So the properties worth pinning are not "it runs" but:
#
#   · a pile of residents with nothing departing is ALARM, and the SAME parser says OK when things
#     actually leave (the arms are twins — one fixture apart);
#   · "no teams ran" is a DISTINCT verdict from "the fix worked" (they rendered identically before,
#     which is half of why nine days passed in silence);
#   · a departure nobody can attribute is NOT ours (six panes really were closed by the vendor with
#     zero lifecycle lines — the first departure this instrument sees must not be mistaken for
#     proof);
#   · every source going blind is NO-DATA, never "they all left".
#
# EVERY ARM HAS ITS TWIN. An assertion that cannot fail proves nothing, and the way this class of
# instrument fails is by reaching the right verdict for the wrong reason — so where a verdict is
# reachable two ways (WARN is), the COUNTS are asserted too, not just the word.
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]`/`(( ))` is errexit-EXEMPT under bats and
# therefore a DEAD assertion (memory: bats-dead-assertions-errexit-exemptions). Negative assertions
# are written as an `if grep -q … then false fi` block, never `! grep -q …`
# (scripts/bats-assert-liveness.py blocks the land at exit 6 on the latter).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/assignee-pane-residency.sh"
  D="$BATS_TEST_TMPDIR"
  # Fixture HOME + an explicit team glob, so the suite can never read — or be swayed by — the
  # operator's live fleet. A residency verdict that changes with what the box happens to be running
  # is not a test result.
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs"
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that, so an unpinned suite would go red-by-LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_RESIDENCY_STATE_DIR="$D/state"
  export CC_RESIDENCY_TEAM_GLOB="$D/teams/*/config.json"
  export TEAMMATE_LIFECYCLE_LOG="$D/lifecycle.log"
  mkdir -p "$D/teams/session-aa"; : > "$TEAMMATE_LIFECYCLE_LOG"

  # Stub the two EXTERNAL reads only. The join, the set difference, the attribution and the verdict
  # are the production code paths verbatim — a control that exercises different code than
  # production proves nothing about production (memory: control-must-replay-the-real-artifact).
  printf '#!/bin/bash\ncat "%s/wins" 2>/dev/null || true\n' "$D" > "$D/it2"; chmod +x "$D/it2"
  printf '#!/bin/bash\ncat "%s/procs" 2>/dev/null || true\n' "$D" > "$D/ps";  chmod +x "$D/ps"
  export CC_RESIDENCY_IT2_BIN="$D/it2" CC_RESIDENCY_PS_BIN="$D/ps"
  # The process table always has SOMETHING in it, so the default fixture carries one unrelated
  # process. An empty `ps` is not "no assignees are running" — it is a failed read, and the subject
  # reports it as `unreachable` on purpose. A fixture that left it empty would silently exercise the
  # blindness path in tests that mean to exercise the join.
  : > "$D/wins"; echo "/sbin/launchd" > "$D/procs"
  OLD_MS=$(( ($(date +%s) - 86400) * 1000 ))   # joined a day ago ⇒ past the 4h staleness floor
}

# seed <n> — n declared members with INTEGER (kitty) panes 401.., all joined a day ago.
seed() {
  local n="$1" i j=""
  # `seq`, not `for (( ))` — scripts/bats-assert-liveness.py reads an arithmetic for-header as a
  # DEAD assertion and blocks the land at exit 6 (already paid for once, 287fc0ed).
  #
  # ⚠ The n=0 guard is REQUIRED, and its absence is not a no-op. `for (( i=0; i<0; i++ ))` runs zero
  # times; `seq 0 -1` counts DOWNWARD and emits `0` and `-1`. Swapping one idiom for the other
  # turned `live 0` into "panes 401 and 400 are alive", which silently cost this suite its
  # twelve-departures control — it read eleven and failed one arm.
  [ "$n" -gt 0 ] || { printf '{"name":"session-aa","members":[]}\n' > "$D/teams/session-aa/config.json"; return 0; }
  for i in $(seq 0 $((n - 1))); do
    [ -n "$j" ] && j="$j,"
    j="$j{\"name\":\"m$i\",\"tmuxPaneId\":\"$((401+i))\",\"joinedAt\":$OLD_MS}"
  done
  printf '{"name":"session-aa","members":[%s]}\n' "$j" > "$D/teams/session-aa/config.json"
}
# live <n> — the FIRST n panes are still in the window list, so m<n>..m11 are the ones that left.
# Which ones depart is not cosmetic: an attribution fixture that closes members still on screen
# tests nothing, and reads as a code defect. It cost a debugging cycle here.
live() { local i n="$1"; : > "$D/wins"; [ "$n" -gt 0 ] || return 0   # see seed(): `seq 0 -1` is NOT empty
         for i in $(seq 0 $((n - 1))); do echo $((401+i)) >> "$D/wins"; done; }
# closed <i> — our chain claims pane 401+i, naming BOTH the pane and the member.
closed() { echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✓ closed pane $((401+$1)) (m$1)" >> "$TEAMMATE_LIFECYCLE_LOG"; }
# seat — take a first sample so a cursor exists to difference against.
seat() { run "$S" --quiet; }
tok() { printf '%s\n' "$output" | sed -n 's/.*\(verdict=.*\)/\1/p' | tail -1; }
field() { printf '%s\n' "$output" | sed -n "s/.*[ ]$1=\([0-9][0-9]*\).*/\1/p" | tail -1; }

@test "embedded selftest passes end to end" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "selftest: all pass"
}

# ── the two arms that carry the whole file ────────────────────────────────────────────────────────

@test "residents past the threshold with nothing departing is ALARM (exit 2)" {
  seed 12; live 12; seat
  run "$S"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "verdict=ALARM"
  [ "$(field stale)" -eq 12 ]
  [ "$(field departed)" -eq 0 ]
}

# THE TWIN. Same subject, same parser, one fixture apart — the panes actually leave and our log can
# account for them. If this ever agrees with the arm above, the instrument is not reading the world.
@test "the same fleet with attributed departures is OK (exit 0) — the positive control" {
  seed 12; live 12; seat
  local i; for i in 0 1 2 3 4 5 6 7 8 9 10 11; do closed "$i"; done
  live 0
  run "$S"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict=OK"
  [ "$(field ours)" -eq 12 ]
  [ "$(field vendor)" -eq 0 ]
}

# ── attribution: a departure is not automatically ours ────────────────────────────────────────────
# Team session-57342265 had six members closed and de-registered with ZERO lifecycle lines while its
# lead stayed alive. If those counted as ours, the FIRST departure this alarm ever saw would read as
# proof the fix worked — the original error in a new coat.
@test "a departure with no matching lifecycle line is UNATTRIBUTED, never ours" {
  seed 12; live 12; seat
  live 6                                   # six vanish; the log says nothing about any of them
  run "$S"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "verdict=WARN"
  [ "$(field departed)" -eq 6 ]
  [ "$(field ours)" -eq 0 ]
  [ "$(field vendor)" -eq 6 ]
  echo "$output" | grep -q "UNATTRIBUTED"
}

# THE TWIN of the arm above: the identical six departures, now each with a `✓ closed pane <pane>
# (<name>)` line. Same world, opposite attribution — that difference is the only thing separating
# "our chain works" from "something else closed them".
@test "the SAME six departures WITH lifecycle lines are attributed to us" {
  seed 12; live 12; seat
  # `live 6` keeps 401..406, so m6..m11 are the ones that leave — those are the members whose closes
  # the log must claim. Same world as the arm above; only the log differs.
  local i; for i in 6 7 8 9 10 11; do closed "$i"; done
  live 6
  run "$S"
  [ "$(field departed)" -eq 6 ]
  [ "$(field ours)" -eq 6 ]
  [ "$(field vendor)" -eq 0 ]
}

# Attribution must match the MEMBER, not merely the fact that something closed. A close line naming
# a different pane cannot launder a departure — otherwise one real close would exonerate a whole
# stalled fleet.
@test "a close line naming a DIFFERENT pane does not attribute this departure" {
  seed 12; live 12; seat
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✓ closed pane 999 (someone-else)" >> "$TEAMMATE_LIFECYCLE_LOG"
  live 6
  run "$S"
  [ "$(field ours)" -eq 0 ]
  [ "$(field vendor)" -eq 6 ]
}

# ── NOT-EXERCISED is a verdict, not a quiet OK ────────────────────────────────────────────────────

@test "no teams at all is NOT-EXERCISED — distinctly, and it is not OK" {
  rm -f "$D/teams/session-aa/config.json"
  run "$S"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict=NOT-EXERCISED"
  [ "$(field members)" -eq 0 ]
  # The whole point: "no teams ran" and "the fix worked" must not render identically. They did, and
  # that is half of why a nine-day outage was never noticed.
  if printf '%s\n' "$output" | grep -q "verdict=OK"; then
    echo "unexpected verdict=OK on a box that ran no teams" >&2; false
  fi
}

# A member with an in-process lead pane ("leader") or an iTerm2 UUID is not the population this file
# tracks. Counting them would put the lead itself in the stale pile, and the lead is never reaped.
@test "only INTEGER panes count — 'leader' and UUIDs are not assignee panes" {
  cat > "$D/teams/session-aa/config.json" <<EOF
{"name":"session-aa","members":[
  {"name":"team-lead","tmuxPaneId":"leader","joinedAt":$OLD_MS},
  {"name":"itermish","tmuxPaneId":"52DF86C3-A1F2-43D0-AEF8-DC88FED9D286","joinedAt":$OLD_MS}]}
EOF
  run "$S"
  [ "$(field members)" -eq 0 ]
  echo "$output" | grep -q "verdict=NOT-EXERCISED"
}

# A member young enough to still be working is not evidence of anything. Without this the alarm
# would fire on every healthy fleet the moment it spawned MIN_EVENTS teammates.
@test "young residents are not stale — a busy fleet must not drift toward ALARM" {
  local now_ms; now_ms=$(( $(date +%s) * 1000 ))
  local i j=""
  for i in $(seq 0 11); do
    [ -n "$j" ] && j="$j,"
    j="$j{\"name\":\"m$i\",\"tmuxPaneId\":\"$((401+i))\",\"joinedAt\":$now_ms}"
  done
  printf '{"name":"session-aa","members":[%s]}\n' "$j" > "$D/teams/session-aa/config.json"
  live 12; seat
  run "$S"
  [ "$status" -eq 0 ]
  [ "$(field resident)" -eq 12 ]
  [ "$(field stale)" -eq 0 ]
  echo "$output" | grep -q "verdict=NOT-EXERCISED"
}

# ── the first sample, and the cursor ──────────────────────────────────────────────────────────────
# A lookup miss is not an absence (memory: lookup-miss-is-not-absence). With no previous resident
# set, `departed` is UNKNOWN — reading it as zero would let the very first run ALARM on a fleet that
# is closing panes perfectly well.
@test "the first sample asserts nothing — departures are UNKNOWN, not zero" {
  seed 12; live 12
  run "$S"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict=NOT-EXERCISED"
  echo "$output" | grep -q "prev=none"
  if printf '%s\n' "$output" | grep -q "verdict=ALARM"; then
    echo "unexpected ALARM on a first sample with no cursor" >&2; false
  fi
}

# Departure is a SET DIFFERENCE, not a count delta. A count delta cancels a real departure against a
# fresh spawn and reports "nothing happened" — the shape live today at bin/cc-reaper:639.
@test "departure is a set difference: one leaves, one arrives, and that is 1 departure not 0" {
  seed 12; live 12; seat
  # m0 leaves; a brand-new m12 arrives on pane 413. A count delta reads 12 → 12 = no change.
  seed 13
  : > "$D/wins"; local i; for i in $(seq 1 12); do echo $((401+i)) >> "$D/wins"; done
  run "$S"
  [ "$(field departed)" -eq 1 ]
  [ "$(field resident)" -eq 12 ]
}

@test "--no-state reads the cursor without advancing it" {
  seed 12; live 12; seat
  local before; before="$(cat "$CC_RESIDENCY_STATE_DIR/assignee-residency.state")"
  live 6
  run "$S" --no-state
  [ "$(field departed)" -eq 6 ]
  echo "$output" | grep -q "state=skipped"
  [ "$(cat "$CC_RESIDENCY_STATE_DIR/assignee-residency.state")" = "$before" ]
  # And the very next reader still sees the same six — the cursor was genuinely not consumed.
  run "$S" --no-state
  [ "$(field departed)" -eq 6 ]
}

# ── blindness is not departure ────────────────────────────────────────────────────────────────────
# The most dangerous false reading this file can make: reporting zero residents because it could not
# look, which renders as "they all left" and therefore as "the fix worked".
@test "every source blind is NO-DATA (exit 3) — residency is UNKNOWN, never zero" {
  seed 12; live 12; seat
  printf '#!/bin/bash\nexit 1\n' > "$D/it2"
  printf '#!/bin/bash\nexit 1\n' > "$D/ps"
  run "$S"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "verdict=NO-DATA"
  if printf '%s\n' "$output" | grep -qE "verdict=(OK|ALARM)"; then
    echo "unexpected verdict asserted while both sources were blind" >&2; false
  fi
}

# The union, not the intersection. One blind source must not manufacture departures: the process
# table alone is enough to prove a member is still here.
@test "the process table alone keeps a member resident when the window list goes blind" {
  seed 12; live 12; seat
  printf '#!/bin/bash\nexit 1\n' > "$D/it2"          # window list unreachable
  local i; : > "$D/procs"
  for i in $(seq 0 11); do echo "claude --agent-id m$i@session-aa --agent-name m$i" >> "$D/procs"; done
  run "$S"
  [ "$(field resident)" -eq 12 ]
  [ "$(field departed)" -eq 0 ]
  echo "$output" | grep -q "src_win=unreachable"
}

# ── the contract other things read ────────────────────────────────────────────────────────────────

@test "the verdict token is greppable without re-deriving anything" {
  seed 12; live 12; seat
  run "$S" --quiet
  # --quiet still emits the token: a consumer that has to parse a human report is a second parser.
  [ -n "$(tok)" ]
  echo "$output" | grep -qE "^verdict=[A-Z-]+ members=[0-9]+ resident=[0-9]+ stale=[0-9]+ departed=[0-9]+ ours=[0-9]+ vendor=[0-9]+ "
  run bash -c "'$S' --quiet | grep -o 'verdict=[A-Z-]*'"
  [ "$output" = "verdict=ALARM" ]
}

# The token carries the verdict in TEXT, so a caller that swallows the exit status still cannot
# launder it (memory: claimed-outcome-vs-checked-outcome — a `|| true` plus a damping marker on the
# fake success DELETES the message).
@test "a caller's || true cannot launder an ALARM" {
  seed 12; live 12; seat
  run bash -c "'$S' --quiet || true"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict=ALARM"
}

@test "json carries the world figures" {
  seed 12; live 12; seat
  run "$S" --json
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '"verdict":"ALARM"'
  echo "$output" | grep -q '"stale":12'
  echo "$output" | grep -q '"ours":0'
}

# ── read-only by construction ─────────────────────────────────────────────────────────────────────
# The subject samples a fleet of live operator panes. An actuator verb reaching this file would be a
# reaper wearing a sensor's name, and the blast radius is the operator's own windows.
@test "it closes no pane and writes no team config — no actuator verbs in the subject" {
  if grep -nE "session close|kill -9|pkill|handoff-fire|it2-kitty close|@ close-window" "$S"; then
    echo "an actuator verb appears in a read-only sampler" >&2; false
  fi
  # `it2` is called exactly once, and only for `session list`.
  run bash -c "grep -oE '\\\$IT2_BIN\" [a-z]+ [a-z]+' '$S' | sort -u"
  [ "$output" = '$IT2_BIN" session list' ]
}

# The ONLY file it may write is its own cursor. Anything under a team dir or a worktree would make a
# sampler into a mutator of the thing it samples.
@test "the only file written is the residency cursor" {
  seed 12; live 12
  run "$S"
  [ -f "$CC_RESIDENCY_STATE_DIR/assignee-residency.state" ]
  # The team config is byte-identical after sampling.
  run bash -c "cksum '$D/teams/session-aa/config.json'"
  local after="$output"
  run "$S"
  run bash -c "cksum '$D/teams/session-aa/config.json'"
  [ "$output" = "$after" ]
}
