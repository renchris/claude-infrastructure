#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are
#   invoked from those test subshells rather than from file scope (SC2329).
#
# cc-fleet — the launchd fleet reconciler's state function (DAEMON_FLEET_V2 §3.1, §4.2). One test
# per arm of the total function, each with its own stubbed launchd fixture:
#   S1 NOT-INSTALLED · S2 DISABLED · S3 NEVER-RAN · S4 FAILING · S5 STALLED · S6 HEALTHY
#   + UNDECIDED (staged) · UNDECLARED-SUMMARY · retired-is-silent
# plus the four disciplines that each cost a real incident here: `plutil -o -`, read-only launchd,
# no-`case`-inside-`$( )`, and sensor-failure ⇒ no row.
#
# HERMETIC BY CONSTRUCTION: setup() fixtures $HOME, LaunchAgents, the override db, launchctl itself,
# the manifest and the clock. Nothing reads or writes the operator's live ~/, and NO test invokes
# real launchd — activation is operator-owned (C10) and this binary is read-only besides.
#
# POSITIVE CONTROLS: every absence assertion ("no row", "silent", "zero rows") is paired IN THE SAME
# TEST with a case that DOES fire off the same fixture. Alone they pass vacuously against a tree
# where nothing fires at all — which is exactly the state this suite exists to distinguish from a
# working reconciler. A detector that fires on everything is not a detector; neither is one that
# fires on nothing.
#
# RED-PROOF: every test below fails against the pristine pre-change tree, where bin/cc-fleet and
# launchd/fleet.manifest do not exist:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CC_FLEET_SUBJECT_ROOT="$t" bats tests/cc-fleet.bats     # 15/15 fail: "cc-fleet is missing"
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — so a non-final occurrence of those is a DEAD assertion that always
# passes (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` (a builtin, fully subject to
# errexit) and appends `|| false` wherever a non-final `[[ ]]` / `!` / `A && B` is used.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_FLEET_SUBJECT_ROOT:-$REPO}"
  FLEET="$ROOT/bin/cc-fleet"

  D="$BATS_TEST_TMPDIR"
  # Fixture $HOME: the reconciler resolves ~/Library/LaunchAgents and expands `~/` evidence paths,
  # so an unfixtured HOME reads the operator's real fleet. The repo's hermeticity ratchet
  # (scripts/test-hermeticity-lint.sh) runs in the land gate and fail-fasts on that.
  export HOME="$D/home"; mkdir -p "$HOME/Library/LaunchAgents"

  export CC_FLEET_MANIFEST="$D/fleet.manifest"
  export CC_FLEET_LIVE_LAUNCHD="$D/agents";      mkdir -p "$CC_FLEET_LIVE_LAUNCHD"
  export CC_FLEET_REPO_LAUNCHD="$D/repo-launchd"; mkdir -p "$CC_FLEET_REPO_LAUNCHD"
  export CC_FLEET_ACTIVATE_DIR="$D/act";          mkdir -p "$CC_FLEET_ACTIVATE_DIR"
  export CC_FLEET_LAUNCHCTL_BIN="$D/launchctl"
  export CC_FLEET_NOW=2000000000
  DISABLED_DB="$D/disabled.txt"; : > "$DISABLED_DB"

  # The stub honours ONLY read-only subcommands and RECORDS every argv, so a mutating call anywhere
  # in cc-fleet is caught by the read-only test rather than by launchd actually changing.
  LCTL_LOG="$D/lctl.log"
  cat > "$CC_FLEET_LAUNCHCTL_BIN" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$LCTL_LOG"
case "\$1" in
  print-disabled) cat "$DISABLED_DB" 2>/dev/null; exit 0 ;;
  print)
    lbl="\${2##*/}"
    if [ -f "$D/print-\$lbl.txt" ]; then cat "$D/print-\$lbl.txt"; exit 0; fi
    # launchd's measured behaviour: rc=113 with an IDENTICAL message for a disabled label and for a
    # label that does not exist (DAEMON_FLEET_V2 §3.1.1) — the ambiguity S1/S2 must never read.
    echo "Bad request." >&2
    echo "Could not find service \"\$lbl\" in domain for user gui: 501" >&2
    exit 113 ;;
  list) exit 0 ;;
  *) echo "stub: refusing non-read-only subcommand \$1" >&2; exit 99 ;;
esac
STUB
  chmod +x "$CC_FLEET_LAUNCHCTL_BIN"

  have_subject() {   # RED-proof legibility: name the absence instead of dying on 127
    [ -x "$FLEET" ] || { echo "cc-fleet is missing or not executable at $FLEET"; return 1; }
  }
  plist() {          # $1=label [$2=StandardOutPath]  → a fixture LaunchAgents plist
    if [ -n "${2:-}" ]; then
      /usr/bin/plutil -create xml1 "$CC_FLEET_LIVE_LAUNCHD/$1.plist"
      /usr/bin/plutil -insert Label -string "$1" "$CC_FLEET_LIVE_LAUNCHD/$1.plist"
      /usr/bin/plutil -insert StandardOutPath -string "$2" "$CC_FLEET_LIVE_LAUNCHD/$1.plist"
    else
      /usr/bin/plutil -create xml1 "$CC_FLEET_LIVE_LAUNCHD/$1.plist"
      /usr/bin/plutil -insert Label -string "$1" "$CC_FLEET_LIVE_LAUNCHD/$1.plist"
    fi
  }
  printfix() {       # $1=label $2...=the `launchctl print` body lines
    shift_label="$1"; shift
    printf '%s\n' "$@" > "$D/print-$shift_label.txt"
  }
  disable() { printf '\t\t"%s" => disabled\n' "$1" >> "$DISABLED_DB"; }
  enable()  { printf '\t\t"%s" => enabled\n'  "$1" >> "$DISABLED_DB"; }
  manifest() { printf '%s\n' "$@" > "$CC_FLEET_MANIFEST"; }
  # Fixture mtimes are derived FROM the pinned test clock, never from the wall clock: with
  # CC_FLEET_NOW in the future a plain `touch` writes a mtime that is years STALE to the subject.
  age_file() { # $1=path $2=age-in-seconds
    : > "$1"; touch -t "$(date -r "$((CC_FLEET_NOW - $2))" +%Y%m%d%H%M.%S)" "$1"
  }
  fleet() { "$FLEET" "$@"; }
  states() { "$FLEET" --json | sed -n 's/.*"state":"\([^"]*\)".*/\1/p'; }
  rows()   { "$FLEET" --json | grep -c fleet-inert || true; }
  field()  { # $1=json-key  → the value from the FIRST row
    "$FLEET" --json | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1
  }
}

