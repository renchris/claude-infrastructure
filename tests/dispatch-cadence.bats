#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked
#   from those test subshells rather than from file scope (SC2329).
#
# dispatch-cadence — S5 (kick on write, poll as backstop) + S8 (inert alarm with existence evidence)
# of AUTONOMY_DISPATCH_V2. Four subjects, one contract: a decision must follow an `add` within the
# 5-minute bound (§7 A2), and when the spine ISN'T deciding, that must be LOUD (§7 A10) — the
# measured failure was ~3 days of silent inertness with both launchd labels `disabled` (§2).
#
# HERMETIC BY CONSTRUCTION: setup() fixtures $HOME, the ledger, the journal, every land-pipeline
# sensor cc-blockers reads, and launchctl itself. Nothing here reads or writes the operator's live
# ~/.claude, and NO test invokes real launchd (activation is operator-owned, C10) or executes an
# activation script — those are asserted by static read only.
#
# RED-PROOF: every test below fails against the pristine pre-change tree. Point the suite at one:
#   t=$(mktemp -d); git archive origin/main bin/cc-backlog bin/cc-blockers \
#       launchd/com.claude.dispatcher.plist launchd/com.claude.discovery.plist \
#       docs/activation/pending-activation/0{2,3}-*.sh | tar -x -C "$t"
#   CC_CADENCE_SUBJECT_ROOT="$t" bats tests/dispatch-cadence.bats
# That is also why the absence assertions ("the kick does NOT change add's stdout", "the kill switch
# fires nothing", "a missing sensor invents no row") each carry a POSITIVE CONTROL in the same test:
# alone they pass vacuously on a tree with no kick and no alarm at all, which is exactly the state
# this suite exists to distinguish from a working one.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_CADENCE_SUBJECT_ROOT:-$REPO}"
  BACKLOG_BIN="$ROOT/bin/cc-backlog"
  BLOCKERS_BIN="$ROOT/bin/cc-blockers"
  DISPATCHER_PLIST="$ROOT/launchd/com.claude.dispatcher.plist"
  DISCOVERY_PLIST="$ROOT/launchd/com.claude.discovery.plist"
  ACT2="$ROOT/docs/activation/pending-activation/02-load-dispatcher-activate.sh"
  ACT3="$ROOT/docs/activation/pending-activation/03-load-discovery-activate.sh"

  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$D/backlog.jsonl"
  export CC_BACKLOG_KICK_MARKER="$HOME/.claude/autonomy/.dispatch-kick"
  KICKLOG="$D/kick.log"

  # cc-blockers' land-pipeline sensors, fixtured to the deterministically SILENT baseline
  # tests/cc-blockers.bats established: a stamps dir that EXISTS but is empty, no land.log, no
  # deploy checkout. Any land-pipeline row in this suite is therefore switched on deliberately.
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_POSTLAND_DIR="$D/postland"; mkdir -p "$CC_POSTLAND_DIR/stamps"
  export CC_LAND_LOG="$D/absent-land.log"
  export DEPLOY_REPO="$D/absent-repo"
  export CC_BLOCKERS_LAUNCHCTL_BIN="$D/launchctl-stub"

  # <exit-code> [sleep-seconds] — a cc-dispatch stand-in that RECORDS its argv, then optionally
  # sleeps (to prove the caller is not waiting on it), then exits with the given code.
  mk_kick_stub() {
    { printf '#!/bin/bash\n'
      printf 'printf "%%s\\n" "$*" >> "%s"\n' "$KICKLOG"
      [ -n "${2:-}" ] && printf 'sleep %s\n' "$2"
      printf 'exit %s\n' "${1:-0}"
    } > "$D/cc-dispatch"
    chmod +x "$D/cc-dispatch"
    export CC_BACKLOG_KICK_BIN="$D/cc-dispatch"
  }
  kicks() { if [ -f "$KICKLOG" ]; then grep -c . "$KICKLOG"; else echo 0; fi; }
  # The kick is DETACHED by design, so its record is asynchronous — bounded wait, never a bare sleep.
  await_kick() {
    local i=0
    while [ "$i" -lt 50 ]; do
      [ -s "$KICKLOG" ] && return 0
      sleep 0.1; i=$((i + 1))
    done
    return 1
  }

  # <loaded 0|1> <disabled 0|1> — a READ-ONLY launchctl stand-in. Real launchd is never touched.
  # `list` prints launchd's "PID\tSTATUS\tLABEL"; `print-disabled` prints the override DB, in which
  # ABSENCE means enabled (it records overrides, not memberships).
  mk_launchctl() {
    printf '%s' "$1" > "$D/stub-loaded"
    printf '%s' "$2" > "$D/stub-disabled"
    cat > "$D/launchctl-stub" <<'STUB'
#!/bin/bash
d="$(dirname "$0")"
case "${1:-}" in
  list)
    [ "$(cat "$d/stub-loaded")" = 1 ] && printf '%s\t%s\t%s\n' 12345 0 com.claude.dispatcher
    printf '%s\t%s\t%s\n' - 0 com.claude.unrelated ;;
  print-disabled)
    if [ "$(cat "$d/stub-disabled")" = 1 ]; then printf '\t\t"com.claude.dispatcher" => disabled\n'
    else printf '\t\t"com.claude.postland-verify" => enabled\n'; fi ;;
