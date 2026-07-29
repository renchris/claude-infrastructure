#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked
#   from those test subshells rather than from file scope (SC2329).
#
# cc-blockers-fleet — DAEMON_FLEET_V2 §4.3 (the fleet-inert rows) and §4.4 (plist SSOT parity), the
# two ADDITIVE legs cc-blockers gained for row 12. Deliberately a separate file from
# tests/cc-blockers.bats: that suite is the additive proof (it must stay green, untouched), so
# mixing the new subjects into it would destroy the very signal it carries.
#
# HERMETIC BY CONSTRUCTION: setup() fixtures $HOME, every land-pipeline sensor cc-blockers reads, the
# board, launchctl, the fleet producer, and BOTH sides of the plist parity compare. Nothing here
# reads or writes the operator's live ~/.claude, ~/Library/LaunchAgents or real launchd — a parity
# check is a `cmp`, never a plutil (`plutil -extract` without `-o -` REWRITES the plist in place and
# destroyed 5 LaunchAgents on 2026-07-25), and no test ever loads, enables or bootstraps anything.
#
# EVERY TEST RUNS THE SUBJECT THROUGH /bin/bash EXPLICITLY (`ccb`), not the shebang's PATH bash. The
# production readers are macOS bash 3.2, whose command-substitution parser mis-reads a `case`
# pattern's `)` as the closing paren — a class of bug `bash -n` and shellcheck both pass, that a
# homebrew bash 5 on PATH would hide, and that has ALREADY shipped in this very file as a FALSE
# verifier-inert row. The new legs add a `case` (in deref) and two `$( )` layers, so this matters.
#
# EVERY non-final `[[ ]]` / `(( ))` / `!` / `A && B` carries `|| false`: under bats those compound
# forms are errexit-EXEMPT, i.e. DEAD assertions that silently always pass (7 were revived in this
# repo already). `[ ]` and simple pipelines are live, which is why they are the default here.
#
# EVERY ABSENCE ASSERTION CARRIES A POSITIVE CONTROL in the same test. A detector that always fires
# is not a detector — and neither is one that can never fire. Each "no rows" case therefore flips
# exactly one condition and re-runs to prove the row DOES appear, and §4.4's clean-board case proves
# the parity leg can go quiet with a real repo/live pair in front of it.
#
# RED-PROOF: every test below fails against the pristine pre-change tree. Point the suite at one:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CC_FLEET_SUBJECT_ROOT="$t" bats tests/cc-blockers-fleet.bats
# On that tree `--plist-parity` is an unknown arg (exit 2) and no fleet-inert row can exist, so the
# suite is 0 passes. Recovered with `git archive`, never a hand-edited approximation: an approximated
# control passes vacuously (memory control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_FLEET_SUBJECT_ROOT:-$REPO}"          # the RED-PROOF seam — see the header recipe
  C="$ROOT/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"

  # The deterministically SILENT baseline tests/cc-blockers.bats established: a stamps dir that
  # EXISTS but is empty, no land.log, no deploy checkout, no launchctl. Every row in this suite is
  # therefore switched on deliberately, one test at a time.
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_POSTLAND_DIR="$D/postland"; mkdir -p "$CC_POSTLAND_DIR/stamps"
  export CC_LAND_LOG="$D/absent-land.log"
  export DEPLOY_REPO="$D/absent-repo"
  export CC_BLOCKERS_LAUNCHCTL_BIN="$D/absent-launchctl"
  # Both parity sides fixtured. Without these, resolve_plist_repo derefs BASH_SOURCE to the real
  # checkout and the live side is the operator's real ~/Library/LaunchAgents.
  export CC_BLOCKERS_PLIST_REPO="$D/repo-launchd"; mkdir -p "$CC_BLOCKERS_PLIST_REPO"
  export CC_BLOCKERS_LAUNCHAGENTS_DIR="$D/live-agents"; mkdir -p "$CC_BLOCKERS_LAUNCHAGENTS_DIR"
  FLEET_ARGV="$D/fleet-argv.log"

  ccb() { /bin/bash "$C" "$@"; }

  frow() { # <state> <subject> <detail> <recover_cmd> — one producer-contract fleet-inert line
    jq -nc --arg s "$1" --arg su "$2" --arg d "$3" --arg c "$4" \
      '{kind:"fleet-inert",state:$s,detail:$d,subject:$su,recover_cmd:$c,ts:1700000000}'; }

  # PAYLOAD VIA A FILE, never a pipe into mk_fleet. `frow ... | mk_fleet 0` puts the helper in a
  # SUBSHELL, so its `export CC_BLOCKERS_FLEET_BIN` never reaches the test body — the stub lands on
  # disk and the subject never looks at it, which reads as "fail-open works" while asserting nothing.
  # Exactly the dead-assertion shape this suite is required to avoid; caught by the argv pin below.
  FPAY="$D/fleet-payload"
  mk_fleet() { # <exit-code> [path] — payload already written to $FPAY; writes+exports an exec stub
    local rc="${1:-0}" p="${2:-$D/cc-fleet}"
    [ -f "$D/fleet-payload" ] || : > "$D/fleet-payload"
    mkdir -p "$(dirname "$p")"
    { printf '#!/bin/bash\n'
      printf 'printf "%%s\\n" "$*" >> %s\n' "$FLEET_ARGV"
      printf 'cat %s\n' "$D/fleet-payload"
      printf 'exit %s\n' "$rc"
    } > "$p"
    chmod +x "$p"
    export CC_BLOCKERS_FLEET_BIN="$p"; }

  plist() { # <dir> <label> <marker-text> — a fixture plist (bytes, never parsed by the subject)
    mkdir -p "$1"
    printf '<?xml version="1.0"?>\n<plist><dict><key>Label</key><string>%s</string><key>M</key><string>%s</string></dict></plist>\n' \
      "$2" "$3" > "$1/$2.plist"; }

  kinds() { ccb --json | jq -r '.[].kind' | sort | tr '\n' ' '; }
  pstates() { ccb --plist-parity --json | jq -r '.[].state' | sort | tr '\n' ' '; }
}

