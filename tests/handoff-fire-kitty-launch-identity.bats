#!/usr/bin/env bats
# handoff-fire.sh on kitty — the fire's own pane, and a launch that is never reported as not launched
# (FLEET_V2 W7c grown scope, 2026-09-30).
#
# THE INCIDENT. The origin lead ran in kitty window 3 as claude ← expect ← bash ← kitty, so no
# interactive rc block ever exported the synthetic ITERM_SESSION_ID=w0t0p0:3. Two defects followed:
#   1. The fire read its own pane from $ITERM_SESSION_ID alone, so it had NO firing pane: every
#      --split-right went HEADLESS ("anchor probe INCONCLUSIVE"), and with CC_TERM=kitty exported by
#      hand it split pane 10, not pane 3, and dropped its back-channel.
#   2. The `--window` fire at 23:01:47Z printed "could not create a fresh iTerm2 window (--window) —
#      nothing launched" while kitty had created window 47 running the brief (load 195 on 10 cores:
#      `kitty @ launch` outlived kt's 10s single-round-trip bound). The lead re-fired, and two sessions
#      worked one wave in one worktree.
#
# The fake kitty below models kitty on the axis that matters: `launch` CREATES the window (recording
# the --env it was handed, as `kitty @ ls` reports it) BEFORE it answers, and the answer can be slow.
# Every launch case counts creations: a fire that "fails" after creating a window is the defect.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry"
  # Hermetic terminal: this suite may itself run inside a kitty or iTerm2 pane.
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_TERM CC_TERM_KITTY_TO IT2_WRAPPER_NO_KITTY
  unset ITERM_SESSION_ID IT2_KITTY_TIMEOUT_S HANDOFF_SPLIT_TIMEOUT_S HF_SPLIT_TIMEOUT_S
  # A fired pane carries these (bin/it2-kitty --env); a suite run from one must not inherit them.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
  # Non-$HOME seams the real script reads in the dry-run cases: pinned to ABSENT paths in the test dir.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CREATED="$BATS_TEST_TMPDIR/created"; : > "$CREATED"

  FAKE_KITTY="$BATS_TEST_TMPDIR/kitty"
  cat > "$FAKE_KITTY" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = @ ] || exit 64
shift
[ "${1:-}" = --to ] && shift 2
case "${1:-}" in
  launch)
    shift; cmd=""
    while [ $# -gt 0 ]; do
      case "$1" in --env) case "$2" in CC_PANE_CMD=*) cmd="${2#CC_PANE_CMD=}" ;; esac; shift 2 ;; *) shift ;; esac
    done
    [ "${FAKE_LAUNCH:-ok}" = refuse ] && { echo "Error: no matching window" >&2; exit 1; }
    n=$(( $(wc -l < "$CREATED") + 101 ))
    echo "$n" >> "$CREATED"
    [ -n "$cmd" ] && printf '%s' "$cmd" > "$CREATED.$n"
    # garble: the window exists and the answer is lost — what a bound expiring after kitty acted
    # looks like to the caller, without making the case depend on machine load.
    [ "${FAKE_LAUNCH:-ok}" = garble ] && { echo "Error: i/o timeout" >&2; exit 1; }
    sleep "${FAKE_SLEEP:-0}"
    echo "$n" ;;
  ls)
    exec /usr/bin/python3 - "$CREATED" "${FOREIGN_CMD:-}" <<'PY'
import json, os, sys
created, foreign = sys.argv[1], sys.argv[2]
wins = [{"id": 7, "env": {}}]
if foreign:
    wins.append({"id": 55, "env": {"CC_PANE_CMD": foreign}})
for line in open(created).read().split():
    p = created + "." + line
    wins.append({"id": int(line), "env": {"CC_PANE_CMD": open(p).read()} if os.path.exists(p) else {}})
