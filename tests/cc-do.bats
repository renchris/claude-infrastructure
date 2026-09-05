#!/usr/bin/env bats
# cc-do — the ONE command the close block points at. Proves:
#   · the RUNNABLE/JUDGMENT split: activations+deploy run; decisions+blocked-backlog NEVER do
#   · the .done marker is EARNED — exit 0 writes it, a failure must not (silent-loss guard)
#   · CONFIRM-gated (effect-bearing) activations outrank plain ones
#   · stem resolution: exactly-one runs, ambiguous and unknown both rc 2 and say why
#   · decision folding matches the readout's: open C and default-less/deadline-less B in, A out
#   · malformed packets degrade (skipped) rather than killing the board
#   · non-TTY with no --run/--list/CC_DO_ASSUME_YES prints, never blocks on a read — and exits 3
#     saying NOTHING RAN, so a no-op can never be mistaken for a clean board (which still exits 0)
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
  [ "$status" -eq 3 ]                                 # rendered, ran nothing, SAID so (rc 3)
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
  [ "$status" -eq 3 ]                                  # non-TTY render: nothing ran, rc 3
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

# ── a blocked row's own `run` reaches the board ───────────────────────────────────────────────────
# `cc-backlog needs --run "<cmd>"` records the exact command that discharges the step, and this
# emitter used to hardcode the generic pointer for every row and drop it. Measured on the live store
# 2026-08-17: 51 of 130 blocked rows carried a command and the board showed none of them.

@test "a blocked row's own --run is the command shown under it in --list" {
  id="$("$BACKLOG" needs "rotate the signing key" --run 'op item edit signing-key' --project p)"
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'op item edit signing-key' || false
  # …and it is the ROW's line it hangs under, not a stray line somewhere on the board.
  echo "$output" | grep -A1 -- "$id" | grep -q 'op item edit signing-key' || false
  # NEGATIVE CONTROL, same store: a row with NO --run still shows the generic pointer and gains no
  # command line of its own. Without this, "the command is present" would also pass on a renderer
  # that printed something under every row.
  bare="$("$BACKLOG" needs "decide the menu direction" --project p)"
  run "$DO" --list </dev/null
  echo "$output" | grep -A1 -- "$bare" | grep -qv 'op item edit' || false
  run bash -c 'echo "$1" | grep -A1 -- "$2" | grep -c "^           "' _ "$output" "$bare"
  [ "$output" -eq 0 ]
}

@test "a row's --run WITH A PLACEHOLDER is not a paste target — ✎, and no command line under it" {
  # Same defect as the close block's (operator, 2026-08-22: `--notification-endpoint <your-address>`
  # handed over under a run marker). This board prints a row's own `run` as its paste target, so it
  # hands the same unpasteable line over by a second route. The suppression rides the mechanism that
  # is already there — putting the GENERIC pointer in `cmd` — so there is no fifth field to sync.
  id="$("$BACKLOG" needs "give me the address the alarms should go to" \
        --run 'aws sns subscribe --topic-arn arn:x --notification-endpoint <your-address>' --project p 2>/dev/null)"
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '✎' || false
  echo "$output" | grep -q 'SUPPLY <your-address>' || false
  ! echo "$output" | grep -q 'aws sns subscribe' || false          # nothing to paste by reflex
  # POSITIVE CONTROL, same store: a complete command still hangs under its row as before, so this is
  # a refusal of templates and not a refusal of every backlog command.
  ok="$("$BACKLOG" needs "rotate the signing key" --run 'op item edit signing-key' --project p)"
  run "$DO" --list </dev/null
  echo "$output" | grep -A1 -- "$ok" | grep -q 'op item edit signing-key' || false
}

@test "cc-backlog needs WARNS at filing time when --run still has a hole in it (and files anyway)" {
  # The earliest point the defect can be told to its author — while it is still in the turn that can
  # fix it. ADVISORY: refusing would lose an operator-only step over a formatting complaint, which is
  # worse than a row that needs a value. rc 0 and the id on stdout are the contract every caller uses.
  run "$BACKLOG" needs "give me the alerts inbox address" --run 'cmd --to <your-address>' --project p
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NOT pasteable' || false
  echo "$output" | grep -qE '^[0-9a-f]{12}$' || false     # the id still reaches stdout
}

