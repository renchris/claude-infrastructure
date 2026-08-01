#!/usr/bin/env bats
# cc-do — the ONE command the close block points at. Proves:
#   · the RUNNABLE/JUDGMENT split: activations+deploy run; decisions+blocked-backlog NEVER do
#   · the .done marker is EARNED — exit 0 writes it, a failure must not (silent-loss guard)
#   · CONFIRM-gated (effect-bearing) activations outrank plain ones
#   · stem resolution: exactly-one runs, ambiguous and unknown both rc 2 and say why
#   · decision folding matches the readout's: open C and default-less/deadline-less B in, A out
#   · malformed packets degrade (skipped) rather than killing the board
#   · non-TTY with no --run/--list/CC_DO_ASSUME_YES prints and exits 0 — it never blocks on a read
#
# EVERY negative assertion below carries a positive control in the same fixture: an unhooked probe
# also reports "did not run", so "no side effect" proves nothing unless the SAME probe is shown
# firing under the condition that should fire it.
#
# Each case redirects `run … </dev/null` so no test can ever hang on the confirm prompt, and so the
# non-TTY branch is exercised deterministically rather than depending on how bats got invoked.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DO="$REPO/bin/cc-do"
  DECIDE="$REPO/bin/cc-decide"
  BACKLOG="$REPO/bin/cc-backlog"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity rule 1
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$BACKLOG"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off                               # no detached dispatch pass from `add`
  # no deploy-lag by default: point the shared checkout at a path that is not a repo
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_DEPLOY_SCRIPT="$BATS_TEST_TMPDIR/no-such-deploy.sh"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR"
  : > "$CC_BACKLOG_FILE"
  SENT="$BATS_TEST_TMPDIR/sentinel"
}

# an activation that TOUCHES a sentinel — the probe every "never ran" assertion is measured against
mkact() {  # $1=name  $2=sentinel path  [$3=exit code, default 0]
  printf '#!/bin/bash\ntouch "%s"\nexit %s\n' "$2" "${3:-0}" > "$CC_ACTIVATION_DIR/$1.sh"
}
# a CONFIRM-gated activation (the effect-bearing shape the ordering rule keys on)
mkact_confirm() {  # $1=name  $2=sentinel path
  # shellcheck disable=SC2016  # ${CONFIRM:-0} must reach the FIXTURE unexpanded — it is that
  # script's own gate, and expanding it here would write a fixture with no gate at all.
  printf '#!/bin/bash\n[ "${CONFIRM:-0}" = 1 ] || exit 0\ntouch "%s"\n' "$2" \
    > "$CC_ACTIVATION_DIR/$1.sh"
}

# ── nothing outstanding ───────────────────────────────────────────────────────────────────────────

@test "nothing outstanding → exit 0 with a clear line, and --run/--list agree" {
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing outstanding' || false
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing outstanding' || false
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing outstanding' || false
}

# ── activations: render, run, and EARN the marker ────────────────────────────────────────────────

@test "a pending activation renders RUN and --run leaves the .done marker" {
  mkact 05-alpha "$SENT"
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RUN  1. 05-alpha' || false
  [ ! -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]      # not yet — rendering must not run

  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]                                       # positive control: it really executed
  [ -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
}

@test "a FAILING activation → exit 1, names the script, NO .done marker (control: success writes it)" {
  mkact 05-boom "$SENT" 7
  run "$DO" --run </dev/null
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAILED — 05-boom' || false
  echo "$output" | grep -q 'exit 7' || false
  [ -f "$SENT" ]                                       # it DID run…
  [ ! -f "$CC_ACTIVATION_DIR/05-boom.sh.done" ]        # …and still earned no marker

  # POSITIVE CONTROL — same name, same path, only the exit code differs
  mkact 05-boom "$SENT" 0
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$CC_ACTIVATION_DIR/05-boom.sh.done" ]
}

@test "execution STOPS at the first failure — nothing after it runs" {
  mkact 05-boom "$BATS_TEST_TMPDIR/first" 4
  mkact 09-after "$BATS_TEST_TMPDIR/second"
  run "$DO" --run </dev/null
  [ "$status" -eq 1 ]
  [ -f "$BATS_TEST_TMPDIR/first" ]                     # control: the loop did reach step 1
  [ ! -f "$BATS_TEST_TMPDIR/second" ]                  # …and never reached step 2
  [ ! -f "$CC_ACTIVATION_DIR/09-after.sh.done" ]
}

@test "a .done-marked activation never renders (control: its un-done sibling does)" {
  mkact 05-fresh "$SENT"
  mkact 06-stale "$SENT"
  : > "$CC_ACTIVATION_DIR/06-stale.sh.done"
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '05-fresh' || false         # positive control
  run bash -c 'echo "$1" | grep -c "06-stale"' _ "$output"
  [ "$output" -eq 0 ]
}