# ── S1 ────────────────────────────────────────────────────────────────────────────────────────────
@test "S1 NOT-INSTALLED: declared run with no plist rows; an installed one does not" {
  have_subject
  manifest 'com.claude.gone | run | 300 | auto | 1 | 18-fleet-activate.sh'
  [ "$(states)" = NOT-INSTALLED ]
  [ "$(rows)" = 1 ]
  # the recover command is the paste-ready C10 platter, not a paraphrase
  [ "$(field recover_cmd)" = "CONFIRM=1 bash $CC_FLEET_ACTIVATE_DIR/18-fleet-activate.sh" ]

  # POSITIVE CONTROL, same fixture: install the plist and make it healthy — the row must vanish.
  # Without this, "S1 fires" is satisfied by a reconciler that reports NOT-INSTALLED for everything.
  plist com.claude.gone "$D/gone.log"
  printfix com.claude.gone '	state = not running' '	runs = 4' '	last exit code = 0'
  age_file "$D/gone.log" 10
  [ "$(rows)" = 0 ]
}

# ── S2 ────────────────────────────────────────────────────────────────────────────────────────────
@test "S2 DISABLED: the override bit rows, terminally, and only for the matched label" {
  have_subject
  plist com.claude.d1 "$D/d1.log"
  plist com.claude.d1-suffix "$D/d1s.log"
  printfix com.claude.d1-suffix '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/d1s.log" 10
  disable com.claude.d1
  manifest 'com.claude.d1 | run | 300 | auto | 12 | 18-fleet-activate.sh' \
           'com.claude.d1-suffix | run | 300 | auto | 12 | 18-fleet-activate.sh'

  [ "$(rows)" = 1 ]                      # TERMINAL: one dark job, ONE row (not five)
  [ "$(states)" = DISABLED ]
  [ "$(field subject)" = com.claude.d1 ]  # whole-and-quoted match: the suffixed label is untouched
  [ "$(field detail)" = "disabled at the domain level (C10)" ]

  # POSITIVE CONTROL: `=> enabled` in the same db is NOT a disable, and absence means enabled too.
  : > "$DISABLED_DB"; enable com.claude.d1
  printfix com.claude.d1 '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/d1.log" 10
  [ "$(rows)" = 0 ]
}

# ── S3 ────────────────────────────────────────────────────────────────────────────────────────────
@test "S3 NEVER-RAN: loaded with runs=0 and no artifact rows; runs>0 does not" {
  have_subject
  plist com.claude.n1 "$D/never-written.log"
  printfix com.claude.n1 '	state = not running' '	runs = 0'
  manifest 'com.claude.n1 | run | 300 | auto | 9 | 18-fleet-activate.sh'

  [ "$(states)" = NEVER-RAN ]
  [ "$(field detail)" = "loaded, runs=0, no evidence artifact" ]

  # POSITIVE CONTROL: the SAME fixture with runs=1 and an artifact is not a never-ran job.
  printfix com.claude.n1 '	state = not running' '	runs = 1' '	last exit code = 0'
  age_file "$D/never-written.log" 10
  [ "$(rows)" = 0 ]
}

# ── S4 ────────────────────────────────────────────────────────────────────────────────────────────
@test "S4 FAILING: a nonzero last exit code rows and beats staleness; exit 0 does not" {
  have_subject
  plist com.claude.f1 "$D/f1.log"
  printfix com.claude.f1 '	state = not running' '	runs = 16' '	last exit code = 1'
  age_file "$D/f1.log" 999999                 # ALSO stale — S4 must win (terminal precedence)
  manifest 'com.claude.f1 | run | 600 | auto | 1 | 14-land-pipeline-v2-activate.sh'

  [ "$(rows)" = 1 ]
  [ "$(states)" = FAILING ]
  [ "$(field detail)" = "last exit code 1 after 16 runs" ]
  # the recover command names the job's OWN log, and emits $(id -u) unexpanded so it stays portable
  printf '%s\n' "$(field recover_cmd)" | grep -q "tail -40 $D/f1.log" || false
  printf '%s\n' "$(field recover_cmd)" | grep -qF 'gui/$(id -u)/com.claude.f1' || false

  # POSITIVE CONTROL: exit 0 on the same stale fixture is STALLED, not FAILING — so the assertion
  # above is about the exit code and not merely about "some row appears".
  printfix com.claude.f1 '	state = not running' '	runs = 16' '	last exit code = 0'
  [ "$(states)" = STALLED ]
}