esac
exit 0
STUB
    chmod +x "$D/launchctl-stub"
    export CC_BLOCKERS_LAUNCHCTL_BIN="$D/launchctl-stub"
  }
  # <hours-ago> — one dispatch decision record. RELATIVE, never an absolute literal: a future date
  # in a fixture is a wall-clock time bomb (scripts/test-walltime-lint.sh).
  seed_dispatch_idl() {
    local ts; ts="$(date -u -v-"$1"H +%Y-%m-%dT%H:%M:%SZ)"
    jq -nc --arg ts "$ts" \
      '{ts:$ts,actor:"cc-dispatch",action:"summary",fired:1,abstained:0,failed:0,skipped:0}' \
      >> "$CC_REAPER_IDL"
  }
  # the dispatch alarm's states, sorted and joined — "" proves NO dispatch row at all
  dkinds() { "$BLOCKERS_BIN" --json | jq -r '[.[] | select(.kind=="dispatch-inert") | .state] | sort | join(",")'; }

  # count of launchctl calls OUTSIDE the CONFIRM branch of an activation script (C10: the agent
  # stages, the operator loads — a call outside that branch makes merely READING the queue an
  # activation).  executed = mentions launchctl and is not a comment, an echo, or an assignment.
  outside_confirm() {
    awk '/^if \[ "\$\{CONFIRM:-0\}" = 1 \]/ { c = 1 }
         /^fi$/                             { c = 0 }
         /^[[:space:]]*(#|echo)/            { next }
         /^[A-Za-z_][A-Za-z0-9_]*=/         { next }
         !c && /launchctl|LAUNCHCTL/        { bad++ }
         END { print bad + 0 }' "$1"
  }
}

# ── S5 · kick on write ───────────────────────────────────────────────────────────────────────────

@test "kick: a successful add fires ONE detached decision pass, and add's stdout is still just the id" {
  mk_kick_stub 0
  run "$BACKLOG_BIN" add --title "t1" --project p
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{12}$ ]] || false      # the whole of stdout — callers parse this
  await_kick                                       # POSITIVE CONTROL: a kick really did happen
  grep -q -- '--decide' "$KICKLOG"                 # …and it asked for a DECISION pass, not a spawn
}

@test "kick debounce: 5 rapid adds collapse to exactly ONE decision pass, all 5 still recorded" {
  mk_kick_stub 0
  for i in 1 2 3 4 5; do "$BACKLOG_BIN" add --title "burst-$i" --project p >/dev/null; done
  await_kick
  sleep 0.4                                        # bounded settle: let any straggler child land
  [ "$(kicks)" = 1 ]
  [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 5 ]  # the ledger is untouched by the collapsing
}

@test "kick debounce window is env-tunable: CC_DISPATCH_KICK_DEBOUNCE_S=0 kicks on every add" {
  mk_kick_stub 0
  export CC_DISPATCH_KICK_DEBOUNCE_S=0
  "$BACKLOG_BIN" add --title "d1" --project p >/dev/null
  "$BACKLOG_BIN" add --title "d2" --project p >/dev/null
  await_kick
  sleep 0.4
  [ "$(kicks)" = 2 ]
}