# ── §4.3 the fleet-inert rows ────────────────────────────────────────────────────────────────────

@test "fleet: the fixtured baseline is SILENT, and one row is all it takes to break the silence" {
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  run ccb
  # COUNTING form, not `grep -qv`: `-qv` succeeds when ANY line lacks the pattern, i.e. it is true
  # of every multi-line output — a dead assertion wearing a negation.
  [ "$(echo "$output" | grep -c 'FLEET' || true)" = 0 ]
  frow DISABLED com.claude.discovery 'launchd label sits in the disabled DB' 'x' > "$FPAY"; mk_fleet 0
  run ccb --json                                         # POSITIVE CONTROL: the same board, one row
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
}

@test "fleet: rows pass THROUGH to --json with kind, state, subject and recover_cmd intact" {
  frow NOT-INSTALLED com.claude.fleet-reconcile 'declared run; no plist in LaunchAgents' \
    'CONFIRM=1 bash /x/18-fleet-activate.sh' > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "fleet-inert" ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "NOT-INSTALLED" ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.fleet-reconcile" ]
  [ "$(echo "$output" | jq -r '.[0].recover_cmd')" = "CONFIRM=1 bash /x/18-fleet-activate.sh" ]
}

@test "fleet: rows render through the SHARED alarm_table renderer, under their own heading" {
  frow STALLED com.claude.log-rotation 'loaded+enabled but no run in 26h' 'launchctl print x' > "$FPAY"; mk_fleet 0
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'FLEET — 1 label(s) not in their declared state'
  echo "$output" | grep -qE '^KIND +STATE +SUBJECT +DETAIL +RECOVER$'
  echo "$output" | grep -q 'fleet-inert'
  echo "$output" | grep -q 'STALLED'
  echo "$output" | grep -q 'com.claude.log-rotation'
  echo "$output" | grep -q 'loaded+enabled but no run in 26h'
  echo "$output" | grep -q 'launchctl print x'
}