# ── S5 + S6 ───────────────────────────────────────────────────────────────────────────────────────
@test "S5 STALLED / S6 HEALTHY: the same fixture flips on the evidence mtime alone" {
  have_subject
  plist com.claude.s1 "$D/s1.log"
  printfix com.claude.s1 '	state = not running' '	runs = 9' '	last exit code = 0'
  manifest 'com.claude.s1 | run | 300 | auto | 1 | 18-fleet-activate.sh'

  age_file "$D/s1.log" 1000                   # 300 x 3 = 900s bound  ⇒ STALLED
  [ "$(states)" = STALLED ]
  [ "$(field detail)" = "evidence 17m old; bound 15m" ]

  age_file "$D/s1.log" 800                    # inside the bound      ⇒ S6, no row
  [ "$(rows)" = 0 ]
  run fleet --check
  [ "$status" -eq 0 ]                         # POSITIVE CONTROL for --check's green side

  # the factor is the declared tunable, not a constant baked into the verdict
  CC_FLEET_STALE_FACTOR=2 fleet --json | grep -q STALLED || false
}

@test "S5: interval_s=0 (calendar-scheduled) uses the 86400 x factor bound, not 0" {
  have_subject
  plist com.claude.cal "$D/cal.log"
  printfix com.claude.cal '	state = not running' '	runs = 3' '	last exit code = 0'
  manifest 'com.claude.cal | run | 0 | auto | 1 | 18-fleet-activate.sh'

  age_file "$D/cal.log" 86400                 # one day: WELL inside 3 days ⇒ no row
  [ "$(rows)" = 0 ]
  age_file "$D/cal.log" 300000                # past 259200 ⇒ STALLED
  [ "$(states)" = STALLED ]
  # a literal 0 bound would have rowed on the one-day case too, which is what this pins
}

# ── R8: no sensor, no verdict ─────────────────────────────────────────────────────────────────────
@test "R8 evidence '-' or an absent StandardOutPath is NEVER claimed STALLED" {
  have_subject
  plist com.claude.noev                       # NO StandardOutPath key at all ⇒ `auto` resolves to none
  plist com.claude.dash "$D/dash.log"
  printfix com.claude.noev '	state = not running' '	runs = 5' '	last exit code = 0'
  printfix com.claude.dash '	state = not running' '	runs = 5' '	last exit code = 0'
  manifest 'com.claude.noev | run | 60 | auto | 9 | 18-fleet-activate.sh' \
           'com.claude.dash | run | 60 | - | 9 | 18-fleet-activate.sh'

  [ "$(rows)" = 0 ]                           # no artifact ⇒ nothing can be "late"

  # POSITIVE CONTROL: a THIRD label with the same interval and a real, stale artifact DOES row —
  # so the two silences above are the absence of a sensor, not the absence of a detector.
  plist com.claude.hasev "$D/hasev.log"
  printfix com.claude.hasev '	state = not running' '	runs = 5' '	last exit code = 0'
  age_file "$D/hasev.log" 999999
  manifest 'com.claude.noev | run | 60 | auto | 9 | 18-fleet-activate.sh' \
           'com.claude.dash | run | 60 | - | 9 | 18-fleet-activate.sh' \
           'com.claude.hasev | run | 60 | auto | 9 | 18-fleet-activate.sh'
  [ "$(rows)" = 1 ]
  [ "$(field subject)" = com.claude.hasev ]
}

# ── UNDECIDED ─────────────────────────────────────────────────────────────────────────────────────
@test "UNDECIDED: staged ALWAYS rows exactly once, carrying the observed state" {
  have_subject
  plist com.claude.st1 "$D/st1.log"
  printfix com.claude.st1 '	state = not running' '	runs = 4' '	last exit code = 0'
  age_file "$D/st1.log" 10                    # HEALTHY by every sensor — and still exactly one row
  manifest 'com.claude.st1 | staged | 300 | auto | 12 | 05-pmset-caffeinate-activate.sh'

  [ "$(rows)" = 1 ]
  [ "$(states)" = UNDECIDED ]
  [ "$(field detail)" = "staged: HEALTHY; decision pending" ]
  [ "$(field recover_cmd)" = "CONFIRM=1 bash $CC_FLEET_ACTIVATE_DIR/05-pmset-caffeinate-activate.sh" ]

  # staged must never become a hiding place: still ONE row when the job is disabled…
  disable com.claude.st1
  [ "$(field detail)" = "staged: DISABLED; decision pending" ]
  [ "$(rows)" = 1 ]
  # …and still ONE row when every sensor is dead (the verdict is about the DECISION, not the daemon)
  CC_FLEET_LAUNCHCTL_BIN="$D/nonexistent" fleet --json | grep -q 'staged: UNKNOWN' || false
  [ "$(CC_FLEET_LAUNCHCTL_BIN="$D/nonexistent" fleet --json | grep -c fleet-inert)" = 1 ]

  # --check ignores it: staged is a pending decision, not a declared-run failure
  run fleet --check
  [ "$status" -eq 0 ]
}

# ── retired ───────────────────────────────────────────────────────────────────────────────────────
@test "retired is silent in every state a run label would row for" {
  have_subject
  # deliberately the WORST fixture: no plist, so a `run` twin would be NOT-INSTALLED
  manifest 'com.claude.ret | retired | 300 | auto | 12 | 18-fleet-activate.sh'
  [ "$(rows)" = 0 ]
  run fleet --check
  [ "$status" -eq 0 ]
  fleet --table | grep -q 'RETIRED  *com.claude.ret' || false   # silent on the board, VISIBLE to the operator

  # POSITIVE CONTROL: the identical fixture declared `run` DOES row — so "silent" is the `retired`
  # classification doing work, not a reconciler that never fires.
  manifest 'com.claude.ret | run | 300 | auto | 12 | 18-fleet-activate.sh'
  [ "$(states)" = NOT-INSTALLED ]
}

