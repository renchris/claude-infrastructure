#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# cc-sessions — rendering an OFF-BOX session in a local session view
# (docs/plans/CLOUD_OBSERVABILITY.md §9.3).
#
# WHAT IS BEING GUARDED. cc-sessions enumerates ~/.claude/cc-registry and decides liveness with
# `kill -0` on a LOCAL pid. A session running in an Anthropic-managed VM has no such pid, which is
# why §5.2 lists this class of oracle among the three that convert "not on this box" into "dead".
# The fix is not to teach the registry about the cloud — it is to source those rows from `cc-cloud`
# and render them as a separate KIND that carries no local vocabulary at all. The three rules, each
# one test below:
#   1. never a pid/UUID column and never `kill -0`  — a blank pid beside live local pids reads dead
#   2. U0 UNKNOWN renders as the literal word        — an empty cell in a live table reads as absent
#   3. the recover action is `open <url>`            — there is no local process to signal
#
# THE CONTROL IS THE POINT. Without the zero-declaration byte-identity test below you cannot tell a
# working feature from a broken enumerator: an implementation that dropped every local row would
# pass every off-box assertion here. It compares the feature IDLE against the feature ABSENT
# (CC_CLOUD_BIN pointed at nothing) across all three modes, byte for byte.
#
# REAL ARTIFACT, NOT A STUB: `bin/cc-cloud` is the real binary and every "remote" is a real local
# bare repository, so the join under test is the one that will run. Stubbing cc-cloud would test
# the stub and would not notice a consumer that re-derived the state function instead of asking it.
#
# HERMETIC: fixture $HOME, CC_CLOUD_STATE, CC_REGISTRY_DIR, and IT2_BIN pointed at a path that does
# not exist (so the pane signal is UNKNOWN and the lister never touches the operator's iTerm2).
# NO WALL-CLOCK: CC_CLOUD_NOW drives every age.
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET` and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit, so a non-final occurrence of those always passes. POSIX `[ ]` only, and
# `|| false` appended wherever a negation is not the last command.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SESSIONS="$REPO/bin/cc-sessions"
  CLOUD="$REPO/bin/cc-cloud"
  D="$BATS_TEST_TMPDIR"

  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_CLOUD_STATE="$D/cloud"; mkdir -p "$CC_CLOUD_STATE"
  export CC_REGISTRY_DIR="$D/reg";  mkdir -p "$CC_REGISTRY_DIR"
  export CC_CLOUD_BIN="$CLOUD"
  export IT2_BIN="$D/no-such-it2"          # unreadable pane list → fail-safe, no sweep, no IPC
  export CC_CLOUD_NOW=2000000000
  export GIT_CONFIG_NOSYSTEM=1

  have_subject() {
    [ -x "$SESSIONS" ] || { echo "cc-sessions is missing or not executable at $SESSIONS"; return 1; }
    [ -x "$CLOUD" ]    || { echo "cc-cloud is missing or not executable at $CLOUD"; return 1; }
  }

  bare() { git init -q --bare "$D/$1.git" >/dev/null 2>&1; printf '%s' "$D/$1.git"; }

  # A live LOCAL row: the pid is this bats process, so `kill -0` succeeds for real.
  local_row() { # $1=name $2=uuid
    cat > "$CC_REGISTRY_DIR/$2.json" <<EOF
{"paneUUID":"$2","name":"$1","account":"next","pid":$$,"startedAt":1999999000000,"cwd":"/w/local"}
EOF
  }

  # The OFF-BOX block only — everything after the blank line that follows the local table.
  # shellcheck disable=SC2120  # the "$@" pass-through is deliberate: every current caller wants the
  # default table, but a test asking for --json/--names must not have to fork the helper to get it.
  offblock() { "$SESSIONS" "$@" | sed -n '/^OFF-BOX/,$p'; }
}

# ── rule 1: the row appears, as a distinct kind, with no local vocabulary ─────────────────────────
@test "a declared off-box session APPEARS as kind=offbox — and carries no pid, no UUID, no kill" {
  have_subject
  r="$(bare rem)"
  local_row local-one AAAA-1111-BBBB-2222
  cloud_declared=session_01CHQoFxvsoD
  "$CLOUD" declare --id "$cloud_declared" --branch feat/cloud --remote "$r" --repo "" >/dev/null 2>&1

  run "$SESSIONS"
  [ "$status" -eq 0 ]
  # The LOCAL row is untouched — this is an addition, not a replacement.
  printf '%s\n' "$output" | grep -q 'local-one' || false
  printf '%s\n' "$output" | grep -q 'AAAA-1111-BBBB-2222' || false
  # The OFF-BOX row is present, in its own block, labelled with its kind.
  printf '%s\n' "$output" | grep -q '^OFF-BOX' || false
  block="$(offblock)"
  printf '%s\n' "$block" | grep -q "$cloud_declared" || false
  printf '%s\n' "$block" | grep -qw 'offbox' || false

  # RULE 1, asserted as ABSENCE of the local vocabulary inside the off-box block: no pid column, no
  # UUID column, no kill action. A blank pid cell beside live local pids is what reads as "dead".
  ! printf '%s\n' "$block" | grep -qi 'pid'  || false
  ! printf '%s\n' "$block" | grep -qi 'uuid' || false
  ! printf '%s\n' "$block" | grep -qi 'kill' || false
  ! printf '%s\n' "$block" | grep -q  'AAAA-1111-BBBB-2222' || false

  # And the machine surface says the same thing, with no local keys to select on.
  run "$SESSIONS" --offbox --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].kind')" = "offbox" ]
  [ "$(printf '%s' "$output" | jq -r '.[0].id')" = "$cloud_declared" ]
  [ "$(printf '%s' "$output" | jq -r '.[0] | has("pid")')" = "false" ]
  [ "$(printf '%s' "$output" | jq -r '.[0] | has("paneUUID")')" = "false" ]
}

# ── rule 2: U0 renders as the WORD, and a probe that could not run never deletes the row ──────────
@test "UNKNOWN renders as the literal word, never a blank cell — and never as a missing row" {
  have_subject
  gone="$D/never-existed.git"                  # unreachable remote ⇒ cc-cloud's U0 arm
  r="$(bare rem)"
  "$CLOUD" declare --id sess_dark  --branch feat/a --remote "$gone" --repo "" >/dev/null 2>&1
  "$CLOUD" declare --id sess_light --branch feat/b --remote "$r"    --repo "" >/dev/null 2>&1

  block="$(offblock)"
  # The unreachable one reads UNKNOWN...
  printf '%s\n' "$block" | grep -qE '^offbox +sess_dark +UNKNOWN ' || false
  # ...and the POSITIVE CONTROL on the same fixture reads a real verdict, so the renderer is not
  # simply printing UNKNOWN for everything (a cell that is always UNKNOWN carries no bits either).
  printf '%s\n' "$block" | grep -qE '^offbox +sess_light +BOOTING ' || false

  # THE HARDER HALF: the state PROBE itself fails. The row must survive and degrade to UNKNOWN —
  # "could not look" is a non-verdict, and dropping the row would put this lister straight back in
  # the class of local oracles that report a healthy off-box session as absent.
  cat > "$D/cloud-no-state" <<EOF
#!/bin/bash
for a in "\$@"; do [ "\$a" = "--state" ] && exit 1; done
exec "$CLOUD" "\$@"
EOF
  chmod +x "$D/cloud-no-state"
  CC_CLOUD_BIN="$D/cloud-no-state" run "$SESSIONS" --offbox --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r 'length')" -eq 2 ]
  [ "$(printf '%s' "$output" | jq -r '[.[] | select(.state != "UNKNOWN")] | length')" -eq 0 ]
  ! printf '%s' "$output" | jq -e '.[] | select(.state == "")' >/dev/null || false
}

# ── rule 3: the action is the URL ─────────────────────────────────────────────────────────────────
@test "the recover action is open <url>, never a kill — and the declared url is the one used" {
  have_subject
  r="$(bare rem)"
  "$CLOUD" declare --id sess_url --branch feat/a --remote "$r" --repo "" \
    --url 'https://claude.ai/code/session_abc' >/dev/null 2>&1

  block="$(offblock)"
  printf '%s\n' "$block" | grep -q 'open https://claude.ai/code/session_abc' || false
  ! printf '%s\n' "$block" | grep -qi 'kill' || false

  run "$SESSIONS" --offbox --json
  [ "$(printf '%s' "$output" | jq -r '.[0].action')" = "open https://claude.ai/code/session_abc" ]

  # DEFAULT CONTROL: an undeclared url still yields an ACTION, never an empty cell.
  "$CLOUD" declare --id sess_nourl --branch feat/b --remote "$r" --repo "" >/dev/null 2>&1
  run "$SESSIONS" --offbox --json
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id=="sess_nourl") | .action')" = "open https://claude.ai/code" ]
}

# ── retired is terminal for the LIVE views (cc-cloud keeps it for forensics; this view must not) ──
@test "a RETIRED declaration does not appear as live" {
  have_subject
  r="$(bare rem)"
  "$CLOUD" declare --id sess_done --branch feat/a --remote "$r" --repo "" >/dev/null 2>&1
  "$CLOUD" declare --id sess_open --branch feat/b --remote "$r" --repo "" >/dev/null 2>&1
  "$CLOUD" retire  --id sess_done >/dev/null 2>&1

  block="$(offblock)"
  ! printf '%s\n' "$block" | grep -q 'sess_done' || false
  # POSITIVE CONTROL off the same store: the sibling that was NOT retired is still rendered, so the
  # absence above is a filter and not an empty block.
  printf '%s\n' "$block" | grep -q 'sess_open' || false

  run "$SESSIONS" --offbox --json
  [ "$(printf '%s' "$output" | jq -r 'length')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].id')" = "sess_open" ]

  # CONTROL on cc-cloud itself: it still holds the retired declaration. The two views differ on
  # purpose, and this pins that the filtering happens HERE rather than by losing the record.
  run "$CLOUD" list --json
  printf '%s' "$output" | grep -q '"retired":true' || false
}

# ── THE CONTROL: idle feature == absent feature, byte for byte ────────────────────────────────────
@test "CONTROL — with zero declarations every mode is byte-identical to the feature being absent" {
  have_subject
  local_row local-one AAAA-1111-BBBB-2222
  local_row local-two CCCC-3333-DDDD-4444

  for mode in "" "--json" "--names" "--all"; do
    # shellcheck disable=SC2086
    with="$("$SESSIONS" $mode)"
    # shellcheck disable=SC2086
    without="$(CC_CLOUD_BIN="$D/there-is-no-cc-cloud" "$SESSIONS" $mode)"
    [ "$with" = "$without" ] || { echo "mode '$mode' DIFFERS:"; diff <(printf '%s\n' "$without") <(printf '%s\n' "$with"); false; }
  done

  # POSITIVE CONTROL: the comparison above is only evidence if the two DO diverge once a session is
  # declared. Otherwise a lister that ignored cc-cloud entirely would pass this test.
  r="$(bare rem)"
  "$CLOUD" declare --id sess_new --branch feat/a --remote "$r" --repo "" >/dev/null 2>&1
  with="$("$SESSIONS")"
  without="$(CC_CLOUD_BIN="$D/there-is-no-cc-cloud" "$SESSIONS")"
  ! [ "$with" = "$without" ] || { echo "table did NOT change when a session was declared"; false; }
  printf '%s\n' "$with" | grep -q 'sess_new' || false
}

# ── the ADDRESSING views stay local-only ──────────────────────────────────────────────────────────
@test "--json and --names never resolve an off-box id — they are the addressing views" {
  have_subject
  r="$(bare rem)"
  local_row local-one AAAA-1111-BBBB-2222
  "$CLOUD" declare --id sess_cloud --branch feat/a --remote "$r" --repo "" >/dev/null 2>&1

  # cc-notify resolves a friendly name → pane UUID through these. An off-box id has no pane and no
  # local delivery path, so a name that CANNOT be delivered to must never resolve here.
  run "$SESSIONS" --json
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'sess_cloud' || false
  [ "$(printf '%s' "$output" | jq -r 'length')" -eq 1 ]

  run "$SESSIONS" --names
  ! printf '%s' "$output" | grep -q 'sess_cloud' || false
  printf '%s' "$output" | grep -q 'local-one' || false

  # POSITIVE CONTROL: it IS reachable, on the explicit surface, so the exclusion above is a scoping
  # decision and not a broken join.
  run "$SESSIONS" --offbox --names
  [ "$output" = "sess_cloud" ]
}