@test "CONFIRM-gated activations sort ABOVE plain ones despite filename order" {
  mkact 04-plain "$BATS_TEST_TMPDIR/p"                 # sorts FIRST by filename
  mkact_confirm 18-gated "$BATS_TEST_TMPDIR/g"         # sorts LAST by filename
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RUN  1. 18-gated' || false
  echo "$output" | grep -q 'RUN  2. 04-plain' || false
  # and the gate really is honoured: CONFIRM=1 is what makes the gated body fire
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/g" ]
}

# ── stem resolution ──────────────────────────────────────────────────────────────────────────────

@test "cc-do <stem> runs exactly ONE activation and leaves the others pending" {
  mkact 05-alpha "$BATS_TEST_TMPDIR/a"
  mkact 09-bravo "$BATS_TEST_TMPDIR/b"
  run "$DO" 05-alpha </dev/null
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/a" ]
  [ -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
  [ ! -f "$BATS_TEST_TMPDIR/b" ]                       # control below proves this probe can fire
  [ ! -f "$CC_ACTIVATION_DIR/09-bravo.sh.done" ]
  run "$DO" 09-bravo </dev/null
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/b" ]                         # POSITIVE CONTROL for the probe above
}

@test "an ambiguous stem exits 2 and LISTS the matches, running nothing" {
  mkact 05-alpha "$BATS_TEST_TMPDIR/a"
  mkact 05-anvil "$BATS_TEST_TMPDIR/b"
  run "$DO" 05-a </dev/null
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ambiguous' || false
  echo "$output" | grep -q '05-alpha' || false
  echo "$output" | grep -q '05-anvil' || false
  [ ! -f "$BATS_TEST_TMPDIR/a" ]
  [ ! -f "$BATS_TEST_TMPDIR/b" ]
}

@test "an unknown stem exits 2 and says so (control: the exact stem exits 0)" {
  mkact 05-alpha "$BATS_TEST_TMPDIR/a"
  run "$DO" 99-nope </dev/null
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'no pending activation' || false
  [ ! -f "$BATS_TEST_TMPDIR/a" ]
  run "$DO" 05-alpha </dev/null                        # POSITIVE CONTROL
  [ "$status" -eq 0 ]
}

@test "a stem that resolves ONLY to a .done activation is unresolvable (rc 2)" {
  mkact 05-alpha "$BATS_TEST_TMPDIR/a"
  : > "$CC_ACTIVATION_DIR/05-alpha.sh.done"
  run "$DO" 05-alpha </dev/null
  [ "$status" -eq 2 ]
  [ ! -f "$BATS_TEST_TMPDIR/a" ]
}

# ── decisions + backlog are JUDGMENT: counted, itemized on demand, NEVER executed ─────────────────

@test "an open class-C decision counts as judgment and is NEVER executed" {
  # the packet carries a staged artifact — the strongest possible probe: if cc-do ever ran a
  # decision's command, this sentinel would exist.
  printf '#!/bin/bash\ntouch "%s"\n' "$SENT" > "$BATS_TEST_TMPDIR/staged.sh"
  "$DECIDE" open --class C --what "Choose the reboot posture. Long tail." \
    --staged-artifact "$BATS_TEST_TMPDIR/staged.sh" >/dev/null
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '1 open decision(s)' || false
  echo "$output" | grep -q 'cc-decide list --open' || false
  [ ! -f "$SENT" ]
  # POSITIVE CONTROL — the identical script, staged as an ACTIVATION, does fire
  cp "$BATS_TEST_TMPDIR/staged.sh" "$CC_ACTIVATION_DIR/05-same.sh"
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
}

@test "the default view COUNTS decisions; --list itemizes them; --json exposes every one" {
  "$DECIDE" open --class C --what "Choose the reboot posture. Tail." >/dev/null
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  run bash -c 'echo "$1" | grep -c "Choose the reboot posture"' _ "$output"
  [ "$output" -eq 0 ]                                  # counted, not itemized
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Choose the reboot posture' || false   # POSITIVE CONTROL
  run "$DO" --json </dev/null
  [ "$status" -eq 0 ]
  run bash -c 'printf "%s" "$1" | jq -r ".[] | select(.class==\"decision\") | .mark"' _ "$output"
  [ "$output" = "◆" ]
}

@test "class-A and a well-formed class-B are excluded; class-C in the same store is not" {
  "$DECIDE" open --class C --what "Ruling required here. Tail." >/dev/null
  "$DECIDE" open --class A --what "Auto-decided audit trail. Never operator-facing." >/dev/null
  "$DECIDE" open --class B --what "Auto-fires unless vetoed. Tail." \
    --default "proceed" --deadline "2099-01-01T00:00:00Z" >/dev/null
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Ruling required here' || false        # POSITIVE CONTROL
  echo "$output" | grep -q '1 open decision(s)' || false           # exactly one folded in
  run bash -c 'echo "$1" | grep -c "audit trail"' _ "$output"
  [ "$output" -eq 0 ]
  run bash -c 'echo "$1" | grep -c "Auto-fires unless vetoed"' _ "$output"
  [ "$output" -eq 0 ]
}

@test "a status-less class-B with NO default and NO deadline still reaches the board" {
  # `cc-decide open` refuses that combination, so it can only be hand-written — a hard block
  # wearing the wrong label. Raw JSON is the correct fixture shape for exactly this reason.
  printf '{"id":"shipland-esc-deadbee","class":"B","what_plain":"ship-land refused to auto-land. Tail."}\n' \
    > "$CC_DECISIONS_DIR/shipland-esc-deadbee.json"
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ship-land refused to auto-land' || false
  echo "$output" | grep -q 'shipland-esc-deadbee' || false        # WHOLE id, pasteable back
}

@test "a malformed decision packet is SKIPPED, not fatal (control: the good one still renders)" {
  # named to sort FIRST: a producer that aborts on the malformed packet instead of skipping it
  # would then swallow every packet BEHIND it, and a later-sorting fixture could not tell the two
  # apart (the survivor would render either way).
  printf 'this is not json at all {{{\n' > "$CC_DECISIONS_DIR/0000-broken.json"
  "$DECIDE" open --class C --what "Survivor packet renders. Tail." >/dev/null
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Survivor packet renders' || false      # POSITIVE CONTROL
  echo "$output" | grep -q '1 open decision(s)' || false
}

@test "a blocked backlog item is counted judgment with its needs, and is never run" {
  id="$("$BACKLOG" add --title "wire the vendor key" --project p)"
  "$BACKLOG" block "$id" --needs "paste the API key into SSM" >/dev/null
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '1 blocked backlog' || false
  echo "$output" | grep -q 'cc-backlog list --blocked' || false
  run bash -c 'echo "$1" | grep -c "paste the API key"' _ "$output"
  [ "$output" -eq 0 ]                                  # counted only in the default/run view
  run "$DO" --list </dev/null
  echo "$output" | grep -q 'paste the API key into SSM' || false   # POSITIVE CONTROL
}

# ── deploy: ordered first, and the platter is existence-checked ──────────────────────────────────

@test "deploy-lag renders FIRST and falls back to the repo copy when CC_DEPLOY_SCRIPT is absent" {
  o="$BATS_TEST_TMPDIR/o.git"; w="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$o"
  git clone -q "$o" "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo more > more.txt; git add more.txt; git commit -q -m ahead; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  mkdir -p "$w/scripts"; printf '#!/bin/bash\ntouch "%s"\n' "$SENT" > "$w/scripts/deploy-live.sh"
  export CC_SHARED_CHECKOUT="$w"
  mkact 05-after "$BATS_TEST_TMPDIR/a"

  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RUN  1. deploy-live' || false          # irreversibility order
  echo "$output" | grep -q 'behind origin/main' || false
  echo "$output" | grep -q 'RUN  2. 05-after' || false

  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]                                                    # the fallback path really ran
}