# ── UNDECLARED-SUMMARY ────────────────────────────────────────────────────────────────────────────
@test "UNDECLARED-SUMMARY: one row naming the count and the labels, not one row each" {
  have_subject
  plist com.claude.declared "$D/dec.log"
  printfix com.claude.declared '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/dec.log" 10
  plist com.claude.strayA "$D/a.log"
  plist com.claude.strayB "$D/b.log"
  manifest 'com.claude.declared | run | 300 | auto | 1 | 18-fleet-activate.sh'

  [ "$(rows)" = 1 ]                                        # ONE summary, not one per stray
  [ "$(states)" = UNDECLARED-SUMMARY ]
  [ "$(field detail)" = "2 live com.claude labels undeclared" ]
  [ "$(field subject)" = "com.claude.strayA,com.claude.strayB" ]
  # a manifest gap is not a daemon fault: it must NOT fail the declared-run gate
  run fleet --check
  [ "$status" -eq 0 ]

  # POSITIVE CONTROL: declare them and the summary disappears entirely.
  manifest 'com.claude.declared | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.strayA | retired | 300 | - | 1 | 18-fleet-activate.sh' \
           'com.claude.strayB | retired | 300 | - | 1 | 18-fleet-activate.sh'
  [ "$(rows)" = 0 ]
}

# ── sensor failure ────────────────────────────────────────────────────────────────────────────────
@test "sensor failure yields NO row and a named UNKNOWN, never a vacuous pass" {
  have_subject
  plist com.claude.u1 "$D/u1.log"
  age_file "$D/u1.log" 999999                 # stale enough to row IF the sensors were readable
  manifest 'com.claude.u1 | run | 300 | auto | 1 | 18-fleet-activate.sh'

  # (a) launchctl absent entirely
  run env CC_FLEET_LAUNCHCTL_BIN="$D/nonexistent" "$FLEET" --json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run env CC_FLEET_LAUNCHCTL_BIN="$D/nonexistent" "$FLEET" --table
  printf '%s\n' "$output" | grep -q 'UNKNOWN .*com.claude.u1' || false
  run env CC_FLEET_LAUNCHCTL_BIN="$D/nonexistent" "$FLEET" --check
  [ "$status" -eq 1 ]                         # a check that cannot RUN must never pass

  # (b) DELIBERATE CHANGE 2026-07-29, not a relaxed assertion — this case used to assert UNKNOWN
  # (no row). It was wrong: installed (S1 passed) + not disabled (S2 passed) + launchctl saying the
  # label is absent from the domain is a DETERMINED FAULT, not a missing sensor. Folding it into
  # UNKNOWN made the fleet's most common live fault emit NO row on the board built to show it —
  # measured the same day, when com.claude.dispatcher, com.claude.discovery and
  # com.claude.postland-verify each silently dropped out of the domain while enabled and installed.
  # It is now S2b NOT-LOADED and it ROWS. The UNKNOWN contract is unchanged for (a) and (c), which
  # are the genuine broken-sensor cases — that split is the point, so assert BOTH halves here.
  run "$FLEET" --json
  [ "$(printf '%s\n' "$output" | grep -c .)" = 1 ]
  printf '%s\n' "$output" | grep -q '"state":"NOT-LOADED"' || false
  printf '%s\n' "$output" | grep -q '"subject":"com.claude.u1"' || false
  run "$FLEET" --table
  printf '%s\n' "$output" | grep -q 'NOT-LOADED .*com.claude.u1' || false
  # ...and it must NOT be reported as an unrunnable sensor: a determined fault is not an unknown.
  ! printf '%s\n' "$output" | grep -q 'UNKNOWN .*com.claude.u1' || false
  run "$FLEET" --check
  [ "$status" -eq 1 ]                         # a declared-run job that is not loaded fails the gate

  # (c) an unparseable print body (rc=0 but no `runs` line) is a sensor failure, not runs=0
  printfix com.claude.u1 '	state = not running' '	garbage = yes'
  run "$FLEET" --json
  [ -z "$output" ]
  run "$FLEET" --table
  printf '%s\n' "$output" | grep -q 'launchctl-print-unparseable' || false

  # POSITIVE CONTROL: repair the sensor and the SAME fixture rows — the three silences above are
  # the sensors failing, not a reconciler that cannot fire.
  printfix com.claude.u1 '	state = not running' '	runs = 7' '	last exit code = 0'
  [ "$(states)" = STALLED ]
}

@test "a malformed manifest row is UNKNOWN and never poisons its neighbours" {
  have_subject
  plist com.claude.good "$D/good.log"
  printfix com.claude.good '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/good.log" 999999
  manifest '# a comment, and a blank line follows' \
           '' \
           'com.claude.bad | run | not-a-number | auto | 1 | x.sh' \
           'com.claude.wrongexpect | maybe | 300 | auto | 1 | x.sh' \
           'com.claude.good | run | 300 | auto | 1 | 18-fleet-activate.sh'

  [ "$(rows)" = 1 ]                                        # the good row still lands
  [ "$(field subject)" = com.claude.good ]
  fleet --table | grep -q 'manifest-row-malformed' || false
  fleet --table | grep -q 'manifest-expect-invalid' || false
}

# ── kill switch ───────────────────────────────────────────────────────────────────────────────────
@test "CC_FLEET_RECONCILE=off yields zero rows, exit 0, and one stderr line" {
  have_subject
  plist com.claude.k1 "$D/k1.log"
  printfix com.claude.k1 '	state = not running' '	runs = 3' '	last exit code = 1'
  manifest 'com.claude.k1 | run | 300 | auto | 1 | 18-fleet-activate.sh'
  [ "$(states)" = FAILING ]                   # POSITIVE CONTROL first: it fires when ON

  # bats' `run` merges stderr into $output, so the row assertion redirects it: the point here is
  # that no ROW is emitted, and the announcement line is asserted separately below.
  run bash -c "CC_FLEET_RECONCILE=off '$FLEET' --json 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c "CC_FLEET_RECONCILE=off '$FLEET' --check 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # the switch announces itself: an inert reconciler must never be indistinguishable from a green one
  run bash -c "CC_FLEET_RECONCILE=off '$FLEET' --json 2>&1 >/dev/null"
  printf '%s\n' "$output" | grep -q 'reconciliation is OFF' || false
}

