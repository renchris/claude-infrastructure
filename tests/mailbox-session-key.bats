#!/usr/bin/env bats
# mailbox-session-key.bats — v2 M1 (session-keyed addressing + pane alias trail) and
# M4 (pull-adoption from a provably-dead predecessor).
# Design: docs/plans/CROSS_SESSION_COMMS_V2.md §4 M1/M4 · acceptance A2-A5, A8.
#
# HERMETIC: $HOME is fixtured (scripts/test-hermeticity-lint.sh enforces this at the land gate —
# a suite that runs against the operator's live ~/ contaminates every other result).
#
# BATS ERREXIT DISCIPLINE (memory bats-dead-assertions-errexit-exemptions): a non-final `[[ ]]`,
# `(( ))`, `!` or `A && B` is errexit-EXEMPT and therefore a DEAD assertion. Every such assertion
# here carries `|| false`. `[ ]` as the final command in a body is live and needs no suffix.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"          # ← hermeticity: fixtured $HOME
  export CC_MAILBOX_DIR="$HOME/.claude/mailbox"
  mkdir -p "$CC_MAILBOX_DIR"
  # The kitty-start gate reads $KITTY_PID, and a run from a kitty pane inherits the operator's. Pinned
  # off so every test starts with the kitty UNKNOWN (no gate); the KITTY GATE tests set it themselves.
  unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID
  # shellcheck disable=SC1091
  . "$REPO/hooks/lib/mailbox-pending.sh"
  PANE_A="AAAAAAAA-1111-2222-3333-444444444444"
  PANE_B="BBBBBBBB-1111-2222-3333-444444444444"
  SESS_1="11111111-AAAA-BBBB-CCCC-000000000001"
  SESS_2="22222222-AAAA-BBBB-CCCC-000000000002"
  SESS_3="33333333-AAAA-BBBB-CCCC-000000000003"
}

# ── M1: the alias trail ──────────────────────────────────────────────────────────────────────────

@test "M1 alias: write then resolve gives the session, not the pane" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_1" ]
}

@test "M1 alias: an unaliased pane echoes ITSELF (callers pipe unconditionally)" {
  [ "$(mailbox_alias_of "$PANE_B")" = "$PANE_B" ]
}

@test "M1 alias: repeated boundaries DEDUP — one line per occupancy, not per turn" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do mailbox_alias_write "$PANE_A" "$SESS_1"; done
  run grep -c '' "$CC_MAILBOX_DIR/.alias/$PANE_A"
  [ "$output" = "1" ]
}

@test "M1 alias: a new session on the same pane APPENDS (history preserved, never rewritten)" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  run grep -c '' "$CC_MAILBOX_DIR/.alias/$PANE_A"
  [ "$output" = "2" ]
  # tip is the CURRENT occupant; the predecessor is still on disk
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
  grep -q "$SESS_1" "$CC_MAILBOX_DIR/.alias/$PANE_A" || false
}

@test "M1 alias: trail is newest-first" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  mailbox_alias_write "$PANE_A" "$SESS_3"
  run mailbox_alias_trail "$PANE_A"
  [ "$(printf '%s\n' "$output" | head -1)" = "$SESS_3" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "$SESS_1" ]
}

@test "M1 alias: a self-alias is refused (carries no information)" {
  run mailbox_alias_write "$PANE_A" "$PANE_A"
  [ "$status" -eq 1 ]
}

# ── M1: resolution — THE incident (same session, new pane) ───────────────────────────────────────

@test "M1 RESUME INTO A NEW PANE loses nothing — the 2026-07-29 incident" {
  # session 1 first lives in pane A and receives mail there
  mailbox_alias_write "$PANE_A" "$SESS_1"
  printf '2026-07-29T10:00:00-0700 [peer] a seam ruling you asked for\n' \
    >> "$CC_MAILBOX_DIR/$(mailbox_resolve_key "$PANE_A").md"
  # …then is RESUMED into pane B (same session id, new container)
  mailbox_alias_write "$PANE_B" "$SESS_1"
  # a sender still addressing the OLD pane must reach the same box the session reads
  [ "$(mailbox_resolve_key "$PANE_A")" = "$SESS_1" ]
  [ "$(mailbox_resolve_key "$PANE_B")" = "$SESS_1" ]
  run mailbox_lines "$SESS_1"
  [ "$output" = "1" ]
  grep -q "seam ruling" "$CC_MAILBOX_DIR/$SESS_1.md" || false
}