print(json.dumps([{"tabs": [{"windows": wins}]}]))
PY
    ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$FAKE_KITTY"
  export CC_TERM_KITTY="$FAKE_KITTY"

  # The REAL bound machinery and the REAL launch sites, never copies.
  eval "$(sed -n '/^hf_bounded() {/,/^}/p;/^hf_bounded_s() {/,/^}/p;/^in_kitty() {/p;/^kt() {/p;/^kt_launch() {/,/^}/p;/^hf_adopt_split_pane() {/,/^}/p;/^spawn_frontmost() {/,/^}/p;/^as_tab() {/,/^}/p' "$HF")"
  eval "$(grep -E '^HF_(SPLIT_)?TIMEOUT_S=' "$HF")"
  HF_TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)"
  export KITTY_WINDOW_ID=7
  # shellcheck disable=SC2034  # read by the eval'd spawn_frontmost
  FOLLOW=0
  CMD="claude --fire-marker $BATS_TEST_NUMBER-$$"
  # shellcheck disable=SC2034  # read by the eval'd launch sites
  HF_ARGV=(--env "CC_PANE_CMD=$CMD")
  # shellcheck disable=SC2034  # read by the eval'd hf_adopt_split_pane
  HF_ARGV_ACTIVE=1
}

created() { wc -l < "$CREATED" | tr -d ' '; }

@test "THE INCIDENT (--window): an os-window launch slower than one IPC round-trip returns its id — ONE window" {
  # One round-trip scaled 10s -> 1s, kitty answers in 3s: pre-fix kt's bound kills it after the
  # window exists and spawn_frontmost prints nothing, which its caller reports as "nothing launched".
  HF_TIMEOUT_S=1; export FAKE_SLEEP=3
  run spawn_frontmost
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(created)" = 1 ]
  [ "$output" = 101 ]
}

@test "--tab: the same slow launch keeps the OK <id> contract instead of reading as a dead anchor" {
  HF_TIMEOUT_S=1; export FAKE_SLEEP=3
  run as_tab 7
  echo "$output"
  [ "$(created)" = 1 ]
  [ "$output" = "OK 101" ]
}

@test "bg-tab: it2py's kitty launch site goes through kt_launch too" {
  # The third site. Extracting it2py whole needs the kitty suite's fixtures, so this pins the call.
  local x_py
  x_py="$(sed -n '/^it2py() {/,/^}/p' "$HF" | sed 's/#.*//')"
  [ -n "$x_py" ]
  grep -qE 'bnew="\$\(kt_launch --type=tab --keep-focus' <<<"$x_py"
  ! grep -qE 'kt launch' <<<"$x_py" || false
}

@test "the launch bound is the split's, and it exceeds the kitty bound inside it (measured on the call)" {
  local rec="$BATS_TEST_TMPDIR/bound"
  HF_TIMEOUT_BIN="$BATS_TEST_TMPDIR/timeout-rec"
  printf '#!/usr/bin/env bash\necho "$3" > %q\nshift 3\nexec "$@"\n' "$rec" > "$HF_TIMEOUT_BIN"
  chmod +x "$HF_TIMEOUT_BIN"
  run spawn_frontmost
  [ "$status" -eq 0 ]
  local inner
  inner="$(sed -n 's/^TIMEOUT_S="\${IT2_KITTY_TIMEOUT_S:-\([0-9]*\)}"$/\1/p' "$REPO/bin/it2-kitty")"
  [ -n "$inner" ]
  echo "launch bound=$(cat "$rec") inner kitty bound=$inner HF_TIMEOUT_S=$HF_TIMEOUT_S"
  [ "$(cat "$rec")" -gt "$inner" ]
  [ "$(cat "$rec")" = "$HF_SPLIT_TIMEOUT_S" ]
}

@test "a launch that created the window but lost its answer ADOPTS it — never 'nothing launched'" {
  # A generous round-trip bound: this case is about adoption, and its `kitty @ ls` is a python start-up
  # that measured past 10s at load 227 on 10 cores.
  HF_TIMEOUT_S=120
  export FAKE_LAUNCH=garble
  run spawn_frontmost
  echo "$output"
  [ "$(created)" = 1 ]
  [[ "$output" == *"ADOPTED"* ]] || false
  [ "$(printf '%s\n' "$output" | tail -1)" = 101 ]
}