@test "fleet: the SUBJECT column is present, and a row is ATTRIBUTABLE to its label" {
  # Measured against the real bin/cc-fleet: 13 rows, 6 of them identical in KIND, STATE, DETAIL and
  # RECOVER (three DISABLED labels share one activation script). Without the subject the board hands
  # over a verdict that names no job — the floor's whole promise (§4.3) is one honest verdict PER
  # LABEL, and a row you cannot attribute is not one.
  { frow DISABLED com.claude.log-rotation 'disabled at the domain level (C10)' 'CONFIRM=1 bash /x/17.sh'
    frow DISABLED com.claude.session-search-sweep 'disabled at the domain level (C10)' 'CONFIRM=1 bash /x/17.sh'
    frow DISABLED com.claude.session-search-backfill 'disabled at the domain level (C10)' 'CONFIRM=1 bash /x/17.sh'
  } > "$FPAY"; mk_fleet 0
  run ccb
  [ "$status" -eq 0 ]
  # three rows that differ ONLY in the label: each must be individually identifiable
  [ "$(echo "$output" | grep -c 'com.claude.log-rotation')" = 1 ]
  [ "$(echo "$output" | grep -c 'com.claude.session-search-sweep')" = 1 ]
  [ "$(echo "$output" | grep -c 'com.claude.session-search-backfill')" = 1 ]
  # the longest declared label (34 bytes) is shown WHOLE — a label is pasted into launchctl verbatim
  echo "$output" | grep -q 'com.claude.session-search-backfill '
}

@test "render: the LAND and DISPATCH tables keep their 4-column shape byte-for-byte" {
  # The ADDITIVE proof at RENDER level. The subject column is opt-in precisely so that adding a third
  # family cannot reshape the two that were already there — their .subject is a PATH (a stamps dir, a
  # deploy checkout) that a 34-byte cell would truncate into noise.
  export CC_POSTLAND_DIR="$D/never"; : > "$CC_LAND_LOG"        # ⇒ verifier-inert / NEVER-ACTIVATED
  frow DISABLED com.claude.log-rotation 'd' 'c' > "$FPAY"; mk_fleet 0
  run ccb
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cE '^KIND +STATE +DETAIL +RECOVER$')" = 1 ]         # LAND: 4 columns
  [ "$(echo "$output" | grep -cE '^KIND +STATE +SUBJECT +DETAIL +RECOVER$')" = 1 ] # FLEET: 5
  # and the LAND row itself carries no subject cell: its detail must sit where it always sat
  echo "$output" | grep -qE '^verifier-inert  +NEVER-ACTIVATED +no stamps dir'
}

@test "fleet: every declared state reaches the board — the consumer filters on kind, never state" {
  # Filtering on the state ENUM would silently drop a state the reconciler adds later; the whole
  # point of the floor is that every label gets an honest verdict, including one this file has
  # never heard of.
  { frow NOT-INSTALLED a 'd1' 'c1'; frow DISABLED b 'd2' 'c2'; frow NEVER-RAN c 'd3' 'c3'
    frow FAILING d 'd4' 'c4'; frow STALLED e 'd5' 'c5'; frow UNDECIDED f 'd6' 'c6'
    frow UNDECLARED-SUMMARY g 'd7' 'c7'; frow SOME-FUTURE-STATE h 'd8' 'c8'; } > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$(echo "$output" | jq '[.[]|select(.kind=="fleet-inert")]|length')" = 8 ]
}

@test "fleet: the producer is invoked as \`cc-fleet --json\` (the frozen contract, pinned)" {
  frow DISABLED x 'd' 'c' > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(cat "$FLEET_ARGV")" = "--json" ]
}