@test "kick kill switch: CC_BACKLOG_KICK=off fires nothing and stamps nothing; on, the same add does" {
  mk_kick_stub 0
  export CC_BACKLOG_KICK=off
  run "$BACKLOG_BIN" add --title "off-1" --project p
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{12}$ ]] || false
  sleep 0.4
  [ "$(kicks)" = 0 ]
  [ ! -e "$CC_BACKLOG_KICK_MARKER" ]
  # POSITIVE CONTROL — same binary, same shape of add, switch back on ⇒ the harness DOES see a kick
  unset CC_BACKLOG_KICK
  run "$BACKLOG_BIN" add --title "on-1" --project p
  [ "$status" -eq 0 ]
  await_kick
  [ -e "$CC_BACKLOG_KICK_MARKER" ]
}

@test "kick failure is harmless: an ABSENT dispatch binary leaves add's id, exit code and ledger intact" {
  export CC_BACKLOG_KICK_BIN="$D/definitely-not-here/cc-dispatch"
  run "$BACKLOG_BIN" add --title "absent-bin" --project p
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{12}$ ]] || false
  id="$output"
  [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 1 ]
  [ "$(jq -rs '.[0].id' "$CC_BACKLOG_FILE")" = "$id" ]
  [ "$(jq -rs '.[0].event' "$CC_BACKLOG_FILE")" = add ]
  # The ATTEMPT is still observable (the marker is stamped before the spawn) — the positive half
  # of this test, and what makes it fail on a tree with no kick rather than pass vacuously.
  [ -e "$CC_BACKLOG_KICK_MARKER" ]
}

@test "kick failure is harmless: a decision pass exiting NON-ZERO does not change add's id or rc" {
  mk_kick_stub 3
  run "$BACKLOG_BIN" add --title "rc3" --project p
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{12}$ ]] || false
  await_kick                                       # it really ran, and really failed
  [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 1 ]
}

@test "kick never holds the caller's fds: a SLOW pass does not stall id=\$(cc-backlog add …)" {
  # The cc-discover contract. A background child that inherits the caller's stdout keeps the
  # command substitution's pipe open, so `id="$(cc-backlog add …)"` blocks until the child exits —
  # a 5s dispatch pass would stall every one of a 20-item discovery loop.
  mk_kick_stub 0 5
  start="$(date +%s)"
  id="$("$BACKLOG_BIN" add --title "slow" --project p)"
  elapsed=$(( $(date +%s) - start ))
  [[ "$id" =~ ^[0-9a-f]{12}$ ]] || false
  [ "$elapsed" -lt 3 ]
  await_kick                                       # POSITIVE CONTROL: the slow pass did start
}

@test "kick does not disturb the idempotent re-add contract (same id, rc 0, one ledger record)" {
  mk_kick_stub 0
  first="$("$BACKLOG_BIN" add --title "same" --project p)"
  export CC_DISPATCH_KICK_DEBOUNCE_S=0
  run "$BACKLOG_BIN" add --title "same" --project p
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 1 ]
  await_kick
}

# ── S5 · the poll backstop ───────────────────────────────────────────────────────────────────────

@test "plists: the dispatcher backstop is 300s, discovery stays hourly, both lint clean" {
  # NEVER `plutil -extract` a plist without -o: it REWRITES the file in place and has destroyed
  # LaunchAgents on this host. Read a COPY, and only ever to stdout.
  cp "$DISPATCHER_PLIST" "$D/d.plist"; cp "$DISCOVERY_PLIST" "$D/y.plist"
  run /usr/bin/plutil -lint "$D/d.plist" "$D/y.plist"
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/plutil -convert json -o - "$D/d.plist" | jq -r '.StartInterval')" = 300 ]
  [ "$(/usr/bin/plutil -convert json -o - "$D/y.plist" | jq -r '.StartInterval')" = 3600 ]
  # RunAtLoad stays false in both: activation is a deliberate operator step (C10), never a side
  # effect of installing the file.
  [ "$(/usr/bin/plutil -convert json -o - "$D/d.plist" | jq -r '.RunAtLoad')" = false ]
  [ "$(/usr/bin/plutil -convert json -o - "$D/y.plist" | jq -r '.RunAtLoad')" = false ]
}