@test "a row's --run is NOT promoted to runnable — it is never counted, never executed" {
  # The hazard this design refuses. The live population includes a production-token revoke, an
  # `rm -i`, and `brew services stop postgresql@14`; the bulk Enter must never reach any of them.
  # The fixture is the strongest probe available: if cc-do ever ran a backlog `run`, the sentinel
  # would exist.
  # VACUOUS PRE-FIX BY NATURE, and named as such rather than counted as evidence: before this diff
  # no backlog row carried a command near the runnable set, so it passes at both shas. It is not
  # proof of the diff — it is the pin that stops the NEXT reader "finishing the job" by promoting
  # `run` to ▶, which is what would put the token revoke one Enter away.
  printf '#!/bin/bash\ntouch "%s"\n' "$SENT" > "$BATS_TEST_TMPDIR/blg.sh"
  chmod +x "$BATS_TEST_TMPDIR/blg.sh"
  "$BACKLOG" needs "destroy the staging database" --run "bash $BATS_TEST_TMPDIR/blg.sh" --project p >/dev/null
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$SENT" ]
  echo "$output" | grep -q '0 runnable' || false
  # POSITIVE CONTROL — the identical script staged as an ACTIVATION does fire, so the assertion
  # above is about the CLASS, not about a script that could never have run.
  cp "$BATS_TEST_TMPDIR/blg.sh" "$CC_ACTIVATION_DIR/05-same.sh"
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
  # …and the json still marks it judgment, so no consumer can read it as runnable either.
  run "$DO" --json </dev/null
  run bash -c 'printf "%s" "$1" | jq -r ".[] | select(.class==\"backlog\") | .mark" | sort -u' _ "$output"
  [ "$output" = "◆" ]
}

# ── deploy: ordered first, and the platter is existence-checked ──────────────────────────────────

@test "deploy-lag renders FIRST and falls back to the repo copy when CC_DEPLOY_SCRIPT is absent" {
  o="$BATS_TEST_TMPDIR/o.git"; w="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$o"
  git clone -q "$o" "$w"
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo more > more.txt; git add more.txt; git commit -q -m ahead; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  mkdir -p "$w/scripts"; printf '#!/bin/bash\ntouch "%s"\n' "$SENT" > "$w/scripts/deploy-live.sh"
  export CC_SHARED_CHECKOUT="$w"
  mkact 05-after "$BATS_TEST_TMPDIR/a"

  run "$DO" </dev/null
  [ "$status" -eq 3 ]                                              # non-TTY render: nothing ran
  echo "$output" | grep -q 'RUN  1. deploy-live' || false          # irreversibility order
  echo "$output" | grep -q 'behind origin/main' || false
  echo "$output" | grep -q 'RUN  2. 05-after' || false

  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]                                                    # the fallback path really ran
}

# ── the non-interactive contract ─────────────────────────────────────────────────────────────────

@test "non-TTY with steps pending: prints the board, NEVER prompts, and never runs anything" {
  mkact 05-alpha "$SENT"
  run "$DO" </dev/null
  echo "$output" | grep -q 'RUN  1. 05-alpha' || false
  run bash -c 'echo "$1" | grep -c "Y/n"' _ "$output"
  [ "$output" -eq 0 ]                                  # never blocks on a read it cannot answer
  [ ! -f "$SENT" ]
  [ ! -f "$CC_ACTIVATION_DIR/05-alpha.sh.done" ]
}

# The defect this pair pins: rc 0 + a printed board was BYTE-IDENTICAL in verdict to a clean board,
# so `!cc-do` under Claude Code (stdin closed) read as a successful run of a no-op. The exit code is
# what a caller can branch on, so it must SPLIT the two states — and the human-readable half must
# say it too, since the operator reads the block, not the status.
@test "non-TTY with steps pending → rc 3 and says NOTHING RAN (control: empty board is still rc 0)" {
  mkact 05-alpha "$SENT"
  run "$DO" </dev/null
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'NOTHING RAN' || false
  echo "$output" | grep -q '1 runnable step(s) are still pending' || false
  echo "$output" | grep -q 'cc-do --run' || false      # names the way out, non-interactively

  # POSITIVE CONTROL — same binary, same closed stdin, nothing outstanding: the honest 0 survives,
  # so rc 3 is carrying "there was work", not merely "there was no tty".
  rm -f "$CC_ACTIVATION_DIR/05-alpha.sh"
  run "$DO" </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing outstanding' || false
  run bash -c 'echo "$1" | grep -c "NOTHING RAN"' _ "$output"
  [ "$output" -eq 0 ]
}