@test "fleet: an ABSENT producer yields zero rows and an unchanged exit (fail-open)" {
  export CC_BLOCKERS_FLEET_BIN="$D/no-such-cc-fleet"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked sessions'      # the clean-board message, unchanged
  # POSITIVE CONTROL: the SAME path, now present and executable, must produce the row — otherwise
  # "zero rows" above proves only that this suite cannot make a row at all.
  frow DISABLED com.claude.x 'd' 'c' > "$FPAY"; mk_fleet 0 "$D/no-such-cc-fleet"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
}

@test "fleet: a NON-EXECUTABLE producer yields zero rows (fail-open on the mode bit alone)" {
  frow DISABLED com.claude.x 'd' 'c' > "$D/payload"
  cp "$D/payload" "$D/cc-fleet-noexec"; chmod 0644 "$D/cc-fleet-noexec"
  export CC_BLOCKERS_FLEET_BIN="$D/cc-fleet-noexec"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  # POSITIVE CONTROL: same bytes, same path, only the x-bit flipped — via a real stub so the file
  # is actually runnable rather than a plist-looking blob.
  frow DISABLED com.claude.x 'd' 'c' > "$FPAY"; mk_fleet 0 "$D/cc-fleet-noexec"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
}

@test "fleet: a producer exiting NON-ZERO yields zero rows and no error" {
  frow FAILING com.claude.y 'd' 'c' > "$FPAY"; mk_fleet 3
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked sessions'
  # POSITIVE CONTROL: byte-identical payload, exit 0 — so the absence above is the EXIT CODE's doing.
  frow FAILING com.claude.y 'd' 'c' > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
}

@test "fleet: GARBAGE output does not crash, and the good line in the same stream survives" {
  { printf '%s\n' 'THIS IS NOT JSON at all'
    printf '%s\n' '"a bare string"'
    printf '%s\n' '{ unterminated'
    frow DISABLED com.claude.z 'd' 'c'; } > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.z" ]
}

@test "fleet: a garbage producer cannot take the LAND-PIPELINE row down with it (no collateral)" {
  # The reason the kind-filter lives in fleet_alarm_rows and not in the shared slurp: one bad line
  # reaching `jq -s '.'` fails the WHOLE array, and the `|| true` beside it then hands back '[]' —
  # silently deleting the land-pipeline and dispatch rows. A sensor's own failure must never blind
  # the sensors beside it.
  export CC_POSTLAND_DIR="$D/never"                     # ⇒ verifier-inert / NEVER-ACTIVATED
  : > "$CC_LAND_LOG"                                    # its evidence gate
  printf '%s\n' 'not json' 'also not json' > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "verifier-inert" ]
  # POSITIVE CONTROL: swap the garbage for one valid row — BOTH families must then be present, which
  # is what proves the assertion above measured collateral damage and not a swallowed board.
  frow DISABLED com.claude.z 'd' 'c' > "$FPAY"; mk_fleet 0
  [ "$(kinds)" = "fleet-inert verifier-inert " ]
}

@test "fleet: non-fleet kinds emitted by the producer are IGNORED, not laundered onto the board" {
  { printf '%s\n' '{"kind":"trunk-red","state":"PERSISTENT-RED","detail":"d","subject":"s"}'
    printf '%s\n' '{"kind":"safeguard-blocked","pane":"P","refusal":"r"}'
    printf '%s\n' '[{"kind":"fleet-inert","state":"DISABLED"}]'; } > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  # POSITIVE CONTROL: the same stream plus a real fleet-inert OBJECT ⇒ exactly one row.
  { printf '%s\n' '{"kind":"trunk-red","state":"PERSISTENT-RED","detail":"d","subject":"s"}'
    frow DISABLED com.claude.z 'd' 'c'; } > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "fleet-inert" ]
}