@test "M1 resolve: a session-keyed sender is IDEMPOTENT (no double-resolution)" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  [ "$(mailbox_resolve_key "$SESS_1")" = "$SESS_1" ]
}

@test "M1 resolve: an unaliased pane still resolves to ITSELF — no regression" {
  printf 'x\n' >> "$CC_MAILBOX_DIR/$PANE_B.md"
  [ "$(mailbox_resolve_key "$PANE_B")" = "$PANE_B" ]
}

@test "M1 KILL SWITCH CC_MBX_SESSION_KEY=0 reproduces pane-keyed behaviour exactly" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  [ "$(mailbox_resolve_key "$PANE_A")" = "$SESS_1" ]        # ON  → session
  CC_MBX_SESSION_KEY=0
  export CC_MBX_SESSION_KEY
  [ "$(mailbox_resolve_key "$PANE_A")" = "$PANE_A" ]        # OFF → pane, verbatim today
}

# ── M4: pull-adoption, and the guard that makes it safe ──────────────────────────────────────────

@test "M4 adopts from a predecessor that shared my pane and is nowhere current" {
  mailbox_alias_write "$PANE_A" "$SESS_1"      # predecessor (crashed — wrote no .forward)
  mailbox_alias_write "$PANE_A" "$SESS_2"      # me, now on the same pane
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2"
  [ "$status" -eq 0 ]
  [ "$output" = "$SESS_1" ]
}

@test "M4 REFUSES a predecessor that RESUMED ELSEWHERE and is still live" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"      # I take pane A
  mailbox_alias_write "$PANE_B" "$SESS_1"      # …but SESS_1 resumed into pane B and is ALIVE
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# POSITIVE CONTROL for the refusal above (memory absence-alarm-needs-evidence): the same fixture
# minus the resume MUST yield an adoption. Without this, a bug that returned nothing unconditionally
# would pass the refusal test and the mechanism would be silently dead.
@test "M4 positive control: identical fixture WITHOUT the resume DOES adopt" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2"
  [ "$output" = "$SESS_1" ]
}

@test "M4 never adopts from itself" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_1"
  [ -z "$output" ]
}

@test "M4 is BOUNDED by CC_MBX_ALIAS_MAX_PRED (a hook does no unbounded work)" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  mailbox_alias_write "$PANE_A" "$SESS_3"
  mailbox_alias_write "$PANE_A" "44444444-AAAA-BBBB-CCCC-000000000004"
  CC_MBX_ALIAS_MAX_PRED=2
  export CC_MBX_ALIAS_MAX_PRED
  run mailbox_adoptable_predecessors "$PANE_A" "44444444-AAAA-BBBB-CCCC-000000000004"
  [ "$(printf '%s\n' "$output" | grep -c '')" = "2" ]
  # newest-first ordering means the bound keeps the MOST RECENT predecessors
  [ "$(printf '%s\n' "$output" | head -1)" = "$SESS_3" ]
}

@test "M4 end-to-end: a crashed predecessor's mail reaches the successor with NO .forward" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  printf '2026-07-29T10:00:00-0700 [peer] mail the crashed session never read\n' \
    >> "$CC_MAILBOX_DIR/$SESS_1.md"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  # no .forward exists anywhere — this is the 96.7% case the push-pointer never reached
  [ ! -f "$CC_MAILBOX_DIR/$SESS_1.forward" ]
  for p in $(mailbox_adoptable_predecessors "$PANE_A" "$SESS_2"); do
    mailbox_migrate "$p" "$SESS_2" >/dev/null
  done
  grep -q "mail the crashed session never read" "$CC_MAILBOX_DIR/$SESS_2.md" || false
}