# ── S8 · inert alarm with existence evidence ─────────────────────────────────────────────────────

@test "A10 dispatch alarm: label ABSENT ⇒ NOT-ACTIVATED only; loaded+enabled+ancient ⇒ STALE only" {
  # The discriminating pair. One input must never produce both rows, and the two inputs must never
  # produce the same row: they have different owners (run the C10 step vs. read the job's log).
  seed_dispatch_idl 72
  mk_launchctl 0 1                                 # neither loaded nor enabled
  [ "$(dkinds)" = "NOT-ACTIVATED" ]
  mk_launchctl 1 0                                 # loaded + enabled, identical ancient journal
  [ "$(dkinds)" = "STALE" ]
}

@test "A10: loaded but DISABLED is still NOT-ACTIVATED — not a stall (bootstrap of a disabled label)" {
  # The measured state on this host: the labels sat in the disabled DB, so a bootstrap that looked
  # like it worked never ran anything. Reporting that as "stalled" sends the operator to debug a
  # process that was never started.
  seed_dispatch_idl 72
  mk_launchctl 1 1
  [ "$(dkinds)" = "NOT-ACTIVATED" ]
  mk_launchctl 1 0                                 # POSITIVE CONTROL: clear the bit, verdict flips
  [ "$(dkinds)" = "STALE" ]
}

@test "dispatch alarm STALE keys on the NEWEST decision and only past CC_DISPATCH_STALE_H" {
  mk_launchctl 1 0
  seed_dispatch_idl 72                             # an ancient record …
  seed_dispatch_idl 0                              # … and a fresh one: newest wins ⇒ silent
  [ "$(dkinds)" = "" ]
  # POSITIVE CONTROL on the same fixture: with only the ancient record present, it fires
  : > "$CC_REAPER_IDL"; seed_dispatch_idl 72
  [ "$(dkinds)" = "STALE" ]
  # and the horizon is the knob, not a hardcoded 2h
  export CC_DISPATCH_STALE_H=96
  [ "$(dkinds)" = "" ]
}

@test "dispatch alarm needs EXISTENCE evidence: no cc-dispatch record ever ⇒ no row, even label-absent" {
  # absence-alarm-needs-existence-evidence: "it stopped" is only an alarm where it was SUPPOSED to
  # be running. Keyed on the label alone this fires in every fixtured $HOME void and on every host
  # that never had the spine — the exact phantom row the verifier alarm already had to fix.
  mk_launchctl 0 1                                 # the alarming input …
  jq -nc --arg ts "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts:$ts,actor:"cc-reaper",kind:"surface-page",cause:"crashed",name:"x",pane:"P0"}' >> "$CC_REAPER_IDL"
  [ "$(dkinds)" = "" ]                             # … but the dispatcher never ran here
  seed_dispatch_idl 72                             # POSITIVE CONTROL: one record, and it fires
  [ "$(dkinds)" = "NOT-ACTIVATED" ]
}

@test "dispatch alarm fails OPEN: a missing or erroring launchctl yields NO row, never an invented one" {
  seed_dispatch_idl 72
  export CC_BLOCKERS_LAUNCHCTL_BIN="$D/no-such-launchctl"
  [ "$(dkinds)" = "" ]
  printf '#!/bin/bash\nexit 1\n' > "$D/broken-launchctl"; chmod +x "$D/broken-launchctl"
  export CC_BLOCKERS_LAUNCHCTL_BIN="$D/broken-launchctl"
  [ "$(dkinds)" = "" ]
  mk_launchctl 0 1                                 # POSITIVE CONTROL: with a working sensor, a row
  [ "$(dkinds)" = "NOT-ACTIVATED" ]
}