# ── the non-interactive contract ─────────────────────────────────────────────────────────────────

@test "non-TTY with no --run/--list/CC_DO_ASSUME_YES prints the board and exits 0 WITHOUT prompting" {
  mkact 05-alpha "$SENT"
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RUN  1. 05-alpha' || false
  run bash -c 'echo "$1" | grep -c "Y/n"' _ "$output"
  [ "$output" -eq 0 ]
  [ ! -f "$SENT" ]
  [ ! -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
}

@test "CC_DO_ASSUME_YES=1 is the scripted opt-in that DOES run (control for the case above)" {
  mkact 05-alpha "$SENT"
  run env CC_DO_ASSUME_YES=1 "$DO" </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
  [ -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
}

@test "--list runs nothing (control: --run on the identical fixture does)" {
  mkact 05-alpha "$SENT"
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$SENT" ]
  [ ! -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
  run "$DO" --run </dev/null                           # POSITIVE CONTROL
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
}

# ── surface contract ─────────────────────────────────────────────────────────────────────────────

@test "--json emits exactly the four contracted keys, one object per step" {
  mkact 05-alpha "$SENT"
  "$DECIDE" open --class C --what "A ruling. Tail." >/dev/null
  run "$DO" --json </dev/null
  [ "$status" -eq 0 ]
  json="$output"        # `run` CLOBBERS $output — every derived assertion reads this copy
  run bash -c 'printf "%s" "$1" | jq -r "length"' _ "$json"
  [ "$output" -eq 2 ]
  run bash -c 'printf "%s" "$1" | jq -r "[.[] | keys_unsorted] | flatten | unique | join(\",\")"' _ "$json"
  [ "$output" = "class,cmd,label,mark" ]
}

@test "-h prints usage and exits 0; an unknown option exits 2" {
  run "$DO" --help </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'cc-do <stem>' || false
  run "$DO" --nonsense </dev/null
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown option' || false
}