@test "M4 adoption is EXACTLY-ONCE — re-running on every SessionStart is a no-op" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  printf '2026-07-29T10:00:00-0700 [peer] one message\n' >> "$CC_MAILBOX_DIR/$SESS_1.md"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  for _ in 1 2 3; do
    for p in $(mailbox_adoptable_predecessors "$PANE_A" "$SESS_2"); do
      mailbox_migrate "$p" "$SESS_2" >/dev/null 2>&1 || true
    done
  done
  run mailbox_lines "$SESS_2"
  [ "$output" = "1" ]
}

@test "M4 KILL SWITCH: CC_MBX_PULL_ADOPT=0 is honored by the drain hook" {
  # The switch is read by the CALLER (hooks/mailbox-drain.sh), so drive the real hook. A grep for the
  # name cannot see this: it also sits in a comment there, and a kill switch that exists only in a
  # comment is not a kill switch. Both arms share one fixture — a crashed predecessor on my pane.
  mailbox_alias_write "$PANE_A" "$SESS_1"
  printf '2026-07-29T10:00:00-0700 [peer] mail for a crashed predecessor\n' >> "$CC_MAILBOX_DIR/$SESS_1.md"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  drain() { printf '{"session_id":"%s"}' "$SESS_2" \
    | env CC_MBX_PULL_ADOPT="$1" CC_PANE_ID="$PANE_A" "$REPO/hooks/mailbox-drain.sh" session-start; }
  run drain 0
  [ "$status" -eq 0 ]
  ! grep -qs 'crashed predecessor' "$CC_MAILBOX_DIR/$SESS_2.md" || false   # not adopted
  grep -q 'crashed predecessor' "$CC_MAILBOX_DIR/$SESS_1.md"                 # still where it was
  # CONTROL: the same fixture at the default switch value DOES adopt, so the arm above is not silent
  # for a harness reason.
  run drain 1
  [ "$status" -eq 0 ]
  grep -q 'crashed predecessor' "$CC_MAILBOX_DIR/$SESS_2.md"
}

# ── liveness proxy ───────────────────────────────────────────────────────────────────────────────

@test "session_is_current: tip of a trail is current, a superseded session is not" {
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  mailbox_session_is_current "$SESS_2" || false
  run mailbox_session_is_current "$SESS_1"
  [ "$status" -eq 1 ]
}

@test "session_is_current: no alias dir at all → nothing is current (fail-safe, no error)" {
  run mailbox_session_is_current "$SESS_1"
  [ "$status" -eq 1 ]
}

# ── TENANCY GATE on the alias write (item 66ec1b04f050) ──────────────────────────────────────────
# A nested `claude` inherits the pane id and, ungated, appends its own dying session as the tip of
# the tenant's trail. The trail is APPEND-ONLY and mailbox_adoptable_predecessors keeps only the 3
# most recent entries, so each such write permanently consumes an adoption slot and pushes a real
# predecessor off the end — its mail is then never adopted, silently.
#
# A LIVE STRICT ANCESTOR is taken from the real process tree rather than mocked: the gate's whole
# point is that it rests on a live kernel fact, so a mocked `ps` would test the mock.
#
# DERIVED INDEPENDENTLY OF THE SUBJECT, and that is not fastidiousness — it is the difference
# between a control and a decoration. Two earlier versions of this fixture were both wrong, in
# opposite ways, and the second was the dangerous one:
#   1. parent-of-$PPID, on the stated premise "there is no `claude` in the bats ancestry". FALSE:
#      this suite normally runs from inside a live Claude Code session, so the subject finds that
#      real claude and walks from ABOVE the pid the test had chosen. The case failed for a reason
#      that had nothing to do with the gate.
#   2. parent-of-_mbx_claude_pid — correct against the fixed tree, and VACUOUS as a red-proof: on a
#      pre-fix tree that function does not exist, so this returned empty, the `skip` below fired,
#      and bats renders a skip as `ok`. The red-proof reported 5/5 green against origin/main — a
#      control that could not fail, reading exactly like one that passed.
# So walk the chain here, in the test, and never call into the subject. No `skip`: an underivable
# ancestor is now a hard failure, because a skip is precisely how this went vacuous.
live_ancestor_pid() { # a pid that is STRICTLY above this process's claude (or above $PPID if none)
  local walk="$$" prev="" chain="" i=0 c
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 20 ]; do
    chain="$chain $walk"
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  # first claude in the chain → its parent is a strict ancestor, one hop up, well inside the
  # subject's 16-hop bound. No claude (CI) → the topmost ancestor, which is above $PPID either way.
  for c in $chain; do
    case "$(ps -o comm= -p "$c" 2>/dev/null | sed 's#.*/##')" in
      claude|claude.exe|claude-*) ps -o ppid= -p "$c" 2>/dev/null | tr -d ' '; return 0 ;;
    esac
    prev="$c"
  done
  printf '%s' "$prev"
}
write_row() { # <pane> <pid>
  mkdir -p "$HOME/.claude/cc-registry"
  printf '{"paneUUID":"%s","name":"t","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"session_id":"s"}' \
    "$1" "$2" > "$HOME/.claude/cc-registry/$1.json"
}