@test "dispatch alarm hands over an EXACT runnable command per state, and rides in the --json array" {
  seed_dispatch_idl 72; mk_launchctl 0 1
  run "$BLOCKERS_BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'dispatch-inert'
  echo "$output" | grep -q 'NOT-ACTIVATED'
  echo "$output" | grep -q 'CONFIRM=1 bash .*02-load-dispatcher-activate.sh'
  run "$BLOCKERS_BIN" --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="dispatch-inert")] | length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[] | select(.kind=="dispatch-inert") | .subject')" = "com.claude.dispatcher" ]
  # STALE hands over the other command — the job's own log, not the activation step
  mk_launchctl 1 0
  run "$BLOCKERS_BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'STALE'
  echo "$output" | grep -q 'tail -20 /tmp/claude-dispatcher.stderr.log'
  # shellcheck disable=SC2016  # the row EMITS a literal $(id -u) for the operator's shell to expand
  echo "$output" | grep -q 'launchctl print gui/\$(id -u)/com.claude.dispatcher'
}

@test "the two alarm families render as SEPARATE tables (a dispatch row never lands under LAND-PIPELINE)" {
  rm -rf "$CC_POSTLAND_DIR/stamps"; : > "$CC_LAND_LOG"   # switch on the land-pipeline NEVER-ACTIVATED
  seed_dispatch_idl 72; mk_launchctl 0 1                 # …and the dispatch NOT-ACTIVATED
  run "$BLOCKERS_BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^LAND-PIPELINE — 1 alarm'
  echo "$output" | grep -q '^DISPATCH — 1 alarm'
  run "$BLOCKERS_BIN" --json
  [ "$(echo "$output" | jq -r '[.[].kind] | sort | join(",")')" = "dispatch-inert,verifier-inert" ]
}

@test "a healthy spine is SILENT: loaded, enabled and deciding yields no dispatch row at all" {
  mk_launchctl 1 0
  seed_dispatch_idl 0
  [ "$(dkinds)" = "" ]
  run "$BLOCKERS_BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked'       # the whole board is clean, not just quiet
  # POSITIVE CONTROL: the same healthy fixture, one sensor flipped, is NOT silent
  mk_launchctl 0 1
  [ "$(dkinds)" = "NOT-ACTIVATED" ]
}

# ── §9 · activation SSOT (static reads only — the scripts are NEVER executed here) ───────────────

@test "activation 02: enable precedes bootstrap, absolute launchctl, and it prints the A11 verify reads" {
  [ -f "$ACT2" ]
  run bash -n "$ACT2"                                    # a parse, not a run
  [ "$status" -eq 0 ]
  # THE invariant: a bootstrap against a label still in the disabled DB fails silently — which is
  # why both labels sat disabled for 3 days. No bootstrap may ever appear before an enable.
  awk '/launchctl enable/ { e = 1 } /launchctl bootstrap/ { if (!e) bad = 1 } END { exit bad }' "$ACT2"
  grep -q '/bin/launchctl' "$ACT2"                       # absolute: launchd expands neither ~ nor PATH
  grep -q 'StartInterval 300' "$ACT2"                    # the doc line tracks the plist it installs
  grep -q 'print-disabled' "$ACT2"                       # A11 read 2: the label left the disabled DB
  grep -q 'claude-dispatcher.stdout.log' "$ACT2"         # A11 read 3: the job actually produced a log
  # …and the script stays INERT: every launchctl call sits inside the CONFIRM branch
  [ "$(outside_confirm "$ACT2")" = 0 ]
  # POSITIVE CONTROL — that checker is not vacuous: one injected unguarded call is caught
  # shellcheck disable=SC2016  # the injected line is script TEXT, never evaluated here
  { head -20 "$ACT2"; printf '%s\n' '"$LAUNCHCTL" bootout "gui/$UID_/$LABEL"'; tail -n +21 "$ACT2"; } > "$D/tampered.sh"
  [ "$(outside_confirm "$D/tampered.sh")" != 0 ]
}

@test "activation 03: enable precedes bootstrap, absolute launchctl, and it prints the A11 verify reads" {
  [ -f "$ACT3" ]
  run bash -n "$ACT3"
  [ "$status" -eq 0 ]
  awk '/launchctl enable/ { e = 1 } /launchctl bootstrap/ { if (!e) bad = 1 } END { exit bad }' "$ACT3"
  grep -q '/bin/launchctl' "$ACT3"
  grep -q 'print-disabled' "$ACT3"
  grep -q 'claude-discovery.stdout.log' "$ACT3"
  [ "$(outside_confirm "$ACT3")" = 0 ]
}