@test "fleet: the DEFAULT producer path is DEPLOY_REPO-rooted, never the live ~/.claude/bin" {
  # HERMETICITY, load-bearing. tests/cc-blockers.bats fixtures every sensor but NOT $HOME, so a
  # $HOME/.claude/bin/cc-fleet default would make that suite read the operator's real fleet the
  # moment the binary deployed — the phantom-row defect the verifier alarm and the dispatch alarm
  # each had to fix already. DEPLOY_REPO is a seam every cc-blockers suite already fixtures, and in
  # production the two paths are the SAME FILE (~/.claude/bin/cc-* are symlinks into the checkout).
  unset CC_BLOCKERS_FLEET_BIN
  mkdir -p "$HOME/.claude/bin"
  frow DISABLED com.claude.trap 'the operator live fleet must NOT be read' 'c' > "$FPAY"; mk_fleet 0 "$HOME/.claude/bin/cc-fleet"
  unset CC_BLOCKERS_FLEET_BIN
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  [ ! -f "$FLEET_ARGV" ]                                 # it was never even invoked
  # POSITIVE CONTROL: the same stub under DEPLOY_REPO/bin ⇒ the row appears, so the default path is
  # reachable and this test measured WHICH path, not a dead sensor.
  frow DISABLED com.claude.ok 'd' 'c' > "$FPAY"; mk_fleet 0 "$DEPLOY_REPO/bin/cc-fleet"
  unset CC_BLOCKERS_FLEET_BIN
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.ok" ]
}

@test "fleet: overlap with a dispatch-inert row on the SAME label is KEPT, never deduped" {
  # §4.3: the specific row carries meaning a generic reconciler cannot express, and the fleet row is
  # the FLOOR. Two rows for one label is the design; dedup would delete the specific one.
  { printf '#!/bin/bash\n'
    printf 'if [ "${1:-}" = "list" ]; then printf "%%s\\t%%s\\t%%s\\n" - 0 com.claude.other; exit 0; fi\n'
    printf 'exit 0\n'; } > "$D/launchctl-stub"
  chmod +x "$D/launchctl-stub"
  export CC_BLOCKERS_LAUNCHCTL_BIN="$D/launchctl-stub"
  # the dispatch alarm's EXISTENCE-EVIDENCE gate: >=1 actor=="cc-dispatch" record. Relative stamp,
  # signed offset — never a future absolute literal (test-walltime-lint).
  jq -nc --arg ts "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts:$ts,actor:"cc-dispatch",kind:"decision"}' > "$CC_REAPER_IDL"
  frow DISABLED com.claude.dispatcher 'launchd label sits in the disabled DB' 'c' > "$FPAY"; mk_fleet 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.subject=="com.claude.dispatcher")]|length')" = 2 ]
  [ "$(kinds)" = "dispatch-inert fleet-inert " ]
  run ccb
  echo "$output" | grep -q 'DISPATCH — 1 alarm(s)'      # two tables, one renderer, both headed
  echo "$output" | grep -q 'FLEET — 1 label(s)'
}

# ── §4.4 plist SSOT parity ───────────────────────────────────────────────────────────────────────

@test "parity: a perfect repo/live pair and a zero-row producer yield a CLEAN board (can go quiet)" {
  # THE POSITIVE CONTROL FOR THE WHOLE LEG. A detector that always fires is not a detector.
  plist "$CC_BLOCKERS_PLIST_REPO"      com.claude.discovery same
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.discovery same
  plist "$CC_BLOCKERS_PLIST_REPO"      com.claude.dispatcher same
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.dispatcher same
  : > "$FPAY"; mk_fleet 0
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  run ccb --plist-parity
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 drift'
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked sessions'
}