@test "M1 tenancy: a nested session REFUSES to re-point a pane held by a live ancestor" {
  local anc; anc="$(live_ancestor_pid)"
  [ -n "$anc" ] || { echo "could not derive a live ancestor pid — a SKIP here is how this control went vacuous" >&2; false; }
  mailbox_alias_write "$PANE_A" "$SESS_1"          # the real tenant establishes the trail
  write_row "$PANE_A" "$anc"
  run mailbox_alias_write "$PANE_A" "$SESS_2"      # the nested `claude -p`
  [ "$status" -eq 2 ]
  # and the trail is UNCHANGED — the tenant is still the tip
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_1" ]
}

@test "M1 tenancy: negative control — a DEAD pid in the row must NOT refuse the write" {
  # Fail-OPEN is the designed direction: refusing wrongly strands a legitimate tenant's addressing,
  # while allowing wrongly costs one trail entry. Without this control the case above could pass
  # because the gate refuses EVERYTHING that has a row.
  local dead; sleep 1 & dead=$!; kill "$dead" 2>/dev/null || true; wait "$dead" 2>/dev/null || true
  mailbox_alias_write "$PANE_A" "$SESS_1"
  write_row "$PANE_A" "$dead"
  run mailbox_alias_write "$PANE_A" "$SESS_2"
  [ "$status" -eq 0 ]
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
}

@test "M1 tenancy: negative control — NO registry row must NOT refuse the write" {
  # The overwhelmingly common path, and the one every other case in this suite rides on.
  mailbox_alias_write "$PANE_A" "$SESS_1"
  run mailbox_alias_write "$PANE_A" "$SESS_2"
  [ "$status" -eq 0 ]
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
}

@test "M1 tenancy: CC_MBX_ALIAS_TENANCY=0 restores the pre-gate behaviour verbatim" {
  local anc; anc="$(live_ancestor_pid)"
  [ -n "$anc" ] || { echo "could not derive a live ancestor pid — a SKIP here is how this control went vacuous" >&2; false; }
  mailbox_alias_write "$PANE_A" "$SESS_1"
  write_row "$PANE_A" "$anc"
  CC_MBX_ALIAS_TENANCY=0 mailbox_alias_write "$PANE_A" "$SESS_2"
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
}

@test "M1 tenancy: the TENANT's own row must never refuse the tenant's own write" {
  # The real-world common path and the most important non-regression: on an ordinary boundary the
  # pane's registry row holds THIS session's own claude pid. If that read as "held by an ancestor",
  # every live session would stop maintaining its own alias trail — a far worse outage than the
  # pollution the gate exists to stop. Distinct from the no-row control: this one HAS a row, and a
  # live one, so it exercises the whole gate rather than its first early return.
  mailbox_alias_write "$PANE_A" "$SESS_1"
  write_row "$PANE_A" "$(_mbx_claude_pid)"
  run mailbox_alias_write "$PANE_A" "$SESS_2"
  [ "$status" -eq 0 ]
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
}