@test "adoption never takes a window running ANOTHER fire's command" {
  HF_TIMEOUT_S=120
  export FAKE_LAUNCH=refuse FOREIGN_CMD="claude --fire-marker someone-else"
  run spawn_frontmost
  echo "$output"
  [ "$(created)" = 0 ]
  [ -z "$output" ]
}

@test "EQUIVALENCE GUARD: a launch kitty REFUSES still prints nothing (the caller's fail-loud signal)" {
  export FAKE_LAUNCH=refuse
  run spawn_frontmost
  [ "$(created)" = 0 ]
  [ -z "$output" ]
  run as_tab 7
  [ "$output" = NOTFOUND ]
}

# ── the fire's own pane ──────────────────────────────────────────────────────────────────────────
# The REAL script, --dry-run only (prints and exits before any side effect). The ancestry verdict is
# fixtured by stubbing $HOME/.claude/bin/cc-in-kitty; kitty itself is the fake above.

fire_dry() { # $1 = cc-in-kitty exit code → the dry run's anchor line
  printf '#!/bin/sh\nexit %s\n' "$1" > "$HOME/.claude/bin/cc-in-kitty"; chmod +x "$HOME/.claude/bin/cc-in-kitty"
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"
  printf 'brief\n' > "$BATS_TEST_TMPDIR/brief.txt"
  run env -u CC_TERM KITTY_WINDOW_ID=3 CC_FIRE_HEADLESS_ANCHOR=off bash "$HF" --dry-run \
      --prompt-file "$BATS_TEST_TMPDIR/brief.txt" --split-right
  echo "$output"
}

@test "THE INCIDENT (--split-right): a genuine kitty pane with no ITERM_SESSION_ID anchors to ITS OWN window" {
  fire_dry 0
  [[ "$output" == *"anchor:   firing session 3 "* ]] || false
  [[ "$output" != *"HEADLESS"* ]] || false
}

@test "…and its default back-channel addresses that pane by its registry name, not 'headless: skipped'" {
  printf '{"name":"lead-pane-3","pane":"3"}\n' > "$HOME/.claude/cc-registry/3.json"
  fire_dry 0
  [[ "$output" == *"notify-back: originator lead-pane-3 "* ]] || false
  [[ "$output" != *"no firing pane to ping"* ]] || false
}

@test "an INHERITED KITTY_WINDOW_ID (kitty is not an ancestor) is not a firing pane" {
  fire_dry 1
  [[ "$output" == *"anchor:   HEADLESS"* ]] || false
  [[ "$output" != *"firing session 3"* ]] || false
}

@test "an UNVERIFIABLE kitty verdict pins nothing and stays headless (fail-closed)" {
  fire_dry 2
  [[ "$output" == *"anchor:   HEADLESS"* ]] || false
}

@test "a genuine iTerm2 pane with a polluted KITTY_WINDOW_ID keeps its iTerm2 session" {
  printf '#!/bin/sh\nexit 1\n' > "$HOME/.claude/bin/cc-in-kitty"; chmod +x "$HOME/.claude/bin/cc-in-kitty"
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"; chmod +x "$HOME/.claude/bin/it2"
  printf 'brief\n' > "$BATS_TEST_TMPDIR/brief.txt"
  run env -u CC_TERM KITTY_WINDOW_ID=3 ITERM_SESSION_ID=w0t0p0:ABCDEF12-0000-4000-8000-000000000000 \
      bash "$HF" --dry-run --prompt-file "$BATS_TEST_TMPDIR/brief.txt" --split-right
  echo "$output"
  [[ "$output" == *"anchor:   firing session ABCDEF12-0000-4000-8000-000000000000 "* ]] || false
}