@test "the non-TTY rc 3 is a RENDER verdict, not a mode verdict: --list/--json/--run keep rc 0" {
  mkact 05-alpha "$SENT"
  for mode in --list --json; do
    run "$DO" "$mode" </dev/null
    [ "$status" -eq 0 ]                                # explicit "runs nothing" modes are not a
    [ ! -f "$SENT" ]                                   # failed run — they did what was asked
  done
  run "$DO" --run </dev/null                           # the scripted opt-in still succeeds
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
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

# ── deploy refusal is a STEADY STATE, not an error ────────────────────────────────────────────────

mklag() {  # a shared checkout that is BEHIND its origin, with a deploy script of the given exit code
  o="$BATS_TEST_TMPDIR/lo.git"; w="$BATS_TEST_TMPDIR/lw"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  # `cd || exit` is not ceremony here: the whole body is redirected to /dev/null, so a failed cd
  # would silently build the fixture in the TEST's cwd and the lag assertion would then measure
  # the wrong repo — a false green in a test whose entire job is to observe a lagging checkout.
  ( cd "$w" || exit 1
    git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo more > more.txt; git add more.txt; git commit -q -m ahead; git push -q origin main
    git reset -q --hard HEAD~1 ) >/dev/null 2>&1
  export CC_SHARED_CHECKOUT="$w"
  printf '#!/bin/bash\nexit %s\n' "$1" > "$BATS_TEST_TMPDIR/dep.sh"
  chmod +x "$BATS_TEST_TMPDIR/dep.sh"
  export CC_DEPLOY_SCRIPT="$BATS_TEST_TMPDIR/dep.sh"
}

@test "a REFUSING deploy step does NOT halt the run — the activations behind it still execute" {
  # deploy-live is fail-closed on a background verifier's green stamp ("the live layer is FROZEN
  # until a tree verifies green"), and this box's trunk is PERSISTENT-RED for reasons no operator
  # action clears. Deploy sorts FIRST, so treating its refusal as fatal meant the ONE COMMAND ran
  # NOTHING: every pending activation sat behind a step that cannot succeed today.
  #
  # FIXTURE RETARGETED (§2.6 D5). `mklag 1` made this test VACUOUS the moment cc-do started holding
  # deploys the lane says it would refuse: the step is ⊘ and never runs, so "it did not halt the run"
  # became true because nothing ran — a control passing because a sibling mechanism already fixed
  # what it tests. The residual risk this skip actually exists for is narrower and still real: the
  # probe is taken when the board is RENDERED and the run happens seconds later, so a lane that
  # passes --dry-run can still refuse for real (the tip moved, the fetch now fails, a peer's file
  # went dirty). This stub IS that state — probe passes, run refuses.
  mklag 0
  printf '#!/bin/bash\ncase " $* " in *" --dry-run "*) exit 0 ;; esac\nexit 1\n' \
    > "$BATS_TEST_TMPDIR/dep.sh"
  mkact 70-after "$BATS_TEST_TMPDIR/ran"
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ran" ]
  [ -f "$CC_ACTIVATION_DIR/70-after.sh.done" ]
}

@test "POSITIVE CONTROL: a SUCCEEDING deploy is not merely skipped — it actually runs" {
  # Without this, "deploy never fails the run" could be satisfied by never running deploy at all.
  mklag 0
  printf '#!/bin/bash\ntouch "%s"\n' "$SENT" > "$BATS_TEST_TMPDIR/dep.sh"
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ -f "$SENT" ]
}

@test "POSITIVE CONTROL: an ACTIVATION failure still halts — deploy is the ONLY non-fatal class" {
  # Making deploy non-fatal must not have made everything non-fatal — that would gut the .done
  # earn-guard, whose whole point is that a failed activation stays pending.
  mkact 71-bad "$BATS_TEST_TMPDIR/bad" 1
  mkact 72-after "$BATS_TEST_TMPDIR/should-not-run"
  run "$DO" --run </dev/null
  [ "$status" -eq 1 ]
  [ ! -f "$CC_ACTIVATION_DIR/71-bad.sh.done" ]
  [ ! -f "$BATS_TEST_TMPDIR/should-not-run" ]
}

# ── the platter must not offer a command its own gate rejects (DEPLOY_LANE_GROUND_UP §2.6 D5 / V9) ─
# RUN 1 on this board was `bash ~/.claude/scripts/deploy-live.sh` for the entire window in which that
# command refused 534 consecutive times. I11 had already established the rule for a MISSING platter
# command — "a recover command that cannot run is worse than no row: it teaches the operator the
# board lies" — and existence was only half of it. A command that exists and cannot succeed teaches
# exactly the same lesson. cc-do now asks the lane (`--dry-run --offline`: its own T1/T2/T3 verdict,
# no network) and downgrades a refusing deploy to ⊘ HELD.

@test "a deploy the LANE REFUSES is HELD, not plattered as RUN" {
  mklag 1
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'HELD    dep ' || false
  echo "$output" | grep -q 'the lane REFUSES' || false
  ! echo "$output" | grep -q 'RUN  1\.' || false          # nothing was offered as runnable
  echo "$output" | grep -q '^cc-do — 0 runnable' || false  # and it does not inflate the count
}