@test "M1 tenancy: a LIVE but NON-ANCESTOR pid in the row must NOT refuse (pid/pane reuse)" {
  # The case that credits the ANCESTRY check specifically, and the one session-register.sh:74-79
  # names as the reason the cheaper "incumbent is a live claude" test was rejected: it convicts on
  # pid REUSE (the kernel recycles a stale row's pid onto an unrelated process) and on pane REUSE
  # (a `handoff-fire --recycle` relaunch), refusing a legitimate tenant forever — the very failure
  # the gate exists to prevent, re-created by the gate.
  #
  # It also pins what the mutants proved is NOT load-bearing: `kill -0` is a fork-saving fast path,
  # not the safety property. Removing it reds nothing, because a dead pid is not in our ancestor
  # chain either. This case fails if the ancestry requirement is dropped; the dead-pid case does not.
  local live; sleep 30 & live=$!
  mailbox_alias_write "$PANE_A" "$SESS_1"
  write_row "$PANE_A" "$live"
  run mailbox_alias_write "$PANE_A" "$SESS_2"
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(mailbox_alias_of "$PANE_A")" = "$SESS_2" ]
}

# ── KITTY GATE (2026-10-04): a kitty window number reused across kitty restarts is not a succession ──
# Incident: fresh session aee462b0 in kitty window 236 (kitty started Oct 1) adopted b6b0ac64, which
# held window 236 in an EARLIER kitty and closed on Sep 11. "This kitty" is stood in for by the test
# process itself ($$): it started moments ago, so a trail line stamped now is inside it and a Sep 11
# line is not. The real `ps -o lstart` path runs; nothing about the clock is stubbed.
# RED-proof: on the pre-fix lib the REPLAY test below adopts b6b0ac64 and folds the two Sep 11 pane
# lines into the session box (3 [forwarded:] lines), exactly the incident; the CONTROL arm shows the
# fixture still does that whenever the kitty is unknown.
kitty_epoch() { KITTY_PID=$$ mailbox_kitty_start_s; }
trail_line() { # <pane> <iso-stamp> <session> — a trail line from a given time
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  printf '%s %s\n' "$2" "$3" >> "$CC_MAILBOX_DIR/.alias/$1"
}

@test "KITTY GATE: a predecessor last seen BEFORE this kitty started is not adopted" {
  local ep; ep="$(kitty_epoch)"
  [ -n "$ep" ] || { echo "no kitty start epoch — every assertion below would be vacuous"; false; }
  trail_line "$PANE_A" 2026-09-11T09:24:14-0500 "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2" "$ep"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "adopted a session from an earlier kitty: $output"; false; }
  # CONTROL: the same trail with the kitty UNKNOWN adopts, as it did before the gate.
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2" ""
  [ "$output" = "$SESS_1" ]
}

@test "KITTY GATE positive: a same-kitty crash relaunch still adopts its predecessor" {
  local ep; ep="$(kitty_epoch)"
  [ -n "$ep" ] || false
  mailbox_alias_write "$PANE_A" "$SESS_1"      # crashed in THIS kitty
  mailbox_alias_write "$PANE_A" "$SESS_2"      # relaunched into the same window
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_2" "$ep"
  [ "$output" = "$SESS_1" ]
}