@test "parity LIVE-ONLY: installed but never committed — com.claude.lead-supervisor is caught" {
  # The real box has EXACTLY this drift today (~/Library/LaunchAgents/com.claude.lead-supervisor.plist
  # with no launchd/ counterpart), which is the label fixtured here by name. The fixture, not the
  # live dir, is the subject: reading the operator's real ~/Library/LaunchAgents would make this
  # suite's verdict a function of whatever is installed on the box.
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  plist "$CC_BLOCKERS_PLIST_REPO"       com.claude.discovery same
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.discovery same
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "plist-parity" ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "LIVE-ONLY" ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.lead-supervisor" ]
  run ccb --plist-parity
  echo "$output" | grep -q 'LIVE-ONLY'
  echo "$output" | grep -q 'com.claude.lead-supervisor'
  echo "$output" | grep -q 'installed but never committed'
  # the RECOVER cell is the exact runnable command that rescues the unrecoverable copy
  echo "$output" | grep -q "cp $CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.lead-supervisor.plist $CC_BLOCKERS_PLIST_REPO/com.claude.lead-supervisor.plist"
}

@test "parity REPO-ONLY: committed but never installed, so launchd never loads it" {
  plist "$CC_BLOCKERS_PLIST_REPO" com.claude.fleet-reconcile repo
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "REPO-ONLY" ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.fleet-reconcile" ]
  run ccb --plist-parity
  echo "$output" | grep -q 'REPO-ONLY'
  echo "$output" | grep -q 'committed but not installed'
  echo "$output" | grep -q "cp $CC_BLOCKERS_PLIST_REPO/com.claude.fleet-reconcile.plist $CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.fleet-reconcile.plist"
}

@test "parity CONTENT-DRIFT: both exist, bytes differ — the copy launchd loads is not the SSOT" {
  plist "$CC_BLOCKERS_PLIST_REPO"       com.claude.dispatcher committed
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.dispatcher DRIFTED
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "CONTENT-DRIFT" ]
  [ "$(echo "$output" | jq -r '.[0].subject')" = "com.claude.dispatcher" ]
  run ccb --plist-parity
  echo "$output" | grep -q 'CONTENT-DRIFT'
  echo "$output" | grep -q 'live bytes differ from the committed SSOT'
  echo "$output" | grep -q "diff $CC_BLOCKERS_PLIST_REPO/com.claude.dispatcher.plist $CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.dispatcher.plist"
  # POSITIVE CONTROL for the compare itself: make the bytes match ⇒ the row must clear.
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.dispatcher committed
  [ "$(pstates)" = "" ]
}

@test "parity: all three classes at once, each named separately" {
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  plist "$CC_BLOCKERS_PLIST_REPO"       com.claude.fleet-reconcile repo
  plist "$CC_BLOCKERS_PLIST_REPO"       com.claude.dispatcher committed
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.dispatcher DRIFTED
  [ "$(pstates)" = "CONTENT-DRIFT LIVE-ONLY REPO-ONLY " ]
  run ccb --plist-parity
  echo "$output" | grep -q 'PLIST-SSOT PARITY — 3 drift(s)'
}

@test "parity: a \`.plist.local\` marker exempts LIVE-ONLY, and only LIVE-ONLY" {
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  : > "$CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.lead-supervisor.plist.local"
  [ "$(pstates)" = "" ]
  # POSITIVE CONTROL: drop the marker ⇒ the row returns. Without this the exemption above could be
  # hiding a leg that never fires at all.
  rm -f "$CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.lead-supervisor.plist.local"
  [ "$(pstates)" = "LIVE-ONLY " ]
  # and the exemption is scoped: a marked file whose bytes DRIFT still reports.
  : > "$CC_BLOCKERS_LAUNCHAGENTS_DIR/com.claude.lead-supervisor.plist.local"
  plist "$CC_BLOCKERS_PLIST_REPO" com.claude.lead-supervisor committed
  [ "$(pstates)" = "CONTENT-DRIFT " ]
}