# ── the disciplines ───────────────────────────────────────────────────────────────────────────────
@test "launchd is only ever READ: no load/unload/enable/disable/bootstrap/bootout/kickstart" {
  have_subject
  plist com.claude.r1 "$D/r1.log"
  printfix com.claude.r1 '	state = not running' '	runs = 1' '	last exit code = 1'
  disable com.claude.r2; plist com.claude.r2 "$D/r2.log"
  manifest 'com.claude.r1 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.r2 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.r3 | staged | 300 | auto | 1 | 18-fleet-activate.sh'
  fleet --json >/dev/null
  fleet --table >/dev/null

  [ -s "$LCTL_LOG" ]                                       # the stub WAS exercised (not vacuous)
  [ "$(grep -cvE '^(list|print|print-disabled)( |$)' "$LCTL_LOG")" = 0 ]
  # static back-stop: a mutating verb must not appear in the source at all, even unexecuted
  [ "$(grep -cE '(launchctl|LAUNCHCTL_BIN)"? +(load|unload|enable|disable|bootstrap|bootout|kickstart)' "$FLEET")" = 0 ]
}

@test "plutil -extract carries -o - and a full pass rewrites no plist" {
  have_subject
  plist com.claude.p1 "$D/p1.log"
  printfix com.claude.p1 '	state = not running' '	runs = 1' '	last exit code = 0'
  age_file "$D/p1.log" 999999
  manifest 'com.claude.p1 | run | 300 | auto | 1 | 18-fleet-activate.sh'

  cp "$CC_FLEET_LIVE_LAUNCHD/com.claude.p1.plist" "$D/before.plist"
  [ "$(states)" = STALLED ]                                # the extract path really ran
  cmp -s "$D/before.plist" "$CC_FLEET_LIVE_LAUNCHD/com.claude.p1.plist"
  # `-o -` is what makes that true: without it plutil -extract REWRITES the plist in place, which
  # destroyed 5 LaunchAgents on 2026-07-25. Asserted statically too — the incident is unrecoverable.
  # Scanned over the RECONCILER region only — the subject's own --selftest quotes this very pattern,
  # and a check that matches its own source text is not evidence (memory: detector-matches-own-text).
  body="$(sed -n '1,/^if \[ "\$MODE" = selftest \]/p' "$FLEET")"
  n="$(printf '%s\n' "$body" | grep -c 'PLUTIL_BIN.*-extract')"
  m="$(printf '%s\n' "$body" | grep -c 'PLUTIL_BIN.*-extract.*-o -')"
  [ "$n" -ge 1 ]
  [ "$n" = "$m" ]
}

@test "no case statement inside a \$( ) — the bash 3.2 runtime-only death" {
  have_subject
  # STATIC: an opening `$(` and a `case` on the same line is the shape that dies. bash -n and
  # ShellCheck both PASS it, so only a scan or an exercised path catches it.
  [ "$(grep -cE '\$\(.*[^"'"'"']case ' "$FLEET")" = 0 ]

  # DYNAMIC, which is the real proof: every arm is exercised under /bin/bash 3.2 below, and a
  # `case` inside a `$( )` would make the substitution die at RUNTIME and yield a garbage verdict.
  plist com.claude.c2 "$D/c2.log"; disable com.claude.c2
  plist com.claude.c3 "$D/c3.log"; printfix com.claude.c3 '	state = not running' '	runs = 0'
  plist com.claude.c4 "$D/c4.log"; printfix com.claude.c4 '	state = not running' '	runs = 2' '	last exit code = 1'
  plist com.claude.c5 "$D/c5.log"; printfix com.claude.c5 '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/c5.log" 999999
  manifest 'com.claude.c1 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.c2 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.c3 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.c4 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.c5 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.c6 | staged | 300 | auto | 1 | 18-fleet-activate.sh'
  run /bin/bash "$FLEET" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c fleet-inert)" = 6 ]
  printf '%s\n' "$output" | grep -q 'NOT-INSTALLED' || false
  printf '%s\n' "$output" | grep -q 'DISABLED' || false
  printf '%s\n' "$output" | grep -q 'NEVER-RAN' || false
  printf '%s\n' "$output" | grep -q 'FAILING' || false
  printf '%s\n' "$output" | grep -q 'STALLED' || false
  printf '%s\n' "$output" | grep -q 'UNDECIDED' || false
}