@test "KITTY GATE positive: recycle N→N+1→N+2 in one kitty adopts both, and drops only the earlier kitty's" {
  local ep; ep="$(kitty_epoch)"
  [ -n "$ep" ] || false
  trail_line "$PANE_A" 2026-08-02T18:14:22-0700 "44444444-AAAA-BBBB-CCCC-000000000004"   # earlier kitty
  mailbox_alias_write "$PANE_A" "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  mailbox_alias_write "$PANE_A" "$SESS_3"
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_3" "$ep"
  [ "$output" = "$SESS_2
$SESS_1" ]
}

@test "KITTY GATE: a session's NEWEST trail line dates it, not its first stay" {
  # mailbox_alias_trail keeps each session's OLDEST line. A session that held the pane in an earlier
  # kitty and came back in this one would be dated to its first stay and wrongly refused.
  local ep; ep="$(kitty_epoch)"
  [ -n "$ep" ] || false
  trail_line "$PANE_A" 2026-09-11T09:24:14-0500 "$SESS_1"
  mailbox_alias_write "$PANE_A" "$SESS_2"
  mailbox_alias_write "$PANE_A" "$SESS_1"      # back, in this kitty
  mailbox_alias_write "$PANE_A" "$SESS_3"
  run mailbox_adoptable_predecessors "$PANE_A" "$SESS_3" "$ep"
  [ "$output" = "$SESS_1
$SESS_2" ]
}

@test "KITTY GATE: with KITTY_PID stripped, the registry row naming my session supplies the kitty" {
  local ep; ep="$(kitty_epoch)"
  [ -n "$ep" ] || false
  mkdir -p "$HOME/.claude/cc-registry"
  printf '{"paneUUID":"%s","pid":1,"session_id":"%s","kitty_pid":%s}' "$PANE_A" "$SESS_2" "$$" \
    > "$HOME/.claude/cc-registry/$PANE_A.json"
  run mailbox_kitty_start_s "$SESS_2"
  [ "$output" = "$ep" ]
  # A row naming ANOTHER session is not mine to read.
  run mailbox_kitty_start_s "$SESS_1"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# THE REAL 2026-10-04 STATE, replayed through the real drain hook. Fixture files are verbatim copies
# of ~/.claude/mailbox/.alias/236 (the 6 lines before aee462b0 arrived), 236.md (the 2 Sep 11 lines
# it held) and b6b0ac64's box.
replay_fixture() {
  RF="$REPO/tests/fixtures/mailbox-kitty-epoch-2026-10-04"
  ME="aee462b0-ce17-4954-9a42-ac926a55e261"; OLD="b6b0ac64-5189-483f-ad49-f412df637e3e"
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  cp "$RF/alias-236" "$CC_MAILBOX_DIR/.alias/236"
  cp "$RF/pane-236.md" "$CC_MAILBOX_DIR/236.md"
  cp "$RF/$OLD.md" "$CC_MAILBOX_DIR/$OLD.md"
}
replay_drain() { printf '{"session_id":"%s"}' "$ME" | CC_PANE_ID=236 "$REPO/hooks/mailbox-drain.sh" session-start; }

@test "REPLAY 2026-10-04: a fresh session in reused kitty window 236 inherits nothing from Sep 11" {
  replay_fixture
  export KITTY_PID=$$
  run replay_drain
  [ "$status" -eq 0 ]
  ! grep -qs 'forwarded:' "$CC_MAILBOX_DIR/$ME.md" \
    || { echo "Sep 11 mail reached the new session's box:"; cat "$CC_MAILBOX_DIR/$ME.md"; false; }
  [[ "$output" != *"post-land RED"* ]] || { echo "delivered b6b0ac64's Sep 11 page: $output"; false; }
  [[ "$output" != *"WAKE-PATH-DOWN"* ]] || { echo "delivered the Sep 11 pane lines: $output"; false; }
  # b6b0ac64's box is untouched: not adopted, cursor not advanced.
  [ "$(mailbox_acked "$OLD")" = 0 ]
  # The pane box's two lines are SEALED: consumed by cursor and logged, still on disk.
  [ "$(mailbox_acked 236)" = 2 ]
  [ "$(grep -c '' "$CC_MAILBOX_DIR/236.md")" = 2 ]
  grep -q 'sealed 2 line(s) 1..2 of 236' "$CC_MAILBOX_DIR/236.sealed" || false
}

@test "REPLAY CONTROL: the same fixture with the kitty UNKNOWN still reproduces the incident" {
  # Shows the fixture can fail: without a kitty epoch (iTerm, headless) behaviour is exactly the
  # pre-fix one, and it is the incident's.
  replay_fixture
  run replay_drain
  [ "$status" -eq 0 ]
  grep -q "\[forwarded:b6b0ac64\] .*post-land RED" "$CC_MAILBOX_DIR/$ME.md" || false
  [ "$(grep -c '\[forwarded:236\] 2026-09-11' "$CC_MAILBOX_DIR/$ME.md")" = 2 ]
}