@test "parity: only com.claude.* plists are in scope, and launchd/staged/ is out by construction" {
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.chrisren.autonomy-sweep live   # another vendor's label
  plist "$CC_BLOCKERS_PLIST_REPO/staged" com.claude.relogin staged         # deliberately uninstalled
  [ "$(pstates)" = "" ]
  # POSITIVE CONTROL: one in-scope live-only plist beside them ⇒ exactly one row, so the silence
  # above is the SCOPE and not a dead leg.
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  [ "$(pstates)" = "LIVE-ONLY " ]
}

@test "parity: an UNRESOLVABLE repo side is REPORTED as a row, never a silent pass" {
  export CC_BLOCKERS_PLIST_REPO="$D/no-such-launchd"
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "UNRESOLVABLE" ]
  echo "$output" | jq -r '.[0].detail' | grep -q 'DID NOT RUN'
  run ccb --plist-parity
  echo "$output" | grep -q 'UNRESOLVABLE'
  echo "$output" | grep -q 'DID NOT RUN'
  # POSITIVE CONTROL: point it at a real dir ⇒ the UNRESOLVABLE row is replaced by the real verdict.
  export CC_BLOCKERS_PLIST_REPO="$D/repo-launchd"
  [ "$(pstates)" = "LIVE-ONLY " ]
}

@test "parity: an absent LaunchAgents dir is REPORTED, never read as 'everything is installed'" {
  plist "$CC_BLOCKERS_PLIST_REPO" com.claude.dispatcher committed
  export CC_BLOCKERS_LAUNCHAGENTS_DIR="$D/no-such-agents-dir"
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "UNRESOLVABLE" ]
  # POSITIVE CONTROL: create it ⇒ the honest REPO-ONLY verdict, not the non-verdict.
  mkdir -p "$CC_BLOCKERS_LAUNCHAGENTS_DIR"
  [ "$(pstates)" = "REPO-ONLY " ]
}

@test "parity: ~/.claude can NEVER pose as the repo SSOT (the .git gate, backlog 816015ecb30b)" {
  # A sibling parity assert resolved REPO=~/.claude via an underefed BASH_SOURCE and every leg
  # exited 0 VACUOUSLY. Reproduced exactly: the subject is run from a $HOME/.claude/bin copy, with a
  # $HOME/.claude/launchd/ dir present as the bait, and no .git anywhere. The verdict must be the
  # non-verdict, not "0 drift".
  unset CC_BLOCKERS_PLIST_REPO
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/launchd"
  cp "$C" "$HOME/.claude/bin/cc-blockers"
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  run /bin/bash "$HOME/.claude/bin/cc-blockers" --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "UNRESOLVABLE" ]
  [ "$(echo "$output" | jq '[.[]|select(.state=="LIVE-ONLY")]|length')" = 0 ]
  # POSITIVE CONTROL: give that root a `.git` (a FILE, as a linked worktree has) ⇒ it now resolves
  # and reports the real verdict, proving the gate — not a broken deref — produced the row above.
  : > "$HOME/.claude/.git"
  run /bin/bash "$HOME/.claude/bin/cc-blockers" --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "LIVE-ONLY" ]
}

@test "parity is its OWN leg: no plist-parity row ever reaches the default board" {
  # Folding it in would make every suite that renders the default board (and fixtures the board
  # sensors but not \$HOME) read the operator's real ~/Library/LaunchAgents.
  plist "$CC_BLOCKERS_LAUNCHAGENTS_DIR" com.claude.lead-supervisor live
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="plist-parity")]|length')" = 0 ]
  run ccb
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'PLIST-SSOT' || true)" = 0 ]
  # POSITIVE CONTROL: the leg itself does see it.
  [ "$(pstates)" = "LIVE-ONLY " ]
}

@test "args: --plist-parity composes with --json, and an unknown arg still exits 2" {
  run ccb --plist-parity --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]
  run ccb --json --plist-parity
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]
  run ccb --bogus
  [ "$status" -eq 2 ]
  run ccb --plist-parity --bogus
  [ "$status" -eq 2 ]
}