@test "every emitted detail is ASCII and <=44 bytes (the board pads by BYTES)" {
  have_subject
  plist com.claude.b2 "$D/b2.log"; disable com.claude.b2
  plist com.claude.b3 "$D/b3.log"; printfix com.claude.b3 '	state = not running' '	runs = 0'
  plist com.claude.b4 "$D/b4.log"; printfix com.claude.b4 '	state = not running' '	runs = 123456' '	last exit code = -128'
  plist com.claude.b5 "$D/b5.log"; printfix com.claude.b5 '	state = not running' '	runs = 2' '	last exit code = 0'
  age_file "$D/b5.log" 99999999               # the widest duration render
  plist com.claude.b6 "$D/b6.log"
  manifest 'com.claude.b1 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.b2 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.b3 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.b4 | run | 300 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.b5 | run | 0 | auto | 1 | 18-fleet-activate.sh' \
           'com.claude.b6 | staged | 300 | auto | 1 | 18-fleet-activate.sh'

  [ "$(rows)" -ge 6 ]                         # not vacuous: there ARE details to measure
  over=0; nonascii=0
  while IFS= read -r det; do
    [ -n "$det" ] || continue
    [ "$(printf '%s' "$det" | wc -c | tr -d ' ')" -le 44 ] || over=$((over + 1))
    if printf '%s' "$det" | LC_ALL=C grep -q '[^ -~]'; then nonascii=$((nonascii + 1)); fi
  done < <(fleet --json | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
  [ "$over" = 0 ]
  [ "$nonascii" = 0 ]
}

# ── --plist-parity ────────────────────────────────────────────────────────────────────────────────
@test "--plist-parity names LIVE-ONLY, REPO-ONLY and CONTENT-DRIFT, and is clean when it should be" {
  have_subject
  plist com.claude.same "$D/same.log"
  cp "$CC_FLEET_LIVE_LAUNCHD/com.claude.same.plist" "$CC_FLEET_REPO_LAUNCHD/com.claude.same.plist"
  manifest 'com.claude.same | retired | 300 | - | 1 | 18-fleet-activate.sh'

  run fleet --plist-parity                    # POSITIVE CONTROL for the clean side
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'parity: clean' || false

  plist com.claude.liveonly "$D/lo.log"                                  # live, no repo SSOT
  printf 'repo only\n' > "$CC_FLEET_REPO_LAUNCHD/com.claude.repoonly.plist"
  plist com.claude.drift "$D/dr.log"
  printf 'different\n' > "$CC_FLEET_REPO_LAUNCHD/com.claude.drift.plist"
  run fleet --plist-parity
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'LIVE-ONLY .*com.claude.liveonly' || false
  printf '%s\n' "$output" | grep -q 'REPO-ONLY .*com.claude.repoonly' || false
  printf '%s\n' "$output" | grep -q 'CONTENT-DRIFT .*com.claude.drift' || false
}

# ── the shipped manifest ──────────────────────────────────────────────────────────────────────────
@test "the committed manifest parses, declares every repo plist, and uses only legal values" {
  have_subject
  M="$ROOT/launchd/fleet.manifest"
  [ -r "$M" ]
  n=0
  while IFS='|' read -r label expect interval evidence owner activate rest; do
    label="$(printf '%s' "$label" | tr -d '[:space:]')"
    case "$label" in ''|'#'*) continue ;; esac
    expect="$(printf '%s' "$expect" | tr -d '[:space:]')"
    interval="$(printf '%s' "$interval" | tr -d '[:space:]')"
    activate="$(printf '%s' "$activate" | tr -d '[:space:]')"
    n=$((n + 1))
    case "$expect" in run|staged|retired) ;; *) echo "bad expect '$expect' for $label"; return 1 ;; esac
    case "$interval" in ''|*[!0-9]*) echo "bad interval '$interval' for $label"; return 1 ;; esac
    [ -n "$activate" ] || { echo "no activate script for $label"; return 1; }
    case "$activate" in *.sh) ;; *) echo "activate '$activate' is not a .sh for $label"; return 1 ;; esac
  done < "$M"
  # 20, not 14: the fleet is TWO label families. com.chrisren.* (6 labels, incl. cc-reaper — row 4's
  # LIVE reaper) was undeclared until 2026-07-29 and therefore invisible to every leg of this tool.
  # 21 since 2026-07-30: com.claude.capacity-alarm. Its plist landed (12595000) with NO manifest row,
  # which made THIS test red on pristine origin/main — the coverage loop below is what caught it, so the
  # count moves with the repair rather than the repair being hidden behind a looser count.
  # 22 since 2026-07-30 (row 7, ACCOUNT_ROUTING_V2 M4): com.claude.relogin. NOT caught by the coverage
  # loop below and it never could have been — that loop globs launchd/*.plist, and this plist lives in
  # launchd/staged/ on purpose (install.sh globs launchd/*.plist, so a plist there would let a routine
  # install activate credentials automation). So a staged-only plist can be undeclared indefinitely with
  # every lint green, which is how a tested poller stayed unscheduled and unreported since 2026-07-26.
  # Same convention as above: the count moves WITH the repair.
  # 23 since 2026-07-30: com.claude.scratchpad-reaper — a TRUNK REPAIR, not row 7's artifact.
  # 97d4984b landed launchd/com.claude.scratchpad-reaper.plist with no manifest row, so THIS test and
  # the coverage lint were RED on pristine origin/main for every lander after it. Identical shape to
  # the capacity-alarm repair above; fixed the same way rather than loosened.
  # 24 since 2026-07-30: com.claude.qos-census (72405f63, MACHINE_CAPACITY_V2 M12). The FIRST bump of
  # a different shape: every prior one paid for a defect (a plist landed with no row, coverage RED).
  # 72405f63 did it CORRECTLY — plist and manifest row in one commit — and this assertion still went
  # red, alone, on pristine origin/main for every lander after it, because the count is a hand-copied
  # mirror of a fact the manifest already states. So the count now also fires on the correct action.
  # It is bumped, NOT derived, because it is the only manifest-side ratchet there is: the coverage
  # loop below runs plist->manifest only, so nothing else in this file would notice a row invented for
  # a plist that does not exist, or a staged row (relogin) silently deleted. Deriving `n` from the
  # plists on disk would buy back the misses and give up that direction — a loosening wearing the
  # costume of a fix. What DID change is the diagnostic: this used to fail as a bare `[ "$n" = 23 ]`
  # with the observed count nowhere in the output, so a lander could not tell a legitimate fleet
  # addition from a plist that skipped its row without re-deriving both by hand.
  # 25 since 2026-08-01: com.claude.worktree-gc-infra — the cron scripts/worktree-gc.sh never had
  # (126 worktrees / 1,193 branches, swept by nothing, because the only worktree reaper with a plist
  # on this box hardcodes the reso repo). Second bump of the qos-census shape: plist and manifest row
  # landed in ONE commit, so this count is the only thing that had to move, and it moves WITH the
  # addition rather than the addition waiting to red someone else's land.
  # 27 since 2026-08-06: com.claude.teammate-reap-alarm (f863034f, `staged`) and
  # com.claude.compressor-sentinel (13bfa557, `run`). Both are the qos-census shape done RIGHT —
  # plist and manifest row in one commit — and both still reddened trunk, which is worth stating
  # plainly because it is now the RULE and not the exception: the smoke is the land's only test
  # work, and on this box it mostly reads `smoke:"skipped"` (R7 load-shed at 1-min load >= 8), so
  # a hand-copied count is structurally a POST-land finding. cc-fleet.bats IS a `--direct` suite of
  # both diffs — `gate-select.sh --direct f863034f^..f863034f` names it — so selection was never the
  # gap and no selector edge would have closed it. The net caught both exactly where it is designed
  # to: postland-verify -> backlog. Do NOT "fix" that by deriving `n` from the plists on disk; the
  # paragraph above already ruled on it, and the shed is a deliberate non-verdict, not a leak.
  # 28 since 2026-08-08: com.claude.devserver-gc (195d91f5) — the capacity-alarm/scratchpad-reaper
  # shape a THIRD time: a plist landed with no manifest row, so the coverage loop below (not this
  # count) was RED on pristine origin/main for every lander after it. The count moves WITH the
  # repair, as every entry above did. Worth stating once more because the shape keeps recurring:
  # the coverage loop is the only leg that catches it, and it can only fire POST-land — the smoke
  # mostly reads `smoke:"skipped"` under R7 load-shed, and `gate-select.sh --direct` naming this
  # suite was never the gap either. postland-verify → backlog caught it exactly as designed.
  # 29 since 2026-08-10: com.claude.auth-timeseries (MASTER M6, backlog b22e519e06cb, `staged`) —
  # plist, manifest row and this count in ONE commit, which is the shape the paragraphs above keep
  # asking for. Note what that costs and what it buys: because the count moved WITH the addition,
  # this suite is GREEN on the landing commit, so postland-verify has nothing to catch and no
  # backlog row is minted. The three entries above each describe the net catching a miss; this one
  # is the case where the net never had to fire, and it is only distinguishable from "the check is
  # asleep" because the coverage loop below runs over the same manifest and would red on a plist
  # with no row. Do NOT read a quiet ratchet as a weak one.
  # 30 since 2026-08-11: com.claude.accounts-keepwarm (b3b14ecbe0, `staged`) — the qos-census shape
  # with the count LEFT BEHIND. b3b14ecbe0 landed the plist under launchd/staged/ and its manifest
  # row in one commit, correctly, and moved neither this count nor anything else that mirrors it, so
  # this assertion alone went red on pristine origin/main for every lander after it. Note which leg
  # caught it and which could not: the coverage loop below walks launchd/*.plist -> manifest, and a
  # STAGED plist is not in that glob, so the only thing standing between a staged addition and a
  # silent manifest is this hand-copied count. That is the direction the paragraph above refuses to
  # give up by deriving `n` from disk, and this entry is what it buys — at the price of a post-land
  # red, because the count cannot be checked before the row exists. Caught by postland-verify
  # (RED 60a8f0cc8ff7, C29-corroborated across two load windows) whose auto-revert then FAILED
  # rc=90 (`git revert b3b14ecbe00` conflicts against the five commits on top), so the veto could
  # not actuate and forward was the only remedy left — which is the branch the FAILED page names.
  # 31 since 2026-08-12: com.claude.cc-gc (backlog 6cab0ab3cb2f) — plist, manifest row and this count
  # in ONE commit, the accounts-keepwarm miss above done right. It is the SECOND staged-out-of-glob
  # addition, so re-read what that means here: launchd/staged/ is outside the coverage loop's
  # `launchd/*.plist` glob on purpose (a standing DELETER must not be armable by a routine install),
  # which leaves this hand-copied count as the ONLY leg that can notice it. That is the whole reason
  # the block above refuses to derive `n` from disk, and it is why this entry had to move with the
  # addition rather than be left for postland-verify — for a staged plist there is no second net.
  # 32 since 2026-08-17: com.claude.browser-spin-guard. The capacity-alarm/scratchpad-reaper/
  # devserver-gc shape a FOURTH time — a plist landed (438883e365ec) with no manifest row, so the
  # coverage loop below went RED on trunk for every lander after it, and postland-verify bisected it
  # to that commit. Repaired forward, count moving WITH the repair as every entry above did.
  # Worth one line on WHY the lander missed it, since the comments above keep noting the recurrence:
  # nothing in the land gate reads this file. cc-fleet.bats is a `--direct` suite of any diff that
  # touches launchd/, but the land's smoke is load-shed on a busy box (R7) — and that box was at load
  # 244 at the time, from the very wedge the new plist exists to catch. So the one land most likely
  # to add a plist was also the one least able to test it. That is an argument for the §4.4 chokepoint
  # lint, not for deriving `n` from disk, which the block above has already ruled out twice.
  if [ "$n" != 32 ]; then
    echo "manifest declares $n labels, expected 32 — if a plist was legitimately added or retired,"
    echo "move this count and say why (see the block above); if not, a row is missing. Declared:"
    grep -vE '^[[:space:]]*(#|$)' "$M" | cut -d'|' -f1 | sed 's/[[:space:]]//g; s/^/  /'
    return 1
  fi

  # three-way coverage: every committed plist is declared (the lint §4.4 enforces at the chokepoint)
  for f in "$ROOT"/launchd/com.claude.*.plist "$ROOT"/launchd/com.chrisren.*.plist; do
    [ -f "$f" ] || continue
    b="${f##*/}"; lbl="${b%.plist}"
    grep -q "^$lbl *|" "$M" || { echo "repo plist $lbl is UNDECLARED in the manifest"; return 1; }
  done
}