@test "POSITIVE CONTROL: a deploy the lane ACCEPTS is still plattered as RUN 1" {
  # Without this, "refusing deploys are held" is satisfied by holding EVERY deploy — a gate that
  # always fires carries the same zero bits as one that cannot. It also pins that the probe reads the
  # lane's EXIT CODE and not merely the presence of a deploy script.
  mklag 0
  run "$DO" --list </dev/null
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RUN  1. dep ' || false
  ! echo "$output" | grep -q 'HELD' || false
}

@test "a HELD deploy is never EXECUTED — --run skips straight to the activations behind it" {
  # The mark is the whole mechanism: NRUN, run_steps and the prompt all key on ▶, so a ⊘ row cannot
  # be run by construction. Asserted through the sentinel rather than the board, because the board
  # already passed the test above and this is about what the RUNNER does with the same row.
  mklag 1
  # The stub must tell the PROBE apart from the RUN, or the sentinel below records the probe's own
  # invocation and the test can never fail. --dry-run ⇒ refuse silently; a bare call ⇒ leave a mark.
  printf '#!/bin/bash\ncase " $* " in *" --dry-run "*) exit 1 ;; esac\ntouch "%s"\nexit 1\n' \
    "$BATS_TEST_TMPDIR/deploy-ran" > "$BATS_TEST_TMPDIR/dep.sh"
  mkact 70-after "$BATS_TEST_TMPDIR/ran"
  run "$DO" --run </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/deploy-ran" ]                 # held ⇒ the refusing command never ran
  [ -f "$BATS_TEST_TMPDIR/ran" ]                          # …and nothing behind it was starved
}

# ── `cc-do <backlog-id>`: an operator-run step gets an OBSERVER (2026-09-05, BACKLOG_ZERO §5) ─────
# Pre-fix a blocked row's `--run` was printed and never executed or closed by anything: 677 such
# rows filed all-time, 0 closed by the command that discharged them. Red pre-fix: a 12-hex stem
# fell into run_stem's activation search and exited 2 ("no pending activation starts with").

mkrow() {  # $1=run-cmd → echoes the id of ONE blocked row carrying it
  bash "$BACKLOG" needs "operator step under test" --run "$1" --project P 2>/dev/null
}
row_status() { bash "$BACKLOG" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

@test "cc-do <id> runs the row's command and CLOSES the row on exit 0 (CC_DO_ASSUME_YES stands in for the typed yes)" {
  id=$(mkrow "touch '$SENT'")
  [ "$(row_status "$id")" = "blocked" ]
  CC_DO_ASSUME_YES=1 run "$DO" "$id" </dev/null
  [ "$status" -eq 0 ]
  [ -e "$SENT" ]
  [ "$(row_status "$id")" = "done" ]
  grep -q 'cc-do ran' "$CC_BACKLOG_FILE"
}

@test "a FAILING command leaves the row blocked and exits 1 — no close on a red run" {
  id=$(mkrow "touch '$SENT'; exit 7")
  CC_DO_ASSUME_YES=1 run "$DO" "$id" </dev/null
  [ "$status" -eq 1 ]
  [ -e "$SENT" ]                                   # it ran…
  [ "$(row_status "$id")" = "blocked" ]            # …and closed nothing
  echo "$output" | grep -q 'untouched' || false
}

@test "no confirm channel ⇒ NOTHING RAN, exit 3, row untouched (a non-TTY cannot type yes)" {
  id=$(mkrow "touch '$SENT'")
  run "$DO" "$id" </dev/null
  [ "$status" -eq 3 ]
  [ ! -e "$SENT" ]
  [ "$(row_status "$id")" = "blocked" ]
}

@test "a placeholder-carrying command and a slash command are REFUSED (exit 2), never run" {
  id=$(mkrow "cc-relogin <your-account>")
  CC_DO_ASSUME_YES=1 run "$DO" "$id" </dev/null
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'placeholder' || false
  id2=$(mkrow "/ship")
  CC_DO_ASSUME_YES=1 run "$DO" "$id2" </dev/null
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'slash command' || false
  [ "$(row_status "$id")" = "blocked" ]; [ "$(row_status "$id2")" = "blocked" ]
}

@test "CONTROL — the BOARD still never runs a blocked row: --run with a runnable row on the board executes nothing of it" {
  id=$(mkrow "touch '$SENT'")
  run "$DO" --run </dev/null
  [ ! -e "$SENT" ]
  [ "$(row_status "$id")" = "blocked" ]
}