# ── the supervisor's own declaration (audit 2026-07-22 V6) ────────────────────────────────────────
# Two properties that are easy to "tidy" back into breakage, so they are pinned here rather than only
# argued in the manifest's comments.
@test "lead-supervisor is declared run, and its evidence is NOT the dead stdout sensor (V6)" {
  have_subject
  M="$ROOT/launchd/fleet.manifest"
  row="$(grep '^com\.claude\.lead-supervisor *|' "$M")"
  [ -n "$row" ]
  # `run`, not `staged`: this manifest IS the absence reader V6 found missing, and a `staged` label is
  # never evaluated (one UNDECIDED row) — so leaving it staged means the supervisor can be dark forever
  # with nothing saying so, which is the finding rather than a fix for it.
  expect="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$2); print $2}')"
  [ "$expect" = run ]
  # NOT `auto`: `auto` reads StandardOutPath, and this daemon redirects every line it writes to files,
  # so its stdout stays 0 bytes even when healthy — an evidence sensor that can only ever say STALLED.
  # (Measured 2026-07-29: supervisor.out.log 0 bytes since Jul 14 vs supervisor.log at 1.2MB.)
  evidence="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$4); print $4}')"
  [ "$evidence" != auto ]
  [ "$evidence" != - ]
  case "$evidence" in *supervisor.log) ;; *) echo "evidence '$evidence' is not the per-sweep artifact"; return 1 ;; esac
}

@test "lead-deathwatch is NOT declared, and lead-reconciler is staged OUT of the manifest (named gates)" {
  have_subject
  M="$ROOT/launchd/fleet.manifest"
  # Neither may carry a row: a row needs a plist, and a plist for either would claim coverage that does
  # not exist — deathwatch has no production watch-file producer (~100% abstain, inert by construction)
  # and the reconciler's roster A is unwired (an empty roster alarms on every live pid). Both gates are
  # named in the manifest's comment block; this asserts nobody quietly promoted one to a row instead.
  ! grep -q '^com\.claude\.lead-deathwatch *|' "$M" || false
  ! grep -q '^com\.claude\.lead-reconciler *|' "$M" || false
  # ...and the reconciler's pin really is StartInterval, never KeepAlive: it has only a `--once` mode,
  # and KeepAlive on a one-shot relaunches it at the 10s throttle floor forever.
  P="$ROOT/launchd/staged/com.claude.lead-reconciler.plist"
  [ -r "$P" ]
  # Match the KEY, never the word: that plist's comment block explains at length WHY KeepAlive is wrong
  # here, so a bare `grep KeepAlive` matches the explanation and convicts the correct file (the
  # detector-matches-its-own-text trap — prose is never evidence about behaviour).
  grep -q '<key>StartInterval</key>' "$P"
  ! grep -q '<key>KeepAlive</key>' "$P"
}

# ── ok_exits — a DESIGNED non-zero verdict is not a failure (plan §5 F20) ────────────────────────
# Live cause: com.claude.deploy-live exits 1 to mean "no GREEN stamp, nothing safe to deploy"
# (verified via `deploy-live.sh --dry-run`). Keying S4 on exit!=0 alone put a permanent false row
# on a healthy job — the alarm-fatigue failure the design exists to prevent.
@test "ok_exits: a declared-healthy nonzero exit does NOT row; the same fixture without it DOES" {
  have_subject
  plist com.claude.ok1 "$D/ok1.log"
  printfix com.claude.ok1 '	state = not running' '	runs = 18' '	last exit code = 1'

  # declared healthy ⇒ silent
  manifest 'com.claude.ok1 | run | 600 | - | 1 | 14-land-pipeline-v2-activate.sh | 0,1'
  [ "$(rows)" = 0 ]

  # DISCRIMINATING CONTROL: identical fixture, ok_exits omitted ⇒ defaults to 0 ⇒ S4 fires.
  # Without this pair, a cc-fleet that never rows anything would pass the assertion above.
  manifest 'com.claude.ok1 | run | 600 | - | 1 | 14-land-pipeline-v2-activate.sh'
  [ "$(rows)" = 1 ]
  [ "$(states)" = FAILING ]

  # whole-field match, never substring: exit 1 must NOT be satisfied by an ok_exits of "13"
  manifest 'com.claude.ok1 | run | 600 | - | 1 | 14-land-pipeline-v2-activate.sh | 13'
  [ "$(states)" = FAILING ]

  # a malformed value degrades to 0 rather than crashing the row (a parser that dies is a dead sensor)
  manifest 'com.claude.ok1 | run | 600 | - | 1 | 14-land-pipeline-v2-activate.sh | yes please'
  [ "$(states)" = FAILING ]
}

# ── evidence '-' — no durable product ⇒ S5 is UNPROVABLE ⇒ no verdict, not a red (R8) ────────────
@test "evidence '-': a job with no per-run artifact is NEVER STALLED; an 'auto' peer still is" {
  have_subject
  plist com.claude.ev1 "$D/ev1.log"
  printfix com.claude.ev1 '	state = not running' '	runs = 9' '	last exit code = 0'
  age_file "$D/ev1.log" 999999                      # maximally stale on disk

  manifest 'com.claude.ev1 | run | 300 | - | 1 | 14-land-pipeline-v2-activate.sh'
  [ "$(rows)" = 0 ]

  # DISCRIMINATING CONTROL: identical fixture declaring `auto` DOES row STALLED — so the silence
  # above is attributable to the evidence declaration and not to a detector that never fires.
  manifest 'com.claude.ev1 | run | 300 | auto | 1 | 14-land-pipeline-v2-activate.sh'
  [ "$(rows)" = 1 ]
  [ "$(states)" = STALLED ]
}
